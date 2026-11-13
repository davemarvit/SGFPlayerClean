import Foundation
import ImageIO

@main struct HandStonePipelineTests {
    struct Meta:Decodable {let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double}
    static func main()throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ ok:Bool,_ text:String) {checks+=1;if !ok {print("FAIL: \(text)")};precondition(ok,text)}
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/A18HandOutline")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:root.appendingPathComponent("sample.json")))
        func photo(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let reference=GrayFrame(image:photo("reference.png"))!
        let before=photo("before.png"),hand=photo("hand.png"),after=photo("after.png")
        let expected=BoardDetector.detect(frame:GrayFrame(image:before)!,reference:reference,calibration:meta.calibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!.signature
        var tracker=HandOutlineTracker(),time=0.0
        func process(_ image:CGImage)->CameraAnalysisPipeline.Output {
            time+=0.21
            let output=CameraAnalysisPipeline.process(.init(target:image,calibration:meta.calibration,threshold:meta.threshold,
                reference:reference,referenceCalibration:meta.referenceCalibration,straighten:false,longAxisRows:false,
                checkStoneAspect:false,previousStoneCount:0,pendingAxis:nil,trackingAnchor:nil,alignmentExpected:expected,
                checkAlignment:false,trackingState:EstablishedStoneTracker(),trackingExpected:expected,trackingContext:"test",
                trackingManualPoints:[],trackingFresh:true,trackingTime:time,checkHands:true,handTracking:tracker))
            tracker=output.handTracking;return output
        }
        // Repeated photographs test pipeline wiring; the separate sampled
        // sequence test retains original camera timestamps and exit labels.
        for _ in 0..<6 {_=process(before)}
        for _ in 0..<2 {check(process(hand).handObstructed==true,"Actual placing hand bypassed the pipeline gate")}
        var last=process(after)
        for _ in 0..<4 {last=process(after)}
        check(last.handObstructed==false,"New white stone kept the pipeline hand gate latched")
        check(last.result?.signature[17] == .white,"Hand clearance lost the independently detected A18 stone")
        let sample=HandOutlineSampling.sample(GrayFrame(image:after)!,calibration:meta.calibration,observation:last.rawResult)
        check(sample.verifiedWhiteStones.contains{abs($0.x-17)<0.1 && abs($0.y)<0.1},"Current A18 shape/core did not reach outline tracking")
        check(HandOutlineSampling.sample(GrayFrame(image:after)!,calibration:meta.calibration).whiteStones.isEmpty,"Missing observation reused stale stone masks")
        var weak=BoardObservation(readings:last.rawResult!.readings.map{.init(row:$0.row,col:$0.col,occupancy:$0.occupancy,confidence:0.5,delta:$0.delta)},size:19)
        weak.footprints=last.rawResult!.footprints
        check(HandOutlineSampling.sample(GrayFrame(image:after)!,calibration:meta.calibration,observation:weak).whiteStones.isEmpty,"Uncertain readings supplied clearance masks")
        print("PASS: \(checks) photographed hand/stone pipeline checks: placing hand blocked, new white stone clears, current shape/core required, stale and weak evidence rejected")
    }
}
