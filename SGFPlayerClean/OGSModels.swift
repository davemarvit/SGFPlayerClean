//
//  OGSModels.swift
//  SGFPlayerClean
//
//  Created: 2025-11-24
//  Updated: 2025-12-02 (Added Automatch Payloads)
//  Purpose: Data models for OGS API responses
//

import Foundation

/// Represents an available game/challenge on OGS
struct OGSChallenge: Codable, Identifiable, Hashable {
    let id: Int
    let challenger: ChallengerInfo
    let game: GameInfo
    let challengerColor: String
    let minRanking: Int
    let maxRanking: Int
    let created: String?

    var boardSize: String {
        "\(game.width)×\(game.height)"
    }

    // Helper to extract the raw JSON parameters once
    private var timeParams: [String: Any]? {
        guard let params = game.timeControlParameters,
              let data = params.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Robust category detection for filtering (Live vs Correspondence)
    var speedCategory: String {
        if let json = timeParams, let speed = json["speed"] as? String {
            return speed // "blitz", "live", "correspondence"
        }
        // Fallback checks
        let tc = (game.timeControl ?? "").lowercased()
        if tc.contains("simple") || tc.contains("correspondence") { return "correspondence" }
        return "live"
    }

    /// Detailed human-readable time string (e.g., "10m + 5x30s")
    var timeControlDisplay: String {
        guard let json = timeParams else { return game.timeControl?.capitalized ?? "Unknown" }
        
        let system = json["system"] as? String ?? ""
        
        if system == "byoyomi" {
            let mainTime = json["main_time"] as? Int ?? 0
            let periods = json["periods"] as? Int ?? 0
            let periodTime = json["period_time"] as? Int ?? 0
            return "\(mainTime/60)m + \(periods)x\(periodTime)s"
        }
        else if system == "fischer" {
            let initialTime = json["initial_time"] as? Int ?? 0
            let increment = json["time_increment"] as? Int ?? 0
            return "\(initialTime/60)m + \(increment)s"
        }
        else if system == "simple" {
            let perMove = json["per_move"] as? Int ?? 0
            if perMove > 3600 {
                return "\(perMove/3600)h / move"
            }
            return "\(perMove)s / move"
        }
        
        return (json["speed"] as? String ?? "Unknown").capitalized
    }

    // Hashable conformance for SwiftUI Lists
    static func == (lhs: OGSChallenge, rhs: OGSChallenge) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    enum CodingKeys: String, CodingKey {
        case id, challenger, game, created
        case challengerColor = "challenger_color"
        case minRanking = "min_ranking"
        case maxRanking = "max_ranking"
    }
}

struct ChallengerInfo: Codable, Hashable {
    let id: Int
    let username: String
    let ranking: Double
    let professional: Bool

    var displayRank: String {
        let rank = Int(round(ranking))
        if rank < 30 {
            return "\(30 - rank)k"
        } else {
            return "\(rank - 29)d"
        }
    }
}

struct GameInfo: Codable, Hashable {
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
    let black: Int?
    let white: Int?
    let started: String? // OGS sends ISO string or nil
    let blackLost: Bool
    let whiteLost: Bool
    let annulled: Bool

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

struct OGSChallengesResponse: Codable {
    let results: [OGSChallenge]
    let count: Int
    let next: String?
    let previous: String?
}

// MARK: - Automatch Payloads

/// The structure sent to "automatch/find_match"
struct AutomatchPayload: Codable {
    let uuid: String
    let size_speed_options: [SizeSpeedOption]
    let lower_rank_diff: Int
    let upper_rank_diff: Int
    let rules: ConditionValue
    let handicap: ConditionValue

    // Quick init for standard settings (19x19 Live Japanese)
    static func standard(uuid: String = UUID().uuidString) -> AutomatchPayload {
        return AutomatchPayload(
            uuid: uuid,
            size_speed_options: [
                SizeSpeedOption(size: "19x19", speed: "live", system: "byoyomi")
            ],
            lower_rank_diff: -3,
            upper_rank_diff: 3,
            rules: ConditionValue(condition: "required", value: "japanese"),
            handicap: ConditionValue(condition: "no-preference", value: "disabled")
        )
    }
}

struct SizeSpeedOption: Codable {
    let size: String   // "19x19", "13x13", "9x9"
    let speed: String  // "live", "blitz", "correspondence"
    let system: String // "byoyomi", "simple", "fischer"
}

struct ConditionValue: Codable {
    let condition: String // "required", "no-preference"
    let value: String     // "japanese", "chinese", "disabled"
}

/// The response received from "automatch/start"
struct AutomatchStart: Codable {
    let game_id: Int
    let uuid: String?
}
