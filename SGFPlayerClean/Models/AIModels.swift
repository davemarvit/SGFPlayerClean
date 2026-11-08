import Foundation
import CoreGraphics

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

/// Use the engine's recommendation order, not noisy individual win percentages.
enum AIMovePresentation {
    static func ranked(_ moves: [AIMoveInfo]) -> [AIMoveInfo] {
        moves.sorted {
            let lhs = $0.order.flatMap { $0 >= 0 ? $0 : nil } ?? Int.max
            let rhs = $1.order.flatMap { $0 >= 0 ? $0 : nil } ?? Int.max
            if lhs != rhs { return lhs < rhs }
            // Legacy caches have no order. Search visits are a safer fallback
            // than optimistic winrate outliers, with stable coordinate ties.
            if $0.visits != $1.visits { return $0.visits > $1.visits }
            return $0.move < $1.move
        }
    }

}

/// Represents the analysis payload for a specific turn
struct AIAnalysis: Codable {
    let id: String
    let isDuringSearch: Bool?
    let turnNumber: Int
    let moveInfos: [AIMoveInfo]?
    let rootInfo: AIRootInfo?
    var ownership: [Double]? = nil
    var ownershipStdev: [Double]? = nil
}

/// A conservative visual estimate of stones expected to be lost, not a death
/// probability or scoring adjudication. Ownership uses the configured side-to-move
/// perspective. Neutral ownership (including unsettled/seki points) is not death.
struct AIOwnershipEstimate: Equatable {
    let color: Stone
    let strength: Double
}

enum AILikelyDeadStones {
    static func ownershipEstimates(analysis: AIAnalysis?, size: Int,
                                   playerToMove: Stone) -> [BoardPosition: AIOwnershipEstimate] {
        guard (2...19).contains(size), let analysis, (analysis.rootInfo?.visits ?? 0) >= 50,
              let ownership = analysis.ownership, ownership.count == size * size,
              ownership.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else { return [:] }
        let deviations = analysis.ownershipStdev
        if let deviations, deviations.count != ownership.count ||
            !deviations.allSatisfy({ $0.isFinite && (0...1).contains($0) }) { return [:] }
        var result: [BoardPosition: AIOwnershipEstimate] = [:]
        for (index, value) in ownership.enumerated() {
            let evidence = abs(value) - (deviations?[index] ?? 0)
            guard evidence > 0.65 else { continue }
            let color = value > 0 ? playerToMove : playerToMove.opponent
            result[BoardPosition(index / size, index % size)] = AIOwnershipEstimate(
                color: color, strength: min(1, (evidence - 0.65) / 0.35))
        }
        // One confidently owned intersection beneath an isolated living stone
        // is not a territory region. Require support from nearby strong estimates.
        return result.filter { point, estimate in
            let neighbors = [BoardPosition(point.row - 1, point.col), BoardPosition(point.row + 1, point.col),
                             BoardPosition(point.row, point.col - 1), BoardPosition(point.row, point.col + 1)]
            return neighbors.filter { result[$0]?.color == estimate.color }.count >= 2
        }
    }

    static func strengths(analysis: AIAnalysis?, stones: [BoardPosition: Stone],
                          size: Int, playerToMove: Stone) -> [BoardPosition: Double] {
        guard (2...19).contains(size), let analysis, (analysis.rootInfo?.visits ?? 0) >= 50,
              let ownership = analysis.ownership, ownership.count == size * size,
              ownership.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else { return [:] }
        let deviations = analysis.ownershipStdev
        if let deviations, deviations.count != ownership.count ||
            !deviations.allSatisfy({ $0.isFinite && (0...1).contains($0) }) { return [:] }
        var remaining = Set(stones.keys)
        var result: [BoardPosition: Double] = [:]
        while let start = remaining.first {
            guard let color = stones[start] else { break }
            var group: [BoardPosition] = [], pending = [start]
            remaining.remove(start)
            var evidence = 1.0
            while let point = pending.popLast() {
                guard (0..<size).contains(point.row), (0..<size).contains(point.col) else { return [:] }
                group.append(point)
                let index = point.row * size + point.col
                let own = ownership[index] * (color == playerToMove ? 1 : -1)
                // Require the whole connected group to look lost. Search disagreement
                // reduces the mark instead of being presented as calibrated confidence.
                evidence = min(evidence, -own - (deviations?[index] ?? 0))
                for neighbor in [BoardPosition(point.row - 1, point.col), BoardPosition(point.row + 1, point.col),
                                 BoardPosition(point.row, point.col - 1), BoardPosition(point.row, point.col + 1)] {
                    if stones[neighbor] == color, remaining.remove(neighbor) != nil { pending.append(neighbor) }
                }
            }
            // Begin with a subtle warning for likely losses. Keep the existing
            // stronger marks unchanged once evidence reaches 0.6.
            guard evidence > 0.2 else { continue }
            let strength = evidence < 0.6
                ? (evidence - 0.2) * 0.5
                : min(1, (evidence - 0.5) / 0.5)
            for point in group { result[point] = strength }
        }
        return result
    }
}

/// Shared feathered ownership field for the flat board and the lit 3D surface.
/// Values are interpolated between intersections, leaving uncertain gaps clear.
enum AIOwnershipTexture {
    private static let cache = NSCache<NSString, CGImage>()
    static let pixelsPerCell = 24
    // Strongly settled regions should read clearly over the board grain.
    // Confidence and feathering still taper the shading toward uncertain edges.
    static let maximumOpacity = 0.50

    static func image(estimates: [BoardPosition: AIOwnershipEstimate], size: Int) -> CGImage? {
        guard (2...19).contains(size), !estimates.isEmpty else { return nil }
        var field = Array(repeating: 0.0, count: size * size)
        for (point, estimate) in estimates where (0..<size).contains(point.row) && (0..<size).contains(point.col) {
            guard estimate.strength.isFinite else { continue }
            field[point.row * size + point.col] = min(1, max(0, estimate.strength)) * (estimate.color == .black ? -1 : 1)
        }
        let key = ("\(size):" + field.map { String($0) }.joined(separator: ",")) as NSString
        if let image = cache.object(forKey: key) { return image }
        let dimension = size * pixelsPerCell
        var pixels = Array(repeating: UInt8(0), count: dimension * dimension * 4)
        func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
        func sample(_ row: Int, _ col: Int) -> Double {
            field[min(size - 1, max(0, row)) * size + min(size - 1, max(0, col))]
        }
        for y in 0..<dimension {
            let row = (Double(y) + 0.5) / Double(pixelsPerCell) - 0.5
            let r = Int(floor(row)), fy = smooth(row - Double(r))
            for x in 0..<dimension {
                let col = (Double(x) + 0.5) / Double(pixelsPerCell) - 0.5
                let c = Int(floor(col)), fx = smooth(col - Double(c))
                let top = sample(r, c) * (1 - fx) + sample(r, c + 1) * fx
                let bottom = sample(r + 1, c) * (1 - fx) + sample(r + 1, c + 1) * fx
                let value = top * (1 - fy) + bottom * fy
                // Feather the outer half-cell as well, so the map has no hard frame.
                let edge = min(Double(min(x, dimension - 1 - x)) + 0.5,
                               Double(min(y, dimension - 1 - y)) + 0.5)
                let alpha = UInt8((255 * maximumOpacity * abs(value) * smooth(min(1, edge / 12))).rounded())
                let offset = (y * dimension + x) * 4
                let ink: UInt8 = value > 0 ? alpha : 0
                pixels[offset] = ink; pixels[offset + 1] = ink; pixels[offset + 2] = ink
                pixels[offset + 3] = alpha
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: dimension, height: dimension, bitsPerComponent: 8,
                  bitsPerPixel: 32, bytesPerRow: dimension * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        cache.totalCostLimit = 8 * 1024 * 1024
        cache.setObject(image, forKey: key, cost: pixels.count)
        return image
    }
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

/// Symmetric score bounds keep an even position centered. Probability uses the
/// same screen extent but preserves its own fixed 0–100% meaning.
struct AIReviewGraphScale {
    let limit: Double
    init(scores: [Double]) {
        let magnitude = scores.filter(\.isFinite).map { abs($0) }.max() ?? 0
        limit = magnitude > 0 ? magnitude : 1
    }
    func winratePosition(_ blackWinrate: Double) -> Double { (blackWinrate * 2 - 1) * limit }
}

enum MoveQuality: String, CaseIterable, Identifiable {
    case excellent = "Excellent"
    case good = "Good"
    case mediocre = "Mediocre"
    case poor = "Poor"
    case disastrous = "Disastrous"
    
    var id: String { rawValue }
    
    /// Textual summary grades retain their existing thresholds. Board/graph colors
    /// use the continuous point-loss scale below, independently of these categories.
    static func classify(winDelta: Double, scoreDelta: Double) -> Self {
        if winDelta < -0.20 || scoreDelta < -8.0 { return .disastrous }
        if winDelta < -0.10 || scoreDelta < -4.0 { return .poor }
        if winDelta < -0.05 || scoreDelta < -2.0 { return .mediocre }
        if winDelta < -0.015 || scoreDelta < -0.5 { return .good }
        return .excellent
    }
}

/// KaTrain's normal palette and loss anchors, with interpolation instead of bands.
/// https://github.com/sanderland/katrain/blob/master/katrain/gui/theme.py
/// https://github.com/sanderland/katrain/blob/master/katrain/config.json
enum MoveLossPalette {
    struct Stop {
        let loss: Double
        let red: Double
        let green: Double
        let blue: Double
        var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
        var labelColor: Color {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
            return luminance > 0.179 ? .black : .white
        }
    }
    static let stops: [Stop] = [
        Stop(loss: 0, red: 0.117, green: 0.588, blue: 0),
        Stop(loss: 0.5, red: 0.67, green: 0.9, blue: 0.18),
        Stop(loss: 1.5, red: 0.95, green: 0.95, blue: 0),
        Stop(loss: 3, red: 0.9, green: 0.4, blue: 0.1),
        Stop(loss: 6, red: 0.8, green: 0, blue: 0),
        Stop(loss: 12, red: 0.447, green: 0.129, blue: 0.42)
    ]
    static func sample(pointsLost: Double) -> Stop {
        guard pointsLost.isFinite else { return Stop(loss: 0, red: 0.5, green: 0.5, blue: 0.5) }
        let loss = max(0, pointsLost)
        for (low, high) in zip(stops, stops.dropFirst()) where loss <= high.loss {
            let t = (loss - low.loss) / (high.loss - low.loss)
            return Stop(loss: loss, red: low.red + (high.red - low.red) * t,
                green: low.green + (high.green - low.green) * t,
                blue: low.blue + (high.blue - low.blue) * t)
        }
        return stops[stops.count - 1]
    }
    static func color(pointsLost: Double) -> Color { sample(pointsLost: pointsLost).color }
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
        return String(format: "%@%.1f", loss >= 0.05 ? "−" : "", loss < 0.05 ? 0 : loss)
    }
    var stoneChanceText: String? {
        guard let before = winBefore, let after = winAfter else { return nil }
        let change = (after - before) * 100
        return String(format: "%@%.1f%%", abs(change) < 0.05 ? "" : (change < 0 ? "−" : "+"), abs(change) < 0.05 ? 0 : abs(change))
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
    init?(engine: SGFPlayer, analyses: [Int: AIAnalysis], moveNumber: Int? = nil) {
        let move = (moveNumber ?? engine.currentIndex) - 1
        guard move >= 0, let color = engine.moveColor(at: move) else { return nil }
        self.moveNumber = move + 1; player = color
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

/// The played move uses the same before/after evaluation as mistake navigation.
/// An unevaluated move is never fabricated as a zero-loss candidate.
enum HistoricalMoveHints {
    static func candidates(analysis: AIAnalysis?, evaluation: MoveEvaluation?, position: BoardPosition?, size: Int) -> [AIMoveInfo] {
        let moves = analysis?.moveInfos ?? []
        var result = Array(AIMovePresentation.ranked(moves).prefix(10))
        guard let position else { return result }
        let letters = Array("ABCDEFGHJKLMNOPQRST")
        guard letters.indices.contains(position.col) else { return result }
        let coordinate = "\(letters[position.col])\(size - position.row)"
        if let evaluation, let root = analysis?.rootInfo {
            let existing = moves.first { $0.move.uppercased() == coordinate }
            let played = AIMoveInfo(move: coordinate, visits: existing?.visits ?? 0,
                winrate: root.winrate + evaluation.winDelta,
                scoreLead: root.scoreLead + evaluation.scoreDelta, pv: existing?.pv,
                prior: existing?.prior, order: existing?.order)
            if let index = result.firstIndex(where: { $0.move.uppercased() == coordinate }) { result[index] = played }
            else { result.append(played) }
        } else if !result.contains(where: { $0.move.uppercased() == coordinate }),
                  let played = moves.first(where: { $0.move.uppercased() == coordinate }) { result.append(played) }
        return result
    }
}
