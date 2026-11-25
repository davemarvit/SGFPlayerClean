import Foundation
import CoreGraphics
import ImageIO

/// Only the generated experimental BoardVision copy calls this observer.
enum NativeShadowCost {
    static var cells=[UInt64](repeating:0,count:361)
    static func record(_ index:Int,_ started:UInt64) {cells[index] += DispatchTime.now().uptimeNanoseconds-started}
}

@main struct NativeRegionShadowReplay {
    struct Frame:Decodable {let name:String;let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double;let time:Double?}
    static func sample(_ frame:GrayFrame,_ calibration:BoardCalibration,_ scope:String)->ShadowScheduler.Descriptor {
        let offsets=[-0.4,-0.2,0.0,0.2,0.4]
        let cells=(0..<361).map { i -> ShadowScheduler.Cell in
            var light=[Double](),red=[Double](),green=[Double]()
            for dy in offsets {for dx in offsets {
                let point=calibration.point(col:Double(i%19)+dx,row:Double(i/19)+dy)
                light.append(frame.patchMean(point) ?? .nan)
                let color=frame.patchColor(point);red.append(color?.red ?? .nan);green.append(color?.green ?? .nan)
            }}
            return .init(light:light,red:red,green:green)
        }
        return .init(cells:cells,scope:scope)
    }
    static func load(_ path:URL)->GrayFrame {
        GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(path as CFURL,nil)!,0,nil)!)!
    }
    static func requirements(_ anchor:BoardObservation,_ current:BoardObservation)->Set<Int> {
        var result=Set<Int>()
        for i in 0..<361 {
            let a=anchor.readings[i],b=current.readings[i]
            if b.occupancy == .uncertain || b.occupancy == .white || a.occupancy != b.occupancy ||
                (a.confidence>=0.95) != (b.confidence>=0.95) {result.insert(i)}
            switch (anchor.placementOffsets[i],current.placementOffsets[i]) {
            case (.some(let a),.some(let b)):if abs(a-b)>0.04 {result.insert(i)}
            case (.some,.none),(.none,.some):result.insert(i)
            default:break
            }
        }
        return result
    }
    static func checks()->Int {
        let cell=ShadowScheduler.Cell(light:[Double](repeating:0.5,count:25),red:[Double](repeating:0.03,count:25),green:[Double](repeating:0.02,count:25))
        let anchor=ShadowScheduler.Descriptor(cells:[ShadowScheduler.Cell](repeating:cell,count:361),scope:"a")
        let wood=Set(0..<361)
        func run(_ constraints:ShadowScheduler.Constraints,_ current:ShadowScheduler.Descriptor?=nil)->ShadowScheduler.Result {
            ShadowScheduler.compare(anchor:anchor,current:current ?? anchor,woodCandidates:wood,constraints:constraints)
        }
        precondition(run(.init()).selected.isEmpty)
        for flag in 0..<5 {
            var c=ShadowScheduler.Constraints()
            if flag==0 {c.geometryUnknown=true};if flag==1 {c.handUnknown=true};if flag==2 {c.visibilityUnknown=true}
            if flag==3 {c.postDark=true};if flag==4 {c.refreshDue=true}
            precondition(run(c).selected.count==361)
        }
        precondition(run(.init(),.init(cells:anchor.cells,scope:"b")).selected.count==361)
        var mandatory=ShadowScheduler.Constraints();mandatory.mandatory=[180]
        precondition(run(mandatory).selected==Set([160,161,162,179,180,181,198,199,200]))
        var cells=anchor.cells
        cells[180] = .init(light:[Double](repeating:0.1,count:25),red:cell.red,green:cell.green)
        precondition(run(.init(),.init(cells:cells,scope:"a")).selected.contains(180))
        // Identical hidden pixels remain unchanged; independent visibility must
        // force inspection. Never interpret zero selected as newly clear.
        precondition(run(.init()).selected.isEmpty)
        return 10
    }
    static func main()throws {
        setbuf(stdout,nil)
        let folder=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        let metadata=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:folder.appendingPathComponent("metadata.json")))
        let frames=metadata.filter{$0.time != nil};precondition(frames.count==16)
        let reference=load(folder.appendingPathComponent("reference.png")).preparingPatchSamples()
        let pending:Set<Int>=[39,20,58,78,77,97,96]
        var anchorView:BoardObservation?,anchor:ShadowScheduler.Descriptor?,lastFull=frames[0].time!
        var mandatory=pending,wood=Set<Int>(),rows=[[String:Any]]()
        var sourceAnchor:GrayFrame?
        for (index,item) in frames.enumerated() {
            let image=load(folder.appendingPathComponent(item.name+".png"))
            let samplingStart=DispatchTime.now().uptimeNanoseconds
            let descriptor=sample(image,item.calibration,"crowded-fixed")
            let samplingMS=Double(DispatchTime.now().uptimeNanoseconds-samplingStart)/1e6
            var constraints=ShadowScheduler.Constraints();constraints.mandatory=mandatory
            constraints.refreshDue=index==0 || item.time!-lastFull>=1
            let schedulingStart=DispatchTime.now().uptimeNanoseconds
            let plan=ShadowScheduler.compare(anchor:anchor ?? descriptor,current:descriptor,woodCandidates:wood,constraints:constraints)
            let schedulingMS=Double(DispatchTime.now().uptimeNanoseconds-schedulingStart)/1e6
            NativeShadowCost.cells=[UInt64](repeating:0,count:361)
            let fullStarted=DispatchTime.now().uptimeNanoseconds
            let view=BoardDetector.detect(frame:image,reference:reference,calibration:item.calibration,threshold:item.threshold,referenceCalibration:item.referenceCalibration)!
            let fullMS=Double(DispatchTime.now().uptimeNanoseconds-fullStarted)/1e6
            let fullCosts=NativeShadowCost.cells
            if index==0 {
                anchorView=view;anchor=descriptor;sourceAnchor=image
                mandatory.formUnion(view.readings.indices.filter{view.readings[$0].occupancy == .white || view.readings[$0].occupancy == .uncertain})
                // Anchor-confirmed exposed wood is only a normalization candidate;
                // it is not a claim that the current frame is still unobstructed.
                wood=Set(view.readings.indices.filter{view.readings[$0].occupancy == .empty && view.readings[$0].confidence>=0.95})
                    .subtracting(ShadowScheduler.halo(mandatory))
            }
            if constraints.refreshDue {lastFull=item.time!}
            let required=requirements(anchorView!,view).union(pending)
            let missing=required.subtracting(plan.selected).sorted()
            let potential=fullCosts.enumerated().filter{!plan.selected.contains($0.offset)}.reduce(UInt64(0)){$0+$1.element}
            rows.append(["name":item.name,"recordedTime":item.time!,"selected":plan.selected.sorted(),"pixelChanged":plan.pixelChanged.sorted(),
                         "required":required.sorted(),"missed":missing,"reasons":plan.reasons,"gain":plan.gain,"offset":plan.offset,
                         "normalizationCandidates":plan.normalizationCount,"sampleMS":samplingMS,"scheduleMS":schedulingMS,"fullRecognitionMS":fullMS,
                         "classificationLoopMS":Double(fullCosts.reduce(0,+))/1e6,"candidateAvoidedLoopMS":Double(potential)/1e6,
                         "netHypotheticalMS":Double(potential)/1e6-samplingMS-schedulingMS,"lightingBlocked":view.lightingBlocked,
                         "signature":view.readings.map{$0.occupancy.rawValue},"nativeConfidence":view.readings.map(\.confidence)])
            print("\(item.name): selected=\(plan.selected.count) missing=\(missing) fullMS=\(fullMS)")
        }
        // Held-out source images/control transformations do not set thresholds.
        var controls=[[String:Any]]()
        func control(_ name:String,_ image:GrayFrame,_ item:Frame,_ required:Set<Int>,_ flags:ShadowScheduler.Constraints) {
            let descriptor=sample(image,item.calibration,"crowded-fixed")
            let raw=ShadowScheduler.compare(anchor:anchor!,current:descriptor,woodCandidates:wood,constraints:.init())
            let guarded=ShadowScheduler.compare(anchor:anchor!,current:descriptor,woodCandidates:wood,constraints:flags)
            controls.append(["name":name,"required":required.sorted(),"rawSelected":raw.selected.sorted(),
                             "rawMissed":required.subtracting(raw.selected).sorted(),"guardedSelected":guarded.selected.sorted(),
                             "guardedMissed":required.subtracting(guarded.selected).sorted(),"reasons":guarded.reasons])
        }
        let hand=metadata.first{$0.name=="frame-950"}!
        var handFlags=ShadowScheduler.Constraints();handFlags.handUnknown=true
        control("held-out-recorded-hand",load(folder.appendingPathComponent("frame-950.png")),hand,[95,134],handFlags)
        let original=sourceAnchor!,cal=frames[0].calibration
        let sourceImage=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(folder.appendingPathComponent(frames[0].name+".png") as CFURL,nil)!,0,nil)!
        var originalColor=[UInt8](repeating:0,count:original.width*original.height*4)
        originalColor.withUnsafeMutableBytes { bytes in
            let flags=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
            let context=CGContext(data:bytes.baseAddress,width:original.width,height:original.height,bitsPerComponent:8,
                bytesPerRow:original.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:flags)!
            context.draw(sourceImage,in:CGRect(x:0,y:0,width:original.width,height:original.height))
        }
        // Native GrayFrame transformations; no raster output or fresh capture.
        var shift=[UInt8](repeating:0,count:original.pixels.count)
        var shiftedColor=[UInt8](repeating:0,count:originalColor.count)
        for y in 0..<original.height {for x in 2..<original.width {
            let to=y*original.width+x,from=to-2;shift[to]=original.pixels[from]
            for k in 0..<4 {shiftedColor[to*4+k]=originalColor[from*4+k]}
        }}
        var geoFlags=ShadowScheduler.Constraints();geoFlags.geometryUnknown=true
        let moved=GrayFrame(width:original.width,height:original.height,pixels:shift,colorBytes:shiftedColor)
        control("held-out-whole-board-2px-drift",moved,frames[0],Set(0..<361),geoFlags)
        var placed=original.pixels
        var placedColor=originalColor
        let p=cal.point(col:9,row:9),centerX=p.x*Double(original.width-1),centerY=p.y*Double(original.height-1)
        let q=cal.point(col:10,row:9),radius=hypot((q.x-p.x)*Double(original.width),(q.y-p.y)*Double(original.height))*0.35
        for y in max(0,Int(centerY-radius))...min(original.height-1,Int(centerY+radius)) {
            for x in max(0,Int(centerX-radius))...min(original.width-1,Int(centerX+radius)) where hypot(Double(x)-centerX,Double(y)-centerY)<=radius {
                let i=y*original.width+x;placed[i]=25
                for k in 0..<3 {placedColor[i*4+k]=25}
            }
        }
        control("held-out-synthetic-black-insertion",GrayFrame(width:original.width,height:original.height,pixels:placed,colorBytes:placedColor),frames[0],[180],.init())
        let report:[String:Any]=["diagnosticOnly":true,"runtimeIntegrated":false,"nativeBase":"1f6fb91cac57616791d47c2fea4cc4eca0426a28",
                               "fixture":folder.path,"frameCount":16,"pureChecks":checks(),"pending":pending.sorted(),"frames":rows,"controls":controls,
                               "contract":"Full native recognition runs every frame. Fixed first-frame anchor. Current output is comparator only. Fixture geometry/hand-clear are conditional assumptions, not live qualifications. No measured work skipped."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
    }
}
