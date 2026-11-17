import AppKit
@main struct AsyncDiagnosticsTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("async-diagnostics-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=DiagnosticArchiveStorage(roots:[root],limit:5_000_000)
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        DispatchQueue.global(qos:.utility).async {
            _=try! store.allocate(payload:1_000_000) {_,_ in entered.signal();release.wait();return true}
        }
        check(entered.wait(timeout:.now()+2) == .success,"Storage blocker did not start")
        let recorder=DiagnosticRecorder(root:root,archiveStorage:store)
        let start=ProcessInfo.processInfo.systemUptime
        try recorder.start(context:["test":"blocked allocation"],byteLimit:1_000_000,reserveBytes:0)
        check(ProcessInfo.processInfo.systemUptime-start<0.1,"Archive allocation blocked live processing")
        var heartbeat=false
        DispatchQueue.main.async {heartbeat=true}
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        check(heartbeat && recorder.isCapturing,"Main thread stalled while diagnostic storage was blocked")
        let context=CGContext(data:nil,width:16,height:16,bitsPerComponent:8,bytesPerRow:64,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray:0.5,alpha:1));context.fill(CGRect(x:0,y:0,width:16,height:16))
        let ticket=recorder.capture(context.makeImage()!,at:100,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        recorder.event("queued during startup",ticket:ticket);recorder.stop()
        check(!recorder.canStart,"Stop released an uninitialized writer prematurely")
        release.signal()
        let deadline=Date().addingTimeInterval(5)
        while !recorder.canStart && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
        check(recorder.state == .stopped && recorder.savedFrames==1,"Startup/stop race lost its frame")
        let rows=try String(contentsOf:recorder.folder!.appendingPathComponent("events.jsonl"))
        check(rows.contains("queued during startup") && rows.contains("capture ended"),"Startup queue lost event ordering or close")
        let badRoot=root.appendingPathComponent("not-a-directory");try Data([0]).write(to:badRoot)
        let failed=DiagnosticRecorder(root:badRoot);try failed.start(context:[:],reserveBytes:0)
        let end=Date().addingTimeInterval(5)
        while failed.state != .failed && Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
        check(failed.state == .failed && failed.canStart,"Asynchronous startup failure left the recorder stuck")
        let defaultsName="PhysicalGo.ArmedDiagnostics."+UUID().uuidString
        let defaults=UserDefaults(suiteName:defaultsName)!
        defer {defaults.removePersistentDomain(forName:defaultsName)}
        let captureRoot=root.appendingPathComponent("armed-continuous")
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,referenceArchive:nil,
            recordingStorage:nil,settings:defaults,diagnosticRoot:captureRoot,moveEvidenceRoot:root.appendingPathComponent("clips"))
        model.recorder.clock.audible=false
        model.armDiagnosticsForNextGame(true)
        check(model.diagnostics.startWithNextGame && !model.diagnostics.isOpen && model.diagnostics.folder==nil,"Arming opened a capture")
        check(!FileManager.default.fileExists(atPath:captureRoot.path),"Arming wrote an archive before Start")
        check(model.recorder.resume() == .unavailable && model.diagnostics.startWithNextGame,"Unavailable Start consumed the arm")
        model.recorder.start(size:19,clockSettings:.init(kind:.absolute,mainSeconds:120),startPaused:true)
        check(model.recorder.awaitingFirstStart && !model.recorder.clock.running && !model.diagnostics.isOpen,"Saving setup started clocks or capture")
        check(model.recorder.resume() == .checking,"First Start failed")
        check(model.diagnostics.isCapturing && !model.diagnostics.startWithNextGame,"First Start did not consume the arm and start capture")
        check(!model.recorder.clock.running && model.recorder.clock.engine.black.remaining==120,"Capture bypassed clock verification or changed balances")
        let firstFolder=model.diagnostics.folder
        model.recorder.pause();model.recorder.resume()
        check(model.diagnostics.folder==firstFolder && model.diagnostics.isCapturing,"Resume duplicated the continuous capture")
        model.recorder.pause();model.diagnostics.closeForExit()
        model.recorder.resume()
        check(!model.diagnostics.isOpen && model.diagnostics.folder==firstFolder,"Stopped capture restarted without rearming")
        model.recorder.pause();model.armDiagnosticsForNextGame(true);model.diagnosticSettings.enabled=false
        check(!model.diagnostics.startWithNextGame,"Diagnostics master switch left capture armed")
        model.recorder.resume()
        check(!model.diagnostics.isOpen,"Diagnostics-off Start opened capture")
        model.recorder.pause();model.armDiagnosticsForNextGame(true);model.diagnostics.stop()
        check(!model.diagnostics.startWithNextGame,"Stop did not cancel an armed capture")
        // A paused game requiring agreed times must not consume a Start request.
        let fixtureRoot=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ClockAwaitingTurn")
        let reviewRoot=root.appendingPathComponent("reviewed-game")
        try FileManager.default.createDirectory(at:reviewRoot,withIntermediateDirectories:true)
        for suffix in ["sgf","clock.json","pending.json"] {
            try FileManager.default.copyItem(at:fixtureRoot.appendingPathComponent("game."+suffix),to:reviewRoot.appendingPathComponent("game."+suffix))
        }
        let reviewed=GameRecorder(storage:reviewRoot)
        reviewed.clock.audible=false
        try reviewed.restoreSavedGame(from:reviewRoot.appendingPathComponent("game.sgf"))
        var startRequests=0;reviewed.onFirstStartRequested={startRequests+=1}
        check(reviewed.resume() == .clockReview && startRequests==0,"Rejected clock-review resume invoked capture hook")
        print("PASS: \(checks) asynchronous archive allocation, armed Start capture, clock gates, stop ordering and startup-failure checks")
    }
}
