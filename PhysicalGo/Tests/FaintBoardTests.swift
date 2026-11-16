import Foundation
import ImageIO
import CoreImage

@main struct FaintBoardTests {
    struct Anchor:Decodable {let calibration:BoardCalibration;let fittedGrid:BoardCalibration;let width:Int;let height:Int}
    struct Meta:Decodable {
        let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double
        let anchor:Anchor;let expected:[Occupancy];let frames:[String]
    }
    static func main() throws {
        setbuf(stdout,nil)
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/FaintBoardO2")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("metadata.json")))
        func load(_ name:String)->GrayFrame {
            GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!,0,nil)!)!
        }
        let reference=load("reference.png"),anchor=AutoGridDetector.TrackingAnchor(
            calibration:meta.anchor.calibration,fittedGrid:meta.anchor.fittedGrid,
            frame:GrayFrame(width:meta.anchor.width,height:meta.anchor.height,pixels:Array(try Data(contentsOf:folder.appendingPathComponent("anchor.gray")))))
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        for name in meta.frames {
            let frame=load(name)
            let result=BoardDetector.detect(frame:frame,reference:reference,calibration:meta.calibration,
                threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            for (index,state) in meta.expected.enumerated() {
                check(state == .empty ? result.readings[index].occupancy.stone==nil:result.readings[index].occupancy==state,
                    "Wrong occupancy at \(index) in \(name)")
            }
            check(AutoGridDetector.track(frame:frame,from:meta.calibration,anchor:anchor,expected:meta.expected) != nil,
                "Visible faint board rejected")
            for level:UInt8 in [0,170,255] {
                let blank=GrayFrame(width:frame.width,height:frame.height,pixels:Array(repeating:level,count:frame.pixels.count))
                check(AutoGridDetector.track(frame:blank,from:meta.calibration,anchor:anchor,expected:meta.expected)==nil,
                    "History authorized a blank frame")
            }
        }
        let empty=BoardDetector.detect(frame:reference,reference:reference,calibration:meta.referenceCalibration,threshold:meta.threshold)!
        check(empty.snapshot.stones.isEmpty,"Empty faint board invented stones")
        // Exercise the edge failure under small exposure changes, including
        // positive and negative controls from the same camera and reference.
        let context=CIContext()
        for name in ["000010.png","000016.png","reference.png"] {
            let source=CIImage(contentsOf:folder.appendingPathComponent(name))!
            for brightness in [-0.005,0.005] {
                let adjusted=source.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness])
                let frame=GrayFrame(image:context.createCGImage(adjusted,from:source.extent)!)!
                let grid=name=="reference.png" ? meta.referenceCalibration:meta.calibration
                let result=BoardDetector.detect(frame:frame,reference:reference,calibration:grid,
                    threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
                check(name=="reference.png" ? result.readings[266].occupancy == .empty:result.readings[266].occupancy == .white,
                    "Wrong edge occupancy in \(name), exposure \(brightness)")
                check(result.readings.enumerated().allSatisfy { index,reading in
                    reading.occupancy.stone==nil || (name != "reference.png" && meta.expected[index]==reading.occupancy)
                },"Invented stone in \(name), exposure \(brightness)")
            }
        }
        print("PASS: \(checks) faint-board photo and alignment checks")
    }
}
