// MARK: - File: OGSModels.swift (v4.246)
import Foundation
import CoreFoundation
import SwiftUI

enum AppMode: String, CaseIterable {
    case playOnline = "Play Online", localPlay = "Local Play", observe = "Observe", review = "Review"
    var usesOGS: Bool { self == .playOnline || self == .observe }
}

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
    let blackRank: String
    let whiteRank: String
    let strongestRank: Double?
    let boardSize: String
    let moveCount: Int?
    let timeControl: String?

    init?(json: [String: Any]) {
        let snapshot = json["json"] as? [String: Any] ?? [:]
        guard let id = json["id"] as? Int, id > 0,
              (json["phase"] ?? snapshot["phase"]) as? String != "finished",
              json["ended"] == nil || json["ended"] is NSNull else { return nil }
        self.id = id
        func player(_ color: String) -> [String: Any] {
            // Summary players can contain only a name/ID; retain snapshot ratings.
            var result = (snapshot["players"] as? [String: Any])?[color] as? [String: Any] ?? [:]
            for source in [(json["players"] as? [String: Any])?[color], json[color]] {
                if let details = source as? [String: Any] { result.merge(details) { _, new in new } }
            }
            return result
        }
        let black = player("black"), white = player("white")
        blackName = black["username"] as? String ?? "Black"
        whiteName = white["username"] as? String ?? "White"
        let b = Self.rank(black), w = Self.rank(white)
        blackRank = b.label; whiteRank = w.label
        strongestRank = [b.strength, w.strength].compactMap { $0 }.max()
        if let width = (json["width"] ?? snapshot["width"]) as? Int,
           let height = (json["height"] ?? snapshot["height"]) as? Int, width > 0, height > 0 {
            boardSize = "\(width)×\(height)"
        } else { boardSize = "" }
        if let moves = (snapshot["moves"] ?? json["moves"]) as? [Any] {
            moveCount = moves.count // Includes passes, like the OGS game list.
        } else if let count = json["move_number"] as? Int, count >= 0 {
            moveCount = count
        } else { moveCount = nil }
        timeControl = Self.timeControlDescription(json)
    }

    /// Both live-list snapshots and the REST game detail use this formatter.
    static func timeControlDescription(_ json: [String: Any]) -> String? {
        let snapshot = (json["gamedata"] ?? json["json"]) as? [String: Any] ?? [:]
        func object(_ value: Any?) -> [String: Any]? {
            if let value = value as? [String: Any] { return value }
            // REST also exposes time_control_parameters as a JSON-encoded string.
            if let value = value as? String, let data = value.data(using: .utf8) {
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            return nil
        }
        var parameters = object(snapshot["time_control"])
            ?? object(snapshot["time_control_parameters"])
            ?? object(json["time_control_parameters"])
            ?? object(json["time_control"])
        if parameters?["system"] == nil, parameters?["time_control"] == nil {
            parameters?["system"] = (snapshot["time_control"] as? String) ?? (json["time_control"] as? String)
        }
        return timeControl(parameters)
    }

    /// Compare the stronger player, retaining server order when strengths tie or are unknown.
    static func strongestFirst(_ games: [Self]) -> [Self] {
        games.enumerated().sorted {
            let a = $0.element.strongestRank ?? -.infinity
            let b = $1.element.strongestRank ?? -.infinity
            return a == b ? $0.offset < $1.offset : a > b
        }.map(\.element)
    }

    private static func rank(_ player: [String: Any]?) -> (label: String, strength: Double?) {
        guard let player else { return ("?", nil) }
        let legacy = (player["ranking"] ?? player["rank"]) as? Double
        if let value = legacy, value.isFinite,
           value > 900 || (player["professional"] as? Bool == true || player["pro"] as? Bool == true) {
            let pro = value > 900 ? value - 1036 : value - 36
            guard pro >= 1, pro <= 9 else { return ("?", nil) }
            return ("\(Int(pro))p", 1000 + pro)
        }
        let ratings = player["ratings"] as? [String: Any]
        let overall = ratings?["overall"] as? [String: Any]
        var strength = legacy
        if let rating = overall?["rating"] as? Double, rating.isFinite {
            // OGS overall Glicko rating to rank (rank_utils.ts).
            strength = log(min(6000, max(100, rating)) / 525) * 23.15
        }
        guard let value = strength, value.isFinite, value > -900, value < 900 else { return ("?", nil) }
        let provisional = (overall?["deviation"] as? Double).map { $0 >= 160 } ?? false
        return (provisional ? "?" : ChallengeHelpers.formatRank(value), value)
    }

    private static func timeControl(_ params: [String: Any]?) -> String? {
        guard let p = params, let system = (p["system"] ?? p["time_control"]) as? String else { return nil }
        func seconds(_ keys: String...) -> Int? {
            for key in keys { if let n = p[key] as? Int, n >= 0 { return n } }
            return nil
        }
        func duration(_ s: Int) -> String {
            if s >= 3600 && s % 3600 == 0 { return "\(s / 3600)h" }
            if s >= 60 && s % 60 == 0 { return "\(s / 60)m" }
            return "\(s)s"
        }
        switch system {
        case "byoyomi":
            guard let main = seconds("main_time"), let periods = seconds("periods"),
                  let period = seconds("period_time") else { return "Byo-yomi" }
            return "\(duration(main)) + \(periods)×\(duration(period))"
        case "fischer":
            guard let main = seconds("initial_time", "main_time"),
                  let increment = seconds("time_increment", "increment") else { return "Fischer" }
            return "\(duration(main)) + \(duration(increment))/move"
        case "canadian":
            guard let main = seconds("main_time"), let period = seconds("period_time"),
                  let stones = seconds("stones_per_period") else { return "Canadian" }
            return "\(duration(main)) + \(duration(period))/\(stones) stones"
        case "simple":
            return seconds("per_move").map { "\(duration($0))/move" } ?? "Per move"
        case "absolute":
            return seconds("total_time", "main_time").map { "\(duration($0)) total" } ?? "Absolute"
        case "none": return "No time limit"
        default: return nil
        }
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
    func rankRestriction(for rank: Int?) -> String? {
        guard let rank else { return nil }
        if let min_rank, rank < min_rank {
            return "Requires at least \(ChallengeHelpers.formatRank(Double(min_rank)))"
        }
        if let max_rank, rank > max_rank {
            return "Requires at most \(ChallengeHelpers.formatRank(Double(max_rank)))"
        }
        return nil
    }
    var speedCategory: String {
        // OGS can supply the classification inside the time control or on the
        // challenge itself. Ignore unrecognized tags so a filter cannot lose a row.
        for tag in [time_control_parameters?.speed, speed] {
            if let tag, ["live", "blitz", "correspondence"].contains(tag) { return tag }
        }

        // Match OGS classifyGameSpeed in components/TimeControl/util.ts:
        // zero means untimed, 10 seconds and exactly one hour are both live.
        guard let tpm = time_per_move else { return "live" }
        if tpm == 0 || tpm > 3600 { return "correspondence" }
        return tpm < 10 ? "blitz" : "live"
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
    // Retain the imported tree independently of the active playback path. ReviewTree
    // owns branch edits and export; local/online playback does not mutate this record.
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

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a challenge name." }
        if ![9, 13, 19].contains(size) { return "Choose a supported board size." }
        if !["japanese", "chinese", "aga"].contains(rules) { return "Choose a supported rule set." }
        if !(-1...9).contains(handicap) || handicap == 1 { return "Choose a valid handicap." }
        if !["automatic", "black", "white"].contains(color) { return "Choose a player color." }
        if !(0...38).contains(minRank) || !(minRank...38).contains(maxRank) { return "Choose a valid rank range." }
        switch timeControl {
        case "byoyomi":
            if mainTime < 0 || periodTime <= 0 || !(1...10).contains(periods) {
                return "Byo-yomi needs a positive period time and 1–10 periods; main time may be zero."
            }
        case "fischer":
            if initialTime <= 0 || increment < 0 || maxTime < initialTime {
                return "Fischer needs positive initial time, a nonnegative increment, and maximum time at least as large as initial time."
            }
        case "simple":
            if perMove <= 0 { return "Time per move must be greater than zero." }
        default: return "Choose a supported time control."
        }
        return nil
    }
    
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

/// Lossless property/branch writer for the first game parsed from an SGF collection.
/// Iterative traversal also supports records with thousands of nested continuations.
enum SGFWriter {
    static func serialize(_ tree: SGFTree) -> String {
        guard !tree.branches.isEmpty else { return "(;GM[1]FF[4])" }
        var output = ""
        var pending: [Int?] = [0]
        while let action = pending.popLast() {
            guard let branch = action else { output += ")"; continue }
            output += "("
            for (index, node) in tree.branches[branch].sequence.enumerated() {
                var props = node.props
                if branch == 0 && index == 0 { props["CA"] = ["UTF-8"] }
                output += ";"
                for key in props.keys.sorted() {
                    output += key
                    for value in props[key] ?? [] {
                        output += "[" + value.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "]", with: "\\]") + "]"
                    }
                }
            }
            pending.append(nil)
            for child in tree.branches[branch].children.reversed() { pending.append(child) }
        }
        return output
    }
}

/// Stable document nodes, distinct from a chosen playback path and temporary AI PVs.
struct ReviewTree {
    struct Node: Identifiable {
        let id: Int
        let parent: Int?
        var children: [Int]
        let properties: [String: [String]]
        let moveNumber: Int
        let depth: Int
        let isVirtual: Bool
        let sourceBranch: Int
        let sourceIndex: Int
        var color: Stone? { properties["B"] != nil ? .black : properties["W"] != nil ? .white : nil }
        var comment: String? { properties["C"]?.first }
        var isPass: Bool { color != nil && (properties[color == .black ? "B" : "W"]?.first ?? "").isEmpty }
        var label: String { color == nil ? (parent == nil ? "Start" : "·") : String(moveNumber) }
    }
    let source: SGFTree
    let originalSGF: String
    let baseGame: SGFGame
    let baseAnalysisID: String
    let filename: String
    let nodes: [Node]
    let columns: [Int]
    let rows: [[Int]]
    let columnCount: Int
    private(set) var selectedID: Int = 0
    private var chosenChildren: [Int: Int] = [:]

    init(game: SGFGame, analysisID: String, filename: String, originalSGF: String? = nil) {
        baseGame = game; baseAnalysisID = analysisID; self.filename = filename
        let tree = game.sourceTree.flatMap { $0.branches.first?.sequence.isEmpty == false ? $0 : nil } ?? Self.linearTree(game)
        source = tree
        self.originalSGF = originalSGF ?? SGFWriter.serialize(tree)
        var built: [Node] = []
        if let first = tree.branches.first?.sequence.first,
           first.props["B"] != nil || first.props["W"] != nil {
            built.append(Node(id: 0, parent: nil, children: [], properties: [:], moveNumber: 0, depth: 0, isVirtual: true, sourceBranch: -1, sourceIndex: -1))
        }
        var stack: [(Int, Int?)] = [(0, built.isEmpty ? nil : 0)]
        while let (branch, parent) = stack.popLast() {
            var previous = parent
            for (sourceIndex, value) in tree.branches[branch].sequence.enumerated() {
                let id = built.count
                let number = previous.map { built[$0].moveNumber } ?? 0
                let depth = previous.map { built[$0].depth + 1 } ?? 0
                built.append(Node(id: id, parent: previous, children: [], properties: value.props,
                    moveNumber: number + (value.props["B"] != nil || value.props["W"] != nil ? 1 : 0), depth: depth, isVirtual: false, sourceBranch: branch, sourceIndex: sourceIndex))
                if let previous { built[previous].children.append(id) }
                previous = id
            }
            for child in tree.branches[branch].children.reversed() { stack.append((child, previous)) }
        }
        nodes = built
        var lanes = Array(repeating: 0, count: built.count)
        var grouped = Array(repeating: [Int](), count: (built.map(\.depth).max() ?? 0) + 1)
        for node in built { grouped[node.depth].append(node.id) }

        // Pack each uninterrupted first-child continuation against the occupied
        // rows, not the total number of leaves in its sibling's entire subtree.
        // This keeps continuations straight and lets short variations at different
        // depths reuse columns. Iterative traversal visits each node twice overall.
        var rightmost = Array(repeating: -1, count: grouped.count)
        var pending = built.isEmpty ? [] : [0]
        while let start = pending.popLast() {
            var path: [Int] = []
            var next: Int? = start
            var column = built[start].parent.map { lanes[$0] + 1 } ?? 0
            while let id = next {
                path.append(id)
                column = max(column, rightmost[built[id].depth] + 1)
                next = built[id].children.first
            }
            for id in path {
                lanes[id] = column
                rightmost[built[id].depth] = column
                for child in built[id].children.dropFirst().reversed() {
                    pending.append(child)
                }
            }
        }
        columns = lanes; rows = grouped; columnCount = (lanes.max() ?? 0) + 1
    }

    var activePath: [Int] {
        guard !nodes.isEmpty else { return [] }
        var path: [Int] = []; var next: Int? = 0
        while let id = next {
            path.append(id)
            next = chosenChildren[id] ?? nodes[id].children.first
        }
        return path
    }
    var isMainLine: Bool {
        let path = activePath
        return zip(path, path.dropFirst()).allSatisfy { nodes[$0.0].children.first == $0.1 }
    }
    mutating func select(_ id: Int) {
        guard nodes.indices.contains(id) else { return }
        selectedID = id
        var child = id
        while let parent = nodes[child].parent { chosenChildren[parent] = child; child = parent }
    }
    mutating func followPlayback(index: Int) {
        guard nodes[selectedID].moveNumber != index else { return }
        if let id = activePath.first(where: { nodes[$0].moveNumber == index }) { selectedID = id }
    }
    func neighbor(direction: Int) -> Int? {
        if direction < 0 { return nodes[selectedID].parent }
        return chosenChildren[selectedID] ?? nodes[selectedID].children.first
    }
    func sibling(direction: Int) -> Int? {
        // From inside a branch, navigate at the closest branching ancestor.
        var child = selectedID
        while let parent = nodes[child].parent {
            let siblings = nodes[parent].children
            if siblings.count > 1, let index = siblings.firstIndex(of: child) {
                let next = index + direction
                return siblings.indices.contains(next) ? siblings[next] : nil
            }
            child = parent
        }
        return nil
    }
    /// Append a continuation or a sibling variation; never truncate an existing line.
    /// Replaying an existing child navigates to it instead of duplicating it.
    func addingMove(color: Stone, point: BoardPosition?) -> ReviewTree {
        let key = color == .black ? "B" : "W"
        let coordinate = point.map { SGFCoordinates.toSGF(x: $0.col, y: $0.row) } ?? ""
        if let child = nodes[selectedID].children.first(where: { nodes[$0].properties[key] == [coordinate] }) {
            var copy = self; copy.select(child); return copy
        }
        var branches = source.branches
        let selected = nodes[selectedID]
        var branch = selected.sourceBranch
        var index = selected.sourceIndex
        if selected.isVirtual {
            // Rare SGF with a move on its root: create an explicit setup root.
            let first = branches[0].sequence[0].props
            let moveKeys: Set<String> = ["B", "W", "C", "N", "TE", "BM", "DO", "IT"]
            let root = SGFNode(props: first.filter { !moveKeys.contains($0.key) })
            branches[0].sequence[0].props = first.filter { moveKeys.contains($0.key) }
            let oldRoot = branches.count
            branches.append(branches[0])
            branches[0] = .init(sequence: [root], children: [oldRoot])
            branch = 0; index = 0
        }
        let node = SGFNode(props: [key: [coordinate]])
        let newBranch: Int
        let newIndex: Int
        if index + 1 == branches[branch].sequence.count && branches[branch].children.isEmpty {
            newBranch = branch; newIndex = index + 1
            branches[branch].sequence.append(node)
        } else {
            if index + 1 < branches[branch].sequence.count {
                let continuation = SGFTree.Branch(sequence: Array(branches[branch].sequence.dropFirst(index + 1)), children: branches[branch].children)
                let continuationID = branches.count
                branches.append(continuation)
                branches[branch].sequence = Array(branches[branch].sequence.prefix(index + 1))
                branches[branch].children = [continuationID]
            }
            newBranch = branches.count; newIndex = 0
            branches.append(.init(sequence: [node]))
            branches[branch].children.append(newBranch)
        }
        var game = baseGame
        game.sourceTree = SGFTree(branches: branches)
        var updated = ReviewTree(game: game, analysisID: baseAnalysisID, filename: filename, originalSGF: originalSGF)
        if let target = updated.nodes.first(where: { $0.sourceBranch == newBranch && $0.sourceIndex == newIndex }) {
            updated.select(target.id)
        }
        return updated
    }

    enum PlaybackError: LocalizedError {
        case setupAfterMoves
        var errorDescription: String? {
            "This branch changes setup stones or rules after play begins. Those nodes are preserved when saving, but playback of this branch is not supported yet."
        }
    }
    func playbackGame() throws -> SGFGame {
        var sequence: [SGFNode] = []
        var movesStarted = false
        var setup: [BoardPosition: Stone] = [:]
        for id in activePath where !nodes[id].isVirtual {
            let node = SGFNode(props: nodes[id].properties)
            let edits = ["AB", "AW", "AE", "PL", "SZ", "RU", "KM", "HA"]
            if movesStarted && edits.contains(where: { node.props[$0] != nil }) {
                // Keep the playable prefix available without silently moving setup
                // stones into the initial position. The full document still exports.
                if nodes[selectedID].depth >= nodes[id].depth { throw PlaybackError.setupAfterMoves }
                break
            }
            sequence.append(node)
            for (key, color) in [("AB", Stone.black), ("AW", Stone.white)] {
                for value in node.props[key] ?? [] {
                    for point in Self.setupPoints(value) { setup[point] = color }
                }
            }
            for value in node.props["AE"] ?? [] { for point in Self.setupPoints(value) { setup.removeValue(forKey: point) } }
            if node.props["B"] != nil || node.props["W"] != nil { movesStarted = true }
        }
        var game = SGFGame.from(tree: SGFTree(branches: [.init(sequence: sequence)]))
        game.setup = setup.sorted { ($0.key.row, $0.key.col) < ($1.key.row, $1.key.col) }.map { ($0.value, $0.key.col, $0.key.row) }
        game.analysisOnline = baseGame.analysisOnline
        game.whiteHandicapBonus = baseGame.whiteHandicapBonus
        game.ruleOverrides = baseGame.ruleOverrides
        game.freeHandicapPlacement = baseGame.freeHandicapPlacement
        game.sourceTree = source
        return game
    }
    private static func setupPoints(_ value: String) -> [BoardPosition] {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard let first = parts.first, let (x, y) = SGFCoordinates.parse(String(first)) else { return [] }
        guard parts.count == 2, let (endX, endY) = SGFCoordinates.parse(String(parts[1])), endX >= x, endY >= y else { return [BoardPosition(y, x)] }
        return (y...endY).flatMap { row in (x...endX).map { BoardPosition(row, $0) } }
    }
    static func linearTree(_ game: SGFGame) -> SGFTree {
        var root: [String: [String]] = ["GM":["1"], "FF":["4"], "CA":["UTF-8"], "SZ":[String(game.boardSize)]]
        for (key, value) in [("PB",game.info.playerBlack),("PW",game.info.playerWhite),("BR",game.info.blackRank),
                             ("WR",game.info.whiteRank),("RE",game.info.result),("DT",game.info.date),("EV",game.info.event),
                             ("RU",game.info.rules),("KM",game.info.komi)] { if let value { root[key] = [value] } }
        if game.handicap > 0 { root["HA"] = [String(game.handicap)] }
        if let player = game.initialPlayer { root["PL"] = [player == .black ? "B" : "W"] }
        func coordinate(_ x: Int, _ y: Int) -> String {
            String(UnicodeScalar(97 + x)!) + String(UnicodeScalar(97 + y)!)
        }
        for (color, x, y) in game.setup { root[color == .black ? "AB" : "AW", default: []].append(coordinate(x, y)) }
        let sequence = [SGFNode(props: root)] + game.moves.map { color, point in
            SGFNode(props: [color == .black ? "B" : "W": [point.map { coordinate($0.0, $0.1) } ?? ""]])
        }
        return SGFTree(branches: [.init(sequence: sequence)])
    }
}

/// Recoverable edits live separately from the user's source file and AI cache.
struct ReviewDraft: Codable {
    let originalSGF: String
    let editedSGF: String
    let selectedID: Int

    init(_ tree: ReviewTree) {
        originalSGF = tree.originalSGF
        editedSGF = SGFWriter.serialize(tree.source)
        selectedID = tree.selectedID
    }
    func restore(over tree: ReviewTree) throws -> ReviewTree? {
        guard originalSGF == tree.originalSGF else { return nil }
        var game = tree.baseGame
        game.sourceTree = try SGFParser.parse(text: editedSGF)
        var restored = ReviewTree(game: game, analysisID: tree.baseAnalysisID, filename: tree.filename, originalSGF: originalSGF)
        restored.select(selectedID)
        return restored
    }
}
