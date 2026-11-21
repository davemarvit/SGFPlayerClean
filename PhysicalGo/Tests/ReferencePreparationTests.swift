import Foundation
import ImageIO

@main struct ReferencePreparationTests {
    @MainActor static func main() async throws {
        var checks=0
        func check(_ ok:Bool,_ why:String) {checks+=1;precondition(ok,why)}
        func same(_ a:BoardChroma?,_ b:BoardChroma?)->Bool {a?.red==b?.red && a?.green==b?.green}
        var seed:UInt64=123456789
        func byte()->UInt8 {seed=seed &* 6364136223846793005 &+ 1;return UInt8(truncatingIfNeeded:seed>>32)}
        for (width,height) in [(1,1),(1,11),(13,1),(2,2),(3,3),(17,23),(64,45)] {
            for color in [false,true] {
                let pixels=(0..<width*height).map{_ in byte()}
                let rgba=color ? (0..<width*height*4).map{_ in byte()}:nil
                let raw=GrayFrame(width:width,height:height,pixels:pixels,colorBytes:rgba)
                let prepared=raw.preparingPatchSamples()
                check(raw.preparedPatchBytes==0 && prepared.patchIdentity==raw.patchIdentity,"Preparation mutated the source or lost its identity")
                check(prepared.preparedPatchBytes==width*height*(color ? 8:2),"Reference cache size is wrong")
                var points=[ImagePoint(x:0,y:0),.init(x:1,y:1),.init(x:-0.01,y:0),.init(x:1.01,y:1),.init(x:.nan,y:0),.init(x:0,y:.infinity)]
                for y in 0..<height {for x in 0..<width {points.append(.init(x:Double(x)/Double(max(1,width-1)),y:Double(y)/Double(max(1,height-1))))}}
                for _ in 0..<500 {points.append(.init(x:Double(byte())/255,y:Double(byte())/255))}
                for point in points {
                    check(raw.patchMean(point)==prepared.patchMean(point),"Prepared luminance differs at a pixel, edge, or invalid coordinate")
                    check(same(raw.patchColor(point),prepared.patchColor(point)),"Prepared chroma differs at a pixel, edge, or invalid coordinate")
                }
                let scaled=prepared.scaledLuminance(by:0.8),adjusted=prepared.adjustedLuminance(.init(constant:1.05,x:0.02,y:-0.01,residual:0))
                check(scaled.patchIdentity != raw.patchIdentity && scaled.preparedPatchBytes==0,"Luminance scaling reused stale reference sums")
                check(adjusted.patchIdentity != raw.patchIdentity && adjusted.preparedPatchBytes==0,"Lighting adjustment reused stale reference sums")
                check(raw.preparingPatchSamples().preparingPatchSamples().preparedPatchBytes==prepared.preparedPatchBytes,"Repeated preparation duplicated cache storage")
            }
        }
        for level in [UInt8(0),10,30,31,255] {
            let raw=GrayFrame(width:3,height:3,pixels:Array(repeating:level,count:9),colorBytes:Array(repeating:level,count:36))
            let prepared=raw.preparingPatchSamples()
            check(same(raw.patchColor(.init(x:0.5,y:0.5)),prepared.patchColor(.init(x:0.5,y:0.5))),"Dark-color rejection boundary changed")
        }
        let large=GrayFrame(width:4_194_305,height:1,pixels:Array(repeating:127,count:4_194_305))
        check(large.preparingPatchSamples().preparedPatchBytes==0,"Optional reference cache exceeded its memory limit")

        struct Meta:Decodable {let calibration:BoardCalibration,referenceCalibration:BoardCalibration;let threshold:Double}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/A18HandOutline")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:fixture.appendingPathComponent("sample.json")))
        func photo(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(fixture.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let target=photo("after.png"),reference=GrayFrame(image:photo("reference.png"))!
        let pipeline=CameraAnalysisPipeline()
        func input(_ reference:GrayFrame?)->CameraAnalysisPipeline.Input {
            .init(target:target,calibration:meta.calibration,threshold:meta.threshold,reference:reference,
                referenceCalibration:meta.referenceCalibration,straighten:false,longAxisRows:false,checkStoneAspect:false,
                previousStoneCount:0,pendingAxis:nil,trackingAnchor:nil,alignmentExpected:[],checkAlignment:false,
                trackingState:EstablishedStoneTracker(),trackingExpected:[],trackingContext:"prepared reference test",
                trackingManualPoints:[],trackingFresh:true,trackingTime:ProcessInfo.processInfo.systemUptime)
        }
        func submit(_ ref:GrayFrame?) async -> CameraAnalysisPipeline.Output {
            await withCheckedContinuation { continuation in pipeline.submit(input(ref)) {continuation.resume(returning:$0)} }
        }
        func evidence(_ view:BoardObservation?)throws->Data {
            let view=view!,encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            return try encoder.encode(view.readings)+encoder.encode(view.footprints)+encoder.encode(view.placementFits)+encoder.encode(view.centeringEvidence)
        }
        let direct=try evidence(CameraAnalysisPipeline.process(input(reference)).result)
        let first=await submit(reference)
        check(try first.preparedReferenceBytes==0 && (evidence(first.result))==direct,"Cold reference preparation delayed or changed the first result")
        var warm=first
        for _ in 0..<40 where warm.preparedReferenceBytes==0 {
            try await Task.sleep(nanoseconds:20_000_000);warm=await submit(reference)
        }
        check(try warm.preparedReferenceBytes>0 && (evidence(warm.result))==direct,"Background-prepared reference was unavailable or changed recognition")
        let changed=reference.scaledLuminance(by:0.9)
        let expectedChanged=try evidence(CameraAnalysisPipeline.process(input(changed)).result)
        var replacement=await submit(changed)
        check(try replacement.preparedReferenceBytes==0 && (evidence(replacement.result))==expectedChanged,"A replacement reference reused stale cached pixels")
        for _ in 0..<40 where replacement.preparedReferenceBytes==0 {
            try await Task.sleep(nanoseconds:20_000_000);replacement=await submit(changed)
        }
        check(try replacement.preparedReferenceBytes>0 && (evidence(replacement.result))==expectedChanged,"Replacement reference did not prepare correctly")
        _=await submit(nil)
        let restored=await submit(reference)
        check(try restored.preparedReferenceBytes==0 && (evidence(restored.result))==direct,"Clearing the reference retained an obsolete cache")
        print("PASS: \(checks) exact reference sampling, invalidation, memory-bound and asynchronous pipeline checks")
    }
}
