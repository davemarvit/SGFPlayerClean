import AppKit
import SwiftUI

/// Reproduces the user's saved pending turn in private temporary copies only.
@main struct EndPendingGameTests {
    @MainActor static func main()throws {
        NSApplication.shared.setActivationPolicy(.accessory);setbuf(stdout,nil)
        let source=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("end-pending-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;if !ok {print("FAIL: \(message)")};precondition(ok,message)}
        func encoded<T:Encodable>(_ value:T)throws->Data {
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];return try encoder.encode(value)
        }
        func copied(_ name:String)throws->URL {
            let folder=root.appendingPathComponent(name)
            try FileManager.default.copyItem(at:source,to:folder)
            return try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).first{$0.pathExtension=="sgf"}!
        }
        let file=try copied("normal"),r=GameRecorder(storage:file.deletingLastPathComponent(),deferredLocations:true)
        r.clock.audible=false;try r.restoreSavedGame(from:file)
        check(r.moveCount==1 && r.pendingMoveCount==1 && r.clock.provisionalMoves.count==1,"Incident did not restore its unverified white turn")
        let sgf=r.sgf(),sequence=r.tentativeHistory.tentativeSequences,ids=r.stoneLedger!.records.map(\.id)
        let engine=r.clock.engine,receipts=try encoded(r.clock.moves+r.clock.provisionalMoves),review=r.clock.requiresReview
        r.finish()
        check(r.state == .paused && r.status.contains("Not finished") && r.canEndKeepingPending,"Original End Game failure or new alternative unavailable")
        r.finish(retainingPending:true)
        check(r.state == .finished && r.playFlow == .finished && !r.clock.running,"Explicit end did not stop the session")
        check(r.pendingMoveCount==1 && r.tentativeHistory.tentativeSequences==sequence && r.stoneLedger?.records.map(\.id)==ids,"Ending discarded pending chronology or identity")
        check(try r.sgf()==sgf && r.clock.engine==engine && encoded(r.clock.moves+r.clock.provisionalMoves)==receipts,"Ending changed moves, balances or original timing")
        check(r.hasUnfinishedReviews && !r.canScorePosition,"Ending certified an unresolved position for scoring/export")
        check(r.resume() == .unavailable,"An ended game resumed its clock")
        for i in 0..<8 {
            let t=ProcessInfo.processInfo.systemUptime+Double(i)*0.21
            r.consume(.init(readings:(0..<361).map{.init(row:$0/19,col:$0%19,occupancy:.empty,confidence:1,delta:0)},size:19,capturedAt:t,handObstructed:false),now:t)
        }
        r.finish(retainingPending:true)
        check(r.state == .finished && r.pendingMoveCount==1 && r.clock.engine==engine,"Later images or repeated End changed the retained game")
        check(r.flushForExit(),"Ended session could not be saved on exit")
        let restored=GameRecorder(storage:file.deletingLastPathComponent(),deferredLocations:true);restored.clock.audible=false
        try restored.restoreSavedGame(from:file)
        check(restored.state == .finished && restored.pendingMoveCount==1 && restored.hasUnfinishedReviews,"Restart lost the ended state or unverified move")
        check(restored.tentativeHistory.tentativeSequences==sequence && restored.stoneLedger?.records.map(\.id)==ids,"Restart discarded retained position choices or identities")
        check(try restored.clock.engine==engine && encoded(restored.clock.moves+restored.clock.provisionalMoves)==receipts,"Restart changed original clock receipts")
        restored.reopenUnfinishedReview()
        check(restored.state == .paused && !restored.clock.running && restored.clock.requiresReview==review,"Opening review restarted or bypassed clock review")
        check(restored.resume() == .clockReview && !restored.clock.running,"Review reopening bypassed the existing timing hold")
        restored.finish(retainingPending:true)
        restored.start(size:9,startPaused:true)
        check(restored.autosaveURL != file && restored.awaitingFirstStart && !restored.clock.running,"Ended game prevented a separate new game")
        let old=GameRecorder(storage:file.deletingLastPathComponent(),deferredLocations:true);old.clock.audible=false
        try old.restoreSavedGame(from:file)
        check(old.state == .finished && old.pendingMoveCount==1 && old.sgf()==sgf,"Starting another game overwrote the ended game")
        check((try encoded(old.clock.moves+old.clock.provisionalMoves))==receipts,"Starting another game changed old timing")

        // A failed save must leave the game stopped and retryable, without
        // claiming the pending history has been safely ended on disk.
        let failureFile=try copied("failure"),failed=GameRecorder(storage:failureFile.deletingLastPathComponent(),deferredLocations:true)
        failed.clock.audible=false;try failed.restoreSavedGame(from:failureFile);try failed.flushStorage()
        let directory=failureFile.deletingLastPathComponent(),moved=root.appendingPathComponent("temporarily-unavailable")
        try FileManager.default.moveItem(at:directory,to:moved);try Data("unavailable".utf8).write(to:directory)
        failed.finish(retainingPending:true)
        check(failed.state == .paused && !failed.clock.running && failed.pendingMoveCount==1,"Save failure reported success or discarded pending evidence")
        check(failed.status.contains("could not be saved") && failed.playFlow == .storageBlocked,"Save failure did not provide a retryable explanation")
        try FileManager.default.removeItem(at:directory);try FileManager.default.moveItem(at:moved,to:directory)
        failed.finish(retainingPending:true)
        check(failed.state == .finished && failed.pendingMoveCount==1,"Repaired storage could not complete End and review later")

        let corruptFile=try copied("corrupt"),pending=corruptFile.deletingPathExtension().appendingPathExtension("pending.json")
        try Data("damaged".utf8).write(to:pending)
        let blocked=GameRecorder(storage:corruptFile.deletingLastPathComponent(),deferredLocations:true);blocked.clock.audible=false
        do {try blocked.restoreSavedGame(from:corruptFile);check(false,"Damaged pending history was silently accepted")} catch {}
        blocked.finish(retainingPending:true)
        check(try !blocked.canEndKeepingPending && blocked.state != .finished && Data(contentsOf:pending)==Data("damaged".utf8),"End bypassed damaged-file protection")

        let suiteName="EndPendingGameTests."+UUID().uuidString,settings=UserDefaults(suiteName:suiteName)!
        defer {settings.removePersistentDomain(forName:suiteName)}
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,
            referenceArchive:nil,recordingStorage:root.appendingPathComponent("ui"),settings:settings)
        let host=NSHostingView(rootView:PlaySessionControls(model:model,recorder:old,sidebar:true))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:380,height:230),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=host;window.orderFront(nil)
        defer {window.orderOut(nil)}
        RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("ended-controls.png"))
        print("PASS: \(checks) end-with-pending checks: actual incident, original receipts, repeat end, restart, review, new game, failed save and damaged-file protection")
    }
}
