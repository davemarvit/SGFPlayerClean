import Foundation

/// Heuristic evidence quality, not a shadow classifier or a probability.
/// Only new dark readings are discounted; uncertainty never means empty.
struct ShadowEvidence {
    static let handLookback=0.8
    struct Discount {let capturedAt:Double;let processedAt:Double;let points:Set<Int>}
    private struct Sample {let time:Double;let processedAt:Double;let points:Set<Int>}
    private var recent=[Sample]()
    private var last:Double?
    private var handAt:Double?
    private var darkSince=[Int:Double]()
    private var clusterPoints=Set<Int>()
    mutating func reset() {self=Self()}
    mutating func noteHand(at time:Double,protected:Set<Int>)->Set<Int> {
        noteHandSamples(at:time,protected:protected).reduce(into:Set<Int>()){$0.formUnion($1.points)}
    }
    mutating func noteHandSamples(at time:Double,protected:Set<Int>)->[Discount] {
        guard time.isFinite,last.map({time>$0}) ?? true else {return []}
        if let last,time-last>1.5 {reset()}
        last=time;handAt=time
        let points=recent.filter{time-$0.time<=Self.handLookback}.compactMap {sample -> Discount? in
            let points=sample.points.subtracting(protected)
            return points.isEmpty ? nil:Discount(capturedAt:sample.time,processedAt:sample.processedAt,points:points)
        }
        recent=[]
        return points
    }
    mutating func discount(_ raw:BoardObservation,base:[Occupancy],protected:Set<Int>,at time:Double,processedAt:Double?=nil)->Set<Int> {
        guard raw.readings.count==base.count,time.isFinite,last.map({time>$0}) ?? true else {return []}
        if let last,time-last>1.5 {reset()}
        last=time;recent.removeAll{time-$0.time>Self.handLookback}
        guard !raw.lightingBlocked,raw.manualPoints.isEmpty else {return []}
        let dark=Set(base.indices.filter{raw.readings[$0].occupancy == .black && base[$0] != .black && !protected.contains($0)})
        darkSince=darkSince.filter{dark.contains($0.key)}
        for p in dark where darkSince[p]==nil {darkSince[p]=time}
        clusterPoints.formIntersection(dark)
        let unknown=raw.readings.filter{$0.occupancy == .uncertain}.count
        let weak=Set(dark.filter{raw.readings[$0].confidence<0.97})
        let wrongWhite=dark.contains{base[$0] == .white}
        let broad=unknown>=max(3,base.count/20)
        let nearHand=handAt.map{time-$0<=1.0} ?? false
        // Several apparent black stones plus uncertainty/color contradictions
        // are a shadow-prone cluster. A clean catch-up position is not one.
        let simultaneous=Set(dark.filter{time-darkSince[$0]!<=0.6})
        if simultaneous.count>=3 && (broad || wrongWhite && unknown>=2) {clusterPoints.formUnion(simultaneous)}
        if !broad && !(wrongWhite && unknown>=2) {clusterPoints=[]}
        let suspect=clusterPoints.union(broad || nearHand && unknown>=2 ? weak:[])
        // Preserve a short lookback for the hand detector's entry latency.
        // Low score alone, on an otherwise clear board, is not enough.
        let retrospective=unknown>=2 ? weak.union(simultaneous.count>=3 ? simultaneous:[]):[]
        recent.append(Sample(time:time,processedAt:processedAt ?? time,points:retrospective))
        if recent.count>64 {recent.removeFirst(recent.count-64)}
        return suspect
    }
}

extension BoardObservation {
    func discountingDarkReadings(_ points:Set<Int>)->Self {
        var copy=self
        copy.readings=readings.enumerated().map {p,r in
            points.contains(p) && r.occupancy == .black
                ? .init(row:r.row,col:r.col,occupancy:.uncertain,confidence:0,delta:r.delta):r
        }
        return copy
    }
}
