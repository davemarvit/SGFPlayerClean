import Foundation

extension BoardObservation {
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
