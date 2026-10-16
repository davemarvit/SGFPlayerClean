import Foundation

/// Represents a single candidate move from KataGo
struct AIMoveInfo: Codable, Identifiable {
    var id: String { move }
    let move: String        // SGF String e.g. "Q16", "pass", or SGF "[dp]"? KataGo uses standard coordinates (A1 to T19, skipping I)
    let visits: Int
    let winrate: Double     // 0.0 to 1.0 (from Black's perspective if mapped, but KataGo outputs for the player to move, wait, KataGo generally outputs winrate from the perspective of the player to move. We will need to map it)
    let scoreLead: Double   // Positive is good for the player to move
    let pv: [String]?       // Principal variation
    
    // KataGo outputs winrate from the perspective of the player to move.
}

/// Represents the analysis payload for a specific turn
struct AIAnalysis: Codable {
    let id: String
    let isDuringSearch: Bool?
    let turnNumber: Int
    let moveInfos: [AIMoveInfo]?
    let rootInfo: AIRootInfo?
}

struct AIRootInfo: Codable {
    let winrate: Double
    let scoreLead: Double
    let visits: Int
}

import SwiftUI

enum MoveQuality: String, CaseIterable, Identifiable {
    case excellent = "Excellent"
    case good = "Good"
    case mediocre = "Mediocre"
    case poor = "Poor"
    case disastrous = "Disastrous"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .excellent: return .blue
        case .good: return .green
        case .mediocre: return .yellow
        case .poor: return .orange
        case .disastrous: return .red
        }
    }
}

struct MoveEvaluation {
    let turn: Int
    let quality: MoveQuality
    let winDelta: Double
    let scoreDelta: Double
    let player: Stone
}

/// A hypothetical continuation built on a private rules engine. The real SGF,
/// playback position, prisoners and scoring state are never changed.
struct AIVariationFrame {
    let stones: [BoardPosition: Stone]
    let numbers: [BoardPosition: Int]
    let caption: String
}

enum AIVariation {
    static func position(_ coordinate: String, size: Int) -> BoardPosition? {
        let value = coordinate.uppercased()
        let letters = Array("ABCDEFGHJKLMNOPQRST")
        guard let first = value.first, let col = letters.firstIndex(of: first), col < size,
              let row = Int(value.dropFirst()), (1...size).contains(row),
              value == "\(first)\(row)" else { return nil }
        return BoardPosition(size - row, col)
    }

    static func frames(candidate: AIMoveInfo, game: SGFPlayer, limit: Int = 12) -> [AIVariationFrame] {
        guard let pv = candidate.pv, !pv.isEmpty,
              pv.first?.uppercased() == candidate.move.uppercased() else { return [] }
        let s = game.createSnapshot()
        let copy = SGFPlayer()
        copy.restoreSnapshot(SGFPlayer.LocalGameSnapshot(moves: Array(s.moves.prefix(s.currentIndex)),
            setup: s.setup, size: s.size, currentIndex: s.currentIndex, initialPlayer: s.initialPlayer,
            stateVersion: s.stateVersion, analysisSettings: s.analysisSettings, freeHandicapMoves: s.freeHandicapMoves,
            capturedWhite: s.capturedWhite, capturedBlack: s.capturedBlack))
        var frames: [AIVariationFrame] = []
        var numbers: [BoardPosition: Int] = [:]
        for (index, coordinate) in pv.prefix(max(0, limit)).enumerated() {
            let pass = coordinate.lowercased() == "pass"
            let point = position(coordinate, size: s.size)
            guard pass || point != nil else { break }
            let color = copy.turn
            guard copy.tryPlayMove(color: color, x: point?.col ?? -1, y: point?.row ?? -1) == nil else { break }
            numbers = numbers.filter { copy.board.stones[$0.key] != nil }
            if let point { numbers[point] = index + 1 }
            let caption = "AI preview · \(index + 1)" + (pass ? " · \(color == .black ? "Black" : "White") passes" : "")
            frames.append(AIVariationFrame(stones: copy.board.stones, numbers: numbers, caption: caption))
        }
        return frames
    }
}
