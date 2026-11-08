import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct StoneCalibrationPhoto {
    let id: UUID
    let capturedAt: Date
    let image: CGImage
    let calibration: BoardCalibration
    let readings: [IntersectionReading]
    let labels: [Int:Occupancy]
    let stage: Int
}
struct StoneCalibrationSession {
    let id: UUID
    let size: Int
    let quarterTurns: Int
    let cameraID: String
    let originalReference: CGImage
    var photos: [StoneCalibrationPhoto] = []
    var pending: StoneCalibrationPhoto?
    var stage:Int {photos.count}
    var targets:[Int:Occupancy] {
        stage==0 ? [:] : StoneCalibrationPattern.stones(size:size,round:stage-1)
    }
    var labels:[Int:Occupancy] {
        if stage==0 {return StoneCalibrationPattern.labels(size:size,round:0).mapValues{_ in .empty}}
        return StoneCalibrationPattern.labels(size:size,round:stage-1)
    }
    func examples() -> [StoneAppearanceModel.Example] {
        guard let first=photos.first,let reference=GrayFrame(image:first.image) else {return []}
        return photos.flatMap {photo -> [StoneAppearanceModel.Example] in
            guard let frame=GrayFrame(image:photo.image) else {return []}
            return photo.labels.sorted{$0.key<$1.key}.compactMap {point,label in
                guard let features=StoneAppearanceFeatures.extract(frame:frame,reference:reference,
                    calibration:photo.calibration,referenceCalibration:first.calibration,point:point) else {return nil}
                let stones=photo.stage==0 ? [:] : StoneCalibrationPattern.stones(size:size,round:photo.stage-1)
                // The user confirmed the complete placement diagram. Keep training
                // labels limited to samples, but record its known neighborhood.
                let known=Dictionary(uniqueKeysWithValues:(0..<size*size).map{($0,stones[$0] ?? Occupancy.empty)})
                return StoneAppearanceModel.Example(point:point,label:label,features:features,
                    context:StoneNeighborContext.measure(point:point,size:size,known:known))
            }
        }
    }
}

enum StoneCalibrationArchive {
    static var directory: URL {CorrectionArchive.directory.deletingLastPathComponent().appendingPathComponent("Stone Calibration",isDirectory:true)}
    static func save(photo:StoneCalibrationPhoto,session:StoneCalibrationSession,root:URL=directory) throws -> URL {
        let fm=FileManager.default
        let folder=root.appendingPathComponent(session.id.uuidString,isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        let destination=folder.appendingPathComponent(photo.id.uuidString,isDirectory:true)
        // A retry after profile-write failure must not lose or replace a confirmed photo.
        if fm.fileExists(atPath:destination.appendingPathComponent("capture.json").path) {return folder}
        let temporary=folder.appendingPathComponent(".pending-\(photo.id.uuidString)",isDirectory:true)
        try fm.createDirectory(at:temporary,withIntermediateDirectories:false)
        defer {try? fm.removeItem(at:temporary)}
        guard let png=CGImageDestinationCreateWithURL(temporary.appendingPathComponent("camera.png") as CFURL,UTType.png.identifier as CFString,1,nil) else {throw CocoaError(.fileWriteUnknown)}
        CGImageDestinationAddImage(png,photo.image,nil)
        guard CGImageDestinationFinalize(png) else {throw CocoaError(.fileWriteUnknown)}
        func encode<T:Encodable>(_ x:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(x))}
        let metadata:[String:Any]=[
            "schemaVersion":1,"id":photo.id.uuidString,"session":session.id.uuidString,"stage":photo.stage,
            "capturedAt":ISO8601DateFormatter().string(from:photo.capturedAt),
            "confirmedAt":ISO8601DateFormatter().string(from:Date()),"labelSource":"user-confirmed calibration diagram and frozen photo",
            "coordinateSystem":"raw camera grid, zero-based row-major","size":session.size,"viewQuarterTurns":session.quarterTurns,
            "cameraID":session.cameraID,"image":"camera.png","width":photo.image.width,"height":photo.image.height,
            "referenceCapture":(session.photos.first?.id ?? photo.id).uuidString,
            "calibration":try encode(photo.calibration),"rawReadings":try encode(photo.readings),
            "confirmedDiagramStones":try encode(photo.stage==0 ? [:] : StoneCalibrationPattern.stones(size:session.size,round:photo.stage-1)),
            "labels":photo.labels.sorted{$0.key<$1.key}.map{["point":$0.key,"occupancy":$0.value.rawValue] as [String:Any]},
            "appVersion":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") ?? "test",
            "sourceHash":Bundle.main.object(forInfoDictionaryKey:"PhysicalGoSourceHash") ?? "test"
        ]
        try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]).write(to:temporary.appendingPathComponent("capture.json"),options:.atomic)
        try fm.moveItem(at:temporary,to:destination)
        return folder
    }
    /// Only confirmed stage folders participate; partial writes cannot be resumed.
    static func latestIncomplete(root:URL=directory)->URL? {
        let fm=FileManager.default
        let folders=(try? fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.contentModificationDateKey],options:.skipsHiddenFiles)) ?? []
        return folders.filter {folder in
            guard UUID(uuidString:folder.lastPathComponent) != nil,
                  !fm.fileExists(atPath:folder.appendingPathComponent("profile.json").path),
                  let children=try? fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) else {return false}
            return children.contains {fm.fileExists(atPath:$0.appendingPathComponent("capture.json").path)}
        }.max {a,b in
            ((try? a.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
            ((try? b.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
    }
    static func load(folder:URL,reference:CGImage,cameraID:String,calibration:BoardCalibration,turns:Int)throws->StoneCalibrationSession {
        struct Payload:Decodable {
            struct Label:Decodable {let point:Int;let occupancy:Occupancy}
            let schemaVersion:Int,id:UUID,session:UUID,stage:Int,size:Int,viewQuarterTurns:Int
            let capturedAt:String
            let cameraID:String?
            let calibration:BoardCalibration
            let rawReadings:[IntersectionReading]
            let labels:[Label]
        }
        func invalid()->NSError {NSError(domain:"StoneCalibration",code:2,userInfo:[NSLocalizedDescriptionKey:"The saved calibration does not match this board, camera, or reference. Start a new calibration instead."])}
        guard let id=UUID(uuidString:folder.lastPathComponent),let referenceFrame=GrayFrame(image:reference) else {throw invalid()}
        let children=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)
        var photos=[StoneCalibrationPhoto]()
        for child in children where UUID(uuidString:child.lastPathComponent) != nil {
            let d=try JSONDecoder().decode(Payload.self,from:Data(contentsOf:child.appendingPathComponent("capture.json")))
            guard d.schemaVersion==1,d.session==id,d.id.uuidString==child.lastPathComponent,(0...2).contains(d.stage),
                  d.size==calibration.size,d.viewQuarterTurns==turns,d.cameraID==nil || d.cameraID==cameraID,
                  d.calibration.size==calibration.size,d.calibration.corners.count==4,
                  zip(d.calibration.corners,calibration.corners).allSatisfy({hypot($0.x-$1.x,$0.y-$1.y)<0.008}),
                  let checked=BoardCalibration(size:d.size,corners:d.calibration.corners),
                  let source=CGImageSourceCreateWithURL(child.appendingPathComponent("camera.png") as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(source,0,nil),image.width==reference.width,image.height==reference.height,
                  let stamp=ISO8601DateFormatter().date(from:d.capturedAt),
                  d.rawReadings.count==d.size*d.size else {throw invalid()}
            var labels=[Int:Occupancy]()
            for label in d.labels {
                guard (0..<d.size*d.size).contains(label.point),label.occupancy != .uncertain,labels[label.point]==nil else {throw invalid()}
                labels[label.point]=label.occupancy
            }
            let expected=d.stage==0 ? StoneCalibrationPattern.labels(size:d.size,round:0).mapValues{_ in Occupancy.empty} : StoneCalibrationPattern.labels(size:d.size,round:d.stage-1)
            guard labels==expected else {throw invalid()}
            photos.append(StoneCalibrationPhoto(id:d.id,capturedAt:stamp,image:image,calibration:checked,readings:d.rawReadings,labels:labels,stage:d.stage))
        }
        photos.sort{$0.stage<$1.stage}
        guard !photos.isEmpty,photos.count<=3,photos.enumerated().allSatisfy({$0.offset==$0.element.stage}),
              let first=photos.first,let empty=GrayFrame(image:first.image) else {throw invalid()}
        // Also protect legacy archives without camera IDs: the confirmed empty
        // photo must agree with the current empty reference at the same grid.
        var deltas=[Double]()
        for r in 0..<calibration.size-1 {for c in 0..<calibration.size-1 {
            if let a=referenceFrame.patchMean(calibration.point(col:Double(c)+0.5,row:Double(r)+0.5)),
               let b=empty.patchMean(first.calibration.point(col:Double(c)+0.5,row:Double(r)+0.5)) {deltas.append(abs(a-b))}
        }}
        guard deltas.count>=20,StoneAppearanceFeatures.quantile(deltas,0.9)<0.08 else {throw invalid()}
        return StoneCalibrationSession(id:id,size:calibration.size,quarterTurns:turns,cameraID:cameraID,originalReference:reference,photos:photos)
    }
    static func saveProfile(_ profile:StoneAppearanceModel,session:StoneCalibrationSession,root:URL=directory)throws {
        struct Payload:Encodable {
            let schemaVersion=1
            let purpose="Experimental appearance ranges. No move dispatch or probability calibration."
            let model:StoneAppearanceModel
            let captures:[UUID]
            let examples:[StoneAppearanceModel.Example]
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let data=try encoder.encode(Payload(model:profile,captures:session.photos.map(\.id),examples:session.examples()))
        try data.write(to:root.appendingPathComponent(session.id.uuidString).appendingPathComponent("profile.json"),options:.atomic)
    }
}
