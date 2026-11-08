import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct DisplacedNeighborsTests {
    static func main() throws {
        setbuf(stdout,nil)
        struct Meta:Decodable { let calibration:BoardCalibration; let referenceCalibration:BoardCalibration; let threshold:Double; let readings:[IntersectionReading] }
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/MultipleDisplaced")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
        func load(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        let image=load("frame.png"),reference=GrayFrame(image:load("empty-reference.png"))!
        let expected=meta.readings.filter{$0.occupancy.stone != nil}
        guard expected.count==21,meta.readings.filter({$0.occupancy == .uncertain}).count==12 else { fatalError("Wrong regression fixture") }
        let context=CIContext(),input=CIImage(cgImage:image)
        var cases=0
        for brightness in [-0.005,0,0.005] {
            let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
            let frame=GrayFrame(image:adjusted)!
            for dy in [-0.5,0,0.5] { for dx in [-0.5,0,0.5] {
                let cal=BoardCalibration(size:19,corners:meta.calibration.corners.map{ImagePoint(x:$0.x+dx/1919,y:$0.y+dy/1079)})!
                let result=BoardDetector.detect(frame:frame,reference:reference,calibration:cal,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
                for point in expected {
                    guard result.readings[point.row*19+point.col].occupancy == point.occupancy else {
                        fatalError("Lost displaced stone \(point.row),\(point.col) at brightness \(brightness), shift \(dx),\(dy)")
                    }
                }
                guard result.snapshot.stones.count==21 else { fatalError("Invented a neighboring stone") }
                if brightness==0 && dx==0 && dy==0 {
                    for (row,col) in [(14,6),(15,1),(15,8),(17,7)] {
                        guard result.readings[row*19+col].occupancy == .empty else { fatalError("Visible shaded wood stayed uncertain: \(row),\(col)") }
                    }
                    print("Base sample:",result.signature.filter{$0 == .uncertain}.count,"uncertain, all 21 stones retained")
                    // A point whose vertical rail is obscured must remain uncertain.
                    guard result.readings[12*19+17].occupancy == .uncertain else { fatalError("Insufficient grid evidence was forced to empty") }
                }
                cases += 1
            } }
        }
        // A shadow preserves the printed cross; an opaque wood-colored object
        // with the same brightness/color must not be called empty.
        let side=720
        let syntheticCal=BoardCalibration(size:9,corners:[.init(x:0.1,y:0.1),.init(x:0.9,y:0.1),.init(x:0.9,y:0.9),.init(x:0.1,y:0.9)])!
        func synthetic(_ mode:Int)->GrayFrame {
            var bytes=[UInt8](repeating:255,count:side*side*4)
            let pitch=Double(side-1)*0.1
            for y in 0..<side { for x in 0..<side {
                let gx=(Double(x)-Double(side-1)*0.1)/pitch,gy=(Double(y)-Double(side-1)*0.1)/pitch
                let ink=gx>=0 && gx<=8 && gy>=0 && gy<=8 && (abs(gx-gx.rounded())*pitch<1.2 || abs(gy-gy.rounded())*pitch<1.2)
                let inside=hypot(gx-4,gy-4)<0.42
                for channel in 0..<3 {
                    let wood=Double([190,175,100][channel])
                    var value=ink ? 35.0 : wood
                    if inside && mode==1 { value *= 0.90 + 0.10*(gx-4) }
                    if inside && mode==2 { value = wood*0.88 }
                    bytes[(y*side+x)*4+channel]=UInt8(value.rounded())
                }
            } }
            let flags=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            let image=CGImage(width:side,height:side,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:side*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:flags),
                provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            return GrayFrame(image:image)!
        }
        let syntheticReference=synthetic(0)
        let shadow=BoardDetector.detect(frame:synthetic(1),reference:syntheticReference,calibration:syntheticCal,threshold:0.13)!
        guard shadow.readings[40].occupancy == .empty,shadow.snapshot.stones.isEmpty else { fatalError("Shadow with surviving rails did not remain empty") }
        let opaque=BoardDetector.detect(frame:synthetic(2),reference:syntheticReference,calibration:syntheticCal,threshold:0.13)!
        guard opaque.readings[40].occupancy == .uncertain else { fatalError("Opaque wood-colored object was explained away as a shadow") }
        print("PASS: displaced stones, neighboring shaded wood and no false/duplicate stones across \(cases) lighting/alignment cases")
    }
}
