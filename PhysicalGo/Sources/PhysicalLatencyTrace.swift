import Foundation
import Darwin

/// Optional text-only diagnostics. No trace field grants hardware/game authority.
/// A bounded number of small events may wait behind the utility writer; producers
/// never encode JSON, open files, or wait for writer capacity.
final class PhysicalLatencyTrace: @unchecked Sendable {
    struct Event: Encodable {
        let schemaVersion=1
        let source="native"
        let clockDomain:String
        let runID:String
        let event:String
        let uptimeSeconds:Double
        let unixSeconds:Double
        let fields:[String:String]
        let metrics:[String:Double]
        var eventSequence:Int=0
        var droppedEvents:Int=0
        var writerFailures:Int=0
    }
    typealias Writer = (Data) throws -> Void
    static let shared:PhysicalLatencyTrace? = configured()
    private static func configured()->PhysicalLatencyTrace? {
        guard let path=ProcessInfo.processInfo.environment["PHYSICAL_GO_LATENCY_TRACE_DIRECTORY"],
              path.hasPrefix("/"),path.utf8.count<=4096 else {return nil}
        let output=RotatingWriter(directory:URL(fileURLWithPath:path))
        return PhysicalLatencyTrace(writer:{try output.write($0)})
    }
    private let queue=DispatchQueue(label:"PhysicalGo.LatencyTrace",qos:.utility)
    private let slots:DispatchSemaphore
    private let drops=DispatchSemaphore(value:0)
    private let pending=DispatchGroup()
    private let writer:Writer
    private let runID=UUID().uuidString
    // Writer-queue ownership only.
    private var sequence=0,dropped=0,failures=0
    init(capacity:Int=256,writer:@escaping Writer) {
        slots=DispatchSemaphore(value:max(1,min(capacity,4096)));self.writer=writer
    }
    @discardableResult func record(_ event:String,fields:[String:String]=[:],metrics:[String:Double]=[:],
                                  uptime:Double=ProcessInfo.processInfo.systemUptime,
                                  unix:Double=Date().timeIntervalSince1970)->Bool {
        guard event.utf8.count<=80,fields.count<=24,metrics.count<=24,
              uptime.isFinite,unix.isFinite,
              fields.allSatisfy({$0.key.utf8.count<=64 && $0.value.utf8.count<=512}),
              metrics.allSatisfy({$0.key.utf8.count<=64 && $0.value.isFinite}) else {drops.signal();return false}
        guard slots.wait(timeout:.now()) == .success else {drops.signal();return false}
        let value=Event(clockDomain:"swift-systemUptime/"+runID,runID:runID,event:event,
                        uptimeSeconds:uptime,unixSeconds:unix,fields:fields,metrics:metrics)
        pending.enter()
        queue.async { [self] in
            defer {slots.signal();pending.leave()}
            // Bound drop accounting per accepted event too. Excess drops remain
            // in the semaphore and are reported by subsequent accepted events.
            for _ in 0..<4096 {if drops.wait(timeout:.now()) != .success {break};dropped+=1}
            sequence+=1
            var output=value;output.eventSequence=sequence;output.droppedEvents=dropped;output.writerFailures=failures
            do {var data=try JSONEncoder().encode(output);data.append(10);try writer(data)}
            catch {failures+=1} // Diagnostics cannot propagate into control flow.
        }
        return true
    }
    /// Tests/offline shutdown only. Never call from a game/camera/hardware path.
    func waitForTesting(seconds:Double=2)->Bool {pending.wait(timeout:.now()+seconds) == .success}

    private final class RotatingWriter {
        let directory:URL
        let limit=1_048_576
        private var lockDescriptor:Int32 = -1
        init(directory:URL) {self.directory=directory}
        deinit {if lockDescriptor>=0 {Darwin.close(lockDescriptor)}}
        func write(_ data:Data)throws {
            guard data.count<=32768 else {throw CocoaError(.fileWriteOutOfSpace)}
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            if lockDescriptor<0 {
                let fd=Darwin.open(directory.appendingPathComponent("native-latency.lock").path,O_CREAT|O_RDWR,0o600)
                guard fd>=0 else {throw CocoaError(.fileWriteUnknown)}
                guard flock(fd,LOCK_EX|LOCK_NB)==0 else {Darwin.close(fd);throw CocoaError(.fileWriteNoPermission)}
                lockDescriptor=fd
            }
            let current=directory.appendingPathComponent("native-latency.jsonl")
            let previous=directory.appendingPathComponent("native-latency.previous.jsonl")
            let bytes=(try? current.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
            if bytes+data.count>limit {
                if FileManager.default.fileExists(atPath:previous.path) {try FileManager.default.removeItem(at:previous)}
                if FileManager.default.fileExists(atPath:current.path) {try FileManager.default.moveItem(at:current,to:previous)}
            }
            if !FileManager.default.fileExists(atPath:current.path) {FileManager.default.createFile(atPath:current.path,contents:nil)}
            let file=try FileHandle(forWritingTo:current);defer {try? file.close()}
            try file.seekToEnd();try file.write(contentsOf:data)
        }
    }
}

/// Opt-in synchronous stage accounting. Never carry an instance across queues:
/// thread CPU excludes work performed by CI/Vision workers and the GPU. A wall
/// minus thread-CPU gap is not by itself proof of scheduling contention.
final class CameraStageTiming {
    struct Sample {
        let wall:Double
        let threadCPU:Double?
        static func read()->Sample {
            var value=timespec()
            let cpu=clock_gettime(CLOCK_THREAD_CPUTIME_ID,&value)==0
                ? Double(value.tv_sec)+Double(value.tv_nsec)/1_000_000_000:nil
            return Sample(wall:ProcessInfo.processInfo.systemUptime,threadCPU:cpu)
        }
    }
    static let enabled=ProcessInfo.processInfo.environment["PHYSICAL_GO_CAMERA_STAGE_TRACE"] == "1"
    static func start(_ event:String,capturedAt:Double?,fields:[String:String]=[:])->CameraStageTiming? {
        guard enabled,let trace=PhysicalLatencyTrace.shared else {return nil}
        return CameraStageTiming(event:event,capturedAt:capturedAt,fields:fields,trace:trace)
    }
    private let event:String,fields:[String:String],trace:PhysicalLatencyTrace
    private let clock:()->Sample
    private let began:Sample
    private var previous:Sample
    private var metrics:[String:Double]
    private var count=0,finished=false
    // Injectable clock/sink keep CPU accounting and event bounds testable without
    // sleeping, camera acquisition, application startup or global configuration.
    init(event:String,capturedAt:Double?,fields:[String:String]=[:],trace:PhysicalLatencyTrace,
         clock:@escaping ()->Sample=Sample.read) {
        self.event=event;self.fields=fields;self.trace=trace;self.clock=clock
        let now=clock();began=now;previous=now
        metrics=["stageStartUptime":now.wall]
        if let capturedAt {metrics["captureUptime"]=capturedAt}
    }
    func mark(_ name:String) {
        guard !finished,count<10,name.utf8.count<=40 else {return}
        let now=clock()
        metrics[name+"WallSeconds"]=now.wall-previous.wall
        if let current=now.threadCPU,let prior=previous.threadCPU,current>=prior {
            metrics[name+"ThreadCPUSeconds"]=current-prior
        }
        previous=now;count+=1
    }
    func finish() {
        guard !finished else {return};finished=true
        let now=clock()
        metrics["totalWallSeconds"]=now.wall-began.wall
        if let current=now.threadCPU,let prior=began.threadCPU,current>=prior {
            metrics["totalThreadCPUSeconds"]=current-prior
        }
        // At most 24 metrics (ten stages plus start/capture/total wall/CPU).
        trace.record(event,fields:fields,metrics:metrics)
    }
}
