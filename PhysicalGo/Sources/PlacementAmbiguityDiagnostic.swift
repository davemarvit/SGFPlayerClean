import Foundation

/// Metadata only. This is an explanation of an existing rejection, never
/// evidence that can authorize a move, clearance, or laser operation.
struct PlacementAmbiguityDiagnostic: Codable {
    struct FrameIdentity: Codable {
        let streamEpoch:String
        let frameID:UInt64
        let capturedAtUptime:Double
        let arrivedAtUptime:Double
        let capturedAtUnix:Double
        let timestampSource:String
    }
    struct Reading: Codable {
        let point:Int
        let occupancy:String
        let confidence:Double
        let delta:Double
        let expected:String?
        let verified:String?
        let rejection:String?
    }
    struct Fit: Codable {
        let point:Int
        let centerX,centerY,radiusCol,radiusRow,quality,rawOffset:Double
        init(_ shape:StoneFootprint,size:Int) {
            point=shape.row*size+shape.col
            centerX=shape.center.x;centerY=shape.center.y
            radiusCol=shape.radiusCol;radiusRow=shape.radiusRow;quality=shape.quality
            rawOffset=max(abs(shape.center.x-Double(shape.col)),abs(shape.center.y-Double(shape.row)))
        }
    }
    let schemaVersion:Int
    let session:String
    let moveNumber:Int
    let generation:String
    let phase:String
    let atUnix,capturedAtUptime,observedAtUptime:Double
    let frame:FrameIdentity?
    let frameIdentityStatus:String
    let candidatePoint,boardSize,witnessesBeforeReset:Int
    let cameraContext,verifiedCameraContext:String?
    let verifiedSource:String
    let verifiedAtUptime:Double?
    let verifiedContextMatches:Bool
    let readings:[Reading]
    let footprints,placementFits:[Fit]
    let fitAttempts:[StoneFitAttempt]
    let omittedFitCount:Int
    let candidateGeometryStatus:String
    let assignmentOffsets:[Int:Double]
    let trackedAssignments:[Int:Int]
    let manualPoints:[Int]
    let note:String

    var episode:String {
        [session,String(moveNumber),generation,cameraContext ?? "unknown"].joined(separator:"|")
    }
    /// Class changes are representative; confidence jitter alone cannot fill
    /// the archive. The exact confidence is still retained for each selected event.
    var reasonSignature:String {
        ([String(candidatePoint),candidateGeometryStatus] + readings.compactMap {r in
            r.rejection.map {"\(r.point):\(r.occupancy):\($0)"}
        } + fitAttempts.filter {$0.row*boardSize+$0.col==candidatePoint}.map {"\($0.stage):\($0.reason)"}.sorted()).joined(separator:"|")
    }
    static func capture(observation:BoardObservation,point:Int,unresolvedNeighbors:[Int],
                        expected:[String],verified:[String]?,cameraContext:String?,verifiedContext:String?,
                        verifiedSource:String,verifiedAt:Double?,session:UUID,moveNumber:Int,generation:UUID,
                        phase:String,now:Double,wall:Double,witnesses:Int,frame:FrameIdentity?,assignmentOffsets:[Int:Double]?=nil)->Self {
        let size=observation.size,row=point/size,col=point%size
        let local=Set((max(0,row-1)...min(size-1,row+1)).flatMap {r in
            (max(0,col-1)...min(size-1,col+1)).map {r*size+$0}
        })
        // The live controller supplies its already-computed assignment result.
        // Standalone diagnostic callers may calculate it here when absent.
        let offsets=assignmentOffsets ?? observation.assignmentOffsets(confirmedBoard:expected.compactMap(Occupancy.init(rawValue:)))
        let blocked=Set(unresolvedNeighbors)
        let readings=observation.readings.filter {local.contains($0.row*size+$0.col)}.map {r -> Reading in
            let p=r.row*size+r.col
            let reason=blocked.contains(p) ? (r.occupancy == .uncertain ? "uncertain_neighbor":"low_confidence_neighbor"):
                p==point && (offsets[p] ?? 0)>=0.30 ? "ambiguous_assignment":nil
            return Reading(point:p,occupancy:r.occupancy.rawValue,confidence:r.confidence,delta:r.delta,
                expected:expected.indices.contains(p) ? expected[p]:nil,
                verified:verified.flatMap {$0.indices.contains(p) ? $0[p]:nil},rejection:reason)
        }.sorted {$0.point<$1.point}
        let footprintShapes=observation.footprints.filter {local.contains($0.row*size+$0.col)}
        let placementShapes=observation.placementFits.filter {local.contains($0.row*size+$0.col)}
        // A malformed or unusually dense observation cannot make a large file.
        let footprints=Array(footprintShapes.prefix(64)).map {Fit($0,size:size)}
        let placementFits=Array(placementShapes.prefix(64)).map {Fit($0,size:size)}
        let localAttempts=observation.fitAttempts.filter {local.contains($0.row*size+$0.col)}
        let candidateFits=(footprints+placementFits).filter {$0.point==point}
        let geometry=candidateFits.isEmpty ? "no_admitted_fit":(offsets[point].map {$0>=0.30} == true ? "ambiguous_assignment":"admitted_fit")
        let captured=observation.capturedAt ?? now
        let matching=frame.flatMap {abs($0.capturedAtUptime-captured)<0.000001 ? $0:nil}
        return Self(schemaVersion:1,session:session.uuidString,moveNumber:moveNumber,generation:generation.uuidString,phase:phase,
            atUnix:wall,capturedAtUptime:captured,observedAtUptime:now,frame:matching,
            frameIdentityStatus:matching == nil ? "unavailable_or_capture_mismatch":"exact_capture_match",
            candidatePoint:point,boardSize:size,witnessesBeforeReset:witnesses,
            cameraContext:cameraContext,verifiedCameraContext:verifiedContext,verifiedSource:verifiedSource,
            verifiedAtUptime:verifiedAt,verifiedContextMatches:cameraContext != nil && cameraContext==verifiedContext,
            readings:readings,footprints:footprints,placementFits:placementFits,fitAttempts:Array(localAttempts.prefix(64)),
            omittedFitCount:max(0,footprintShapes.count-64)+max(0,placementShapes.count-64)+max(0,localAttempts.count-64),candidateGeometryStatus:geometry,
            assignmentOffsets:offsets.filter {local.contains($0.key)},
            trackedAssignments:observation.trackedAssignments.filter {local.contains($0.key)},
            manualPoints:observation.manualPoints.filter {local.contains($0)}.sorted(),
            note:"Fit-attempt receipts cover initial outlines and placement refinement, not every recovery path. Not a tracker checkpoint or raw image replay.")
    }
}

/// Called only on AIRecognitionTrace's utility queue. Two files, eight distinct
/// event signatures each. The first rejection survives ordinary trace rollover.
final class PlacementAmbiguityArchive {
    struct Episode: Codable {
        let schemaVersion:Int
        let episode:String
        var events:[PlacementAmbiguityDiagnostic]
        var representativeLimitReached:Bool
    }
    private let directory:URL
    private var current:Episode?
    private var loaded=false
    init(directory:URL) {self.directory=directory}
    @discardableResult func record(_ event:PlacementAmbiguityDiagnostic)throws->Bool {
        let file=directory.appendingPathComponent("placement-ambiguity.json")
        let previous=directory.appendingPathComponent("placement-ambiguity-previous.json")
        if !loaded {
            loaded=true
            if let attributes=try? FileManager.default.attributesOfItem(atPath:file.path),
               let size=attributes[.size] as? NSNumber,size.intValue<=2_000_000,
               let data=try? Data(contentsOf:file),let saved=try? JSONDecoder().decode(Episode.self,from:data),
               saved.schemaVersion==1,!saved.events.isEmpty,saved.events.count<=8 {current=saved}
        }
        let changingEpisode=current?.episode != event.episode
        var next=changingEpisode ? Episode(schemaVersion:1,episode:event.episode,events:[],representativeLimitReached:false):current!
        if next.events.contains(where:{$0.reasonSignature==event.reasonSignature}) {return false}
        if next.events.count>=8 {
            guard !next.representativeLimitReached else {return false}
            next.representativeLimitReached=true
        } else {next.events.append(event)}
        // Publish the in-memory checkpoint only after a successful atomic write.
        let data=try JSONEncoder().encode(next)
        guard data.count<=2_000_000 else {return false}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        if changingEpisode,let current {try JSONEncoder().encode(current).write(to:previous,options:.atomic)}
        try data.write(to:file,options:.atomic);current=next
        return true
    }
}
