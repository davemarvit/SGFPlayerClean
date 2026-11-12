import Foundation

/// Debounce actionable evidence independently at each intersection. Uncertainty
/// about an unchanged recorded stone is neither a contradiction nor a request
/// to move it. A displayed marker clears only after repeated agreement.
struct BoardAdjustmentMonitor {
    enum Kind:String,Equatable {case placement,capture,conflict,newMove}
    private struct Run {var kind:Kind;var first:Double;var last:Double;var frames:Int}
    private struct ClearRun {var first:Double;var last:Double;var frames:Int}
    private var pending:[Int:Run]=[:]
    private var clearing:[Int:ClearRun]=[:]
    private var lastTime:Double?
    private(set) var visible:[Int:Kind]=[:]
    static func evidence(readings:[Occupancy],base:[Occupancy],after:[Occupancy])->[Int:Kind] {
        guard readings.count==base.count,after.count==base.count else {return [:]}
        var result:[Int:Kind]=[:]
        for p in readings.indices {
            if readings[p] == .uncertain {
                // A retained new candidate can need a clearer view without
                // reopening any unchanged recorded identities.
                if base[p].stone != nil && after[p] == .empty {result[p] = .capture}
                else if base[p] != after[p] {result[p] = .newMove}
            } else if readings[p] != after[p] {
                result[p] = base[p].stone != nil && after[p] == .empty ? .capture:.conflict
            }
        }
        return result
    }
    mutating func resolve(_ points:Set<Int>) {
        for point in points {visible.removeValue(forKey:point);pending.removeValue(forKey:point);clearing.removeValue(forKey:point)}
    }
    mutating func update(issues:[Int:Kind],clear:Set<Int>,now:Double) {
        guard now.isFinite,lastTime.map({now>$0}) ?? true else {return}
        if let lastTime,now-lastTime>1 {pending=[:];clearing=[:]}
        lastTime=now
        for p in Array(pending.keys) where issues[p]==nil {pending.removeValue(forKey:p)}
        for (point,kind) in issues {
            clearing.removeValue(forKey:point)
            var run=pending[point] ?? Run(kind:kind,first:now,last:now,frames:0)
            if run.kind != kind || now-run.last>0.5 {run=Run(kind:kind,first:now,last:now,frames:0)}
            run.last=now;run.frames += 1;pending[point]=run
            if run.frames>=4 && now-run.first>=0.65 {visible[point]=kind}
        }
        for point in Array(visible.keys) {
            guard issues[point]==nil,clear.contains(point) else {clearing.removeValue(forKey:point);continue}
            var run=clearing[point] ?? ClearRun(first:now,last:now,frames:0)
            if now-run.last>0.5 {run=ClearRun(first:now,last:now,frames:0)}
            run.last=now;run.frames += 1;clearing[point]=run
            if run.frames>=5 && now-run.first>=0.8 {visible.removeValue(forKey:point);clearing.removeValue(forKey:point)}
        }
    }
}
