import AVFoundation
import ImageIO

@main struct HandTimingLabTests {
    static func main()throws {
        let temporary=CommandLine.arguments.count==1
        let folder=temporary ? FileManager.default.temporaryDirectory.appendingPathComponent("HandTimingLab-"+UUID().uuidString):URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        defer {if temporary {try? FileManager.default.removeItem(at:folder)}}
        let capture=LabCapture();try capture.prepareSyntheticTest(in:folder)
        var pixel:CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault,320,240,kCVPixelFormatType_32BGRA,[kCVPixelBufferIOSurfacePropertiesKey:[:] as [String:Any]] as CFDictionary,&pixel)==kCVReturnSuccess)
        let buffer=pixel!
        CVPixelBufferLockBaseAddress(buffer,[])
        memset(CVPixelBufferGetBaseAddress(buffer),180,CVPixelBufferGetBytesPerRow(buffer)*240)
        CVPixelBufferUnlockBaseAddress(buffer,[])
        var format:CMVideoFormatDescription?
        precondition(CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:buffer,formatDescriptionOut:&format)==noErr)
        let output=AVCaptureVideoDataOutput(),connection=AVCaptureConnection(inputPorts:[],output:AVCaptureVideoDataOutput())
        for i in 0..<12 {
            var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:30),presentationTimeStamp:CMClockGetTime(CMClockGetHostTimeClock()),decodeTimeStamp:.invalid)
            var sample:CMSampleBuffer?
            precondition(CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:buffer,formatDescription:format!,sampleTiming:&timing,sampleBufferOut:&sample)==noErr)
            let arrival=ProcessInfo.processInfo.systemUptime
            let mapped=CameraFrameTimestamp.make(sample!,clock:CMClockGetHostTimeClock(),arrival:arrival)
            precondition(mapped.source=="cameraPresentation" && abs(mapped.capturedAt-arrival)<0.05)
            precondition(CameraFrameTimestamp.make(sample!,clock:nil,arrival:arrival).source=="callback")
            if i==5 {capture.captureOutput(output,didDrop:sample!,from:connection)}
            else {capture.captureOutput(output,didOutput:sample!,from:connection)}
            Thread.sleep(forTimeInterval:1/30)
        }
        capture.finishSyntheticTest()
        let lines=try String(contentsOf:folder.appendingPathComponent("frames.jsonl")).split(separator:"\n")
        let frames=try lines.map{try JSONDecoder().decode(LabFrame.self,from:Data($0.utf8))}
        precondition(frames.count==12 && frames.filter{$0.dropped != nil}.count==1)
        precondition(frames.map(\.index)==Array(0..<12))
        precondition(zip(frames,frames.dropFirst()).allSatisfy{$0.timestamp.capturedAt<$1.timestamp.capturedAt})
        for frame in frames where frame.file != nil {
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(frame.file!) as CFURL,nil)!
            let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
            precondition(image.width==320 && image.height==240)
        }
        let grid:[String:Any]=["size":19,"corners":[["x":0.1,"y":0.1],["x":0.9,"y":0.1],["x":0.9,"y":0.9],["x":0.1,"y":0.9]]]
        try JSONSerialization.data(withJSONObject:grid).write(to:folder.appendingPathComponent("calibration.json"))
        try JSONEncoder().encode(LabLabels(session:folder.lastPathComponent,withdrawals:[])).write(to:folder.appendingPathComponent("labels.json"))
        print("PASS: native sample → JPEG → timestamp journal, dropped-frame indexing and decode; synthetic fixture only, not accuracy evidence")
    }
}
