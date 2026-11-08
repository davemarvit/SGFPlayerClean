import AppKit
import SwiftUI

@main struct ReviewQueueTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        checks += try PhysicalReviewTests.run()
        func check(_ value:Bool,_ text:String) {checks += 1;precondition(value,text)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("review-queue-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var time=ProcessInfo.processInfo.systemUptime
        func view(_ board:BoardSnapshot)->BoardObservation {
            BoardObservation(readings:DeferredMoveHistory.states(board).enumerated().map{p,v in
                .init(row:p/board.size,col:p%board.size,occupancy:v,confidence:1,delta:0)
            },size:board.size)
        }
        func feed(_ r:GameRecorder,_ board:BoardSnapshot,frames:Int=7) {
            for _ in 0..<frames {time += 0.21;r.consume(view(board),now:time)}
        }
        func fresh(timed:Bool=false)->GameRecorder {
            let r=GameRecorder(storage:root);r.clock.audible=false
            r.start(size:9,clockSettings:timed ? .init():.init(kind:.none));r.pause();return r
        }
        func play(_ player:SGFPlayer,_ points:[BoardPosition]) {
            for p in points {check(player.tryPlayMove(color:player.turn,x:p.col,y:p.row)==nil,"Bad fixture move")}
        }
        func proposal(_ r:GameRecorder,_ section:DeferredMoveHistory.Section,_ points:[BoardPosition])->MoveRecoveryDraft {
            let context=r.contextForReview(section.id)!
            var draft=MoveRecoveryDraft(game:context.game,observation:nil)
            for p in points {check(draft.add(p,checkCameraColor:false)==nil,"Review proposal rejected")}
            return draft
        }
        // Known chronology held for an ambiguous placement must stay in the
        // existing tracker. The 0.90 fit deliberately cannot certify uniqueness.
        let placement=fresh();placement.resume();feed(placement,placement.positions[0])
        var placementColors=Array(repeating:Occupancy.empty,count:81)
        for (point,color,count) in [(10,Occupancy.black,3),(20,.white,8),(30,.black,80)] {
            placementColors[point]=color
            for _ in 0..<count {
                time += 0.21
                placement.consume(BoardObservation(readings:placementColors.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,
                    footprints:[.init(row:1,col:1,center:.init(x:1.36,y:1),radiusCol:0.46,radiusRow:0.46,quality:0.90)]),now:time)
            }
        }
        check(placement.moveCount==0 && !placement.hasDeferredMoves && placement.pendingConfidence.compactMap(\.point)==[10,20,30],"Known chronology was replaced with a review gap")

        let r=fresh(timed:true)
        r.manualMove(at:BoardPosition(0,1))
        _=r.confirmClockReview(black:r.clock.engine.black,white:r.clock.engine.white,resume:false)
        let actual=SGFPlayer();actual.load(game:r.game);actual.seek(to:r.moveCount)
        // Match the clock-and-recording Resume control after clock correction.
        r.clock.requestResume();r.resume();feed(r,actual.board)
        let orders=[[BoardPosition(0,0),BoardPosition(6,6),BoardPosition(7,7)],
                    [BoardPosition(1,7),BoardPosition(1,6),BoardPosition(1,5)],
                    [BoardPosition(7,1),BoardPosition(6,1),BoardPosition(5,1)]]
        let later=[BoardPosition(1,0),BoardPosition(4,4),BoardPosition(3,3)]
        for i in 0..<3 {
            play(actual,orders[i]);feed(r,actual.board)
            check(r.reviewHistory.reviews.count==i+1,"Missing review section \(i+1): \(r.status)")
            check(r.moveCount==1 && r.hasDeferredMoves,"Gap leaked into accepted SGF")
            check(r.lastInterpretedPoint==nil,"Unknown order marked an invented last move")
            play(actual,[later[i]]);feed(r,actual.board)
            check(r.reviewHistory.retainedMoveCount==i+1,"Later ordered move was lost")
            check(r.lastInterpretedPoint==later[i].row*9+later[i].col,"Latest observed move marker remained on the saved prefix")
            check(r.tentativeNextPlayer==actual.turn,"Pass control named the saved prefix's player instead of the observed next player")
        }
        check(actual.board.grid[0][0]==nil,"Capture fixture failed")
        check(r.state == .recording && r.clock.running && !r.clock.requiresReview,"An order-only gap stopped live recording or the clocks")
        r.clock.pauseOnInterruption=false;r.suspendVision("Camera interrupted")
        check(r.clock.running,"Unresolved chronology overrode the optional camera interruption policy")
        check(r.hasUnfinishedReviews && r.canPass,"Later known turn should allow an explicit pass while export stays gated")
        let oldClock=(r.clock.engine.black.remaining,r.clock.engine.white.remaining)
        check(r.recordedMoveCount(for:.black)==4 && r.recordedMoveCount(for:.white)==0 && r.moveCountsNeedReview,"Unknown gaps invented move counts or lost later observed plays")
        let before=r.sgf(),file=r.autosaveURL!
        r.pause()
        let reviews=r.reviewHistory.reviews
        // The third section can be resolved before the first two.
        check(r.resolveReview(reviews[2].id,draft:proposal(r,reviews[2],orders[2]),overrideCamera:false)==nil,"Out-of-order review failed")
        check(r.reviewHistory.unresolved==2 && r.sgf()==before,"Partial review changed accepted prefix")
        let restored=GameRecorder(storage:root);restored.clock.audible=false
        try restored.restoreSavedGame(from:file)
        check(restored.reviewHistory.reviews.count==3 && restored.reviewHistory.unresolved==2 && restored.reviewHistory.retainedMoveCount==6,"Review queue failed restart")
        check(restored.reviewHistory.reviews[2].moves != nil && restored.state == .paused,"Resolved review failed restart")
        restored.resume();feed(restored,actual.board)
        check(restored.moveCount==1 && restored.reviewHistory.sections.count==6,"Resuming duplicated or discarded sections")
        // A brief false reading must not become a new review or move.
        let ghost=SGFPlayer();var ghostGame=DeferredMoveHistory.positionGame(DeferredMoveHistory.states(actual.board),size:9,rules:"Japanese",turn:.white)
        ghostGame.initialPlayer = .white;ghost.load(game:ghostGame);play(ghost,[BoardPosition(8,8)])
        feed(restored,ghost.board,frames:2);feed(restored,actual.board)
        check(restored.reviewHistory.sections.count==6,"Brief camera noise became a section")
        restored.pause()
        check(restored.resolveReview(reviews[0].id,draft:proposal(restored,reviews[0],orders[0]),overrideCamera:false)==nil,"First review failed")
        check(restored.reviewHistory.unresolved==1 && restored.moveCount==1,"Unresolved gap was finalized")
        check(restored.resolveReview(reviews[1].id,draft:proposal(restored,reviews[1],orders[1]),overrideCamera:false)==nil,"Final review failed: \(restored.status)")
        check(restored.moveCount==13 && !restored.hasUnfinishedReviews,"All-green queue did not finalize")
        check(restored.positions.last==actual.board && restored.nextPlayer==actual.turn,"Replayed board/turn differs from observed game")
        check(restored.reviewHistory.reviews.allSatisfy{$0.committed && $0.moves != nil},"Green review history disappeared")
        check(restored.clock.engine.black.remaining==oldClock.0 && restored.clock.engine.white.remaining==oldClock.1,"Recovered history invented clock time")
        check(!restored.clock.requiresReview && !restored.clock.running,"Historical resolution created an unnecessary clock-review gate")
        check(restored.sgf().components(separatedBy:"Entered manually.").count==11,"Camera-observed suffix was mislabeled manual")
        check(restored.recordedMoveCount(for:.black)==7 && restored.recordedMoveCount(for:.white)==6 && !restored.moveCountsNeedReview,"Finalization duplicated counts or captures removed played moves")
        restored.seek(0)
        check(restored.recordedMoveCount(for:.black)==7 && restored.recordedMoveCount(for:.white)==6,"Browsing changed clock move counts")
        restored.returnToLatest()
        let again=GameRecorder(storage:root);again.clock.audible=false;try again.restoreSavedGame(from:file)
        check(again.moveCount==13 && again.reviewHistory.reviews.count==3 && !again.hasDeferredMoves,"Finalized queue failed restart")
        check(again.finalizeReviews() != nil && again.moveCount==13,"Finalization duplicated moves")

        // Full-history ko validation must reopen a later locally plausible move.
        let ko=fresh()
        for p in [BoardPosition(1,0),BoardPosition(1,1),BoardPosition(0,1),BoardPosition(2,0),BoardPosition(1,2),BoardPosition(2,2),BoardPosition(8,8),BoardPosition(3,1)] {ko.manualMove(at:p)}
        let koActual=SGFPlayer();koActual.load(game:ko.game);koActual.seek(to:ko.moveCount)
        ko.resume();feed(ko,koActual.board)
        let koGap=[BoardPosition(8,7),BoardPosition(8,6),BoardPosition(2,1)]
        play(koActual,koGap);feed(ko,koActual.board)
        check(ko.reviewHistory.unresolved==1,"Ko gap missing")
        let local=SGFPlayer();local.load(game:DeferredMoveHistory.positionGame(DeferredMoveHistory.states(koActual.board),size:9,rules:"Japanese",turn:.white))
        play(local,[BoardPosition(1,1)]);feed(ko,local.board)
        check(ko.reviewHistory.retainedMoveCount==1,"Provisional later ko observation not retained")
        ko.pause();let koSection=ko.reviewHistory.reviews[0]
        let koError=ko.resolveReview(koSection.id,draft:proposal(ko,koSection,koGap),overrideCamera:false)
        check(koError?.contains("Ko") == true && ko.moveCount==8 && ko.reviewHistory.unresolved==1 && ko.reviewHistory.reviews.count==2,"Illegal later move was silently finalized")

        // Explicit passes after a known later move must survive and end capture,
        // with final SGF still waiting for the earlier review.
        let passing=fresh();passing.manualMove(at:BoardPosition(0,1))
        let passActual=SGFPlayer();passActual.load(game:passing.game);passActual.seek(to:1)
        passing.resume();feed(passing,passActual.board)
        play(passActual,orders[0]);feed(passing,passActual.board)
        check(passing.canPass && passing.liveNextPlayer == .black,"Color counts failed to establish the next player independently of order")
        play(passActual,[later[0]]);feed(passing,passActual.board)
        check(passing.canPass,"Known later turn could not pass")
        passing.pass();passing.pass()
        check(passing.state == .finished && passing.reviewHistory.endRequested && passing.reviewHistory.retainedMoveCount==3,"Two passes lost pending history or failed to stop recording")
        let passSection=passing.reviewHistory.reviews[0]
        check(passing.resolveReview(passSection.id,draft:proposal(passing,passSection,orders[0]),overrideCamera:false)==nil && passing.state == .finished && passing.moveCount==7,"Reviewed ended game was not finalized")

        check(passing.recordedMoveCount(for:.black)==4 && passing.recordedMoveCount(for:.white)==3,"Passes missing from player move counts")
        // A failed review save must not allow final SGF to outrun its recovery journal.
        let unsaved=fresh();unsaved.manualMove(at:BoardPosition(0,1))
        let unsavedActual=SGFPlayer();unsavedActual.load(game:unsaved.game);unsavedActual.seek(to:1)
        unsaved.resume();feed(unsaved,unsavedActual.board);play(unsavedActual,orders[0]);feed(unsaved,unsavedActual.board);unsaved.pause()
        let unsavedSection=unsaved.reviewHistory.reviews[0]
        let blockedFile=unsaved.autosaveURL!.deletingPathExtension().appendingPathExtension("reviews.json")
        try FileManager.default.removeItem(at:blockedFile)
        try FileManager.default.createDirectory(at:blockedFile,withIntermediateDirectories:false)
        check(unsaved.resolveReview(unsavedSection.id,draft:proposal(unsaved,unsavedSection,orders[0]),overrideCamera:false) != nil,"Failed journal write was hidden")
        check(unsaved.finalizeReviews() != nil && unsaved.moveCount==1,"SGF finalized despite an unsaved review journal")
        try FileManager.default.removeItem(at:blockedFile);unsaved.retryReviewSave()
        check(unsaved.finalizeReviews()==nil && unsaved.moveCount==4,"Successful save retry could not finalize")

        // Interrupted SGF/sidecar finalization must reopen without duplication.
        var interrupted=restored.reviewHistory
        interrupted.anchorSignature=r.reviewHistory.anchorSignature;interrupted.baseMove=1
        for i in interrupted.sections.indices {interrupted.sections[i].committed=false;interrupted.sections[i].savedStart=nil}
        try JSONEncoder().encode(interrupted).write(to:file.deletingPathExtension().appendingPathExtension("reviews.json"),options:.atomic)
        var stalePending=try JSONSerialization.jsonObject(with:Data(contentsOf:file.deletingPathExtension().appendingPathExtension("pending.json"))) as! [String:Any]
        stalePending["signature"]=r.reviewHistory.anchorSignature!
        try JSONSerialization.data(withJSONObject:stalePending).write(to:file.deletingPathExtension().appendingPathExtension("pending.json"),options:.atomic)
        let reconciled=GameRecorder(storage:root);reconciled.clock.audible=false;try reconciled.restoreSavedGame(from:file)
        check(reconciled.moveCount==13 && !reconciled.hasDeferredMoves,"Interrupted finalization duplicated/blocked the saved suffix")

        // Corrupt recovery metadata must block final export without being overwritten.
        let corrupt=file.deletingPathExtension().appendingPathExtension("reviews.json")
        let validData=try Data(contentsOf:corrupt)
        try Data("broken".utf8).write(to:corrupt,options:.atomic)
        let damaged=GameRecorder(storage:root);damaged.clock.audible=false
        do {try damaged.restoreSavedGame(from:file);check(false,"Corrupt review file accepted")}
        catch {check(damaged.hasUnfinishedReviews,"Corrupt review file silently unblocked export")}
        damaged.retryReviewSave()
        check((try? Data(contentsOf:corrupt))==Data("broken".utf8),"Retry overwrote damaged recovery file")
        try validData.write(to:corrupt,options:.atomic);damaged.retryReviewSave()
        check(!damaged.hasUnfinishedReviews && damaged.reviewHistory.reviews.count==3,"Repaired review file could not be recovered")

        // A missed white stone must be explained precisely; it must never be
        // silently accepted or hidden under ghost stones from the camera layer.
        var selected=Array(repeating:Occupancy.empty,count:361)
        selected[173] = .black;selected[231] = .white;selected[193] = .black
        var camera=selected;camera[231] = .empty
        let differences=ReviewComparison.differences(selected:DeferredMoveHistory.board(selected,size:19),camera:camera)
        check(differences.count==1 && differences[0].point==231 && differences[0].selected == .white && differences[0].camera == .empty,"Missing white stone explanation failed")
        for (turns,label) in [(0,"D7"),(1,"G16"),(2,"Q13"),(3,"N4")] {
            check(differences[0].coordinate(size:19,orientation:BoardOrientation(turns))==label,"Review coordinate orientation failed")
        }
        check(ReviewComparison.differences(selected:DeferredMoveHistory.board(selected,size:19),camera:selected).isEmpty,"Matching sequence incorrectly marked")
        camera[231] = .black
        check(ReviewComparison.differences(selected:DeferredMoveHistory.board(selected,size:19),camera:camera)[0].camera == .black,"Wrong-color discrepancy lost")
        camera[231] = .white;camera[100] = .black
        check(ReviewComparison.differences(selected:DeferredMoveHistory.board(selected,size:19),camera:camera)[0].selected == .empty,"Extra camera stone discrepancy lost")
        let reviewWindow=ReviewWindow()
        reviewWindow.open(recorder:r,id:reviews[0].id,orientation:BoardOrientation(1))
        let independent=reviewWindow.window!
        check(independent.sheetParent==nil && independent.isMovable && independent.styleMask.contains(.resizable),"Review still attached or immovable")
        reviewWindow.open(recorder:r,id:reviews[1].id,orientation:BoardOrientation(1))
        check(reviewWindow.window === independent,"Opening another review discarded unsubmitted selections")
        reviewWindow.close();check(reviewWindow.window==nil,"Review window did not close")

        // Optional read-only session reproduction uses an isolated copy, never the live game.
        if let fixture=ProcessInfo.processInfo.environment["PHYSICAL_GO_REVIEW_FIXTURE"] {
            let source=URL(fileURLWithPath:fixture)
            let target=root.appendingPathComponent(source.lastPathComponent)
            for suffix in ["sgf","pending.json","reviews.json","clock.json"] {
                let original=source.deletingPathExtension().appendingPathExtension(suffix)
                if FileManager.default.fileExists(atPath:original.path) {
                    try FileManager.default.copyItem(at:original,to:target.deletingPathExtension().appendingPathExtension(suffix))
                }
            }
            let actual=GameRecorder(storage:root);actual.clock.audible=false;try actual.restoreSavedGame(from:target)
            let section=actual.reviewHistory.reviews.first{$0.reviewNumber==4}!
            let draft=proposal(actual,section,[BoardPosition(9,2),BoardPosition(12,3),BoardPosition(10,3)])
            let diff=ReviewComparison.differences(selected:draft.board,camera:section.after)
            check(diff.count==1 && diff[0].coordinate(size:19,orientation:BoardOrientation(3))=="N4","Actual review mismatch differs from N4")
            check(actual.resolveReview(section.id,draft:draft,overrideCamera:false) != nil,"Camera disagreement silently accepted")
            check(actual.resolveReview(section.id,draft:draft,overrideCamera:true)==nil && !actual.hasUnfinishedReviews && actual.moveCount==53,"Authoritative N4 correction failed final replay")
            print("Actual Review 4: only N4 differs; B K3, W N4, B L4 is legal and finalizes 53 moves with explicit camera override.")
        }

        if let replayPath=ProcessInfo.processInfo.environment["PHYSICAL_GO_RESUME_REPLAY"],
           let gamePath=ProcessInfo.processInfo.environment["PHYSICAL_GO_RESUME_GAME"] {
            struct Frame:Decodable {let frame:Int;let readings:[IntersectionReading];let shapes:[StoneFootprint]}
            let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:URL(fileURLWithPath:replayPath)))
            let original=URL(fileURLWithPath:gamePath),target=root.appendingPathComponent("resume.sgf")
            for suffix in ["sgf","clock.json","pending.json","reviews.json"] {
                try FileManager.default.copyItem(at:original.deletingPathExtension().appendingPathExtension(suffix),to:target.deletingPathExtension().appendingPathExtension(suffix))
            }
            let resumed=GameRecorder(storage:root);resumed.clock.audible=false;try resumed.restoreSavedGame(from:target)
            let correctBlack=resumed.clock.engine.black,correctWhite=resumed.clock.engine.white
            let saved=resumed.moveCount,black=resumed.clock.engine.black.remaining
            resumed.clock.requestResume();resumed.resume()
            var now=ProcessInfo.processInfo.systemUptime
            for frame in frames.sorted(by:{$0.frame<$1.frame}) {
                now+=0.55
                let observation=BoardObservation(readings:frame.readings,size:19,footprints:frame.shapes)
                resumed.consume(observation,now:now)
                check(resumed.moveCount==saved && resumed.pendingMoveCount==0 && !resumed.hasDeferredMoves,"Unchanged bright wood became a move or review")
                check(resumed.nextPlayer == .white && resumed.tentativeNextPlayer==nil,"False white detection changed the turn")
            }
            check(resumed.synchronized && resumed.clock.running,"Actual resumed board failed to synchronize")
            check(!resumed.clock.engine.blackToPlay && resumed.clock.engine.black.remaining==black,"Resume charged the wrong player's clock")
            check(!resumed.needsAttention,"Actual resumed board still produced a stop warning")
            resumed.pause()
            if let repairPath=ProcessInfo.processInfo.environment["PHYSICAL_GO_GLARE_REPAIR"],
               let outputPath=ProcessInfo.processInfo.environment["PHYSICAL_GO_GLARE_REPAIR_OUTPUT"] {
                let input=URL(fileURLWithPath:repairPath),repairFile=root.appendingPathComponent("repair.sgf")
                for suffix in ["sgf","clock.json","pending.json","reviews.json","observations.jsonl"] {
                    try FileManager.default.copyItem(at:input.deletingPathExtension().appendingPathExtension(suffix),to:repairFile.deletingPathExtension().appendingPathExtension(suffix))
                }
                let repair=GameRecorder(storage:root);repair.clock.audible=false;try repair.restoreSavedGame(from:repairFile)
                check(repair.moveCount==saved,"Live game changed since false detections")
                for section in repair.reviewHistory.sections.filter({!$0.committed}) {
                    let draft=MoveRecoveryDraft(game:repair.contextForReview(section.id)!.game,observation:nil)
                    check(repair.resolveReview(section.id,draft:draft,overrideCamera:true)==nil,"Confirmed no-move correction failed")
                }
                check(repair.moveCount==saved && !repair.hasDeferredMoves,"False review entries remain")
                check(repair.confirmClockReview(black:correctBlack,white:correctWhite,resume:false),"Failed to undo false-detection clock charge")
                check(repair.nextPlayer == .white && repair.clock.engine.black==correctBlack && repair.clock.engine.white==correctWhite,"Wrong repaired turn/time")
                let output=URL(fileURLWithPath:outputPath)
                try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                for suffix in ["sgf","clock.json","pending.json","reviews.json","observations.jsonl"] {
                    try FileManager.default.copyItem(at:repairFile.deletingPathExtension().appendingPathExtension(suffix),to:output.appendingPathComponent(input.deletingPathExtension().appendingPathExtension(suffix).lastPathComponent))
                }
            }
            print("Actual glare clip: \(frames.count) frames, no false moves/reviews, White clock resumes.")
        }

        let output=try TestArtifacts.directory("physical-review-queue")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func render<V:View>(_ value:V,_ name:String,width:CGFloat,height:CGFloat)throws {
            let host=NSHostingView(rootView:value.background(Color(nsColor:.windowBackgroundColor)))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled],backing:.buffered,defer:false)
            window.appearance=NSAppearance(named:.darkAqua);host.appearance=window.appearance
            window.backgroundColor = .windowBackgroundColor;window.contentView=host;window.orderFront(nil)
            RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
            window.orderOut(nil)
        }
        try render(HStack(alignment:.top){RecordedBoard(recorder:r,orientation:BoardOrientation(1),showsLivePosition:true,onPoint:{_ in}).frame(width:520,height:520);ReviewQueueRail(recorder:r,onReview:{_ in})}.padding(),"three-reviews",width:730,height:570)
        try render(ReviewSectionView(recorder:r,id:reviews[0].id,orientation:BoardOrientation(1)),"section-editor",width:960,height:820)
        try render(LocalClockPanel(clock:restored.clock,recorder:restored),"clock-move-counts",width:1100,height:660)
        try render(ReviewQueueRail(recorder:restored,onReview:{_ in}).padding(),"all-green",width:210,height:500)
        print("PASS: \(checks) review-queue checks; three gaps, later ordered moves, capture, out-of-order resolution, restart, noise rejection, ko reopening, clock preservation, interrupted-finalization recovery and native review views")
    }
}
