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
    enum Status: Equatable {
        case ready, waitingForCamera, checking
        case unclear([Int]), different([Int]), obstructed(Int)

        func guidance(coordinate: (Int) -> String) -> String {
            switch self {
            case .ready: return "The camera has verified the corrected position."
            case .waitingForCamera: return "Waiting for a fresh camera view. Check that the camera is running and the board is visible."
            case .checking: return "The position matches. Keep hands clear while the camera confirms a steady view."
            case .unclear(let points): return "The camera cannot yet verify \(points.map(coordinate).joined(separator: ", ")). Keep those intersections clearly visible."
            case .different(let points): return "The camera sees a different position at \(points.prefix(8).map(coordinate).joined(separator: ", "))\(points.count > 8 ? " and other intersections" : ""). Check these locations against the board shown."
            case .obstructed(let count): return "The camera cannot read \(count) intersections. Clear hands or shadows and check the camera view."
            }
        }
    }
    static func matches(_ readings: [Occupancy], target: [Occupancy], requiredClear: Set<Int>) -> Bool {
        status(readings, target: target, requiredClear: requiredClear) == .ready
    }
    static func status(_ readings: [Occupancy], target: [Occupancy], requiredClear: Set<Int>) -> Status {
        guard readings.count == target.count else { return .waitingForCamera }
        let unclear = target.indices.filter { requiredClear.contains($0) && readings[$0] == .uncertain }
        if !unclear.isEmpty { return .unclear(unclear) }
        let different = target.indices.filter { readings[$0] != .uncertain && readings[$0] != target[$0] }
        if !different.isEmpty { return .different(different) }
        let unknown = readings.filter { $0 == .uncertain }.count
        // Match CameraViewContinuity's broad-loss boundary. Limited uncertainty
        // outside the corrected points must not erase known, unchanged history.
        if unknown > max(2, target.count / 3) { return .obstructed(unknown) }
        return .ready
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
