import Foundation
import CoreGraphics
import ImageIO

@main struct PlacementAmbiguityDiagnosticTests {
    static func main() throws {
        var checks=0
        func check(_ result:Bool,_ message:String) {precondition(result,message);checks+=1}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("ambiguity-diagnostic-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let session=UUID(),baselineGeneration=UUID(),epoch=UUID().uuidString
        func sample(point:Int=41,neighbor:Int=59,occupancy:Occupancy = .empty,confidence:Double=0.75,
                    wall:Double=100,generation:UUID?=nil,matchingFrame:Bool=true,fit:Bool=false,
                    verifiedSource:String="fresh_board_confirmed")->PlacementAmbiguityDiagnostic {
            var readings=(0..<361).map {IntersectionReading(row:$0/19,col:$0%19,occupancy:.empty,confidence:1,delta:0)}
            readings[point] = .init(row:point/19,col:point%19,occupancy:.black,confidence:0.9666666666666667,delta:-0.4)
            readings[neighbor] = .init(row:neighbor/19,col:neighbor%19,occupancy:occupancy,confidence:confidence,delta:0.01)
            var observation=BoardObservation(readings:readings,size:19)
            observation.capturedAt=wall-0.12
            let shape=StoneFootprint(row:point/19,col:point%19,center:.init(x:Double(point%19),y:Double(point/19)-0.12),radiusCol:0.52,radiusRow:0.55,quality:0.7307114)
            observation.fitAttempts=[.init(row:point/19,col:point%19,stage:"outline",reason:"below_minimum_quality",minimumQuality:0.78,maskCount:0,best:shape)]
            if fit {observation.footprints=[shape]}
            observation.trackedAssignments=[neighbor:60];observation.manualPoints=[0]
            let frame=PlacementAmbiguityDiagnostic.FrameIdentity(streamEpoch:epoch,frameID:UInt64(wall),capturedAtUptime:wall-(matchingFrame ? 0.12:0.1),arrivedAtUptime:wall-0.08,capturedAtUnix:1_000_000+wall-0.12,timestampSource:"cameraPresentation")
            return .capture(observation:observation,point:point,unresolvedNeighbors:[neighbor],expected:Array(repeating:"empty",count:361),verified:Array(repeating:"empty",count:361),cameraContext:"same-grid",verifiedContext:"same-grid",verifiedSource:verifiedSource,verifiedAt:90,session:session,moveNumber:6,generation:generation ?? baselineGeneration,phase:"human",now:wall,wall:1_000_000+wall,witnesses:2,frame:frame)
        }
        let first=sample()
        check(first.frame?.frameID==100 && first.frameIdentityStatus=="exact_capture_match","Lost exact camera identity")
        check(first.readings.count==9 && first.readings.first(where:{$0.point==59})?.confidence==0.75,"Lost exact bounded neighbor confidence")
        check(first.candidateGeometryStatus=="no_admitted_fit" && first.footprints.isEmpty,"Missing outline was represented as a centered fit")
        check(first.fitAttempts.first?.reason=="below_minimum_quality" && abs(first.fitAttempts.first!.maxAxisOffset!-0.12)<1e-9,"Lost rejected quality/offset provenance")
        check(first.verifiedSource=="fresh_board_confirmed" && first.verifiedAtUptime==90 && first.verifiedContextMatches,"Lost verification provenance")
        check(first.trackedAssignments==[59:60] && first.manualPoints.isEmpty,"Local tracker/manual provenance was mis-scoped")
        let mismatch=sample(matchingFrame:false)
        check(mismatch.frame==nil && mismatch.frameIdentityStatus=="unavailable_or_capture_mismatch","Borrowed a newer frame identity")
        check(mismatch.episode==first.episode,"Missing identity rotated and discarded first evidence")
        check(sample(verifiedSource:"restored_saved_position").verifiedSource=="restored_saved_position","Saved verification was presented as a fresh checkpoint")
        let archive=PlacementAmbiguityArchive(directory:directory)
        check(try archive.record(first),"First ambiguity was not retained")
        for n in 1...1400 {check(try !archive.record(sample(confidence:n%2==0 ? 0.75:0.7777778,wall:100+Double(n))),"Confidence jitter displaced first event")}
        let changed=sample(occupancy:.uncertain,confidence:0.7777778,wall:2000)
        check(try archive.record(changed),"Changed uncertain-neighbor reason was not retained")
        for point in [40,42,58,60,22,23,24,25] {_ = try archive.record(sample(point:point,neighbor:point+1,wall:2100+Double(point)))}
        func load(_ file:String)throws->PlacementAmbiguityArchive.Episode {
            try JSONDecoder().decode(PlacementAmbiguityArchive.Episode.self,from:Data(contentsOf:directory.appendingPathComponent(file)))
        }
        let current=try load("placement-ambiguity.json")
        check(current.events.count==8 && current.representativeLimitReached,"Distinct reasons escaped the eight-event bound")
        check(current.events.first?.atUnix==first.atUnix && current.events[1].readings.first(where:{$0.point==59})?.occupancy=="uncertain","First/changing evidence was lost")
        let reopened=PlacementAmbiguityArchive(directory:directory)
        check(try !reopened.record(first),"Restart overwrote the first saved event")
        check(try reopened.record(sample(wall:3000,generation:UUID())),"New generation did not start a separate episode")
        check(try load("placement-ambiguity-previous.json").events.first?.atUnix==first.atUnix,"Rotation lost previous first event")
        check(try FileManager.default.contentsOfDirectory(atPath:directory.path).count==2,"Archive created unbounded files")

        let traceDirectory=directory.appendingPathComponent("trace")
        let trace=AIRecognitionTrace(url:traceDirectory.appendingPathComponent("recognition-trace.json"))
        trace.recordPlacementAmbiguity(first)
        for index in 0...1400 {trace.record(["reason":"ordinary_frame","index":index])}
        trace.recordPlacementAmbiguity(changed)
        let deadline=Date().addingTimeInterval(5)
        var traceRows=[[String:Any]]()
        while Date()<deadline {
            if let data=try? Data(contentsOf:traceDirectory.appendingPathComponent("recognition-trace.json")),
               let rows=try? JSONSerialization.jsonObject(with:data) as? [[String:Any]],rows.last?["index"] as? Int==1400 {
                traceRows=rows;break
            }
            Thread.sleep(forTimeInterval:0.02)
        }
        let pinned=try JSONDecoder().decode(PlacementAmbiguityArchive.Episode.self,from:Data(contentsOf:traceDirectory.appendingPathComponent("placement-ambiguity.json")))
        check(traceRows.count==1200 && traceRows.first?["index"] as? Int==201,"Rolling trace did not exercise eviction")
        check(pinned.events.count==2 && pinned.events.first?.atUnix==first.atUnix,"Rolling trace evicted the pinned ambiguity evidence")

        // Optional retained-frame comparison exercises actual production vision
        // and confirms that collecting fit receipts changes no vision decisions.
        if let fixture=ProcessInfo.processInfo.environment["PHYSICAL_GO_R16_DIAGNOSTIC_FIXTURE"] {
            struct Meta:Decodable {let currentCalibration,referenceCalibration:BoardCalibration}
            struct Baseline:Decodable {let readings:[IntersectionReading];let footprints,placementFits:[StoneFootprint]}
            let base=URL(fileURLWithPath:fixture)
            let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:base.appendingPathComponent("metadata.json")))
            func image(_ name:String)->GrayFrame {
                let src=CGImageSourceCreateWithURL(base.appendingPathComponent(name) as CFURL,nil)!
                return GrayFrame(image:CGImageSourceCreateImageAtIndex(src,0,nil)!)!
            }
            let observation=BoardDetector.detect(frame:image("frame.png"),reference:image("reference.png"),calibration:meta.currentCalibration,threshold:0.13,referenceCalibration:meta.referenceCalibration)!
            let baseline=try JSONDecoder().decode(Baseline.self,from:Data(contentsOf:base.appendingPathComponent("baseline.json")))
            check(observation.readings==baseline.readings,"Diagnostic receipts changed occupancy/confidence")
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            check(try encoder.encode(observation.footprints)==encoder.encode(baseline.footprints),"Diagnostic receipts changed admitted footprints")
            check(try encoder.encode(observation.placementFits)==encoder.encode(baseline.placementFits),"Diagnostic receipts changed placement fits")
            for point in [41,60] {
                let attempts=observation.fitAttempts.filter {$0.row*19+$0.col==point}
                check(attempts.contains {$0.stage=="outline" && $0.reason=="below_minimum_quality" && ($0.best?.quality ?? 1)<0.78},"Missing cause of rejected R16 pair outline")
                check(attempts.contains {$0.stage=="placement" && $0.reason=="no_neighbor_masks"},"Missing cause of absent placement refinement")
            }
        }
        print("PASS: \(checks) placement-ambiguity diagnostic checks; bounded first/change evidence, provenance, frame identity, rotation and optional unchanged vision")
    }
}
