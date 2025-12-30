import Foundation

/// Represents an available game/challenge on OGS
struct OGSChallenge: Codable, Identifiable {
    let id: Int
    let challenger: ChallengerInfo
    let game: GameInfo
    let challengerColor: String
    let minRanking: Int
    let maxRanking: Int
    let created: String?  // ISO 8601 timestamp when challenge was created

    var boardSize: String {
        "\(game.width)×\(game.height)"
    }

    var timeControlDisplay: String {
        // Try to parse the time_control_parameters JSON string
        guard let params = game.timeControlParameters,
              let data = params.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return game.timeControl ?? "Unknown"
        }

        // Extract speed
        if let speed = json["speed"] as? String {
            return speed.capitalized
        }

        return game.timeControl ?? "Unknown"
    }

    enum CodingKeys: String, CodingKey {
        case id, challenger, game, created
        case challengerColor = "challenger_color"
        case minRanking = "min_ranking"
        case maxRanking = "max_ranking"
    }
}

/// Information about the player who created the challenge
struct ChallengerInfo: Codable {
    let id: Int
    let username: String
    let ranking: Double
    let professional: Bool

    var displayRank: String {
        // Convert OGS ranking to traditional kyu/dan
        // Ranking around 30 = 1d, 20 = 10k, etc.
        let rank = Int(round(ranking))
        if rank < 30 {
            let kyu = 30 - rank
            return "\(kyu)k"
        } else {
            let dan = rank - 29
            return "\(dan)d"
        }
    }
}

/// Game information within a challenge
struct GameInfo: Codable {
    let id: Int
    let name: String?
    let width: Int
    let height: Int
    let rules: String
    let ranked: Bool
    let handicap: Int
    let komi: String?
    let timeControl: String?
    let timeControlParameters: String?
    let disableAnalysis: Bool
    let pauseOnWeekends: Bool
    let black: Int?  // Player ID of black player (null if not accepted yet)
    let white: Int?  // Player ID of white player (null if not accepted yet)
    let started: String?  // Timestamp when game started (null if not started)
    let blackLost: Bool  // True if black lost/abandoned (challenge expired)
    let whiteLost: Bool  // True if white lost/abandoned (challenge expired)
    let annulled: Bool  // True if game was cancelled/annulled

    enum CodingKeys: String, CodingKey {
        case id, name, width, height, rules, ranked, handicap, komi, black, white, started, annulled
        case timeControl = "time_control"
        case timeControlParameters = "time_control_parameters"
        case disableAnalysis = "disable_analysis"
        case pauseOnWeekends = "pause_on_weekends"
        case blackLost = "black_lost"
        case whiteLost = "white_lost"
    }
}

/// Response from the challenges list endpoint
struct OGSChallengesResponse: Codable {
    let results: [OGSChallenge]
    let count: Int
    let next: String?
    let previous: String?
}
