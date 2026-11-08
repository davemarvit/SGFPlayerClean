import Foundation
import CoreGraphics
import ImageIO
import CoreImage

@main struct GridAspectTests {
    static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;if !value {print("FAIL:",message);exit(1)}}
        struct Metadata:Decodable {let calibration:BoardCalibration}
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures")
        for name in ["SideCameraEmpty","LongSideBump","DisplacedRound2","RecordingStalled","ReferenceOffset","MultipleDisplaced","GrainedWhite","LargeCameraMove"] {
            let folder=root.appendingPathComponent(name)
            let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent("frame.png") as CFURL,nil)!
            let image=CGImageSourceCreateImageAtIndex(source,0,nil)!,frame=GrayFrame(image:image,includeColor:false)!
            let lines=GridLineAspectEstimator.estimate(frame:frame,calibration:meta.calibration)
            print(name,"rows",lines.map{String($0.longAxisRows)} ?? "unknown","ratio",lines?.medianRatio ?? 0,"pairs",lines?.sampleCount ?? 0)
            if name=="LargeCameraMove" {check(lines==nil,"Unaligned grid must not provide axis evidence");continue}
            check(lines?.longAxisRows==false,"Actual camera fixture must recover long columns: \(name)")
            let resolved=BoardAspectEstimate.estimate(meta.calibration,width:frame.width,height:frame.height,frame:frame)
            check(resolved.longAxisRows==false && resolved.confident,"Combined aspect must use printed-grid evidence: \(name)")
            if name=="SideCameraEmpty" {
                let old=BoardAspectEstimate.estimate(meta.calibration,width:frame.width,height:frame.height)
                check(!old.confident,"Failure fixture must expose corner-only ambiguity")
                let turns=BoardViewOrientationPolicy.preferredTurns(current:0,longAxisRows:resolved.longAxisRows)
                check(turns==1,"Actual side-camera fixture needs an odd quarter-turn for the true long side")
                // Circular stones are unnecessary: the user's empty board must work.
                check(resolved.gridLineSamples>=100,"Actual empty image needs distributed support")
                let corrected=BoardRectifier.render(image,geometry:.init(calibration:meta.calibration,longAxisRows:resolved.longAxisRows))!
                let upright=CIImage(cgImage:corrected).oriented(.right)
                let rendered=CIContext().createCGImage(upright,from:upright.extent)!
                let output=root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/corrected-long-side.png")
                let destination=CGImageDestinationCreateWithURL(output as CFURL,"public.png" as CFString,1,nil)!
                CGImageDestinationAddImage(destination,rendered,nil);check(CGImageDestinationFinalize(destination),"Render actual corrected view")
            }
        }
        let width=1200,height=1000,size=19
        for (rows,tilt,focal,samples) in [(false,0.35,1000.0,4),(false,0.35,1600.0,8),(false,0.65,1600.0,8),(true,0.35,1600.0,8),(true,0.65,1600.0,8)] {
            let ratio=BoardRectifiedGeometry.longToShort
            let w=rows ? 1.0:ratio,h=rows ? ratio:1.0
            let corners=[(-0.5,-0.5),(0.5,-0.5),(0.5,0.5),(-0.5,0.5)].map {u,v in
                let x=u*w,y=v*h,z=2+sin(tilt)*y
                return ImagePoint(x:(599.5+focal*x/z)/1199,y:(499.5+focal*cos(tilt)*y/z)/999)
            }
            let cal=BoardCalibration(size:size,corners:corners)!
            var pixels=[UInt8](repeating:180,count:width*height)
            let spacingX=rows ? 1.0:ratio,spacingY=rows ? ratio:1.0
            for y in 0..<height {for x in 0..<width {
                var sum=0.0
                for sy in 0..<samples {for sx in 0..<samples {
                    let p=ImagePoint(x:(Double(x)+(Double(sx)-Double(samples-1)/2)/Double(samples))/Double(width-1),y:(Double(y)+(Double(sy)-Double(samples-1)/2)/Double(samples))/Double(height-1))
                    if let grid=cal.gridPoint(for:p),grid.x>=0,grid.x<=18,grid.y>=0,grid.y<=18 {
                        let ink=abs(grid.x-grid.x.rounded())*spacingX<0.013 || abs(grid.y-grid.y.rounded())*spacingY<0.013
                        let wood=180+20*Double(x)/Double(width)
                        sum += ink ? wood*0.2:wood
                    } else {sum += 180}
                }}
                pixels[y*width+x]=UInt8((sum/Double(samples*samples)).rounded())
            }}
            let frame=GrayFrame(width:width,height:height,pixels:pixels)
            let result=GridLineAspectEstimator.estimate(frame:frame,calibration:cal)
            print("Synthetic",rows,tilt,"ratio",result?.medianRatio ?? 0)
            if focal==1000 {check(result==nil,"Conflicting subpixel rail measurements must not choose an axis")}
            else {check(result?.longAxisRows==rows,"Independent physical-grid projection must resolve both sides")}
            check(GridLineAspectEstimator.estimate(frame:.init(width:width,height:height,pixels:Array(repeating:180,count:pixels.count)),calibration:cal)==nil,"Blank wood has no axis evidence")
        }
        print("PASS: \(checks) printed-grid aspect checks on actual camera fixtures and independently projected boards")
    }
}
