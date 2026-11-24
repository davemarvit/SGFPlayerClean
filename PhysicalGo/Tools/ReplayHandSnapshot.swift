// Compile as a small offline runner against an existing shared regression runtime.
// Never opens camera, app UI, audio, serial, or live bridge files.
@testable import PhysicalGoTestRuntime
import Foundation
import ImageIO
import CryptoKit

@main struct ReplayHandSnapshot {
    struct Input:Decodable {
        let reference:String
        let target:String
        let calibration:BoardCalibration
        let threshold:Double
        let label:String
    }
    static func main()throws {
        guard CommandLine.arguments.count==3 else {
            throw NSError(domain:"Usage: ReplayHandSnapshot input.json output.json",code:1)
        }
        let source=URL(fileURLWithPath:CommandLine.arguments[1])
        let config=try JSONDecoder().decode(Input.self,from:Data(contentsOf:source))
        guard config.threshold.isFinite,(0.05...0.35).contains(config.threshold) else {
            throw NSError(domain:"Invalid threshold",code:2)
        }
        func image(_ path:String)throws->CGImage {
            guard let data=CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(data,0,nil) else {
                throw NSError(domain:"Unreadable saved image",code:3)
            }
            return image
        }
        func encoded<T:Encodable>(_ value:T?)throws->Any {
            guard let value else {return NSNull()}
            return try JSONSerialization.jsonObject(with:JSONEncoder().encode(value),options:.fragmentsAllowed)
        }
        func hash(_ path:String)throws->String {
            SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map{String(format:"%02x",$0)}.joined()
        }
        let referenceImage=try image(config.reference),target=try image(config.target)
        guard let reference=GrayFrame(image:referenceImage) else {throw NSError(domain:"Gray decode",code:4)}
        let expected=[Occupancy](repeating:.empty,count:config.calibration.size*config.calibration.size)
        var tracker=HandOutlineTracker(),time=0.0,rows=[[String:Any]]()
        // Four repeated photographs only initialize a known-clear diagnostic
        // baseline. This is not a replay of the live temporal tracker history.
        for (index,current) in ([CGImage](repeating:referenceImage,count:4)+[CGImage](repeating:target,count:3)).enumerated() {
            time+=0.2
            let output=CameraAnalysisPipeline.process(.init(target:current,calibration:config.calibration,
                threshold:config.threshold,reference:reference,referenceCalibration:config.calibration,
                straighten:false,longAxisRows:false,checkStoneAspect:false,previousStoneCount:0,pendingAxis:nil,
                trackingAnchor:nil,alignmentExpected:expected,checkAlignment:false,
                trackingState:EstablishedStoneTracker(),trackingExpected:expected,trackingContext:"offline-snapshot",
                trackingManualPoints:[],trackingFresh:true,trackingTime:time,checkHands:true,handTracking:tracker))
            tracker=output.handTracking
            rows.append(["input":index<4 ? "repeated_reference":"repeated_target",
                "syntheticTime":time,"pose":try encoded(output.handPose),
                "poseObstructed":output.handPose?.obstructed(size:config.calibration.size) as Any? ?? NSNull(),
                "handOutline":try encoded(output.handOutline),
                "handObstructed":output.handObstructed as Any? ?? NSNull(),
                "exposureFailure":output.exposureFailure,"lightingBlocked":output.result?.lightingBlocked as Any? ?? NSNull(),
                "detectedNonemptyPoints":output.rawResult?.readings.filter{$0.occupancy != .empty}.count ?? -1])
        }
        let report:[String:Any]=["kind":"offline_saved_snapshot_probe","label":config.label,"grantsMotion":false,
            "reference":config.reference,"referenceSHA256":try hash(config.reference),
            "target":config.target,"targetSHA256":try hash(config.target),"inputSHA256":try hash(source.path),
            "calibration":try encoded(config.calibration),"threshold":config.threshold,"rows":rows,
            "limitations":["Repeated saved photos and synthetic times; not the original temporal sequence.",
                "Known-clear reference assumption, empty expected board, fresh tracker initialization.",
                "Uses supplied calibration without native grid tracking; no alignment qualification is inferred.",
                "Native hand/lighting state, camera reference, threshold, expected board and exact stop pixels may differ.",
                "Apple Vision is evaluated on this OS/runtime now, not a stored historical model output."]]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(
            to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("Offline snapshot probe saved: \(config.label)")
    }
}
