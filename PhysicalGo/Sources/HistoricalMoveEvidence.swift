import Foundation

/// Remembers verified position transitions, never substitutes labels in camera
/// observations. No network, images, UI, or platform-specific dependencies.
struct HistoricalMoveEvidence {
    enum Outcome: Equatable {
        case idle, candidate(Int), ambiguous, obscured, placementNeeded, contradiction
    }
    private var submitted:(point:Int,color:String)?
    private var suspected:Int?
    private(set) var board=[String]()
    private(set) var placements=[Int:String]()
    private(set) var removals=[Int:String]()
    private(set) var emptyWitnesses=Set<Int>()
    private(set) var comparison=[String]()

    mutating func anchor(_ position:[String]) {
        board=position;placements=[:];removals=[:];submitted=nil;suspected=nil
        emptyWitnesses=Set(position.indices.filter{position[$0]=="empty"})
    }
    mutating func didSubmit(_ point:Int,color:String) {submitted=(point,color)}
    mutating func advance(_ next:[String],submitted:Int?) {
        guard board.count==next.count else {self=Self();return}
        for p in next.indices where next[p] != board[p] {
            placements[p]=nil;removals[p]=nil;emptyWitnesses.remove(p)
            if next[p]=="empty" {removals[p]=board[p]}
            else if submitted != p && !(self.submitted?.point==p && self.submitted?.color==next[p]) {placements[p]=next[p]}
        }
        if let accepted=self.submitted,next[accepted.point]==accepted.color {self.submitted=nil}
        board=next;suspected=nil
    }
    mutating func observe(_ readings:[String],confidence:[Double],size:Int,color:String,
                          myTurn:Bool,ambiguous:Set<Int> = [])->Outcome {
        guard board.count==size*size,readings.count==board.count,confidence.count==board.count else {return .obscured}
        // Only for discrepancy presentation. This is NOT a reconstructed camera
        // observation and must never enter training data or recognition evidence.
        comparison=board
        let unknown=readings.filter{$0=="uncertain"}.count
        guard unknown<=max(12,board.count/5) else {return .obscured}
        for (p,value) in placements where readings[p]==value && confidence[p]>=0.8 && !ambiguous.contains(p) {
            placements[p]=nil
        }
        for (p,_) in removals where readings[p]=="empty" && confidence[p]>=0.8 {
            removals[p]=nil;emptyWitnesses.insert(p)
        }
        let additions=board.indices.filter {board[$0]=="empty" && readings[$0]==color && removals[$0]==nil}
        if myTurn,additions.count==1 {suspected=additions[0]}
        if let p=suspected,readings[p]=="empty" || !myTurn {suspected=nil}
        let point=myTurn && additions.count==1 ? additions[0]:nil
        let result=point.flatMap {PhysicalMoveInference.position(after:$0,board:board,size:size,color:color)}
        var conflict=false
        for p in board.indices {
            let seen=readings[p]
            guard seen != "uncertain",seen != board[p] else {continue}
            if removals[p]==seen {continue} // Captured stones may be removed later.
            if p==point,result != nil {continue}
            if board[p] != "empty",result?[p]=="empty",seen=="empty" {continue}
            // Missing opponent placement is an explicit outstanding obligation.
            if placements[p] != nil {comparison[p]=seen;continue}
            // Positive contradictory evidence matters; ambiguity elsewhere does not.
            if confidence[p]>=0.8 {
                conflict=true;comparison[p]=seen
            }
        }
        if conflict {return .contradiction}
        if !placements.isEmpty {
            for p in placements.keys {comparison[p]=readings[p]=="uncertain" ? "empty":readings[p]}
            return .placementNeeded
        }
        if additions.count>1 && myTurn {return .ambiguous}
        guard let point else {return suspected == nil ? .idle:.ambiguous} // Explicit no-move alternative.
        guard result != nil,emptyWitnesses.contains(point),confidence[point]>=0.8,
              !ambiguous.contains(point) else {return .ambiguous}
        return .candidate(point)
    }
}
