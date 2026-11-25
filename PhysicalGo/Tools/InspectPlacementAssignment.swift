// Offline retained-frame diagnostic; no camera, app or device access.
@testable import PhysicalGoTestRuntime
import Foundation
import CoreGraphics
import ImageIO

@main struct InspectR16 {
    struct Meta:Decodable {let currentCalibration:BoardCalibration;let referenceCalibration:BoardCalibration}
    struct Evidence:Encodable {
        let readings:[IntersectionReading]
        let footprints:[StoneFootprint]
        let placementFits:[StoneFootprint]
        let placementOffsets:[Int:Double]
        let assignmentOffsets:[Int:Double]
    }
    static func main() throws {
        let args=CommandLine.arguments
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        func load(_ path:String)->GrayFrame {
            let src=CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil)!
            return GrayFrame(image:CGImageSourceCreateImageAtIndex(src,0,nil)!)!
        }
        #if TOUCHING_BLACK_CANDIDATE
        let observation=CandidateBoardDetector.detect(frame:load(args[2]),reference:load(args[3]),calibration:meta.currentCalibration,threshold:0.13,referenceCalibration:meta.referenceCalibration)!
        #else
        let observation=BoardDetector.detect(frame:load(args[2]),reference:load(args[3]),calibration:meta.currentCalibration,threshold:0.13,referenceCalibration:meta.referenceCalibration)!
        #endif
        let evidence=Evidence(readings:observation.readings,footprints:observation.footprints,placementFits:observation.placementFits,placementOffsets:observation.placementOffsets,assignmentOffsets:observation.assignmentOffsets)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(evidence).write(to:URL(fileURLWithPath:args[4]))
        for point in [22,41,59,60,61] {
            let r=observation.readings[point]
            print("Point \(point): \(r.occupancy) confidence \(r.confidence) rawOffset \(String(describing:observation.placementOffsets[point])) assignmentOffset \(String(describing:observation.assignmentOffsets[point]))")
            for shape in observation.footprints+observation.placementFits where shape.row*19+shape.col==point {print(shape)}
        }
    }
}
