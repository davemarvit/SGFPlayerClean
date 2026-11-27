import Foundation
import CoreGraphics

/// Actual asynchronous writer lifecycle with synthetic pixels only.
@main struct DiagnosticManifestWriterTests {
    @MainActor static func main()throws {
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        func wait(_ predicate:()->Bool) {
            let end=Date().addingTimeInterval(5)
            while !predicate() && Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
            check(predicate(),"Writer did not finish bounded test")
        }
        func manifest(_ recorder:DiagnosticRecorder)throws->[String:Any] {
            try JSONSerialization.jsonObject(with:Data(contentsOf:recorder.folder!.appendingPathComponent("session.json"))) as! [String:Any]
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("manifest-writer-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let pixels=CGContext(data:nil,width:16,height:16,bitsPerComponent:8,bytesPerRow:64,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixels.setFillColor(CGColor(gray:0.5,alpha:1));pixels.fill(CGRect(x:0,y:0,width:16,height:16))
        let image=pixels.makeImage()!
        let checkpoint:[String:Any]=["background":["pixels":Array(0..<512)],"temporal":["references":[["pixels":Array(0..<512)]]]]
        let store=DiagnosticArchiveStorage(roots:[root],limit:5_000_000)
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        DispatchQueue.global(qos:.utility).async {
            _=try! store.allocate(payload:1_000_000) {_,_ in entered.signal();release.wait();return true}
        }
        check(entered.wait(timeout:.now()+2) == .success,"Allocation blocker missing")
        let recorder=DiagnosticRecorder(root:root,maximumPendingFrames:2,archiveStorage:store)
        try recorder.start(context:["handOutlineCheckpoint":checkpoint],byteLimit:1_000_000,reserveBytes:0)
        for i in 0..<102 {_=recorder.capture(image,at:Double(i),context:[:],reference:nil,anchor:nil,anchorRevision:0)}
        check(recorder.omittedImages==100,"Image backpressure changed")
        release.signal();wait {recorder.savedFrames==2}
        let path=recorder.folder!.appendingPathComponent("session.json")
        let initial=try Data(contentsOf:path)
        _=recorder.capture(image,at:200,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        wait {recorder.savedFrames==3}
        check(try Data(contentsOf:path)==initial,"Gap rewrote the entire immutable manifest")
        recorder.stop();wait {recorder.canStart}
        let finished=try manifest(recorder)
        check(finished["status"] as? String == "complete" && finished["framesSaved"] as? Int==3 && finished["omittedImages"] as? Int==100,"Final counters lost")
        check(finished["handOutlineCheckpoint"] as? NSDictionary == checkpoint as NSDictionary,"Final checkpoint changed")
        let rows=try String(contentsOf:recorder.folder!.appendingPathComponent("events.jsonl")).split(separator:"\n").map {try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        let gaps=rows.filter {$0["event"] as? String == "image writing gap"}
        check(gaps.count==1 && gaps[0]["omittedImages"] as? Int==100 && gaps[0]["firstCaptureUptime"] as? Double==2 && gaps[0]["lastCaptureUptime"] as? Double==101,"Exact gap evidence lost")
        let periodic=DiagnosticRecorder(root:root,maximumPendingFrames:32)
        try periodic.start(context:["handOutlineCheckpoint":checkpoint],reserveBytes:0)
        for i in 0..<25 {_=periodic.capture(image,at:Double(i),context:[:],reference:nil,anchor:nil,anchorRevision:0)}
        wait {periodic.savedFrames==25}
        let progress=try manifest(periodic)
        check(progress["status"] as? String == "recording" && progress["framesSaved"] as? Int==25,"Periodic snapshot disappeared")
        check(progress["handOutlineCheckpoint"] as? NSDictionary == checkpoint as NSDictionary,"Periodic checkpoint changed")
        periodic.closeForExit()
        check(try manifest(periodic)["status"] as? String == "complete","Exit snapshot disappeared")
        let failed=DiagnosticRecorder(root:root)
        try failed.start(context:["handOutlineCheckpoint":checkpoint],byteLimit:1,reserveBytes:0)
        _=failed.capture(image,at:1,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        wait {failed.state == .failed}
        let failure=try manifest(failed)
        check(failure["status"] as? String == "failed" && failure["framesSaved"] as? Int==0,"Abort counters missing")
        check(failure["handOutlineCheckpoint"] as? NSDictionary == checkpoint as NSDictionary,"Abort lost checkpoint")
        print("PASS \(checks) diagnostic manifest writer lifecycle checks")
    }
}
