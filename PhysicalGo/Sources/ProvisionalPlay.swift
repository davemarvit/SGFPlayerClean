import Foundation

/// Turn certainty and location certainty are different questions. All retained
/// paths must agree on the prefix's move count, colours and capture consequences.
@MainActor enum ProvisionalPlay {
    struct Turn {
        let offset:Int
        let color:Stone
        let target:[Occupancy]
        let changed:Set<Int>
        let locations:Set<Int>
        let aliases:[Set<Int>]
        let captured:Set<Int>
    }
    static func turn(history:MoveObservationHistory,game:SGFGame,base:BoardSnapshot,offset:Int,now:Double)->Turn? {
        let candidates=history.candidates
        guard offset>=0,!candidates.isEmpty,candidates.allSatisfy({$0.moves.count>offset}),let first=candidates.first else {return nil}
        // Differing orders are not interchangeable locations of one known turn.
        for i in 0...offset {
            let locations=Set(candidates.map{$0.moves[i]})
            if locations.count>1 && !candidates.allSatisfy({($0.locationChoices[i] ?? []).isSuperset(of:locations)}) {return nil}
        }
        let color=offset%2==0 ? (game.moves.last?.0.opponent ?? game.initialPlayer ?? .black):(game.moves.last?.0 ?? game.initialPlayer?.opponent ?? .white)
        let before=DeferredMoveHistory.states(offset==0 ? base:first.boards[offset-1])
        let target=DeferredMoveHistory.states(first.boards[offset])
        let captured=Set(before.indices.filter{before[$0].stone==color.opponent && target[$0] == .empty})
        guard candidates.allSatisfy({path in
            let prior=DeferredMoveHistory.states(offset==0 ? base:path.boards[offset-1]),after=DeferredMoveHistory.states(path.boards[offset])
            return Set(prior.indices.filter{prior[$0].stone==color.opponent && after[$0] == .empty})==captured &&
                path.witnesses.contains{$0.depth==offset+1 && now-$0.time<0.75}
        }) else {return nil}
        let locations=Set(candidates.map{$0.moves[offset]}).union(first.locationChoices[offset] ?? [])
        var aliases=Array(first.locationChoices.filter{$0.key<=offset}.values)
        if locations.count>1 {aliases.append(locations)}
        return Turn(offset:offset,color:color,target:target,changed:Set(before.indices.filter{before[$0] != target[$0]}),locations:locations,aliases:aliases,captured:captured)
    }
    static func normalized(_ readings:[Occupancy],path:MoveObservationHistory.Candidate,target:[Occupancy])->[Occupancy] {
        var values=readings
        for locations in path.locationChoices.values {
            let actual=locations.filter{values[$0].stone != nil},expected=locations.filter{target[$0].stone != nil}
            if actual.count==1,expected.count==1,let a=actual.first,let b=expected.first,values[a]==target[b] {
                values[a] = .empty;values[b]=target[b]
            }
        }
        return values
    }
    static func hasDefiniteConflict(_ readings:[Occupancy],history:MoveObservationHistory)->Bool {
        !history.candidates.contains {path in
            guard let board=path.boards.last else {return false}
            let target=DeferredMoveHistory.states(board),values=normalized(readings,path:path,target:target)
            return values.indices.allSatisfy{values[$0] == .uncertain || values[$0]==target[$0]}
        }
    }
    enum Removal {case none,uncertain,capture(AutomaticCapture,completed:Bool)}
    static func removal(history:MoveObservationHistory,game:SGFGame,readings:[Occupancy],minimum:Int,timedCount:Int,includingCompleted:Bool=false)->Removal {
        guard minimum>=2,timedCount>0,!history.candidates.isEmpty,
              history.candidates.allSatisfy({$0.moves.count==timedCount}) else {return .none}
        var plans=[AutomaticCapture](),nonCapture=false,completed=true
        for path in history.candidates {
            var context=game,color=game.moves.last?.0.opponent ?? game.initialPlayer ?? .black
            for p in path.moves {context.moves.append((color,(p%game.boardSize,p/game.boardSize)));color=color.opponent}
            context.sourceTree=nil
            let before=DeferredMoveHistory.states(path.boards.last!)
            let values=normalized(readings,path:path,target:before)
            if let plan=AutomaticCapture.find(game:context,readings:values,minimum:minimum,includingCompleted:includingCompleted) {plans.append(plan);completed = completed && plan.matchesCompleted(values);continue}
            let additions=values.indices.filter{before[$0] == .empty && values[$0].stone != nil}
            if additions.count==1,let p=additions.first,values[p].stone==color {
                let player=SGFPlayer();player.load(game:context);player.seek(to:context.moves.count)
                if player.tryPlayMove(color:color,x:p%game.boardSize,y:p/game.boardSize)==nil,
                   ReviewBoardVerification.matches(values,target:DeferredMoveHistory.states(player.board),requiredClear:[p]) {nonCapture=true}
            }
        }
        guard let first=plans.first else {return .none}
        guard !nonCapture,plans.allSatisfy({$0.point==first.point && $0.color==first.color && $0.captured==first.captured}) else {return .uncertain}
        return .capture(first,completed:completed)
    }

}
