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
        print("PASS: \(checks) asynchronous archive allocation, main-thread responsiveness, stop/queue ordering and startup-failure checks")
    }
}
