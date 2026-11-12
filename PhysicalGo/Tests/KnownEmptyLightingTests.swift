import Foundation
import ImageIO
import CoreGraphics

@main struct KnownEmptyLightingTests {
    struct Case:Decodable {let image:String;let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double;let expectedWhite:Bool}
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/KnownPositionGlare")
        func load(_ name:String)->GrayFrame {
            let source=CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!
            return GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
        }
        let cases=try JSONDecoder().decode([Case].self,from:Data(contentsOf:root.appendingPathComponent("cases.json")))
        let reference=load("reference.png"),frames=cases.map {load($0.image)}
        let raw=zip(cases,frames).map {item,frame in
            BoardDetector.detect(frame:frame,reference:reference,calibration:item.calibration,
                threshold:item.threshold,referenceCalibration:item.referenceCalibration)!
        }
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        var position=[Occupancy](repeating:.empty,count:361)
        position[60] = .black;position[180] = .black;position[300] = .white
        var tracker=KnownEmptyLighting(),now=0.0
        func observe(_ photo:Int,override:BoardObservation?=nil,valid:Bool=true,context:String="game")->BoardObservation {
            now+=0.21
            return tracker.observe(override ?? raw[photo],frame:frames[photo],calibration:cases[photo].calibration,
                expected:position,context:context,now:now,valid:valid)
        }
        func changed(_ source:BoardObservation,_ p:Int,_ occupancy:Occupancy)->BoardObservation {
            var readings=source.readings
            let r=readings[p];readings[p] = .init(row:r.row,col:r.col,occupancy:occupancy,confidence:occupancy == .uncertain ? 0:1,delta:r.delta)
            return .init(readings:readings,size:source.size)
        }
        func train(_ photo:Int) {for _ in 0..<9 {_=observe(photo)}}
        check(raw.map {$0.signature[185]} == [.empty,.white,.empty],"Real glare placement sequence did not reproduce")
        // Each synthetic fresh timestamp exercises the policy; these repeated
        // photos are not represented as a captured temporal sequence.
        for _ in 0..<4 {_=observe(2)}
        check(tracker.report.learned==0,"A baseline was learned before eight frames / 1.4 seconds")
        train(2)
        let learned=tracker.report.learned
        check(learned>300,"Known clear empty intersections did not train")
        let reduced=observe(0)
        check(raw[0].signature[109] == .uncertain && reduced.signature[109] == .empty,
              "Known empty lighting baseline did not resolve real glare uncertainty")
        check(!tracker.report.resolved.isEmpty,"Adaptation omitted its diagnostic provenance")
        for p in [60,180,300] {check(reduced.signature[p]==position[p],"A known stone changed")}
        let white=observe(1)
        check(white.signature[185] == .white,"Saved three-stone count suppressed a fourth stone")
        check(observe(2).signature[185] == .empty,"Physical removal was not recognized")
        // Even if the ordinary detector calls the new White uncertain, its
        // changed pixels must defeat the learned empty prior.
        tracker.reset();train(0)
        let weakWhite=observe(1,override:changed(raw[1],185,.uncertain))
        check(weakWhite.signature[185] == .uncertain,"Prior erased a weak new White in the glare")
        tracker.reset();train(2)
        let missing=changed(raw[0],180,.empty)
        check(observe(0,override:missing).signature[180] == .empty,"Known position hid a removed Black")
        check(observe(0).signature[109] == .uncertain,"Contradictory known stones did not invalidate learned baseline")
        tracker.reset();train(2)
        check(observe(0,valid:false).signature[109] == .uncertain,"Unaligned, hand-obstructed or frozen frame used baseline")
        check(observe(0).signature[109] == .uncertain,"Invalid frame left old baseline active")
        tracker.reset();train(2)
        check(observe(0,context:"another game").signature[109] == .uncertain,"Baseline leaked between games")
        tracker.reset();train(2);now+=2
        check(observe(0).signature[109] == .uncertain,"Camera gap kept a stale baseline")
        tracker.reset();train(2)
        let duplicate=tracker.observe(raw[0],frame:frames[0],calibration:cases[0].calibration,
            expected:position,context:"game",now:now,valid:true)
        check(duplicate.signature[109] == .uncertain,"Repeated timestamp counted as fresh evidence")
        tracker.reset();train(2)
        // A small opaque cover can miss the off-axis wood samples; the central
        // sample must still invalidate the empty baseline.
        let source=CGImageSourceCreateWithURL(root.appendingPathComponent("after.png") as CFURL,nil)!
        let photo=CGImageSourceCreateImageAtIndex(source,0,nil)!
        let canvas=CGContext(data:nil,width:photo.width,height:photo.height,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        canvas.draw(photo,in:CGRect(x:0,y:0,width:photo.width,height:photo.height))
        let center=cases[2].calibration.point(col:14,row:9)
        canvas.setFillColor(gray:0.05,alpha:1)
        canvas.fillEllipse(in:CGRect(x:center.x*Double(photo.width-1)-5,y:(1-center.y)*Double(photo.height-1)-5,width:10,height:10))
        let cover=GrayFrame(image:canvas.makeImage()!)!
        now+=0.21
        let covered=tracker.observe(changed(raw[2],185,.uncertain),frame:cover,calibration:cases[2].calibration,
            expected:position,context:"game",now:now,valid:true,appearanceThreshold:0.13)
        check(covered.signature[185] == .uncertain,"Small central obstruction was hidden by empty prior")
        for _ in 0..<10 {
            now+=0.21
            let held=tracker.observe(changed(raw[2],185,.uncertain),frame:cover,calibration:cases[2].calibration,
                expected:position,context:"game",now:now,valid:true,appearanceThreshold:0.13)
            check(held.signature[185] == .uncertain,"Appearance-only relearning hid a persistent central obstruction")
        }
        tracker.reset();train(2)
        var expired=raw[0]
        for _ in 0..<150 {expired=observe(0)}
        check(expired.signature[109] == .uncertain,"Baseline learned from its own resolved output or failed to expire")
        tracker.reset();train(2)
        let moved=BoardCalibration(size:19,corners:cases[2].calibration.corners.map {.init(x:$0.x+0.005,y:$0.y)})!
        now+=0.21
        let shifted=tracker.observe(raw[0],frame:frames[0],calibration:moved,expected:position,context:"game",now:now,valid:true)
        check(shifted.signature[109] == .uncertain,"Moved grid kept old local baselines")
        tracker.reset();train(2)
        position[109] = .white
        check(observe(0).signature[109] == .uncertain,"Expected-position change retained an old empty prior")
        // Independently enumerated occupied fixture also includes the grained
        // White at 311, which older captured raw readings had missed.
        struct Occupied:Decodable {let calibration:BoardCalibration;let threshold:Double}
        let occupiedRoot=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/OccupiedTracking")
        let occupiedMeta=try JSONDecoder().decode(Occupied.self,from:Data(contentsOf:occupiedRoot.appendingPathComponent("sample.json")))
        let occupiedSource=CGImageSourceCreateWithURL(occupiedRoot.appendingPathComponent("frame.png") as CFURL,nil)!
        let occupiedFrame=GrayFrame(image:CGImageSourceCreateImageAtIndex(occupiedSource,0,nil)!)!
        let stones:Set<Int>=[60,174,244,263,264,282,283,287,288,289,291,300,301,306,307,309,311,313,319,320,329]
        for p in stones {
            check(BoardAppearanceDetector.emptyConfidence(frame:occupiedFrame,calibration:occupiedMeta.calibration,
                point:p,threshold:occupiedMeta.threshold,occupied:stones.subtracting([p])) == nil,
                "Current-image wood evidence accepted an actual stone, including grained White")
        }
        _ = try ResidualGlareTests.run()
        print("PASS: \(checks) known-empty lighting checks; real glare reduction and White placement/removal, weak new stone, missing Black, invalid frames, context, gaps and duplicate timestamps")
    }
}
