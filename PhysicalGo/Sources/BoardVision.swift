import Foundation
import CoreGraphics

// Image coordinates always run from top-left (0,0) to bottom-right (1,1).
struct ImagePoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct BoardCalibration: Codable, Equatable {
    let size: Int
    let corners: [ImagePoint] // TL, TR, BR, BL: corner intersections, not wood edges.
    private let h: [Double]

    init?(size: Int, corners: [ImagePoint]) {
        guard [9, 13, 19].contains(size), corners.count == 4,
              corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return nil }
        // Reject crossed, reversed, tiny and nearly collinear quadrilaterals.
        var area = 0.0
        for i in 0..<4 {
            let a = corners[i], b = corners[(i+1)%4], c = corners[(i+2)%4]
            guard (b.x-a.x)*(c.y-b.y) - (b.y-a.y)*(c.x-b.x) > 0.0005 else { return nil }
            area += a.x*b.y - b.x*a.y
        }
        guard area > 0.04 else { return nil }
        let unit = [(0.0,0.0),(1.0,0.0),(1.0,1.0),(0.0,1.0)]
        var a = [[Double]]()
        for i in 0..<4 {
            let (u,v) = unit[i], p = corners[i]
            a.append([u,v,1,0,0,0,-p.x*u,-p.x*v,p.x])
            a.append([0,0,0,u,v,1,-p.y*u,-p.y*v,p.y])
        }
        for col in 0..<8 {
            let pivot = (col..<8).max { abs(a[$0][col]) < abs(a[$1][col]) }!
            guard abs(a[pivot][col]) > 1e-9 else { return nil }
            a.swapAt(col, pivot)
            let d = a[col][col]
            for j in col...8 { a[col][j] /= d }
            for row in 0..<8 where row != col {
                let f = a[row][col]
                for j in col...8 { a[row][j] -= f*a[col][j] }
            }
        }
        self.size = size; self.corners = corners; self.h = a.map { $0[8] }
    }

    func point(col: Double, row: Double) -> ImagePoint {
        let u = col / Double(size-1), v = row / Double(size-1)
        let d = h[6]*u + h[7]*v + 1
        return ImagePoint(x: (h[0]*u+h[1]*v+h[2])/d, y: (h[3]*u+h[4]*v+h[5])/d)
    }

    /// Columns of the unit-grid homography, in normalized source coordinates.
    var projectiveAxes: [(Double,Double,Double)] { [(h[0],h[3],h[6]),(h[1],h[4],h[7])] }

    /// Inverse of point(col:row:), including the small border outside the grid.
    func gridPoint(for point:ImagePoint)->ImagePoint? {
        guard point.x.isFinite,point.y.isFinite else { return nil }
        let a=h[0]-point.x*h[6],b=h[1]-point.x*h[7],c=point.x-h[2]
        let d=h[3]-point.y*h[6],e=h[4]-point.y*h[7],f=point.y-h[5]
        let determinant=a*e-b*d
        guard abs(determinant)>1e-12 else { return nil }
        let n=Double(size-1)
        return ImagePoint(x:(c*e-b*f)/determinant*n,y:(a*f-c*d)/determinant*n)
    }
}

struct BoardChroma {
    let red: Double
    let green: Double
    var blue: Double { -red-green }
    var magnitude: Double { sqrt(red*red+green*green+blue*blue) }
    static func + (a:Self,b:Self)->Self { .init(red:a.red+b.red,green:a.green+b.green) }
    static func - (a:Self,b:Self)->Self { .init(red:a.red-b.red,green:a.green-b.green) }
}

struct GrayFrame {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    private let colorBytes: [UInt8]?

    init(width: Int, height: Int, pixels: [UInt8], colorBytes: [UInt8]? = nil) {
        precondition(width > 0 && height > 0 && pixels.count == width*height)
        precondition(colorBytes == nil || colorBytes?.count == width*height*4)
        self.width = width; self.height = height; self.pixels = pixels
        self.colorBytes = colorBytes
    }

    init?(image: CGImage, includeColor: Bool = true) {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width*height)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        var colors: [UInt8]?
        if includeColor {
            var rgba = [UInt8](repeating:0,count:width*height*4)
            let rendered = rgba.withUnsafeMutableBytes { raw -> Bool in
                let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                guard let space = CGColorSpace(name:CGColorSpace.sRGB),
                      let context = CGContext(data:raw.baseAddress,width:width,height:height,bitsPerComponent:8,
                        bytesPerRow:width*4,space:space,bitmapInfo:flags) else { return false }
                context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
                return true
            }
            if rendered { colors = rgba }
        }
        self.init(width: width, height: height, pixels: bytes, colorBytes: colors)
    }

    /// Only the comparison uses this luminance scale. Camera pixels and the
    /// saved reference stay intact, including chromaticity measurements.
    func scaledLuminance(by gain: Double) -> GrayFrame {
        let lut=(0..<256).map { UInt8(min(255,(Double($0)*gain).rounded())) }
        return GrayFrame(width:width,height:height,pixels:pixels.map { lut[Int($0)] },colorBytes:colorBytes)
    }

    func adjustedLuminance(_ field:LightingCompensation.Field)->GrayFrame {
        var adjusted=pixels
        for row in 0..<height {
            let base=field.constant+field.y*Double(row)/Double(max(1,height-1))
            let step=field.x/Double(max(1,width-1))
            for col in 0..<width {
                let i=row*width+col,gain=max(0.45,min(2.8,base+step*Double(col)))
                adjusted[i]=UInt8(max(0,min(255,(Double(pixels[i])*gain).rounded())))
            }
        }
        return GrayFrame(width:width,height:height,pixels:adjusted,colorBytes:colorBytes)
    }

    func sample(_ p: ImagePoint) -> Double? {
        guard p.x.isFinite, p.y.isFinite, (0...1).contains(p.x), (0...1).contains(p.y) else { return nil }
        let x = min(width-1, Int((p.x*Double(width-1)).rounded()))
        let y = min(height-1, Int((p.y*Double(height-1)).rounded()))
        return Double(pixels[y*width+x])/255
    }

    // Small patches reduce single-pixel noise and sensitivity to subpixel changes.
    // Keep point sampling available for geometry and diagnostic callers.
    func patchMean(_ p: ImagePoint) -> Double? {
        guard p.x.isFinite, p.y.isFinite, (0...1).contains(p.x), (0...1).contains(p.y) else { return nil }
        let x = Int((p.x*Double(width-1)).rounded()), y = Int((p.y*Double(height-1)).rounded())
        var sum = 0, count = 0
        for row in max(0,y-1)...min(height-1,y+1) { for col in max(0,x-1)...min(width-1,x+1) {
            sum += Int(pixels[row*width+col]); count += 1
        } }
        return Double(sum)/Double(count*255)
    }

    func patchColor(_ p: ImagePoint) -> BoardChroma? {
        guard let colorBytes, p.x.isFinite, p.y.isFinite,
              (0...1).contains(p.x), (0...1).contains(p.y) else { return nil }
        let x = Int((p.x*Double(width-1)).rounded()), y = Int((p.y*Double(height-1)).rounded())
        var red = 0, green = 0, blue = 0, count = 0
        for row in max(0,y-1)...min(height-1,y+1) { for col in max(0,x-1)...min(width-1,x+1) {
            let index = (row*width+col)*4
            red += Int(colorBytes[index]); green += Int(colorBytes[index+1]); blue += Int(colorBytes[index+2]); count += 1
        } }
        let total = Double(red+green+blue)
        guard total > Double(count)*255*0.12 else { return nil } // Dark-pixel chroma is unreliable.
        return BoardChroma(red:Double(red)/total-1.0/3.0,green:Double(green)/total-1.0/3.0)
    }
}

enum Occupancy: String, Codable, CaseIterable {
    case empty, black, white, uncertain
    var stone: Stone? { self == .black ? .black : self == .white ? .white : nil }
    var next: Occupancy {
        switch self { case .uncertain: return .empty; case .empty: return .black; case .black: return .white; case .white: return .uncertain }
    }
}

struct IntersectionReading: Codable, Equatable {
    let row: Int
    let col: Int
    let occupancy: Occupancy
    let confidence: Double // Heuristic separation score, not a probability.
    let delta: Double
}

struct BoardObservation {
    let readings: [IntersectionReading]
    let size: Int
    var notice: String? = nil
    var lightingBlocked = false
    var lightingAdjusted = false
    var lightingField:LightingCompensation.Field? = nil
    var footprints: [StoneFootprint] = []
    var placementFits: [StoneFootprint] = []
    var manualPoints: Set<Int> = []
    /// Geometry-supported associations; never ground-truth training labels.
    var trackedAssignments: [Int:Int] = [:]
    var capturedAt:Double?=nil
    var handObstructed:Bool?=nil
    /// Positive geometric evidence about displacement, in grid-spacing units.
    /// Missing/weak outlines are not evidence that a placement is centered.
    var placementOffsets:[Int:Double] { offsets(forAssignment: false) }
    var assignmentOffsets:[Int:Double] { offsets(forAssignment: true) }

    func assignmentOffsets(confirmedBoard: [Occupancy]) -> [Int:Double] {
        offsets(forAssignment:true, confirmedBoard:confirmedBoard)
    }

    private func offsets(forAssignment: Bool, confirmedBoard: [Occupancy] = []) -> [Int:Double] {
        let shapes = footprints + placementFits
        // A previously recorded neighbor can rule out an alternative assignment
        // only if its own stone has a separate, visible outline at that point.
        func occupiedNeighbor(_ shape:StoneFootprint, col:Int, row:Int) -> Bool {
            guard col>=0, row>=0, col<size, row<size, confirmedBoard.count==readings.count else {return false}
            let index=row*size+col
            guard confirmedBoard[index].stone != nil, readings[index].occupancy==confirmedBoard[index],
                  readings[index].confidence>=0.9 else {return false}
            return shapes.contains { other in
                other.col==col && other.row==row && other.quality>=0.78 &&
                other.contains(.init(x:Double(col),y:Double(row))) &&
                hypot((shape.center.x-other.center.x)/(shape.radiusCol+other.radiusCol),
                      (shape.center.y-other.center.y)/(shape.radiusRow+other.radiusRow))>=0.90
            }
        }
        // Assignment depends on which intersection the outline covers, with an
        // 0.08-cell margin inside the target and outside every adjacent point.
        // Existing temporal confirmation still requires independent sightings.
        func uniquelyCovers(_ shape:StoneFootprint,index:Int)->Bool {
            guard shape.quality>=0.94,readings[index].confidence>=0.94,
                  (0.36...0.65).contains(shape.radiusCol),(0.36...0.65).contains(shape.radiusRow),
                  shape.contains(.init(x:Double(shape.col),y:Double(shape.row)),padding:-0.08) else {return false}
            for r in max(0,shape.row-1)...min(size-1,shape.row+1) {
                for c in max(0,shape.col-1)...min(size-1,shape.col+1) where r != shape.row || c != shape.col {
                    if shape.contains(.init(x:Double(c),y:Double(r)),padding:0.08) {return false}
                }
            }
            return true
        }
        return Dictionary(shapes.compactMap { shape -> (Int,Double)? in
            let index=shape.row*size+shape.col
            guard shape.quality>=0.86,readings.indices.contains(index),readings[index].occupancy.stone != nil else {return nil}
            let dx = shape.center.x - Double(shape.col)
            let dy = shape.center.y - Double(shape.row)
            let displacement = max(abs(dx), abs(dy))
            if forAssignment,uniquelyCovers(shape,index:index) {return (index,0)}
            // Outward displacement cannot favor another playable point. The
            // stone still has to cover the actual intersection with a strong fit.
            guard forAssignment, shape.quality >= 0.90, readings[index].confidence >= 0.90,
                  displacement <= 0.46, shape.contains(.init(x:Double(shape.col), y:Double(shape.row))) else {
                return (index, displacement)
            }
            let outwardX = (shape.col == 0 && dx < 0) || (shape.col == size - 1 && dx > 0)
            let outwardY = (shape.row == 0 && dy < 0) || (shape.row == size - 1 && dy > 0)
            let blockedX = abs(dx)>0.24 && abs(dy)<=0.24 && occupiedNeighbor(shape,col:shape.col+(dx>0 ? 1 : -1),row:shape.row)
            let blockedY = abs(dy)>0.24 && abs(dx)<=0.24 && occupiedNeighbor(shape,col:shape.col,row:shape.row+(dy>0 ? 1 : -1))
            return (index, max(outwardX || blockedX ? 0 : abs(dx), outwardY || blockedY ? 0 : abs(dy)))
        },uniquingKeysWith:max)
    }
    var ambiguousPlacements:Set<Int> {Set(assignmentOffsets.filter{$0.value>=0.30}.map(\.key))}
    var signature: [Occupancy] { readings.map(\.occupancy) }
    var snapshot: BoardSnapshot {
        var grid = Array(repeating: [Stone?](repeating: nil, count: size), count: size)
        var stones = [BoardPosition: Stone]()
        for r in readings { if let s = r.occupancy.stone { grid[r.row][r.col] = s; stones[BoardPosition(r.row,r.col)] = s } }
        return BoardSnapshot(size: size, grid: grid, stones: stones)
    }
    // A position, never fabricated move history. Reuses the existing app's SGF writer.
    func positionSGF(labels: [Int: Occupancy] = [:]) -> String? {
        guard !lightingBlocked else { return nil }
        let states = readings.enumerated().map { labels[$0.offset] ?? $0.element.occupancy }
        guard !states.contains(.uncertain) else { return nil }
        var props = ["GM": ["1"], "FF": ["4"], "CA": ["UTF-8"], "SZ": [String(size)],
                     "AP": ["PhysicalGo:0.7"], "C": ["Camera experiment: board position only; not a recorded game. Verify against the physical board."]]
        for occupancy in [Occupancy.black, .white] {
            let points = readings.enumerated().filter { states[$0.offset] == occupancy }.map { SGFCoordinates.toSGF(x: $0.element.col, y: $0.element.row) }
            if !points.isEmpty { props[occupancy == .black ? "AB" : "AW"] = points }
        }
        return SGFWriter.serialize(SGFTree(branches: [.init(sequence: [SGFNode(props: props)])]))
    }
}

enum BoardDetector {
    private struct Sample {
        let current: Double; let reference: Double
        let currentColor: BoardChroma?; let referenceColor: BoardChroma?
    }
    private static func quantile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[min(sorted.count-1, Int(Double(sorted.count-1)*fraction))]
    }
    private static func colorCorrection(_ values:[BoardChroma], minimum:Int)->BoardChroma? {
        guard values.count >= minimum else { return nil }
        let median = BoardChroma(red:quantile(values.map(\.red),0.5),green:quantile(values.map(\.green),0.5))
        guard quantile(values.map { ($0-median).magnitude },0.8) < 0.025 else { return nil }
        return median
    }
    private static func boardColorCorrection(_ gaps: [BoardChroma?], side: Int) -> BoardChroma? {
        let colors = gaps.compactMap { $0 }
        if let uniform = colorCorrection(colors, minimum: 20) { return uniform }
        // On a crowded board some cell centers fall on stones. Retain a small
        // wood-color correction only when a tighter majority agrees across the board.
        guard colors.count >= 48 else { return nil }
        let center = BoardChroma(red:quantile(colors.map(\.red),0.5), green:quantile(colors.map(\.green),0.5))
        guard center.magnitude < 0.025 else { return nil }
        var matches = [Int](repeating:0,count:4)
        for (index,color) in gaps.enumerated() {
            guard let color, (color-center).magnitude < 0.015 else { continue }
            let quadrant = (index / side < side / 2 ? 0 : 2) + (index % side < side / 2 ? 0 : 1)
            matches[quadrant] += 1
        }
        guard matches.min()! >= 4, matches.reduce(0,+)*5 >= colors.count*3 else { return nil }
        return center
    }
    private static func coveredGrid(frame:GrayFrame,reference:GrayFrame,calibration:BoardCalibration,referenceCalibration:BoardCalibration,
                                    col:Double,row:Double,woodLevel:Double,correction:Double)->Bool? {
        var found = 0, covered = 0
        // Locate actual reference ink near each predicted rail, allowing small lens
        // and calibration errors. Judge coverage on raw pixels, never the cyan overlay.
        for vertical in [false,true] { for along in [-0.24,-0.12,0.12,0.24] {
            var ink: (ImagePoint,Double)?
            for across in [-0.08,-0.04,0,0.04,0.08] {
                let point = calibration.point(col:(vertical ? col.rounded()+across : col+along),row:(vertical ? row+along : row.rounded()+across))
                let referencePoint=referenceCalibration.point(col:(vertical ? col.rounded()+across : col+along),row:(vertical ? row+along : row.rounded()+across))
                if let base = reference.patchMean(referencePoint), ink == nil || base < ink!.1 { ink = (point,base) }
            }
            guard let (point,base) = ink, woodLevel-base > 0.08,
                  let current = frame.patchMean(point) else { continue }
            found += 1
            if current-correction-base > 0.08 && current-correction > woodLevel-0.05 { covered += 1 }
        } }
        guard found >= 3 else { return nil } // No reliable printed-line evidence here.
        return Double(covered)/Double(found) >= 0.6
    }

    /// Positive evidence for shaded wood: both printed rails survive and the
    /// surrounding wood retains its color/texture under a modest lighting shift.
    /// This cannot resolve disputed ownership merely because another stone exists.
    private struct ExposedWood { let confidence:Double; let lighting:Double }

    /// Compare both printed rails inside a possible stone body with the empty
    /// reference. Local contrast survives shading. Positive line survival can
    /// contradict a stone; positive loss can contradict empty. Neither result
    /// alone assigns a stone color or a new empty label.
    private static func gridCrossEvidence(frame:GrayFrame,reference:GrayFrame,
                                           calibration:BoardCalibration,referenceCalibration:BoardCalibration,
                                           col:Double,row:Double)->(survives:Bool,covered:Bool) {
        var found=[0,0],matched=[0,0],missing=[0,0]
        for axis in 0..<2 { for along in [-0.24,-0.12,0.12,0.24] {
            let vertical=axis==1,c=col+(vertical ? 0:along),r=row+(vertical ? along:0)
            guard c>=0,r>=0,c<=Double(calibration.size-1),r<=Double(calibration.size-1) else {continue}
            func contrast(_ image:GrayFrame,_ grid:BoardCalibration,_ offset:Double)->Double? {
                let x=c+(vertical ? offset:0),y=r+(vertical ? 0:offset)
                guard let ink=image.patchMean(grid.point(col:x,row:y)),
                      let a=image.patchMean(grid.point(col:x+(vertical ? -0.14:0),row:y+(vertical ? 0:-0.14))),
                      let b=image.patchMean(grid.point(col:x+(vertical ? 0.14:0),row:y+(vertical ? 0:0.14))) else {return nil}
                let beside=min(a,b)
                return (beside-ink)/max(0.10,beside)
            }
            let probes=[-0.08,-0.06,-0.04,-0.02,0,0.02,0.04,0.06,0.08].compactMap { offset -> (Double,Double)? in
                contrast(reference,referenceCalibration,offset).map{(offset,$0)}
            }
            guard let best=probes.max(by:{$0.1<$1.1}),best.1>0.07 else {continue}
            found[axis] += 1
            let live=[-0.04,-0.02,0,0.02,0.04].compactMap{contrast(frame,calibration,best.0+$0)}.max() ?? 0
            if live>0.07 && live>=best.1*0.55 && live<=best.1*1.8 {matched[axis] += 1}
            if live<0.035 && live<best.1*0.35 {missing[axis] += 1}
        } }
        // At the board edge only the inward half of one rail is printed.
        let enough=found.allSatisfy{$0>=2}
        return (enough && (0..<2).allSatisfy{Double(matched[$0])/Double(found[$0])>=0.75},
                enough && (0..<2).allSatisfy{Double(missing[$0])/Double(found[$0])>=0.75})
    }
    private static func shadedEmptyEvidence(frame:GrayFrame,reference:GrayFrame,calibration:BoardCalibration,
                                            referenceCalibration:BoardCalibration,col:Double,row:Double,
                                            correction:Double,colorShift:BoardChroma?,shadowNeighbors:[StoneFootprint]=[])->ExposedWood? {
        func coveredByNeighbor(_ c:Double,_ r:Double)->Bool {
            shadowNeighbors.contains{$0.contains(ImagePoint(x:c,y:r),padding:0.04)}
        }
        var samples=[Sample]()
        for dy in -4...4 { for dx in -4...4 where dx != 0 && dy != 0 && dx*dx+dy*dy <= 16 {
            let c=col+Double(dx)*0.075,r=row+Double(dy)*0.075
            guard !coveredByNeighbor(c,r) else {continue}
            let p=calibration.point(col:c,row:r),q=referenceCalibration.point(col:c,row:r)
            if let current=frame.patchMean(p),let base=reference.patchMean(q) {
                samples.append(Sample(current:current,reference:base,currentColor:frame.patchColor(p),referenceColor:reference.patchColor(q)))
            }
        } }
        let woodLevel=quantile(samples.map(\.reference),0.75)
        let wood=samples.filter{$0.reference>=woodLevel-0.08}
        guard wood.count>=16,let colorShift else { return nil }
        let changes=wood.map{$0.current-$0.reference-correction}
        let lighting=quantile(changes,0.5)
        guard abs(lighting)<0.16 else { return nil }
        let matching=zip(wood,changes).filter { sample,delta in
            guard let current=sample.currentColor,let base=sample.referenceColor else { return false }
            return abs(delta-lighting)<0.035 && (current-base-colorShift).magnitude<0.025
        }.count
        let woodAgreement=Double(matching)/Double(wood.count)
        // Allow a minority of patches to be affected by an adjacent stone;
        // both surviving rails below must independently confirm the empty cross.
        // A neighboring stone can cast a brightness gradient across exposed wood.
        // Require nine out of ten exposed samples to retain wood color for this
        // alternate path, plus the original printed rails in relative contrast.
        // It is enabled only beside independently fitted neighboring black stones.
        let shadowMatches=wood.filter { sample in
            guard let current=sample.currentColor,let base=sample.referenceColor else {return false}
            let level=sample.current-correction
            let expected=base+colorShift
            // A stone can block one of several light sources, making exposed
            // wood darker and warmer. Permit that change only in darker patches
            // that retain the wood hue and saturation; a pale stone loses that
            // tint. Both reference rails must still survive independently below.
            let dot=current.red*expected.red+current.green*expected.green+current.blue*expected.blue
            let coloredShadow = level<=sample.reference-0.03 && expected.magnitude>=0.04
                && current.magnitude>=expected.magnitude*0.90 && current.magnitude<=expected.magnitude*1.80
                && dot>=current.magnitude*expected.magnitude*0.95
            return level>=sample.reference*0.55 && level<=sample.reference+0.07
                && ((current-expected).magnitude<0.030 || coloredShadow)
        }.count
        let shadowAgreement=Double(shadowMatches)/Double(wood.count)
        guard woodAgreement>=0.75 || (!shadowNeighbors.isEmpty && shadowAgreement>=0.90) else {return nil}
        var found=[0,0],matched=[0,0],shadowFound=[0,0],shadowMatched=[0,0]
        for axis in 0..<2 { for along in [-0.24,-0.12,0.12,0.24] {
            let vertical=axis==1,c=col+(vertical ? 0 : along),r=row+(vertical ? along : 0)
            guard c>=0,r>=0,c<=Double(calibration.size-1),r<=Double(calibration.size-1) else { continue }
            func contrast(_ image:GrayFrame,_ grid:BoardCalibration,_ offset:Double,relative:Bool=false)->Double? {
                let x=c+(vertical ? offset : 0),y=r+(vertical ? 0 : offset)
                guard let ink=image.patchMean(grid.point(col:x,row:y)),
                      let a=image.patchMean(grid.point(col:x+(vertical ? -0.14 : 0),row:y+(vertical ? 0 : -0.14))),
                      let b=image.patchMean(grid.point(col:x+(vertical ? 0.14 : 0),row:y+(vertical ? 0 : 0.14))) else { return nil }
                let wood=min(a,b)
                return relative ? (wood-ink)/max(0.10,wood) : wood-ink
            }
            // Normalize ink contrast by the wood immediately beside that rail.
            // Multiplicative shading should not erase a still-visible grid line.
            let relativeProbes=(shadowNeighbors.isEmpty ? [] : [-0.08,-0.06,-0.04,-0.02,0,0.02,0.04,0.06,0.08]).compactMap { offset -> (Double,Double)? in
                contrast(reference,referenceCalibration,offset,relative:true).map{(offset,$0)}
            }
            if let best=relativeProbes.max(by:{$0.1<$1.1}),best.1>0.07 {
                shadowFound[axis] += 1
                let live=[-0.04,-0.02,0,0.02,0.04].compactMap{contrast(frame,calibration,best.0+$0,relative:true)}.max() ?? 0
                if live>0.07 && live>=best.1*0.55 && live<=best.1*1.8 {shadowMatched[axis] += 1}
            }
            let probes=[-0.08,-0.04,0,0.04,0.08].compactMap { offset -> (Double,Double)? in
                contrast(reference,referenceCalibration,offset).map{(offset,$0)}
            }
            guard let best=probes.max(by:{$0.1<$1.1}),best.1>0.035 else { continue }
            found[axis] += 1
            let live=[-0.04,0,0.04].compactMap{contrast(frame,calibration,best.0+$0)}.max() ?? 0
            if live>0.035 && live>=best.1*0.55 && live<=best.1*1.8 { matched[axis] += 1 }
        } }
        if found.allSatisfy({$0>=2}),woodAgreement>=0.75 {
            let railAgreement=(0..<2).map{Double(matched[$0])/Double(found[$0])}
            if railAgreement.allSatisfy({$0>=0.75}) {
                return ExposedWood(confidence:min(woodAgreement,railAgreement.min()!),lighting:lighting+correction)
            }
        }
        guard !shadowNeighbors.isEmpty,shadowAgreement>=0.90,shadowFound.allSatisfy({$0>=3}) else {return nil}
        let shadowRails=(0..<2).map{Double(shadowMatched[$0])/Double(shadowFound[$0])}
        guard shadowRails.allSatisfy({$0>=0.75}) else {return nil}
        return ExposedWood(confidence:min(shadowAgreement,shadowRails.min()!),lighting:lighting+correction)
    }

    static func detect(frame: GrayFrame, reference: GrayFrame, calibration: BoardCalibration, threshold: Double, referenceCalibration: BoardCalibration? = nil, adaptLighting: Bool = true) -> BoardObservation? {
        guard frame.width == reference.width, frame.height == reference.height else { return nil }
        let referenceCalibration=referenceCalibration ?? calibration
        guard referenceCalibration.size==calibration.size else { return nil }
        let threshold = max(0.04, min(0.5, threshold))
        // Estimate modest uniform exposure drift from the wood between intersections.
        // Sampling cell centers keeps a crowded board's stones out of this estimate.
        let gapSide = calibration.size-1
        var gapDeltas = [Double](), woodGains = [Double]()
        var lightingSamples=[LightingCompensation.Sample]()
        var gaps = [Double?](repeating:nil,count:gapSide*gapSide)
        var gapColors = [BoardChroma?](repeating:nil,count:gapSide*gapSide)
        for row in 0..<gapSide { for col in 0..<gapSide {
            let point = calibration.point(col: Double(col)+0.5, row: Double(row)+0.5)
            let basePoint=referenceCalibration.point(col:Double(col)+0.5,row:Double(row)+0.5)
            if let current = frame.patchMean(point), let base = reference.patchMean(basePoint) {
                gaps[row*gapSide+col] = current-base
                gapDeltas.append(current-base)
                lightingSamples.append(.init(point:point,current:current,reference:base))
                if current>0.06, base>0.06, current<0.95, base<0.95 { woodGains.append(base/current) }
            }
            if let current = frame.patchColor(point), let base = reference.patchColor(basePoint) {
                gapColors[row*gapSide+col] = current-base
            }
        } }
        let exposureDelta = quantile(gapDeltas, 0.5)
        let exposureSpread = quantile(gapDeltas.map { abs($0-exposureDelta) }, 0.8)
        let uniformExposure = gapDeltas.count >= 20 && exposureSpread < 0.04
        // A large change can also be uneven when only some room lights go out.
        // Require a consistent direction across all four regions of exposed wood.
        var shifted = [Int](repeating:0,count:4), totals = shifted
        for (i, delta) in gaps.enumerated() {
            guard let delta else { continue }
            let region = (i/gapSide < gapSide/2 ? 0 : 2) + (i%gapSide < gapSide/2 ? 0 : 1)
            totals[region] += 1
            if exposureDelta < 0 ? delta < -0.12 : delta > 0.12 { shifted[region] += 1 }
        }
        let widespreadShift = abs(exposureDelta) > 0.14 && totals.indices.allSatisfy {
            totals[$0] >= 4 && shifted[$0]*4 >= totals[$0]*3
        }
        let regionalShift=gapDeltas.filter {abs($0)>0.10}.count*2>gapDeltas.count
        if widespreadShift || (uniformExposure && abs(exposureDelta) > 0.08) || regionalShift {
            var current = BoardAppearanceDetector.detect(frame:frame,calibration:calibration,threshold:threshold,changedLighting:true)
            let empty = current.readings.filter { $0.occupancy == .empty }.count
            let uncertain = current.readings.filter { $0.occupancy == .uncertain }.count
            // Local empties require both wood and visible printed rails. If those
            // landmarks disappear too, withhold this frame from play and review.
            current.lightingBlocked = empty*4 < current.readings.count || uncertain*4 > current.readings.count
            current.notice = current.lightingBlocked
                ? "The lighting differs from the saved reference and the grid is hard to read. Restore more light to continue."
                : "Lighting differs from the saved reference. Reading stones from the current board."
            current.lightingAdjusted = !current.lightingBlocked
            // Spatial exposure correction handles a window or room light changing
            // one side more than the other. Independent live grid/stone evidence
            // must agree before the corrected comparison can drive play.
            if adaptLighting && !current.lightingBlocked,
               let field=LightingCompensation.fit(lightingSamples,calibration:calibration),
               var matched=detect(frame:frame.adjustedLuminance(field),reference:reference,calibration:calibration,
                                  threshold:threshold,referenceCalibration:referenceCalibration,adaptLighting:false),
               matched.notice == nil {
                let contradictions=zip(current.readings,matched.readings).filter {a,b in
                    a.occupancy != .uncertain && b.occupancy != .uncertain && a.occupancy != b.occupancy
                }.count
                if contradictions<=max(1,calibration.size/6),matched.readings.filter({$0.occupancy == .uncertain}).count<=uncertain {
                    matched.notice="Lighting adjusted automatically across the board."
                    matched.lightingAdjusted=true
                    matched.lightingField=field
                    return matched
                }
            }
            // Keep the reference-backed geometry when the wood samples agree
            // on one gain and independent visible grid crosses support the result.
            if adaptLighting && !current.lightingBlocked && woodGains.count >= gapSide*gapSide/2 {
                let gain=quantile(woodGains,0.5)
                if (0.45...2.8).contains(gain), quantile(woodGains.map { abs($0/gain-1) },0.8)<0.12,
                   var matched=detect(frame:frame.scaledLuminance(by:gain),reference:reference,calibration:calibration,
                                      threshold:threshold,referenceCalibration:referenceCalibration,adaptLighting:false),
                   matched.notice == nil {
                    let contradictions=zip(current.readings,matched.readings).filter { a,b in
                        a.occupancy != .uncertain && b.occupancy != .uncertain && a.occupancy != b.occupancy
                    }.count
                    if contradictions <= max(1,calibration.size/6),
                       matched.readings.filter({$0.occupancy == .uncertain}).count <= uncertain {
                        matched.notice="Lighting changed. The live view is adjusted to the saved reference."
                        matched.lightingAdjusted=true
                        return matched
                    }
                }
            }
            return current
        }
        let globalCorrection = uniformExposure ? exposureDelta : 0
        let globalColorCorrection = boardColorCorrection(gapColors,side:gapSide)

        // A brightness difference alone cannot identify a white stone. First
        // find exposed wood by its retained color/texture AND both printed rails.
        // These independent landmarks also validate larger local lighting changes;
        // cell-center samples alone can be contaminated by shadows or stones.
        var exposedWood=[ExposedWood?](repeating:nil,count:calibration.size*calibration.size)
        for row in 0..<calibration.size { for col in 0..<calibration.size {
            var colors=[BoardChroma]()
            for r in max(0,row-2)..<min(gapSide,row+2) { for c in max(0,col-2)..<min(gapSide,col+2) {
                if let color=gapColors[r*gapSide+c] { colors.append(color) }
            } }
            exposedWood[row*calibration.size+col]=shadedEmptyEvidence(frame:frame,reference:reference,
                calibration:calibration,referenceCalibration:referenceCalibration,col:Double(col),row:Double(row),
                correction:globalCorrection,colorShift:colorCorrection(colors,minimum:4) ?? globalColorCorrection)
        } }

        var readings = [IntersectionReading]()
        var centers = [ImagePoint]() // Sample centers in grid coordinates for ownership checks.
        var geometryBlocked=Set<Int>()
        var liveWood=[Int:Double]()
        var independentAppearance:BoardObservation?
        for row in 0..<calibration.size { for col in 0..<calibration.size {
            // Estimate illumination from nearby cell centers, not from the stone.
            // A robust neighborhood median tolerates a few shadows/occluded gaps.
            var nearby = [Double]()
            var nearbyColors = [BoardChroma]()
            for r in max(0,row-2)..<min(gapSide,row+2) { for c in max(0,col-2)..<min(gapSide,col+2) {
                if let change = gaps[r*gapSide+c] { nearby.append(change) }
                if let change = gapColors[r*gapSide+c] { nearbyColors.append(change) }
            } }
            let localChange = quantile(nearby,0.5)
            let localSpread = quantile(nearby.map { abs($0-localChange) },0.8)
            let localReliable = nearby.count >= 4 && localSpread < 0.04
            var verifiedLighting=[Double]()
            for r in max(0,row-2)...min(calibration.size-1,row+2) { for c in max(0,col-2)...min(calibration.size-1,col+2) {
                if let wood=exposedWood[r*calibration.size+c] { verifiedLighting.append(wood.lighting) }
            } }
            let verifiedMedian=quantile(verifiedLighting,0.5)
            let verifiedReliable=verifiedLighting.count>=4 && quantile(verifiedLighting.map{abs($0-verifiedMedian)},0.8)<0.04
            let excessiveChange = localReliable && abs(localChange)>0.08 && !verifiedReliable
            let correction = excessiveChange ? globalCorrection
                : verifiedReliable ? verifiedMedian : localReliable ? localChange : globalCorrection
            let colorShift = colorCorrection(nearbyColors,minimum:4) ?? globalColorCorrection
            var candidate = classify(frame:frame,reference:reference,calibration:calibration,referenceCalibration:referenceCalibration,
                col:Double(col),row:Double(row),threshold:threshold,correction:correction,colorShift:colorShift)
            var center = ImagePoint(x:Double(col),y:Double(row))
            var independentlyDark=false
            if excessiveChange,candidate.occupancy == .black,candidate.confidence>=0.95,candidate.delta < -0.30 {
                if independentAppearance==nil {independentAppearance=BoardAppearanceDetector.detect(frame:frame,calibration:calibration,threshold:threshold)}
                let live=independentAppearance!.readings[row*calibration.size+col]
                let cross=BoardAppearanceDetector.gridEvidence(frame:frame,calibration:calibration,col:Double(col),row:Double(row),relativeContrast:true)
                independentlyDark=live.occupancy == .black && live.confidence>=0.95 && cross.horizontal<0.25 && cross.vertical<0.25
            }
            if excessiveChange && !independentlyDark { candidate.occupancy = .uncertain; candidate.confidence = 0; geometryBlocked.insert(row*calibration.size+col) }
            else if candidate.occupancy == .uncertain || candidate.occupancy == .empty, let hint = candidate.stoneHint {
                // Stones need not be centered perfectly on the printed intersection.
                // Partial white/color evidence can challenge an apparently
                // unchanged center. Every offset still needs 80% agreement, valid
                // reference wood, and unique ownership below.
                var bestScore = -Double.infinity
                for rowStep in -3...3 { for colStep in -3...3 where rowStep != 0 || colStep != 0 {
                    let dr=Double(rowStep)/10, dc=Double(colStep)/10
                    let shifted = classify(frame:frame,reference:reference,calibration:calibration,referenceCalibration:referenceCalibration,
                        col:Double(col)+dc,row:Double(row)+dr,threshold:threshold,correction:correction,colorShift:colorShift)
                    let score = shifted.confidence-0.15*hypot(dc,dr)
                    if shifted.occupancy == hint && score > bestScore {
                        candidate = shifted
                        center = ImagePoint(x:Double(col)+dc,y:Double(row)+dr)
                        bestScore = score
                    }
                } }
            }
            // Retained wood and both surviving rails contradict a stone of
            // either color, even when dark-pixel votes alone are unanimous.
            // One grain line on a stone is insufficient.
            if candidate.occupancy == .uncertain || candidate.occupancy == .white || candidate.occupancy == .black,
               let empty=exposedWood[row*calibration.size+col] {
                candidate.occupancy = .empty; candidate.confidence = empty.confidence
                geometryBlocked.remove(row*calibration.size+col)
            }
            if candidate.occupancy != .empty,
               let confidence=BoardAppearanceDetector.exposedWoodConfidence(frame:frame,calibration:calibration,col:col,row:row,bodyCenter:center) {
                candidate.occupancy = .empty;candidate.confidence=confidence
                liveWood[row*calibration.size+col]=confidence
                geometryBlocked.insert(row*calibration.size+col)
            }
            if candidate.occupancy.stone != nil,
               gridCrossEvidence(frame:frame,reference:reference,calibration:calibration,
                   referenceCalibration:referenceCalibration,col:Double(col),row:Double(row)).survives {
                candidate.occupancy = .uncertain; candidate.confidence = 0
                // Neither geometry nor a neighboring stone can override the
                // contradictory printed cross in this frame.
                geometryBlocked.insert(row*calibration.size+col)
            }
            readings.append(.init(row:row,col:col,occupancy:candidate.occupancy,confidence:candidate.confidence,delta:candidate.delta))
            centers.append(center)
        } }
        // Neighboring intersections must not claim the same displaced stone. Keep
        // clearly stronger/closer ownership; ambiguous shared evidence stays uncertain.
        let proposals = readings
        var disputed = Set<Int>()
        for i in proposals.indices where proposals[i].occupancy.stone != nil {
            let a = proposals[i]
            for row in max(0,a.row-1)...min(calibration.size-1,a.row+1) {
                for col in max(0,a.col-1)...min(calibration.size-1,a.col+1) {
                    let j = row*calibration.size+col
                    guard j > i, proposals[j].occupancy == a.occupancy else { continue }
                    let b = proposals[j]
                    guard hypot(centers[i].x-centers[j].x,centers[i].y-centers[j].y)<0.6 else { continue }
                    let offsetA = hypot(centers[i].x-Double(a.col),centers[i].y-Double(a.row))
                    let offsetB = hypot(centers[j].x-Double(b.col),centers[j].y-Double(b.row))
                    if a.confidence > b.confidence+0.1 && offsetA+0.12 < offsetB { disputed.insert(j) }
                    else if b.confidence > a.confidence+0.1 && offsetB+0.12 < offsetA { disputed.insert(i) }
                    else { disputed.insert(i); disputed.insert(j) }
                }
            }
        }
        for index in disputed {
            let reading = readings[index]
            readings[index] = .init(row:reading.row,col:reading.col,occupancy:.uncertain,confidence:0,delta:reading.delta)
        }
        let geometry=StoneGeometry.refine(frame:frame,reference:reference,calibration:calibration,
            referenceCalibration:referenceCalibration,readings:readings,blocked:geometryBlocked.union(disputed),
            correction:globalCorrection,colorShift:globalColorCorrection,samplingCenters:centers)
        // An independently fitted nearby black stone can shade bare wood and
        // overlap the outer sample patches. Mask its observed body, then require
        // retained wood color and both printed rails. Geometry alone cannot mark
        // a point empty, and uncertain/rejected stone hypotheses cannot seed this.
        var resolved=geometry.readings
        for (index,reading) in geometry.readings.enumerated() where reading.occupancy == .uncertain
            && !geometryBlocked.contains(index) && !disputed.contains(index) {
            let neighbors=geometry.footprints.filter { shape in
                let stone=geometry.readings[shape.row*calibration.size+shape.col]
                // Touching stones can lose part of their fitted outline. Strong
                // black-pixel evidence can support a slightly weaker outline for
                // shadow testing only; exposed wood and both rails still decide.
                let trustedShape=shape.quality>=0.85 || (shape.quality>=0.80 && stone.confidence>=0.90)
                return trustedShape && abs(shape.row-reading.row)<=1 && abs(shape.col-reading.col)<=1
                    && stone.occupancy == .black
            }
            guard !neighbors.isEmpty else {continue}
            var colors=[BoardChroma]()
            for r in max(0,reading.row-2)..<min(gapSide,reading.row+2) {
                for c in max(0,reading.col-2)..<min(gapSide,reading.col+2) {
                    if let color=gapColors[r*gapSide+c] {colors.append(color)}
                }
            }
            if let wood=shadedEmptyEvidence(frame:frame,reference:reference,calibration:calibration,
                referenceCalibration:referenceCalibration,col:Double(reading.col),row:Double(reading.row),
                correction:globalCorrection,colorShift:colorCorrection(colors,minimum:4) ?? globalColorCorrection,
                shadowNeighbors:neighbors) {
                resolved[index]=IntersectionReading(row:reading.row,col:reading.col,
                    occupancy:.empty,confidence:wood.confidence,delta:reading.delta)
            }
        }
        // Missing expected ink contradicts "empty", even when the body has
        // the same brightness as the reference wood. Color remains unassigned
        // unless an independent bounded stone outline supports it.
        var recoveredShapes=[StoneFootprint]()
        for (index,reading) in resolved.enumerated() where reading.occupancy == .empty ||
            (reading.occupancy == .uncertain && !geometryBlocked.contains(index) && !disputed.contains(index)) {
            guard gridCrossEvidence(frame:frame,reference:reference,calibration:calibration,
                referenceCalibration:referenceCalibration,col:Double(reading.col),row:Double(reading.row)).covered else {continue}
            let recovered=StoneGeometry.coveredStone(reading,frame:frame,reference:reference,
                calibration:calibration,referenceCalibration:referenceCalibration,correction:globalCorrection,
                colorShift:globalColorCorrection,neighbors:geometry.footprints+recoveredShapes,
                neighborReadings:geometry.readings)
            resolved[index]=IntersectionReading(row:reading.row,col:reading.col,
                occupancy:recovered?.0 ?? .uncertain,confidence:recovered?.1.quality ?? 0,delta:reading.delta)
            if let recovered {recoveredShapes.append(recovered.1)}
        }
        let outlined=Set((geometry.footprints+geometry.placementFits+recoveredShapes).filter{$0.quality>=0.80}.map{$0.row*calibration.size+$0.col})
        for (index,reading) in resolved.enumerated() where reading.occupancy.stone != nil && !outlined.contains(index) {
            if (reading.occupancy == .white && !BoardAppearanceDetector.boundedWhite(frame:frame,calibration:calibration,col:Double(reading.col),row:Double(reading.row))) ||
                retainsWoodTint(frame:frame,reference:reference,calibration:calibration,referenceCalibration:referenceCalibration,
                col:reading.col,row:reading.row) {
                resolved[index] = .init(row:reading.row,col:reading.col,occupancy:.uncertain,confidence:0,delta:reading.delta)
            }
        }
        // A missing/misaligned rail in the old reference cannot overturn two
        // rails and exposed wood independently observed in this live image.
        for (index,confidence) in liveWood {
            let reading=resolved[index]
            resolved[index] = .init(row:reading.row,col:reading.col,occupancy:.empty,confidence:confidence,delta:reading.delta)
        }
        let validShape:(StoneFootprint)->Bool = {liveWood[$0.row*calibration.size+$0.col] == nil}
        return BoardObservation(readings: resolved, size: calibration.size,
            footprints:(geometry.footprints+recoveredShapes).filter(validShape),placementFits:geometry.placementFits.filter(validShape))
    }

    /// Bright or shaded wood is not a stone merely because its brightness
    /// differs from the old reference. Without a bounded outline, retained hue and
    /// saturation contradict that hypothesis. Withhold the reading; this does
    /// not declare an intersection empty or use game history as a visual label.
    private static func retainsWoodTint(frame:GrayFrame,reference:GrayFrame,calibration:BoardCalibration,
                                        referenceCalibration:BoardCalibration,col:Int,row:Int)->Bool {
        var sampled=0,wood=0
        for dy in -4...4 {for dx in -4...4 where dx != 0 && dy != 0 && dx*dx+dy*dy<=16 {
            let c=Double(col)+Double(dx)*0.075,r=Double(row)+Double(dy)*0.075
            guard let current=frame.patchColor(calibration.point(col:c,row:r)),
                  let original=reference.patchColor(referenceCalibration.point(col:c,row:r)) else {continue}
            let expected=original
            sampled+=1
            let dot=current.red*expected.red+current.green*expected.green+current.blue*expected.blue
            if current.magnitude>=0.045,expected.magnitude>=0.035,
               current.magnitude>=expected.magnitude*0.65,
               dot>=current.magnitude*expected.magnitude*0.94 {wood+=1}
        }}
        return sampled>=20 && Double(wood)/Double(sampled)>=0.75
    }

    private struct Candidate {
        var occupancy: Occupancy
        var confidence: Double
        let delta: Double
        let stoneHint: Occupancy?
    }
    private static func classify(frame:GrayFrame,reference:GrayFrame,calibration:BoardCalibration,referenceCalibration:BoardCalibration,
                                 col:Double,row:Double,threshold:Double,correction:Double,colorShift:BoardChroma?) -> Candidate {
        var samples = [Sample]()
        // Avoid the central cross, and filter reference ink where alignment is imperfect.
        for dy in -4...4 { for dx in -4...4 where dx != 0 && dy != 0 && dx*dx+dy*dy <= 16 {
            let p = calibration.point(col:col+Double(dx)*0.075,row:row+Double(dy)*0.075)
            let basePoint=referenceCalibration.point(col:col+Double(dx)*0.075,row:row+Double(dy)*0.075)
            if let current = frame.patchMean(p), let base = reference.patchMean(basePoint) {
                samples.append(Sample(current:current,reference:base,currentColor:frame.patchColor(p),referenceColor:reference.patchColor(basePoint)))
            }
        } }
        let woodLevel = quantile(samples.map(\.reference),0.75)
        let wood = samples.filter { $0.reference >= woodLevel-0.08 }
        let deltas = wood.map { $0.current-$0.reference-correction }
        let delta = quantile(deltas,0.5)
        guard samples.count >= 20, wood.count >= 16 else {
            return Candidate(occupancy:.uncertain,confidence:0,delta:delta,stoneHint:nil)
        }
        let referenceLevel = quantile(wood.map(\.reference),0.5)+correction
        let whiteThreshold = max(0.045,min(threshold,(1-referenceLevel)*0.20))
        let dark = Double(deltas.filter { $0 < -threshold }.count)/Double(deltas.count)
        var lightVotes = 0, colorHintVotes = 0
        var checkedCoverage = false, gridCoverage: Bool?
        for (sample,change) in zip(wood,deltas) {
            var whiteColor = false
            if let shift = colorShift, let current = sample.currentColor, let base = sample.referenceColor {
                let expectedWood = base+shift
                // A white stone can match wood brightness while losing its yellow/red tint.
                // Correct white balance from nearby bare wood. Near-equal brightness
                // is allowed only when the reference ink is positively covered;
                // dark patches and shadows with surviving lines do not qualify.
                // A shaded white stone may be slightly darker than bare wood.
                // Allow that only with strong loss of wood chroma and covered
                // reference ink below; brightness similarity alone is not empty.
                whiteColor = change > -0.06 && expectedWood.magnitude-current.magnitude > 0.035
                    && current.magnitude < expectedWood.magnitude*0.65
                if whiteColor {
                    colorHintVotes += 1
                    if !checkedCoverage {
                        gridCoverage = coveredGrid(frame:frame,reference:reference,calibration:calibration,referenceCalibration:referenceCalibration,
                            col:col,row:row,woodLevel:referenceLevel-correction,correction:correction)
                        checkedCoverage = true
                    }
                    whiteColor = gridCoverage == true || (change > 0.015 && gridCoverage != false)
                }
            }
            if change > whiteThreshold || whiteColor { lightVotes += 1 }
        }
        let light = Double(lightVotes)/Double(deltas.count)
        let unchanged = Double(deltas.filter { abs($0) < min(threshold*0.55,whiteThreshold*0.8) }.count)/Double(deltas.count)
        // An offset stone may cover less than half the centered patch. Permit a
        // search from partial support only when the other color is largely absent;
        // promotion still requires 80% agreement at a nearby center and unique ownership.
        // Partial loss of the wood tint can seed a search even if the stone
        // covers too little of the intersection's cross. Acceptance still checks
        // reference ink beneath the displaced candidate, not just its color.
        let whiteHint = light >= 0.35 || Double(colorHintVotes)/Double(deltas.count) >= 0.25
        let hint: Occupancy? = dark >= 0.35 && light < 0.15 ? .black : (whiteHint && dark < 0.15 ? .white : nil)
        if dark >= 0.8 { return Candidate(occupancy:.black,confidence:dark,delta:delta,stoneHint:hint) }
        if light >= 0.8 { return Candidate(occupancy:.white,confidence:light,delta:delta,stoneHint:hint) }
        if unchanged >= 0.8 { return Candidate(occupancy:.empty,confidence:unchanged,delta:delta,stoneHint:hint) }
        return Candidate(occupancy:.uncertain,confidence:max(dark,light,unchanged),delta:delta,stoneHint:hint)
    }
}

struct ObservationStability {
    private var previous: [Occupancy] = []
    private(set) var matchingFrames = 0
    mutating func reset() { previous = []; matchingFrames = 0 }
    mutating func update(_ observation: BoardObservation) -> Bool {
        let signature = observation.signature
        if signature.contains(.uncertain) { reset(); return false }
        matchingFrames = signature == previous ? matchingFrames+1 : 1
        previous = signature
        return matchingFrames >= 5
    }
}
