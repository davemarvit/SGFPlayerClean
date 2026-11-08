import Foundation
import CoreGraphics
import ImageIO

/// Replay the production detector against a saved sample, without opening a camera.
@main struct InspectSample {
    struct Metadata: Decodable {
        let boardSize: Int
        let calibration: BoardCalibration?
        let referenceCalibration: BoardCalibration?
        let detectionMode:String?
        let threshold: Double
        let readings: [IntersectionReading]
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "PhysicalGo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected a saved sample folder"])
        }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: folder.appendingPathComponent("sample.json")))
        guard let saved = metadata.calibration,
              let calibration = BoardCalibration(size: metadata.boardSize, corners: saved.corners) else {
            throw NSError(domain: "PhysicalGo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sample has no valid calibration"])
        }
        func load(_ name: String) throws -> GrayFrame {
            guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let frame = GrayFrame(image: image) else {
                throw NSError(domain: "PhysicalGo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot read \(name)"])
            }
            return frame
        }
        let frame = try load("frame.png")
        let reference = FileManager.default.fileExists(atPath:folder.appendingPathComponent("empty-reference.png").path) ? try load("empty-reference.png") : nil
        let observation:BoardObservation?
        if let reference,metadata.detectionMode != "localAppearance" {
            observation=BoardDetector.detect(frame:frame,reference:reference,calibration:calibration,threshold:metadata.threshold,referenceCalibration:metadata.referenceCalibration)
        } else { observation=BoardAppearanceDetector.detect(frame:frame,calibration:calibration,threshold:metadata.threshold) }
        guard let result=observation else {
            throw NSError(domain: "PhysicalGo", code: 4, userInfo: [NSLocalizedDescriptionKey: "Frame and reference dimensions differ"])
        }
        struct PointReport: Encodable {
            let row: Int; let col: Int; let coordinate: String; let occupancy: Occupancy
            let confidence: Double; let referenceMedian: Double?; let currentMedian: Double
            let deltaMedian: Double?; let deltaLow: Double?; let deltaHigh: Double?
        }
        func quantile(_ values: [Double], _ fraction: Double) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[min(sorted.count-1, Int(Double(sorted.count-1)*fraction))]
        }
        let letters = Array("ABCDEFGHJKLMNOPQRST")
        var points = [PointReport]()
        for reading in result.readings {
            var current = [Double](), base = [Double](), delta = [Double]()
            for dy in -4...4 { for dx in -4...4 where dx != 0 && dy != 0 && dx*dx+dy*dy <= 16 {
                let point = calibration.point(col: Double(reading.col)+Double(dx)*0.075, row: Double(reading.row)+Double(dy)*0.075)
                let basePoint=(metadata.referenceCalibration ?? calibration).point(col: Double(reading.col)+Double(dx)*0.075, row: Double(reading.row)+Double(dy)*0.075)
                if let c = frame.sample(point) {
                    current.append(c)
                    if let b = reference?.sample(basePoint) { base.append(b); delta.append(c-b) }
                }
            } }
            points.append(PointReport(row: reading.row, col: reading.col, coordinate: "\(letters[reading.col])\(calibration.size-reading.row)",
                occupancy: reading.occupancy, confidence: reading.confidence, referenceMedian: base.isEmpty ? nil : quantile(base,0.5), currentMedian: quantile(current,0.5),
                deltaMedian: delta.isEmpty ? nil : quantile(delta,0.5), deltaLow: delta.isEmpty ? nil : quantile(delta,0.1), deltaHigh: delta.isEmpty ? nil : quantile(delta,0.9)))
        }
        struct Report: Encodable {
            let width: Int; let height: Int; let threshold: Double
            let counts: [String: Int]; let matchesSavedClassifications: Bool
            let points: [PointReport]
            let placementOffsets:[Int:Double]
            let placementFits:[StoneFootprint]
        }
        let counts = Dictionary(uniqueKeysWithValues: Occupancy.allCases.map { state in (state.rawValue, result.signature.filter { $0 == state }.count) })
        let report = Report(width: frame.width, height: frame.height, threshold: metadata.threshold,
            counts: counts, matchesSavedClassifications: result.signature == metadata.readings.map(\.occupancy), points: points,placementOffsets:result.placementOffsets,placementFits:result.placementFits)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(report), encoding: .utf8)!)
    }
}
