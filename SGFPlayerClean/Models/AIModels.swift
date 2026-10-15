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

