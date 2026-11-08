import Foundation

/// Independent silhouette measurements in grid coordinates. Unlike the occupancy
/// footprint fitter, this does not restrict ellipses to either hypothesized aspect.
enum StoneAspectEstimator {
    struct Measurement {
        let row:Int, col:Int
        let color:Occupancy
        let ratio:Double // Horizontal / vertical radius, before display stretching.
    }
    struct Estimate {
        let longAxisRows:Bool
        let measurements:[Measurement]
        let medianRatio:Double
    }
    private static func median(_ values:[Double])->Double {
        let sorted=values.sorted(); return sorted.isEmpty ? 0 : sorted[sorted.count/2]
    }
    static func estimate(frame:GrayFrame,calibration:BoardCalibration,readings:[IntersectionReading])->Estimate? {
        consensus(measurements(frame:frame,calibration:calibration,readings:readings))
    }
    static func measurements(frame:GrayFrame,calibration:BoardCalibration,readings:[IntersectionReading])->[Measurement] {
        readings.filter{$0.occupancy.stone != nil && $0.confidence>=0.75}
            .prefix(40).compactMap { measure($0,frame:frame,calibration:calibration) }
    }
    static func consensus(_ measurements:[Measurement])->Estimate? {
        guard measurements.count>=3 else { return nil }
        let ratios=measurements.map{log($0.ratio)},middle=median(ratios)
        let expected=log(BoardRectifiedGeometry.longToShort)
        // Round, unexplained elongated, or inconsistent shapes cannot determine orientation.
        guard abs(middle)>0.035, abs(abs(middle)-expected)<0.045,
              median(ratios.map{abs($0-middle)})<0.035 else { return nil }
        let supporting=measurements.filter{log($0.ratio)*middle>0 && abs(log($0.ratio)-middle)<0.065}
        guard supporting.count>=3,Double(supporting.count)/Double(measurements.count)>=0.75,
              Set(supporting.map(\.row)).count>=2,Set(supporting.map(\.col)).count>=2 else { return nil }
        // Opposing conclusions from black and white stones suggest material/shadow bias.
        for color in [Occupancy.black,.white] {
            let group=measurements.filter{$0.color==color}.map{log($0.ratio)}
            if group.count>=2 && median(group)*middle<0 { return nil }
        }
        return Estimate(longAxisRows:middle>0,measurements:measurements,medianRatio:exp(middle))
    }
    private static func measure(_ reading:IntersectionReading,frame:GrayFrame,calibration:BoardCalibration)->Measurement? {
        let col=Double(reading.col),row=Double(reading.row),n=Double(calibration.size-1)
        guard row>=1,col>=1,row<n,col<n else { return nil }
        var levels=[Double](),colors=[BoardChroma]()
        for dy in [-1.5,-0.5,0.5,1.5] { for dx in [-1.5,-0.5,0.5,1.5] {
            guard col+dx>=0,col+dx<=n,row+dy>=0,row+dy<=n else { continue }
            let p=calibration.point(col:col+dx,row:row+dy)
            if let value=frame.patchMean(p) { levels.append(value); if let color=frame.patchColor(p) { colors.append(color) } }
        } }
        guard levels.count>=9 else { return nil }
        let wood=median(levels)
        guard wood>0.25,wood<0.94 else { return nil }
        let woodColor=colors.count>=8 ? BoardChroma(red:median(colors.map(\.red)),green:median(colors.map(\.green))) : nil
        let side=101,step=0.02
        var mask=[Bool](repeating:false,count:side*side)
        for y in 0..<side { for x in 0..<side {
            let p=calibration.point(col:col+Double(x-50)*step,row:row+Double(y-50)*step)
            guard let value=frame.patchMean(p) else { continue }
            if reading.occupancy == .black {
                mask[y*side+x]=value<wood*0.50 && value<wood-0.20
            } else {
                let pale:Bool
                if let a=frame.patchColor(p),let b=woodColor {
                    pale=b.magnitude-a.magnitude>0.025 && a.magnitude<b.magnitude*0.7 && value>wood-0.08
                } else { pale=false }
                mask[y*side+x]=pale || value>wood+0.10
            }
        } }
        // Opening removes thin printed rails and narrow tendrils of shadow.
        var eroded=mask,opened=[Bool](repeating:false,count:mask.count)
        for y in 1..<side-1 { for x in 1..<side-1 {
            eroded[y*side+x]=(-1...1).allSatisfy { dy in (-1...1).allSatisfy { dx in mask[(y+dy)*side+x+dx] } }
        } }
        for y in 1..<side-1 { for x in 1..<side-1 {
            opened[y*side+x]=(-1...1).contains { dy in (-1...1).contains { dx in eroded[(y+dy)*side+x+dx] } }
        } }
        var visited=[Bool](repeating:false,count:mask.count)
        var best:[Int]?,bestDistance=Double.infinity
        for seed in opened.indices where opened[seed] && !visited[seed] {
            var component=[seed],cursor=0;visited[seed]=true
            while cursor<component.count {
                let i=component[cursor];cursor += 1
                let x=i%side,y=i/side
                for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx>=0 && ny>=0 && nx<side && ny<side {
                    let j=ny*side+nx
                    if opened[j] && !visited[j] { visited[j]=true;component.append(j) }
                }
            }
            let cx=Double(component.reduce(0){$0+$1%side})/Double(component.count)
            let cy=Double(component.reduce(0){$0+$1/side})/Double(component.count)
            let distance=hypot(cx-50,cy-50)*step
            if distance<0.55 && component.count>500 && distance<bestDistance { best=component;bestDistance=distance }
        }
        guard let component=best else { return nil }
        let xs=component.map{$0%side},ys=component.map{$0/side}
        let minX=xs.min()!,maxX=xs.max()!,minY=ys.min()!,maxY=ys.max()!
        guard minX>1,minY>1,maxX<side-2,maxY<side-2,
              (0.55...1.2).contains(Double(maxX-minX)*step),(0.55...1.2).contains(Double(maxY-minY)*step) else { return nil }
        // Fill enclosed highlights/grain so surface texture does not distort the moments.
        var body=[Bool](repeating:false,count:mask.count)
        for i in component { body[i]=true }
        var outside=[Bool](repeating:false,count:mask.count),queue=[0],cursor=0;outside[0]=true
        while cursor<queue.count {
            let i=queue[cursor];cursor += 1;let x=i%side,y=i/side
            for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx>=0 && ny>=0 && nx<side && ny<side {
                let j=ny*side+nx
                if !body[j] && !outside[j] { outside[j]=true;queue.append(j) }
            }
        }
        let filled=body.indices.filter{body[$0] || !outside[$0]}
        let area=Double(filled.count)*step*step
        guard (0.28...1.0).contains(area) else { return nil }
        let cx=Double(filled.reduce(0){$0+$1%side})/Double(filled.count),cy=Double(filled.reduce(0){$0+$1/side})/Double(filled.count)
        var xx=0.0,yy=0.0,xy=0.0
        for i in filled { let x=Double(i%side)-cx,y=Double(i/side)-cy;xx += x*x;yy += y*y;xy += x*y }
        guard xx>0,yy>0,abs(xy)/sqrt(xx*yy)<0.12 else { return nil }
        let rx=2*sqrt(xx/Double(filled.count))*step,ry=2*sqrt(yy/Double(filled.count))*step
        let ratio=rx/ry
        // A compact elliptical body must explain the measured area and perimeter extent.
        guard (0.75...1.33).contains(ratio),abs(area/(Double.pi*rx*ry)-1)<0.12,
              abs(Double(maxX-minX)*step/(2*rx)-1)<0.12,
              abs(Double(maxY-minY)*step/(2*ry)-1)<0.12 else { return nil }
        return Measurement(row:reading.row,col:reading.col,color:reading.occupancy,ratio:ratio)
    }
}
