import Foundation
import CoreGraphics
import CryptoKit
import ImageIO

@main struct WoodenBoardPerimeterTests {
    static func main()throws {
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks+=1;precondition(condition,message)}
        let calibration=BoardCalibration(size:19,corners:[.init(x:0.2,y:0.2),.init(x:0.8,y:0.2),.init(x:0.8,y:0.8),.init(x:0.2,y:0.8)])!
        let boundary=HandBoardBoundary(size:19,vertices:[.init(x:-0.6,y:-0.6),.init(x:18.6,y:-0.6),.init(x:18.6,y:18.6),.init(x:-0.6,y:18.6)])!
        let profile=WoodenBoardPerimeter(schemaVersion:1,cameraID:"camera",referenceCalibrationSHA256:WoodenBoardPerimeter.calibrationSHA256(calibration)!,
            referenceImageSHA256:String(repeating:"a",count:64),imageWidth:640,imageHeight:480,boundary:boundary)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let before=try encoder.encode(calibration)
        check(profile.isValid,"Valid measured perimeter rejected")
        check(profile.snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480) == .verified(boundary),"Matched profile lost boundary")
        check(profile.snapshot(cameraID:"other",referenceCalibration:calibration,width:640,height:480).failure != nil,"Wrong camera accepted")
        check(profile.snapshot(cameraID:"camera",referenceCalibration:calibration,width:1280,height:960).failure != nil,"Changed resolution accepted")
        let changed=BoardCalibration(size:19,corners:calibration.corners.map{.init(x:$0.x+0.01,y:$0.y)})!
        check(profile.snapshot(cameraID:"camera",referenceCalibration:changed,width:640,height:480).failure != nil,"Changed reference grid accepted")
        check(try encoder.encode(calibration)==before,"Independent perimeter changed calibration bytes")
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("wood-perimeter-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("profile.json")
        let absent=WoodenBoardPerimeterStore(url:file)
        check(absent.snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480) == .absent,"Absent profile was not explicitly absent")
        try profile.save(to:file)
        var configured=false
        let store=WoodenBoardPerimeterStore(url:file,onProfileLoaded:{configured=true})
        check(configured,"Successful profile load did not activate required-profile state")
        try FileManager.default.removeItem(at:file)
        check(WoodenBoardPerimeterStore(url:file,required:configured).snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480).failure != nil,
            "Deleted configured profile silently reverted to legacy boundary")
        check(WoodenBoardPerimeterStore(url:nil,required:true).snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480).failure != nil,
            "Missing configured profile URL silently reverted to legacy boundary")
        try profile.save(to:file)
        check(store.snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480) == .verified(boundary),"Profile roundtrip changed geometry")
        try Data("invalid JSON".utf8).write(to:file)
        check(store.snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480) == .verified(boundary),"Immutable loaded snapshot reread disk")
        check(WoodenBoardPerimeterStore(url:file).snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480).failure != nil,"Invalid present file silently became absent/clear")
        var dictionary=try JSONSerialization.jsonObject(with:encoder.encode(profile)) as! [String:Any]
        for (key,value) in [("schemaVersion",2 as Any),("referenceCalibrationSHA256","bad" as Any),("imageWidth",0 as Any)] {
            var broken=dictionary;broken[key]=value
            try JSONSerialization.data(withJSONObject:broken).write(to:file)
            check(WoodenBoardPerimeterStore(url:file).snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480).failure != nil,"Invalid profile metadata accepted: \(key)")
        }
        dictionary["boundary"]=["size":19,"vertices":[["x":0,"y":0],["x":18,"y":18],["x":18,"y":0],["x":0,"y":18]]]
        try JSONSerialization.data(withJSONObject:dictionary).write(to:file)
        check(WoodenBoardPerimeterStore(url:file).snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480).failure != nil,"Crossed polygon accepted from decoding")
        try Data(repeating:32,count:65537).write(to:file)
        check(WoodenBoardPerimeterStore(url:file).snapshot(cameraID:"camera",referenceCalibration:calibration,width:640,height:480).failure != nil,"Unbounded profile file accepted")

        // Same production pipeline: invalid configuration must reach the early
        // safety publication as unknown even if image processing finds no hand.
        let color=CGColorSpaceCreateDeviceRGB()
        let context=CGContext(data:nil,width:640,height:480,bitsPerComponent:8,bytesPerRow:640*4,space:color,
            bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red:0.6,green:0.5,blue:0.35,alpha:1));context.fill(CGRect(x:0,y:0,width:640,height:480))
        let image=context.makeImage()!
        var safety:CameraAnalysisPipeline.CameraSafety?
        let output=CameraAnalysisPipeline.process(.init(target:image,calibration:calibration,threshold:0.2,
            reference:nil,referenceCalibration:calibration,straighten:false,longAxisRows:false,checkStoneAspect:false,
            previousStoneCount:0,pendingAxis:nil,trackingAnchor:nil,alignmentExpected:[],checkAlignment:false,
            trackingState:EstablishedStoneTracker(),trackingExpected:[],trackingContext:"test",trackingManualPoints:[],
            trackingFresh:true,trackingTime:1,checkHands:true,perimeter:.invalid("fixture mismatch")),safety:{safety=$0})
        check(output.handObstructed==nil && safety?.handObstructed==nil,"Invalid perimeter bypassed early/full unknown verdict")
        check(output.handOutline?.reason=="fixture mismatch","Invalid perimeter reason disappeared")
        let sample=HandOutlineSampling.sample(GrayFrame(image:image)!,calibration:calibration,boundary:boundary)
        check(sample.boundary==boundary,"Boundary did not reach sampled hand frame")

        // Actual image pixels, not precomputed hand samples: exterior changes
        // must not leak through the 3x3 sampling footprints at the wood edge.
        func photographedBoard(outside:(UInt8,UInt8,UInt8),intrusion:Bool=false)->GrayFrame {
            var pixels=[UInt8](repeating:0,count:640*480),colors=[UInt8](repeating:255,count:640*480*4)
            for y in 0..<480 {for x in 0..<640 {
                let grid=calibration.gridPoint(for:.init(x:Double(x)/639,y:Double(y)/479))!
                let inside=boundary.contains(x:grid.x,y:grid.y)
                let finger=intrusion && (8...8.8).contains(grid.x) && grid.y < -0.45
                let rgb:(UInt8,UInt8,UInt8)=finger ? (220,100,80):inside ? (180,145,95):outside
                let i=y*640+x
                colors[i*4]=rgb.0;colors[i*4+1]=rgb.1;colors[i*4+2]=rgb.2
                pixels[i]=UInt8((Int(rgb.0)*77+Int(rgb.1)*150+Int(rgb.2)*29)/256)
            }}
            return GrayFrame(width:640,height:480,pixels:pixels,colorBytes:colors)
        }
        let baselineImage=photographedBoard(outside:(100,100,100))
        let baselineSample=HandOutlineSampling.sample(baselineImage,calibration:calibration,boundary:boundary)
        func preparedTracker()->HandOutlineTracker {
            var tracker=HandOutlineTracker()
            for i in 1...6 {_=tracker.observe(baselineSample,pose:.init(hands:[]),at:Double(i)*0.1,source:"fixture")}
            return tracker
        }
        for exterior:(UInt8,UInt8,UInt8) in [(0,0,0),(255,255,255),(240,25,20)] {
            let changed=HandOutlineSampling.sample(photographedBoard(outside:exterior),calibration:calibration,boundary:boundary)
            for i in changed.pixels.indices {
                let p=changed.grid(i)
                if boundary.contains(x:p.0,y:p.1) {
                    let a=changed.pixels[i],b=baselineSample.pixels[i]
                    check(a.red==b.red && a.green==b.green && a.light==b.light,"Outside image pixels leaked into inside hand sample")
                }
            }
            var tracker=preparedTracker()
            check(tracker.observe(changed,pose:.init(hands:[]),at:0.8,source:"fixture").obstructed == false,
                "Exterior-only pixel changes stopped an otherwise clear board")
        }
        let shallow=HandOutlineSampling.sample(photographedBoard(outside:(100,100,100),intrusion:true),calibration:calibration,boundary:boundary)
        var shallowTracker=preparedTracker()
        check(shallowTracker.observe(shallow,pose:.init(hands:[]),at:0.8,source:"fixture").obstructed != false,
            "A shallow interior fingertip without a pose was treated as clear")

        if let measured=ProcessInfo.processInfo.environment["PHYSICAL_GO_MEASURED_PERIMETER"] {
            let url=URL(fileURLWithPath:measured)
            let loaded=try JSONDecoder().decode(WoodenBoardPerimeter.self,from:Data(contentsOf:url))
            check(loaded.isValid,"Root measured profile failed actual Swift validation")
            struct Metadata:Decodable {let cameraID:String;let referenceCalibration:BoardCalibration;let currentCalibration:BoardCalibration;let width:Int;let height:Int}
            let source=url.deletingLastPathComponent().appendingPathComponent("wood-boundary-camera")
            let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:source.appendingPathComponent("frame.json")))
            check(WoodenBoardPerimeterStore(url:url).snapshot(cameraID:meta.cameraID,referenceCalibration:meta.referenceCalibration,
                width:meta.width,height:meta.height) == .verified(loaded.boundary),"Measured profile mismatched actual saved camera reference")
            let sourceSHA=SHA256.hash(data:try Data(contentsOf:source.appendingPathComponent("frame.png"))).map{String(format:"%02x",$0)}.joined()
            check(sourceSHA==loaded.referenceImageSHA256,"Measured profile source-image provenance changed")
            let photo=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(source.appendingPathComponent("frame.png") as CFURL,nil)!,0,nil)!
            let actual=GrayFrame(image:photo)!
            for enabled in [false,true] {
                var durations=[Double]()
                for _ in 0..<7 {
                    let began=ProcessInfo.processInfo.systemUptime
                    let sample=HandOutlineSampling.sample(actual,calibration:meta.currentCalibration,boundary:enabled ? loaded.boundary:nil)
                    durations.append((ProcessInfo.processInfo.systemUptime-began)*1000)
                    check(sample.pixels.count>0,"Benchmark work was omitted")
                }
                durations.sort()
                print("Sampling milliseconds perimeter=\(enabled): median=\(durations[3]), max=\(durations[6])")
            }
            // Differential early-safety cost on the retained real camera
            // frame. This uses local appearance (no empty reference) and fixed
            // grid, so it is not an end-to-end live-game latency claim.
            for enabled in [false,true] {
                var durations=[Double](),tracker=HandOutlineTracker()
                for index in 0..<7 {
                    let began=ProcessInfo.processInfo.systemUptime
                    let output=CameraAnalysisPipeline.process(.init(target:photo,calibration:meta.currentCalibration,threshold:0.2,
                        reference:nil,referenceCalibration:meta.referenceCalibration,straighten:false,longAxisRows:false,
                        checkStoneAspect:false,previousStoneCount:9,pendingAxis:nil,trackingAnchor:nil,alignmentExpected:[],
                        checkAlignment:false,trackingState:EstablishedStoneTracker(),trackingExpected:[],trackingContext:"benchmark",
                        trackingManualPoints:[],trackingFresh:true,trackingTime:Double(index)*0.2,checkHands:true,handTracking:tracker,
                        perimeter:enabled ? .verified(loaded.boundary):.absent),safety:{_ in
                            durations.append((ProcessInfo.processInfo.systemUptime-began)*1000)
                        })
                    tracker=output.handTracking
                }
                durations.sort()
                check(durations.count==7,"Early safety callback was omitted")
                print("Early safety milliseconds perimeter=\(enabled): median=\(durations[3]), max=\(durations[6]); retained local-appearance/fixed-grid path")
            }
            print("Measured profile accepted: \(url.path), camera \(loaded.cameraID)")
        }
        print("PASS: \(checks) wooden-board perimeter profile and pipeline checks")
    }
}
