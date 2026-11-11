import Foundation

/// A single legal capture, including an intermediate physical removal position.
/// Nothing here accepts a game move or infers a color from an uncertain reading.
@MainActor struct AutomaticCapture {
    let point:Int
    let color:Stone
    let captured:Set<Int>
    let before:[Occupancy]
    /// Expected intermediate position for persistence/manual review. Unchanged
    /// points come from legal history; this is not a replacement camera reading.
    let source:[Occupancy]
    let target:[Occupancy]
    let board:BoardSnapshot
    /// Prisoners may remain or be removed in any order. Unknown readings are
    /// not contradictions; every other definite change needs attention.
    func conflictingPoints(_ readings:[Occupancy])->Set<Int> {
        guard readings.count==target.count else {return []}
        return Set(readings.indices.filter {p in
            readings[p] != .uncertain && (captured.contains(p)
                ? readings[p] != before[p] && readings[p] != .empty
                : readings[p] != target[p])
        })
    }
    /// Intermediate removals and the completed board belong to the same move.
    /// Require clear capture points and reject every definite contradiction.
    /// Limited uncertainty elsewhere follows the same rule as final verification.
    func matchesRemoval(_ readings:[Occupancy])->Bool {
        guard readings.count==target.count else {return false}
        var intermediate=target
        for p in captured {
            guard readings[p]==before[p] || readings[p] == .empty else {return false}
            intermediate[p]=readings[p]
        }
        return ReviewBoardVerification.matches(readings,target:intermediate,requiredClear:captured.union([point]))
    }
    func matchesCompleted(_ readings:[Occupancy])->Bool {
        ReviewBoardVerification.matches(readings,target:target,requiredClear:captured.union([point]))
    }
    static func find(game:SGFGame,readings:[Occupancy],minimum:Int,includingCompleted:Bool=false)->Self? {
        guard minimum>=2,readings.count==game.boardSize*game.boardSize else {return nil}
        let trial=SGFPlayer();trial.load(game:game);trial.seek(to:game.moves.count)
        let before=DeferredMoveHistory.states(trial.board)
        let added=before.indices.filter {before[$0] == .empty && readings[$0].stone != nil}
        guard added.count==1,let point=added.first,readings[point].stone==trial.turn else {return nil}
        let color=trial.turn
        guard trial.tryPlayMove(color:color,x:point%game.boardSize,y:point/game.boardSize)==nil else {return nil}
        let target=DeferredMoveHistory.states(trial.board)
        let captured=Set(before.indices.filter {before[$0].stone==color.opponent && target[$0] == .empty})
        guard captured.count>=minimum,includingCompleted || captured.contains(where:{readings[$0] != .empty}) else {return nil}
        let source=before.indices.map {p in p==point || captured.contains(p) ? readings[p]:before[p]}
        let plan=Self(point:point,color:color,captured:captured,before:before,source:source,target:target,board:trial.board)
        return plan.matchesRemoval(readings) ? plan:nil
    }
}

/// Speech evidence only; never changes capture acceptance or clock arithmetic.
/// Each continuously visible disagreement is announced once. Hands, uncertainty
/// or a camera interruption require fresh evidence before another announcement.
struct CaptureConflictMonitor {
    private struct Sightings {let first:Double;var count:Int}
    private var sightings=[Int:Sightings]()
    private var announced=Set<Int>()
    private var lastFrame:Double?
    private(set) var points=[Int]()
    mutating func interrupt() {self=Self()}
    mutating func update(_ conflicts:Set<Int>,now:Double)->Bool {
        guard now.isFinite,lastFrame.map({now>$0}) ?? true else {return false}
        if let lastFrame,now-lastFrame>1.5 {interrupt()}
        lastFrame=now
        announced.formIntersection(conflicts)
        sightings=sightings.filter{conflicts.contains($0.key)}
        for point in conflicts {
            var seen=sightings[point] ?? Sightings(first:now,count:0)
            seen.count += 1;sightings[point]=seen
        }
        points=sightings.filter{$0.value.count>=3 && now-$0.value.first>=2}.keys.sorted()
        let fresh=Set(points).subtracting(announced)
        announced.formUnion(fresh)
        return !fresh.isEmpty
    }
}

/// Bounded, chronological evidence survives hand re-entry and recognition lag.
/// Camera interruption, pause or calibration changes still invalidate the epoch.
struct ClearBoardTiming {
    private struct View {let time:Double;let position:[Occupancy];let confidence:[Double];let estimate:ClockPressEstimate}
    private var views=[View]()
    private var consumedUntil = -Double.infinity
    private var lastActivity:Double?
    mutating func reset() {views=[];consumedUntil = -Double.infinity;lastActivity=nil}
    mutating func noteHand(at time:Double) {
        guard time.isFinite else {return}
        if let lastActivity,time-lastActivity>1.5 {reset()}
        lastActivity=max(lastActivity ?? time,time)
    }
    mutating func consume(through time:Double) {
        consumedUntil=max(consumedUntil,time);views.removeAll{$0.time<=consumedUntil}
    }
    mutating func observe(_ observation:BoardObservation,now:Double) {
        guard observation.handObstructed == false,let stamp=observation.capturedAt,
              stamp.isFinite,stamp<=now,now-stamp<1.5,!observation.lightingBlocked else {return}
        guard views.last.map({stamp>$0.time}) ?? true else {return}
        if let lastActivity,stamp-lastActivity>1.5 {reset()}
        lastActivity=stamp
        views.removeAll {stamp-$0.time>120}
        let estimate=observation.clockPressEstimate.flatMap{$0.valid && $0.time<=stamp ? $0:nil}
            ?? ClockPressEstimate(time:stamp,method:.clearFrame)
        views.append(.init(time:stamp,position:observation.signature,confidence:observation.readings.map(\.confidence),estimate:estimate))
        if views.count>1000 {views.removeFirst(views.count-1000)}
    }
    func estimate(target:[Occupancy],changed:Set<Int>,after epoch:Double)->ClockPressEstimate? {
        // A definite withdrawal invalidates the earlier placement at that point.
        // Changes elsewhere do not erase an intermediate move during catch-up.
        let contradicted=views.last {view in
            changed.contains {p in target.indices.contains(p) && view.position.indices.contains(p) &&
                view.position[p] != .uncertain && view.position[p] != target[p]}
        }?.time ?? -Double.infinity
        return views.first {view in
            view.time>contradicted &&
            view.estimate.time>=epoch && view.estimate.time>consumedUntil &&
            ReviewBoardVerification.matches(view.position,target:target,requiredClear:changed)
        }?.estimate
    }
    /// Turn identity can be certain before the exact intersection. Require a
    /// single visible stone, repeated clear frames, and agreement elsewhere.
    func provisionalEstimate(target:[Occupancy],changed:Set<Int>,locations:Set<Int>,color:Stone,
                             aliases:[Set<Int>],after epoch:Double)->ClockPressEstimate? {
        func matches(_ view:View)->Bool {
            guard view.position.count==target.count,view.estimate.time>=epoch,view.estimate.time>consumedUntil else {return false}
            let present=locations.filter{view.position[$0].stone != nil}
            guard present.count==1,let point=present.first,view.position[point].stone==color,view.confidence[point]>=0.9 else {return false}
            var values=view.position
            for group in aliases {
                let actual=group.filter{values[$0].stone != nil},expected=group.filter{target[$0].stone != nil}
                guard actual.count==1,expected.count==1,let a=actual.first,let b=expected.first,values[a]==target[b] else {continue}
                for p in group {values[p] = .empty};values[b]=target[b]
            }
            return ReviewBoardVerification.matches(values,target:target,requiredClear:changed)
        }
        // A definite absence retracts an earlier flash; later real play needs
        // its own boundary. Hand frames alone do not retract placement evidence.
        let absent=views.last{view in locations.allSatisfy{view.position.indices.contains($0) && view.position[$0] == .empty}}?.time ?? -.infinity
        let eligible=views.filter{$0.time>absent && matches($0)}
        guard let first=eligible.first,let last=eligible.last,let newest=views.last,
              last.time==newest.time,eligible.count>=3,last.time-first.time>=0.2 else {return nil}
        return first.estimate
    }
    func firstMatch(target:[Occupancy],changed:Set<Int>,after epoch:Double)->Double? {
        estimate(target:target,changed:changed,after:epoch)?.time
    }
}
