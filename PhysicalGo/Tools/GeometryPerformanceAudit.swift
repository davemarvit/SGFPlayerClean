import Foundation
import ImageIO

/// Measures recognition on existing images. Image decoding and JSON encoding
/// are outside the measured interval; every repetition must return identical evidence.
@main struct GeometryPerformanceAudit {
    struct Frame:Decodable {
        let id:String,image:String,reference:String
        let calibration:BoardCalibration,referenceCalibration:BoardCalibration
        let threshold:Double
    }
    static func main() throws {
        setbuf(stdout,nil)
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        let repetitions=Int(CommandLine.arguments[3])!
        precondition(repetitions>0)
        func load(_ path:String)throws->GrayFrame {
            guard let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(source,0,nil),let frame=GrayFrame(image:image) else {
                throw NSError(domain:"GeometryPerformanceAudit",code:1)
            }
            return frame
        }
        func value<T:Encodable>(_ v:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(v),options:.fragmentsAllowed)}
        var rows=[[String:Any]]()
        for f in frames {
            let frame=try load(f.image),reference=try load(f.reference)
            var durations=[Double](),canonical:Data?,evidence:[String:Any]=[:]
            // One unmeasured warmup per image makes repeated before/after
            // comparisons less dependent on one-time runtime initialization.
            for run in 0...repetitions {
                let start=ProcessInfo.processInfo.systemUptime
                guard let view=BoardDetector.detect(frame:frame,reference:reference,calibration:f.calibration,
                    threshold:f.threshold,referenceCalibration:f.referenceCalibration) else {throw NSError(domain:"GeometryPerformanceAudit",code:2)}
                let elapsed=ProcessInfo.processInfo.systemUptime-start
                evidence=["readings":try value(view.readings),"footprints":try value(view.footprints),
                    "placementFits":try value(view.placementFits),"centeringEvidence":try value(view.centeringEvidence),
                    "notice":view.notice as Any? ?? NSNull(),"lightingBlocked":view.lightingBlocked,
                    "lightingAdjusted":view.lightingAdjusted,"lightingField":try value(view.lightingField)]
                let bytes=try JSONSerialization.data(withJSONObject:evidence,options:.sortedKeys)
                if let canonical {precondition(canonical==bytes,"Non-deterministic recognition for \(f.id)")} else {canonical=bytes}
                if run>0 {durations.append(elapsed)}
            }
            rows.append(["id":f.id,"seconds":durations,"evidence":evidence])
            print(f.id,durations.sorted()[durations.count/2])
        }
        try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
    }
}
