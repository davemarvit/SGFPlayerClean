//
//  SGFGameWrapper.swift
//  SGFPlayerClean
//
//  Purpose: Wraps SGFGame with metadata for game library
//  Adapted from AppModel.swift
//

import Foundation

/// Wrapper for SGF game with metadata
struct SGFGameWrapper: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let game: SGFGame

    // Generate a stable fingerprint for caching
    var fingerprint: String {
        return url.lastPathComponent + "_" + String(url.path.hashValue)
    }

    // Convenience accessors for game metadata
    var title: String? {
        if let event = game.info.event, !event.isEmpty {
            return event
        }
        return url.deletingPathExtension().lastPathComponent
    }

    var blackPlayer: String? { game.info.playerBlack }
    var whitePlayer: String? { game.info.playerWhite }
    var result: String? { game.info.result }
    var date: String? { game.info.date }
    var komi: String? { game.info.komi }
    var size: Int { game.boardSize }
    var handicap: Int? {
        // Handicap is the number of black stones in setup (AB property)
        let blackSetup = game.setup.filter { $0.0 == .black }.count
        return blackSetup > 0 ? blackSetup : nil
    }

    static func == (lhs: SGFGameWrapper, rhs: SGFGameWrapper) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
