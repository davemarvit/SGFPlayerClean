import Foundation
import Combine
import CoreGraphics

/// A bounded, transient camera ring. Selected diagnostic events persist short clips.
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
    @Published private(set) var status="Buffers camera images during play; selected diagnostic events save clips automatically."
    let recorder:DiagnosticRecorder
    let root:URL
    @Published private(set) var storageBlocked=false
    private let byteLimit:Int64,memoryLimit:Int
    private let scheduleDeadlines:Bool
    private(set) var beforeSeconds=4
    private(set) var afterSeconds=3
    private(set) var framesPerSecond=2
    func configure(_ settings:DiagnosticSettings) {
        guard settings.valid else {return}
        if beforeSeconds != settings.beforeSeconds || afterSeconds != settings.afterSeconds || framesPerSecond != settings.framesPerSecond {
            stop(reason:"Diagnostic clip settings changed")
            beforeSeconds=settings.beforeSeconds;afterSeconds=settings.afterSeconds;framesPerSecond=settings.framesPerSecond
        }
        enabled=settings.enabled && (settings.unusualMoves || settings.byoyomiLosses)
    }
    private var frames=[Frame](),events=[(time:Double,details:[String:Any])]()
    private var lastSample = -Double.infinity
    private var deadline:Double?,maximumEnd:Double?
    private var subscription:AnyCancellable?
    private var stateSubscriptions=Set<AnyCancellable>()
    private var activeGame:String?
    private(set) var droppedSamples=0
    var bufferedFrames:Int {frames.count}
    var bufferedImageBytes:Int {frames.reduce(0){$0+$1.bytes}}
    init(root:URL=MoveEvidenceCapture.directory,byteLimit:Int64=10_000_000_000,
         memoryLimit:Int=256*1024*1024,scheduleDeadlines:Bool=true) {
        self.root=root;self.byteLimit=byteLimit;self.memoryLimit=memoryLimit;self.scheduleDeadlines=scheduleDeadlines
        let archiveStorage = root==Self.directory && byteLimit==DiagnosticArchiveStorage.defaultLimit
            ? DiagnosticArchiveStorage.shared:DiagnosticArchiveStorage(roots:[root],limit:byteLimit)
        recorder=DiagnosticRecorder(root:root,maximumPendingFrames:64,archiveStorage:archiveStorage)
        subscription=recorder.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        recorder.$state.filter{$0 == .failed}.sink { [weak self] _ in
            self?.storageBlocked=true
        }.store(in:&stateSubscriptions)
    }
    func offer(_ image:CGImage,at now:Double,online:Bool,context:@autoclosure ()->[String:Any],reference:CGImage?,
               anchor:AutoGridDetector.TrackingAnchor?,anchorRevision:Int) {
        guard enabled else {stop(reason:"Camera buffering disabled");return}
        expire(now:now)
        // Pausing play must not cut off an already-triggered post-roll.
        guard online || recorder.isCapturing else {stop(reason:"Camera buffering paused");return}
        guard now-lastSample+1e-7>=1/Double(framesPerSecond) else {return}
        lastSample=now
        let frame=Frame(image:image,time:now,context:context(),reference:reference,anchor:anchor,anchorRevision:anchorRevision)
        frames.removeAll{now-$0.time>Double(beforeSeconds)}
        guard frame.bytes<=memoryLimit else {droppedSamples += 1;return}
        frames.append(frame)
        while bufferedImageBytes>memoryLimit || frames.count>beforeSeconds*framesPerSecond+1 {frames.removeFirst();droppedSamples += 1}
        if recorder.isCapturing {save(frame)}
    }
    func annotate(_ details:@autoclosure ()->[String:Any],now:Double=ProcessInfo.processInfo.systemUptime) {
        guard enabled,!frames.isEmpty else {return}
        let details=details()
        events.append((now,details));events.removeAll{now-$0.time>Double(beforeSeconds)}
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
            deadline=min(now+Double(afterSeconds),maximumEnd ?? now+Double(afterSeconds))
            recorder.event("move evidence trigger",details:event);scheduleExpiry()
            return recorder.folder?.path
        }
        guard recorder.canStart else {status="Previous move capture is finishing; this trigger could not start another clip.";return nil}
        frames.removeAll{now-$0.time>Double(beforeSeconds)}
        guard !frames.isEmpty else {status="No buffered camera images were available for this diagnostic event.";return nil}
        do {
            // Reserve room for a full bounded clip before starting, including
            // pre-roll, the maximum extension, reference PNGs and metadata.
            let largest=Int64(frames.map(\.bytes).max() ?? 0)
            let referenceBytes=Int64(frames.compactMap{$0.reference}.map{$0.bytesPerRow*$0.height}.max() ?? 0)
            let clipBudget=max(64_000_000,largest*Int64((beforeSeconds+12)*framesPerSecond+2)+referenceBytes*2+8_000_000)
            storageBlocked=false
            var context:[String:Any]=["kind":"automatic move evidence","trigger":event,
                "capturePolicy":"Lossless full-resolution PNG, at most \(framesPerSecond) samples/second; \(beforeSeconds) seconds before and \(afterSeconds) seconds after a trigger, subject to camera/memory/storage/writer limits. Overlapping triggers extend the clip up to 12 seconds after the first trigger.",
                "requestedPreSeconds":beforeSeconds,"requestedPostSeconds":afterSeconds,
                "preSecondsAvailable":max(0,now-frames[0].time),"preFrameCount":frames.count,
                "bufferImageByteLimit":memoryLimit,"droppedBufferSamples":droppedSamples,
                "totalArchiveByteLimit":byteLimit,"samplesPerSecond":framesPerSecond,"labelsAreGroundTruth":false]
            for key in ["appVersion","appBuild","sourceHash"] {context[key]=event[key]}
            try recorder.start(context:context,byteLimit:clipBudget)
            activeGame=game;deadline=now+Double(afterSeconds);maximumEnd=now+12
            for frame in frames {save(frame)}
            for entry in events where now-entry.time<=Double(beforeSeconds) {recorder.event("automatic analysis",details:entry.details)}
            recorder.event("move evidence trigger",details:event)
            status="Saving a diagnostic event and its surrounding camera frames."
            scheduleExpiry()
            return recorder.folder?.path
        } catch {storageBlocked=true;status="Automatic move capture failed: \(error.localizedDescription)";return nil}
    }
    private func save(_ frame:Frame) {
        _=recorder.capture(frame.image,at:frame.time,context:frame.context,reference:frame.reference,
                         anchor:frame.anchor,anchorRevision:frame.anchorRevision)
    }
    private func scheduleExpiry() {
        guard scheduleDeadlines,let deadline else {return}
        DispatchQueue.main.asyncAfter(deadline:.now()+max(0,deadline-ProcessInfo.processInfo.systemUptime)+0.05) { [weak self] in
            self?.expire(now:ProcessInfo.processInfo.systemUptime)
        }
    }
    private func expire(now:Double) {
        if let deadline,now>=deadline {
            recorder.stop(reason:"Automatic move evidence window complete")
            self.deadline=nil;maximumEnd=nil;activeGame=nil
            status=recorder.state == .failed ? recorder.status:"Diagnostic clip finished; saved images stay on this Mac."
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
