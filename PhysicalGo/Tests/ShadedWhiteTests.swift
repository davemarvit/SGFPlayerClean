import Foundation
import ImageIO

@main struct ShadedWhiteTests {
    static func main() throws {
        setbuf(stdout,nil)
        struct Meta:Decodable {let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double}
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ShadedWhiteO3")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
        func load(_ name:String)->GrayFrame {
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!
            return GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
        }
        let reference=load("empty-reference.png")
        let source=CGImageSourceCreateWithURL(folder.appendingPathComponent("empty-reference.png") as CFURL,nil)!
        let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
        var referenceColors=[UInt8](repeating:0,count:reference.width*reference.height*4)
        referenceColors.withUnsafeMutableBytes { bytes in
            let context=CGContext(data:bytes.baseAddress,width:reference.width,height:reference.height,
                bitsPerComponent:8,bytesPerRow:reference.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,
                bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:reference.width,height:reference.height))
        }
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks+=1;precondition(condition,message)}
        let expected:[Int:Occupancy]=[60:.white,249:.white,267:.black,268:.black,269:.white,300:.black,307:.black]
        for name in ["000001.png","000013.png"] {
            let result=BoardDetector.detect(frame:load(name),reference:reference,calibration:meta.calibration,
                threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            for (index,color) in expected {check(result.readings[index].occupancy==color,"Lost or recolored stone \(index) in \(name)")}
            for (index,reading) in result.readings.enumerated() where expected[index]==nil {
                check(reading.occupancy.stone==nil,"Invented stone \(index) in \(name)")
            }
        }
        let empty=BoardDetector.detect(frame:reference,reference:reference,calibration:meta.calibration,
            threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
        check(empty.snapshot.stones.isEmpty,"Empty reference became occupied")
        // A circular shadow retains the board's color and rails. Desaturating
        // that shadow still leaves the rails: neither is a white stone.
        for point in [(2.0,13.0),(0.0,14.0)] { for neutral in [false,true] {
            var pixels=reference.pixels,colors=referenceColors
            let center=meta.calibration.point(col:point.0,row:point.1)
            for y in 0..<reference.height {for x in 0..<reference.width {
                guard hypot((Double(x)/Double(reference.width-1)-center.x)/0.015,
                            (Double(y)/Double(reference.height-1)-center.y)/0.026)<1 else {continue}
                let index=y*reference.width+x
                pixels[index]=UInt8(Double(pixels[index])*0.85)
                for channel in 0..<3 {
                    colors[index*4+channel]=neutral ? pixels[index]:UInt8(Double(colors[index*4+channel])*0.85)
                }
            }}
            let frame=GrayFrame(width:reference.width,height:reference.height,pixels:pixels,colorBytes:colors)
            let result=BoardDetector.detect(frame:frame,reference:reference,calibration:meta.calibration,
                threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            check(result.snapshot.stones.isEmpty,"Circular shadow became a stone at \(point) (neutral=\(neutral))")
        }
        }
        print("PASS: \(checks) shaded-white photo and shadow checks")
    }
}
