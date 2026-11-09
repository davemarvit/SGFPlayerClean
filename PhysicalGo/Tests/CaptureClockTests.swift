import AppKit
import SwiftUI
import ImageIO

@main struct CaptureClockTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
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
        func feed(_ r:GameRecorder,_ values:[Occupancy],count:Int=5,hand:Bool=false,delay:Double=0)->Double {
            var first=0.0
            for i in 0..<count {
                now += 0.21
                if i==0 {first=now-delay}
                r.consume(.init(readings:values.enumerated().map {.init(row:$0.offset/r.game.boardSize,col:$0.offset%r.game.boardSize,occupancy:$0.element,confidence:1,delta:0)},size:r.game.boardSize,capturedAt:now-delay,handObstructed:hand),now:now)
            }
            return first
        }
        func make(minimum:Int=2,kind:LocalClockSettings.Kind = .absolute)throws->GameRecorder {
            let file=root.appendingPathComponent(UUID().uuidString+".sgf")
            try sgf.write(to:file,atomically:true,encoding:.utf8)
            let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file)
            r.attachClock(.init(kind:kind,mainSeconds:100,periodSeconds:15,periods:5,incrementSeconds:5,automaticCaptureMinimum:minimum))
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
        let restored=GameRecorder(storage:root);restored.clock.audible=false;try restored.restoreSavedGame(from:r.autosaveURL!)
        check(restored.moveCount==46 && !restored.clock.running,"Restart changed accepted move or resumed clocks")
        for minimum in [0,5] {
            let disabled=try make(minimum:minimum);_=feed(disabled,incomplete,count:4)
            check(!disabled.clock.automaticCapturePaused,"Nonqualifying capture auto-paused")
            disabled.pause()
        }
        let manual=try make();_=feed(manual,incomplete,count:3);manual.pause();_=feed(manual,plan.target,count:10)
        check(!manual.clock.running && manual.moveCount==45,"Manual pause ignored during capture")
        manual.clock.requestResume();manual.resume();_=feed(manual,plan.target,count:5)
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
        check(timing.firstMatch(target:board,changed:[20],after:0)==2,"Hand reentry retained an old completion boundary")
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
        print("PASS: \(checks) automatic capture and hand-clear timing checks")
    }
}
