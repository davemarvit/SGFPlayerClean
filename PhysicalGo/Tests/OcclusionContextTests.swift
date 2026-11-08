import Foundation
import CoreGraphics

/// Controlled geometry tests, separate from the immutable photographic corpus.
@main struct OcclusionContextTests {
    static func main() {
        setbuf(stdout,nil)
        let width=640,size=9,pitch=Double(width-1)*0.8/8
        let calibration=BoardCalibration(size:size,corners:[.init(x:0.1,y:0.1),.init(x:0.9,y:0.1),.init(x:0.9,y:0.9),.init(x:0.1,y:0.9)])!
        var base=[UInt8](repeating:255,count:width*width*4)
        for y in 0..<width {for x in 0..<width {
            let gx=(Double(x)-Double(width-1)*0.1)/pitch,gy=(Double(y)-Double(width-1)*0.1)/pitch
            let ink=abs(gx-gx.rounded())*pitch<0.8 || abs(gy-gy.rounded())*pitch<0.8
            for c in 0..<3 {base[(y*width+x)*4+c]=ink ? 85 : [190,175,100][c]}
        }}
        func frame(_ bytes:[UInt8])->GrayFrame {
            let flags=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            let cg=CGImage(width:width,height:width,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:.init(rawValue:flags),
                provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            return GrayFrame(image:cg)!
        }
        func paint(_ bytes:inout [UInt8],_ center:ImagePoint,_ color:Occupancy,_ radius:Double=0.46) {
            let point=calibration.point(col:center.x,row:center.y),cx=point.x*Double(width-1),cy=point.y*Double(width-1),r=radius*pitch
            for y in max(0,Int(cy-r-1))...min(width-1,Int(cy+r+1)) {for x in max(0,Int(cx-r-1))...min(width-1,Int(cx+r+1)) {
                if hypot(Double(x)-cx,Double(y)-cy)<=r {
                    for c in 0..<3 {bytes[(y*width+x)*4+c]=color == .black ? 15 : 235}
                }
            }}
        }
        let reference=frame(base),target=IntersectionReading(row:4,col:4,occupancy:.empty,confidence:1,delta:0)
        let zero=BoardChroma(red:0,green:0)
        var checked=0,recovered=0,failures=0
        func check(_ value:Bool,_ message:String) {checked += 1;if !value {print("FAIL: " + message);failures += 1}}
        func recover(_ bytes:[UInt8],_ neighbors:[StoneFootprint],_ readings:[IntersectionReading])->(Occupancy,StoneFootprint)? {
            StoneGeometry.coveredStone(target,frame:frame(bytes),reference:reference,calibration:calibration,
                referenceCalibration:calibration,correction:0,colorShift:zero,neighbors:neighbors,neighborReadings:readings)
        }
        for color in [Occupancy.black,.white] {
            for neighborColor in [Occupancy.black,.white] {
                for distance in [0.68,0.74,0.80] {
                    for count in [1,2] {
                        var bytes=base,neighbors=[StoneFootprint](),readings=[IntersectionReading]()
                        paint(&bytes,.init(x:4,y:4),color)
                        for i in 0..<count {
                            let sign=i==0 ? 1.0 : -1.0
                            let center=ImagePoint(x:4+sign*distance,y:4)
                            let col=i==0 ? 5 : 3
                            paint(&bytes,center,neighborColor)
                            neighbors.append(.init(row:4,col:col,center:center,radiusCol:0.46,radiusRow:0.46,quality:0.97))
                            readings.append(.init(row:4,col:col,occupancy:neighborColor,confidence:0.99,delta:0))
                        }
                        let before=recover(bytes,neighbors,[]),after=recover(bytes,neighbors,readings)
                        if count==2 && distance==0.68 {
                            check(after==nil || after?.0==color,"Heavy overlap assigned the wrong color")
                        } else {
                        check(after?.0==color,"Overlap failed: \(color), neighbors \(neighborColor), d=\(distance), n=\(count), got \(String(describing:after?.0))")
                        check((after?.1.radiusCol ?? 0)>=0.40,"Recovered a fragment rather than full-size outline")
                        if before==nil {recovered += 1}
                        }
                        var absent=base
                        for n in neighbors {paint(&absent,n.center,neighborColor)}
                        check(recover(absent,neighbors,readings)==nil,"Neighbor alone invented a target")
                        paint(&absent,.init(x:4,y:4),color,0.22)
                        check(recover(absent,neighbors,readings)==nil,"Small fragment passed as a whole stone")
                    }
                }
            }
        }
        // Mixed-color neighborhoods and overlap along the other camera axis.
        for color in [Occupancy.black,.white] {
            for vertical in [false,true] {
                for distance in [0.74,0.80] {
                    var mixed=base,shapes=[StoneFootprint](),known=[IntersectionReading]()
                    paint(&mixed,.init(x:4,y:4),color)
                    for (sign,neighborColor) in [(1.0,Occupancy.black),(-1.0,Occupancy.white)] {
                        let center=ImagePoint(x:4+(vertical ? 0 : sign*distance),y:4+(vertical ? sign*distance : 0))
                        let row=4+(vertical ? Int(sign) : 0),col=4+(vertical ? 0 : Int(sign))
                        paint(&mixed,center,neighborColor)
                        shapes.append(.init(row:row,col:col,center:center,radiusCol:0.46,radiusRow:0.46,quality:0.97))
                        known.append(.init(row:row,col:col,occupancy:neighborColor,confidence:0.99,delta:0))
                    }
                    check(recover(mixed,shapes,known)?.0==color,"Mixed-color overlap failed, vertical=\(vertical), d=\(distance)")
                }
            }
        }
        // Opposite-color masks cannot hide pixels unless they match that color.
        var bytes=base
        paint(&bytes,.init(x:4,y:4),.white)
        paint(&bytes,.init(x:4.68,y:4),.black)
        let neighbor=StoneFootprint(row:4,col:5,center:.init(x:4.68,y:4),radiusCol:0.46,radiusRow:0.46,quality:0.97)
        check(recover(bytes,[neighbor],[.init(row:4,col:5,occupancy:.white,confidence:1,delta:0)])==nil,"Wrong-color mask excused contradictory pixels")
        check(recover(bytes,[neighbor],[.init(row:4,col:5,occupancy:.black,confidence:0.5,delta:0)])==nil,"Weak neighbor enabled occlusion recovery")
        check(recover(bytes,[neighbor],[.init(row:4,col:5,occupancy:.uncertain,confidence:1,delta:0)])==nil,"Unknown neighbor enabled occlusion recovery")
        // Severe occlusion from four sides must stay unresolved.
        var hidden=base,neighbors=[StoneFootprint](),readings=[IntersectionReading]()
        paint(&hidden,.init(x:4,y:4),.white)
        for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
            let center=ImagePoint(x:4+Double(dx)*0.60,y:4+Double(dy)*0.60)
            paint(&hidden,center,.black)
            neighbors.append(.init(row:4+dy,col:4+dx,center:center,radiusCol:0.46,radiusRow:0.46,quality:0.97))
            readings.append(.init(row:4+dy,col:4+dx,occupancy:.black,confidence:1,delta:0))
        }
        check(recover(hidden,neighbors,readings)==nil,"Severely hidden target must stay unresolved")
        check(recovered>0,"Test did not exercise new recovery")
        if failures>0 {exit(1)}
        print("PASS: \(checked) overlap checks; \(recovered) previously rejected outlines recovered. Both colors, one/two neighbors, absent targets, fragments, unreliable/wrong-color masks and severe occlusion.")
    }
}
