import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct ShadedCrossTests {
    struct Metadata:Decodable {
        let calibration:BoardCalibration,referenceCalibration:BoardCalibration
        let threshold:Double
        let readings:[IntersectionReading]
    }
    static func main() throws {
        setbuf(stdout,nil)
        func check(_ value:Bool,_ message:String) {if !value {print("FAIL:",message);exit(1)}}
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ShadedCross")
        let target=15*19+12,context=CIContext()
        func image(_ name:String)->CGImage {
            CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!
        }
        let reference=GrayFrame(image:image("empty-reference.png"))!
        var cases=0,resolved=0
        for id in [10,75,150] {
            let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:root.appendingPathComponent("\(id).json")))
            check(meta.readings[target].occupancy == .uncertain,"Fixture must reproduce the original stall")
            let input=CIImage(cgImage:image("\(id).png"))
            for brightness in [-0.003,0,0.003] {
                let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
                for dy in [-0.5,0,0.5] { for dx in [-0.5,0,0.5] {
                    let cal=BoardCalibration(size:19,corners:meta.calibration.corners.map{ImagePoint(x:$0.x+dx/1919,y:$0.y+dy/1079)})!
                    let result=BoardDetector.detect(frame:GrayFrame(image:adjusted)!,reference:reference,calibration:cal,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
                    for r in meta.readings where r.occupancy.stone != nil {
                        check(result.signature[r.row*19+r.col]==r.occupancy,"Lost a real stone in \(id), brightness \(brightness), shift \(dx),\(dy)")
                    }
                    for r in result.readings where r.occupancy.stone != nil {
                        check(meta.readings[r.row*19+r.col].occupancy==r.occupancy,"Invented a stone")
                    }
                    if result.signature[target] == .empty {resolved += 1}
                    if result.signature[target] != .empty {print("Unresolved: \(id), brightness \(brightness), shift \(dx),\(dy)") }
                    cases += 1
                } }
            }
        }
        check(resolved==cases,"Only \(resolved)/\(cases) shaded-cross cases resolved")
        // Cover the same cross with opaque objects, including wood-colored
        // objects and a one-axis dark vein. Visible neighboring rails are not
        // permission to erase a new stone at this intersection.
        let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:root.appendingPathComponent("10.json")))
        let original=image("10.png"),w=original.width,h=original.height
        var bytes=[UInt8](repeating:0,count:w*h*4)
        let flags=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        bytes.withUnsafeMutableBytes { raw in
            let c=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:flags)!
            c.draw(original,in:CGRect(x:0,y:0,width:w,height:h))
        }
        let q=meta.calibration.point(col:12.18,row:15.18)
        let qi=(Int(q.y*Double(h-1))*w+Int(q.x*Double(w-1)))*4
        let wood=(0..<3).map{bytes[qi+$0]}
        var negatives=0
        for (col,row,radius) in [(12.0,15.0,0.42),(12.25,15.0,0.40),(12.0,15.0,0.22)] {
            for (color,stripe) in [([UInt8(25),25,25],false),([UInt8(235),235,235],false),(wood,false),(wood,true)] {
                var changed=bytes
                let center=meta.calibration.point(col:col,row:row),cx=Int(center.x*Double(w-1)),cy=Int(center.y*Double(h-1))
                for y in max(0,cy-50)...min(h-1,cy+50) { for x in max(0,cx-50)...min(w-1,cx+50) {
                    guard let p=meta.calibration.gridPoint(for:ImagePoint(x:Double(x)/Double(w-1),y:Double(y)/Double(h-1))),
                        pow((p.x-col)/radius,2)+pow((p.y-row)/(radius*1.06),2)<=1 else {continue}
                    for channel in 0..<3 {changed[(y*w+x)*4+channel]=(stripe && abs(p.x-col)<0.025) ? 40:color[channel]}
                } }
                let cg=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,
                    space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:flags),
                    provider:CGDataProvider(data:Data(changed) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
                let result=BoardDetector.detect(frame:GrayFrame(image:cg)!,reference:reference,calibration:meta.calibration,
                    threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
                check(result.signature[target] != .empty,"Erased a covered cross: \(color), stripe \(stripe), radius \(radius), col \(col)")
                negatives += 1
            }
        }
        print("PASS: \(resolved)/\(cases) shaded-cross brightness/alignment cases, all 37 stones retained; \(negatives) opaque/one-axis/displaced/small-object checks")
    }
}
