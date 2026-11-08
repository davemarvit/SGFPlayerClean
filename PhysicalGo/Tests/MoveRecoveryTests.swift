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
