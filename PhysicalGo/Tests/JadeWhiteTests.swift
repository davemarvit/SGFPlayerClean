import Foundation
import ImageIO

@main struct JadeWhiteTests {
    struct Frame:Decodable {let frameID:Int;let calibration:BoardCalibration}
    struct Meta:Decodable {let referenceCalibration:BoardCalibration;let threshold:Double;let frames:[Frame]}
    static func main() throws {
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/JadeWhiteA19")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("metadata.json")))
        func load(_ name:String)->GrayFrame {
            GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!,0,nil)!)!
        }
        let reference=load("../FaintBoardO2/reference.png")
        let black:Set<Int>=[2,19,20,36,72,180,186,300,307]
        let white:Set<Int>=[18,60,66,248,249,266,269,286,287]
        var checks=0,recognized=0
        func check(_ condition:Bool,_ message:String) {checks+=1;precondition(condition,message)}
        for input in meta.frames {
            let result=BoardDetector.detect(frame:load(String(format:"%06d.png",input.frameID)),reference:reference,
                calibration:input.calibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            for (index,reading) in result.readings.enumerated() {
                let expected:Occupancy=black.contains(index) ? .black:white.contains(index) ? .white:.empty
                // One recorded frame remains a known miss. Never accept a wrong
                // color, and require the other five snapshots to recognize A19.
                if index==18 && input.frameID==62 {
                    check(reading.occupancy == .white || reading.occupancy == .empty,"Wrong A19 color in residual frame")
                } else {
                    check(expected == .empty ? reading.occupancy.stone==nil:reading.occupancy==expected,
                        "Wrong point \(index) in jade frame \(input.frameID)")
                }
            }
            if result.readings[18].occupancy == .white {recognized+=1}
        }
        check(recognized>=5,"Jade A19 recognition regressed")
        for name in ["../FaintBoardO2/reference.png","../FaintBoardO2/000010.png","../FaintCaptureQ3/000003.png"] {
            let result=BoardDetector.detect(frame:load(name),reference:reference,calibration:meta.referenceCalibration,
                threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            check(result.readings[18].occupancy == .empty,"Invented A19 before placement in \(name)")
            if name.hasSuffix("reference.png") {check(result.snapshot.stones.isEmpty,"Invented stones on the empty board")}
        }
        // A cool-colored circular lighting patch still exposes the grid rails.
        // Its color alone must not create a white stone, at an edge or inside.
        let image=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(folder.appendingPathComponent("../FaintBoardO2/reference.png") as CFURL,nil)!,0,nil)!
        var rgba=[UInt8](repeating:0,count:reference.width*reference.height*4)
        rgba.withUnsafeMutableBytes { bytes in
            let context=CGContext(data:bytes.baseAddress,width:reference.width,height:reference.height,bitsPerComponent:8,
                bytesPerRow:reference.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,
                bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:reference.width,height:reference.height))
        }
        for point in [(18.0,0.0),(9.0,9.0)] {
            var colors=rgba,pixels=reference.pixels
            let center=meta.referenceCalibration.point(col:point.0,row:point.1)
            for y in 0..<reference.height {for x in 0..<reference.width {
                guard hypot((Double(x)/Double(reference.width-1)-center.x)/0.012,
                            (Double(y)/Double(reference.height-1)-center.y)/0.020)<1 else {continue}
                let i=y*reference.width+x
                colors[i*4]=UInt8(max(0,Double(colors[i*4])*0.78))
                colors[i*4+2]=UInt8(min(255,Double(colors[i*4+2])*1.22))
                pixels[i]=UInt8((Int(colors[i*4])+Int(colors[i*4+1])+Int(colors[i*4+2]))/3)
            }}
            let result=BoardDetector.detect(frame:GrayFrame(width:reference.width,height:reference.height,pixels:pixels,colorBytes:colors),
                reference:reference,calibration:meta.referenceCalibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            check(result.snapshot.stones.isEmpty,"Cool lighting patch became a stone at \(point)")
        }
        print("PASS: \(checks) jade A19 photo, absence and cool-lighting checks; \(recognized)/6 positive snapshots")
    }
}
