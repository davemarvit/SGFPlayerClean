import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A frozen, unmodified camera observation shown during a correction session.
/// Only explicitly edited intersections become training labels; the remainder
/// of the interpreted board is never promoted to ground truth.
struct BoardCorrectionSnapshot {
    let id: UUID
    let capturedAt: Date
    let image: CGImage
    let reference: CGImage?
    let calibration: BoardCalibration
    let referenceCalibration: BoardCalibration?
    let observation: BoardObservation
    let threshold: Double
    let quarterTurns: Int
    let source: String
}

enum CorrectionArchive {
    static var directory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Physical Go/Corrections",isDirectory:true)
    }
    static func save(_ snapshot: BoardCorrectionSnapshot, edits: [Int: ManualBoardCorrections.Choice],
                     root: URL = directory) throws -> URL {
        let fm=FileManager.default
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let temporary=root.appendingPathComponent(".pending-\(snapshot.id.uuidString)",isDirectory:true)
        let destination=root.appendingPathComponent(snapshot.id.uuidString,isDirectory:true)
        try fm.createDirectory(at:temporary,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:temporary) }
        func image(_ image:CGImage,_ name:String) throws {
            guard let out=CGImageDestinationCreateWithURL(temporary.appendingPathComponent(name) as CFURL,UTType.png.identifier as CFString,1,nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(out,image,nil)
            guard CGImageDestinationFinalize(out) else { throw CocoaError(.fileWriteUnknown) }
        }
        func encoded<T: Encodable>(_ value:T) throws -> Any {
            try JSONSerialization.jsonObject(with:JSONEncoder().encode(value))
        }
        try image(snapshot.image,"camera.png")
        if let reference=snapshot.reference { try image(reference,"reference.png") }
        let n=snapshot.observation.size
        let actions=edits.sorted{$0.key<$1.key}.map { point,choice in
            ["point":point,"row":point/n,"col":point%n,"choice":choice.rawValue] as [String:Any]
        }
        let labels=actions.filter { $0["choice"] as? String != "automatic" }
        let metadata:[String:Any]=[
            "schemaVersion":1,"id":snapshot.id.uuidString,
            "capturedAt":ISO8601DateFormatter().string(from:snapshot.capturedAt),
            "correctedAt":ISO8601DateFormatter().string(from:Date()),
            "labelSource":"explicit user correction","coordinateSystem":"raw camera grid, zero-based row-major",
            "image":"camera.png","reference":snapshot.reference == nil ? NSNull() : "reference.png",
            "size":n,"width":snapshot.image.width,"height":snapshot.image.height,
            "calibration":try encoded(snapshot.calibration),
            "referenceCalibration":try snapshot.referenceCalibration.map {try encoded($0)} ?? NSNull(),
            "threshold":snapshot.threshold,"viewQuarterTurns":snapshot.quarterTurns,"source":snapshot.source,
            "rawReadings":try encoded(snapshot.observation.readings),
            "footprints":try encoded(snapshot.observation.footprints),
            "placementFits":try encoded(snapshot.observation.placementFits),
            "lightingBlocked":snapshot.observation.lightingBlocked,
            "actions":actions,"labels":labels,
            "appVersion":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") ?? "test",
            "sourceHash":Bundle.main.object(forInfoDictionaryKey:"PhysicalGoSourceHash") ?? "test"
        ]
        try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys])
            .write(to:temporary.appendingPathComponent("corrections.json"),options:.atomic)
        try fm.moveItem(at:temporary,to:destination)
        return destination
    }
}
