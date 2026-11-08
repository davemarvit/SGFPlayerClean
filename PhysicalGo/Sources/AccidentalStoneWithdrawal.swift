import Foundation

/// A concrete, rules-checked cleanup proposal. Original snapshots are retained;
/// only additions explicitly selected for withdrawal are excluded from the record.
@MainActor struct AccidentalStoneWithdrawal {
    let sectionIDs:[UUID]
    let removedPoints:Set<Int>
    let results:[UUID:[Occupancy]]
    let moves:[UUID:[DeferredMoveHistory.Move]]
    let target:[Occupancy]
    let verificationPoints:Set<Int>
    let keptMoves:[DeferredMoveHistory.Move]
    let nextPlayer:Stone
    static func make(history:DeferredMoveHistory,id:UUID,context:SGFGame)->Self? {
        guard let index=history.sections.firstIndex(where:{$0.id==id}),!history.sections[index].committed else {return nil}
        let initial=history.sections[index]
        let points=Set(initial.before.indices.filter{initial.before[$0] != initial.after[$0]})
        guard !points.isEmpty,points.allSatisfy({initial.before[$0] == .empty && initial.after[$0].stone != nil}) else {return nil}
        let player=SGFPlayer();player.load(game:context);player.seek(to:context.moves.count)
        let start=DeferredMoveHistory.states(player.board)
        guard start==initial.before else {return nil}
        func normalized(_ values:[Occupancy])->[Occupancy] {
            values.enumerated().map{points.contains($0.offset) ? .empty:$0.element}
        }
        var results=[UUID:[Occupancy]](),moves=[UUID:[DeferredMoveHistory.Move]](),kept=[DeferredMoveHistory.Move](),ids=[UUID]()
        for (offset,section) in history.sections.enumerated() where offset>=index {
            guard !section.committed,normalized(section.before)==DeferredMoveHistory.states(player.board) else {return nil}
            let selected:[DeferredMoveHistory.Move]
            if offset==index {selected=[]}
            else {
                // A later new placement at an excluded point could be a real
                // replay. Never silently discard it as part of an old mistake.
                guard !points.contains(where:{section.before[$0] == .empty && section.after[$0].stone != nil}) else {return nil}
                if let known=section.moves {
                    guard known.allSatisfy({$0.point.map{!points.contains($0.row*history.size+$0.col)} ?? true}) else {return nil}
                    selected=known
                } else {
                    guard normalized(section.before)==normalized(section.after) else {return nil}
                    selected=[] // Only the physical removal of the selected extras.
                }
            }
            for move in selected {
                guard player.tryPlayMove(color:move.color,x:move.point?.col ?? -1,y:move.point?.row ?? -1)==nil else {return nil}
            }
            let result=DeferredMoveHistory.states(player.board)
            guard result==normalized(section.after) else {return nil}
            ids.append(section.id);results[section.id]=result;moves[section.id]=selected
            if offset>index {kept += selected}
        }
        let target=DeferredMoveHistory.states(player.board)
        let changed=Set(start.indices.filter{start[$0] != target[$0]})
        return .init(sectionIDs:ids,removedPoints:points,results:results,moves:moves,target:target,
                     verificationPoints:points.union(changed),keptMoves:kept,nextPlayer:player.turn)
    }
}
