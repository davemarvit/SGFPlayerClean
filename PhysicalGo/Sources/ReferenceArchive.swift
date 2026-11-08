import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// One atomic file pairs reference pixels with their calibration. Saving never
/// installs an occupied frame as a baseline; samples retain their separate roles.
struct ReferenceArchive {
    struct Snapshot {
        let image:CGImage
        let referenceCalibration:BoardCalibration
        let calibration:BoardCalibration
        let cameraID:String?
        let cameraName:String
        let enabled:Bool
        let savedAt:Date
    }
    struct Sample {
        let reference:Snapshot
        let frame:CGImage?
        let turns:Int?
        let threshold:Double?
    }
    private struct Payload:Codable {
        let version:Int
        let png:Data
        let referenceCalibration:BoardCalibration
        let calibration:BoardCalibration
        let cameraID:String?
        let cameraName:String
        let enabled:Bool
        let savedAt:Date
    }
    let url:URL
    static var standard:ReferenceArchive {
        let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        return ReferenceArchive(url:root.appendingPathComponent("Physical Go/EmptyBoardReference.plist"))
    }
    enum ArchiveError:LocalizedError {
        case invalid, noReference
        var errorDescription:String? {
            switch self {
            case .invalid:return "The saved reference has invalid or mismatched image/calibration data."
            case .noReference:return "This sample has no empty-board reference."
            }
        }
    }
    private static func validated(_ calibration:BoardCalibration)->BoardCalibration? {
        BoardCalibration(size:calibration.size,corners:calibration.corners)
    }
    private static func decodeImage(_ data:Data)throws->CGImage {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil),
              image.width>=100,image.height>=100,image.width<=8192,image.height<=8192 else { throw ArchiveError.invalid }
        return image
    }
    func save(image:CGImage,referenceCalibration:BoardCalibration,calibration:BoardCalibration,cameraID:String?,cameraName:String,enabled:Bool=true)throws {
        guard referenceCalibration.size==calibration.size,
              Self.validated(referenceCalibration) != nil,Self.validated(calibration) != nil else { throw ArchiveError.invalid }
        let data=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else { throw ArchiveError.invalid }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { throw ArchiveError.invalid }
        let payload=Payload(version:1,png:data as Data,referenceCalibration:referenceCalibration,calibration:calibration,
            cameraID:cameraID,cameraName:cameraName,enabled:enabled,savedAt:Date())
        let encoder=PropertyListEncoder();encoder.outputFormat = .binary
        let encoded=try encoder.encode(payload)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try encoded.write(to:url,options:.atomic)
    }
    func load()throws->Snapshot? {
        guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        let payload=try PropertyListDecoder().decode(Payload.self,from:Data(contentsOf:url))
        guard payload.version==1,let referenceCal=Self.validated(payload.referenceCalibration),
              let currentCal=Self.validated(payload.calibration),referenceCal.size==currentCal.size else { throw ArchiveError.invalid }
        return Snapshot(image:try Self.decodeImage(payload.png),referenceCalibration:referenceCal,calibration:currentCal,
            cameraID:payload.cameraID,cameraName:payload.cameraName,enabled:payload.enabled,savedAt:payload.savedAt)
    }
    func disableAutomaticReuse()throws {
        guard FileManager.default.fileExists(atPath:url.path) else { return }
        let old=try PropertyListDecoder().decode(Payload.self,from:Data(contentsOf:url))
        guard old.enabled else { return }
        let updated=Payload(version:old.version,png:old.png,referenceCalibration:old.referenceCalibration,
            calibration:old.calibration,cameraID:old.cameraID,cameraName:old.cameraName,enabled:false,savedAt:old.savedAt)
        let encoder=PropertyListEncoder();encoder.outputFormat = .binary
        try encoder.encode(updated).write(to:url,options:.atomic)
    }
    static func readSample(_ folder:URL)throws->Sample {
        struct Metadata:Decodable {
            let calibration:BoardCalibration?
            let referenceCalibration:BoardCalibration?
            let source:String?
            let cameraID:String?
            let displayQuarterTurns:Int?
            let threshold:Double?
            let detectionMode:String?
        }
        let metadata=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
        let referenceURL=folder.appendingPathComponent("empty-reference.png")
        guard FileManager.default.fileExists(atPath:referenceURL.path),metadata.detectionMode != "localAppearance" else { throw ArchiveError.noReference }
        guard let savedCal=metadata.calibration,let current=validated(savedCal),
              let reference=validated(metadata.referenceCalibration ?? savedCal),current.size==reference.size else { throw ArchiveError.invalid }
        let image=try decodeImage(Data(contentsOf:referenceURL))
        let frameURL=folder.appendingPathComponent("frame.png")
        let frame=FileManager.default.fileExists(atPath:frameURL.path) ? try decodeImage(Data(contentsOf:frameURL)) : nil
        if let frame,frame.width != image.width || frame.height != image.height { throw ArchiveError.invalid }
        return Sample(reference:Snapshot(image:image,referenceCalibration:reference,calibration:current,
            cameraID:metadata.cameraID,cameraName:metadata.source ?? "Saved sample",enabled:true,savedAt:Date()),
            frame:frame,turns:metadata.displayQuarterTurns,threshold:metadata.threshold)
    }
}
