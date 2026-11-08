import Foundation

/// Review chronology policy, independent of UI, file I/O and live clock presses.
@MainActor enum ReviewHistoryCoordinator {
    struct Restoration {
        var history: DeferredMoveHistory
        var recoveredCommit: Bool
    }
    static func precedingWasPass(_ history: DeferredMoveHistory, game: SGFGame) -> Bool {
        for section in history.sections.reversed() where !section.committed {
            // Unknown order is not a move. Empty, resolved false detections can
            // be skipped, but an unresolved section breaks known chronology.
            guard let moves = section.moves else { return false }
            if let move = moves.last { return move.point == nil }
        }
        return game.moves.last.map { $0.1 == nil } ?? false
    }
    static func restore(_ saved: DeferredMoveHistory, game: SGFGame) throws -> Restoration {
        var history = saved
        var recoveredCommit = false
        let signature = RecordingIdentity.signature(for: game)
        // An SGF write can finish before the review sidecar is marked committed.
        // Match the complete suffix before recovering it; never append it twice.
        if history.active, history.anchorSignature != signature,
           let base = history.baseMove, base >= 0, base <= game.moves.count, history.unresolved == 0 {
            var prefix = game; prefix.moves = Array(game.moves.prefix(base))
            let moves = history.sections.filter { !$0.committed }.flatMap { $0.moves ?? [] }
            let suffix = game.moves.dropFirst(base).map {
                DeferredMoveHistory.Move(color: $0.0, point: $0.1.map { BoardPosition($0.1, $0.0) })
            }
            if RecordingIdentity.signature(for: prefix) == history.anchorSignature, moves == suffix {
                var number = base
                for i in history.sections.indices where !history.sections[i].committed {
                    history.sections[i].savedStart = number
                    number += history.sections[i].moves?.count ?? 0
                    history.sections[i].committed = true
                }
                history.anchorSignature = nil; history.baseMove = nil; recoveredCommit = true
            }
        }
        guard history.validate(size: game.boardSize, signature: signature) else {
            throw RecordingStore.Failure(message: "Review history does not match the saved game.")
        }
        return Restoration(history: history, recoveredCommit: recoveredCommit)
    }
}
