import AppKit
import SwiftUI
import ImageIO

@main struct CaptureClockTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        let uncertaintyChecks=try CaptureUncertaintyTests.run()
        let captureSpeechChecks=try CaptureConflictGuidanceTests.run()
        var checks=0
        func check(_ value:Bool,_ reason:String) {checks += 1;precondition(value,reason)}
        func near(_ a:Double,_ b:Double)->Bool {abs(a-b)<0.00001}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("capture-clock-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/IncompleteCapture")
        let sgf=try String(contentsOf:fixture.appendingPathComponent("before.sgf"),encoding:.utf8)
        let incomplete=try JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:fixture.appendingPathComponent("observed.json")))
        var now=ProcessInfo.processInfo.systemUptime
        func feed(_ r:GameRecorder,_ values:[Occupancy],count:Int=5,hand:Bool=false,delay:Double=0,step:Double=0.21)->Double {
            var first=0.0
            for i in 0..<count {
                now += step
                if i==0 {first=now-delay}
                r.consume(.init(readings:values.enumerated().map {.init(row:$0.offset/r.game.boardSize,col:$0.offset%r.game.boardSize,occupancy:$0.element,confidence:1,delta:0)},size:r.game.boardSize,capturedAt:now-delay,handObstructed:hand),now:now)
            }
            return first
        }
        func make(minimum:Int=2,kind:LocalClockSettings.Kind = .absolute,mainSeconds:Int=100)throws->GameRecorder {
            let file=root.appendingPathComponent(UUID().uuidString+".sgf")
            try sgf.write(to:file,atomically:true,encoding:.utf8)
            let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file)
            r.attachClock(.init(kind:kind,mainSeconds:mainSeconds,periodSeconds:15,periods:5,incrementSeconds:5,automaticCaptureMinimum:minimum))
            r.resume();_ = feed(r,DeferredMoveHistory.states(r.positions.last!))
            check(r.clock.running,"Capture fixture did not resume")
            return r
        }
        let r=try make();let plan=AutomaticCapture.find(game:r.game,readings:incomplete,minimum:2)!
        check(plan.captured.count==3 && plan.point==314,"Legal capture differs from actual photograph")
        check(AutomaticCapture.find(game:r.game,readings:incomplete,minimum:5)==nil,"Threshold ignored")
        check(AutomaticCapture.find(game:r.game,readings:incomplete,minimum:0)==nil,"Off ignored")
        var extra=incomplete;extra[0] = .white
        check(AutomaticCapture.find(game:r.game,readings:extra,minimum:2)==nil,"Unrelated stone hidden by capture pause")
        var unclear=incomplete;unclear[314] = .uncertain
        check(AutomaticCapture.find(game:r.game,readings:unclear,minimum:2)==nil,"Uncertain capturing stone paused timing")
        var speech=[String]();r.clock.onResumeAnnouncement={speech.append($0)}
        let baseline=r.clock.engine,first=feed(r,incomplete,count:3)
        check(r.clock.automaticCapturePaused && !r.clock.running && r.moveCount==45,"Capture removal did not pause both clocks without saving")
        check(r.automaticCaptureRemainingPoints == [312],"Automatic capture speech included already removed stones")
        let instruction=r.spokenRecoveryInstruction(orientation:.init(3))
        check(instruction.contains(BoardCoordinates.name(point:312,size:19,orientation:.init(3))) && instruction.contains("clocks restart after verification") && !instruction.contains("Confirm capture"),"Automatic capture guidance requested manual confirmation or omitted the remaining point")
        check(near(r.clock.engine.black.remaining,baseline.black.remaining-(first-baseline.anchor!)),"Recognition delay charged during removal")
        let stopped=r.clock.engine
        _=feed(r,incomplete,count:20,hand:true)
        check(r.clock.engine.black==stopped.black && r.clock.engine.white==stopped.white,"Hand/removal time charged to a player")
        check(speech.isEmpty,"Capture completion announced before completion")
        let clear=feed(r,plan.target,count:5,delay:0.1)
        check(r.moveCount==46 && r.nextPlayer == .white && !r.hasDeferredMoves,"Automatic removal did not record exactly the legal capture")
        check(r.clock.running && !r.clock.automaticCapturePaused,"Verified removal failed to restart clock")
        check(near(r.clock.engine.white.remaining,stopped.white.remaining-(now-clear)),"Opponent was not charged verification delay from clear frame")
        check(speech==["Capture complete. Clocks resumed. White to play."],"Actual resume announcement missing or duplicated")
        r.pause()
        try r.flushStorage()
        let restored=GameRecorder(storage:root);restored.clock.audible=false;try restored.restoreSavedGame(from:r.autosaveURL!)
        check(restored.moveCount==46 && !restored.clock.running,"Restart changed accepted move or resumed clocks")
        // One clear glimpse per removal trip must retain the original boundary.
        // Hand-covered frames establish continuity without confirming a stone.
        let trips=try make(),tripBaseline=trips.clock.engine
        let placed=feed(trips,incomplete,count:1)
        _=feed(trips,extra,count:10,hand:true)
        check(!trips.clock.automaticCapturePaused && trips.moveCount==45,"Covered frames confirmed a tentative capture")
        _=feed(trips,incomplete,count:1)
        _=feed(trips,extra,count:10,hand:true)
        let removed=feed(trips,plan.target,count:5)
        check(trips.moveCount==46 && trips.clock.running && !trips.hasDeferredMoves,"Repeated hand entry lost capture evidence")
        check(near(trips.clock.engine.black.remaining,tripBaseline.black.remaining-(placed-tripBaseline.anchor!)),"Removal trips were charged to the capturing player")
        check(near(trips.clock.engine.white.remaining,tripBaseline.white.remaining-(now-removed)),"Final verification was charged from a later view")
        trips.pause()
        // No second incomplete glimpse: the fully removed target confirms the
        // earlier capture rather than requiring prisoners to reappear.
        let quick=try make(),quickBaseline=quick.clock.engine
        let quickPlaced=feed(quick,incomplete,count:1)
        _=feed(quick,incomplete,count:8,hand:true)
        let quickRemoved=feed(quick,plan.target,count:5)
        check(quick.moveCount==46 && quick.clock.running,"Fully removed target discarded the initial capture glimpse")
        check(near(quick.clock.engine.black.remaining,quickBaseline.black.remaining-(quickPlaced-quickBaseline.anchor!)),"Fully removed target lost the placement timestamp")
        check(near(quick.clock.engine.white.remaining,quickBaseline.white.remaining-(now-quickRemoved)),"Retroactive capture lost the first final-clear timestamp")
        quick.pause()
        let faster=try make()
        _=feed(faster,incomplete,count:4,step:0.101)
        check(!faster.clock.automaticCapturePaused,"10 fps shortened capture identification below 0.4 seconds")
        _=feed(faster,incomplete,count:1,step:0.101)
        check(faster.clock.automaticCapturePaused,"10 fps did not identify a stable capture")
        _=feed(faster,plan.target,count:5,step:0.101)
        check(!faster.clock.running && faster.moveCount==45,"10 fps shortened final verification below 0.8 seconds")
        _=feed(faster,plan.target,count:4,step:0.101)
        check(faster.clock.running && faster.moveCount==46,"10 fps final verification did not finish")
        faster.pause()
        // Clear contradictions start a fresh candidate; a genuine interruption
        // or an explicit pause invalidates all tentative timing evidence.
        for interruption in ["conflict","camera","pause"] {
            let reset=try make(),start=reset.clock.engine
            _=feed(reset,incomplete,count:1)
            if interruption=="conflict" {_=feed(reset,plan.before,count:1)}
            if interruption=="camera" {reset.suspendVision("Camera interrupted",preserveOrder:true)}
            if interruption=="pause" {reset.pause()}
            if interruption != "conflict" {
                if interruption=="pause" {reset.clock.requestResume();reset.resume()}
                _=feed(reset,plan.before,count:5)
            }
            let freshBaseline=reset.clock.engine
            let fresh=feed(reset,incomplete,count:3)
            check(reset.clock.automaticCapturePaused,"Fresh capture after \(interruption) failed")
            check(near(reset.clock.engine.black.remaining,freshBaseline.black.remaining-(fresh-freshBaseline.anchor!)),"\(interruption) reused stale capture evidence")
            check(reset.clock.engine.black.remaining<start.black.remaining,"\(interruption) invented clock time")
            reset.pause()
        }
        // An on-time sighting must freeze for review before hidden removal can
        // produce even a provisional loss. Later confirmation preserves that
        // explicit review; a first post-expiry sighting cannot revive the clock.
        let late=try make(mainSeconds:2)
        let lateStart=late.clock.engine.anchor!
        let onTime=feed(late,incomplete,count:1)
        _=feed(late,incomplete,count:12,hand:true);late.clock.tick(at:now)
        check(late.clock.requiresReview && !late.clock.running && late.clock.engine.expiredBlack==nil,"Pending on-time capture was shown as a loss")
        _=feed(late,plan.target,count:5)
        check(late.moveCount==46 && !late.clock.running && late.clock.requiresReview && late.clock.engine.expiredBlack==nil,"Capture confirmation lost the move or bypassed timing review")
        check(near(late.clock.engine.black.remaining,2-(onTime-lateStart)),"Expiry recovery used an invented pause boundary")
        late.pause()
        let tooLate=try make(mainSeconds:2)
        _=feed(tooLate,incomplete,count:12,hand:true);tooLate.clock.tick(at:now)
        _=feed(tooLate,incomplete,count:4)
        check(!tooLate.clock.automaticCapturePaused && !tooLate.clock.running && tooLate.clock.engine.expiredBlack==true,"Capture first seen after expiry revived the clock")
        tooLate.pause()
        for minimum in [0,5] {
            let disabled=try make(minimum:minimum);_=feed(disabled,incomplete,count:4)
            check(!disabled.clock.automaticCapturePaused,"Nonqualifying capture auto-paused")
            disabled.pause()
        }
        let manual=try make();_=feed(manual,incomplete,count:3);manual.pause()
        let manuallyHeld=manual.clock.engine
        _=feed(manual,plan.target,count:10)
        check(!manual.clock.running && manual.moveCount==45,"Manual pause ignored during capture")
        check(manual.captureProgressRemaining == [] && manual.automaticCaptureRemainingPoints == [],"Paused capture panel and instructions disagree about removed prisoners")
        check(manual.automaticCaptureStatus?.contains("Press Resume") == true,"Paused completed removal still instructs the user to remove stones")
        check(manual.spokenRecoveryInstruction().contains("Press Resume") && !manual.spokenRecoveryInstruction().contains("clocks restart after verification"),"Paused capture speech promises an automatic restart")
        check(manual.clock.engine.black==manuallyHeld.black && manual.clock.engine.white==manuallyHeld.white && manual.clock.automaticCapturePaused,"Read-only removal guidance changed held clock balances or capture ownership")
        _=feed(manual,incomplete,count:2,hand:true)
        check(manual.automaticCaptureRemainingPoints == [],"Covered frame replaced paused removal guidance")
        _=feed(manual,incomplete,count:2,delay:2)
        check(manual.automaticCaptureRemainingPoints == [],"Stale frame replaced paused removal guidance")
        _=feed(manual,incomplete,count:2)
        check(manual.captureProgressRemaining == [312] && manual.automaticCaptureRemainingPoints == [312],"Paused replacement did not update both removal counts")
        check(manual.automaticCaptureStatus?.contains("1 captured stone,") == true,"Paused instruction uses stale removal count or plural")
        var hiddenPrisoner=plan.target;hiddenPrisoner[312] = .uncertain
        _=feed(manual,hiddenPrisoner,count:2)
        check(manual.automaticCaptureRemainingPoints == [312],"Uncertain prisoner was treated as removed while paused")
        check(manual.automaticCaptureStatus?.contains("unclear") == true && manual.spokenRecoveryInstruction().contains("unclear"),"Uncertain captured point was described as a stone still needing removal")
        check(!manual.spokenRecoveryInstruction().contains("Finish removing") && manual.spokenRecoveryInstruction().contains("Press Resume"),"Uncertain capture speech demanded removal or lost manual pause")
        _=feed(manual,plan.target,count:10)
        manual.clock.requestResume();manual.resume();_=feed(manual,plan.target,count:4)
        check(manual.moveCount==45 && !manual.clock.running,"Resume reused paused observations as completion proof")
        _=feed(manual,plan.target,count:1)
        check(manual.moveCount==46 && manual.clock.running,"Explicit resume did not allow capture completion")
        manual.pause()
        let interrupted=try make();_=feed(interrupted,incomplete,count:3);_=feed(interrupted,plan.target,count:4)
        interrupted.suspendVision("Camera disconnected",preserveOrder:true)
        _=feed(interrupted,plan.target,count:4)
        check(!interrupted.clock.running && interrupted.moveCount==45,"Interruption reused stale removal proof")
        _=feed(interrupted,plan.target,count:1)
        check(interrupted.moveCount==46,"Fresh removal proof after interruption failed")
        interrupted.pause()
        let pending=try make();_=feed(pending,incomplete,count:3)
        check(pending.hasUnfinishedReviews && !pending.canScorePosition && !pending.canEdit,"Capture hold allowed export/scoring or history edits")
        let beforeRestart=pending.clock.engine
        try pending.flushStorage()
        let resumed=GameRecorder(storage:root);resumed.clock.audible=false;try resumed.restoreSavedGame(from:pending.autosaveURL!)
        check(resumed.automaticCaptureStatus != nil && resumed.clock.automaticCapturePaused && !resumed.clock.running,"Restart lost the pending capture hold")
        check(resumed.clock.engine.black==beforeRestart.black && resumed.clock.engine.white==beforeRestart.white,"Restart charged removal time")
        _=feed(resumed,plan.target,count:6)
        check(!resumed.clock.running && resumed.moveCount==45,"Restart resumed a capture without user action")
        resumed.clock.requestResume();resumed.resume();_=feed(resumed,plan.target,count:5)
        check(resumed.moveCount==46 && resumed.clock.running,"Restored capture did not complete after Resume")
        resumed.pause()
        let fallback=try make();_=feed(fallback,incomplete,count:3)
        let reviewID=fallback.prepareAutomaticCaptureReview()
        check(reviewID != nil && fallback.pendingCaptureReview?.id==reviewID && fallback.automaticCaptureStatus==nil,"Automatic capture had no explicit review escape")
        check(!fallback.clock.automaticCapturePaused && !fallback.clock.running && fallback.clock.requiresReview,"Manual capture handoff lost the timing review gate")
        _=feed(fallback,plan.target,count:5)
        check(fallback.confirmCaptureReview(reviewID!,now:now)==nil && fallback.moveCount==46,"Explicit capture fallback could not save")
        try fallback.flushStorage()
        let fallbackRestart=GameRecorder(storage:root);fallbackRestart.clock.audible=false;try fallbackRestart.restoreSavedGame(from:fallback.autosaveURL!)
        check(fallbackRestart.automaticCaptureStatus==nil && !fallbackRestart.clock.running,"Finished fallback restored an obsolete automatic hold")
        let ending=try make();_=feed(ending,incomplete,count:3);ending.finish()
        check(ending.state == .paused && ending.hasUnfinishedReviews && ending.pendingCaptureReview != nil,"Ending during removal lost the capture review")
        check(!ending.clock.running && !ending.clock.automaticCapturePaused,"Ending left an automatic restart armed")
        let cancelled=try make();_=feed(cancelled,incomplete,count:3);_=feed(cancelled,plan.before,count:5)
        check(cancelled.clock.requiresReview && !cancelled.clock.running && cancelled.moveCount==45,"Abandoned capture silently invented clock time")
        let legacy=try JSONDecoder().decode(LocalClockSettings.self,from:Data(#"{"kind":"absolute","mainSeconds":100,"periodSeconds":30,"periods":5,"incrementSeconds":0,"maximumSeconds":1200,"stonesPerPeriod":25}"#.utf8))
        check(legacy.capturePauseMinimum==2,"Legacy setup did not use two-stone default")
        check(try JSONDecoder().decode(LocalClockSettings.self,from:JSONEncoder().encode(LocalClockSettings(automaticCaptureMinimum:0))).capturePauseMinimum==0,"Off setting lost across restart")
        // Explicit clear-frame timestamps must beat later analysis/confirmation time.
        let timed=GameRecorder(storage:nil);timed.clock.audible=false
        timed.start(size:9,now:now,clockSettings:.init(kind:.absolute,mainSeconds:100))
        var board=Array(repeating:Occupancy.empty,count:81);_=feed(timed,board)
        let initial=timed.clock.engine
        board[20] = .black;_=feed(timed,board,count:4,hand:true)
        check(timed.moveCount==0 && timed.clock.running,"Hand-over-board frame completed a move")
        let boundary=feed(timed,board,count:12,delay:0.1)
        check(timed.moveCount==1,"Hand-clear legal move was not saved")
        check(near(timed.clock.moves.last!.before.black.remaining,initial.black.remaining-(boundary-initial.anchor!)),"Clock press used recognition time instead of hand-clear frame")
        timed.pause()
        var timing=ClearBoardTiming()
        var o=BoardObservation(readings:board.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:1,handObstructed:false)
        timing.observe(o,now:1.1);timing.reset();o.capturedAt=2;timing.observe(o,now:2.1)
        check(timing.firstMatch(target:board,changed:[20],after:0)==2,"Explicit interruption retained an old completion boundary")
        o.capturedAt=10;timing.observe(o,now:10.1)
        check(timing.firstMatch(target:board,changed:[20],after:0)==10,"Camera gap retained a stale boundary")
        var empty=board;empty[20] = .empty
        timing.observe(.init(readings:empty.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:10.2,handObstructed:false),now:10.3)
        o.capturedAt=10.4;timing.observe(o,now:10.5)
        check(timing.firstMatch(target:board,changed:[20],after:0)==10.4,"Reappearing stone reused a withdrawn placement time")
        for kind in LocalClockSettings.Kind.allCases where kind != .none {
            let clock=LocalGameClock();clock.audible=false
            clock.configure(.init(kind:kind,mainSeconds:[.byoyomi,.canadian].contains(kind) ? 0:100,periodSeconds:15,periods:5,incrementSeconds:5,stonesPerPeriod:2),blackToPlay:true)
            clock.ready(at:0);clock.tick(at:8)
            check(clock.beginAutomaticCapture(at:5,now:8),"Capture pause failed in \(kind)")
            let held=clock.engine.black
            clock.tick(at:30)
            check(clock.engine.black==held,"Removal consumed overtime in \(kind)")
            clock.recordMove(number:1,black:true,at:35)
            let completed=clock.engine.black
            clock.recordMove(number:1,black:true,at:35)
            check(clock.engine.black==completed,"Capture applied a second bonus/reset in \(kind)")
            clock.finishAutomaticCapture(at:30,now:35)
            check(clock.running && near(clock.engine.white.remaining,kind == .absolute || kind == .fischer ? 95:10),"Opponent delay incorrect in \(kind)")
            if kind == .byoyomi {check(clock.engine.black.periods==5 && clock.engine.black.remaining==15,"Capture consumed a byoyomi period")}
            if kind == .canadian {check(clock.engine.black.stones==1,"Capture counted prisoners as overtime moves")}
            clock.pause(at:35)
        }
        for stones in [1,2] {
            var game=SGFGame();game.boardSize=9;game.initialPlayer = .black
            game.setup=[(.white,1,1),(.black,1,0),(.black,0,1),(.black,1,2)]
            if stones==2 {game.setup += [(.white,2,1),(.black,2,0),(.black,2,2)]}
            let player=SGFPlayer();player.load(game:game)
            var seen=DeferredMoveHistory.states(player.board);seen[9+stones+1] = .black
            let candidate=AutomaticCapture.find(game:game,readings:seen,minimum:2)
            check((candidate != nil)==(stones==2),"Two-stone default has the wrong boundary")
        }
        // Exercise every configured boundary through recorder + clock, including
        // completion and the following move; these are synthetic legal positions.
        for minimum in [0,2,3,5] {
            for stones in Set([max(1,minimum-1),max(2,minimum)]).sorted() {
                let blacks=[BoardPosition(1,0)] + (1...stones).flatMap{[BoardPosition(0,$0),BoardPosition(2,$0)]}
                let whites=(1...stones).map{BoardPosition(1,$0)} + (0...stones).map{BoardPosition(8,$0)}
                let sequence=zip(blacks,whites).map {black,white in
                    ";B[\(SGFCoordinates.toSGF(x:black.col,y:black.row))];W[\(SGFCoordinates.toSGF(x:white.col,y:white.row))]"
                }.joined()
                let file=root.appendingPathComponent("threshold-\(minimum)-\(stones).sgf")
                try "(;FF[4]GM[1]AP[PhysicalGo:test]SZ[9]RU[Japanese]\(sequence))".write(to:file,atomically:true,encoding:.utf8)
                let boundary=GameRecorder(storage:root);boundary.clock.audible=false
                try boundary.restoreSavedGame(from:file)
                boundary.attachClock(.init(kind:.fischer,mainSeconds:100,incrementSeconds:2,maximumSeconds:200,automaticCaptureMinimum:minimum))
                let prefix=boundary.moveCount
                boundary.resume();_=feed(boundary,DeferredMoveHistory.states(boundary.positions.last!))
                var seen=DeferredMoveHistory.states(boundary.positions.last!);seen[9+stones+1] = .black
                let trial=SGFPlayer();trial.load(game:boundary.game);trial.seek(to:boundary.moveCount)
                check(trial.tryPlayMove(color:.black,x:stones+1,y:1)==nil,"Threshold fixture illegal")
                let target=DeferredMoveHistory.states(trial.board)
                let prisoners=Set((1...stones).map{9+$0})
                let qualifying=minimum>0 && stones>=minimum
                let initialClock=boundary.clock.engine
                let placed=feed(boundary,seen,count:4)
                check(boundary.clock.automaticCapturePaused==qualifying,"Capture threshold \(minimum) misclassified \(stones) stones")
                if !qualifying {check(boundary.clock.running && !boundary.clock.requiresReview,"A below-threshold removal introduced a hold")}
                let issue=RecordingClarity.issues(recorder:boundary).first{$0.kind == .capture}
                check(issue != nil && issue?.hold==(qualifying ? .capture:nil),"Removal guidance was missing or changed clock policy")
                if (minimum==0 || minimum==2) && stones==2 {
                    let clockBeforeInspection=boundary.clock.engine
                    let host=NSHostingView(rootView:AutomaticCaptureInspection(recorder:boundary,orientation:.init(0),onReview:{}).background(Color(nsColor:.windowBackgroundColor)))
                    let preview=NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:340),styleMask:[.titled],backing:.buffered,defer:false)
                    preview.appearance=NSAppearance(named:.darkAqua);host.appearance=preview.appearance
                    preview.contentView=host;preview.orderFront(nil)
                    RunLoop.main.run(until:Date().addingTimeInterval(0.15));host.layoutSubtreeIfNeeded()
                    let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
                    host.cacheDisplay(in:host.bounds,to:bitmap)
                    let output=try TestArtifacts.directory("live-position-issues")
                    try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("capture-\(minimum).png"))
                    preview.orderOut(nil)
                    check(boundary.clock.engine==clockBeforeInspection,"Native capture inspection changed timing")
                }
                let identity=issue!.id
                let inspectionClock=boundary.clock.engine
                let action:RecordingClarity.Action=qualifying ? .automaticCapture:.captureProgress
                check(prisoners.union([9+stones+1]).allSatisfy{RecordingClarity.action(at:$0,recorder:boundary)==action},"Capture inspection changed route across its intersections")
                if stones>1 {
                    var partial=seen;partial[prisoners.sorted().first!] = .empty
                    _=feed(boundary,partial,count:4)
                    check(RecordingClarity.issues(recorder:boundary).first{$0.kind == .capture}?.id==identity,"Partial removal split capture identity")
                    check(boundary.captureProgressRemaining?.count==stones-1,"Capture inspector did not report remaining removals")
                    if qualifying {check(boundary.clock.engine.black==inspectionClock.black && boundary.clock.engine.white==inspectionClock.white,"Partial removal charged time")}
                }
                let completed=feed(boundary,target,count:10)
                boundary.clock.tick(at:now)
                check(boundary.moveCount==prefix+1 && boundary.clock.moves.count==1 && boundary.clock.provisionalMoves.isEmpty,"Capture completion duplicated or lost its timed turn")
                let firstClock=boundary.clock.moves[0]
                check(near(firstClock.after.black.remaining,initialClock.black.remaining-(placed-initialClock.anchor!)+2),"Capture charged removal time or duplicated its increment")
                let nextBoundary=qualifying ? completed:placed
                check(near(boundary.clock.engine.white.remaining,initialClock.white.remaining-(now-nextBoundary)),"Capture policy changed the following player's completion boundary")
                var following=target;following[80] = .white
                _=feed(boundary,following,count:10)
                check(boundary.moveCount==prefix+2 && boundary.clock.moves.count==2 && boundary.clock.moves[0].after==firstClock.after,"Following move changed the capture clock event")
                boundary.pause()
            }
        }
        // Real images exercise the detector independently of simulated timing signals.
        struct CameraFixture:Decodable {let calibration:BoardCalibration}
        let handRoot=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CoveredBorder")
        let handMeta=try JSONDecoder().decode(CameraFixture.self,from:Data(contentsOf:handRoot.appendingPathComponent("metadata.json")))
        func photo(_ url:URL)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!}
        check(BoardHandDetector.obstructed(image:photo(handRoot.appendingPathComponent("000011.png")),calibration:handMeta.calibration)==true,"Actual hand over the board was not detected")
        check(BoardHandDetector.obstructed(image:photo(handRoot.appendingPathComponent("000001.png")),calibration:handMeta.calibration)==false,"Clear photographed board was classified as a hand")
        // Opening reviews uses an attached sheet, including the photo-editor handoff.
        let settings=UserDefaults(suiteName:"CaptureClockTests."+UUID().uuidString)!
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:root,settings:settings,diagnosticRoot:root.appendingPathComponent("diagnostics"))
        model.recorder.clock.audible=false
        let file=root.appendingPathComponent("sheet.sgf");try sgf.write(to:file,atomically:true,encoding:.utf8)
        let game=SGFGame.from(tree:try SGFParser.parse(text:sgf))
        var history=DeferredMoveHistory();history.size=19;history.baseMove=45;history.anchorSignature=RecordingIdentity.signature(for:game)
        let section=DeferredMoveHistory.Section(reviewNumber:1,before:plan.before,after:incomplete,reason:"Capture",firstSeen:now,confirmedAt:now)
        history.sections=[section]
        try JSONEncoder().encode(history).write(to:file.deletingPathExtension().appendingPathExtension("reviews.json"))
        try model.recorder.restoreSavedGame(from:file)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:900),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:ExperimentView(model:model));window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until:Date().addingTimeInterval(0.3))
        model.reviewPresentation.open(recorder:model.recorder,id:section.id,orientation:.init(0))
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        check(window.attachedSheet != nil,"Review editor escaped the application window")
        _=feed(model.recorder,plan.target,count:5)
        check(model.recorder.captureRemovalVerified(model.recorder.pendingCaptureReview!,now:now),"Clear review fixture did not verify")
        model.recorder.noteHandObstruction()
        check(model.recorder.handOverBoard,"Hand obstruction was not reflected in photo-review eligibility")
        model.recorder.noteHandClear()
        check(!model.recorder.handOverBoard,"Clearing a hand required move ingestion while a photo editor was open")
        check(!model.recorder.captureRemovalVerified(model.recorder.pendingCaptureReview!,now:now),"A hand left stale review confirmation enabled")
        model.reviewPresentation.close()
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        check(window.attachedSheet==nil && model.recorder.activeReviewID==nil,"Review sheet did not dismiss cleanly")
        window.close()
        try runLocalClockTests()
        print("PASS: \(checks + uncertaintyChecks + captureSpeechChecks) automatic capture and hand-clear timing checks")
    }
}
