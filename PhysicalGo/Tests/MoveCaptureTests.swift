import AppKit
import ImageIO

@main struct MoveCaptureTests {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("move-capture-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let bitmap=CGContext(data:nil,width:128,height:96,bitsPerComponent:8,bytesPerRow:128*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red:0.7,green:0.5,blue:0.2,alpha:1));bitmap.fill(CGRect(x:0,y:0,width:128,height:96))
        bitmap.setFillColor(CGColor(gray:0,alpha:1));bitmap.fill(CGRect(x:23,y:31,width:7,height:9))
        let image=bitmap.makeImage()!
        let capture=MoveEvidenceCapture(root:root.appendingPathComponent("normal"),scheduleDeadlines:false)
        var annotationBuilds=0
        func annotation()->[String:Any] {annotationBuilds += 1;return ["lazyAnnotation":annotationBuilds]}
        capture.annotate(annotation(),now:0)
        precondition(annotationBuilds==0,"Empty capture ring built an annotation")
        func offer(_ time:Double) {
            capture.offer(image,at:time,online:true,context:["viewQuarterTurns":3,"testFrameTime":time],
                reference:image,anchor:nil,anchorRevision:1)
        }
        func settle() {RunLoop.main.run(until:Date().addingTimeInterval(0.08))}
        func entries(_ folder:URL)throws->[[String:Any]] {
            try String(contentsOf:folder.appendingPathComponent("events.jsonl"),encoding:.utf8).split(separator:"\n").map {
                try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
            }
        }
        for i in 0...9 {offer(Double(i)*0.5)}
        precondition(capture.bufferedFrames==9)
        precondition(!FileManager.default.fileExists(atPath:capture.root.path),"Untriggered ring wrote images to disk")
        capture.annotate(annotation(),now:4.5)
        precondition(annotationBuilds==1,"Buffered annotation was omitted or built twice")
        capture.annotate(["captureUptime":4.5,"alignment":["rejectionReason":"test failure"]],now:4.5)
        let event:[String:Any]=["event":"uncertain_move","game":42,"attempt":"a","point":10,"uptime":4.5]
        let first=capture.trigger(event,now:4.5)!
        settle()
        offer(5);settle();offer(5.1) // Rate limit.
        offer(5.5);settle()
        precondition(capture.trigger(event,now:6)==first,"Overlapping triggers did not coalesce")
        offer(6);settle();offer(8.5);settle();offer(9.1);settle()
        precondition(!capture.recorder.isCapturing)
        capture.closeForExit()
        let folder=URL(fileURLWithPath:first),rows=try entries(folder)
        let frames=rows.filter{$0["event"] as? String=="frame"}
        precondition(frames.count==13,"Pre/post frames lost or duplicate samples added: \(frames.count)")
        precondition(frames.first?["captureUptime"] as? Double==0.5)
        precondition(frames.last?["captureUptime"] as? Double==8.5)
        precondition(frames.allSatisfy{$0["viewQuarterTurns"] as? Int==3})
        precondition(rows.filter{$0["event"] as? String=="move evidence trigger"}.count==2)
        precondition(rows.contains{$0["alignment"] != nil})
        let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(frames[0]["image"] as! String) as CFURL,nil)!
        let restored=CGImageSourceCreateImageAtIndex(source,0,nil)!
        precondition(restored.width==image.width && restored.height==image.height)
        precondition(GrayFrame(image:restored)!.pixels==GrayFrame(image:image)!.pixels,"Capture changed recognition pixels")
        let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("session.json"))) as! [String:Any]
        precondition((manifest["capturePolicy"] as! String).contains("2 samples/second"))
        precondition(manifest["labelsAreGroundTruth"] as? Bool==false)
        let tiny=MoveEvidenceCapture(root:root.appendingPathComponent("tiny"),memoryLimit:image.bytesPerRow*image.height*2,scheduleDeadlines:false)
        for i in 0...10 {tiny.offer(image,at:Double(i),online:true,context:[:],reference:nil,anchor:nil,anchorRevision:0)}
        precondition(tiny.bufferedFrames==2 && tiny.bufferedImageBytes<=image.bytesPerRow*image.height*2)
        tiny.enabled=false
        tiny.annotate(annotation(),now:12)
        precondition(annotationBuilds==1,"Disabled capture built an annotation")
        precondition(tiny.bufferedFrames==0 && tiny.trigger(event,now:10)==nil)
        let full=MoveEvidenceCapture(root:root.appendingPathComponent("full"),byteLimit:100,scheduleDeadlines:false)
        full.offer(image,at:0,online:true,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        precondition(full.trigger(event,now:0)==nil && full.status.contains("storage allowance"))
        precondition(!FileManager.default.fileExists(atPath:full.root.path))
        let capped=MoveEvidenceCapture(root:root.appendingPathComponent("capped"),scheduleDeadlines:false)
        capped.offer(image,at:0,online:true,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        precondition(capped.trigger(event,now:0) != nil);settle()
        for time in stride(from:2.0,through:10.0,by:2.0) {precondition(capped.trigger(event,now:time) != nil)}
        capped.offer(image,at:12.1,online:true,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        precondition(!capped.recorder.isCapturing,"Repeated triggers extended a clip without bound")
        capped.closeForExit()
        // Complete path: accepted 0.85 camera move -> bridge -> timing trigger ->
        // lossless archive, using an isolated fake server directory (no OGS IO).
        let bridgeRoot=root.appendingPathComponent("bridge")
        try FileManager.default.createDirectory(at:bridgeRoot,withIntermediateDirectories:true)
        let board=Array(repeating:"empty",count:81)
        let state:[String:Any]=["token":"TEST-ONLY","game":42,"version":1,"size":9,"cells":board,
            "ready":true,"myTurn":true,"color":"black","time":Date().timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject:state).write(to:bridgeRoot.appendingPathComponent("state.json"))
        let journal=PhysicalMoveTiming(directory:bridgeRoot.appendingPathComponent("timing"))
        let automatic=MoveEvidenceCapture(root:root.appendingPathComponent("integrated"),scheduleDeadlines:false)
        automatic.offer(image,at:1,online:true,context:["viewQuarterTurns":0],reference:image,anchor:nil,anchorRevision:1)
        let bridge=PhysicalOnlineBoard(directory:bridgeRoot,moveTiming:journal,announceOpponent:{},announceCorrection:{})
        bridge.onEvidenceCapture={event in automatic.trigger(event,now:event["uptime"] as! Double)}
        bridge.enabled=true
        func observation(_ stone:Bool)->BoardObservation {
            BoardObservation(readings:(0..<81).map{IntersectionReading(row:$0/9,col:$0%9,
                occupancy:stone && $0==10 ? .black:.empty,confidence:stone && $0==10 ? 0.85:1,delta:0)},size:9)
        }
        bridge.consume(observation(false),now:1)
        for i in 0..<4 {bridge.consume(observation(true),now:1.2+Double(i)*0.4)}
        journal.flush();automatic.closeForExit()
        precondition(FileManager.default.fileExists(atPath:bridgeRoot.appendingPathComponent("move.json").path))
        let journalFile=try FileManager.default.contentsOfDirectory(at:journal.directory,includingPropertiesForKeys:nil)[0]
        let timingRows=try String(contentsOf:journalFile,encoding:.utf8).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }
        let sent=timingRows.first{$0["event"] as? String=="move_request_written"}!
        let archived=URL(fileURLWithPath:sent["evidenceCaptureFolder"] as! String)
        precondition((sent["submissionEvidence"] as! [String:Any])["confidence"] as? Double==0.85)
        let captured=try entries(archived)
        precondition(captured.contains{$0["event"] as? String=="frame"})
        precondition(captured.filter{$0["event"] as? String=="move evidence trigger"}.count==2)
        print("PASS: transient pre-buffer, post-roll, rate/memory/storage limits, overlapping triggers, bounded duration, full-resolution lossless frames, orientation/context, and orderly shutdown.")
        print("PASS: accepted 0.85 move dispatch through the real bridge automatically creates and links an evidence archive; no live server used.")
    }
}
