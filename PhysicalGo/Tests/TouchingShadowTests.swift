import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct TouchingShadowTests {
    struct Metadata:Decodable {
        let calibration:BoardCalibration,referenceCalibration:BoardCalibration
        let threshold:Double
        let readings:[IntersectionReading]
    }
    static func main() throws {
        setbuf(stdout,nil)
        func check(_ value:Bool,_ message:String) {if !value {print("FAIL:",message);exit(1)}}
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/TouchingShadow")
        let target=13*19+5,context=CIContext()
        func image(_ name:String)->CGImage {
            CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!
        }
        let reference=GrayFrame(image:image("empty-reference.png"))!
        var cases=0,resolved=0
        for id in [17] {
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
                    check(result.signature[12*19+3] == .empty,"Other empty cross unresolved")
                    cases += 1
                } }
            }
        }
        check(resolved==cases,"Only \(resolved)/\(cases) shaded-cross cases resolved")
        // Cover the same cross with opaque objects, including wood-colored
        // objects and a one-axis dark vein. Visible neighboring rails are not
        // permission to erase a new stone at this intersection.
        let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:root.appendingPathComponent("17.json")))
        let original=image("17.png"),w=original.width,h=original.height
        var bytes=[UInt8](repeating:0,count:w*h*4)
        let flags=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        bytes.withUnsafeMutableBytes { raw in
            let c=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:flags)!
            c.draw(original,in:CGRect(x:0,y:0,width:w,height:h))
        }
        let q=meta.calibration.point(col:5.18,row:13.18)
        let qi=(Int(q.y*Double(h-1))*w+Int(q.x*Double(w-1)))*4
        let wood=(0..<3).map{bytes[qi+$0]}
        var negatives=0,withdrawnEmpty=0,remainingEmpty=0
        // Frozen baseline classifications for adversarial covers. Missing-grid
        // evidence may now withdraw a false empty call; it must not invent a
        // black/white color for a wood-colored object or erase a known stone.
        let baselineCovers:[Occupancy]=[.black,.white,.empty,.empty,.black,.white,.uncertain,.uncertain,.uncertain,.uncertain,.empty,.empty]
        for (col,row,radius) in [(5.0,13.0,0.42),(5.25,13.0,0.40),(5.0,13.0,0.22)] {
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
                let value=result.signature[target],baseline=baselineCovers[negatives]
                if baseline == .empty {
                    check(value == .empty || value == .uncertain,"Invented a stone color for a wood-colored cover")
                    if value == .uncertain {withdrawnEmpty += 1} else {remainingEmpty += 1}
                    if negatives==2 {check(value == .uncertain,"A normal-size plain wood-colored cover must contradict empty")}
                } else {check(value==baseline,"Changed a known stone/ambiguous cover classification") }
                negatives += 1
            }
        }
        check(withdrawnEmpty>0,"Expected missing-grid check to challenge a false empty")
        print("PASS: \(resolved)/\(cases) shaded-cross variants, all 11 stones retained; \(negatives) cover cases, \(withdrawnEmpty) false empty calls withdrawn; \(remainingEmpty) preexisting small/striped wood-cover limitations remain")
    }
}
