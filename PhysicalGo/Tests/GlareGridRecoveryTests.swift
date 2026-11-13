import Foundation
import CoreGraphics
import ImageIO

@main struct GlareGridRecoveryTests {
    struct Anchor:Decodable {let calibration:BoardCalibration;let fittedGrid:BoardCalibration;let width:Int;let height:Int}
    struct Frame:Decodable {let image:String;let time:Double;let calibration:BoardCalibration}
    struct Metadata:Decodable {
        let calibration:BoardCalibration;let referenceCalibration:BoardCalibration
        let anchor:Anchor;let threshold:Double;let frames:[Frame];let expected:[Occupancy]
    }
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/GlareGridRecovery")
        let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:root.appendingPathComponent("metadata.json")))
        func image(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let anchor=AutoGridDetector.TrackingAnchor(calibration:meta.anchor.calibration,fittedGrid:meta.anchor.fittedGrid,
            frame:GrayFrame(width:meta.anchor.width,height:meta.anchor.height,pixels:Array(try Data(contentsOf:root.appendingPathComponent("anchor.gray")))))
        let reference=GrayFrame(image:image("reference.png"))!
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        var previous=meta.calibration,tracker=KnownEmptyLighting(),refinements=0
        for (index,item) in meta.frames.enumerated() {
            let frame=GrayFrame(image:image(item.image))!
            let before=BoardDetector.detect(frame:frame,reference:reference,calibration:item.calibration,
                threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            check(before.signature.filter{$0 == .uncertain}.count>18,"Fixture no longer reproduces the unreadable-board block")
            var report=[String:Any]()
            guard let aligned=AutoGridDetector.track(frame:frame,from:previous,anchor:anchor,expected:meta.expected,report:{report=$0}) else {
                fatalError("Retained occupied board was rejected")
            }
            if report["outcome"] as? String == "known grid refined from exposed outer rails" {refinements+=1}
            if index==0 {
                check(aligned != previous,"Coarse known-stone fallback retained the displaced grid")
                check(report["outcome"] as? String == "known grid refined from exposed outer rails","Expected fallback refinement was bypassed")
            }
            let raw=BoardDetector.detect(frame:frame,reference:reference,calibration:aligned,
                threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            let result=tracker.observe(raw,frame:frame,calibration:aligned,expected:meta.expected,
                context:"retained thirteen-move game",now:item.time,valid:true,appearanceThreshold:meta.threshold)
            print(item.image,"uncertain",before.signature.filter{$0 == .uncertain}.count,"→",result.signature.filter{$0 == .uncertain}.count)
            // The first captured frame retains one honest uncertainty; by the
            // second distinct frame the local learner has independent evidence.
            check(result.signature.filter{$0 == .uncertain}.count <= (index==0 ? 1:0),"Glare did not settle after alignment recovery")
            check(zip(result.signature,meta.expected).allSatisfy { $0 == $1 || ($0 == .uncertain && $1 == .empty) },"Grid refinement invented or lost a stone")
            check(AutoGridDetector.knownGridSupport(frame:frame,calibration:aligned,expected:meta.expected) != nil,"Refinement lacked independent outer-rail support")
            previous=aligned
        }
        check(refinements>=1,"No refinement occurred")
        let final=GrayFrame(image:image(meta.frames.last!.image))!
        for _ in 0..<12 {
            let repeated=AutoGridDetector.track(frame:final,from:previous,anchor:anchor,expected:meta.expected)
            check(repeated==previous,"Repeated stationary frame caused calibration drift")
        }
        // Saved labels cannot validate a blank camera image.
        let blank=GrayFrame(width:final.width,height:final.height,pixels:Array(repeating:170,count:final.width*final.height))
        check(AutoGridDetector.track(frame:blank,from:meta.calibration,anchor:anchor,expected:meta.expected)==nil,"Saved stones fabricated alignment in a blank image")
        print("PASS: \(checks) glare-grid recovery checks, \(meta.frames.count) distinct captured frames, fixed reference/thresholds and stationary-grid stability")
    }
}
