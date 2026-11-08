import Foundation
import Combine
import CoreGraphics

/// A bounded, transient camera ring. Only unusual move attempts persist in either play mode.
/// Reuses the lossless, asynchronous diagnostic writer and its failure reporting.
@MainActor final class MoveEvidenceCapture:ObservableObject {
    nonisolated static var directory:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Physical Go/Move Evidence",isDirectory:true)
    }
    struct Frame {
        let image:CGImage,time:Double,context:[String:Any],reference:CGImage?
        let anchor:AutoGridDetector.TrackingAnchor?,anchorRevision:Int
        var bytes:Int {image.bytesPerRow*image.height}
    }
    @Published var enabled=true {didSet {if !enabled {stop(reason:"Automatic capture disabled")}}}
    @Published private(set) var status="Buffering during play or local recording; unusual moves save automatically."
    let recorder:DiagnosticRecorder
    let root:URL
    private let byteLimit:Int64,memoryLimit:Int
    private let scheduleDeadlines:Bool
    private var frames=[Frame](),events=[(time:Double,details:[String:Any])]()
    private var lastSample = -Double.infinity
    private var deadline:Double?,maximumEnd:Double?
    private var subscription:AnyCancellable?
    private var activeGame:String?
    private(set) var droppedSamples=0
    var bufferedFrames:Int {frames.count}
    var bufferedImageBytes:Int {frames.reduce(0){$0+$1.bytes}}
    init(root:URL=MoveEvidenceCapture.directory,byteLimit:Int64=5_000_000_000,
         memoryLimit:Int=80*1024*1024,scheduleDeadlines:Bool=true) {
        self.root=root;self.byteLimit=byteLimit;self.memoryLimit=memoryLimit;self.scheduleDeadlines=scheduleDeadlines
        recorder=DiagnosticRecorder(root:root,maximumPendingFrames:12)
        subscription=recorder.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    func offer(_ image:CGImage,at now:Double,online:Bool,context:[String:Any],reference:CGImage?,
               anchor:AutoGridDetector.TrackingAnchor?,anchorRevision:Int) {
        guard enabled,online else {stop(reason:"Camera buffering paused");return}
        expire(now:now)
        guard now-lastSample>=0.5 else {return}
        lastSample=now
        let frame=Frame(image:image,time:now,context:context,reference:reference,anchor:anchor,anchorRevision:anchorRevision)
        frames.removeAll{now-$0.time>4}
        guard frame.bytes<=memoryLimit else {droppedSamples += 1;return}
        frames.append(frame)
        while bufferedImageBytes>memoryLimit || frames.count>9 {frames.removeFirst();droppedSamples += 1}
        if recorder.isCapturing {save(frame)}
    }
    func annotate(_ details:[String:Any],now:Double=ProcessInfo.processInfo.systemUptime) {
        guard enabled,!frames.isEmpty else {return}
        events.append((now,details));events.removeAll{now-$0.time>4}
        if events.count>64 {events.removeFirst(events.count-64)}
        if recorder.isCapturing {recorder.event("automatic analysis",details:details)}
    }
    /// Returns the archive path for correlation in the persistent timing journal.
    /// Overlapping triggers share a clip, capped at 12 seconds after its first trigger.
    func trigger(_ event:[String:Any],now:Double)->String? {
        guard enabled else {return nil}
        expire(now:now)
        let game=event["game"].map { String(describing:$0) }
        if recorder.isCapturing,game != activeGame {stop(reason:"Game changed")}
        if recorder.isCapturing {
            deadline=min(now+3,maximumEnd ?? now+3)
            recorder.event("move evidence trigger",details:event);scheduleExpiry()
            return recorder.folder?.path
        }
        guard recorder.canStart else {status="Previous move capture is finishing; this trigger could not start another clip.";return nil}
        frames.removeAll{now-$0.time>4}
        guard !frames.isEmpty else {status="No buffered camera images were available for the unusual move.";return nil}
        do {
            let used=try storedBytes()
            // Leave room for manifests/failure records, which are deliberately
            // written even when an archive reaches its payload limit.
            guard byteLimit-used>1_000_000 else {status="Automatic captures paused: 5 GB storage allowance reached. Saved clips are retained.";return nil}
            var context:[String:Any]=["kind":"automatic move evidence","trigger":event,
                "capturePolicy":"Lossless full-resolution PNG, at most 2 samples/second; 4 seconds before and 3 seconds after a trigger, subject to memory/storage/writer limits. Overlapping triggers extend the clip up to 12 seconds after the first trigger.",
                "preSecondsAvailable":max(0,now-frames[0].time),"preFrameCount":frames.count,
                "bufferImageByteLimit":memoryLimit,"droppedBufferSamples":droppedSamples,
                "totalArchiveByteLimit":byteLimit,"samplesPerSecond":2,"labelsAreGroundTruth":false]
            for key in ["appVersion","appBuild","sourceHash"] {context[key]=event[key]}
            try recorder.start(context:context,byteLimit:byteLimit-used-1_000_000)
            activeGame=game;deadline=now+3;maximumEnd=now+12
            for frame in frames {save(frame)}
            for entry in events where now-entry.time<=4 {recorder.event("automatic analysis",details:entry.details)}
            recorder.event("move evidence trigger",details:event)
            status="Saving an unusual move and its surrounding camera frames."
            scheduleExpiry()
            return recorder.folder?.path
        } catch {status="Automatic move capture failed: \(error.localizedDescription)";return nil}
    }
    private func storedBytes() throws -> Int64 {
        guard FileManager.default.fileExists(atPath:root.path) else {return 0}
        var enumerationError:Error?
        guard let walker=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.fileSizeKey,.isRegularFileKey],
            errorHandler:{_,error in enumerationError=error;return false}) else {return byteLimit}
        var bytes:Int64=0
        for case let url as URL in walker {
            let info=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
            if info.isRegularFile==true {bytes += Int64(info.fileSize ?? 0)}
        }
        if let enumerationError {throw enumerationError}
        return bytes
    }
    private func save(_ frame:Frame) {
        _=recorder.capture(frame.image,at:frame.time,context:frame.context,reference:frame.reference,
                         anchor:frame.anchor,anchorRevision:frame.anchorRevision)
    }
    private func scheduleExpiry() {
        guard scheduleDeadlines else {return}
        DispatchQueue.main.asyncAfter(deadline:.now()+3.05) { [weak self] in
            self?.expire(now:ProcessInfo.processInfo.systemUptime)
        }
    }
    private func expire(now:Double) {
        if let deadline,now>=deadline {
            recorder.stop(reason:"Automatic move evidence window complete")
            self.deadline=nil;maximumEnd=nil;activeGame=nil
            status="Unusual move captured; saved clips stay on this Mac."
        }
    }
    func stop(reason:String) {
        if recorder.isCapturing {recorder.stop(reason:reason)}
        deadline=nil;maximumEnd=nil;activeGame=nil;frames=[];events=[];lastSample = -Double.infinity
    }
    func closeForExit() {
        recorder.closeForExit();frames=[];events=[];deadline=nil;maximumEnd=nil
    }
}
