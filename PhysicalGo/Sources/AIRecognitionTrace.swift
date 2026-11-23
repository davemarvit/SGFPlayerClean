import Foundation

/// Bounded text-only flight recorder; disk IO never runs on the camera/UI path.
final class AIRecognitionTrace {
    private let queue=DispatchQueue(label:"PhysicalGo.AIRecognitionTrace",qos:.utility)
    private let url:URL
    private var entries=[[String:Any]]()
    private var pending=false
    init(url:URL) {self.url=url}
    func record(_ entry:[String:Any]) {
        queue.async { [self] in
            guard JSONSerialization.isValidJSONObject(entry) else {return}
            entries.append(entry)
            if entries.count>1200 {entries.removeFirst(entries.count-1200)}
            guard !pending else {return};pending=true
            queue.asyncAfter(deadline:.now()+1) { [self] in
                defer {pending=false}
                guard let data=try? JSONSerialization.data(withJSONObject:entries) else {return}
                try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
                try? data.write(to:url,options:.atomic)
            }
        }
    }
    /// Two bounded sampled-state snapshots, independent of continuous image
    /// recording. Encoding and IO stay off the camera and main queues.
    func recordHandStall(_ evidence:HandOutlineTracker.StallEvidence,calibration:BoardCalibration,
                         session:UUID?,moveNumber:Int?,atUnix:Double) {
        struct Snapshot:Encodable {
            let schemaVersion=1
            let atUnix:Double
            let session:UUID?
            let moveNumber:Int?
            let calibration:BoardCalibration
            let evidence:HandOutlineTracker.StallEvidence
        }
        let snapshot=Snapshot(atUnix:atUnix,session:session,moveNumber:moveNumber,
                              calibration:calibration,evidence:evidence)
        queue.async { [self] in
            let directory=url.deletingLastPathComponent()
            let current=directory.appendingPathComponent("hand-clearance-stall.json")
            let previous=directory.appendingPathComponent("hand-clearance-stall-previous.json")
            do {
                let data=try JSONEncoder().encode(snapshot)
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                if let old=try? Data(contentsOf:current) {try old.write(to:previous,options:.atomic)}
                try data.write(to:current,options:.atomic)
            } catch {
                record(["reason":"hand_clearance_diagnostic_write_failed","atUnix":atUnix,
                        "detail":error.localizedDescription])
            }
        }
    }

}
