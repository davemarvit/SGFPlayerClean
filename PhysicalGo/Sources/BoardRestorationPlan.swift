import Foundation

/// A proposal to restore accidentally disturbed stones without adding a move.
/// The player must choose restoration, and fresh observations must verify it.
@MainActor struct BoardRestorationPlan {
    enum Kind: Equatable {
        case displaced(from: Int, to: Int, color: Stone)
        case missing
    }
    let id: UUID
    let kind: Kind
    let target: [Occupancy]
    let source: [Occupancy]
    let changed: Set<Int>

    func remaining(in readings: [Occupancy]?) -> Set<Int> {
        let values = readings?.count == target.count ? readings! : source
        return Set(changed.filter { values[$0] != target[$0] })
    }
    func matches(_ readings: [Occupancy]) -> Bool {
        ReviewBoardVerification.matches(readings, target: target, requiredClear: changed)
    }
    static func make(history: DeferredMoveHistory, id: UUID, context: SGFGame) -> Self? {
        guard let section = history.sections.last, section.id == id,
              !section.committed, section.moves == nil, history.size == context.boardSize else { return nil }
        let trial = SGFPlayer(); trial.load(game: context); trial.seek(to: context.moves.count)
        let before = DeferredMoveHistory.states(trial.board)
        guard section.before == before, section.after.count == before.count else { return nil }
        let changed = Set(before.indices.filter { before[$0] != section.after[$0] })
        let removed = changed.filter { before[$0].stone != nil && section.after[$0] == .empty }
        let added = changed.filter { before[$0] == .empty && section.after[$0].stone != nil }
        let kind: Kind
        if changed.count == 2, removed.count == 1, added.count == 1,
           let from = removed.first, let to = added.first, let color = before[from].stone,
           section.after[to].stone == color,
           max(abs(from / history.size - to / history.size), abs(from % history.size - to % history.size)) <= 1 {
            kind = .displaced(from: from, to: to, color: color)
        } else if !removed.isEmpty, changed == removed {
            kind = .missing
        } else { return nil }
        return Self(id: id, kind: kind, target: before, source: section.after, changed: changed)
    }
}

enum ReviewBoardVerification {
    static func matches(_ readings: [Occupancy], target: [Occupancy], requiredClear: Set<Int>) -> Bool {
        guard readings.count == target.count else { return false }
        guard readings.filter({ $0 == .uncertain }).count <= max(2, target.count / 20) else { return false }
        return target.indices.allSatisfy { p in
            if requiredClear.contains(p) { return readings[p] == target[p] }
            return readings[p] == target[p] || readings[p] == .uncertain
        }
    }
}

/// Describes observed differences without claiming an unknown cause or order.
enum ReviewChangeKind {
    case additions, missing, colorChanges, mixed

    static func classify(before: [Occupancy], after: [Occupancy]) -> Self {
        guard before.count == after.count else { return .mixed }
        let changed = before.indices.filter { before[$0] != after[$0] }
        guard !changed.isEmpty else { return .mixed }
        if changed.allSatisfy({ before[$0] == .empty && after[$0].stone != nil }) { return .additions }
        if changed.allSatisfy({ before[$0].stone != nil && after[$0] == .empty }) { return .missing }
        if changed.contains(where: { before[$0].stone != nil && after[$0].stone != nil }) { return .colorChanges }
        return .mixed
    }
    var title: String {
        switch self {
        case .additions: return "New stones need checking"
        case .missing: return "Recorded stones are missing"
        case .colorChanges: return "Stone colors differ"
        case .mixed: return "Board changes need checking"
        }
    }
    var instructions: String {
        switch self {
        case .additions: return "Review the sequence if these were played moves, or undo the extras if they were placed accidentally."
        case .missing: return "Restore stones removed accidentally. If they were captured, review the capturing moves."
        case .colorChanges: return "Check the physical colors at the marked intersections. Review any captures and replacement moves, or correct a mistaken camera reading."
        case .mixed: return "Check the marked placements and removals. These changes may include captures, moved stones, or missed moves."
        }
    }
    var reviewAction: String { self == .additions ? "Review these moves" : "Review moves and captures" }
}
