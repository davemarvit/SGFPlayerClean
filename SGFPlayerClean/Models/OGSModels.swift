// MARK: - File: OGSModels.swift (v4.246)
import Foundation
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
}

// MARK: - OGS Network & Lobby Models
struct NetworkLogEntry: Identifiable { let id = UUID(); let timestamp = Date(); let direction, content: String; let isHeartbeat: Bool }
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
}

struct OGSChallenge: Identifiable, Decodable {
    let id: Int; let name: String?; let challenger: ChallengerInfo?; let game: ChallengeGameInfo?; let time_per_move: Int?
    let time_control: String?
    let time_control_parameters: TimeParameters?
    
    enum CodingKeys: String, CodingKey { case challenge_id, game_id, name, user_id, username, ranking, rank, professional, width, height, ranked, rules, time_per_move, black, white, time_control, time_control_parameters }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .challenge_id)) ?? (try? c.decode(Int.self, forKey: .game_id)) ?? 0
        self.name = try? c.decode(String.self, forKey: .name); self.time_per_move = try? c.decode(Int.self, forKey: .time_per_move)
        
        self.time_control = try? c.decode(String.self, forKey: .time_control)
        self.time_control_parameters = try? c.decode(TimeParameters.self, forKey: .time_control_parameters)
        
        if c.contains(.black) || c.contains(.white) {
            self.challenger = (try? c.decode(ChallengerInfo.self, forKey: .black)) ?? (try? c.decode(ChallengerInfo.self, forKey: .white))
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
        
        self.game = ChallengeGameInfo(ranked: isRanked, width: (try? c.decode(Int.self, forKey: .width)) ?? 19, height: (try? c.decode(Int.self, forKey: .height)) ?? 19, rules: try? c.decode(String.self, forKey: .rules))
    }
    var boardSize: String { "\(game?.width ?? 19)x\(game?.height ?? 19)" }
    var speedCategory: String {
        guard let tpm = time_per_move else { return "live" }
        return tpm < 30 ? "blitz" : (tpm > 43200 ? "correspondence" : "live")
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
struct SGFTree { let nodes: [SGFNode] }
enum SGFError: Error { case parseError(String) }

enum SGFParser {
    static func parse(text: String) throws -> SGFTree {
        let s = text.replacingOccurrences(of: "\r", with: ""); var i = s.startIndex
        func peek() -> Character? { i < s.endIndex ? s[i] : nil }
        func advance() { if i < s.endIndex { i = s.index(after: i) } }
        func skipWS() { while let cc = peek(), cc.isWhitespace { advance() } }
        var nodes: [SGFNode] = []; skipWS()
        guard peek() == "(" else { throw SGFError.parseError("Missing '('") }
        func consume() throws {
            advance(); skipWS()
            while let c = peek() {
                if c == ";" { advance(); nodes.append(try parseNode()); skipWS() }
                else if c == "(" { try skipSubtree(); skipWS() }
                else if c == ")" { advance(); break } else { advance() }
            }
        }
        func parseNode() throws -> SGFNode {
            var props: [String:[String]] = [:]; skipWS()
            while let c = peek(), c.isLetter {
                let sk = i; while let cc = peek(), cc.isLetter { advance() }
                let key = String(s[sk..<i]).uppercased(); var values: [String] = []; skipWS()
                while peek() == "[" {
                    advance(); var val = ""
                    while let cc = peek() {
                        if cc == "\\" { advance(); if let nxt = peek() { val.append(nxt); advance() } }
                        else if cc == "]" { advance(); break } else { val.append(cc); advance() }
                    }
                    values.append(val); skipWS()
                }
                props[key] = values; skipWS()
            }
            return SGFNode(props: props)
        }
        func skipSubtree() throws { advance(); var d = 0; while let cc = peek() { advance(); if cc == "(" { d += 1 } else if cc == ")" { if d == 0 { break } else { d -= 1 } } } }
        try consume(); return SGFTree(nodes: nodes)
    }
}

struct SGFGame {
    struct Info { var event, playerBlack, playerWhite, blackRank, whiteRank, result, date, komi: String? }
    var boardSize: Int = 19; var info: Info = .init(); var setup: [(Stone, Int, Int)] = []; var moves: [(Stone, (Int,Int)?)] = []
    static func from(tree: SGFTree) -> SGFGame {
        var g = SGFGame()
        for node in tree.nodes {
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
enum GameSpeedFilter: String, CaseIterable, Identifiable { case all = "All Speeds", live = "Live", blitz = "Blitz", correspondence = "Correspondence"; var id: String { rawValue } }

struct ChallengeSetup: Codable {
    var name = "Friendly Match"; var size = 19; var rules = "japanese"; var ranked = true; var handicap = 0; var color = "automatic"; var minRank = 0; var maxRank = 38; var timeControl = "byoyomi"; var mainTime = 600; var periods = 5; var periodTime = 30; var initialTime = 600; var increment = 30; var maxTime = 1200; var perMove = 30
    func toDictionary() -> [String: Any] { ["game": ["name": name, "rules": rules, "ranked": ranked, "width": size, "height": size], "challenger_color": color] }
    static func load() -> ChallengeSetup { ChallengeSetup() }; func save() {}
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
