import AppKit
import ImageIO

/// Re-write actual camera images at delivery cadence while automatic evidence
/// competes for disk/PNG time. Test artifacts are isolated from the real archive.
@main struct RecordingWriterTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        let input=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let entries=try String(contentsOf:input.appendingPathComponent("events.jsonl")).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }.filter{$0["event"] as? String == "frame"}
        let frames=entries.filter{FileManager.default.fileExists(atPath:input.appendingPathComponent($0["image"] as! String).path)}
        let recorder=DiagnosticRecorder(root:output.appendingPathComponent("continuous"))
        let clips=DiagnosticRecorder(root:output.appendingPathComponent("automatic"),maximumPendingFrames:64)
        try recorder.start(context:["test":"recorded camera writing throughput"],byteLimit:5_000_000_000,reserveBytes:0)
        try clips.start(context:["test":"concurrent automatic clip burst"],byteLimit:2_000_000_000,reserveBytes:0)
        let started=ProcessInfo.processInfo.systemUptime
        var heartbeat=0
        let timer=Timer.scheduledTimer(withTimeInterval:0.05,repeats:true) {_ in heartbeat+=1}
        defer {timer.invalidate()}
        for (i,row) in frames.enumerated() {
            autoreleasepool {
                let image=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(input.appendingPathComponent(row["image"] as! String) as CFURL,nil)!,0,nil)!
                let time=row["captureUptime"] as! Double
                _=recorder.capture(image,at:time,context:["originalFrameID":row["frameID"]!],reference:nil,anchor:nil,anchorRevision:0)
                // A buffered pre-roll arrives as a burst rather than at camera cadence.
                if i==60 || i==140 {
                    for j in 0..<21 {_=clips.capture(image,at:time-4+Double(j)*0.2,context:[:],reference:nil,anchor:nil,anchorRevision:0)}
                }
            }
            RunLoop.main.run(until:Date().addingTimeInterval(max(0,started+Double(i+1)*0.2-ProcessInfo.processInfo.systemUptime)))
            precondition(recorder.isCapturing,"Writer stopped during recorded-camera playback")
        }
        recorder.stop();clips.stop()
        let deadline=Date().addingTimeInterval(30)
        while (!recorder.canStart || !clips.canStart) && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
        precondition(recorder.state == .stopped && clips.state == .stopped,"Writers failed to close")
        precondition(recorder.savedFrames+recorder.omittedImages==frames.count,"Image accounting lost camera deliveries")
        precondition(heartbeat>frames.count*2,"Diagnostic writing blocked the main run loop")
        let saved=try String(contentsOf:recorder.folder!.appendingPathComponent("events.jsonl")).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }.filter{$0["event"] as? String == "frame"}
        for row in saved {
            let original=frames.first{$0["frameID"] as? Int==row["originalFrameID"] as? Int}!
            precondition(row["captureUptime"] as? Double==original["captureUptime"] as? Double,"Writing changed capture time")
            let url=recorder.folder!.appendingPathComponent(row["image"] as! String)
            precondition(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil) != nil,"Saved PNG unreadable")
        }
        let result:[String:Any]=["delivered":frames.count,"saved":recorder.savedFrames,"omitted":recorder.omittedImages,
            "automaticSaved":clips.savedFrames,"automaticOmitted":clips.omittedImages,"mainHeartbeats":heartbeat,
            "elapsed":ProcessInfo.processInfo.systemUptime-started,"complete":true]
        try JSONSerialization.data(withJSONObject:result,options:.prettyPrinted).write(to:output.appendingPathComponent("results.json"))
        print("PASS: \(result)")
    }
}
