import Foundation

/// Physical verification of already timed identities, not a legal-history
/// assignment. Matching a visible member of a candidate set never resolves the
/// original intersection or creates a new clock press.
@MainActor enum RetainedTurnPosition {
    static func match(base:[Occupancy],moves:[LocalGameClock.Move],capture:AutomaticCapture?,readings:[Occupancy])->[Occupancy]? {
        guard base.count==readings.count,!moves.isEmpty else {return nil}
        var target=base,options=[[Int]]()
        if let capture {
            guard capture.before==base else {return nil}
            target=capture.target
            for p in capture.captured {
                guard readings[p] == .empty || readings[p]==capture.before[p] else {return nil}
                target[p]=readings[p]
            }
        }
        for (offset,move) in moves.enumerated() {
            guard move.number==moves[0].number+offset,move.black == (offset%2==0 ? moves[0].black:!moves[0].black),
                  move.estimate?.valid == true || move.reviewed == true,
                  let choices=move.observedLocations,!choices.isEmpty,
                  choices.allSatisfy({base.indices.contains($0)}) else {return nil}
            let color:Occupancy=move.black ? .black:.white
            let occupied=choices.filter {p in
                readings[p]==color && (target[p] == .empty || (offset==0 && capture?.point==p && target[p]==color))
            }
            guard !occupied.isEmpty else {return nil}
            options.append(occupied)
        }
        // Verify that every known identity has a distinct visible stone. Later
        // occupied candidates constrain this matching rather than blocking it.
        // The temporary matching is discarded, never saved as a location choice.
        var owner=[Int:Int]()
        func assign(_ move:Int,_ visited:inout Set<Int>)->Bool {
            for p in options[move] where visited.insert(p).inserted {
                if let previous=owner[p] {
                    if assign(previous,&visited) {owner[p]=move;return true}
                } else {owner[p]=move;return true}
            }
            return false
        }
        for i in moves.indices {var visited=Set<Int>();guard assign(i,&visited) else {return nil}}
        for (p,i) in owner {target[p]=moves[i].black ? .black:.white}
        let required=Set(target.indices.filter{target[$0].stone != nil}).union(capture?.captured ?? [])
        return ReviewBoardVerification.matches(readings,target:target,requiredClear:required) ? target:nil
    }
}
