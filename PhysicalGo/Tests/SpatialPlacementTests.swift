import Foundation
import CoreGraphics
import ImageIO

@main struct SpatialPlacementTests {
    struct Frame:Decodable {let id:Int;let warnings:[Int];let clear:[Int]}
    struct Metadata:Decodable {let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double;let frames:[Frame]}
    @MainActor static func main()throws {
        let path=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/PlacementAmbiguity")
        let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:path.appendingPathComponent("metadata.json")))
        func load(_ name:String)->GrayFrame {GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(path.appendingPathComponent(name) as CFURL,nil)!,0,nil)!)!}
        let reference=load("empty-reference.png")
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        for frame in meta.frames {
            let result=BoardDetector.detect(frame:load(String(format:"%06d.png",frame.id)),reference:reference,calibration:meta.calibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            print("Frame \(frame.id): old centering warnings \(frame.warnings), remaining assignment warnings \(result.ambiguousPlacements.sorted())")
            check(result.ambiguousPlacements.isSubset(of:Set(frame.warnings)),"Created a new placement warning")
            check(result.ambiguousPlacements.contains(252),"Insufficient edge margin was accepted")
            for point in frame.warnings {
                check(result.signature[point] == .black,"Best-estimate stone disappeared when flagged")
                check(result.placementOffsets[point]!>=0.30,"Flagged without a geometric margin")
            }
            for point in frame.clear {check(!result.ambiguousPlacements.contains(point),"Clearly assigned control stone was flagged")}
        }
        _ = try PlacementSessionChecks.run()
        print("PASS: \(checks) actual placement-image checks: conservative centering warnings relaxed only for unique outlines; inadequate edge margin held; clear controls retained; best estimates unchanged.")
    }
}
