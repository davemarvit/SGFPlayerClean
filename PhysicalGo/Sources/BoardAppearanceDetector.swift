import Foundation

/// Single-frame classification. Exposed wood between intersections estimates the
/// local board appearance; printed lines provide positive evidence of emptiness.
/// No occupied image is synthesized or installed as an empty-board baseline.
enum BoardAppearanceDetector {
    private struct Wood { let level:Double; let color:BoardChroma? }
    private struct Neighbor { let x:Double; let y:Double; let wood:Wood }
    private struct Candidate { let state:Occupancy; let confidence:Double; let delta:Double }
    private static func median(_ values:[Double])->Double {
        let sorted=values.sorted(); return sorted.isEmpty ? 0 : sorted[sorted.count/2]
    }
    /// Independent current-image evidence for learning a known-empty point.
    /// Neighboring wood supplies a local illumination/color plane. Both printed
    /// axes must remain visible; a saved label alone supplies no pixel evidence.
    static func emptyConfidence(frame:GrayFrame,calibration:BoardCalibration,point:Int,
                                threshold:Double,occupied:Set<Int>)->Double? {
        let n=calibration.size,r=point/n,c=point%n
        guard (0..<n*n).contains(point),!occupied.contains(point) else {return nil}
        var neighbors=[Neighbor](),wider=[Wood]()
        for y in max(0,r-3)..<min(n-1,r+3) {for x in max(0,c-3)..<min(n-1,c+3) {
            // Confirmed/detected stones can shade the four adjacent cell centers.
            guard ![y*n+x,y*n+x+1,(y+1)*n+x,(y+1)*n+x+1].contains(where:occupied.contains) else {continue}
            let p=calibration.point(col:Double(x)+0.5,row:Double(y)+0.5)
            guard let level=frame.patchMean(p),let color=frame.patchColor(p) else {continue}
            let wood=Wood(level:level,color:color);wider.append(wood)
            if y>=r-2,y<r+2,x>=c-2,x<c+2 {
                neighbors.append(.init(x:Double(x)+0.5-Double(c),y:Double(y)+0.5-Double(r),wood:wood))
            }
        }}
        guard let wood=localWood(neighbors),wood.color != nil,!wider.isEmpty else {return nil}
        let candidate=classify(frame:frame,calibration:calibration,col:Double(c),row:Double(r),
            wood:wood,blackWoodLevel:min(wood.level,median(wider.map(\.level))),threshold:threshold)
        let cross=gridEvidence(frame:frame,calibration:calibration,col:Double(c),row:Double(r))
        guard candidate.state == .empty,candidate.confidence>=0.75,cross.crossVisible else {return nil}
        return candidate.confidence
    }
    static func detect(frame:GrayFrame,calibration:BoardCalibration,threshold:Double, changedLighting:Bool = false)->BoardObservation {
        let n=calibration.size
        var gaps=[Wood?](repeating:nil,count:(n-1)*(n-1))
        for r in 0..<(n-1) { for c in 0..<(n-1) {
            let p=calibration.point(col:Double(c)+0.5,row:Double(r)+0.5)
            if let value=frame.patchMean(p) { gaps[r*(n-1)+c]=Wood(level:value,color:frame.patchColor(p)) }
        } }
        func classifyPoints(_ gaps:[Wood?],prior:[IntersectionReading]?=nil)->[IntersectionReading] {
        var readings=[IntersectionReading]()
        for r in 0..<n { for c in 0..<n {
            if let prior,prior[r*n+c].occupancy != .uncertain { readings.append(prior[r*n+c]); continue }
            var neighbors=[Neighbor]()
            for y in max(0,r-2)..<min(n-1,r+2) { for x in max(0,c-2)..<min(n-1,c+2) {
                if let wood=gaps[y*(n-1)+x] { neighbors.append(Neighbor(x:Double(x)+0.5-Double(c),y:Double(y)+0.5-Double(r),wood:wood)) }
            } }
            let wood=localWood(neighbors)
            var wider=[Wood]()
            for y in max(0,r-3)..<min(n-1,r+3) { for x in max(0,c-3)..<min(n-1,c+3) {
                if let value=gaps[y*(n-1)+x] { wider.append(value) }
            } }
            let broadLevel=median(wider.map(\.level))
            let colors=wider.filter{abs($0.level-broadLevel)<0.06}.compactMap(\.color)
            let broadColor:BoardChroma? = colors.count>=4 ? BoardChroma(red:median(colors.map(\.red)),green:median(colors.map(\.green))) : nil
            let broad:Wood? = wider.count>=4 && broadLevel>0.15 && broadLevel<0.96 ? Wood(level:broadLevel,color:broadColor) : nil
            // Share the conservative darkness baseline across every offset and
            // both wood models; trying another model must not bypass this check.
            let blackWoodLevel=[wood,broad].compactMap { $0?.level }.min() ?? 0
            var candidate=Candidate(state:.uncertain,confidence:0,delta:0)
            if let wood { candidate=classify(frame:frame,calibration:calibration,col:Double(c),row:Double(r),wood:wood,blackWoodLevel:blackWoodLevel,threshold:threshold) }
            if candidate.state == .uncertain {
                for local in [wood,broad].compactMap({$0}) {
                    for dy in [-0.24,0,0.24] { for dx in [-0.24,0,0.24] {
                        let other=classify(frame:frame,calibration:calibration,col:Double(c)+dx,row:Double(r)+dy,wood:local,blackWoodLevel:blackWoodLevel,threshold:threshold)
                        if other.state.stone != nil && other.confidence>candidate.confidence { candidate=other }
                    } }
                }
            }
            readings.append(.init(row:r,col:c,occupancy:candidate.state,confidence:candidate.confidence,delta:candidate.delta))
        } }
        return readings
        }
        let initial=classifyPoints(gaps)
        // Confident stones can cover cell-center samples or shade the adjacent
        // wood. Exclude those samples when revisiting uncertain intersections.
        // One refinement only: newly promoted candidates never feed this mask.
        var clean=gaps
        for reading in initial where reading.occupancy.stone != nil {
            for r in [reading.row-1,reading.row] { for c in [reading.col-1,reading.col] {
                if (0..<(n-1)).contains(r) && (0..<(n-1)).contains(c) { clean[r*(n-1)+c]=nil }
            } }
        }
        var readings=initial.contains{$0.occupancy.stone != nil} ? classifyPoints(clean,prior:initial) : initial
        if changedLighting {
            for (index,reading) in readings.enumerated() where reading.occupancy != .empty {
                let cross=gridEvidence(frame:frame,calibration:calibration,col:Double(reading.col),row:Double(reading.row),relativeContrast:true)
                guard cross.horizontal>=0.75, cross.vertical>=0.75 else {continue}
                // A shell vein can coincide with a rail. Require both printed
                // axes and a wood-colored patch in the interior of the cross.
                var nearby=[BoardChroma]()
                for y in max(0,reading.row-1)..<min(n-1,reading.row+1) {
                    for x in max(0,reading.col-1)..<min(n-1,reading.col+1) {
                        if let color=gaps[y*(n-1)+x]?.color {nearby.append(color)}
                    }
                }
                let c=Double(reading.col), r=Double(reading.row)
                var matches=0
                for dx in [-0.18,0.18] { for dy in [-0.18,0.18] {
                    if let color=frame.patchColor(calibration.point(col:c+dx,row:r+dy)),
                       nearby.contains(where:{($0-color).magnitude<0.055}) { matches+=1 }
                } }
                let state:Occupancy = matches>=3 ? .empty : .uncertain
                readings[index] = .init(row:reading.row,col:reading.col,occupancy:state,
                    confidence:state == .empty ? min(cross.horizontal,cross.vertical) : 0,delta:reading.delta)
            }
        }
        return BoardObservation(readings:readings,size:n,notice:nil)
    }
    /// Fit a local brightness plane so edge lighting gradients are extrapolated
    /// to the intersection, instead of borrowing brighter wood farther inside.
    private static func localWood(_ neighbors:[Neighbor])->Wood? {
        func fit(_ points:[Neighbor],value:(Wood)->Double?)->[Double]? {
            var matrix=Array(repeating:Array(repeating:0.0,count:4),count:3)
            var used=0
            for point in points {
                guard let z=value(point.wood) else { continue }
                let a=[1.0,point.x,point.y],w=1/pow(0.5+point.x*point.x+point.y*point.y,2)
                for r in 0..<3 { for c in 0..<3 { matrix[r][c] += w*a[r]*a[c] }; matrix[r][3] += w*a[r]*z }
                used += 1
            }
            guard used>=4 else { return nil }
            for col in 0..<3 {
                let pivot=(col..<3).max { abs(matrix[$0][col])<abs(matrix[$1][col]) }!
                guard abs(matrix[pivot][col])>1e-8 else { return nil }
                matrix.swapAt(pivot,col)
                let scale=matrix[col][col]
                for j in col...3 { matrix[col][j] /= scale }
                for row in 0..<3 where row != col {
                    let scale=matrix[row][col]
                    for j in col...3 { matrix[row][j] -= scale*matrix[col][j] }
                }
            }
            return matrix.map{$0[3]}
        }
        guard let first=fit(neighbors,value:{$0.level}) else { return nil }
        let residuals=neighbors.map { abs($0.wood.level-first[0]-first[1]*$0.x-first[2]*$0.y) }
        let cutoff=max(0.025,3*median(residuals))
        let clean=zip(neighbors,residuals).filter{$0.1<cutoff}.map{$0.0}
        guard let plane=fit(clean,value:{$0.level}),plane[0]>0.15,plane[0]<0.96,
              abs(plane[1])<0.12,abs(plane[2])<0.12,median(residuals)<0.04 else { return nil }
        var color:BoardChroma?
        if let red=fit(clean,value:{$0.color?.red}),let green=fit(clean,value:{$0.color?.green}) {
            color=BoardChroma(red:red[0],green:green[0])
        }
        return Wood(level:plane[0],color:color)
    }
    private static func classify(frame:GrayFrame,calibration:BoardCalibration,col:Double,row:Double,wood:Wood,blackWoodLevel:Double,threshold:Double)->Candidate {
        var values=[Double](),black=0,outerCount=0,white=0,similar=0
        for dy in [-0.26,-0.18,-0.10,0.10,0.18,0.26] { for dx in [-0.26,-0.18,-0.10,0.10,0.18,0.26] where dx*dx+dy*dy<0.13 {
            let p=calibration.point(col:col+dx,row:row+dy)
            guard let level=frame.patchMean(p) else { continue }
            let delta=level-wood.level
            values.append(delta)
            // Keep black evidence away from the printed cross. Extra inner
            // samples help resolve white shell grain, but ink itself is dark.
            if abs(dx)>=0.18 && abs(dy)>=0.18 {
                outerCount += 1
                // A local plane can extrapolate too bright beside a cluster of
                // stones. Require darkness relative to the broader wood estimate
                // as well, so an offset search cannot promote their shadows.
                if level-blackWoodLevel < -max(0.10,threshold) { black += 1 }
            }
            var pale=false
            if let base=wood.color,let current=frame.patchColor(p) {
                pale=base.magnitude-current.magnitude>0.035 && current.magnitude<base.magnitude*0.65 && delta > -0.01
            }
            if delta>max(0.045,min(threshold,(1-wood.level)*0.22)) || pale { white += 1 }
            let colorClose:Bool
            if let base=wood.color,let current=frame.patchColor(p) { colorClose=(base-current).magnitude<0.045 }
            else { colorClose=true }
            if abs(delta)<max(0.06,threshold*0.6) && colorClose { similar += 1 }
        } }
        guard values.count>=24 && outerCount>=9 else { return Candidate(state:.uncertain,confidence:0,delta:0) }
        let count=Double(values.count),dark=Double(black)/Double(outerCount),light=Double(white)/count
        let delta=median(values)
        let grid=gridEvidence(frame:frame,calibration:calibration,col:col.rounded(),row:row.rounded())
        let ink=grid.fraction
        if dark>=0.85 && ink<0.65 { return Candidate(state:.black,confidence:dark,delta:delta) }
        // Parallel shell grain can resemble one printed rail. A surviving grid
        // cross needs support in BOTH directions; color/patch votes still apply.
        if light>=0.85 && !grid.crossVisible && boundedWhite(frame:frame,calibration:calibration,col:col.rounded(),row:row.rounded()) {
            return Candidate(state:.white,confidence:light,delta:delta)
        }
        // The empty-board hypothesis must be supported by wood AND a visible cross.
        if Double(similar)/count>=0.75 && ink>=0.65 {
            return Candidate(state:.empty,confidence:min(Double(similar)/count,ink),delta:delta)
        }
        return Candidate(state:.uncertain,confidence:0,delta:delta)
    }
    /// A pale patch needs a surrounding boundary. A smooth lighting gradient
    /// can be brighter than a wood estimate without being a physical white stone.
    /// Sample between the printed axes so grid ink alone cannot supply the rim.
    static func boundedWhite(frame:GrayFrame,calibration:BoardCalibration,col:Double,row:Double)->Bool {
        var tested=0,supported=0
        for sector in 0..<12 {
            let angle=(Double(sector)+0.5)*Double.pi/6
            func sample(_ radius:Double)->Double? {
                let c=col+cos(angle)*radius,r=row+sin(angle)*radius
                guard c>=0,r>=0,c<=Double(calibration.size-1),r<=Double(calibration.size-1),
                      let value=frame.patchMean(calibration.point(col:c,row:r)) else {return nil}
                return value
            }
            let radial=[0.2,0.3,0.4,0.5,0.6,0.7,0.8].compactMap(sample)
            guard radial.count>=5 else {continue}
            tested+=1
            let levels=radial
            let drop=zip(levels,levels.dropFirst()).map(-).max() ?? 0
            // A rim changes abruptly over a tenth of a grid spacing. The
            // relative threshold also works when the whole scene is dimmed.
            if drop>max(0.025,min(0.065,median(Array(levels.prefix(3)))*0.18)) {supported+=1}
        }
        return tested>=3 && supported*2>tested
    }

    /// Positive current-image evidence: two printed rails cross a wood-colored
    /// interior. Unlike a reference contrast ratio, this survives a moved glare
    /// patch or different camera exposure. It never uses accepted game labels.
    static func exposedWoodConfidence(frame:GrayFrame,calibration:BoardCalibration,col:Int,row:Int,bodyCenter:ImagePoint?=nil)->Double? {
        let cross=gridEvidence(frame:frame,calibration:calibration,col:Double(col),row:Double(row),relativeContrast:true)
        guard cross.horizontal>=0.75,cross.vertical>=0.75 else {return nil}
        var wood=[BoardChroma](),levels=[Double]()
        for r in max(0,row-1)..<min(calibration.size-1,row+1) {
            for c in max(0,col-1)..<min(calibration.size-1,col+1) {
                let p=calibration.point(col:Double(c)+0.5,row:Double(r)+0.5)
                if let color=frame.patchColor(p),color.magnitude>=0.035 {wood.append(color)}
                if let level=frame.patchMean(p) {levels.append(level)}
            }
        }
        let center=bodyCenter ?? ImagePoint(x:Double(col),y:Double(row))
        // A displaced dark stone can expose the cross at the nominal point.
        // Check its proposed body as well; exposed rails beside it are not empty.
        // Check the inner body separately: a small opaque cover can darken both
        // rails while leaving all four outer diagonal samples on exposed wood.
        guard !levels.isEmpty else {return nil}
        let minimumBody=median(levels)*0.75
        let nominal=ImagePoint(x:Double(col),y:Double(row))
        let centers=(center.x==nominal.x && center.y==nominal.y) ? [nominal]:[nominal,center]
        for bodyCenter in centers {for radius in [0.12,0.18] {
            var body=[Double]()
            for dx in [-radius,radius] {for dy in [-radius,radius] {
                if let level=frame.patchMean(calibration.point(col:bodyCenter.x+dx,row:bodyCenter.y+dy)) {body.append(level)}
            }}
            guard body.count==4,body.filter({$0>=minimumBody}).count>=3 else {return nil}
        }}
        var matches=0
        for dx in [-0.18,0.18] {for dy in [-0.18,0.18] {
            if let color=frame.patchColor(calibration.point(col:Double(col)+dx,row:Double(row)+dy)),
               color.magnitude>=0.035,wood.contains(where:{($0-color).magnitude<0.045 && color.magnitude >= $0.magnitude*0.65}) {matches+=1}
        }}
        return matches>=3 ? min(cross.horizontal,cross.vertical):nil
    }
    struct GridEvidence {
        let horizontal:Double
        let vertical:Double
        let fraction:Double
        var crossVisible:Bool { horizontal>=0.5 && vertical>=0.5 }
    }
    static func gridEvidence(frame:GrayFrame,calibration:BoardCalibration,col:Double,row:Double,relativeContrast:Bool = false)->GridEvidence {
        var visible=[0,0],total=[0,0]
        let arms=relativeContrast ? [-0.28,-0.18,0.18,0.28] : [-0.30,-0.20,0.20,0.30]
        let offsets=relativeContrast ? [-0.12,-0.08,-0.04,0,0.04,0.08,0.12] : [-0.18,-0.12,-0.06,0,0.06,0.12,0.18]
        let flank=relativeContrast ? 0.14 : 0.16
        for vertical in [false,true] { for along in arms {
            let c=col+(vertical ? 0 : along),r=row+(vertical ? along : 0)
            guard c>=0,r>=0,c<=Double(calibration.size-1),r<=Double(calibration.size-1) else { continue }
            var lineVisible=false
            for offset in offsets {
                let x=c+(vertical ? offset : 0),y=r+(vertical ? 0 : offset)
                let p=calibration.point(col:x,row:y)
                let a=calibration.point(col:x+(vertical ? -flank : 0),row:y+(vertical ? 0 : -flank))
                let b=calibration.point(col:x+(vertical ? flank : 0),row:y+(vertical ? 0 : flank))
                if let center=frame.patchMean(p),let before=frame.patchMean(a),let after=frame.patchMean(b) {
                    let wood=min(before,after)
                    let threshold=relativeContrast ? max(0.012,wood*0.07) : 0.045
                    if wood-center>threshold {lineVisible=true;break}
                }
            }
            let axis=vertical ? 1 : 0
            total[axis] += 1; if lineVisible { visible[axis] += 1 }
        } }
        func fraction(_ axis:Int)->Double { total[axis]>0 ? Double(visible[axis])/Double(total[axis]) : 0 }
        let count=total.reduce(0,+)
        return GridEvidence(horizontal:fraction(0),vertical:fraction(1),fraction:count>0 ? Double(visible.reduce(0,+))/Double(count) : 0)
    }
}
