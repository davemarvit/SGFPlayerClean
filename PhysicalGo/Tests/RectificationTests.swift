import Foundation
import CoreGraphics
import ImageIO

struct RectificationTests {
    static func run() throws -> Int {
        var count=0
        func check(_ condition:Bool,_ message:String) {
            guard condition else { fatalError(message) }; count += 1
        }
        // Independently project a physical rectangle through a known pinhole camera.
        func board(rows:Bool,pitch:Double,yaw:Double)->BoardCalibration {
            let w=rows ? 1.0 : BoardRectifiedGeometry.longToShort
            let h=rows ? BoardRectifiedGeometry.longToShort : 1.0
            let corners=[(-0.5,-0.5),(0.5,-0.5),(0.5,0.5),(-0.5,0.5)].map { u,v in
                let x=u*w,y=v*h
                let xx=cos(yaw)*x+sin(yaw)*sin(pitch)*y
                let yy=cos(pitch)*y
                let zz=3-sin(yaw)*x+cos(yaw)*sin(pitch)*y
                return ImagePoint(x:(499.5+1000*xx/zz)/999,y:(399.5+1000*yy/zz)/799)
            }
            return BoardCalibration(size:19,corners:corners)!
        }
        for rows in [false,true] {
            for angles in [(0.0,0.0),(0.45,0.55),(-0.45,0.55),(0.55,-0.45)] {
                let cal=board(rows:rows,pitch:angles.0,yaw:angles.1)
                let estimate=BoardAspectEstimate.estimate(cal,width:1000,height:800)
                check(estimate.longAxisRows==rows,"Wrong long side for known camera: \(rows), \(angles)")
                check(estimate.confident,"Unconfident known camera: \(rows), \(angles)")
            }
        }
        let ambiguous=BoardAspectEstimate.estimate(board(rows:true,pitch:0.7,yaw:0),width:1000,height:800)
        check(!ambiguous.confident,"Axial tilt must not pretend the unknown focal length is determined")
        let cal=board(rows:true,pitch:0.45,yaw:0.55)
        let geometry=BoardRectifiedGeometry(calibration:cal,longAxisRows:true)
        check(geometry.outputSize.height>geometry.outputSize.width,"Long rows must render vertically")
        let other=BoardRectifiedGeometry(calibration:cal,longAxisRows:false)
        check(other.outputSize.width>other.outputSize.height,"Long columns must render horizontally")
        for point in [ImagePoint(x:0,y:0),ImagePoint(x:18,y:18),ImagePoint(x:5,y:12),ImagePoint(x:-0.5,y:18.5)] {
            let source=cal.point(col:point.x,row:point.y)
            let back=cal.gridPoint(for:source)!
            check(hypot(back.x-point.x,back.y-point.y)<1e-8,"Inverse homography lost grid coordinates")
            let normalized=geometry.normalizedPoint(from:source)!
            for turns in 0..<4 {
                let orientation=BoardOrientation(turns)
                let recovered=geometry.sourcePoint(from:orientation.source(orientation.display(normalized)))
                check(hypot(recovered.x-source.x,recovered.y-source.y)<1e-9,"Rotated corrected-view hit testing lost source coordinates")
            }
        }
        check(cal.gridPoint(for:ImagePoint(x:.nan,y:0)) == nil,"NaN should not enter inverse mapping")
        // Raster landmarks independently check Core Image's bottom-left origin,
        // cropping, aspect scaling, and preservation of edge stones.
        let landmarks=[(0.0,0.0),(18,0),(18,18),(0,18),(5,12)]
        var pixels=[UInt8](repeating:180,count:1000*800)
        for (col,row) in landmarks {
            let p=cal.point(col:col,row:row),cx=Int(p.x*999),cy=Int(p.y*799)
            for y in cy-7...cy+7 { for x in cx-7...cx+7 where hypot(Double(x-cx),Double(y-cy))<7 { pixels[y*1000+x]=10 } }
        }
        let provider=CGDataProvider(data:Data(pixels) as CFData)!
        let input=CGImage(width:1000,height:800,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:1000,
                          space:CGColorSpaceCreateDeviceGray(),bitmapInfo:[],provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let output=BoardRectifier.render(input,geometry:geometry)!
        check(output.width==960 && output.height==1030,"Rectified dimensions must use standard 22:23.6 proportions")
        let gray=GrayFrame(image:output)!
        for (col,row) in landmarks {
            let p=ImagePoint(x:(col+0.75)/19.5,y:(row+0.75)/19.5)
            check(gray.sample(p)!<0.15,"Rectification displaced or flipped a landmark at \(col),\(row)")
        }
        check(gray.sample(ImagePoint(x:0.5,y:0.5))!>0.4,"Rectified blank center was corrupted")
        print("PASS: \(count) rectification and automatic aspect checks")
        return count
    }
}
