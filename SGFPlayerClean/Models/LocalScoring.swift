import Foundation

/// Arithmetic after players agree on life/death. This deliberately does not adjudicate life,
/// death, seki, ko disputes, or Japanese exceptional positions automatically.
enum LocalScoringRule: String, CaseIterable, Identifiable {
    case unspecified = "Choose scoring rules"
    case japanese = "Japanese"
    case korean = "Korean"
    case chinese = "Chinese"
    case chineseOGS = "Chinese-OGS"
    case chineseKGS = "Chinese-KGS"
    case aga = "AGA"
    case bga = "BGA"
    case newZealand = "New Zealand"
    case trompTaylor = "Tromp-Taylor"
    var id: String { rawValue }
    var territoryScoring: Bool { self == .japanese || self == .korean }

    init(settings: GameAnalysisSettings) {
        guard settings.rules != nil, settings.analysisRulesSupported else { self = .unspecified; return }
        switch settings.kataRules {
        case "japanese": self = .japanese
        case "korean": self = .korean
        case "chinese": self = .chinese
        case "chinese-ogs": self = .chineseOGS
        case "chinese-kgs": self = .chineseKGS
        case "aga": self = .aga
        case "bga": self = .bga
        case "new-zealand": self = .newZealand
        case "tromp-taylor": self = .trompTaylor
        default: self = .unspecified
        }
    }

    func handicapBonus(_ handicap: Int) -> Double {
        guard handicap > 1 else { return 0 }
        switch self {
        case .chinese, .chineseOGS, .chineseKGS: return Double(handicap)
        case .aga, .bga: return Double(handicap - 1)
        default: return 0
        }
    }
}

struct LocalScoreResult {
    struct Side {
        let territory, livingStones, captured, markedDead: Int
        let komi, handicap, total: Double
    }
    let black, white: Side
    let territory: [BoardPosition: Stone]
    func winnerDescription(blackName: String?, whiteName: String?) -> String {
        winningScoreDescription(black: black.total, white: white.total, blackName: blackName, whiteName: whiteName)
    }
}

struct LocalScoringSession {
    enum Tool: String, CaseIterable { case deadGroups = "Dead groups", neutralAreas = "Neutral areas" }
    struct Region { let points: Set<BoardPosition>; let owner: Stone? }
    let index: Int
    let board: BoardSnapshot
    let capturesByBlack, capturesByWhite, handicap: Int
    var rule: LocalScoringRule
    var komiText: String
    var handicapBonusOverride: Double?
    var invalidHandicapBonus = false
    var deadStones: Set<BoardPosition> = []
    var neutralPoints: Set<BoardPosition> = []
    var tool: Tool = .deadGroups
    var isFinal = false

    init(player: SGFPlayer, handicap: Int) {
        index = player.currentIndex
        board = player.board
        capturesByBlack = player.capturesByBlack
        capturesByWhite = player.capturesByWhite
        self.handicap = handicap
        rule = LocalScoringRule(settings: player.analysisSettings)
        komiText = player.analysisSettings.komi.map { String($0) } ?? ""
        if let bonus = player.analysisSettings.whiteHandicapBonus {
            switch bonus.uppercased() {
            case "0": handicapBonusOverride = 0
            case "N": handicapBonusOverride = handicap > 1 ? Double(handicap) : 0
            case "N-1": handicapBonusOverride = Double(max(0, handicap - 1))
            default: invalidHandicapBonus = true
            }
        }
    }

    var issue: String? {
        if rule == .unspecified { return "Choose scoring rules. The file's rules are missing or unsupported for local scoring." }
        guard let komi = Double(komiText.trimmingCharacters(in: .whitespacesAndNewlines)),
              komi.isFinite, (-400...400).contains(komi), (komi * 2).rounded() == komi * 2 else {
            return "Enter komi in whole or half points, including 0 if there is no komi."
        }
        if invalidHandicapBonus { return "Unknown handicap compensation. Choose scoring rules to use their standard compensation." }
        return nil
    }

    private func neighbors(_ p: BoardPosition) -> [BoardPosition] {
        [(p.row-1,p.col), (p.row+1,p.col), (p.row,p.col-1), (p.row,p.col+1)]
            .filter { (0..<board.size).contains($0.0) && (0..<board.size).contains($0.1) }
            .map { BoardPosition($0.0, $0.1) }
    }

    mutating func toggleDeadGroup(at point: BoardPosition) {
        guard !isFinal, let color = board.stones[point] else { return }
        var group: Set<BoardPosition> = [point]
        var stack = [point]
        while let p = stack.popLast() {
            for q in neighbors(p) where board.stones[q] == color && group.insert(q).inserted { stack.append(q) }
        }
        if deadStones.contains(point) { deadStones.subtract(group) }
        else { deadStones.formUnion(group) }
    }

    var regions: [Region] {
        let living = board.stones.filter { !deadStones.contains($0.key) }
        var visited: Set<BoardPosition> = []
        var result: [Region] = []
        for row in 0..<board.size { for col in 0..<board.size {
            let start = BoardPosition(row, col)
            guard living[start] == nil, visited.insert(start).inserted else { continue }
            var stack = [start], points: Set<BoardPosition> = [start], boundary: Set<Stone> = []
            while let point = stack.popLast() {
                for next in neighbors(point) {
                    if let color = living[next] { boundary.insert(color) }
                    else if visited.insert(next).inserted { points.insert(next); stack.append(next) }
                }
            }
            result.append(Region(points: points, owner: boundary.count == 1 ? boundary.first : nil))
        } }
        return result
    }

    mutating func toggleNeutralArea(at point: BoardPosition) {
        guard !isFinal, let region = regions.first(where: { $0.points.contains(point) }), region.owner != nil else { return }
        if neutralPoints.isDisjoint(with: region.points) { neutralPoints.formUnion(region.points) }
        else { neutralPoints.subtract(region.points) }
    }

    var territory: [BoardPosition: Stone] {
        var points: [BoardPosition: Stone] = [:]
        for region in regions where neutralPoints.isDisjoint(with: region.points) {
            if let owner = region.owner { for point in region.points { points[point] = owner } }
        }
        return points
    }

    var result: LocalScoreResult? {
        guard issue == nil, let komi = Double(komiText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let points = territory
        func side(_ color: Stone) -> LocalScoreResult.Side {
            let empty = points.values.filter { $0 == color }.count
            let living = board.stones.filter { $0.value == color && !deadStones.contains($0.key) }.count
            let captured = color == .black ? capturesByBlack : capturesByWhite
            let dead = deadStones.filter { board.stones[$0] == color.opponent }.count
            let compensation = color == .white ? komi : 0
            let bonus = color == .white ? (handicapBonusOverride ?? rule.handicapBonus(handicap)) : 0
            let total = Double(empty + (rule.territoryScoring ? captured + dead : living)) + compensation + bonus
            return .init(territory: empty, livingStones: living, captured: captured, markedDead: dead,
                         komi: compensation, handicap: bonus, total: total)
        }
        return LocalScoreResult(black: side(.black), white: side(.white), territory: points)
    }
}
