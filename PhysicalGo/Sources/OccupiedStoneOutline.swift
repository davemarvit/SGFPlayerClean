import Foundation

/// A sharp circular boundary may be darker OR lighter than the surrounding
/// wood. Used only with a changed, explicitly known-empty patch and learned
/// White appearance; it is not a stand-alone occupancy classifier.
enum OccupiedStoneOutline {
    static func fit(frame:GrayFrame,calibration:BoardCalibration,point:Int,minimumContrast:Double)->StoneFootprint? {
        let col=Double(point%calibration.size),row=Double(point/calibration.size)
        var best:StoneFootprint?
        for dy in [-0.16,-0.08,0,0.08,0.16] {for dx in [-0.16,-0.08,0,0.08,0.16] {
            for radius in [0.38,0.42,0.46,0.50,0.54,0.58] {
                var sectors=0,quadrants=[Int](repeating:0,count:4)
                for sector in 0..<12 {
                    let a=(Double(sector)+0.5)*Double.pi/6
                    func level(_ r:Double)->Double? {
                        frame.patchMean(calibration.point(col:col+dx+cos(a)*r,row:row+dy+sin(a)*r*1.06))
                    }
                    guard let inner=level(radius-0.06),let edge=level(radius),let outer=level(radius+0.06) else {continue}
                    let contrast=max(abs(inner-outer),min(inner-edge,outer-edge))
                    if contrast>=minimumContrast {sectors+=1;quadrants[sector/3]+=1}
                }
                guard sectors>=10,quadrants.allSatisfy({$0>=2}) else {continue}
                let quality=Double(sectors)/12
                if best==nil || quality>best!.quality {
                    best = .init(row:Int(row),col:Int(col),center:.init(x:col+dx,y:row+dy),radiusCol:radius,radiusRow:radius*1.06,quality:quality)
                }
            }
        }}
        return best
    }
}
