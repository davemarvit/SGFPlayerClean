import Foundation
import CoreGraphics
import ImageIO

enum PlacementTests {
    static func run() throws -> Int {
        var count = 0
        func check(_ value:@autoclosure ()->Bool,_ message:String) {
            count += 1
            guard value() else { fatalError(message) }
        }
        struct Sample:Decodable { let calibration:BoardCalibration; let threshold:Double }
        struct Expected:Decodable {
            struct Point:Decodable { let row:Int; let col:Int; let occupancy:Occupancy }
            let stones:[Point]
        }
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures")
        for name in ["AdjacentOffset","CenterFlicker","RapidPlayStall"] {
            let folder=root.appendingPathComponent(name)
            let sample=try JSONDecoder().decode(Sample.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
            let expected=try JSONDecoder().decode(Expected.self,from:Data(contentsOf:folder.appendingPathComponent("expected.json")))
            func load(_ name:String)->CGImage {
                let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!
                return CGImageSourceCreateImageAtIndex(source,0,nil)!
            }
            let liveImage=load("frame.png"),reference=GrayFrame(image:load("empty-reference.png"))!
            let frame=GrayFrame(image:liveImage)!
            for (dx,dy) in [(0.0,0.0),(-1.0,0.0),(1.0,0.0),(0.0,-1.0),(0.0,1.0)] {
                let corners=sample.calibration.corners.map { ImagePoint(x:$0.x+dx/Double(frame.width-1),y:$0.y+dy/Double(frame.height-1)) }
                let calibration=BoardCalibration(size:19,corners:corners)!
                let observation=BoardDetector.detect(frame:frame,reference:reference,calibration:calibration,threshold:sample.threshold)!
                for stone in expected.stones { check(observation.readings[stone.row*19+stone.col].occupancy==stone.occupancy,"\(name): stone assignment at \(stone.row),\(stone.col), calibration shift \(dx),\(dy)") }
                check(observation.snapshot.stones.count==expected.stones.count,"\(name): no duplicate stones")
                if dx == 0 && dy == 0 && name != "RapidPlayStall" {
                    check(!observation.signature.contains(.uncertain),"\(name): clear background and stone classifications")
                }
            }
            if name == "CenterFlicker" {
                let bytes=rgba(liveImage)
                for step in 0..<8 {
                    var changed=bytes
                    for i in stride(from:0,to:changed.count,by:4) {
                        let noise=(i/4*31+step*13)%5-2
                        for channel in 0..<3 { changed[i+channel]=UInt8(max(0,min(255,Int(bytes[i+channel])+noise))) }
                    }
                    let image=colorImage(changed,width:frame.width,height:frame.height)
                    let observation=BoardDetector.detect(frame:GrayFrame(image:image)!,reference:reference,calibration:sample.calibration,threshold:sample.threshold)!
                    check(observation.readings[9*19+7].occupancy == .white,"Captured flicker stays white under small deterministic pixel noise: \(step)")
                    check(observation.snapshot.stones.count==9,"Noise does not create neighboring stones")
                }
            }
        }

        let size=9,width=720,height=720
        let corners=[ImagePoint(x:0.1,y:0.1),ImagePoint(x:0.9,y:0.1),ImagePoint(x:0.9,y:0.9),ImagePoint(x:0.1,y:0.9)]
        let calibration=BoardCalibration(size:size,corners:corners)!
        let pitch=Double(width-1)*0.8/8
        func board(_ color:[UInt8],shift:Int=0)->[UInt8] {
            var bytes=[UInt8](repeating:255,count:width*height*4)
            for y in 0..<height { for x in 0..<width {
                let gx=(Double(x-shift)-Double(width-1)*0.1)/pitch
                let gy=(Double(y-shift)-Double(height-1)*0.1)/pitch
                let inside = gx >= -0.02 && gx <= 8.02 && gy >= -0.02 && gy <= 8.02
                let ink = inside && (abs(gx-gx.rounded())*pitch<1.2 || abs(gy-gy.rounded())*pitch<1.2)
                for channel in 0..<3 { bytes[(y*width+x)*4+channel]=ink ? 35 : color[channel] }
            } }
            return bytes
        }
        func stone(_ input:[UInt8],col:Double,row:Double,color:[UInt8],radius:Double=0.42,keepInk:Bool=false)->[UInt8] {
            var bytes=input
            let p=calibration.point(col:col,row:row),cx=p.x*Double(width-1),cy=p.y*Double(height-1),r=radius*pitch
            for y in max(0,Int(cy-r))...min(height-1,Int(cy+r)) { for x in max(0,Int(cx-r))...min(width-1,Int(cx+r)) where hypot(Double(x)-cx,Double(y)-cy)<r {
                let index=(y*width+x)*4
                if keepInk && input[index]==35 { continue }
                for channel in 0..<3 { bytes[index+channel]=color[channel] }
            } }
            return bytes
        }
        let baseline=board([190,175,100])
        let reference=GrayFrame(image:colorImage(baseline,width:width,height:height))!
        func detect(_ bytes:[UInt8])->BoardObservation {
            BoardDetector.detect(frame:GrayFrame(image:colorImage(bytes,width:width,height:height))!,reference:reference,calibration:calibration,threshold:0.13)!
        }
        let lowContrast=stone(baseline,col:3,row:3,color:[185,185,185])
        check(detect(lowContrast).readings[3*size+3].occupancy == .white,"Color and covered printed lines identify a low-brightness-contrast white stone")
        check(detect(stone(baseline,col:3,row:3,color:[185,185,185],keepInk:true)).snapshot.stones.isEmpty,"Color change with grid still visible is not a white stone")
        check(detect(board([192,175,110])).snapshot.stones.isEmpty,"Spatial color correction rejects uniform white-balance drift")
        check(detect(board([190,175,100],shift:2)).snapshot.stones.isEmpty,"Shifted printed lines alone are not white stones")
        for color in [[UInt8(235),235,235],[UInt8(25),25,25]] {
            let first=stone(baseline,col:3,row:4,color:color)
            let pair=detect(stone(first,col:4,row:4,color:color))
            check(pair.snapshot.stones.count==2,"Genuine adjacent same-color stones remain separate")
        }
        let displaced=detect(stone(baseline,col:3.32,row:3.77,color:[235,235,235],radius:0.4))
        check(displaced.readings[4*size+3].occupancy == .white && displaced.snapshot.stones.count==1,"Displaced stone belongs to its nearest intersection")
        let ambiguous=detect(stone(baseline,col:3.5,row:4,color:[235,235,235],radius:0.55))
        check(ambiguous.snapshot.stones.isEmpty,"One large stone between points must not become two stones")
        check(ambiguous.readings[4*size+3].occupancy == .uncertain && ambiguous.readings[4*size+4].occupancy == .uncertain,"Competing intersection claims remain uncertain")

        let p=ImagePoint(x:0.2,y:0.7)
        let expectedPoints=[p,ImagePoint(x:0.3,y:0.2),ImagePoint(x:0.8,y:0.3),ImagePoint(x:0.7,y:0.8)]
        for turns in 0..<4 {
            let orientation=BoardOrientation(turns),displayed=orientation.display(p),restored=orientation.source(displayed)
            check(hypot(displayed.x-expectedPoints[turns].x,displayed.y-expectedPoints[turns].y)<1e-10,"Clockwise display orientation \(turns)")
            check(hypot(restored.x-p.x,restored.y-p.y)<1e-10,"Rotated taps map back to the original image")
            check(orientation.canonicalCorners(orientation.displayedCorners(corners))==corners,"Rotated manual corner order remains canonical")
        }
        print("PASS: \(count) placement, color, printed-line coverage, noise and rotation checks.")
        return count
    }
    private static func colorImage(_ bytes:[UInt8],width:Int,height:Int)->CGImage {
        let flags=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:flags),
            provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
    }
    private static func rgba(_ image:CGImage)->[UInt8] {
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        bytes.withUnsafeMutableBytes { raw in
            let flags=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            let context=CGContext(data:raw.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,
                bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:flags)!
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        return bytes
    }
}
