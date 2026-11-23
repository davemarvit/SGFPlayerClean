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
            var safety:CameraAnalysisPipeline.CameraSafety?
            let output=CameraAnalysisPipeline.process(.init(target:image,calibration:meta.calibration,threshold:meta.threshold,
                reference:reference,referenceCalibration:meta.referenceCalibration,straighten:false,longAxisRows:false,
                checkStoneAspect:false,previousStoneCount:0,pendingAxis:nil,trackingAnchor:nil,alignmentExpected:expected,
                checkAlignment:false,trackingState:EstablishedStoneTracker(),trackingExpected:expected,trackingContext:"test",
                trackingManualPoints:[],trackingFresh:true,trackingTime:time,checkHands:true,handTracking:tracker),safety:{safety=$0})
            check(safety != nil && safety!.handObstructed==output.handObstructed && safety!.exposureFailure==output.exposureFailure && safety!.lightingBlocked==output.result?.lightingBlocked && (safety!.aligned != nil)==(output.aligned != nil),"early broker verdict must match the full same-frame result")
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
        let edgeRoot=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/C1HandOutline")
        let edgeMeta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:edgeRoot.appendingPathComponent("sample.json")))
        func edgePhoto(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(edgeRoot.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let edgeAfter=edgePhoto("after.png"),edgeFrame=GrayFrame(image:edgeAfter)!,edgeBefore=GrayFrame(image:edgePhoto("before.png"))!
        let edgeReference=GrayFrame(image:edgePhoto("reference.png"))!
        let edgeRaw=BoardDetector.detect(frame:edgeFrame,reference:edgeReference,calibration:edgeMeta.calibration,threshold:edgeMeta.threshold,referenceCalibration:edgeMeta.referenceCalibration)!
        let edgePose=BoardHandDetector.pose(image:edgeAfter,calibration:edgeMeta.calibration)
        check(edgePose?.obstructed(size:19)==false,"Photographed C1 fixture is not hand-clear")
        let shape=edgeRaw.footprints.first{$0.row==16 && $0.col==18}!
        check(edgeRaw.readings[322].occupancy == .white && edgeRaw.readings[322].confidence>=0.99 && shape.quality>=0.90 && shape.quality<0.95,"Fixture no longer exercises the missed edge-stone outline")
        let edgeSample=HandOutlineSampling.sample(edgeFrame,calibration:edgeMeta.calibration,observation:edgeRaw)
        check(edgeSample.verifiedWhiteStones.contains{abs($0.x-18)<0.1 && abs($0.y-16)<0.2},"Confident C1 shape/core omitted from hand mask")
        // Reconstructed active track, not an archived live checkpoint: the
        // two photographs test clearance, not an inferred hand-exit time.
        var edgeTracker=HandOutlineTracker(checkpoint:.init(background:HandOutlineSampling.sample(edgeBefore,calibration:edgeMeta.calibration),active:true,edge:1,center:[18,16],direction:nil,appearance:nil))
        let first=edgeTracker.observe(edgeSample,pose:edgePose,at:0,source:"C1-photo")
        check(first.obstructed==true && first.estimate==nil,"Edge stone bypassed two-view clearance")
        let cleared=edgeTracker.observe(edgeSample,pose:edgePose,at:0.2,source:"C1-photo")
        check(cleared.obstructed==false && cleared.estimate==nil,"C1 stone kept a clear board latched or invented exit timing")
        func eligible(quality:Double=0.91,confidence:Double=1,offset:Double=0)->Bool {
            var raw=BoardObservation(readings:[.init(row:16,col:18,occupancy:.white,confidence:confidence,delta:0)],size:19)
            raw.footprints=[.init(row:16,col:18,center:.init(x:18+offset,y:15.88),radiusCol:0.4,radiusRow:0.376,quality:quality)]
            return !HandOutlineSampling.sample(edgeFrame,calibration:edgeMeta.calibration,observation:raw).whiteStones.isEmpty
        }
        check(!eligible(quality:0.89),"Weak edge outline supplied a clearance mask")
        check(!eligible(confidence:0.98),"Weak edge occupancy supplied a clearance mask")
        check(!eligible(offset:0.3),"Displaced edge fit supplied a clearance mask")
        print("PASS: \(checks) photographed hand/stone pipeline checks: placing hand blocked, new white stones clear, current shape/core required, stale and weak evidence rejected")
    }
}
