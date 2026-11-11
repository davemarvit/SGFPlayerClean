import Foundation

extension BoardObservation {
    /// Locations covered by the same off-centre outline, not extra stones.
    func placementAlternatives(base:[Occupancy])->[Int:Set<Int>] {
        var result=[Int:Set<Int>]()
        for shape in footprints + placementFits {
            let point=shape.row*size+shape.col
            guard readings.indices.contains(point),base.count==readings.count,base[point] == .empty,
                  readings[point].occupancy.stone != nil,shape.quality>=0.86,
                  (assignmentOffsets(confirmedBoard:base)[point] ?? 0)>=0.30 else {continue}
            var choices:Set<Int>=[point]
            for row in max(0,shape.row-1)...min(size-1,shape.row+1) {
                for col in max(0,shape.col-1)...min(size-1,shape.col+1) {
                    let p=row*size+col
                    if base[p] == .empty && shape.contains(.init(x:Double(col),y:Double(row)),padding:0.16) {choices.insert(p)}
                }
            }
            if choices.count>1 {result[point,default:[]].formUnion(choices)}
        }
        return result
    }
}
