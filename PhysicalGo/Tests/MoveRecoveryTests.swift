import AppKit
import SwiftUI

@main struct MoveRecoveryTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;precondition(condition,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("recovery-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        func recorder(timed:Bool=false)->GameRecorder {
            let r=GameRecorder(storage:root);r.clock.audible=false
            r.start(size:9,clockSettings:timed ? .init():.init(kind:.none));r.pause()
            r.clock.pause();return r
        }
        let r=recorder(timed:true),original=r.sgf()
        try r.flushStorage()
        let file=r.autosaveURL!,originalBytes=try Data(contentsOf:file)
        let observed=BoardObservation(readings:(0..<81).map {i in
            .init(row:i/9,col:i%9,occupancy:i==10 ? .white:.empty,confidence:1,delta:0)
        },size:9)
        var draft=MoveRecoveryDraft(recorder:r,observation:observed)
        check(draft.add(BoardPosition(1,1)) != nil && draft.moves.isEmpty,"Wrong camera color accepted silently")
        check(draft.add(BoardPosition(1,1),checkCameraColor:false)==nil,"Explicit color correction rejected")
        check(draft.add(BoardPosition(1,1)) != nil && draft.moves.count==1,"Occupied intersection duplicated")
        draft.undo();check(draft.moves.isEmpty && draft.nextPlayer == .black,"Undo did not restore turn")
        check(draft.add(BoardPosition(-1,0)) != nil,"Off-board selection accepted")
        check(draft.add(BoardPosition(0,1))==nil,"First capture move rejected")
        check(draft.add(BoardPosition(0,0))==nil,"Second capture move rejected")
        check(draft.add(BoardPosition(1,0))==nil,"Capturing move rejected")
        check(draft.board.grid[0][0]==nil,"Draft did not model capture")
        check(r.sgf()==original && (try? Data(contentsOf:file))==originalBytes && r.moveCount==0,"Draft changed saved record")
        let black=r.clock.engine.black.remaining,white=r.clock.engine.white.remaining
        let emptyDraft=MoveRecoveryDraft(recorder:r,observation:nil)
        check(r.approveRecovery(emptyDraft) != nil && r.sgf()==original,"Empty approval changed game")
        check(r.approveRecovery(draft)==nil,"Valid capture sequence rejected")
        check(r.moveCount==3 && r.nextPlayer == .white && r.positions.last!.grid[0][0]==nil,"Approved sequence incorrect")
        check(r.state == .paused && r.clock.requiresReview && !r.clock.running,"Recovery bypassed clock review")
        check(r.clock.engine.black.remaining==black && r.clock.engine.white.remaining==white,"Recovery invented move timing")
        check(r.pendingMoveCount==0 && r.sgf().components(separatedBy:"Entered manually.").count==4,"Manual provenance or pending reset missing")
        let saved=r.sgf()
        check(r.approveRecovery(draft) != nil && r.sgf()==saved,"Repeated approval duplicated moves")
        let reopened=GameRecorder(storage:root);reopened.clock.audible=false
        try reopened.restoreSavedGame(from:file)
        check(reopened.moveCount==3 && reopened.positions.last==r.positions.last && reopened.clock.requiresReview,"Recovered record failed round trip")
        check(r.confirmClockReview(black:r.clock.engine.black,white:r.clock.engine.white,resume:true),"Clock confirmation failed")
        check(!r.clock.running && !r.synchronized,"Resume skipped physical-board verification")
        r.pause()

        // A draft made against an older record cannot overwrite a newer move.
        let staleRecorder=recorder();var stale=MoveRecoveryDraft(recorder:staleRecorder,observation:nil)
        _=stale.add(BoardPosition(3,3));staleRecorder.manualMove(at:BoardPosition(2,2))
        check(staleRecorder.approveRecovery(stale) != nil && staleRecorder.moveCount==1,"Stale draft overwrote game")
        // Persist failure must leave in-memory moves untouched as well.
        let failure=recorder();var failing=MoveRecoveryDraft(recorder:failure,observation:nil);_=failing.add(BoardPosition(4,4))
        try failure.flushStorage()
        let failureURL=failure.autosaveURL!;try FileManager.default.removeItem(at:failureURL)
        try FileManager.default.createDirectory(at:failureURL,withIntermediateDirectories:false)
        check(failure.approveRecovery(failing) != nil && failure.moveCount==0 && failure.nextPlayer == .black,"Save failure partially applied sequence")
        // Two passes finish rather than silently resume a completed game.
        let end=recorder();var passes=MoveRecoveryDraft(recorder:end,observation:nil)
        check(passes.add(nil)==nil && passes.add(nil)==nil && passes.add(BoardPosition(1,1)) != nil,"Moves allowed after two passes")
        check(end.approveRecovery(passes)==nil && end.state == .finished,"Two recovered passes failed to finish game")
        // Immediate ko is still rejected by the same engine used during play.
        let ko=recorder()
        for point in [BoardPosition(1,0),BoardPosition(1,1),BoardPosition(0,1),BoardPosition(2,0),BoardPosition(1,2),BoardPosition(2,2),BoardPosition(8,8),BoardPosition(3,1)] {ko.manualMove(at:point)}
        check(ko.moveCount==8,"Ko fixture failed")
        var koDraft=MoveRecoveryDraft(recorder:ko,observation:nil)
        check(koDraft.add(BoardPosition(2,1))==nil,"Legal ko capture rejected")
        check(koDraft.add(BoardPosition(1,1))?.contains("Ko") == true && koDraft.moves.count==1,"Illegal ko recapture accepted")

        let historical=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/MoveRecovery/before-recovery.sgf")
        var recoveredBoards=[BoardSnapshot]()
        for (index,order) in [[31,15,32],[32,15,31]].enumerated() {
            let copy=root.appendingPathComponent("historical-\(index).sgf")
            try FileManager.default.copyItem(at:historical,to:copy)
            let replay=GameRecorder(storage:root);replay.clock.audible=false;try replay.restoreSavedGame(from:copy)
            let prefix=replay.game.moves.map {"\($0.0):\($0.1!.0),\($0.1!.1)"}
            var historyDraft=MoveRecoveryDraft(recorder:replay,observation:nil)
            for point in order {check(historyDraft.add(BoardPosition(point/19,point%19))==nil,"Historical proposal rejected")}
            check(replay.approveRecovery(historyDraft)==nil && replay.moveCount==32,"Historical recovery failed")
            check(replay.game.moves.prefix(29).map {"\($0.0):\($0.1!.0),\($0.1!.1)"}==prefix,"Historical prefix changed")
            check(replay.positions.last!.grid[1][15]==nil,"Historical capture was not applied")
            recoveredBoards.append(replay.positions.last!)
        }
        check(recoveredBoards[0]==recoveredBoards[1],"Two legal orders should explain the same current board")

        // A paused camera-only detection is actionable even when neither player
        // has a placement ambiguity. It must enter game recovery, not photo labels.
        let ghosts=recorder()
        var ghostColors=Array(repeating:Occupancy.empty,count:81)
        ghostColors[10] = .black;ghostColors[20] = .white
        let ghostView=BoardObservation(readings:ghostColors.enumerated().map{
            .init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)
        },size:9)
        var tick=ProcessInfo.processInfo.systemUptime
        for _ in 0..<8 {tick+=0.21;ghosts.consume(ghostView,now:tick)}
        check(ghosts.placementAmbiguities.isEmpty && ghosts.adjustmentIssues.keys.sorted()==[10,20],"Zero-ambiguity camera-only scenario did not reproduce")
        check(RecordingClarity.action(at:10,recorder:ghosts) == .missedMoves(point:10) && RecordingClarity.action(at:20,recorder:ghosts) == .missedMoves(point:20),"Ghost click opened labels or an unrelated placement editor")
        check(RecordingClarity.explanation(recorder:ghosts,observation:ghostView,orientation:.init(0))?.contains("translucent")==true,"Camera-only explanation still claims placement ambiguity")
        let retained=GameRecorder(storage:root);retained.clock.audible=false
        retained.start(size:9,now:tick,clockSettings:.init())
        var colors=Array(repeating:Occupancy.empty,count:81)
        func feedRetained(_ count:Int) {for _ in 0..<count {
            tick+=0.21
            retained.consume(BoardObservation(readings:colors.enumerated().map{
                .init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)
            },size:9,footprints:colors[10] == .black ? [.init(row:1,col:1,center:.init(x:1,y:1.36),radiusCol:0.46,radiusRow:0.46,quality:0.90)]:[]),now:tick)
        }}
        feedRetained(6)
        colors[10] = .black;feedRetained(3)
        colors[20] = .white;feedRetained(8)
        colors[30] = .black;feedRetained(8)
        retained.pause()
        check(retained.pendingConfidence.compactMap(\.point)==[10,20,30],"Retained chronology setup failed")
        check(RecordingClarity.action(at:10,recorder:retained) == .pendingPlacement(number:1),"Pending placement did not route to location confirmation")
        check(retained.clock.correct(black:retained.clock.engine.black,white:retained.clock.engine.white,blackToPlay:false,moveCount:0,at:tick),"Clock review setup failed")
        retained.clock.acknowledgePendingTurns([[10],[20],[30]],firstBlack:true,moveCount:0)
        check(retained.clock.provisionalMoves.count==3,"Reviewed pending clock turns were not retained")
        let pendingSGF=retained.sgf(),pendingClock=retained.clock.engine
        var seeded=MoveRecoveryDraft(recorder:retained,observation:nil)
        check(seeded.moves==[BoardPosition(1,1),BoardPosition(2,2),BoardPosition(3,3)] && seeded.retainedMoveCount==3,"Recovery forgot earlier retained moves")
        var dropping=seeded;dropping.clear();_=dropping.add(BoardPosition(3,3))
        check(retained.approveRecovery(dropping)?.contains("discard or reorder") == true,"Approving the latest stone silently discarded its earlier pending moves")
        check(retained.sgf()==pendingSGF && retained.pendingMoveCount==3 && retained.clock.engine.black==pendingClock.black && retained.clock.engine.white==pendingClock.white,"Rejected recovery changed history or clocks")
        check(seeded.add(BoardPosition(4,4))==nil && retained.approveRecovery(seeded)==nil,"Safe continuation could not be approved")
        check(retained.game.moves.compactMap{$0.1.map{$0.1*9+$0.0}}==[10,20,30,40] && retained.pendingMoveCount==0,"Recovery reordered retained moves")
        check(retained.clock.requiresReview && !retained.clock.running && retained.clock.engine.black==pendingClock.black && retained.clock.engine.white==pendingClock.white,"Recovery invented clock timing")
        check(retained.clock.provisionalMoves.isEmpty && retained.clock.moves.map(\.number)==[1,2,3],"Existing provisional clock turns were dropped or left attached to old move numbers")
        try retained.flushStorage()
        let roundTrip=GameRecorder(storage:nil);try roundTrip.restoreSavedGame(from:retained.autosaveURL!)
        check(roundTrip.moveCount==4 && roundTrip.clock.saveError==nil && roundTrip.clock.requiresReview && roundTrip.clock.engine.black==pendingClock.black && roundTrip.clock.engine.white==pendingClock.white,"Approved recovery and existing clock events failed to reopen together")
        check(RecordingClarity.action(at:10,recorder:retained) == .recordedPlacement(number:1),"Saved placement did not route to historical correction")

        let output=try TestArtifacts.directory("physical-move-recovery")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let ui=GameRecorder(storage:root);ui.clock.audible=false;ui.start(size:19);ui.pause();var proposed=MoveRecoveryDraft(recorder:ui,observation:nil)
        _=proposed.add(BoardPosition(2,2));_=proposed.add(BoardPosition(5,6));_=proposed.add(BoardPosition(6,3))
        for rotation in 0..<4 {
            let host=NSHostingView(rootView:MoveRecoveryView(recorder:ui,orientation:BoardOrientation(rotation),draft:proposed,onApproved:{}).background(Color(nsColor:.windowBackgroundColor)))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:820),styleMask:[.titled],backing:.buffered,defer:false)
            window.appearance=NSAppearance(named:.darkAqua);window.backgroundColor = .windowBackgroundColor;host.appearance=window.appearance;window.contentView=host;window.orderFront(nil)
            RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("ordered-rotation-\(rotation).png"))
            window.orderOut(nil)
        }
        check(ui.moveCount==0 && ui.state == .paused,"Rendering proposal changed game")
        print("PASS: \(checks) recovery checks; captures, ko, clock review, stale/double approval, save failure, SGF round trip, and four rotated native views")
    }
}
