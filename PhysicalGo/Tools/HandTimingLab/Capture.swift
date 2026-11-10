import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct LabFrame:Codable {
    let index:Int
    let file:String?
    let timestamp:CameraFrameTimestamp
    let dropped:String?
}
struct LabLabel:Codable {
    let lastObstructed:Int
    let firstClear:Int
}
struct LabLabels:Codable {
    let session:String
    var withdrawals:[LabLabel]
}

/// Separate development executable. No reference to the game or its clocks.
/// All session state and disk writes are serialized; slow writes cause explicit
/// dropped-frame records rather than an unbounded queue of image buffers.
final class LabCapture:NSObject,AVCaptureVideoDataOutputSampleBufferDelegate {
    static func devices()->[AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera,.external,.continuityCamera],mediaType:.video,position:.unspecified).devices
    }
    let queue=DispatchQueue(label:"HandTimingLab.capture")
    private var session:AVCaptureSession?
    private var journal:FileHandle?
    private var folder:URL?
    private let context=CIContext(options:[.cacheIntermediates:false])
    private var started=0.0, duration=20.0, bytes=0, index=0, saved=0, dropped=0
    private var timer:DispatchSourceTimer?
    var onPreview:((CGImage,Int)->Void)?
    var onComplete:((URL?,String)->Void)?
    func start(deviceID:String,seconds:Double) {
        AVCaptureDevice.requestAccess(for:.video) {granted in
            self.queue.async {
                guard granted else {self.complete(nil,"Camera access is off for Hand Timing Lab.");return}
                do {try self.configure(deviceID:deviceID,seconds:seconds)}
                catch {
                    let message="Capture failed: \(error.localizedDescription)"
                    if self.session != nil || self.journal != nil {self.finish(message)} else {self.complete(nil,message)}
                }
            }
        }
    }
    private func configure(deviceID:String,seconds:Double)throws {
        guard session==nil else {return}
        guard let device=Self.devices().first(where:{$0.uniqueID==deviceID}) else {throw NSError(domain:"Camera unavailable",code:1)}
        let root=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Physical Go Timing Lab",isDirectory:true)
        let destination=root.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        folder=destination;index=0;saved=0;dropped=0;bytes=0;duration=min(30,max(5,seconds))
        let journalURL=destination.appendingPathComponent("frames.jsonl")
        FileManager.default.createFile(atPath:journalURL.path,contents:nil)
        journal=try FileHandle(forWritingTo:journalURL)
        let capture=AVCaptureSession();capture.beginConfiguration()
        if capture.canSetSessionPreset(.hd1920x1080) {capture.sessionPreset = .hd1920x1080}
        let input=try AVCaptureDeviceInput(device:device)
        guard capture.canAddInput(input) else {throw NSError(domain:"Cannot open camera",code:2)}
        capture.addInput(input)
        let output=AVCaptureVideoDataOutput();output.alwaysDiscardsLateVideoFrames=true
        output.videoSettings=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self,queue:queue)
        guard capture.canAddOutput(output) else {throw NSError(domain:"Cannot read camera frames",code:3)}
        capture.addOutput(output);capture.commitConfiguration()
        // Request 30 fps only when supported by the chosen format. Actual PTS
        // and every delivered/dropped frame are recorded; never assume 30 fps.
        try device.lockForConfiguration()
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where:{$0.minFrameRate<=30 && $0.maxFrameRate>=30}) {
            device.activeVideoMinFrameDuration=CMTime(value:1,timescale:30)
            device.activeVideoMaxFrameDuration=CMTime(value:1,timescale:30)
        }
        device.unlockForConfiguration()
        let manifest:[String:Any]=["session":destination.lastPathComponent,"created":ISO8601DateFormatter().string(from:Date()),"camera":device.localizedName,"deviceID":device.uniqueID,"requestedFPS":30,"durationLimitSeconds":duration,"sizeLimitBytes":2_000_000_000,"encoding":"JPEG quality 0.95","purpose":"Developer timing validation; manual labels are independent of the detector"]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:destination.appendingPathComponent("manifest.json"),options:.atomic)
        session=capture;started=ProcessInfo.processInfo.systemUptime
        let watchdog=DispatchSource.makeTimerSource(queue:queue)
        watchdog.schedule(deadline:.now()+duration);watchdog.setEventHandler{[weak self] in self?.finish("Capture complete")}
        timer=watchdog;watchdog.resume();capture.startRunning()
    }
    func stop() {queue.async{self.finish("Capture stopped")}}
    /// Exercise the exact image/journal writer with synthetic pixel buffers,
    /// without camera permission. Available only in this development tool.
    func prepareSyntheticTest(in destination:URL)throws {
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        folder=destination;index=0;saved=0;dropped=0;bytes=0
        let url=destination.appendingPathComponent("frames.jsonl")
        FileManager.default.createFile(atPath:url.path,contents:nil)
        journal=try FileHandle(forWritingTo:url);session=AVCaptureSession()
        started=ProcessInfo.processInfo.systemUptime;duration=30
    }
    func finishSyntheticTest() {finish("Synthetic capture complete")}
    func captureOutput(_ output:AVCaptureOutput,didOutput sample:CMSampleBuffer,from connection:AVCaptureConnection) {
        autoreleasepool {
            guard let folder,let session else {return}
            let stamp=CameraFrameTimestamp.make(sample,clock:session.synchronizationClock,arrival:ProcessInfo.processInfo.systemUptime)
            guard stamp.arrivedAt-started<=duration,bytes<2_000_000_000 else {finish("Capture limit reached");return}
            do {
                guard let buffer=CMSampleBufferGetImageBuffer(sample) else {throw NSError(domain:"Missing pixel buffer",code:4)}
                let ci=CIImage(cvPixelBuffer:buffer)
                guard let image=context.createCGImage(ci,from:ci.extent) else {throw NSError(domain:"Cannot render frame",code:5)}
                let name=String(format:"frame-%06d.jpg",index),url=folder.appendingPathComponent(name)
                guard let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.jpeg.identifier as CFString,1,nil) else {throw NSError(domain:"Cannot create image",code:6)}
                CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.95] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else {throw NSError(domain:"Cannot save image",code:7)}
                bytes += (try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                try append(.init(index:index,file:name,timestamp:stamp,dropped:nil));saved+=1
                if saved%3==0 {let count=saved;DispatchQueue.main.async{self.onPreview?(image,count)}}
            } catch {finish("Capture failed: \(error.localizedDescription)")}
        }
    }
    func captureOutput(_ output:AVCaptureOutput,didDrop sample:CMSampleBuffer,from connection:AVCaptureConnection) {
        guard let session else {return}
        let stamp=CameraFrameTimestamp.make(sample,clock:session.synchronizationClock,arrival:ProcessInfo.processInfo.systemUptime)
        do {try append(.init(index:index,file:nil,timestamp:stamp,dropped:"AVCapture dropped frame"));dropped+=1}
        catch {finish("Frame journal failed: \(error.localizedDescription)")}
    }
    private func append(_ frame:LabFrame)throws {
        var data=try JSONEncoder().encode(frame);data.append(10);try journal?.write(contentsOf:data);index+=1
    }
    private func complete(_ folder:URL?,_ message:String) {DispatchQueue.main.async{self.onComplete?(folder,message)}}
    private func finish(_ message:String) {
        guard session != nil || journal != nil else {return}
        timer?.cancel();timer=nil;session?.stopRunning();session=nil
        do {try journal?.synchronize();try journal?.close()} catch {complete(folder,"Journal close failed: \(error.localizedDescription)");journal=nil;return}
        journal=nil
        let destination=folder;folder=nil
        complete(destination,"\(message) · \(saved) saved, \(dropped) dropped")
    }
}
