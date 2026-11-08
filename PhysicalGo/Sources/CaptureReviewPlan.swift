import Foundation

/// Recognizes one legal capture whose physical removal is incomplete. Full game
/// history supplies turn/ko rules; every other observed point must match.
@MainActor struct CaptureReviewPlan {
    let id: UUID
    let point: Int
    let move: DeferredMoveHistory.Move
    let captured: Set<Int>
    let target: [Occupancy]
    let source: [Occupancy]

    func remaining(in readings: [Occupancy]?) -> Set<Int> {
        let values = readings?.count == target.count ? readings! : source
        return Set(captured.filter { values[$0] != .empty })
    }

    func matches(_ readings: [Occupancy]) -> Bool {
        ReviewBoardVerification.matches(readings, target: target, requiredClear: captured.union([point]))
    }

    static func make(history: DeferredMoveHistory, id: UUID, context: SGFGame) -> Self? {
        guard let index = history.sections.firstIndex(where: { $0.id == id }),
              index == history.sections.indices.last,
              !history.sections[index].committed, history.sections[index].moves == nil,
              history.size == context.boardSize else { return nil }
        let section = history.sections[index]
        let trial = SGFPlayer(); trial.load(game: context); trial.seek(to: context.moves.count)
        let before = DeferredMoveHistory.states(trial.board)
        guard section.before == before, section.after.count == before.count else { return nil }
        let additions = before.indices.filter { before[$0] == .empty && section.after[$0].stone != nil }
        guard additions.count == 1, let point = additions.first,
              section.after[point].stone == trial.turn else { return nil }
        let color = trial.turn
        guard trial.tryPlayMove(color: color, x: point % history.size, y: point / history.size) == nil else { return nil }
        let target = DeferredMoveHistory.states(trial.board)
        let captured = Set(before.indices.filter { before[$0].stone == color.opponent && target[$0] == .empty })
        guard !captured.isEmpty, before.indices.allSatisfy({ p in
            captured.contains(p) ? (section.after[p] == before[p] || section.after[p] == .empty) : section.after[p] == target[p]
        }) else { return nil }
        return Self(id: id, point: point, move: .init(color: color, point: BoardPosition(point / history.size, point % history.size)),
                    captured: captured, target: target, source: section.after)
    }
}
