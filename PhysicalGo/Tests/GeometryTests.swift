import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct GeometryTests {
    static func main() throws {
        setbuf(stdout,nil)
        struct Meta:Decodable { let calibration:BoardCalibration; let referenceCalibration:BoardCalibration; let threshold:Double; let readings:[IntersectionReading] }
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/DisplacedRound2")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
        func load(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        let image=load("frame.png"),reference=GrayFrame(image:load("empty-reference.png"))!
        let expected=meta.readings.filter{$0.occupancy.stone != nil},target=14*19+18
        let context=CIContext(),input=CIImage(cgImage:image)
        var cases=0,worst=0.0,resolved=0,complete=0
        for brightness in [-0.005,0,0.005] {
            let adjusted=context.createCGImage(input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:input.extent)!
            for dy in [-0.5,0,0.5] { for dx in [-0.5,0,0.5] {
                let cal=BoardCalibration(size:19,corners:meta.calibration.corners.map{ImagePoint(x:$0.x+dx/1919,y:$0.y+dy/1079)})!
                let start=Date()
                let result=BoardDetector.detect(frame:GrayFrame(image:adjusted)!,reference:reference,calibration:cal,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
                worst=max(worst,Date().timeIntervalSince(start))
                for stone in expected {
                    let actual=result.readings[stone.row*19+stone.col].occupancy
                    guard actual==stone.occupancy || actual == .uncertain else { fatalError("Geometry erased or recolored a real stone") }
                }
                for reading in result.readings where reading.occupancy.stone != nil {
                    guard meta.readings[reading.row*19+reading.col].occupancy==reading.occupancy else { fatalError("Invented a neighboring stone") }
                }
                if brightness==0 && dx==0 && dy==0 {
                    guard result.snapshot.stones.count==21,result.readings[target].occupancy == .empty,
                          result.signature.filter({$0 == .uncertain}).count<=8,result.footprints.count>=19 else { fatalError("Saved geometry regression did not improve") }
                    print("Saved frame:",result.footprints.count,"outlines,",result.signature.filter{$0 == .uncertain}.count,"uncertain")
                }
                if result.readings[target].occupancy == .empty { resolved += 1 }
                if result.snapshot.stones.count==21 { complete += 1 }
                cases += 1
            } }
        }
        // Directly exercise the refinement with a real extra object deliberately
        // labeled uncertain, so an earlier classifier cannot hide a false-empty bug.
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        let flags=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        bytes.withUnsafeMutableBytes { raw in
            let ctx=CGContext(data:raw.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:flags)!
            ctx.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        let q=meta.calibration.point(col:18.2,row:14.3)
        let qi=(Int(q.y*1079)*1920+Int(q.x*1919))*4
        let wood=(0..<3).map{UInt8(Double(bytes[qi+$0])*0.92)}
        func painted(_ color:[UInt8],col:Double,row:Double,radius:Double)->GrayFrame {
            var changed=bytes
            let center=meta.calibration.point(col:col,row:row)
            let cx=Int(center.x*1919),cy=Int(center.y*1079)
            for y in max(0,cy-70)...min(1079,cy+70) { for x in max(0,cx-70)...min(1919,cx+70) {
                guard let p=meta.calibration.gridPoint(for:ImagePoint(x:Double(x)/1919,y:Double(y)/1079)),
                    pow((p.x-col)/radius,2)+pow((p.y-row)/(radius*1.06),2)<=1 else { continue }
                for channel in 0..<3 { changed[(y*1920+x)*4+channel]=color[channel] }
            } }
            let cg=CGImage(width:1920,height:1080,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:1920*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:flags),provider:CGDataProvider(data:Data(changed) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            return GrayFrame(image:cg)!
        }
        func refine(_ frame:GrayFrame,blocked:Set<Int>=[])->StoneGeometry.Result {
            StoneGeometry.refine(frame:frame,reference:reference,calibration:meta.calibration,referenceCalibration:meta.referenceCalibration,
                readings:meta.readings,blocked:blocked,correction:0,colorShift:BoardChroma(red:0,green:0))
        }
        guard refine(GrayFrame(image:image)!).readings[target].occupancy == .empty else { fatalError("Counterexample harness did not exercise active refinement") }
        for color in [[UInt8(25),25,25],[UInt8(235),235,235],wood] {
            for (col,row,radius) in [(18.2,14.0,0.40),(18.44,14.0,0.35),(18.0,14.0,0.22)] {
                let result=refine(painted(color,col:col,row:row,radius:radius))
                guard result.readings[target].occupancy == .uncertain else { fatalError("Explained away an extra object: \(color), \(col),\(row), radius \(radius)") }
            }
        }
        let blocked=refine(GrayFrame(image:image)!,blocked:[target])
        guard blocked.readings[target].occupancy == .uncertain else { fatalError("Disputed ownership was overridden") }
        print("PASS: \(cases) lighting/alignment cases; extra black, white and wood-colored objects, extreme displacement, small objects, and blocked ownership. Target resolved in \(resolved)/\(cases); all stones in \(complete)/\(cases). Worst full detection: \(worst)s")
    }
}
