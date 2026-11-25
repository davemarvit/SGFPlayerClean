import Foundation

/// Experimental work requests only. No occupancy, clearance or activation output.
enum ShadowScheduler {
    struct Cell {
        let light:[Double]
        let red:[Double]
        let green:[Double]
        var valid:Bool { light.count==25 && red.count==25 && green.count==25 &&
            (light+red+green).allSatisfy(\.isFinite) }
        var mean:Double { light.reduce(0,+)/Double(max(1,light.count)) }
    }
    struct Descriptor {let cells:[Cell];let scope:String}
    struct Constraints {
        var mandatory=Set<Int>()
        var geometryUnknown=false
        var handUnknown=false
        var visibilityUnknown=false
        var postDark=false
        var refreshDue=false
    }
    struct Result {
        let selected:Set<Int>
        let pixelChanged:Set<Int>
        let gain:Double
        let offset:Double
        let normalizationCount:Int
        let reasons:[String]
    }
    static func median(_ values:[Double])->Double {
        guard !values.isEmpty else {return 0}
        let sorted=values.sorted();return sorted[sorted.count/2]
    }
    static func halo(_ cells:Set<Int>,size:Int=19)->Set<Int> {
        var result=cells
        for i in cells {for r in max(0,i/size-1)...min(size-1,i/size+1) {
            for c in max(0,i%size-1)...min(size-1,i%size+1) {result.insert(r*size+c)}
        }}
        return result
    }
    static func compare(anchor:Descriptor,current:Descriptor,woodCandidates:Set<Int>,constraints:Constraints)->Result {
        let all=Set(0..<361)
        var reasons=[String]()
        if anchor.scope != current.scope {reasons.append("scope")}
        if constraints.geometryUnknown {reasons.append("geometry_unknown")}
        if constraints.handUnknown {reasons.append("hand_unknown")}
        if constraints.visibilityUnknown {reasons.append("visibility_unknown")}
        if constraints.postDark {reasons.append("post_dark")}
        if constraints.refreshDue {reasons.append("periodic_full")}
        guard anchor.cells.count==361,current.cells.count==361 else {
            return .init(selected:all,pixelChanged:all,gain:1,offset:0,normalizationCount:0,reasons:["invalid_layout"])
        }
        var pairs=woodCandidates.sorted().compactMap { i -> (Double,Double)? in
            guard all.contains(i),anchor.cells[i].valid,current.cells[i].valid else {return nil}
            let a=anchor.cells[i].mean,b=current.cells[i].mean
            return (0.08...0.95).contains(a) && (0.08...0.95).contains(b) ? (a,b):nil
        }
        var gain=1.0,offset=0.0
        for _ in 0..<3 where pairs.count>=24 {
            let a=pairs.map(\.0),b=pairs.map(\.1),am=a.reduce(0,+)/Double(a.count),bm=b.reduce(0,+)/Double(b.count)
            let variance=a.reduce(0){$0+pow($1-am,2)}
            if variance>0.0001 {
                gain=zip(a,b).reduce(0){$0+($1.0-am)*($1.1-bm)}/variance;offset=bm-gain*am
            } else {gain=1;offset=median(zip(a,b).map{$0.1-$0.0})}
            let residual=pairs.map{$0.1-gain*$0.0-offset}
            let center=median(residual),mad=median(residual.map{abs($0-center)})
            let limit:Double=max(4.0/255.0,3.0*mad)
            pairs=pairs.filter { pair in
                let expected:Double=gain*pair.0+offset
                return abs(pair.1-expected)<=limit
            }
        }
        if pairs.count<24 || !(0.65...1.5).contains(gain) || abs(offset)>40/255 {
            reasons.append("normalization_unresolved");gain=1;offset=0
        }
        var changed=Set<Int>(),unreadable=Set<Int>()
        for i in 0..<361 {
            let a=anchor.cells[i],b=current.cells[i]
            guard a.valid,b.valid else {unreadable.insert(i);continue}
            var count=0
            for j in 0..<25 {
                if abs((b.light[j]-offset)/gain-a.light[j])>6/255 ||
                    abs(b.red[j]-a.red[j])>0.018 || abs(b.green[j]-a.green[j])>0.018 {count += 1}
            }
            if count>=2 {changed.insert(i)}
            if b.light.filter({$0<0.03 || $0>0.98}).count>=13 {unreadable.insert(i)}
        }
        let selected=reasons.isEmpty ? halo(changed.union(unreadable).union(constraints.mandatory)):all
        return .init(selected:selected,pixelChanged:halo(changed),gain:gain,offset:offset,
                     normalizationCount:pairs.count,reasons:reasons)
    }
}
