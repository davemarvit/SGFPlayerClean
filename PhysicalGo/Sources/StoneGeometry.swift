import Foundation

struct StoneFootprint: Codable {
    let row:Int, col:Int
    let center:ImagePoint
    let radiusCol:Double, radiusRow:Double
    let quality:Double
    func contains(_ p:ImagePoint, padding:Double = 0)->Bool {
        pow((p.x-center.x)/(radiusCol+padding),2)+pow((p.y-center.y)/(radiusRow+padding),2)<=1
    }
}

/// Reference-backed geometry refinement. Accepted stones seed outline fits;
/// only independently contradicted occupancy hypotheses can resolve uncertainty.
enum StoneGeometry {
    struct Result { let readings:[IntersectionReading]; let footprints:[StoneFootprint]; var placementFits:[StoneFootprint]=[] }
    struct ColoredNeighbor { let shape:StoneFootprint; let color:Occupancy }
    private struct Span { let y:Int, left:Int, right:Int }
    private struct Disk {
        let spans:[Span]; let count:Double
        init(rx:Double,ry:Double,step:Double) {
            var rows=[Span](),count=0
            for y in -Int(ry/step)...Int(ry/step) {
                let x=Int(rx/step*sqrt(max(0,1-pow(Double(y)*step/ry,2))))
                rows.append(Span(y:y,left:-x,right:x));count += 2*x+1
            }
            spans=rows;self.count=Double(count)
        }
    }
    private struct Shape {
        let rx:Double,ry:Double
        let disk:Disk,inner:Disk,outer:Disk
    }
    private static let step=0.04,side=65,origin=32
    private static let shapes:[Shape] = (0...14).flatMap { i in
        [0.94,1.06].map { aspect in
            let r=0.32+Double(i)*0.02
            return Shape(rx:r,ry:r*aspect,disk:Disk(rx:r,ry:r*aspect,step:step),
                         inner:Disk(rx:r+0.06,ry:(r+0.06)*aspect,step:step),
                         outer:Disk(rx:r+0.15,ry:(r+0.15)*aspect,step:step))
        }
    }
    private static func fit(_ reading:IntersectionReading,frame:GrayFrame,reference:GrayFrame,
                            calibration:BoardCalibration,referenceCalibration:BoardCalibration,
                            correction:Double,colorShift:BoardChroma,masking:[StoneFootprint]=[],minimumQuality:Double=0.78,
                            occlusion:[ColoredNeighbor]=[])->StoneFootprint? {
        // An occlusion fit keeps the expected FULL stone size. Only the minimum
        // visible body shrinks, by the union of independently observed neighbors.
        // This avoids accepting a small shadow as an unusually small stone.
        let contextual = !occlusion.isEmpty
        let radii=occlusion.map{$0.shape.radiusCol}.sorted()
        let expectedRadius=contextual ? radii[radii.count/2] : 0
        var prefix=[Double](repeating:0,count:side*(side+1))
        var maskedCount=prefix,maskedVotes=prefix
        for y in 0..<side { for x in 0..<side {
            let c=Double(reading.col)+Double(x-origin)*step,r=Double(reading.row)+Double(y-origin)*step
            let p=calibration.point(col:c,row:r),q=referenceCalibration.point(col:c,row:r)
            var vote=0.0,black=false,white=false
            if let current=frame.patchMean(p),let base=reference.patchMean(q) {
                black=current-correction<base-0.20 && current-correction<base*0.65
                if contextual || reading.occupancy != .black,let a=frame.patchColor(p),let b=reference.patchColor(q) {
                    let expected=b+colorShift
                    white=(expected.magnitude-a.magnitude>0.035 && a.magnitude<expected.magnitude*0.65 && current-correction>base-0.06)
                        || current-correction>base+0.12
                }
                if reading.occupancy == .black ? black : white {vote=1}
            }
            let offset=y*(side+1)+x
            prefix[offset+1]=prefix[offset]+vote
            if !masking.isEmpty || contextual {
                let point=ImagePoint(x:c,y:r)
                // A predicted neighbor footprint is not enough: the actual pixel
                // must also support that neighbor's color. Empty wood cannot be
                // hidden by a stale or incorrectly colored neighbor mask.
                let covered=contextual ? occlusion.contains {
                    $0.shape.contains(point,padding:0.04) && ($0.color == .black ? black : white)
                } : masking.contains{$0.contains(point,padding:0.04)}
                maskedCount[offset+1]=maskedCount[offset]+(covered ? 1 : 0)
                maskedVotes[offset+1]=maskedVotes[offset]+(covered ? vote : 0)
            }
        } }
        func sum(_ disk:Disk,_ x:Int,_ y:Int,_ values:[Double])->Double {
            var total=0.0
            for span in disk.spans {
                let offset=(y+span.y)*(side+1)
                total += values[offset+x+span.right+1]-values[offset+x+span.left]
            }
            return total
        }
        var best:StoneFootprint?,bestScore = -Double.infinity
        // A touching stone's dark rim/shadow can extend beyond the ordinary
        // outline range. Search farther only with independently observed neighbor
        // masks and the stricter body/visible-ring checks below. Keep a sentinel
        // radius beyond the accepted range so unbounded dark regions still fail.
        let maximumRadius = masking.isEmpty ? 0.54 : 0.60
        for shape in shapes where shape.rx <= maximumRadius { for dy in -11...11 { for dx in -11...11 {
            if contextual && (abs(shape.rx-expectedRadius)>0.041 || abs(dx)>5 || abs(dy)>5) {continue}
            let x=origin+dx,y=origin+dy
            var inside=sum(shape.disk,x,y,prefix)/shape.disk.count
            // Ring penalties are nonnegative. This candidate cannot beat the
            // current fit even with a perfect ring; retain the original tie order.
            // Contextual fits first need their visible-body adjustment below.
            if !contextual && inside<=bestScore {continue}
            let area=shape.outer.count-shape.inner.count
            var ringVotes=sum(shape.outer,x,y,prefix)-sum(shape.inner,x,y,prefix),visible=area
            if contextual {
                let hidden=sum(shape.disk,x,y,maskedCount)
                let body=shape.disk.count-hidden
                // At least 65% of a normal-size body and half its exterior must
                // remain visible. Multiple masks are a union, never double counted.
                // The equivalent visible radius is fullRadius * sqrt(body/fullArea).
                guard hidden>=shape.disk.count*0.02,body>=shape.disk.count*0.65 else {continue}
                inside=(sum(shape.disk,x,y,prefix)-sum(shape.disk,x,y,maskedVotes))/body
                guard inside>=0.92,inside>bestScore else {continue}
                visible -= sum(shape.outer,x,y,maskedCount)-sum(shape.inner,x,y,maskedCount)
                guard visible>=area*0.50 else {continue}
                ringVotes -= sum(shape.outer,x,y,maskedVotes)-sum(shape.inner,x,y,maskedVotes)
            } else if !masking.isEmpty {
                let center=ImagePoint(x:Double(reading.col)+Double(dx)*step,y:Double(reading.row)+Double(dy)*step)
                guard inside>=0.92,!masking.contains(where:{hypot((center.x-$0.center.x)/(shape.rx+$0.radiusCol),(center.y-$0.center.y)/(shape.ry+$0.radiusRow))<0.90}) else {continue}
                visible -= sum(shape.outer,x,y,maskedCount)-sum(shape.inner,x,y,maskedCount)
                guard visible>=area*0.50 else {continue}
                ringVotes -= sum(shape.outer,x,y,maskedVotes)-sum(shape.inner,x,y,maskedVotes)
            }
            let ring=ringVotes/visible
            let score=inside-0.7*ring
            if score>bestScore {
                bestScore=score
                best=StoneFootprint(row:reading.row,col:reading.col,
                    center:ImagePoint(x:Double(reading.col)+Double(dx)*step,y:Double(reading.row)+Double(dy)*step),
                    radiusCol:shape.rx,radiusRow:shape.ry,quality:score)
            }
        } } }
        guard let best,best.quality>=minimumQuality,best.radiusCol>0.32,best.radiusCol<maximumRadius else { return nil }
        return best
    }
    /// Called only after both reference grid rails have positively disappeared.
    /// Missing ink establishes a contradiction, not a stone color. A compact
    /// body and independently visible boundary must support exactly one color.
    static func coveredStone(_ reading:IntersectionReading,frame:GrayFrame,reference:GrayFrame,
                             calibration:BoardCalibration,referenceCalibration:BoardCalibration,
                             correction:Double,colorShift:BoardChroma?,neighbors:[StoneFootprint],
                             neighborReadings:[IntersectionReading]=[])->(Occupancy,StoneFootprint)? {
        let nearby=neighbors.filter{abs($0.row-reading.row)<=1 && abs($0.col-reading.col)<=1}
        // Use only original, strongly classified/fitted neighbors. Newly recovered
        // stones must not recursively lend support to other recoveries this frame.
        let occluders=nearby.compactMap { shape -> ColoredNeighbor? in
            guard shape.quality>=0.86,shape.radiusCol>=0.38,shape.radiusCol<=0.52,
                  shape.row != reading.row || shape.col != reading.col,
                  let stone=neighborReadings.first(where:{$0.row==shape.row && $0.col==shape.col}),
                  stone.occupancy.stone != nil,stone.confidence>=0.90 else {return nil}
            return ColoredNeighbor(shape:shape,color:stone.occupancy)
        }
        var candidates=[(Occupancy,StoneFootprint)]()
        for color in [Occupancy.black,.white] {
            let hypothesis=IntersectionReading(row:reading.row,col:reading.col,occupancy:color,confidence:0,delta:reading.delta)
            // Without a reliable wood-color adjustment, zero shift is only a
            // fitting hypothesis. It cannot label anything without the ink and
            // strong bounded-outline evidence required here.
            let ordinary=fit(hypothesis,frame:frame,reference:reference,calibration:calibration,
                referenceCalibration:referenceCalibration,correction:correction,
                colorShift:colorShift ?? BoardChroma(red:0,green:0),minimumQuality:0.86)
            let separate=ordinary.flatMap { shape -> StoneFootprint? in
                nearby.contains(where:{hypot((shape.center.x-$0.center.x)/(shape.radiusCol+$0.radiusCol),
                    (shape.center.y-$0.center.y)/(shape.radiusRow+$0.radiusRow))<0.90}) ? nil : shape
            }
            // Color-conditioned masks require a measured wood-color correction.
            // Without it, retain the stricter original independent-outline test.
            let contextual:StoneFootprint?
            if separate == nil,let colorShift,!occluders.isEmpty {
                contextual=fit(hypothesis,frame:frame,reference:reference,calibration:calibration,
                    referenceCalibration:referenceCalibration,correction:correction,colorShift:colorShift,
                    minimumQuality:0.90,occlusion:occluders)
            } else {contextual=nil}
            guard let shape=separate ?? contextual,
                shape.contains(.init(x:Double(reading.col),y:Double(reading.row))),
                // Centers are sampled in 0.04-cell steps. Subtraction at a
                // distant column can represent the allowed 0.28 step as
                // 0.280000000000001; acceptance must not depend on board location.
                max(abs(shape.center.x-Double(reading.col)),abs(shape.center.y-Double(reading.row)))<=0.28+1e-9 else {continue}
            candidates.append((color,shape))
        }
        return candidates.count==1 ? candidates[0]:nil
    }
    private struct WoodEvidence { let point:ImagePoint; let matches:Bool }
    private struct InkEvidence { let point:ImagePoint; let axis:Int; let survives:Bool }

    static func refine(frame:GrayFrame,reference:GrayFrame,calibration:BoardCalibration,
                       referenceCalibration:BoardCalibration,readings:[IntersectionReading],
                       blocked:Set<Int>,correction:Double,colorShift:BoardChroma?,samplingCenters:[ImagePoint]?=nil)->Result {
        guard let colorShift else { return Result(readings:readings,footprints:[]) }
        var footprints=readings.filter{$0.occupancy.stone != nil}.compactMap {
            fit($0,frame:frame,reference:reference,calibration:calibration,
                referenceCalibration:referenceCalibration,correction:correction,colorShift:colorShift)
        }
        // Conflicting outlines are unsuitable as evidence about surrounding wood.
        let fitted=footprints
        footprints=fitted.enumerated().filter { i,a in
            !fitted.enumerated().contains { j,b in
                i != j && hypot((a.center.x-b.center.x)/(a.radiusCol+b.radiusCol),
                                (a.center.y-b.center.y)/(a.radiusRow+b.radiusRow))<0.85
            }
        }.map(\.element)
        var result=readings
        if let centers=samplingCenters,centers.count==readings.count {
            let independentlyFitted=Set(footprints.map{$0.row*calibration.size+$0.col})
            for (index,reading) in readings.enumerated() where reading.occupancy == .black {
                let center=centers[index]
                // An offset search or partial dark patch beside a strongly
                // observed black stone can
                // collect its edge and cast shadow. It needs an independent
                // stone outline before claiming a SECOND occupied intersection.
                // Keep it uncertain: lack of an outline does not prove emptiness.
                let borrowing=readings.enumerated().contains { j,neighbor in
                    guard j != index,neighbor.occupancy == .black,
                          abs(neighbor.row-reading.row)<=1,abs(neighbor.col-reading.col)<=1 else {return false}
                    let centeredStrong=neighbor.confidence>=0.9 &&
                        hypot(centers[j].x-Double(neighbor.col),centers[j].y-Double(neighbor.row))<0.05
                    if centeredStrong && hypot(center.x-Double(reading.col),center.y-Double(reading.row))>0.05 {return true}
                    if let shape=fitted.first(where:{$0.row==neighbor.row && $0.col==neighbor.col}) {
                        return shape.contains(center,padding:0.3)
                    }
                    return centeredStrong && hypot(center.x-centers[j].x,center.y-centers[j].y)<0.75
                }
                guard borrowing else {continue}
                var secondaryClaim = !independentlyFitted.contains(index)
                if secondaryClaim,reading.confidence>=0.9,!blocked.contains(index) {
                    let nearby=footprints.filter { abs($0.row-reading.row)<=1 && abs($0.col-reading.col)<=1 }
                    // Touching black stones can spoil each other's exterior ring.
                    // Use a strongly centered neighbor only as an exterior mask.
                    // Its weaker outline cannot establish occupancy. The new stone
                    // still needs 92% body support, a disjoint interior, at least
                    // half its exterior ring visible, and the usual 0.78 outline score.
                    for neighbor in readings where neighbor.occupancy == .black && neighbor.confidence>=0.9 &&
                        (neighbor.row != reading.row || neighbor.col != reading.col) &&
                        abs(neighbor.row-reading.row)<=1 && abs(neighbor.col-reading.col)<=1 {
                        let neighborIndex=neighbor.row*calibration.size+neighbor.col
                        guard !blocked.contains(neighborIndex),
                              hypot(centers[neighborIndex].x-Double(neighbor.col),centers[neighborIndex].y-Double(neighbor.row))<0.05,
                              let proposal=fit(neighbor,frame:frame,reference:reference,calibration:calibration,
                                referenceCalibration:referenceCalibration,correction:correction,colorShift:colorShift,minimumQuality:0.65) else {continue}
                        let other=nearby.filter { !($0.row==neighbor.row && $0.col==neighbor.col) }
                        guard let separate=fit(reading,frame:frame,reference:reference,calibration:calibration,
                                referenceCalibration:referenceCalibration,correction:correction,colorShift:colorShift,masking:other+[proposal]) else {continue}
                        footprints.append(separate);secondaryClaim=false;break
                    }
                }
                if secondaryClaim {result[index]=IntersectionReading(row:reading.row,col:reading.col,occupancy:.uncertain,confidence:0,delta:reading.delta)}
            }
        }
        for (index,reading) in result.enumerated() where reading.occupancy == .uncertain && !blocked.contains(index) {
            let neighbors=footprints.filter{abs($0.row-reading.row)<=1 && abs($0.col-reading.col)<=1}
            guard !neighbors.isEmpty else { continue }
            if excludesAdditionalStone(row:reading.row,col:reading.col,neighbors:neighbors,
                frame:frame,reference:reference,calibration:calibration,referenceCalibration:referenceCalibration,
                correction:correction,colorShift:colorShift) {
                result[index]=IntersectionReading(row:reading.row,col:reading.col,occupancy:.empty,confidence:0.8,delta:reading.delta)
            }
        }
        // Placement-only refinement: same-color neighbors contaminate a stone's
        // exterior ring. White clusters can hide several neighboring outlines at
        // once. Strongly classified white neighbors may supply provisional masks;
        // those masks are not placement evidence themselves. Every reported fit
        // still needs >=92% body coverage, >=50% visible ring, nonoverlap and
        // a strong fit. These fits never resolve occupancy or infer empty points.
        var placementFits=[StoneFootprint]()
        for reading in result where reading.occupancy.stone != nil && reading.confidence>=0.9 {
            let original=footprints.first{$0.row==reading.row && $0.col==reading.col}
            if let original, original.quality>=0.86 {continue}
            var neighbors=footprints.filter {shape in
                (shape.row != reading.row || shape.col != reading.col) &&
                abs(shape.row-reading.row)<=1 && abs(shape.col-reading.col)<=1 &&
                result[shape.row*calibration.size+shape.col].occupancy == reading.occupancy && shape.quality>=0.78
            }
            if reading.occupancy == .white {
                for neighbor in result where neighbor.occupancy == .white && neighbor.confidence>=0.9 &&
                    (neighbor.row != reading.row || neighbor.col != reading.col) &&
                    abs(neighbor.row-reading.row)<=1 && abs(neighbor.col-reading.col)<=1 &&
                    !neighbors.contains(where:{$0.row==neighbor.row && $0.col==neighbor.col}) {
                    if let mask=fit(neighbor,frame:frame,reference:reference,calibration:calibration,
                        referenceCalibration:referenceCalibration,correction:correction,colorShift:colorShift,minimumQuality:0.65) {
                        neighbors.append(mask)
                    }
                }
            }
            guard !neighbors.isEmpty,let refined=fit(reading,frame:frame,reference:reference,calibration:calibration,
                referenceCalibration:referenceCalibration,correction:correction,colorShift:colorShift,masking:neighbors) else {continue}
            if neighbors.count >= (reading.occupancy == .white ? 1 : 2), refined.quality >= 0.90 {
                placementFits.append(refined)
            } else if reading.occupancy == .black, reading.confidence >= 0.95,
                      let original, refined.quality >= 0.86 {
                // A touching stone can spoil the exterior score while leaving
                // the fitted center stable. Require both fits to be well inside
                // this cell and to agree even after the neighbor is masked.
                let point = ImagePoint(x:Double(reading.col), y:Double(reading.row))
                func centered(_ fit:StoneFootprint) -> Bool {
                    max(abs(fit.center.x-point.x),abs(fit.center.y-point.y)) <= 0.20
                }
                if centered(original), centered(refined),
                   hypot(original.center.x-refined.center.x, original.center.y-refined.center.y) <= 0.08 {
                    placementFits.append(refined)
                }
            }
        }
        return Result(readings:result,footprints:footprints,placementFits:placementFits)
    }

    private static func excludesAdditionalStone(row:Int,col:Int,neighbors:[StoneFootprint],
        frame:GrayFrame,reference:GrayFrame,calibration:BoardCalibration,referenceCalibration:BoardCalibration,
        correction:Double,colorShift:BoardChroma)->Bool {
        // Use the smaller nearby stones with a size tolerance. Hypotheses cover
        // their assigned intersection; unexplained colored regions also veto an
        // empty result, including objects displaced beyond that hypothesis range.
        let rx=max(0.30,(neighbors.map(\.radiusCol).min() ?? 0.42)-0.03)
        let ry=max(0.30,(neighbors.map(\.radiusRow).min() ?? 0.42)-0.03)
        func masked(_ p:ImagePoint)->Bool { neighbors.contains{$0.contains(p,padding:0.04)} }
        var wood=[WoodEvidence](),woodLevels=[Double]()
        for y in -8...8 { for x in -8...8 {
            let p=ImagePoint(x:Double(col)+Double(x)*0.08,y:Double(row)+Double(y)*0.08)
            if let v=reference.patchMean(referenceCalibration.point(col:p.x,row:p.y)) { woodLevels.append(v) }
        } }
        guard woodLevels.count>=200 else { return false }
        woodLevels.sort();let woodLevel=woodLevels[woodLevels.count*3/4]
        var unexplained=0
        for y in -8...8 { for x in -8...8 {
            let p=ImagePoint(x:Double(col)+Double(x)*0.08,y:Double(row)+Double(y)*0.08)
            guard !masked(p) else { continue }
            let q=calibration.point(col:p.x,row:p.y),basePoint=referenceCalibration.point(col:p.x,row:p.y)
            guard let a=frame.patchMean(q),let b=reference.patchMean(basePoint),b>=woodLevel-0.08,
                  let ac=frame.patchColor(q),let bc=reference.patchColor(basePoint) else { continue }
            let change=a-b-correction,colorDifference=(ac-bc-colorShift).magnitude
            let matches=change > -0.12 && change<0.07 && colorDifference<0.025
            wood.append(WoodEvidence(point:p,matches:matches))
            if abs(p.x-Double(col))<=0.48 && abs(p.y-Double(row))<=0.48,
               change < -0.18 || (colorDifference>0.04 && change > -0.06) { unexplained += 1 }
        } }
        guard unexplained<5 else { return false }
        var ink=[InkEvidence](),unexplainedCoveredInk=0
        for axis in 0..<2 { for k in -11...11 {
            let vertical=axis==1
            let p=ImagePoint(x:Double(col)+(vertical ? 0 : Double(k)*0.06),y:Double(row)+(vertical ? Double(k)*0.06 : 0))
            guard !masked(p) else { continue }
            func contrast(_ image:GrayFrame,_ grid:BoardCalibration,_ shift:Double)->Double? {
                let x=p.x+(vertical ? shift : 0),y=p.y+(vertical ? 0 : shift)
                let a=ImagePoint(x:x+(vertical ? -0.12 : 0),y:y+(vertical ? 0 : -0.12))
                let b=ImagePoint(x:x+(vertical ? 0.12 : 0),y:y+(vertical ? 0 : 0.12))
                guard !masked(a),!masked(b),let center=image.patchMean(grid.point(col:x,row:y)),
                      let av=image.patchMean(grid.point(col:a.x,row:a.y)),let bv=image.patchMean(grid.point(col:b.x,row:b.y)) else { return nil }
                return min(av,bv)-center
            }
            let candidates=[-0.08,-0.04,0,0.04,0.08].compactMap { shift -> (Double,Double)? in
                contrast(reference,referenceCalibration,shift).map{(shift,$0)}
            }
            guard let best=candidates.max(by:{$0.1<$1.1}),best.1>0.04 else { continue }
            let current=[-0.04,0,0.04].compactMap{contrast(frame,calibration,best.0+$0)}.max() ?? 0
            // A new opaque object can retain the wood's color. Unexplained
            // brightening of formerly dark reference ink vetoes an empty result.
            let x=p.x+(vertical ? best.0 : 0),y=p.y+(vertical ? 0 : best.0)
            if let base=reference.patchMean(referenceCalibration.point(col:x,row:y)) {
                let live=[-0.04,0,0.04].compactMap { offset in
                    frame.patchMean(calibration.point(col:x+(vertical ? offset : 0),row:y+(vertical ? 0 : offset)))
                }.min() ?? 0
                if live-correction-base>0.08 && live-correction>woodLevel-0.08 { unexplainedCoveredInk += 1 }
            }
            ink.append(InkEvidence(point:p,axis:axis,survives:current>0.04 && current>=best.1*0.55 && current<=best.1*1.8))
        } }
        guard unexplainedCoveredInk<2 else { return false }
        let edgeColumn=col==0 || col==calibration.size-1
        let edgeRow=row==0 || row==calibration.size-1
        guard !(edgeColumn && edgeRow) else { return false }
        var feasible=0
        for dy in -6...6 { for dx in -6...6 {
            let center=ImagePoint(x:Double(col)+Double(dx)*0.075,y:Double(row)+Double(dy)*0.075)
            guard pow((center.x-Double(col))/rx,2)+pow((center.y-Double(row))/ry,2)<=0.81 else { continue }
            if neighbors.contains(where:{hypot((center.x-$0.center.x)/(rx+$0.radiusCol),(center.y-$0.center.y)/(ry+$0.radiusRow))<0.90}) { continue }
            feasible += 1
            func inside(_ p:ImagePoint,_ scale:Double)->Bool { pow((p.x-center.x)/(rx*scale),2)+pow((p.y-center.y)/(ry*scale),2)<=1 }
            let body=wood.filter{inside($0.point,0.85)}
            guard body.count>=15,Double(body.filter(\.matches).count)/Double(body.count)>=0.85 else {
                return false
            }
            for axis in 0..<2 {
                let rails=ink.filter{$0.axis==axis && inside($0.point,0.95)}
                // At an outer rail the perpendicular printed line terminates.
                // Require three surviving samples on the continuing rail instead.
                let terminated=(axis==0 && edgeColumn) || (axis==1 && edgeRow)
                if terminated { continue }
                guard rails.filter(\.survives).count >= ((edgeColumn || edgeRow) ? 3 : 2) else {
                    return false
                }
            }
        } }
        // Geometry alone never proves emptiness, including an implausibly tight gap.
        return feasible>=3
    }
}
