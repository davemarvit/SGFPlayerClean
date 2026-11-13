import Foundation
import CoreGraphics
import ImageIO

@main struct LightingInterruptionTests {
    struct Sample:Decodable {let image:String;let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double}
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/KnownPositionGlare")
        func image(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let samples=try JSONDecoder().decode([Sample].self,from:Data(contentsOf:root.appendingPathComponent("cases.json")))
        let reference=GrayFrame(image:image("reference.png"))!,clear=samples[2],glare=samples[0]
        var position=[Occupancy](repeating:.empty,count:361)
        position[60] = .black;position[180] = .black;position[300] = .white
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        func input(_ sample:Sample,_ now:Double,_ baseline:KnownEmptyLighting,context:String="same camera/reference/game",aligned:Bool=true,fresh:Bool=true) -> CameraAnalysisPipeline.Input {
            .init(target:image(sample.image),calibration:sample.calibration,threshold:sample.threshold,
                reference:reference,referenceCalibration:sample.referenceCalibration,straighten:false,
                longAxisRows:false,checkStoneAspect:false,previousStoneCount:3,pendingAxis:nil,trackingAnchor:nil,
                alignmentExpected:position,checkAlignment:!aligned,trackingState:EstablishedStoneTracker(),
                trackingExpected:position,trackingContext:"analysis revision \(now)",trackingManualPoints:[],
                trackingFresh:fresh,trackingTime:now,emptyLighting:baseline,lightingContext:context)
        }
        var baseline=KnownEmptyLighting()
        // Repeated photographs with synthetic timestamps exercise lifecycle
        // policy; these are not claimed to be a recorded camera sequence.
        for step in 0..<10 {baseline=CameraAnalysisPipeline.process(input(clear,Double(step)*0.21,baseline)).emptyLighting}
        check(baseline.report.learned>300,"Pipeline failed to learn independent wood evidence")
        let lost=CameraAnalysisPipeline.process(input(glare,3,baseline,aligned:false))
        check(lost.result==nil,"Unaligned frame produced a board observation")
        baseline=lost.emptyLighting
        for step in 0..<3 {
            let output=CameraAnalysisPipeline.process(input(glare,1324+Double(step)*0.21,baseline))
            check(output.rawResult!.signature[109] == .uncertain,"Fixture no longer exercises learned glare correction")
            check(output.result!.signature[109] == (step<2 ? .uncertain:.empty),"Pipeline lost or prematurely reused the retained baseline")
            baseline=output.emptyLighting
        }
        for identity in ["different camera","different reference","different game"] {
            let changed=CameraAnalysisPipeline.process(input(glare,1325,baseline,context:identity))
            check(changed.result!.signature[109] == .uncertain,"Baseline leaked across lighting context")
        }
        let stopped=CameraAnalysisPipeline.process(input(glare,1325,baseline,fresh:false))
        check(stopped.result!.signature[109] == .uncertain,"Frozen frame used learned lighting")
        baseline=stopped.emptyLighting
        for step in 0..<3 {
            let output=CameraAnalysisPipeline.process(input(glare,1400+Double(step)*0.21,baseline))
            check(output.result!.signature[109] == (step<2 ? .uncertain:.empty),"Freeze/resume failed fresh revalidation")
            baseline=output.emptyLighting
        }
        print("PASS: \(checks) lighting pipeline checks: alignment outage, freeze, independent analysis revisions, three fresh confirmations and context isolation")
    }
}
