import AppKit
import SwiftUI
import ImageIO

@main struct DiagnosticTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        let app=NSApplication.shared;app.setActivationPolicy(.accessory)
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/.build/DiagnosticTests-"+UUID().uuidString)
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;if !condition {fatalError(message)}}
        func wait(_ predicate:()->Bool,timeout:Double=15) {
            let deadline=Date().addingTimeInterval(timeout)
            while !predicate() && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.03))}
            check(predicate(),"Timed out waiting for diagnostic work")
        }
        func settle(_ duration:Double=0.3) {RunLoop.main.run(until:Date().addingTimeInterval(duration))}
        func json(_ url:URL)throws->[String:Any] {try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]}
        func entries(_ folder:URL)throws->[[String:Any]] {
            try String(contentsOf:folder.appendingPathComponent("events.jsonl"),encoding:.utf8).split(separator:"\n").map {
                try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
            }
        }
        func load(_ url:URL)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/RapidPlayStall")
        let empty=load(fixture.appendingPathComponent("empty-reference.png")),occupied=load(fixture.appendingPathComponent("frame.png"))
        struct Meta:Decodable {let calibration:BoardCalibration}
        let cal=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:fixture.appendingPathComponent("sample.json"))).calibration
        let gray=GrayFrame(image:empty)!,anchor=AutoGridDetector.TrackingAnchor(calibration:cal,fittedGrid:cal,frame:gray)
        let recorder=DiagnosticRecorder(root:root)
        check(recorder.capture(empty,at:1,context:[:],reference:nil,anchor:nil,anchorRevision:0)==nil && !FileManager.default.fileExists(atPath:root.path),"Diagnostics wrote files while off")
        try recorder.start(context:["test":"lossless, assets, events and lifecycle"],reserveBytes:0)
        let first=recorder.capture(empty,at:10,context:["calibration":DiagnosticRecorder.value(cal)],reference:empty,anchor:anchor,anchorRevision:1)!
        let op=recorder.begin("analysis",ticket:first)!
        recorder.event("recorder",ticket:first,details:["decision":["moveCount":0,"status":"Checking empty board"]])
        let second=recorder.capture(occupied,at:10.2,context:[:],reference:empty,anchor:anchor,anchorRevision:1)!
        recorder.event("frame skipped",ticket:second,details:["reason":"Analysis busy"])
        _=recorder.capture(occupied,at:10.4,context:[:],reference:occupied,anchor:anchor,anchorRevision:2)
        recorder.stop()
        check(recorder.state == .finishing && !recorder.canStart,"Stop did not await in-flight analysis")
        recorder.end(op,outcome:"grid alignment rejected",details:["readings":NSNull()])
        wait({recorder.canStart})
        let folder=recorder.folder!,events=try entries(folder),frames=events.filter{$0["event"] as? String == "frame"}
        check(frames.count==3 && recorder.savedFrames==3,"Diagnostic frames silently disappeared")
        check(events.contains{$0["outcome"] as? String == "grid alignment rejected"},"Rejected analysis result missing after Stop")
        check(events.contains{$0["event"] as? String == "frame skipped" && $0["frameID"] as? Int==second.frame},"Skipped camera frame lost its reason/ID")
        check(try json(folder.appendingPathComponent("session.json"))["status"] as? String == "complete","Clean completion not marked")
        check(frames[0]["referenceImage"] as? String == frames[1]["referenceImage"] as? String && frames[1]["referenceImage"] as? String != frames[2]["referenceImage"] as? String,"Reference versions were lost or needlessly duplicated")
        let saved=load(folder.appendingPathComponent(frames[0]["image"] as! String))
        check(GrayFrame(image:saved)!.pixels==gray.pixels,"PNG round trip changed analysis pixels")
        let roundTrip=GrayFrame(image:saved)!
        for point in [ImagePoint(x:0.3,y:0.3),ImagePoint(x:0.5,y:0.5),ImagePoint(x:0.7,y:0.7)] {
            let a=gray.patchColor(point)!,b=roundTrip.patchColor(point)!
            check(abs(a.red-b.red)<1e-12 && abs(a.green-b.green)<1e-12,"PNG round trip changed color evidence")
        }
        let savedOccupied=GrayFrame(image:load(folder.appendingPathComponent(frames[1]["image"] as! String)))!
        let originalDetection=BoardDetector.detect(frame:GrayFrame(image:occupied)!,reference:gray,calibration:cal,threshold:0.13)!
        let replayDetection=BoardDetector.detect(frame:savedOccupied,reference:roundTrip,calibration:cal,threshold:0.13)!
        check(originalDetection.readings==replayDetection.readings && replayDetection.snapshot.stones.count==16,"Saved PNG pair changed the full 16-stone detection")
        let savedAnchor=frames[0]["trackingAnchor"] as! [String:Any]
        check(try Data(contentsOf:folder.appendingPathComponent(savedAnchor["pixels"] as! String))==Data(gray.pixels),"Tracking anchor pixels changed")
        try recorder.start(context:[:],reserveBytes:0)
        check(recorder.folder != folder,"New diagnostic run overwrote the old one")
        check(recorder.begin("old callback",ticket:first)==nil,"Old session ticket attached to new session")
        recorder.event("old event",ticket:first)
        recorder.closeForExit()
        check(!(try entries(recorder.folder!)).contains{$0["event"] as? String == "old event"},"Old callback contaminated a new session")
        check(FileManager.default.fileExists(atPath:folder.appendingPathComponent("frames/000001.png").path),"Completed diagnostics were deleted")

        let limited=DiagnosticRecorder(root:root)
        try limited.start(context:[:],byteLimit:1,reserveBytes:0)
        _=limited.capture(empty,at:1,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        wait({limited.state == .failed})
        check(limited.status.contains("storage limit"),"Storage limit did not visibly end capture")
        check(try json(limited.folder!.appendingPathComponent("session.json"))["status"] as? String == "failed","Limit failure was marked successful")
        let fullDisk=DiagnosticRecorder(root:root)
        try fullDisk.start(context:[:],reserveBytes:Int64.max)
        _=fullDisk.capture(empty,at:1,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        wait({fullDisk.state == .failed})
        check(fullDisk.status.contains("disk space"),"Low-space guard failed")
        let slow=DiagnosticRecorder(root:root,maximumPendingFrames:1)
        try slow.start(context:[:],reserveBytes:0)
        _=slow.capture(empty,at:1,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        check(slow.capture(empty,at:1.2,context:[:],reference:nil,anchor:nil,anchorRevision:0)==nil,"Backpressure retained unbounded frames")
        wait({slow.canStart})
        check(slow.state == .failed && slow.savedFrames==1 && slow.status.contains("keep up"),"Writer overload did not preserve queued frame and report failure")
        check(try json(slow.folder!.appendingPathComponent("session.json"))["status"] as? String == "failed","Overload manifest falsely claimed success")
        let broken=DiagnosticRecorder(root:root)
        try broken.start(context:[:],reserveBytes:0)
        try FileManager.default.removeItem(at:broken.folder!.appendingPathComponent("frames"))
        _=broken.capture(empty,at:1,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        wait({broken.state == .failed})
        let exit=DiagnosticRecorder(root:root)
        try exit.start(context:[:],reserveBytes:0)
        let exitFrame=exit.capture(empty,at:1,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        _=exit.begin("unfinished analysis",ticket:exitFrame)
        exit.closeForExit()
        let exitEvents=try entries(exit.folder!)
        check(exitEvents.contains{$0["event"] as? String == "operation canceled"} && exitEvents.contains{$0["event"] as? String == "capture ended"},"App exit left a silent unfinished operation")
        check(FileManager.default.fileExists(atPath:exit.folder!.appendingPathComponent("frames/000001.png").path),"App exit lost queued frame")

        // Exercise actual ExperimentModel routing and recorder correlation, without
        // opening a physical camera or changing the user's reference/settings.
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil,diagnosticRoot:root)
        model.soundMode = .off;model.tracksCameraMotion=false
        try model.openSample(from:fixture);settle(0.6)
        model.running=true;model.frozen=false;model.handleCameraStatus("Live · diagnostic test",state:.live)
        model.startDiagnostics()
        for _ in 0..<6 {model.receive(empty);settle(0.3)}
        check(model.canStartNewRecording,"Diagnostic mode interfered with empty-board readiness")
        model.startRecording()
        let context=CGContext(data:nil,width:empty.width,height:empty.height,bitsPerComponent:8,bytesPerRow:empty.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(empty,in:CGRect(x:0,y:0,width:empty.width,height:empty.height))
        let p=cal.point(col:15,row:15)
        context.setFillColor(CGColor(gray:0.02,alpha:1));context.fillEllipse(in:CGRect(x:p.x*Double(empty.width-1)-21,y:(1-p.y)*Double(empty.height-1)-21,width:42,height:42))
        let one=context.makeImage()!
        for _ in 0..<7 {model.receive(one);settle(0.3)}
        check(model.recorder.moveCount==1 && model.recorder.game.moves.first?.1?.0==15 && model.recorder.game.moves.first?.1?.1==15,"Diagnostic mode prevented the centered test move being recorded at its intended intersection")
        model.recorder.pause();let paused=model.diagnostics.savedFrames
        model.receive(one);settle(0.4)
        check(model.diagnostics.savedFrames>paused && model.recorder.moveCount==1,"Pausing the game stopped diagnostics or changed accepted history")
        model.frozen=true
        let frozenBefore=model.diagnostics.savedFrames
        model.receiveCameraFrame(one,capturedAt:ProcessInfo.processInfo.systemUptime);settle(0.4)
        check(model.diagnostics.savedFrames>frozenBefore && model.recorder.moveCount==1,"Frozen camera input was not saved independently of detection")
        model.frozen=false
        model.handleCameraStatus("Live · diagnostic camera event",state:.live)
        model.receive(one);model.receive(one);settle(0.5) // Deliberately busy analysis.
        // Stale results must also be journaled rather than silently disappearing.
        model.receive(one);model.thresholdChanged();settle(0.5)
        model.diagnostics.stop();wait({model.diagnostics.canStart})
        let integrated=try entries(model.diagnostics.folder!)
        check(integrated.contains{($0["decision"] as? [String:Any])?["event"] as? String == "accepted move" && $0["frameID"] != nil},"Accepted move was not correlated with its image")
        check(integrated.contains{($0["decision"] as? [String:Any])?["sgf"] != nil},"Diagnostic session lost accepted SGF checkpoints")
        check(integrated.contains{$0["outcome"] as? String == "discarded stale analysis"},"Stale revision result was not captured")
        check(integrated.contains{$0["event"] as? String == "camera status"},"Camera status transition was not archived")
        check(integrated.contains{$0["reason"] as? String == "View is frozen"},"Frozen input lost its skip reason")
        check(integrated.contains{$0["reason"] as? String == "Analysis busy"},"Busy frames were not captured with their skip reason")
        let before=model.diagnostics.savedFrames
        model.receive(one);settle(0.3)
        check(model.diagnostics.savedFrames==before && model.recorder.state == .paused,"Stopping diagnostics affected the game or kept writing images")
        let replayFolder=model.diagnostics.folder!
        let latest=URL(fileURLWithPath:"PhysicalGo/.build/DiagnosticIntegrationSession.txt")
        try replayFolder.path.write(to:latest,atomically:true,encoding:.utf8)

        model.startDiagnostics();model.tracksCameraMotion=true
        context.setFillColor(CGColor(gray:0,alpha:1));context.fill(CGRect(x:0,y:0,width:empty.width,height:empty.height))
        model.receive(context.makeImage()!);settle(0.7)
        check(model.alignmentNeedsRecovery,"Black frame did not exercise the failed-alignment path")
        model.detectGrid();wait({!model.detectingGrid})
        model.receive(empty);settle(0.7)
        model.detectGrid();model.resetCalibration() // Invalidate a search in flight.
        model.diagnostics.stop();wait({model.diagnostics.canStart})
        let gridEvents=try entries(model.diagnostics.folder!)
        check(gridEvents.contains{$0["outcome"] as? String == "grid alignment rejected"},"Failed tracking frame was not recorded")
        check(gridEvents.contains{$0["outcome"] as? String == "grid not found"},"Failed full-view search was not recorded")
        check(gridEvents.contains{$0["outcome"] as? String == "discarded stale grid search"},"Canceled search lost its diagnostic result")
        try model.diagnostics.folder!.path.write(to:URL(fileURLWithPath:"PhysicalGo/.build/DiagnosticGridSession.txt"),atomically:true,encoding:.utf8)

        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:400),styleMask:[.titled],backing:.buffered,defer:false)
        let host=NSHostingView(rootView:DiagnosticControls(model:model,diagnostics:model.diagnostics).padding().frame(width:520,height:400).background(Color(nsColor:.windowBackgroundColor)))
        window.contentView=host;window.orderFront(nil);settle()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"PhysicalGo/.build/diagnostic-controls.png"))
        window.orderOut(nil)
        print("Diagnostic integration session:",replayFolder.path)
        print("PASS: \(checks) diagnostic checks: lossless frames, reference/anchor versions, accepted and rejected outcomes, busy/stale inputs, storage/space/backpressure/write failures, stop/exit draining, session isolation, passive game integration and native controls.")
    }
}
