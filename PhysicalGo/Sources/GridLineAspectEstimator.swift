import Foundation

/// Printed rails supply an independent metric when an uncalibrated camera's
/// perspective fits both possible board aspects. Integrating darkness across a
/// rail preserves ink width despite defocus; peak/threshold widths do not.
/// This assumes comparable physical ink widths in both printed directions.
/// Occupied, faint, broad, displaced, or spatially inconsistent rails are rejected.
enum GridLineAspectEstimator {
    struct Estimate {
        let longAxisRows: Bool
        let medianRatio: Double
        let sampleCount: Int
    }
    private static func median(_ values:[Double])->Double {
        let s=values.sorted();return s[s.count/2]
    }
    static func estimate(frame:GrayFrame,calibration:BoardCalibration)->Estimate? {
        let n=calibration.size
        guard [9,13,19].contains(n),frame.width>=400,frame.height>=400 else {return nil}
        func sample(_ col:Double,_ row:Double)->Double? {
            let p=calibration.point(col:col,row:row)
            let x=p.x*Double(frame.width-1),y=p.y*Double(frame.height-1)
            guard x.isFinite,y.isFinite,x>=0,y>=0,x<Double(frame.width-1),y<Double(frame.height-1) else {return nil}
            let ix=Int(x),iy=Int(y),dx=x-Double(ix),dy=y-Double(iy)
            let a=Double(frame.pixels[iy*frame.width+ix]),b=Double(frame.pixels[iy*frame.width+ix+1])
            let c=Double(frame.pixels[(iy+1)*frame.width+ix]),d=Double(frame.pixels[(iy+1)*frame.width+ix+1])
            return ((a*(1-dx)+b*dx)*(1-dy)+(c*(1-dx)+d*dx)*dy)/255
        }
        func inkWidth(col:Int,row:Int,vertical:Bool)->Double? {
            var profile=[Double]();profile.reserveCapacity(111)
            for i in 0...110 {
                let across = -0.22+Double(i)*0.004
                var sum=0.0
                for j in 0...8 {
                    let along=0.3+Double(j)*0.05
                    guard let value=sample(Double(col)+(vertical ? across:along),Double(row)+(vertical ? along:across)) else {return nil}
                    sum += value
                }
                profile.append(sum/9)
            }
            let left=median(Array(profile.prefix(15))),right=median(Array(profile.suffix(15)))
            let wood=(left+right)/2
            guard wood>0.2,abs(left-right)<0.08 else {return nil}
            let ink=profile.map{max(0,wood-$0)}
            guard let peak=ink.max(),peak/wood>0.2,let center=ink.firstIndex(of:peak),abs(-0.22+Double(center)*0.004)<0.09 else {return nil}
            let area=(ink.reduce(0,+)-(ink.first!+ink.last!)/2)*0.004/wood
            guard (0.006...0.05).contains(area) else {return nil}
            return area
        }
        var values=[Double](),quadrants=[[Double]](repeating:[],count:4)
        for row in 1..<n-1 {for col in 1..<n-1 {
            guard let x=inkWidth(col:col,row:row,vertical:true),let y=inkWidth(col:col,row:row,vertical:false),
                  (0.65...1.5).contains(x/y) else {continue}
            let value=log(x/y)
            values.append(value)
            quadrants[(Double(row)<Double(n)/2 ? 0:2)+(Double(col)<Double(n)/2 ? 0:1)].append(value)
        }}
        guard values.count>=max(20,(n-2)*(n-2)/3),quadrants.allSatisfy({$0.count>=4}) else {return nil}
        let middle=median(values),expected=log(BoardRectifiedGeometry.longToShort)
        guard abs(middle)>0.035,abs(abs(middle)-expected)<0.055,
              Double(values.filter{$0*middle>0}.count)/Double(values.count)>=0.64 else {return nil}
        let zones=quadrants.map{median($0)}
        guard zones.filter({$0*middle>0}).count>=3,
              !zones.contains(where:{$0*middle<0 && abs($0)>0.035}) else {return nil}
        return Estimate(longAxisRows:middle>0,medianRatio:exp(middle),sampleCount:values.count)
    }
}
