import Foundation

extension BoardObservation {
    /// A clock-only view of a single white body claimed by two intersections.
    /// Raw labels, SGF placement and capture validation keep their uncertainty.
    /// Both independent searches must fit the same bounded disk; a nearby
    /// already visible stone cannot lend its outline to this turn.
    var turnEvidenceObservation: BoardObservation {
        guard handObstructed == false,!lightingBlocked,manualPoints.isEmpty,
              size>0,readings.count==size*size else {return self}
        let evidence=centeringEvidence.filter { e in
            let s=e.shape,p=s.row*size+s.col
            return e.color == .white && (0..<size).contains(s.row) && (0..<size).contains(s.col) &&
                readings[p].occupancy == .uncertain && s.center.x.isFinite && s.center.y.isFinite &&
                s.quality.isFinite && s.quality>=0.94 && (0.36...0.52).contains(s.radiusCol) &&
                (0.33...0.56).contains(s.radiusRow) &&
                max(abs(s.center.x-Double(s.col)),abs(s.center.y-Double(s.row)))<=0.56+1e-9 &&
                s.contains(.init(x:Double(s.col),y:Double(s.row)),padding:0.16)
        }
        var result=self,used=Set<Int>()
        for e in evidence {
            let s=e.shape
            let group=evidence.filter {hypot($0.shape.center.x-s.center.x,$0.shape.center.y-s.center.y)<=0.08}
            let points=Set(group.map{$0.shape.row*size+$0.shape.col})
            guard points.count==2,points.isDisjoint(with:used),
                  !evidence.contains(where:{other in
                      points.contains(other.shape.row*size+other.shape.col) &&
                      hypot(other.shape.center.x-s.center.x,other.shape.center.y-s.center.y)>0.08
                  }),
                  !(footprints+placementFits).contains(where:{other in
                      other.quality>=0.78 && hypot((s.center.x-other.center.x)/(s.radiusCol+other.radiusCol),
                          (s.center.y-other.center.y)/(s.radiusRow+other.radiusRow))<0.90
                  }),
                  !readings.indices.contains(where:{p in readings[p].occupancy.stone != nil &&
                      s.contains(.init(x:Double(p%size),y:Double(p/size)),padding:0.16)}) else {continue}
            // The representative is only an index for one physical disk. Its
            // fitted outline retains both intersections as timing alternatives.
            let point=points.sorted {a,b in
                let da=hypot(s.center.x-Double(a%size),s.center.y-Double(a/size))
                let db=hypot(s.center.x-Double(b%size),s.center.y-Double(b/size))
                return da==db ? a<b:da<db
            }[0]
            let quality=group.map(\.shape.quality).min()!
            result.readings[point] = .init(row:point/size,col:point%size,occupancy:.white,
                confidence:quality,delta:readings[point].delta)
            result.footprints.append(.init(row:point/size,col:point%size,center:s.center,
                radiusCol:s.radiusCol,radiusRow:s.radiusRow,quality:quality))
            used.formUnion(points)
        }
        return result
    }

    /// Independent evidence that a white disk is present, not proof of its
    /// historical intersection. Keep the photometric score and all placement
    /// warnings unchanged. Black/shadow evidence retains its existing policy.
    var whiteTurnOutlineCenters: [Int: ImagePoint] {
        guard handObstructed == false,!lightingBlocked,manualPoints.isEmpty,
              size>0,readings.count==size*size else {return [:]}
        let shapes=footprints.filter {s in
            (0..<size).contains(s.row) && (0..<size).contains(s.col) &&
            s.center.x.isFinite && s.center.y.isFinite && s.quality.isFinite && s.quality>=0.98 &&
            (0.36...0.56).contains(s.radiusCol) && (0.33...0.60).contains(s.radiusRow) &&
            (0.75...1.30).contains(s.radiusRow/s.radiusCol) &&
            max(abs(s.center.x-Double(s.col)),abs(s.center.y-Double(s.row)))<=0.55
        }
        var result=[Int:ImagePoint]()
        for s in shapes {
            let point=s.row*size+s.col,reading=readings[point]
            guard reading.occupancy == .white,reading.confidence.isFinite,reading.confidence>=0.80,
                  s.contains(.init(x:Double(s.col),y:Double(s.row)),padding:0.12) else {continue}
            // Never let one outline establish two stones or steal a visible
            // neighbor's outline. Distinct touching stones remain eligible.
            let covered=readings.indices.filter {p in readings[p].occupancy.stone != nil &&
                s.contains(.init(x:Double(p%size),y:Double(p/size)),padding:0.12)}
            guard covered==[point],!footprints.contains(where:{other in
                other.row*size+other.col != point && other.quality>=0.86 &&
                hypot(s.center.x-other.center.x,s.center.y-other.center.y)<0.75
            }),shapes.filter({$0.row*size+$0.col==point}).allSatisfy({hypot($0.center.x-s.center.x,$0.center.y-s.center.y)<=0.08}) else {continue}
            result[point]=s.center
        }
        return result
    }
}
