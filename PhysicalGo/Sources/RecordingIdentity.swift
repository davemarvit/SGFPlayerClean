import Foundation

/// Stable identity shared by SGF, clocks and recovery sidecars.
enum RecordingIdentity {
    static func signature(for game: SGFGame) -> String {
        // Preserve the original on-disk format, including empty Japanese games.
        let setupKey = game.handicap == 0 && game.info.rules?.lowercased() == "japanese" ? "" :
            "\(game.info.rules ?? ""):\(game.handicap):" + game.setup.map { "\($0.0.rawValue),\($0.1),\($0.2)" }.joined(separator: ";") + ":"
        return setupKey + "\(game.boardSize):" + game.moves.map { move in
            move.0.rawValue + ":" + (move.1.map { "\($0.0),\($0.1)" } ?? "pass")
        }.joined(separator: ";")
    }
}
