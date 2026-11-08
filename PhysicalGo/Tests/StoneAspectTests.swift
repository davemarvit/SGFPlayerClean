import Foundation
import ImageIO

@main struct StoneAspectTests {
    static func main() throws {
        var checks=0
        func check(_ result:Bool,_ message:String) { checks += 1; if !result { fatalError(message) } }
        let k=BoardRectifiedGeometry.longToShort
        let points=[(2,2),(2,6),(6,2),(6,6),(4,4)]
        for rows in [false,true] { for displacement in [0.0,0.24] { for texture in [false,true] {
            let cal=BoardCalibration(size:9,corners:[.init(x:0.18,y:0.12),.init(x:0.83,y:0.16),.init(x:0.94,y:0.88),.init(x:0.06,y:0.91)])!
            let width=800,height=720
            var pixels=[UInt8](repeating:165,count:width*height)
            for y in 0..<height { for x in 0..<width {
                guard let p=cal.gridPoint(for:.init(x:Double(x)/Double(width-1),y:Double(y)/Double(height-1))) else { continue }
                if abs(p.x-p.x.rounded())<0.012 || abs(p.y-p.y.rounded())<0.012 { pixels[y*width+x]=40 }
                for (i,point) in points.enumerated() {
                    let dx=p.x-Double(point.1)-displacement,dy=p.y-Double(point.0)+displacement/2
                    let rx=rows ? 0.44 : 0.44/k,ry=rows ? 0.44/k : 0.44
                    if pow(dx/rx,2)+pow(dy/ry,2)<1 {
                        pixels[y*width+x]=i%2==0 ? 20 : 240
                        if texture && hypot(dx-0.06,dy+0.06)<0.10 { pixels[y*width+x]=i%2==0 ? 240 : 140 }
                    }
                }
            } }
            let readings=points.enumerated().map { i,p in IntersectionReading(row:p.0,col:p.1,occupancy:i%2==0 ? .black : .white,confidence:1,delta:0) }
            let result=StoneAspectEstimator.estimate(frame:.init(width:width,height:height,pixels:pixels),calibration:cal,readings:readings)
            check(result?.longAxisRows==rows,"Wrong stone-based orientation for rows=\(rows), displacement=\(displacement), texture=\(texture)")
        } } }
        func measurements(_ ratios:[Double])->[StoneAspectEstimator.Measurement] {
            ratios.enumerated().map{.init(row:$0.offset+1,col:$0.offset+1,color:$0.offset%2==0 ? .black : .white,ratio:$0.element)}
        }
        check(StoneAspectEstimator.consensus(measurements([1,1,1,1]))==nil,"Square/ambiguous stone geometry forced an orientation")
        check(StoneAspectEstimator.consensus(measurements([k,k]))==nil,"Two stones were treated as strong evidence")
        check(StoneAspectEstimator.consensus(measurements([1.3,1.3,1.3,1.3]))==nil,"Strongly distorted shapes forced an orientation")
        check(StoneAspectEstimator.consensus(measurements([k,1/k,k,1/k]))==nil,"Black/white disagreement was ignored")
        check(StoneAspectEstimator.consensus(measurements([k,k,k,k,k,0.8]))?.longAxisRows==true,"Single shape outlier defeated consensus")

        for name in ["LongSideBump","DisplacedRound2","RecordingStalled","ReferenceOffset","MultipleDisplaced","GrainedWhite","LargeCameraMove"] {
            let folder=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures/"+name)
            guard FileManager.default.fileExists(atPath:folder.path) else { continue }
            struct Metadata:Decodable { let calibration:BoardCalibration;let readings:[IntersectionReading] }
            let metadata=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent("frame.png") as CFURL,nil)!
            let frame=GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
            let start=ProcessInfo.processInfo.systemUptime
            let measured=StoneAspectEstimator.measurements(frame:frame,calibration:metadata.calibration,readings:metadata.readings)
            let estimate=StoneAspectEstimator.consensus(measured)
            print(name,"rows",estimate.map{String($0.longAxisRows)} ?? "unknown","time",ProcessInfo.processInfo.systemUptime-start)
            if name != "LargeCameraMove" { check(estimate?.longAxisRows==false,"Saved board orientation not recovered: \(name)") }
            if name=="LongSideBump" {
                let before=measured.map{abs(log($0.ratio/k))}.reduce(0,+)/Double(measured.count)
                let after=measured.map{abs(log($0.ratio*k))}.reduce(0,+)/Double(measured.count)
                check(measured.count>=8 && after<before/2,"Corrected saved stones were not substantially rounder")
                for (label,rows) in [("before",true),("after",false)] {
                    let picture=BoardRectifier.render(CGImageSourceCreateImageAtIndex(source,0,nil)!,geometry:.init(calibration:metadata.calibration,longAxisRows:rows))!
                    let url=folder.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/stone-aspect-\(label).png")
                    let destination=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
                    CGImageDestinationAddImage(destination,picture,nil);check(CGImageDestinationFinalize(destination),"Could not render aspect comparison")
                }
            }
            print(measured.map{"\($0.row),\($0.col) \($0.color):"+String(format:"%.3f",$0.ratio)}.joined(separator:"; "))
        }
        print("PASS: \(checks) independent stone-aspect checks")
    }
}
