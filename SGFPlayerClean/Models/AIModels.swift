import Foundation

/// Represents a single candidate move from KataGo
struct AIMoveInfo: Codable, Identifiable {
    var id: String { move }
    let move: String        // SGF String e.g. "Q16", "pass", or SGF "[dp]"? KataGo uses standard coordinates (A1 to T19, skipping I)
    let visits: Int
    let winrate: Double     // 0.0 to 1.0 (from Black's perspective if mapped, but KataGo outputs for the player to move, wait, KataGo generally outputs winrate from the perspective of the player to move. We will need to map it)
    let scoreLead: Double   // Positive is good for the player to move
    let pv: [String]?       // Principal variation
    var prior: Double? = nil // Optional for backward-compatible cached analysis.
    var order: Int? = nil
    
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

/// A graph position always uses Black's perspective, regardless of whose turn it is.
/// The label reports the score leader's win probability, not an unrelated maximum.
struct AIPositionSummary {
    let blackWinrate: Double
    let blackScoreLead: Double
    var leadingColor: Stone {
        if blackScoreLead == 0 { return blackWinrate >= 0.5 ? .black : .white }
        return blackScoreLead > 0 ? .black : .white
    }
    var leadingWinrate: Double { leadingColor == .black ? blackWinrate : 1 - blackWinrate }
    var label: String {
        let color = leadingColor == .black ? "B" : "W"
        return "\(color)+\(Self.number(abs(blackScoreLead))) · \(color) \(Self.number(leadingWinrate * 100))%"
    }
    var accessibilityDescription: String {
        let color = leadingColor == .black ? "Black" : "White"
        return "\(color) estimated lead: \(Self.number(abs(blackScoreLead))) points; \(color) win probability: \(Self.number(leadingWinrate * 100)) percent"
    }
    init?(root: AIRootInfo, playerToMove: Stone) {
        guard root.visits > 0, root.winrate.isFinite, (0...1).contains(root.winrate), root.scoreLead.isFinite else { return nil }
        blackWinrate = playerToMove == .black ? root.winrate : 1 - root.winrate
        blackScoreLead = playerToMove == .black ? root.scoreLead : -root.scoreLead
    }
    private static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: rounded == rounded.rounded() ? "%.0f" : "%.1f", rounded)
    }
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
        case .disastrous: return .pink
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
            capturedWhite: s.capturedWhite, capturedBlack: s.capturedBlack,
            captureSeed: s.captureSeed, captureIdentity: s.captureIdentity))
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

/// The current move keeps its red marker. Only the preceding three moves in
/// the selected history can receive quality rings (four recent moves total).
struct RecentMoveQualityMarker: Identifiable, Equatable {
    let id: Int
    let position: BoardPosition
    let stone: Stone
    let quality: MoveQuality
    let pointsLost: Double
    var label: String { pointsLost < 0.05 ? "0" : String(format: "−%.1f", pointsLost) }

    static func markers(engine: SGFPlayer, evaluations: [Int: MoveEvaluation]) -> [Self] {
        let end = min(engine.currentIndex, engine.maxIndex)
        guard end > 1 else { return [] }
        var seen = Set<BoardPosition>()
        if let current = engine.movePosition(at: end - 1) { seen.insert(current) }
        var result: [Self] = []
        for index in stride(from: end - 2, through: max(0, end - 4), by: -1) {
            guard let position = engine.movePosition(at: index), seen.insert(position).inserted,
                  let color = engine.moveColor(at: index), engine.board.stones[position] == color,
                  let evaluation = evaluations[index], evaluation.scoreDelta.isFinite else { continue }
            result.append(Self(id: index + 1, position: position, stone: color,
                               quality: evaluation.quality, pointsLost: max(0, -evaluation.scoreDelta)))
        }
        return result
    }
}

/// Point-loss filtering is independent of the legacy score/win-probability quality bands.
struct MistakeFilter {
    enum Players: String, CaseIterable, Identifiable {
        case both = "Both", black = "Black", white = "White"
        var id: String { rawValue }
        func includes(_ player: Stone) -> Bool {
            self == .both || (self == .black && player == .black) || (self == .white && player == .white)
        }
    }
    var players: Players = .both
    var minimumLoss: Double = 2
    func moveNumbers(in evaluations: [MoveEvaluation]) -> [Int] {
        guard minimumLoss.isFinite else { return [] }
        return evaluations.filter {
            players.includes($0.player) && $0.scoreDelta.isFinite &&
            max(0, -$0.scoreDelta) >= max(0, minimumLoss)
        }.map { $0.turn + 1 }.sorted()
    }
}

struct AIPlayerPerformance {
    let analyzedMoves: Int
    let meanPointLoss: Double?
    let accuracy: Double?

    /// KaTrain game_report: https://github.com/sanderland/katrain/blob/master/katrain/core/ai.py
    /// Reimplemented from its documented difficulty-weighted point-loss formula.
    /// Missing candidate priors in older caches must not masquerade as easy positions.
    init(player: Stone, evaluations: [MoveEvaluation], analyses: [Int: AIAnalysis]) {
        let moves = evaluations.filter { $0.player == player && $0.scoreDelta.isFinite }
        analyzedMoves = moves.count
        meanPointLoss = moves.isEmpty ? nil : moves.reduce(0) { $0 + max(0, -$1.scoreDelta) } / Double(moves.count)
        var weightedLoss = 0.0, totalWeight = 0.0
        var complete = !moves.isEmpty
        for move in moves {
            guard let analysis = analyses[move.turn], let root = analysis.rootInfo,
                  root.visits > 0, root.scoreLead.isFinite, let candidates = analysis.moveInfos,
                  !candidates.isEmpty else { complete = false; continue }
            // Additional restricted hover queries are stored separately; normal candidates
            // use KataGo's order. Require complete prior metadata for this position.
            let usable = candidates.filter { ($0.order ?? 0) < 999 }
            guard !usable.isEmpty, usable.allSatisfy({
                guard let prior = $0.prior else { return false }
                return prior.isFinite && (0...1).contains(prior) && $0.scoreLead.isFinite
            }) else { complete = false; continue }
            let priors = usable.reduce(0) { $0 + ($1.prior ?? 0) }
            guard priors > 0 else { complete = false; continue }
            let difficulty = min(1, usable.reduce(0) { $0 + max(0, root.scoreLead - $1.scoreLead) * ($1.prior ?? 0) } / priors)
            let loss = max(0, -move.scoreDelta)
            let weight = max(0.05, min(1, max(difficulty, loss / 4)))
            weightedLoss += weight * loss
            totalWeight += weight
        }
        accuracy = complete && totalWeight > 0 ? 100 * pow(0.75, weightedLoss / totalWeight) : nil
    }
}

/// Describes the move that produced the displayed position, never the next move.
struct SelectedMoveFeedback: Equatable {
    let moveNumber: Int
    let player: Stone
    let location: String
    let hasStone: Bool
    let pointsLost: Double?
    let winBefore: Double?
    let winAfter: Double?
    var title: String { "Move \(moveNumber) · \(player == .black ? "Black" : "White") · \(location)" }
    var stoneLossText: String? {
        guard let loss = pointsLost else { return nil }
        return String(format: "%@%.1fpt", loss >= 0.05 ? "−" : "", loss < 0.05 ? 0 : loss)
    }
    var stoneChanceText: String? {
        guard let before = winBefore, let after = winAfter else { return nil }
        let change = (after - before) * 100
        return String(format: "%@%.1fpp", abs(change) < 0.05 ? "" : (change < 0 ? "−" : "+"), abs(change) < 0.05 ? 0 : abs(change))
    }
    var lossText: String {
        pointsLost.map { String(format: "%.1f points lost", $0) } ?? "Analysis pending for this move"
    }
    var chanceText: String? {
        guard let before = winBefore, let after = winAfter else { return nil }
        let change = (after - before) * 100
        let direction = abs(change) < 0.05 ? "No change" : String(format: "%@%.1f percentage points", change < 0 ? "−" : "+", abs(change))
        return String(format: "Win chance: %.1f%% → %.1f%%", before * 100, after * 100) + " (" + direction + ")"
    }
    init?(engine: SGFPlayer, analyses: [Int: AIAnalysis]) {
        let move = engine.currentIndex - 1
        guard move >= 0, let color = engine.moveColor(at: move) else { return nil }
        moveNumber = move + 1; player = color
        if let position = engine.movePosition(at: move) {
            let letters = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")
            location = position.col < letters.count ? "\(letters[position.col])\(engine.board.size - position.row)" : "Intersection"
            hasStone = engine.board.stones[position] == color
        } else { location = "Pass"; hasStone = false }
        if let before = analyses[move]?.rootInfo, let after = analyses[move + 1]?.rootInfo,
           before.visits > 0, after.visits > 0, before.scoreLead.isFinite, after.scoreLead.isFinite,
           before.winrate.isFinite, after.winrate.isFinite,
           (0...1).contains(before.winrate), (0...1).contains(after.winrate) {
            let samePlayer = engine.playerToMove(at: move + 1) == color
            pointsLost = max(0, before.scoreLead - (samePlayer ? after.scoreLead : -after.scoreLead))
            winBefore = before.winrate
            winAfter = samePlayer ? after.winrate : 1 - after.winrate
        } else { pointsLost = nil; winBefore = nil; winAfter = nil }
    }
}
