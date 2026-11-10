import Foundation

/// A single legal capture, including an intermediate physical removal position.
/// Nothing here accepts a game move or infers a color from an uncertain reading.
@MainActor struct AutomaticCapture {
    let point:Int
    let color:Stone
    let captured:Set<Int>
    let before:[Occupancy]
    let source:[Occupancy]
    let target:[Occupancy]
    let board:BoardSnapshot
    /// Intermediate removals and the completed board belong to the same move.
    /// Uncertainty, replacement stones and unrelated changes are not evidence.
    func matchesRemoval(_ readings:[Occupancy])->Bool {
        readings.count==target.count && readings.indices.allSatisfy { p in
            captured.contains(p) ? readings[p]==before[p] || readings[p] == .empty : readings[p]==target[p]
        }
    }
    static func find(game:SGFGame,readings:[Occupancy],minimum:Int)->Self? {
        guard minimum>=2,readings.count==game.boardSize*game.boardSize else {return nil}
        let trial=SGFPlayer();trial.load(game:game);trial.seek(to:game.moves.count)
        let before=DeferredMoveHistory.states(trial.board)
        let added=before.indices.filter {before[$0] == .empty && readings[$0].stone != nil}
        guard added.count==1,let point=added.first,readings[point].stone==trial.turn else {return nil}
        let color=trial.turn
        guard trial.tryPlayMove(color:color,x:point%game.boardSize,y:point/game.boardSize)==nil else {return nil}
        let target=DeferredMoveHistory.states(trial.board)
        let captured=Set(before.indices.filter {before[$0].stone==color.opponent && target[$0] == .empty})
        guard captured.count>=minimum,captured.contains(where:{readings[$0] != .empty}),
              before.indices.allSatisfy({p in captured.contains(p)
                  ? readings[p]==before[p] || readings[p] == .empty
                  : readings[p]==target[p]}) else {return nil}
        return Self(point:point,color:color,captured:captured,before:before,source:readings,target:target,board:trial.board)
    }
}

/// Bounded, chronological evidence survives hand re-entry and recognition lag.
/// Camera interruption, pause or calibration changes still invalidate the epoch.
struct ClearBoardTiming {
    private struct View {let time:Double;let position:[Occupancy];let estimate:ClockPressEstimate}
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
        views.append(.init(time:stamp,position:observation.signature,estimate:estimate))
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
    func firstMatch(target:[Occupancy],changed:Set<Int>,after epoch:Double)->Double? {
        estimate(target:target,changed:changed,after:epoch)?.time
    }
}
