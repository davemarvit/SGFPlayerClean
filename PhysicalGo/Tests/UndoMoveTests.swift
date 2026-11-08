import AppKit
import SwiftUI

@main struct UndoMoveTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.accessory)
        try runLocalClockTests()
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;precondition(ok,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("undo-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/IncompleteCapture/before.sgf")
        let file=root.appendingPathComponent("game.sgf")
        try FileManager.default.copyItem(at:fixture,to:file)
        let r=GameRecorder(storage:root);r.clock.audible=false
        try r.restoreSavedGame(from:file);r.attachClock(.init(kind:.absolute,mainSeconds:300))
        r.manualMove(at:BoardPosition(16,10))
        check(r.moveCount==46,"Capture fixture failed")
        let plan=UndoMovePlan(recorder:r)!
        check(plan.remove==[314] && plan.restore==[294,312,313],"Capture undo failed to explain every restored stone")
        check(plan.color == .black && plan.point==BoardPosition(16,10),"Undo selected a different move")
        r.pause();r.returnToLatest()
        let session=UndoMoveSession(plan:plan)
        let defaults=UserDefaults(suiteName:"undo-ui-"+UUID().uuidString)!
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,
            referenceArchive:nil,recordingStorage:root,settings:defaults,diagnosticRoot:root.appendingPathComponent("diagnostics"))
        model.recorder.clock.audible=false
        let host=NSHostingView(rootView:UndoMoveView(model:model,recorder:r,plan:plan,onClose:{}))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:940,height:790),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;window.orderFront(nil)
        RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:TestArtifacts.file("undo-move/capture-preview.png"))
        window.orderOut(nil)
        var now=ProcessInfo.processInfo.systemUptime
        func observation(_ cells:[Occupancy],blocked:Bool=false)->BoardObservation {
            .init(readings:cells.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,lightingBlocked:blocked)
        }
        func feed(_ cells:[Occupancy],count:Int=5) {
            for _ in 0..<count {now += 0.21;session.observe(observation(cells),now:now)}
        }
        let old=DeferredMoveHistory.states(r.positions.last!),target=DeferredMoveHistory.states(plan.target)
        check(session.confirm(r,now:now) != nil && r.moveCount==46,"Undo committed without restored board")
        feed(old);check(!session.verified(now:now),"Still-present undone stone passed verification")
        check(session.verificationStatus(now:now) == .different([294,312,313,314]),"Undo did not explain mismatched intersections")
        var partial=target;partial[312] = .empty;feed(partial)
        check(!session.verified(now:now),"Missing restored prisoner passed verification")
        partial=target;partial[314] = .uncertain;feed(partial)
        check(!session.verified(now:now),"Unseen removal passed verification")
        check(session.verificationStatus(now:now) == .unclear([314]),"Undo did not identify the obscured affected point")
        partial=target;partial[0] = .white;feed(partial)
        check(!session.verified(now:now),"Unrelated added stone passed verification")
        feed(target,count:4);check(!session.verified(now:now),"Undo accepted too few camera frames")
        feed(target,count:1);check(session.verified(now:now),"Restored position did not verify")
        session.invalidate()
        for _ in 0..<10 {session.observeLive(observation(target),frameTime:now,isLive:true)}
        check(!session.verified(now:now),"Repeated redraw of one frame verified an undo")
        feed(target)
        session.observeLive(observation(target),frameTime:now,isLive:false)
        check(!session.verified(now:now),"Frozen or stopped camera retained undo evidence")
        feed(target)
        session.observeLive(observation(target),frameTime:nil,isLive:true)
        check(!session.verified(now:now),"Missing live frame timestamp retained undo evidence")
        feed(target)
        check(!session.verified(now:now+2),"Stale board verification allowed undo")
        session.observe(observation(target,blocked:true),now:now+0.01)
        check(!session.verified(now:now+0.01),"Blocked view retained verification")
        partial=target
        for p in [4,5,6,7,8,9,15,16,17,18,30,31,32,33,34,35,36,37,38,39,40,41,42,45,46] {partial[p] = .uncertain}
        feed(partial);check(session.verified(now:now),"Limited uncertainty erased unchanged history")
        let black=r.clock.engine.black,white=r.clock.engine.white
        check(session.confirm(r,now:now)==nil,"Verified undo failed")
        check(r.moveCount==45 && r.nextPlayer == .black && r.state == .paused && !r.clock.running,"Undo changed turn or resumed play")
        check(DeferredMoveHistory.states(r.positions.last!)==target,"Undo lost a captured stone")
        check(r.clock.engine.black==black && r.clock.engine.white==white,"Unknown press history invented clock time")
        check(session.confirm(r,now:now) != nil && r.moveCount==45,"Repeated confirmation undid another move")
        check(try FileManager.default.contentsOfDirectory(atPath:root.path).contains{$0.contains("before-undo")},"Undo lost original SGF backup")
        let reopened=GameRecorder(storage:root);reopened.clock.audible=false;try reopened.restoreSavedGame(from:r.autosaveURL!)
        check(reopened.moveCount==45 && reopened.nextPlayer == .black,"Undo failed restart")
        reopened.pass()
        let passPlan=UndoMovePlan(recorder:reopened)!
        check(passPlan.point==nil && passPlan.remove.isEmpty && passPlan.restore.isEmpty,"Pass undo invented stone changes")
        reopened.manualMove(at:BoardPosition(0,0))
        check(reopened.undo(expectedSignature:passPlan.signature) != nil,"Stale undo preview edited a different latest move")

        let failureFile=root.appendingPathComponent("save-failure.sgf")
        try FileManager.default.copyItem(at:fixture,to:failureFile)
        let failure=GameRecorder(storage:root);failure.clock.audible=false;try failure.restoreSavedGame(from:failureFile)
        failure.attachClock(.init(kind:.absolute,mainSeconds:300));failure.manualMove(at:BoardPosition(16,10))
        let failureSession=UndoMoveSession(plan:UndoMovePlan(recorder:failure)!)
        for _ in 0..<5 {now += 0.21;failureSession.observe(observation(target),now:now)}
        let clockFile=failureFile.deletingPathExtension().appendingPathExtension("clock.json")
        try FileManager.default.removeItem(at:clockFile)
        try FileManager.default.createDirectory(at:clockFile,withIntermediateDirectories:false)
        check(failureSession.confirm(failure,now:now) != nil && failureSession.applied && failure.moveCount==45,"Save failure was presented as a completed undo")
        check(failureSession.confirm(failure,now:now) != nil && failure.moveCount==45,"Save retry performed a second undo")
        try FileManager.default.removeItem(at:clockFile)
        check(failureSession.retrySave(failure)==nil && failure.moveCount==45,"Undo save retry did not preserve one edit")

        // The user's actual path: resolve the incomplete capture, then undo it.
        let reviewedFile=root.appendingPathComponent("reviewed-capture.sgf")
        try FileManager.default.copyItem(at:fixture,to:reviewedFile)
        let reviewedGame=SGFGame.from(tree:try SGFParser.parse(text:String(contentsOf:fixture,encoding:.utf8)))
        let observed=try JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:fixture.deletingLastPathComponent().appendingPathComponent("observed.json")))
        var history=DeferredMoveHistory();history.size=19;history.baseMove=45
        history.anchorSignature=RecordingIdentity.signature(for:reviewedGame)
        history.sections=[.init(reviewNumber:2,before:target,after:observed,reason:"Incomplete capture",firstSeen:now,confirmedAt:now)]
        let reviewID=history.sections[0].id
        try JSONEncoder().encode(history).write(to:reviewedFile.deletingPathExtension().appendingPathExtension("reviews.json"))
        let reviewed=GameRecorder(storage:root);reviewed.clock.audible=false;try reviewed.restoreSavedGame(from:reviewedFile)
        reviewed.attachClock(.init(kind:.absolute,mainSeconds:300))
        for _ in 0..<5 {now += 0.21;reviewed.consume(observation(old),now:now)}
        check(reviewed.confirmCaptureReview(reviewID,now:now)==nil && reviewed.clock.baseMove==46,"Capture-review fixture failed to establish clock checkpoint")
        let reviewedUndo=UndoMoveSession(plan:UndoMovePlan(recorder:reviewed)!)
        for _ in 0..<5 {now += 0.21;reviewedUndo.observe(observation(target),now:now)}
        let reviewedClock=reviewed.clock.engine
        check(reviewedUndo.confirm(reviewed,now:now)==nil && reviewed.clock.baseMove==45,"Undo left clock checkpoint beyond saved history")
        check(reviewed.clock.requiresReview && reviewed.clock.engine.black==reviewedClock.black && reviewed.clock.engine.white==reviewedClock.white,"Review undo invented prior press times")
        check(reviewed.reviewHistory.sections[0].before==target && reviewed.reviewHistory.sections[0].after==observed && reviewed.reviewHistory.sections[0].undoneMoveNumbers==[46],"Undo lost original capture review evidence or audit marker")
        let reload=GameRecorder(storage:root);reload.clock.audible=false;try reload.restoreSavedGame(from:reviewedFile)
        check(reload.moveCount==45 && !reload.hasUnfinishedReviews && reload.clock.saveError==nil && reload.clock.requiresReview,"Reviewed capture undo failed clean restart")
        check(reload.finalizeReviews() != nil && reload.moveCount==45,"Re-finalization resurrected undone review move")
        let backups=try FileManager.default.contentsOfDirectory(atPath:root.path).filter{$0.hasPrefix("reviewed-capture.before-undo-")}
        check(backups.contains{$0.hasSuffix(".reviews.json")} && backups.contains{$0.hasSuffix(".clock.json")},"Undo backup omitted review or clock history")
        reload.manualMove(at:BoardPosition(16,10))
        check(reload.undo(expectedSignature:RecordingIdentity.signature(for:reload.game))==nil && reload.reviewHistory.sections[0].undoneMoveNumbers==[46],"Undoing a replacement duplicated the original review audit marker")

        let dir=root.appendingPathComponent("bridge");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let controller=PhysicalUndoController(directory:dir)
        let online=PhysicalOnlineBoard(directory:dir,announceOpponent:{},announceCorrection:{})
        online.enabled=true
        var board=[String](repeating:"empty",count:361);board[10]="black"
        var state=PhysicalUndoState(available:true,moveNumber:1,requesting:false,requestedMove:nil,requester:nil)
        var version=1
        func publish(ready:Bool=true,token:String="session",stale:Bool=false,includeUndo:Bool=true) throws {
            var value:[String:Any]=["time":Date().timeIntervalSince1970-(stale ? 10:0),"token":token,"game":7,"version":version,
                "ready":ready,"size":19,"cells":board,"color":"black","myTurn":true]
            if includeUndo {value["undo"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(state))}
            try JSONSerialization.data(withJSONObject:value).write(to:dir.appendingPathComponent("state.json"),options:.atomic)
        }
        try publish();controller.refresh()
        let dialogContext=controller.context
        version=2;try publish()
        check(!controller.send(.request,expectedContext:dialogContext),"An open confirmation dialog requested undo on a newer position")
        version=1;try publish();controller.refresh()
        check(controller.send(.request),"Online undo request failed")
        let request=try JSONDecoder().decode(PhysicalUndoRequest.self,from:Data(contentsOf:dir.appendingPathComponent("undo.json")))
        check(request.matches(token:"session",game:7,version:1,state:state),"Fresh request failed receiver validation")
        check(!controller.send(.request),"Duplicate click rewrote the request")
        check(!request.matches(token:"other",game:7,version:1,state:state),"Old bridge session accepted")
        check(!request.matches(token:"session",game:8,version:1,state:state),"Another game accepted")
        check(!request.matches(token:"session",game:7,version:2,state:state),"Stale board revision accepted")
        check(!request.matches(token:"session",game:7,version:1,state:state,now:request.time+4),"Expired request accepted")
        state.requesting=true;try publish(ready:false)
        try JSONEncoder().encode(PhysicalUndoReply(id:request.id,message:"Sent",accepted:true)).write(to:dir.appendingPathComponent("undo-result.json"))
        controller.refresh();check(!controller.awaitingCommand && controller.state?.pending==true,"Undo acknowledgement lost server pending state")
        check(controller.send(.cancel),"Outgoing undo could not be canceled")
        state.requesting=false;state.requestedMove=1;state.requester="Opponent"
        try publish(token:"incoming");controller.refresh()
        check(controller.send(.accept),"Incoming undo could not be accepted")
        let accept=try JSONDecoder().decode(PhysicalUndoRequest.self,from:Data(contentsOf:dir.appendingPathComponent("undo.json")))
        check(accept.matches(token:"incoming",game:7,version:1,state:state),"Incoming request failed validation")
        state.requestedMove=2
        check(!accept.matches(token:"incoming",game:7,version:1,state:state),"Changed incoming request accepted")
        try publish(token:"decline");controller.refresh();check(controller.send(.cancel),"Incoming undo could not be declined")
        try publish(stale:true);controller.refresh();check(controller.state==nil,"Disconnected controls remained actionable")
        try publish(includeUndo:false);controller.refresh();check(controller.state==nil,"Old server fabricated undo support")

        state=PhysicalUndoState(available:true,moveNumber:1,requesting:false,requestedMove:nil,requester:nil)
        try publish();online.consume(observation(board.map{Occupancy(rawValue:$0)!}),now:1)
        state.requesting=true;try publish(ready:false)
        var next=board;next[20]="black"
        for i in 0..<8 {online.consume(observation(next.map{Occupancy(rawValue:$0)!}),now:2+Double(i)*0.21)}
        check(!FileManager.default.fileExists(atPath:dir.appendingPathComponent("move.json").path),"Move sent during takeback negotiation")
        state.requesting=false;state.moveNumber=0;version=2;board[10]="empty";try publish()
        var notRestored=board;notRestored[10]="black"
        for i in 0..<8 {online.consume(observation(notRestored.map{Occupancy(rawValue:$0)!}),now:5+Double(i)*0.21)}
        check(!FileManager.default.fileExists(atPath:dir.appendingPathComponent("move.json").path),"Undone stone was automatically replayed")
        check(online.placementIssue?.requiresSynchronization==true,"Accepted undo omitted board synchronization guidance")
        online.consume(observation(board.map{Occupancy(rawValue:$0)!}),now:8)
        next=board;next[20]="black"
        for i in 0..<8 {online.consume(observation(next.map{Occupancy(rawValue:$0)!}),now:9+Double(i)*0.21)}
        check(FileManager.default.fileExists(atPath:dir.appendingPathComponent("move.json").path),"Play did not recover after undo restoration")
        print("PASS: \(checks) undo checks: capture/pass previews, fresh restoration, clocks, restart, stale/double confirmation, online request/accept/decline/cancel, revision/session guards and no replay before physical synchronization")
    }
}
