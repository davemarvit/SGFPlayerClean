import Foundation

/// One item per unresolved placement, never one per alternative intersection.
struct PlacementAmbiguity:Identifiable {
    let id:String
    let color:Stone
    let number:Int?
    let offset:Int?
    let reviewID:UUID?
    let board:BoardSnapshot
    let points:[Int]
}

extension GameRecorder {
    var placementAmbiguities:[PlacementAmbiguity] {
        let history=tentativeHistory
        var result=[PlacementAmbiguity]()
        if let path=history.bestCandidate {
            for (offset,evidence) in history.moveConfidence.enumerated() where evidence.level != "high" && path.boards.indices.contains(offset) {
                // Ordinary recognition needs several frames. A placement issue,
                // competing location, or retained unclear view is actionable.
                guard evidence.placementUncertain || !evidence.alternatives.isEmpty ||
                      evidence.point.map({adjustmentIssues[$0] != nil}) == true else {continue}
                let points=Set(evidence.point.map{[$0]} ?? []).union(evidence.alternatives).union(path.locationChoices[offset] ?? [])
                result.append(.init(id:"move-\(moveCount+offset+1)",color:offset%2==0 ? nextPlayer:nextPlayer.opponent,
                    number:moveCount+offset+1,offset:offset,reviewID:nil,board:path.boards[offset],points:points.sorted()))
            }
        }
        for section in reviewHistory.sections where !section.committed && section.moves==nil {
            // Capture cleanup and restoring a bumped saved stone have their own
            // controls. Do not label them as uncertain new placements.
            if captureReviewPlan(section.id) != nil || boardRestorationPlan(section.id) != nil {continue}
            let orders=section.suggestedOrders ?? []
            if let first=orders.first,!first.isEmpty,orders.allSatisfy({$0.count==first.count}) {
                for i in first.indices {
                    guard let color=Optional(first[i].color),orders.allSatisfy({$0[i].color==color}) else {continue}
                    let points=Set(orders.compactMap{$0[i].point.map{$0.row*game.boardSize+$0.col}})
                    guard !points.isEmpty else {continue}
                    result.append(.init(id:"\(section.id)-\(i)",color:color,number:nil,offset:nil,reviewID:section.id,
                        board:DeferredMoveHistory.board(section.after,size:game.boardSize),points:points.sorted()))
                }
            } else {
                for p in section.after.indices where section.before[p] != section.after[p] {
                    guard let color=section.after[p].stone else {continue}
                    result.append(.init(id:"\(section.id)-point-\(p)",color:color,number:nil,offset:nil,reviewID:section.id,
                        board:DeferredMoveHistory.board(section.after,size:game.boardSize),points:[p]))
                }
            }
        }
        return result
    }
}
