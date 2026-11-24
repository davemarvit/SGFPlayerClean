import Foundation
import ImageIO

// Offline BoardDetector only. No camera, controller, persistence, or move authority.
struct Input: Decodable {
    let id: String
    let image: String
    let referenceImage: String
    let calibration: BoardCalibration
    let referenceCalibration: BoardCalibration
    let threshold: Double
}
struct Output: Encodable {
    let id: String
    let readings: [IntersectionReading]
    let footprints: [StoneFootprint]
    let placementFits: [StoneFootprint]
    let manualPoints: [Int]
    let lightingBlocked: Bool
    let lightingAdjusted: Bool
    let notice: String?
}
@main struct Replay {
    static func pixels(_ path: String) throws -> GrayFrame {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil),
              let image = CGImageSourceCreateImageAtIndex(source,0,nil),
              let frame = GrayFrame(image:image) else {
            throw NSError(domain:"FreshNegativeReplay",code:1,userInfo:[NSLocalizedDescriptionKey:"Cannot decode image: \(path)"])
        }
        return frame
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain:"FreshNegativeReplay",code:2,userInfo:[NSLocalizedDescriptionKey:"Expected one JSON input manifest"])
        }
        let input = try JSONDecoder().decode([Input].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        var rows = [Output]()
        for item in input {
            guard item.threshold.isFinite, item.threshold > 0,
                  item.calibration.size == item.referenceCalibration.size,
                  let observation = BoardDetector.detect(frame:try pixels(item.image),reference:try pixels(item.referenceImage),
                      calibration:item.calibration,threshold:item.threshold,referenceCalibration:item.referenceCalibration) else {
                throw NSError(domain:"FreshNegativeReplay",code:3,userInfo:[NSLocalizedDescriptionKey:"Detection failed: \(item.id)"])
            }
            rows.append(Output(id:item.id,readings:observation.readings,footprints:observation.footprints,
                placementFits:observation.placementFits,manualPoints:observation.manualPoints.sorted(),
                lightingBlocked:observation.lightingBlocked,lightingAdjusted:observation.lightingAdjusted,notice:observation.notice))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(rows))
    }
}
