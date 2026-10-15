// MARK: - File: OGSModels.swift (v4.246)
import Foundation
import CoreFoundation
import SwiftUI

// MARK: - Core Go Models
enum Stone: String, Codable, CaseIterable {
    case black, white
    var opponent: Stone { self == .black ? .white : .black }
}

struct BoardPosition: Hashable, Codable {
    let row, col: Int
    init(_ row: Int, _ col: Int) { self.row = row; self.col = col }
}

struct BoardSnapshot: Equatable {
    let size: Int; let grid: [[Stone?]]; let stones: [BoardPosition: Stone]
}

struct MoveRef: Equatable { let color: Stone; let x, y: Int }

struct RenderStone: Identifiable, Equatable {
    let id: BoardPosition; let color: Stone; let offset: CGPoint
    var isDead: Bool = false
}

// MARK: - OGS Network & Lobby Models
/// A public game already in progress, not an open challenge.
struct OGSObservedGame: Identifiable {
    let id: Int
    let blackName: String
    let whiteName: String
    let boardSize: String

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int, id > 0,
              json["phase"] as? String != "finished",
              json["ended"] == nil || json["ended"] is NSNull else { return nil }
        self.id = id
        let players = json["players"] as? [String: Any]
        let black = (json["black"] ?? players?["black"]) as? [String: Any]
        let white = (json["white"] ?? players?["white"]) as? [String: Any]
        blackName = black?["username"] as? String ?? "Black"
        whiteName = white?["username"] as? String ?? "White"
        if let width = json["width"] as? Int, let height = json["height"] as? Int,
           width > 0, height > 0 {
            boardSize = "\(width)×\(height)"
        } else { boardSize = "" }
    }
}

struct NetworkLogEntry: Identifiable { let id = UUID(); let timestamp = Date(); let direction, content: String; let isHeartbeat: Bool }

struct OGSChatMessage: Identifiable, Equatable, Hashable {
    let id = UUID()
    let timestamp: Date
    let sender: String
    let message: String
    let isSelf: Bool
    
    // To support various chat types (Main, Malkovich, etc - for now "Main" driven)
    // To support various chat types (Main, Malkovich, etc - for now "Main" driven)
    var type: String = "main"
    var moveNumber: Int?
}

struct ChallengerInfo: Codable, Hashable {
    let id: Int; let username: String; let ranking: Double?; let professional: Bool?
    var displayRank: String { ChallengeHelpers.formatRank(ranking ?? 0) }
}
struct ChallengeGameInfo: Codable, Hashable { let ranked: Bool?; let width, height: Int; let rules: String? }
struct TimeParameters: Codable, Hashable {
    let time_control: String?; let main_time: Int?; let initial_time: Int?
    let periods: Int?; let period_time: Int?
    let time_increment: Int?; let increment: Int?
    let stones_per_period: Int?
    let per_move: Int?
    let speed: String? // Authoritative classification from Server
}

struct OGSChallenge: Identifiable, Decodable {
    let id: Int; let name: String?; let challenger: ChallengerInfo?; let game: ChallengeGameInfo?; let time_per_move: Int?
    let time_control: String?
    let time_control_parameters: TimeParameters?
    let min_rank: Int?; let max_rank: Int?
    let process_id: Int? // For tracking specific process/node on server
    let game_started: Bool? // Critical for filtering zombies from REST
    let phase: String? // "play", "finished", etc
    let outcome: String?
    let speed: String? // "live", "blitz", "correspondence"
    let game_id: Int? // Added for duplicate detection
    
    enum CodingKeys: String, CodingKey { case id, challenge_id, game_id, name, user_id, username, ranking, rank, professional, width, height, ranked, rules, time_per_move, black, white, challenger, time_control, time_control_parameters, min_rank, max_rank, process_id, game_started, phase, outcome, speed }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.game_id = try? c.decode(Int.self, forKey: .game_id)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? (try? c.decode(Int.self, forKey: .challenge_id)) ?? (self.game_id) ?? 0
        self.name = try? c.decode(String.self, forKey: .name); self.time_per_move = try? c.decode(Int.self, forKey: .time_per_move)
        
        self.time_control = try? c.decode(String.self, forKey: .time_control)
        self.time_control_parameters = try? c.decode(TimeParameters.self, forKey: .time_control_parameters)
        
        if c.contains(.black) || c.contains(.white) {
            self.challenger = (try? c.decode(ChallengerInfo.self, forKey: .black)) ?? (try? c.decode(ChallengerInfo.self, forKey: .white))
        } else if c.contains(.challenger) {
             self.challenger = try? c.decode(ChallengerInfo.self, forKey: .challenger)
        } else {
            let rankDouble = (try? c.decode(Double.self, forKey: .ranking)) ?? (try? c.decode(Double.self, forKey: .rank))
            let rankInt = (try? c.decode(Int.self, forKey: .ranking)) ?? (try? c.decode(Int.self, forKey: .rank))
            let finalRank = rankDouble ?? (rankInt.map { Double($0) })
            
            let profBool = try? c.decode(Bool.self, forKey: .professional)
            let profInt = try? c.decode(Int.self, forKey: .professional)
            let isProf = profBool ?? (profInt == 1)
            
            self.challenger = ChallengerInfo(id: (try? c.decode(Int.self, forKey: .user_id)) ?? 0, username: (try? c.decode(String.self, forKey: .username)) ?? "Unknown", ranking: finalRank, professional: isProf)
        }
        
        let rankedBool = try? c.decode(Bool.self, forKey: .ranked)
        let rankedInt = try? c.decode(Int.self, forKey: .ranked)
        let isRanked = rankedBool ?? (rankedInt == 1)
        
        
        self.min_rank = try? c.decode(Int.self, forKey: .min_rank)
        self.max_rank = try? c.decode(Int.self, forKey: .max_rank)
        self.process_id = try? c.decode(Int.self, forKey: .process_id)
        self.game_started = try? c.decode(Bool.self, forKey: .game_started)
        self.phase = try? c.decode(String.self, forKey: .phase)
        self.outcome = try? c.decode(String.self, forKey: .outcome)
        self.speed = try? c.decode(String.self, forKey: .speed)
        
        self.game = ChallengeGameInfo(ranked: isRanked, width: (try? c.decode(Int.self, forKey: .width)) ?? 19, height: (try? c.decode(Int.self, forKey: .height)) ?? 19, rules: try? c.decode(String.self, forKey: .rules))
    }
    var boardSize: String { "\(game?.width ?? 19)x\(game?.height ?? 19)" }
    var speedCategory: String {
        // 1. Authoritative: Use server tag if available
        if let s = time_control_parameters?.speed { return s }
        
        // 2. Fallback: Heuristic
        guard let tpm = time_per_move else { return "live" }
        return tpm < 30 ? "blitz" : (tpm >= 3600 ? "correspondence" : "live")
    }
    var formattedTimeControl: String {
        return ChallengeHelpers.formatTimeControl(tc: time_control, params: time_control_parameters, perMove: time_per_move)
    }
    
    // Legacy support
    var timeControlDisplay: String { formattedTimeControl }
}

struct ChallengeHelpers {
    static func formatRank(_ r: Double) -> String {
        let rank = Int(floor(r))
        return rank < 30 ? "\(30 - rank)k" : "\(rank - 29)d"
    }
    static func flagEmoji(for code: String?) -> String {
        guard let code = code, code.count == 2 else { return "" }
        let base: UInt32 = 127397
        var s = ""
        for sScalar in code.uppercased().unicodeScalars {
            s.unicodeScalars.append(UnicodeScalar(base + sScalar.value)!)
        }
        return s
    }
    
    static func formatTimeControl(tc: String?, params: TimeParameters?, perMove: Int?) -> String {
        let sys = tc ?? "byoyomi"
        
        // Helper: Seconds to "10m" or "30s" or "1h"
        func fmt(_ sec: Int) -> String {
            if sec >= 3600 { return "\(sec/3600)h" }
            if sec >= 60 { return "\(sec/60)m" }
            return "\(sec)s"
        }
        
        // If we have detailed params
        if let p = params {
            if let main = p.main_time ?? p.initial_time {
                 let mainStr = fmt(main)
                 
                 if sys == "byoyomi" {
                     let periods = p.periods ?? 5
                     let pTime = p.period_time ?? 30
                     return "\(mainStr) + \(periods)x\(fmt(pTime))"
                 }
                 
                 if sys == "fischer" {
                     let inc = p.time_increment ?? p.increment ?? 0
                     return "\(mainStr) + \(fmt(inc))"
                 }
                 
                 if sys == "canadian" {
                     let stones = p.stones_per_period ?? 25
                     let pTime = p.period_time ?? 600
                     return "\(mainStr) + \(fmt(pTime))/\(stones)"
                 }
                 
                 if sys == "simple" {
                    let perMove = p.per_move ?? 0
                    return "\(mainStr)/\(fmt(perMove))"
                 }
                 
                 if sys == "absolute" { return "\(mainStr)" }
            }
        }
        
        // Fallback if no params but we have time_per_move (Legacy Blitz/Live logic)
        if let tpm = perMove {
            if tpm == 0 { return "None" }
            return tpm < 60 ? "\(tpm)s/mv" : "\(tpm/60)m/mv"
        }
        
        return "Live"
    }
}

// MARK: - SGF Parser & Game Models
struct SGFNode { var props: [String:[String]] }
/// Complete tree for the first game in a collection. Branch indices avoid recursive
/// traversal/storage limits in files that wrap every move in its own continuation.
struct SGFTree {
    struct Branch {
        var sequence: [SGFNode] = []
        var children: [Int] = []
    }
    let branches: [Branch] // Root is index 0; children retain their file order.

    /// Default playback policy only. Alternatives and all their properties remain stored.
    var mainLineNodes: [SGFNode] {
        var result: [SGFNode] = []
        var index: Int? = branches.isEmpty ? nil : 0
        while let current = index {
            result.append(contentsOf: branches[current].sequence)
            index = branches[current].children.first
        }
        return result
    }
}
enum SGFError: Error { case parseError(String) }

enum SGFParser {
    /// Retain every branch and property; choosing a playback path is a separate step.
    static func parse(text: String) throws -> SGFTree {
        let s = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var i = s.startIndex
        func peek() -> Character? { i < s.endIndex ? s[i] : nil }
        func advance() { if i < s.endIndex { i = s.index(after: i) } }
        func skipWS() { while let c = peek(), c.isWhitespace { advance() } }
        func parseNode() throws -> SGFNode {
            var props: [String: [String]] = [:]
            skipWS()
            while let c = peek(), c.isLetter {
                let start = i
                while let c = peek(), c.isLetter { advance() }
                let key = String(s[start..<i]).uppercased()
                var values: [String] = []
                skipWS()
                guard peek() == "[" else { throw SGFError.parseError("Missing value for \(key)") }
                while peek() == "[" {
                    advance()
                    var value = ""
                    var closed = false
                    while let c = peek() {
                        advance()
                        if c == "\\" {
                            guard let escaped = peek() else { break }
                            advance()
                            // An escaped line break continues the value without a newline.
                            if escaped != "\n" { value.append(escaped) }
                        } else if c == "]" {
                            closed = true
                            break
                        } else {
                            value.append(c)
                        }
                    }
                    guard closed else { throw SGFError.parseError("Unterminated value for \(key)") }
                    values.append(value)
                    skipWS()
                }
                props[key] = values
            }
            return SGFNode(props: props)
        }

        // Read every branch, including siblings. Parentheses inside values are text.
        var branches: [SGFTree.Branch] = []
        var stack: [Int] = []
        if peek() == "\u{FEFF}" { advance() }
        skipWS()
        guard peek() == "(" else { throw SGFError.parseError("Missing '('") }
        while let c = peek() {
            switch c {
            case "(":
                let child = branches.count
                if let parent = stack.last {
                    guard !branches[parent].sequence.isEmpty else { throw SGFError.parseError("Empty game tree") }
                    branches[parent].children.append(child)
                }
                branches.append(SGFTree.Branch())
                stack.append(child)
                advance()
            case ";":
                guard let current = stack.last, branches[current].children.isEmpty else {
                    throw SGFError.parseError("Move sequence after variations")
                }
                advance()
                branches[current].sequence.append(try parseNode())
            case ")":
                guard let current = stack.popLast(), !branches[current].sequence.isEmpty else {
                    throw SGFError.parseError("Empty game tree")
                }
                advance()
                // Preserve the existing one-game-per-file playback policy for collections.
                if stack.isEmpty { return SGFTree(branches: branches) }
            default:
                throw SGFError.parseError("Unexpected character outside a property value")
            }
            skipWS()
        }
        throw SGFError.parseError("Unterminated game tree")
    }
}

struct SGFGame {
    // Retain the imported tree for future variation navigation/editing. Local played moves
    // change the playback history, not this source record; no SGF writer is implied.
    var sourceTree: SGFTree?
    struct Info { var event, playerBlack, playerWhite, blackRank, whiteRank, result, date, komi, rules: String? }
    var boardSize: Int = 19; var info: Info = .init(); var setup: [(Stone, Int, Int)] = []; var moves: [(Stone, (Int,Int)?)] = []
    var initialPlayer: Stone?
    var handicap = 0
    var freeHandicapPlacement = false
    var analysisOnline = false
    var whiteHandicapBonus: String?
    var ruleOverrides: GoRuleOverrides?
    var analysisSettings: GameAnalysisSettings {
        GameAnalysisSettings(rules: info.rules, komi: info.komi.map { Double($0) ?? .nan },
            initialPlayer: initialPlayer ?? moves.first?.0 ?? (handicap > 1 ? .white : .black),
            online: analysisOnline, whiteHandicapBonus: whiteHandicapBonus, ruleOverrides: ruleOverrides)
    }
    static func from(tree: SGFTree) -> SGFGame {
        var g = SGFGame()
        g.sourceTree = tree
        for node in tree.mainLineNodes {
            for (k, vals) in node.props {
                switch k {
                case "SZ": if let v = vals.first { g.boardSize = Int(v.components(separatedBy: ":").first ?? "19") ?? 19 }
                case "PB": g.info.playerBlack = vals.first
                case "PW": g.info.playerWhite = vals.first
                case "BR": g.info.blackRank = vals.first
                case "WR": g.info.whiteRank = vals.first
                case "RE": g.info.result = vals.first
                case "DT": g.info.date = vals.first
                case "KM": g.info.komi = vals.first
                case "RU": g.info.rules = vals.first
                case "HA": g.handicap = Int(vals.first ?? "") ?? 0
                case "PL": g.initialPlayer = vals.first == "W" ? .white : .black
                case "EV": g.info.event = vals.first
                case "AB": for v in vals { if let (x,y) = SGFCoordinates.parse(v) { g.setup.append((.black, x, y)) } }
                case "AW": for v in vals { if let (x,y) = SGFCoordinates.parse(v) { g.setup.append((.white, x, y)) } }
                case "B": g.moves.append((.black, SGFCoordinates.parse(vals.first ?? "")))
                case "W": g.moves.append((.white, SGFCoordinates.parse(vals.first ?? "")))
                default: continue
                }
            }
        }
        return g
    }
}

struct SGFGameWrapper: Identifiable, Hashable {
    let id = UUID(); let url: URL; let game: SGFGame
    var title: String? { if let e = game.info.event, !e.isEmpty { return e }; return url.lastPathComponent }
    static func == (l: SGFGameWrapper, r: SGFGameWrapper) -> Bool { l.id == r.id }; func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - UI & Settings Models
struct GameInfo: Codable, Hashable { let id: Int; let name: String?; let width, height: Int; let rules: String; let ranked: Bool; let handicap: Int; let komi: String?; let started: String? }
enum ViewMode: String, CaseIterable, Identifiable { case view2D = "2D", view3D = "3D"; var id: String { rawValue } }
enum OGSBrowserTab: String, CaseIterable { case challenge = "Challenge", watch = "Watch" }
enum BoardSizeCategory: String, CaseIterable, Identifiable { case size19 = "19", size13 = "13", size9 = "9", other = "Other"; var id: String { rawValue } }
enum GameSpeedFilter: String, CaseIterable, Identifiable { case all = "All Speeds", realTime = "Real Time (Live+Blitz)", live = "Live", blitz = "Blitz", correspondence = "Correspondence"; var id: String { rawValue } }

struct ChallengeSetup: Codable {
    var name = "Friendly Match"; var size = 19; var rules = "japanese"; var ranked = true
    var handicap = 0; var color = "automatic"; var minRank = 0; var maxRank = 38
    var timeControl = "byoyomi"; var mainTime = 600; var periods = 5; var periodTime = 30
    var initialTime = 600; var increment = 30; var maxTime = 1200; var perMove = 30
    
    func toDictionary() -> [String: Any] {
        // Based on Verified Web Payload (Step 376)
        
        // Time Control Parameters (Nested & Redundant)
        // Web sends: { per_move: 15, pause_on_weekends: false, speed: "live", system: "simple", time_control: "simple" }
        var tcParams: [String: Any] = [:]
        
        // Infer Speed (heuristic)
        var speed = "live"
        if perMove < 20 { speed = "blitz" }
        else if mainTime < 600 { speed = "blitz" }
        
        if timeControl == "byoyomi" {
            tcParams = [
                "main_time": mainTime,
                "periods": periods,
                "period_time": periodTime,
                "speed": speed,
                "system": "byoyomi",
                "time_control": "byoyomi"
            ]
        } else if timeControl == "fischer" {
            tcParams = [
                "initial_time": initialTime,
                "time_increment": increment,
                "max_time": maxTime,
                "speed": speed,
                "system": "fischer",
                "time_control": "fischer"
            ]
        } else if timeControl == "simple" {
            tcParams = [
                "per_move": perMove,
                "pause_on_weekends": false,
                "speed": speed,
                "system": "simple",
                "time_control": "simple"
            ]
        }
        
        let finalColor = (color == "automatic") ? "automatic" : color // Payload showed "automatic"
        
        // Inner Game Object
        // Payload: { handicap: -1, time_control: "simple", rules: "japanese", ranked: false, width: 19, height: 19 ... }
        let gameObj: [String: Any] = [
            "handicap": (handicap == 0) ? 0 : handicap, // Use 0 for "None", -1 for "Auto" if supported (payload said -1, but 500 happened. Let's stick to Safe 0 or User choice)
            "time_control": timeControl,
            "rules": rules,
            "ranked": ranked,
            "width": size,
            "height": size,
            "disable_analysis": false,
            "initial_state": NSNull(),       // Explicit null from payload
            "komi_auto": "automatic",        // From Payload
            "name": name,
            "pause_on_weekends": false,
            "private": false,                // Explicit false
            "rengo": false,
            "time_control_parameters": tcParams
        ]

        // Top Level
        return [
            "game": gameObj,
            "initialized": false,            // From Payload
            "min_ranking": minRank,          
            "max_ranking": maxRank,          
            "challenger_color": finalColor,
            "aga_ranked": false,             // From Payload
            "invite_only": false,
            "rengo_auto_start": 0
        ]
    }
    
    func toAutomatchPayload(playerID: Int, username: String) -> (String, [String: Any]) {
        let uuid = UUID().uuidString.lowercased()
        
        // Infer Speed from Time Control
        // OGS Web has 'blitz', 'rapid', 'live'
        // Simple heuristic mapping
        var speed = "live"
        if perMove < 20 { speed = "blitz" }
        else if mainTime < 600 { speed = "blitz" }
        
        // Construct Size string (e.g. "19x19")
        let sizeStr = "\(size)x\(size)"
        
        // Time Control Value Construction
        let tcValue: [String: Any] = ["system": timeControl, "speed": speed] // Base
        
        // NOTE: The web client sends essentially "Any Logic" in size_speed_options
        // We will target exactly what the user selected.
        let sizeSpeedOption: [String: Any] = [
            "size": sizeStr,
            "speed": speed,
            "system": timeControl
        ]
        
        // Handicap Logic
        let handicapValue = (handicap == -1 || handicap > 0) ? "enabled" : "none"
        
        let prefs: [String: Any] = [
            "uuid": uuid,
            "size_speed_options": [sizeSpeedOption],
            "lower_rank_diff": 5, // Default reasonable
            "upper_rank_diff": 5,
            "rules": ["condition": "required", "value": rules],
            "time_control": ["condition": "required", "value": tcValue],
            "handicap": ["condition": "preferred", "value": handicapValue]
        ]
        
        let payload: [String: Any] = [
            "uuid": uuid,
            "preferences": prefs,
            "player": [
                "id": playerID,
                "username": username
            ]
        ]
        return (uuid, payload)
    }
    
    static func load() -> ChallengeSetup {
        if let data = UserDefaults.standard.data(forKey: "last_challenge_setup"),
           let decoded = try? JSONDecoder().decode(ChallengeSetup.self, from: data) {
            return decoded
        }
        return ChallengeSetup()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "last_challenge_setup")
        }
    }
}

struct SGFCoordinates {
    static func parse(_ s: String) -> (Int, Int)? {
        guard s.count >= 2 else { return nil }; let chars = Array(s.lowercased())
        let x = Int(chars[0].asciiValue ?? 0) - 97; let y = Int(chars[1].asciiValue ?? 0) - 97
        return (x >= 0 && x < 25 && y >= 0 && y < 25) ? (x, y) : nil
    }
    static func toSGF(x: Int, y: Int) -> String { "\(Character(UnicodeScalar(97 + x)!))\(Character(UnicodeScalar(97 + y)!))" }
}

struct KeychainHelper {
    static func save(service: String, account: String, data: Data) -> OSStatus {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service as CFString, kSecAttrAccount: account as CFString, kSecValueData: data]
        SecItemDelete(q as CFDictionary); return SecItemAdd(q as CFDictionary, nil)
    }
    static func load(service: String, account: String) -> Data? {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service as CFString, kSecAttrAccount: account as CFString, kSecReturnData: kCFBooleanTrue!, kSecMatchLimit: kSecMatchLimitOne]
        var item: AnyObject?; let status = SecItemCopyMatching(q as CFDictionary, &item); return status == noErr ? (item as? Data) : nil
    }
}




/// Metadata sent to analysis; missing values retain the old defaults with a visible notice.
struct GameAnalysisSettings: Codable, Equatable {
    var rules: String?
    var komi: Double?
    var initialPlayer: Stone = .black
    var online = false
    var whiteHandicapBonus: String?
    var ruleOverrides: GoRuleOverrides?

    var kataRules: String? {
        let value = (rules ?? "chinese").trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "_", with: "-")
        switch value {
        case "japanese", "japan": return "japanese"
        case "korean", "korea": return "korean"
        case "chinese", "china": return online ? "chinese-ogs" : "chinese"
        case "aga", "bga", "tromp-taylor", "chinese-ogs", "chinese-kgs", "stone-scoring", "aga-button": return value
        case "new zealand", "new-zealand", "nz": return "new-zealand"
        default: return nil
        }
    }
    var playRules: GoRulePolicy? { GoRulePolicy(settings: self) }
    var effectiveKomi: Double { komi ?? 6.5 }
    var analysisRulesSupported: Bool {
        guard kataRules != nil, let actual = playRules else { return false }
        var preset = self
        preset.ruleOverrides = nil
        guard actual == preset.playRules else { return false }
        let territory = ["japanese", "korean"].contains(kataRules ?? "")
        if let value = ruleOverrides?.scoreTerritory, !value { return false }
        if let value = ruleOverrides?.scoreStones, value == territory { return false }
        if let value = ruleOverrides?.scorePrisoners, value != territory { return false }
        if let value = ruleOverrides?.scoreTerritoryInSeki, value == territory { return false }
        return true
    }
    var notice: String? {
        if kataRules == nil { return "Analysis unavailable: unsupported rules ‘\(rules ?? "")’." }
        if !analysisRulesSupported { return "Analysis unavailable: custom rule settings are not supported by this KataGo preset." }
        guard effectiveKomi.isFinite, (-400...400).contains(effectiveKomi), (effectiveKomi * 2).rounded() == effectiveKomi * 2 else {
            return "Analysis unavailable: invalid komi."
        }
        if rules == nil && komi == nil { return "Rules and komi are missing; analysis assumes Chinese rules and 6.5 komi." }
        if rules == nil { return "Rules are missing; analysis assumes Chinese rules." }
        if komi == nil { return "Komi is missing; analysis assumes 6.5 komi." }
        return nil
    }
}

/// Validate a complete OGS history before changing the board, clocks, scoring, or analysis.
struct OGSGameSnapshot {
    let game: SGFGame
    let stateVersion: Int?
    let freeHandicapMoves: Int

    init?(_ data: [String: Any]) {
        func integer(_ value: Any?) -> Int? {
            if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
               number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue {
                return Int(exactly: number.doubleValue)
            }
            if let text = value as? String { return Int(text) }
            return nil
        }
        let width = integer(data["width"]) ?? 19
        let height = integer(data["height"]) ?? width
        guard (2...52).contains(width), width == height, let moves = data["moves"] as? [[Any]] else { return nil }
        var game = SGFGame()
        game.boardSize = width
        game.info.rules = data["rules"] as? String
        if let komi = data["komi"] as? String { game.info.komi = komi }
        else if let komi = data["komi"] as? NSNumber, CFGetTypeID(komi) != CFBooleanGetTypeID() { game.info.komi = komi.stringValue }
        else if let komi = data["komi"], !(komi is NSNull) { game.info.komi = "invalid" }
        let handicap = max(0, integer(data["handicap"]) ?? 0)
        if let setup = data["initial_state"] as? [String: Any] {
            // Truncated histories require initial prisoner and move-number handling; don't silently miscount.
            guard (integer(setup["move_number"]) ?? 0) == 0 else { return nil }
            for color in Stone.allCases {
                guard let points = OGSScoring.decodePositions(setup[color.rawValue] as? String ?? "", width: width, height: height) else { return nil }
                game.setup += points.map { (color, $0.col, $0.row) }
            }
            guard Set(game.setup.map { BoardPosition($0.2, $0.1) }).count == game.setup.count else { return nil }
        }
        let free = data["free_handicap_placement"] as? Bool ?? false
        freeHandicapMoves = free ? handicap : 0
        // Fixed handicap is setup, never additional moves in the numbered history.
        if let player = data["initial_player"] as? String {
            guard let color = Stone(rawValue: player) else { return nil }
            game.initialPlayer = color
        } else { game.initialPlayer = !free && handicap > 1 ? .white : .black }
        game.handicap = handicap
        game.freeHandicapPlacement = free
        var color = game.initialPlayer ?? .black
        for (index, move) in moves.enumerated() {
            guard move.count >= 2, let x = integer(move[0]), let y = integer(move[1]),
                  (x == -1 && y == -1) || ((0..<width).contains(x) && (0..<height).contains(y)) else { return nil }
            // Packed moves carry optional color at index 3 and extra properties at index 4.
            if move.count > 4, let extra = move[4] as? [String: Any], extra["edited"] as? Bool == true { return nil }
            if move.count > 3, let explicit = integer(move[3]), explicit != 0 {
                guard explicit == 1 || explicit == 2 else { return nil }
                color = explicit == 1 ? .black : .white
            }
            if index < freeHandicapMoves { color = .black; guard x >= 0 else { return nil } }
            game.moves.append((color, x == -1 ? nil : (x, y)))
            if index + 1 >= freeHandicapMoves { color = color.opponent }
        }
        game.analysisOnline = true
        game.ruleOverrides = GoRuleOverrides(allowSelfCapture: data["allow_self_capture"] as? Bool,
            allowKo: data["allow_ko"] as? Bool, allowSuperko: data["allow_superko"] as? Bool,
            superkoAlgorithm: data["superko_algorithm"] as? String,
            scoreTerritory: data["score_territory"] as? Bool, scoreStones: data["score_stones"] as? Bool,
            scorePrisoners: data["score_prisoners"] as? Bool, scoreTerritoryInSeki: data["score_territory_in_seki"] as? Bool)
        if let scoreHandicap = data["score_handicap"] as? Bool {
            game.whiteHandicapBonus = scoreHandicap ? ((data["aga_handicap_scoring"] as? Bool == true) ? "N-1" : "N") : "0"
        }
        self.game = game
        stateVersion = integer(data["state_version"])
    }
}

/// Explicit OGS settings take precedence over the rule-set name.
struct GoRuleOverrides: Codable, Equatable {
    var allowSelfCapture: Bool?
    var allowKo: Bool?
    var allowSuperko: Bool?
    var superkoAlgorithm: String?
    var scoreTerritory: Bool?
    var scoreStones: Bool?
    var scorePrisoners: Bool?
    var scoreTerritoryInSeki: Bool?
}

struct GoRulePolicy: Equatable {
    enum Repetition: String { case none, simple, positional, situational }
    var repetition: Repetition
    var allowsSelfCapture: Bool

    init?(settings: GameAnalysisSettings) {
        switch settings.kataRules {
        case "japanese", "korean", "chinese", "stone-scoring":
            repetition = .simple; allowsSelfCapture = false
        case "chinese-ogs", "chinese-kgs":
            repetition = .positional; allowsSelfCapture = false
        case "aga", "bga", "aga-button":
            repetition = .situational; allowsSelfCapture = false
        case "new-zealand": repetition = .situational; allowsSelfCapture = true
        case "tromp-taylor": repetition = .positional; allowsSelfCapture = true
        default: return nil
        }
        if let overrides = settings.ruleOverrides {
            // Allowing immediate ko while separately restricting longer cycles needs a custom
            // repetition policy; do not silently treat that combination as a standard preset.
            if overrides.allowKo == true && overrides.allowSuperko != true { return nil }
            if overrides.allowSuperko == false && repetition == .simple && overrides.superkoAlgorithm == nil { return nil }
            if let suicide = overrides.allowSelfCapture { allowsSelfCapture = suicide }
            if overrides.allowSuperko == true {
                repetition = overrides.allowKo == true ? .none : .simple
            } else if let algorithm = overrides.superkoAlgorithm {
                switch algorithm.lowercased() {
                case "psk", "csk": repetition = .positional
                case "ssk": repetition = .situational
                case "noresult":
                    guard overrides.allowSuperko != false else { return nil }
                    repetition = overrides.allowKo == true ? .none : .simple
                default: return nil
                }
            } else if overrides.allowKo == true && repetition == .simple { repetition = .none }
        }
    }

    var summary: String {
        let ko: String
        switch repetition {
        case .none: ko = "Repetition allowed"
        case .simple: ko = "Simple ko"
        case .positional: ko = "Positional superko"
        case .situational: ko = "Situational superko"
        }
        return ko + (allowsSelfCapture ? " · Self-capture allowed" : " · No self-capture")
    }
}
