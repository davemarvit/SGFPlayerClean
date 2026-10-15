import Foundation

/// A submission is not confirmation; only matching OGS acceptance data confirms it.
enum OGSScoreAcceptance: Equatable {
    case none, updating, submitting, confirmed, resuming
}

enum OGSScoring {
    static func isScoring(_ phase: String?) -> Bool {
        phase == "stone removal" || phase == "scoring"
    }

    /// OGS encodes intersections using a-z, then A-Z. Empty means explicitly no removals.
    static func decodePositions(_ text: String, width: Int = 52, height: Int = 52) -> Set<BoardPosition>? {
        let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let chars = Array(text)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var positions: Set<BoardPosition> = []
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let x = letters.firstIndex(of: chars[i]), let y = letters.firstIndex(of: chars[i + 1]),
                  x < width, y < height else { return nil }
            positions.insert(BoardPosition(y, x))
        }
        return positions
    }

    static func encodePositions(_ positions: Set<BoardPosition>) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return positions.sorted { ($0.row, $0.col) < ($1.row, $1.col) }.compactMap {
            guard (0..<52).contains($0.col), (0..<52).contains($0.row) else { return nil }
            return String([letters[$0.col], letters[$0.row]])
        }.joined()
    }
}

/// Display server totals, rather than treating a local flood fill as a rules-aware score.
struct OGSScoreSummary: Decodable, Equatable {
    let black: PlayerScore
    let white: PlayerScore

    struct PlayerScore: Decodable, Equatable {
        let total: Double
        let territory: Double?
        let stones: Double?
        let prisoners: Double?
        let komi: Double?
        let handicap: Double?
        let scoringPositions: String?

        enum CodingKeys: String, CodingKey {
            case total, territory, stones, prisoners, komi, handicap
            case scoringPositions = "scoring_positions"
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            func number(_ key: CodingKeys) throws -> Double? {
                if !values.contains(key) { return nil }
                if try values.decodeNil(forKey: key) { return nil }
                let result: Double
                if let value = try? values.decode(Double.self, forKey: key) { result = value }
                else if let value = Double(try values.decode(String.self, forKey: key)) { result = value }
                else { throw DecodingError.dataCorruptedError(forKey: key, in: values, debugDescription: "Invalid score") }
                guard result.isFinite else { throw DecodingError.dataCorruptedError(forKey: key, in: values, debugDescription: "Non-finite score") }
                return result
            }
            guard let total = try number(.total) else {
                throw DecodingError.keyNotFound(CodingKeys.total, .init(codingPath: decoder.codingPath, debugDescription: "Missing total"))
            }
            self.total = total
            territory = try number(.territory)
            stones = try number(.stones)
            prisoners = try number(.prisoners)
            komi = try number(.komi)
            handicap = try number(.handicap)
            scoringPositions = try values.decodeIfPresent(String.self, forKey: .scoringPositions)
        }
    }

    static func parse(_ value: Any?) -> OGSScoreSummary? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func winnerDescription(blackName: String?, whiteName: String?) -> String {
        let difference = black.total - white.total
        guard difference != 0 else { return "Draw" }
        let color = difference > 0 ? "Black" : "White"
        let name = (difference > 0 ? blackName : whiteName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let winner = name.flatMap { $0.isEmpty ? nil : $0 }.map { "\($0) \(color)" } ?? color
        let margin = abs(difference).formatted(.number.precision(.fractionLength(0...2)))
        return "\(winner) wins by \(margin) \(abs(difference) == 1 ? "point" : "points")"
    }

    /// nil means unavailable/invalid; an empty dictionary is an authoritative empty overlay.
    func positions(width: Int, height: Int) -> [BoardPosition: Stone]? {
        guard let b = black.scoringPositions, let w = white.scoringPositions,
              let blackPoints = OGSScoring.decodePositions(b, width: width, height: height),
              let whitePoints = OGSScoring.decodePositions(w, width: width, height: height),
              blackPoints.isDisjoint(with: whitePoints) else { return nil }
        var result = Dictionary(uniqueKeysWithValues: blackPoints.map { ($0, Stone.black) })
        for point in whitePoints { result[point] = .white }
        return result
    }
}
