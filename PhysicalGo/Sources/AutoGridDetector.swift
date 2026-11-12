import Foundation
import CoreGraphics
import CoreImage
import Vision

/// On-device rectangle proposals followed by independent validation of the printed grid.
/// Vision supplies a search area; only the grid fit supplies playable intersections.
enum AutoGridDetector {
    struct Result {
        let calibration: BoardCalibration
        let quality: Double // Geometric/contrast score, not a probability.
    }
    private struct AxisFit { let first: Double; let last: Double; let pitch: Double; let strength: Double }
    private struct Line { let intercept: Double; let slope: Double }
    private static func debug(_ text: String) {
        if ProcessInfo.processInfo.environment["PHYSICAL_GO_GRID_DEBUG"] == "1" { FileHandle.standardError.write(Data((text+"\n").utf8)) }
    }
    private static let side = 512
    private static let expansion = 0.04
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    static func detect(image: CGImage, size: Int, candidates:((Result)->Void)?=nil,knownPosition:Bool=false) throws -> Result? {
        guard [9,13,19].contains(size), let frame = GrayFrame(image: image, includeColor:false) else { return nil }
        // Thin grid lines and a textured background can hide the board outline from
        // Vision, even in a clear view. Search progressively smoother proposals;
        // always fit and validate the printed lines in the original, sharp frame.
        let original = CIImage(cgImage: image)
        let shortSide = Double(min(image.width,image.height))
        for fraction in [0.0,0.0025,0.005,0.008] {
            let proposalImage: CGImage
            if fraction == 0 { proposalImage = image }
            else {
                let softened = original.clampedToExtent()
                    .applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:shortSide*fraction])
                    .cropped(to:original.extent)
                guard let rendered = imageContext.createCGImage(softened,from:original.extent) else { continue }
                proposalImage = rendered
            }
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 8
            request.minimumConfidence = 0.4
            request.minimumAspectRatio = 0.35
            request.maximumAspectRatio = 1
            request.minimumSize = 0.25
            request.quadratureTolerance = 35
            try VNImageRequestHandler(cgImage: proposalImage, options: [:]).perform([request])
            var results = [Result]()
            debug("Proposal smoothing \(fraction): \(request.results?.count ?? 0) rectangles")
            for rectangle in request.results ?? [] {
                let corners = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft].map {
                    ImagePoint(x: Double($0.x), y: 1-Double($0.y))
                }
                guard let proposal = BoardCalibration(size: size, corners: corners),
                      let result = fit(frame: frame, proposal: proposal,knownPosition:knownPosition) else { continue }
                results.append(result);candidates?(result)
            }
            if let best = results.max(by: { $0.quality < $1.quality }) { return best }
        }
        return nil
    }

    struct RecoveryResult {
        let result:Result?
        let usedStones:Bool
        let needsFullBoard:Bool
        let reason:String
    }
    struct LandmarkEvidence {
        let fraction:Double
        let matched:Int
        let distributed:Bool
        var supported:Bool {matched>=4 && fraction>=0.6 && distributed}
    }
    /// Verify a retained homography without requiring projection peaks through
    /// occupied rows. Stones establish intersection identity; exposed segments
    /// establish the printed lattice, all four borders and distributed coverage.
    static func knownGridSupport(frame:GrayFrame,calibration:BoardCalibration,expected:[Occupancy],allowSingleCoveredBorder:Bool=false)->Double? {
        let n=calibration.size
        guard expected.count==n*n else {return nil}
        var tested=0,matched=0,borders=[Int](repeating:0,count:4),quadrants=[Int](repeating:0,count:4)
        for vertical in [false,true] {for rail in 0..<n {for segment in 0..<(n-1) {
            let first=vertical ? segment*n+rail:rail*n+segment
            let second=first+(vertical ? n:1)
            guard expected[first] == .empty,expected[second] == .empty else {continue}
            let col=vertical ? Double(rail):Double(segment)+0.5
            let row=vertical ? Double(segment)+0.5:Double(rail)
            var contrast = -1.0
            for shift in [-0.12,-0.08,-0.04,0,0.04,0.08,0.12] {
                let c=col+(vertical ? shift:0),r=row+(vertical ? 0:shift)
                guard let center=sample(frame,calibration.point(col:c,row:r)),
                      let a=sample(frame,calibration.point(col:c-(vertical ? 0.16:0),row:r-(vertical ? 0:0.16))),
                      let b=sample(frame,calibration.point(col:c+(vertical ? 0.16:0),row:r+(vertical ? 0:0.16))) else {continue}
                contrast=max(contrast,min(a,b)-center)
            }
            tested += 1
            guard contrast>0.045 else {continue}
            matched += 1
            if rail==0 {borders[vertical ? 0:2] += 1}
            if rail==n-1 {borders[vertical ? 1:3] += 1}
            quadrants[(row<Double(n)/2 ? 0:2)+(col<Double(n)/2 ? 0:1)] += 1
        }}}
        debug("Known grid segments \(matched)/\(tested), borders \(borders), quadrants \(quadrants)")
        // Only the live tracker with independently matched stone landmarks may
        // tolerate one covered edge. Acquisition still requires all four rails.
        let bordersSupported=borders.allSatisfy({$0>=3}) ||
            (allowSingleCoveredBorder && borders.filter({$0>=max(3,n/2)}).count>=3)
        guard tested>=n*4,matched>=n*4,Double(matched)>=Double(tested)*0.65,
              bordersSupported,quadrants.allSatisfy({$0>=n/2}) else {return nil}
        return Double(matched)/Double(tested)
    }
    /// Small scale/pose changes can leave stone identities obvious while moving
    /// thin lines several pixels. Fit the exposed outer rails in prior grid units.
    private static func refineKnownGrid(frame:GrayFrame,calibration:BoardCalibration,expected:[Occupancy])->BoardCalibration? {
        let n=calibration.size
        var lines=[Line]()
        for vertical in [true,false] {for rail in [0,n-1] {
            var points=[(Double,Double)]()
            for segment in 0..<(n-1) {
                let first=vertical ? segment*n+rail:rail*n+segment,second=first+(vertical ? n:1)
                guard expected[first] == .empty,expected[second] == .empty else {continue}
                let along=Double(segment)+0.5,col=vertical ? Double(rail):along,row=vertical ? along:Double(rail)
                var best=0.045,offset:Double?
                for step in -18...18 {
                    let shift=Double(step)/100,c=col+(vertical ? shift:0),r=row+(vertical ? 0:shift)
                    guard let center=sample(frame,calibration.point(col:c,row:r)),
                          let a=sample(frame,calibration.point(col:c-(vertical ? 0.16:0),row:r-(vertical ? 0:0.16))),
                          let b=sample(frame,calibration.point(col:c+(vertical ? 0.16:0),row:r+(vertical ? 0:0.16))) else {continue}
                    let contrast=min(a,b)-center
                    if contrast>best {best=contrast;offset=shift}
                }
                if let offset {points.append((along,Double(rail)+offset))}
            }
            guard points.count>=6,let first=points.first,let last=points.last,last.0-first.0>=Double(n-1)*0.5 else {return nil}
            let count=Double(points.count),mx=points.map{$0.0}.reduce(0,+)/count,my=points.map{$0.1}.reduce(0,+)/count
            let variance=points.map{pow($0.0-mx,2)}.reduce(0,+)
            let slope=points.map{($0.0-mx)*($0.1-my)}.reduce(0,+)/variance
            let intercept=my-slope*mx
            guard points.allSatisfy({abs($0.1-intercept-slope*$0.0)<0.09}) else {return nil}
            lines.append(Line(intercept:intercept,slope:slope))
        }}
        var corners=[ImagePoint]()
        for (v,h) in [(0,2),(1,2),(1,3),(0,3)] {
            let vertical=lines[v],horizontal=lines[h]
            let denominator=1-vertical.slope*horizontal.slope
            guard abs(denominator)>0.9 else {return nil}
            let x=(vertical.intercept+vertical.slope*horizontal.intercept)/denominator
            let y=horizontal.intercept+horizontal.slope*x
            let expectedX=v==0 ? 0:Double(n-1),expectedY=h==2 ? 0:Double(n-1)
            guard hypot(x-expectedX,y-expectedY)<0.25 else {return nil}
            corners.append(calibration.point(col:x,row:y))
        }
        return BoardCalibration(size:n,corners:corners)
    }
    /// Independent disk/wood contrast: expected labels select locations, never supply observations.
    static func landmarkEvidence(frame:GrayFrame,size:Int,expected:[Occupancy],point:(Double,Double)->ImagePoint)->LandmarkEvidence {
        var count=0,matched=[(Double,Double)]()
        for i in expected.indices where expected[i].stone != nil {
            count += 1
            let c=Double(i%size),r=Double(i/size)
            var core=[Double](),wood=[Double]()
            for x in [-1.0,1.0] {for y in [-1.0,1.0] {
                if let value=frame.patchMean(point(c+x*0.18,r+y*0.18)) {core.append(value)}
                if let value=frame.patchMean(point(c+x*0.49,r+y*0.49)) {wood.append(value)}
            }}
            guard core.count==4,wood.count==4 else {continue}
            let center=median(core),outside=median(wood)
            let contrast=expected[i] == .black ? outside-center:center-outside
            // A dark grid cross cannot fill all four off-line samples like a stone does.
            let coherent=core.filter {expected[i] == .black ? outside-$0>0.06:$0-outside>0.06}.count
            if contrast>0.09 && coherent>=3 {matched.append((c,r))}
        }
        let n=Double(max(1,matched.count)),mx=matched.map{$0.0}.reduce(0,+)/n,my=matched.map{$0.1}.reduce(0,+)/n
        let xx=matched.map{pow($0.0-mx,2)}.reduce(0,+)/n,yy=matched.map{pow($0.1-my,2)}.reduce(0,+)/n
        let xy=matched.map{($0.0-mx)*($0.1-my)}.reduce(0,+)/n
        // Reject a single tight cluster or a line of stones as a geometric anchor.
        return .init(fraction:Double(matched.count)/Double(max(1,count)),matched:matched.count,
                     distributed:xx>=1 && yy>=1 && xx*yy-xy*xy>=2)
    }
    /// Recovery is deliberately separate from cheap per-frame tracking. The prior layout
    /// proposes translations; independently verified grid fits supply the homography.
    static func recover(image:CGImage,size:Int,previous:BoardCalibration?,expected:[Occupancy]) throws -> RecoveryResult {
        guard expected.count==size*size,expected.filter({$0.stone != nil}).count>=4,
              let frame=GrayFrame(image:image,includeColor:false) else {
            let found=try detect(image:image,size:size)
            return .init(result:found,usedStones:false,needsFullBoard:found==nil,reason:found==nil ? "Full grid not visible or not verifiable":"Grid recovered; too few stone landmarks")
        }
        var candidates=[Result]()
        if let previous,previous.size==size {
            let evidence=landmarkEvidence(frame:frame,size:size,expected:expected) {previous.point(col:$0,row:$1)}
            if evidence.supported,evidence.fraction>=0.8,
               let support=knownGridSupport(frame:frame,calibration:previous,expected:expected) {
                var calibration=previous,quality=support
                if let refined=refineKnownGrid(frame:frame,calibration:previous,expected:expected),
                   let refinedSupport=knownGridSupport(frame:frame,calibration:refined,expected:expected),refinedSupport>=support*0.97 {
                    let landmarks=landmarkEvidence(frame:frame,size:size,expected:expected) {refined.point(col:$0,row:$1)}
                    if landmarks.supported,landmarks.fraction>=0.8 {calibration=refined;quality=refinedSupport}
                }
                return .init(result:Result(calibration:calibration,quality:quality),usedStones:true,needsFullBoard:false,
                             reason:"Existing grid verified with \(evidence.matched) known stones and exposed grid segments")
            }
        }
        func add(_ candidate:Result) {
            guard !candidates.contains(where:{zip($0.calibration.corners,candidate.calibration.corners).allSatisfy {hypot($0.x-$1.x,$0.y-$1.y)<0.004}}) else {return}
            candidates.append(candidate)
        }
        var projectedOutside=false
        if let previous,previous.size==size {
            var proposals=[(Double,Double,LandmarkEvidence)]()
            // Up to three intersections in any direction, at half-cell spacing.
            for dy in -6...6 {for dx in -6...6 {
                let x=Double(dx)*0.5,y=Double(dy)*0.5
                let evidence=landmarkEvidence(frame:frame,size:size,expected:expected) {previous.point(col:$0+x,row:$1+y)}
                if evidence.supported {proposals.append((x,y,evidence))}
            }}
            proposals.sort {$0.2.fraction>$1.2.fraction}
            for (dx,dy,_) in proposals.prefix(8) {
                let n=Double(size-1)
                let corners=[(0.0,0.0),(n,0),(n,n),(0,n)].map {previous.point(col:$0.0+dx,row:$0.1+dy)}
                guard let proposal=BoardCalibration(size:size,corners:corners) else {projectedOutside=true;continue}
                if let fitted=fit(frame:frame,proposal:proposal,knownPosition:true) {add(fitted)}
            }
        }
        // A global rectangle search handles larger shifts, scale, perspective and roll.
        if let found=try detect(image:image,size:size,candidates:{add($0)},knownPosition:true) {add(found)}
        var ranked=[(Result,LandmarkEvidence)]()
        for candidate in candidates {
            for turns in 0..<4 {
                let corners=Array(candidate.calibration.corners[turns...])+Array(candidate.calibration.corners[..<turns])
                guard let calibration=BoardCalibration(size:size,corners:corners) else {continue}
                let evidence=landmarkEvidence(frame:frame,size:size,expected:expected) {calibration.point(col:$0,row:$1)}
                guard evidence.supported else {continue}
                let rotated=Result(calibration:calibration,quality:candidate.quality)
                if !ranked.contains(where:{zip($0.0.calibration.corners,corners).allSatisfy {hypot($0.x-$1.x,$0.y-$1.y)<0.008}}) {ranked.append((rotated,evidence))}
            }
        }
        ranked.sort {$0.1.fraction>$1.1.fraction}
        guard let best=ranked.first else {
            return .init(result:nil,usedStones:false,needsFullBoard:candidates.isEmpty || projectedOutside,
                         reason:candidates.isEmpty ? "Full grid not visible or not verifiable":"Grid found, but known stones do not verify its alignment")
        }
        if ranked.count>1,best.1.fraction-ranked[1].1.fraction<0.15 {
            return .init(result:nil,usedStones:false,needsFullBoard:false,reason:"Stone layout has more than one plausible alignment")
        }
        return .init(result:best.0,usedStones:true,needsFullBoard:false,
                     reason:"Grid verified with \(best.1.matched) known stone landmarks")
    }

    struct TrackingAnchor {
        let calibration:BoardCalibration
        let fittedGrid:BoardCalibration
        let frame:GrayFrame
    }
    static func trackingAnchor(frame:GrayFrame,calibration:BoardCalibration)->TrackingAnchor? {
        let fitted=fit(frame:frame,proposal:calibration)?.calibration ?? calibration
        let anchor=TrackingAnchor(calibration:calibration,fittedGrid:fitted,frame:frame)
        return alignmentSupported(frame:frame,calibration:calibration,anchor:anchor) ? anchor : nil
    }
    /// Compare each frame against a fixed grid anchor, never against a succession
    /// of resampled fits. Preserve original calibration offsets so the current
    /// image and the untouched empty reference still sample corresponding wood.
    static func track(frame:GrayFrame,from previous:BoardCalibration,anchor:TrackingAnchor,
                      expected:[Occupancy]=[],report:(([String:Any])->Void)?=nil)->BoardCalibration? {
        var details:[String:Any]=[:]
        defer {report?(details)}
        func finite(_ value:Double)->Any {value.isFinite ? value as Any:NSNull()}
        // Instrument the existing decisions without changing their thresholds.
        if alignmentSupported(frame:frame,calibration:previous,anchor:anchor,report:{details["initialSupport"]=$0}) {
            details["outcome"]="existing grid supported";return previous
        }
        // A sleeve may hide one outer rail while the board is stationary.
        // Verify actual stone disks and exposed lines before declaring loss.
        // History selects test points; it never supplies their visual evidence.
        if expected.count==previous.size*previous.size {
            let landmarks=landmarkEvidence(frame:frame,size:previous.size,expected:expected) {previous.point(col:$0,row:$1)}
            details["knownStoneMatches"]=landmarks.matched
            details["knownStoneFraction"]=landmarks.fraction
            details["knownStonesDistributed"]=landmarks.distributed
            if landmarks.supported,landmarks.matched>=6,landmarks.fraction>=0.85,
               let support=knownGridSupport(frame:frame,calibration:previous,expected:expected,allowSingleCoveredBorder:true) {
                details["knownGridSupport"]=support
                details["outcome"]="existing grid supported by known stones and exposed lines"
                return previous
            }
        }
        guard let result=fit(frame:frame,proposal:anchor.calibration) else {
            let error=trackingError(frame:frame,calibration:previous,anchor:anchor)
            details["profileError"]=finite(error);details["profileErrorLimit"]=0.04
            let supported=error<0.04 && alignmentSupported(frame:frame,calibration:previous,anchor:anchor,
                minimumFraction:0.33,report:{details["fallbackSupport"]=$0})
            details["outcome"]=supported ? "fallback grid supported":"rejected"
            if !supported {details["rejectionReason"]=error>=0.04 ? "no grid fit; profile error too high":"no grid fit; insufficient distributed line support"}
            return supported ? previous:nil
        }
        details["fitQuality"]=result.quality
        let corners=anchor.calibration.corners.compactMap { p -> ImagePoint? in
            guard let grid=anchor.fittedGrid.gridPoint(for:p) else { return nil }
            return result.calibration.point(col:grid.x,row:grid.y)
        }
        guard let aligned=BoardCalibration(size:previous.size,corners:corners) else {
            details["outcome"]="rejected";details["rejectionReason"]="invalid fitted corners";return nil
        }
        var maximum=0.0
        for (old,new) in zip(anchor.calibration.corners,aligned.corners) {
            guard let a=anchor.calibration.gridPoint(for:old),let b=anchor.calibration.gridPoint(for:new) else {
                details["outcome"]="rejected";details["rejectionReason"]="corner transform failed";return nil
            }
            maximum=max(maximum,hypot(a.x-b.x,a.y-b.y))
        }
        details["maximumMovementCells"]=finite(maximum);details["maximumMovementLimit"]=0.4
        guard maximum<0.4 else {
            details["outcome"]="rejected";details["rejectionReason"]="fitted grid moved at least 0.4 intersections";return nil
        }
        let pixels=zip(previous.corners,aligned.corners).map {
            hypot(($0.x-$1.x)*Double(frame.width-1),($0.y-$1.y)*Double(frame.height-1))
        }.max() ?? 0
        let jitterTolerance=max(0.75,Double(min(frame.width,frame.height))/540)
        details["movementPixels"]=finite(pixels);details["jitterTolerancePixels"]=jitterTolerance
        if pixels<jitterTolerance {details["outcome"]="subpixel jitter; existing grid retained";return previous}
        let before=trackingError(frame:frame,calibration:previous,anchor:anchor)
        let after=trackingError(frame:frame,calibration:aligned,anchor:anchor)
        details["profileErrorBefore"]=finite(before);details["profileErrorAfter"]=finite(after)
        details["requiredErrorRatio"]=0.8;details["requiredErrorImprovement"]=0.008
        if after<before*0.8 && before-after>0.008 {details["outcome"]="tracking correction accepted";return aligned}
        if before<0.04 {details["outcome"]="existing grid retained by profile error";return previous}
        details["outcome"]="rejected";details["rejectionReason"]="tracking correction insufficient; existing profile error too high"
        return nil
    }

    private static func alignmentSupported(frame:GrayFrame,calibration:BoardCalibration,anchor:TrackingAnchor,minimumFraction:Double=0.6,report:(([String:Any])->Void)?=nil)->Bool {
        let n=calibration.size
        var tested=0,matched=0,borders=[Int](repeating:0,count:4),quadrants=[Int](repeating:0,count:4)
        for vertical in [false,true] { for rail in 0..<n { for segment in 0..<(n-1) {
            var a=[Double](),b=[Double]()
            for across in [-0.18,-0.12,-0.06,0,0.06,0.12,0.18] {
                let c=vertical ? Double(rail)+across : Double(segment)+0.5
                let r=vertical ? Double(segment)+0.5 : Double(rail)+across
                if let old=anchor.frame.patchMean(anchor.calibration.point(col:c,row:r)),
                   let now=frame.patchMean(calibration.point(col:c,row:r)) { a.append(old); b.append(now) }
            }
            guard a.count==7,let high=a.max(),let low=a.min(),high-low>0.06,let currentHigh=b.max(),let currentLow=b.min() else { continue }
            tested += 1
            let depth=high-low,currentDepth=currentHigh-currentLow
            guard currentDepth>max(0.035,depth*0.25),currentDepth<depth*3 else { continue }
            var error=0.0
            // Compare line shape independently of exposure. Both profiles still
            // need real contrast, outer-rail support and matching quadrants.
            for i in a.indices { error += abs((a[i]-high)/depth-(b[i]-currentHigh)/currentDepth) }
            guard error/7<min(0.10,0.03/depth) else { continue }
            matched += 1
            if rail==0 { borders[vertical ? 0 : 2] += 1 }
            if rail==n-1 { borders[vertical ? 1 : 3] += 1 }
            let c=vertical ? rail : segment,r=vertical ? segment : rail
            quadrants[(r<n/2 ? 0 : 2)+(c<n/2 ? 0 : 1)] += 1
        } } }
        debug("Stable profile support \(matched)/\(tested), edges \(borders), quadrants \(quadrants)")
        // All four outer rails disambiguate a whole-row/column translation.
        var failed=[String]()
        if tested<n*4 {failed.append("too few reference line samples")}
        if matched<n*8 {failed.append("too few matching line samples")}
        if Double(matched)<Double(tested)*minimumFraction {failed.append("matching fraction below minimum")}
        if !borders.allSatisfy({$0>=3}) {failed.append("one or more outer rails lack support")}
        if !quadrants.allSatisfy({$0>=n/2}) {failed.append("one or more quadrants lack support")}
        report?(["tested":tested,"matched":matched,"minimumTested":n*4,"minimumMatched":n*8,
                 "minimumFraction":minimumFraction,"borderMatches":borders,"minimumPerBorder":3,
                 "quadrantMatches":quadrants,"minimumPerQuadrant":n/2,"failedChecks":failed])
        return failed.isEmpty
    }

    private static func trackingError(frame:GrayFrame,calibration:BoardCalibration,anchor:TrackingAnchor)->Double {
        var errors=[Double]()
        for vertical in [false,true] { for rail in 0..<calibration.size {
            for segment in 0..<(calibration.size-1) {
                var base=[Double](),current=[Double]()
                for across in [-0.18,-0.12,-0.06,0,0.06,0.12,0.18] {
                    let c=vertical ? Double(rail)+across : Double(segment)+0.5
                    let r=vertical ? Double(segment)+0.5 : Double(rail)+across
                    if let a=anchor.frame.patchMean(anchor.calibration.point(col:c,row:r)),
                       let b=frame.patchMean(calibration.point(col:c,row:r)) { base.append(a); current.append(b) }
                }
                guard base.count==7,let bright=base.max(),let dark=base.min(),bright-dark>0.06,
                      let currentBright=current.max() else { continue }
                var difference=0.0
                for index in base.indices { difference += abs((base[index]-bright)-(current[index]-currentBright)) }
                errors.append(difference/7)
            }
        } }
        return errors.count>=calibration.size*4 ? median(errors) : .infinity
    }

    private static func sample(_ frame: GrayFrame, _ p: ImagePoint) -> Double? {
        guard (0...1).contains(p.x), (0...1).contains(p.y) else { return nil }
        let x = p.x*Double(frame.width-1), y = p.y*Double(frame.height-1)
        let x0 = Int(x), y0 = Int(y), x1 = min(frame.width-1,x0+1), y1 = min(frame.height-1,y0+1)
        let a = x-Double(x0), b = y-Double(y0)
        let top = Double(frame.pixels[y0*frame.width+x0])*(1-a)+Double(frame.pixels[y0*frame.width+x1])*a
        let bottom = Double(frame.pixels[y1*frame.width+x0])*(1-a)+Double(frame.pixels[y1*frame.width+x1])*a
        return (top*(1-b)+bottom*b)/255
    }
    private static func sourcePoint(_ proposal: BoardCalibration, x: Double, y: Double) -> ImagePoint {
        let scale = Double(proposal.size-1)
        return proposal.point(col: (x/Double(side-1)*(1+2*expansion)-expansion)*scale,
                              row: (y/Double(side-1)*(1+2*expansion)-expansion)*scale)
    }
    private static func fit(frame: GrayFrame, proposal: BoardCalibration,knownPosition:Bool=false) -> Result? {
        var rectified = [Double](repeating: 1, count: side*side)
        for y in 0..<side { for x in 0..<side {
            rectified[y*side+x] = sample(frame, sourcePoint(proposal,x:Double(x),y:Double(y))) ?? 1
        } }
        var columns = [Double](repeating:0,count:side), rows = columns
        let margin = side/12
        for i in 0..<side {
            for j in margin..<(side-margin) { columns[i] += rectified[j*side+i]; rows[i] += rectified[i*side+j] }
            columns[i] /= Double(side-2*margin); rows[i] /= Double(side-2*margin)
        }
        let xFits = fitAxis(columns,count:proposal.size,knownPosition:knownPosition), yFits = fitAxis(rows,count:proposal.size,knownPosition:knownPosition)
        var results = [Result]()
        for xFit in xFits { for yFit in yFits {
            if let result = fitGrid(frame:frame,proposal:proposal,rectified:rectified,xFit:xFit,yFit:yFit) { results.append(result) }
        } }
        return results.max { $0.quality < $1.quality }
    }
    private static func fitGrid(frame:GrayFrame,proposal:BoardCalibration,rectified:[Double],xFit:AxisFit,yFit:AxisFit) -> Result? {
        debug("Fits \(xFit) \(yFit)")
        let left = refine(rectified, at:xFit.first, start:yFit.first, end:yFit.last, vertical:true, pitch:xFit.pitch)
        let right = refine(rectified, at:xFit.last, start:yFit.first, end:yFit.last, vertical:true, pitch:xFit.pitch)
        let top = refine(rectified, at:yFit.first, start:xFit.first, end:xFit.last, vertical:false, pitch:yFit.pitch)
        let bottom = refine(rectified, at:yFit.last, start:xFit.first, end:xFit.last, vertical:false, pitch:yFit.pitch)
        func intersect(_ vertical: Line, _ horizontal: Line) -> ImagePoint? {
            let denominator = 1-vertical.slope*horizontal.slope
            guard abs(denominator)>0.5 else { return nil }
            let x = (vertical.intercept+vertical.slope*horizontal.intercept)/denominator
            let y = horizontal.intercept+horizontal.slope*x
            return sourcePoint(proposal,x:x,y:y)
        }
        let corners = [intersect(left,top),intersect(right,top),intersect(right,bottom),intersect(left,bottom)].compactMap { $0 }
        guard let calibration = BoardCalibration(size:proposal.size,corners:corners) else { return nil }
        // Check every predicted rail against the original image. A rectangle alone,
        // the board's wood edge, or a plausible-looking subset must not be accepted.
        var scores = [Double]()
        for vertical in [false,true] { for rail in 0..<proposal.size {
            var contrasts = [Double]()
            for index in 0..<(proposal.size-1) { for offset in [0.33,0.67] {
                let along = Double(index)+offset
                let col = vertical ? Double(rail) : along, row = vertical ? along : Double(rail)
                // Real lenses and slightly bowed printed lines need a narrow tolerance
                // around the ideal homography, much smaller than one grid spacing.
                var best = -1.0
                for shift in [-0.08,-0.04,0,0.04,0.08] {
                    let c = col+(vertical ? shift : 0), r = row+(vertical ? 0 : shift)
                    let p = calibration.point(col:c,row:r)
                    let p1 = calibration.point(col:c+(vertical ? -0.12 : 0),row:r+(vertical ? 0 : -0.12))
                    let p2 = calibration.point(col:c+(vertical ? 0.12 : 0),row:r+(vertical ? 0 : 0.12))
                    if let center = sample(frame,p), let a = sample(frame,p1), let b = sample(frame,p2) {
                        best = max(best,(a+b)*0.5-center)
                    }
                }
                if best > -1 { contrasts.append(best) }
            } }
            scores.append(median(contrasts))
        } }
        debug("Corners \(corners); rail scores \(scores)")
        let supported = scores.filter { $0 > 0.035 }.count
        guard [0,proposal.size-1,proposal.size,2*proposal.size-1].allSatisfy({ scores[$0] > 0.035 }) else { return nil }
        guard supported >= Int(ceil(Double(scores.count)*0.9)), median(scores) > 0.07 else { return nil }
        return Result(calibration:calibration,quality:median(scores)+0.1*(xFit.strength+yFit.strength))
    }
    private static func median(_ values:[Double]) -> Double {
        let values = values.sorted(); return values.isEmpty ? 0 : values[values.count/2]
    }
    private static func fitAxis(_ profile:[Double],count:Int,knownPosition:Bool=false) -> [AxisFit] {
        var ridge = [Double](repeating:0,count:side)
        for i in 5..<(side-5) { ridge[i] = (profile[i-4]+profile[i+4])*0.5-profile[i] }
        let cutoff = max(0.015,(ridge.max() ?? 0)*0.10)
        let peaks = (6..<(side-6)).filter { i in ridge[i]>=cutoff && ridge[i] == ridge[(i-3)...(i+3)].max()! }
        debug("Peaks \(peaks.map { "\($0):\(ridge[$0])" })")
        guard peaks.count >= count else { return [] }
        var fits = [(AxisFit,Double)]()
        for first in peaks where first < side/5 {
            for last in peaks where last > side*4/5 {
                let pitch = Double(last-first)/Double(count-1)
                guard pitch >= 12 else { continue }
                let tolerance = min(6,pitch*0.22)
                // The wood margin should be blank. A further regularly spaced line
                // inside the proposed board means this sequence is shifted/truncated.
                let border = Double(side-1)*expansion/(1+2*expansion)
                let extensions = [Double(first)-pitch,Double(last)+pitch]
                if extensions.contains(where: { position in
                    position > border+2 && position < Double(side-1)-border-2 &&
                    peaks.contains(where: { abs(Double($0)-position)<tolerance })
                }) { continue }
                var matches = [Int]()
                for i in 0..<count {
                    let expected = Double(first)+Double(i)*pitch
                    if let peak = peaks.filter({ abs(Double($0)-expected)<tolerance }).max(by:{ridge[$0]<ridge[$1]}) { matches.append(peak) }
                }
                guard matches.count == count, Set(matches).count == count else { continue }
                // Reject a wrong board size fitting every second line of a larger grid.
                let unused = peaks.filter { $0>=first && $0<=last && !matches.contains($0) }
                // Occupied boards also have peaks from stone rims and shadows.
                // Recovery verifies intersection identity against saved stones;
                // ordinary grid discovery retains the strict extra-line check.
                guard knownPosition || unused.count <= max(1,count/8) else { continue }
                let errors = matches.enumerated().map { abs(Double($0.element)-(Double(first)+Double($0.offset)*pitch))/pitch }
                guard errors.max() ?? 1 < 0.16 else { continue }
                let strength = matches.map { ridge[$0] }.reduce(0,+)/Double(count)
                let score = strength-0.8*errors.reduce(0,+)/Double(count)
                fits.append((AxisFit(first:Double(first),last:Double(last),pitch:pitch,strength:strength),score))
            }
        }
        return fits.sorted { $0.1 > $1.1 }.prefix(4).map { $0.0 }
    }
    private static func refine(_ pixels:[Double],at position:Double,start:Double,end:Double,vertical:Bool,pitch:Double) -> Line {
        func value(_ x:Double,_ y:Double) -> Double? {
            guard x>=0,y>=0,x<Double(side-1),y<Double(side-1) else { return nil }
            let xi=Int(x),yi=Int(y),a=x-Double(xi),b=y-Double(yi)
            return (pixels[yi*side+xi]*(1-a)+pixels[yi*side+xi+1]*a)*(1-b)
                + (pixels[(yi+1)*side+xi]*(1-a)+pixels[(yi+1)*side+xi+1]*a)*b
        }
        func score(_ a:Double,_ b:Double) -> Double {
            var values = [Double]()
            for index in 0..<64 {
                let t = (Double(index)+0.5)/64
                let along = start+(end-start)*t
                let across = position+a+(b-a)*t
                let center = vertical ? value(across,along) : value(along,across)
                let before = vertical ? value(across-4,along) : value(along,across-4)
                let after = vertical ? value(across+4,along) : value(along,across+4)
                if let center,let before,let after { values.append((before+after)*0.5-center) }
            }
            // Positive contributions on most of a rail beat isolated dark objects.
            return values.isEmpty ? -1 : values.reduce(0,+)/Double(values.count)
        }
        let radius = min(8,pitch*0.28)
        var a=0.0,b=0.0,best = -Double.infinity
        for da in stride(from:-radius,through:radius,by:2) { for db in stride(from:-radius,through:radius,by:2) {
            let result=score(da,db); if result>best { best=result;a=da;b=db }
        } }
        let oldA=a,oldB=b
        for da in stride(from:oldA-2,through:oldA+2,by:0.5) { for db in stride(from:oldB-2,through:oldB+2,by:0.5) {
            let result=score(da,db); if result>best { best=result;a=da;b=db }
        } }
        let slope=(b-a)/(end-start)
        return Line(intercept:position+a-slope*start,slope:slope)
    }
}
