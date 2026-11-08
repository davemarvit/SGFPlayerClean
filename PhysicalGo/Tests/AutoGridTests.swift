import Foundation
import CoreGraphics
import ImageIO

@main struct AutoGridTests {
    static func main() throws {
        setbuf(stdout, nil)
        var count = 0
        func check(_ condition:@autoclosure () -> Bool,_ message:String) {
            count += 1
            if !condition() { fatalError(message) }
        }
        let folder=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures/EdgeStones")
        func photo(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        let reference=photo("empty-reference.png"), occupied=photo("frame.png")
        for (name,image) in [("empty",reference),("two stones",occupied)] {
            let start=Date()
            guard let result=try AutoGridDetector.detect(image:image,size:19) else { fatalError("No grid in real \(name) photo") }
            let expected=[CGPoint(x:505,y:69),CGPoint(x:1482,y:54),CGPoint(x:1617,y:1015),CGPoint(x:403,y:1014)]
            for (i,p) in result.calibration.corners.enumerated() {
                let error=hypot(p.x*1919-expected[i].x,p.y*1079-expected[i].y)
                check(error<10,"Real \(name): playable corner \(i) is \(error) pixels away")
            }
            let observation=BoardDetector.detect(frame:GrayFrame(image:occupied)!,reference:GrayFrame(image:reference)!,calibration:result.calibration,threshold:0.13)!
            check(observation.readings[15*19].occupancy == .white,"Auto calibration preserves white A4")
            check(observation.readings[18*19+5].occupancy == .black,"Auto calibration preserves black F1")
            check(observation.snapshot.stones.count==2,"Auto calibration does not create extra stones")
            check(!observation.signature.contains(.uncertain),"Auto calibration keeps the other intersections clear")
            print("Real \(name): corners \(result.calibration.corners), \(Date().timeIntervalSince(start)) seconds")
        }
        let failureFolder=folder.deletingLastPathComponent().appendingPathComponent("GridOutlineFailure")
        let expectedFailure=try JSONSerialization.jsonObject(with:Data(contentsOf:failureFolder.appendingPathComponent("expected.json"))) as! [String:Any]
        for name in ["frame.png","screenshot-camera.png"] {
            let source=CGImageSourceCreateWithURL(failureFolder.appendingPathComponent(name) as CFURL,nil)!
            let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
            guard let result=try AutoGridDetector.detect(image:image,size:19) else { fatalError("No grid in clear-board regression \(name)") }
            let expected=expectedFailure[name] as! [[Double]]
            for (i,p) in result.calibration.corners.enumerated() {
                let error=hypot(p.x*Double(image.width-1)-expected[i][0],p.y*Double(image.height-1)-expected[i][1])
                check(error<10,"Clear-board \(name): playable corner \(i) is \(error) pixels away")
            }
        }
        let failureSource=CGImageSourceCreateWithURL(failureFolder.appendingPathComponent("frame.png") as CFURL,nil)!
        let failureImage=CGImageSourceCreateImageAtIndex(failureSource,0,nil)!
        let landmarks=expectedFailure["frame.png"] as! [[Double]]
        for variation in [Variation(name:"dimmer",brightness:0.85), Variation(name:"brighter",brightness:1.15),
                          Variation(name:"720p",scale:2.0/3.0), Variation(name:"540p",scale:0.5),
                          Variation(name:"shifted",dx:12,dy:-8), Variation(name:"clockwise",angle:2),
                          Variation(name:"counterclockwise",angle:-2)] {
            let fixture=variant(failureImage,landmarks:landmarks,variation:variation)
            let start=Date()
            guard let result=try AutoGridDetector.detect(image:fixture.image,size:19) else { fatalError("No grid in real-image variation \(variation.name)") }
            for (i,p) in result.calibration.corners.enumerated() {
                let expected=fixture.corners[i]
                let error=hypot(p.x*Double(fixture.image.width-1)-expected.x,p.y*Double(fixture.image.height-1)-expected.y)
                check(error<max(6,10*variation.scale),"Variation \(variation.name): corner \(i) is \(error) pixels away")
            }
            print("Variation \(variation.name): correct grid, \(Date().timeIntervalSince(start)) seconds")
        }
        for wrongSize in [9,13] {
            check(try! AutoGridDetector.detect(image:failureImage,size:wrongSize) == nil,"Smoothing must not accept a wrong-size subset: \(wrongSize)")
        }
        for wrongSize in [9,13] {
            check(try! AutoGridDetector.detect(image:reference,size:wrongSize) == nil,"Reject wrong board size \(wrongSize) on a 19 grid")
        }
        for (size,rotation) in [(9,0.0),(13,15.0),(19,-15.0)] {
            let fixture=synthetic(size:size,rotation:rotation)
            guard let result=try AutoGridDetector.detect(image:fixture.image,size:size) else { fatalError("No synthetic \(size) grid") }
            for (i,p) in result.calibration.corners.enumerated() {
                let expected=fixture.calibration.corners[i]
                check(hypot((p.x-expected.x)*900,(p.y-expected.y)*720)<7,"Synthetic \(size): correct corner \(i)")
            }
        }
        check(try! AutoGridDetector.detect(image:synthetic(size:19,rotation:0,drawGrid:false).image,size:19) == nil,"Plain wooden rectangle is not a Go grid")
        check(try! AutoGridDetector.detect(image:synthetic(size:19,rotation:0,vertical:false).image,size:19) == nil,"One family of stripes is not a Go grid")
        let cropped=reference.cropping(to:CGRect(x:0,y:250,width:1920,height:830))!
        check(try! AutoGridDetector.detect(image:cropped,size:19) == nil,"Incomplete grid does not silently become a complete calibration")
        print("PASS: \(count) automatic grid checks, including real photos, edge-stone preservation, wrong sizes, 9/13/19 grids, rotated perspective views, plain borders, stripes and cropping.")
    }
    struct Variation {
        let name: String
        var scale=1.0, brightness=1.0, dx=0.0, dy=0.0, angle=0.0
    }
    static func variant(_ image:CGImage,landmarks:[[Double]],variation v:Variation)->(image:CGImage,corners:[CGPoint]) {
        let source=GrayFrame(image:image)!
        let width=Int(Double(image.width)*v.scale),height=Int(Double(image.height)*v.scale)
        let cx=Double(image.width-1)/2,cy=Double(image.height-1)/2
        let cosine=cos(v.angle*Double.pi/180),sine=sin(v.angle*Double.pi/180)
        var pixels=[UInt8](repeating:0,count:width*height)
        for y in 0..<height { for x in 0..<width {
            let tx=(Double(x)+0.5)/v.scale-0.5-cx-v.dx,ty=(Double(y)+0.5)/v.scale-0.5-cy-v.dy
            let sx=cosine*tx+sine*ty+cx,sy = -sine*tx+cosine*ty+cy
            if sx>=0 && sy>=0 && sx<Double(image.width-1) && sy<Double(image.height-1) {
                let ix=Int(sx),iy=Int(sy),a=sx-Double(Int(sx)),b=sy-Double(Int(sy))
                let top=Double(source.pixels[iy*image.width+ix])*(1-a)+Double(source.pixels[iy*image.width+ix+1])*a
                let bottom=Double(source.pixels[(iy+1)*image.width+ix])*(1-a)+Double(source.pixels[(iy+1)*image.width+ix+1])*a
                pixels[y*width+x]=UInt8(max(0,min(255,(top*(1-b)+bottom*b)*v.brightness)))
            }
        } }
        let output=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:Data(pixels) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let corners=landmarks.map { point -> CGPoint in
            let x=point[0]-cx,y=point[1]-cy
            return CGPoint(x:(cosine*x-sine*y+cx+v.dx+0.5)*v.scale-0.5,y:(sine*x+cosine*y+cy+v.dy+0.5)*v.scale-0.5)
        }
        return (output,corners)
    }
    static func synthetic(size:Int,rotation:Double,drawGrid:Bool=true,vertical:Bool=true)->(image:CGImage,calibration:BoardCalibration) {
        let width=900,height=720
        let angle=rotation*Double.pi/180
        func rotate(_ p:ImagePoint)->ImagePoint {
            let x=(p.x-0.5)*Double(width),y=(p.y-0.5)*Double(height)
            return ImagePoint(x:(x*cos(angle)-y*sin(angle))/Double(width)+0.5,y:(x*sin(angle)+y*cos(angle))/Double(height)+0.5)
        }
        let corners=[ImagePoint(x:0.23,y:0.20),ImagePoint(x:0.77,y:0.17),ImagePoint(x:0.82,y:0.80),ImagePoint(x:0.17,y:0.83)].map(rotate)
        let calibration=BoardCalibration(size:size,corners:corners)!
        let n=Double(size-1),m=n*0.035
        let wood=[calibration.point(col:-m,row:-m),calibration.point(col:n+m,row:-m),calibration.point(col:n+m,row:n+m),calibration.point(col:-m,row:n+m)]
        var pixels=[UInt8](repeating:70,count:width*height)
        for y in 0..<height { for x in 0..<width {
            let p=ImagePoint(x:Double(x)/Double(width-1),y:Double(y)/Double(height-1))
            var inside = true
            for i in 0..<4 {
                let a = wood[i], b = wood[(i+1)%4]
                let cross: Double = (b.x-a.x)*(p.y-a.y) - (b.y-a.y)*(p.x-a.x)
                if cross < 0 { inside = false; break }
            }
            if inside { pixels[y*width+x]=UInt8(195+x/40) }
        } }
        func line(_ a:ImagePoint,_ b:ImagePoint) {
            let ax=a.x*Double(width-1),ay=a.y*Double(height-1),bx=b.x*Double(width-1),by=b.y*Double(height-1)
            let vx=bx-ax,vy=by-ay,den=vx*vx+vy*vy
            let xmin=max(0,Int(min(ax,bx))-3),xmax=min(width-1,Int(max(ax,bx))+3)
            let ymin=max(0,Int(min(ay,by))-3),ymax=min(height-1,Int(max(ay,by))+3)
            for y in ymin...ymax { for x in xmin...xmax {
                let t=max(0,min(1,((Double(x)-ax)*vx+(Double(y)-ay)*vy)/den))
                let d=hypot(Double(x)-ax-t*vx,Double(y)-ay-t*vy)
                let coverage=max(0,min(1,1.3-d))
                pixels[y*width+x]=UInt8(Double(pixels[y*width+x])*(1-coverage)+35*coverage)
            } }
        }
        if drawGrid {
            for i in 0..<size {
                line(calibration.point(col:0,row:Double(i)),calibration.point(col:n,row:Double(i)))
                if vertical { line(calibration.point(col:Double(i),row:0),calibration.point(col:Double(i),row:n)) }
            }
        }
        let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:Data(pixels) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        return (image,calibration)
    }
}
