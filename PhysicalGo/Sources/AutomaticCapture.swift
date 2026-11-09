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

/// Uses frame times, not the later completion time of image analysis. A hand
/// re-entering invalidates the earlier boundary; repeated frames add no evidence.
struct ClearBoardTiming {
    private var views:[(time:Double,position:[Occupancy])]=[]
    mutating func reset() {views=[]}
    mutating func observe(_ observation:BoardObservation,now:Double) {
        guard observation.handObstructed == false,let stamp=observation.capturedAt,
              stamp.isFinite,stamp<=now,now-stamp<1.5,!observation.lightingBlocked else {return}
        guard views.last.map({stamp>$0.time}) ?? true else {return}
        if let last=views.last,stamp-last.time>0.6 {views=[]}
        views.removeAll {stamp-$0.time>15}
        views.append((stamp,observation.signature))
    }
    func firstMatch(target:[Occupancy],changed:Set<Int>,after epoch:Double)->Double? {
        views.reversed().prefix {view in view.time>=epoch && ReviewBoardVerification.matches(view.position,target:target,requiredClear:changed)}.last?.time
    }
}
