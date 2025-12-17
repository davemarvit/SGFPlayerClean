//
//  OGSModels.swift
//  SGFPlayerClean
//
//  v3.99: Compilation Fix.
//  - Restored 'started' property to GameInfo (Required by OGSBrowserView).
//  - Maintains clean structure for Socket Adapter.
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

    var speedCategory: String {
        if let speed = game.timeControlParameters?.speed { return speed }
        let tc = (game.timeControl ?? "").lowercased()
        if tc.contains("simple") || tc.contains("correspondence") { return "correspondence" }
        return "live"
    }

    var timeControlDisplay: String {
        return game.timeControl ?? "Unknown"
    }

    static func == (lhs: OGSChallenge, rhs: OGSChallenge) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ChallengerInfo: Codable, Hashable {
    let id: Int
    let username: String
    let ranking: Double?
    let professional: Bool

    var displayRank: String {
        guard let r = ranking else { return "?" }
        let rank = Int(round(r))
        if rank < 30 { return "\(30 - rank)k" }
        else { return "\(rank - 29)d" }
    }
}

struct TimeControlParams: Codable, Hashable {
    let speed: String?
    let system: String?
    let time_control: String?
    let pause_on_weekends: Bool?
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
    let timeControlParameters: TimeControlParams?
    let disableAnalysis: Bool
    
    // v3.99 FIX: Restored this property
    let started: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, width, height, rules, ranked, handicap, komi, started
        case timeControl = "time_control"
        case timeControlParameters = "time_control_parameters"
        case disableAnalysis = "disable_analysis"
    }
}

struct OGSChallengesResponse: Codable {
    let results: [OGSChallenge]
}

// MARK: - Automatch Payloads

struct AutomatchPayload: Codable {
    let uuid: String
    let size_speed_options: [SizeSpeedOption]
    let lower_rank_diff: Int
    let upper_rank_diff: Int
    let rules: ConditionValue
    let handicap: ConditionValue

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
    let size: String
    let speed: String
    let system: String
}

struct ConditionValue: Codable {
    let condition: String
    let value: String
}

struct AutomatchStart: Codable {
    let game_id: Int
    let uuid: String?
}
