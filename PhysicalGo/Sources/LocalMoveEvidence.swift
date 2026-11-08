import Foundation

/// Bounded, run-length encoded evidence at each intersection. Uncertainty is a
/// gap, never an empty point. These sightings establish order, not acceptance.
struct LocalMoveEvidence {
    struct Run {
        let value: Occupancy
        var first: Double
        var last: Double
        var previous: Double?
        var established: Double?
        var count: Int
        mutating func append(_ time: Double) {
            previous=last; last=time; count += 1
            if established == nil && time-first>=0.15 { established=time }
        }
        mutating func trim(before cutoff: Double) {
            guard first<cutoff else { return }
            // Only the two newest times are known exactly. Do not credit an
            // estimated number of repetitions after the retention boundary.
            first=previous.map { $0>=cutoff ? $0 : last } ?? last
            count=first<last ? 2 : 1
            established=last-first>=0.15 ? last : nil
            if first==last { previous=nil }
        }
    }
    private struct Anchor {
        let color:Occupancy
        var first:Double
        var last:Double
        var count:Int
        var supported:Bool {count>=2 && last-first>=0.15}
    }
    // Raw sightings remain useful for later ordering when a stone becomes clear.
    // Only isolated, repeatable changes can block on a now-obscured candidate.
    private var anchors=[Int:Anchor]()
    static let lifetime=12.0
    static let maximumRunsPerPoint=64
    private(set) var points=[[Run]]()
    private(set) var expiredPoints=Set<Int>()
    private var lastTime: Double?
    var runCount:Int { points.reduce(0) { $0+$1.count } }
    var sampleCount:Int { points.reduce(0) { $0+$1.reduce(0) { $0+$1.count } } }
    mutating func reset() { points=[];expiredPoints=[];anchors=[:];lastTime=nil }

    mutating func observe(_ readings:[Occupancy],base:[Occupancy],now:Double) {
        guard lastTime.map({now>$0}) ?? true else { return }
        if points.count != readings.count { reset();points=Array(repeating:[],count:readings.count) }
        lastTime=now
        let cutoff=now-Self.lifetime
        let size=Int(Double(readings.count).squareRoot())
        // A hand can darken dozens of points while leaving a small island of
        // neighbors unchanged. Such a view is useful as raw evidence, but must
        // not promote an isolated patch into a durable, blocking move candidate.
        // Keep partially obscured views with a few real changes eligible: those
        // are how we protect an earlier stone when an opponent plays quickly.
        let additions=readings.indices.filter {readings[$0].stone != nil && readings[$0] != base[$0]}.count
        let canAnchor=additions<=8
        for i in readings.indices {
            if readings[i] == base[i] || (readings[i] != .uncertain && readings[i] != anchors[i]?.color) {
                anchors.removeValue(forKey:i)
            }
            if readings[i].stone != nil && readings[i] != base[i] {
                let row=i/size,col=i%size
                var neighbors=0,unchanged=0
                for dr in -1...1 {for dc in -1...1 where dr != 0 || dc != 0 {
                    guard (0..<size).contains(row+dr),(0..<size).contains(col+dc) else {continue}
                    let j=(row+dr)*size+col+dc;neighbors += 1
                    if readings[j] == base[j] {unchanged += 1}
                }}
                if canAnchor && neighbors>0 && Double(unchanged)/Double(neighbors)>=0.75 {
                    if var old=anchors[i],now-old.last<=1.5 {
                        old.count += 1;old.last=now;anchors[i]=old
                    } else {anchors[i]=Anchor(color:readings[i],first:now,last:now,count:1)}
                }
            }
            // Expiry protects an unresolved appearance, not every historical
            // color error at this coordinate. A later definite contradiction
            // ends that episode (as it does in established()). Otherwise an old
            // hand-shaped false black can permanently poison a future real move.
            func unresolved(_ run:Run)->Bool {
                guard run.value.stone != nil,run.value != base[i] else {return false}
                if readings[i] != .uncertain && readings[i] != run.value {return false}
                return !points[i].contains {$0.first>run.last && $0.value != .uncertain && $0.value != run.value}
            }
            let removed=points[i].filter { $0.last<cutoff }
            if removed.contains(where:unresolved) {expiredPoints.insert(i)}
            let trimmedUnresolved=points[i].contains {$0.first<cutoff && $0.last>=cutoff && unresolved($0)}
            if trimmedUnresolved {expiredPoints.insert(i)}
            points[i].removeAll { $0.last<cutoff }
            for j in points[i].indices {points[i][j].trim(before:cutoff)}
            if readings[i] == base[i] {expiredPoints.remove(i)}
            if let last=points[i].last, last.value==readings[i] {
                points[i][points[i].count-1].append(now)
            } else {
                points[i].append(Run(value:readings[i],first:now,last:now,count:1))
            }
            if points[i].count>Self.maximumRunsPerPoint {
                let excess=points[i].count-Self.maximumRunsPerPoint
                if points[i].prefix(excess).contains(where:unresolved) {expiredPoints.insert(i)}
                points[i].removeFirst(excess)
            }
        }
    }

    func unresolvedPoints(base:[Occupancy])->Set<Int> {
        guard points.count==base.count else {return []}
        return Set(anchors.compactMap { point,anchor in
            anchor.supported && anchor.color != base[point] ? point : nil
        })
    }

    /// The current color episode begins after the last definite contradiction.
    /// Two sightings separated by >=150 ms establish it, including across gaps.
    private func established(point:Int,color:Occupancy)->(first:Double,time:Double)? {
        guard points.indices.contains(point), !expiredPoints.contains(point) else {return nil}
        let runs=points[point]
        let start=runs.lastIndex(where:{$0.value != .uncertain && $0.value != color}).map{$0+1} ?? 0
        let sightings=runs.dropFirst(start).filter{$0.value==color}
        guard let first=sightings.first else {return nil}
        for run in sightings {
            if run.first-first.first>=0.15 {return (first.first,run.first)}
            if let established=run.established {return (first.first,established)}
        }
        return nil
    }

    /// Positive empty evidence after the latest contrary reading. Uncertainty
    /// alone never withdraws a tentative move.
    func repeatedlyEmpty(_ point:Int)->Bool {established(point:point,color:.empty) != nil}

    /// Reject reversing a repeatedly observed stone and a newly appearing reply.
    /// The reply need not have repeated yet: its first sighting must not create
    /// a reversed candidate that later frames would simply continue confirming.
    func wasPresentBeforeAppearance(_ a:Int,_ b:Int,readings:[Occupancy])->Bool {
        guard points.indices.contains(b),let early=established(point:a,color:readings[a]) else {return false}
        let runs=points[b]
        let start=runs.lastIndex(where:{$0.value != .uncertain && $0.value != readings[b]}).map{$0+1} ?? 0
        guard let first=runs.dropFirst(start).first(where:{$0.value==readings[b]})?.first else {return false}
        return runs.contains { run in
            run.value == .empty && run.established != nil &&
            run.previous.map{$0>=early.first && run.last-$0>=0.15} == true &&
            run.last>=early.time && run.last<first
        }
    }

    /// A precedes B only if A was repeatedly seen before B was repeatedly empty,
    /// and B's present color episode began later. First-detection sorting alone
    /// is unsafe: a hand can produce an early false stone at B's future location.
    func precedes(_ a:Int,_ b:Int,readings:[Occupancy])->Bool {
        guard let early=established(point:a,color:readings[a]),
              let late=established(point:b,color:readings[b]), early.time<late.time else {return false}
        return points[b].contains { run in
            run.value == .empty && run.established != nil &&
            run.previous.map{$0>=early.first && run.last-$0>=0.15} == true &&
            run.last>=early.time && run.last<late.time
        }
    }

    /// Enumerate alternating orders; stop as soon as two fit. Never select one
    /// merely because its first sightings were earlier or its score was higher.
    func uniqueOrder(additions:[Int],readings:[Occupancy],blackToPlay:Bool)->[Int]? {
        guard additions.count<=8, !additions.contains(where:{expiredPoints.contains($0)}) else {return nil}
        let edges=additions.flatMap { a in additions.filter{$0 != a && wasPresentBeforeAppearance(a,$0,readings:readings)}.map{(a,$0)} }
        var solutions=[[Int]]()
        func search(_ prefix:[Int],_ remaining:[Int],_ black:Bool) {
            guard solutions.count<2 else {return}
            if remaining.isEmpty {solutions.append(prefix);return}
            for point in remaining where readings[point] == (black ? .black : .white) {
                guard !edges.contains(where:{$0.1==point && remaining.contains($0.0)}) else {continue}
                search(prefix+[point],remaining.filter{$0 != point},!black)
            }
        }
        search([],additions,blackToPlay)
        return solutions.count==1 ? solutions[0] : nil
    }
}
