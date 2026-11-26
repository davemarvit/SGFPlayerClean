import Foundation
import CryptoKit

/// The wood edge is independent of the printed grid calibration. Adding it to
/// BoardCalibration would change cameraContext and invalidate laser bindings.
struct WoodenBoardPerimeter: Codable, Equatable {
    let schemaVersion:Int
    let cameraID:String
    let referenceCalibrationSHA256:String
    let referenceImageSHA256:String
    let imageWidth:Int
    let imageHeight:Int
    let boundary:HandBoardBoundary

    enum Snapshot:Equatable {
        case absent
        case verified(HandBoardBoundary)
        case invalid(String)

        var boundary:HandBoardBoundary? {
            if case .verified(let boundary)=self {return boundary};return nil
        }
        var failure:String? {
            if case .invalid(let reason)=self {return reason};return nil
        }
    }

    static let requiredSettingKey="PhysicalGo.woodenBoardPerimeterRequired"
    static var defaultURL:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Physical Go/wooden-board-perimeter.json")
    }
    static func calibrationSHA256(_ calibration:BoardCalibration)->String? {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        guard let data=try? encoder.encode(calibration) else {return nil}
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    private static func isDigest(_ value:String)->Bool {
        value.count==64 && value.utf8.allSatisfy{(48...57).contains($0) || (97...102).contains($0)}
    }
    var isValid:Bool {
        schemaVersion==1 && !cameraID.isEmpty && Self.isDigest(referenceCalibrationSHA256) &&
        Self.isDigest(referenceImageSHA256) && (1...16384).contains(imageWidth) && (1...16384).contains(imageHeight) &&
        HandBoardBoundary(size:boundary.size,vertices:boundary.vertices)==boundary
    }
    func snapshot(cameraID:String,referenceCalibration:BoardCalibration,width:Int,height:Int)->Snapshot {
        guard isValid else {return .invalid("Wooden board perimeter profile is invalid")}
        guard self.cameraID==cameraID else {return .invalid("Wooden board perimeter belongs to another camera")}
        guard width==imageWidth,height==imageHeight else {return .invalid("Wooden board perimeter image size changed")}
        guard boundary.size==referenceCalibration.size,
              Self.calibrationSHA256(referenceCalibration)==referenceCalibrationSHA256 else {
            return .invalid("Wooden board perimeter needs verification for this grid reference")
        }
        // Canonical grid coordinates follow the current independently checked
        // grid transform. The profile never supplies alignment or hand clearance.
        return .verified(boundary)
    }
    func save(to url:URL)throws {
        guard isValid else {throw CocoaError(.fileWriteInapplicableStringEncoding)}
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let data=try encoder.encode(self)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
    }
}

/// Read once outside camera processing. Present-but-invalid files remain a
/// visible unknown verdict; they never silently fall back to the old boundary.
struct WoodenBoardPerimeterStore {
    private let profile:WoodenBoardPerimeter?
    private let failure:String?
    init(url:URL?,required:Bool=false,onProfileLoaded:(()->Void)?=nil) {
        guard let url else {profile=nil;failure=required ? "Configured wooden board perimeter is missing":nil;return}
        do {
            let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
            guard let size=attributes[.size] as? NSNumber,size.intValue<=65536 else {
                profile=nil;failure="Wooden board perimeter file is too large";return
            }
            let value=try JSONDecoder().decode(WoodenBoardPerimeter.self,from:Data(contentsOf:url))
            guard value.isValid else {profile=nil;failure="Wooden board perimeter profile is invalid";return}
            profile=value;failure=nil;onProfileLoaded?()
        } catch let error as NSError where error.domain==NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(error.code) {
            profile=nil;failure=required ? "Configured wooden board perimeter is missing":nil
        } catch {
            profile=nil;failure="Wooden board perimeter could not be read"
        }
    }
    func snapshot(cameraID:String,referenceCalibration:BoardCalibration,width:Int,height:Int)->WoodenBoardPerimeter.Snapshot {
        if let failure {return .invalid(failure)}
        return profile?.snapshot(cameraID:cameraID,referenceCalibration:referenceCalibration,width:width,height:height) ?? .absent
    }
}
