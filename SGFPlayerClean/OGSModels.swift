//
//  OGSModels.swift
//  SGFPlayerClean
//
//  v3.116: Persistence Update.
//  - Made ChallengeSetup Codable for saving settings.
//  - Added save() and load() helpers using UserDefaults.
//

import Foundation

// MARK: - Challenge Creation Configuration
struct ChallengeSetup: Codable {
    var name: String = "Friendly Match"
    var size: Int = 19
    var rules: String = "japanese"
    var ranked: Bool = true
    var handicap: Int = 0 // 0=None, 2-9
    var color: String = "automatic"
    var minRank: Int = 0  // 30k
    var maxRank: Int = 38 // 9d
    
    var timeControl: String = "byoyomi"
    
    var mainTime: Int = 600
    var periods: Int = 5
    var periodTime: Int = 30
    var initialTime: Int = 600
    var increment: Int = 30
    var maxTime: Int = 1200
    var perMove: Int = 30
    
    // API Payload
    func toDictionary() -> [String: Any] {
        var tcParams: [String: Any] = [:]
        switch timeControl {
        case "byoyomi": tcParams = ["system": "byoyomi", "time_control": "byoyomi", "main_time": mainTime, "period_time": periodTime, "periods": periods]
        case "fischer": tcParams = ["system": "fischer", "time_control": "fischer", "initial_time": initialTime, "time_increment": increment, "max_time": maxTime]
        case "simple":  tcParams = ["system": "simple",  "time_control": "simple",  "per_move": perMove]
        default:        tcParams = ["system": "none",    "time_control": "none"]
        }
        
        return [
            "game": [
                "name": name, "rules": rules, "ranked": ranked, "width": size, "height": size,
                "time_control": timeControl, "time_control_parameters": tcParams,
                "handicap": handicap, "disable_analysis": false
            ],
            "challenger_color": color, "min_ranking": minRank, "max_ranking": maxRank
        ]
    }
    
    // Persistence
    static func load() -> ChallengeSetup {
        if let data = UserDefaults.standard.data(forKey: "OGSChallengeSetup"),
           let decoded = try? JSONDecoder().decode(ChallengeSetup.self, from: data) {
            return decoded
        }
        return ChallengeSetup()
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "OGSChallengeSetup")
        }
    }
}

// MARK: - Models
struct OGSChallenge: Codable, Identifiable, Hashable {
    let id: Int
    let challenger: ChallengerInfo
    let game: GameInfo
    let challengerColor: String
    let minRanking: Int
    let maxRanking: Int
    let created: String?

    var boardSize: String { "\(game.width)×\(game.height)" }
    var speedCategory: String {
        if let speed = game.timeControlParameters?.speed { return speed }
        let tc = (game.timeControl ?? "").lowercased()
        return (tc.contains("simple") || tc.contains("correspondence")) ? "correspondence" : "live"
    }
    var timeControlDisplay: String {
        guard let params = game.timeControlParameters else { return game.timeControl?.capitalized ?? "?" }
        let system = params.system ?? params.time_control ?? "unknown"
        func fmt(_ sec: Int?) -> String {
            guard let s = sec else { return "-" }
            if s == 0 { return "0s" }
            if s >= 86400 { return "\(s/86400)d" }
            if s >= 3600 { return "\(s/3600)h\((s%3600)/60)m" }
            if s >= 60 { return "\(s/60)m\(s%60)s" }
            return "\(s)s"
        }
        switch system {
        case "byoyomi": return "\(fmt(params.main_time)) + \(params.periods ?? 0)x\(fmt(params.period_time))"
        case "fischer": return "\(fmt(params.initial_time)) + \(fmt(params.time_increment))"
        case "simple": return "\(fmt(params.per_move)) / move"
        case "canadian": return "\(fmt(params.main_time)) + \(params.stones_per_period ?? 25)/\(fmt(params.period_time))"
        case "absolute": return fmt(params.total_time)
        default: return system.capitalized
        }
    }
    static func == (lhs: OGSChallenge, rhs: OGSChallenge) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ChallengerInfo: Codable, Hashable {
    let id: Int; let username: String; let ranking: Double?; let professional: Bool
    var displayRank: String {
        guard let r = ranking else { return "?" }
        let rank = Int(round(r)); return rank < 30 ? "\(30 - rank)k" : "\(rank - 29)d"
    }
}

struct TimeControlParams: Codable, Hashable {
    let speed: String?; let system: String?; let time_control: String?; let pause_on_weekends: Bool?
    let main_time: Int?; let period_time: Int?; let periods: Int?; let stones_per_period: Int?
    let initial_time: Int?; let time_increment: Int?; let max_time: Int?
    let per_move: Int?; let total_time: Int?
}

struct GameInfo: Codable, Hashable {
    let id: Int; let name: String?; let width: Int; let height: Int
    let rules: String; let ranked: Bool; let handicap: Int; let komi: String?
    let timeControl: String?; let timeControlParameters: TimeControlParams?
    let disableAnalysis: Bool; let started: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, width, height, rules, ranked, handicap, komi, started
        case timeControl = "time_control", timeControlParameters = "time_control_parameters", disableAnalysis = "disable_analysis"
    }
}

struct OGSChallengesResponse: Codable { let results: [OGSChallenge] }

struct AutomatchPayload: Codable {
    let uuid: String; let size_speed_options: [SizeSpeedOption]
    let lower_rank_diff: Int; let upper_rank_diff: Int
    let rules: ConditionValue; let handicap: ConditionValue
    static func standard(uuid: String = UUID().uuidString) -> AutomatchPayload {
        return AutomatchPayload(uuid: uuid, size_speed_options: [SizeSpeedOption(size: "19x19", speed: "live", system: "byoyomi")], lower_rank_diff: -3, upper_rank_diff: 3, rules: ConditionValue(condition: "required", value: "japanese"), handicap: ConditionValue(condition: "no-preference", value: "disabled"))
    }
}
struct SizeSpeedOption: Codable { let size: String; let speed: String; let system: String }
struct ConditionValue: Codable { let condition: String; let value: String }
struct AutomatchStart: Codable { let game_id: Int; let uuid: String? }
