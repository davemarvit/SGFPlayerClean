// MARK: - File: OGSModels.swift (v4.232)
import Foundation
import SwiftUI

enum Stone: String, Codable, CaseIterable {
    case black, white
    var opponent: Stone { self == .black ? .white : .black }
}

struct BoardPosition: Hashable, Codable {
    let row, col: Int
    init(_ row: Int, _ col: Int) { self.row = row; self.col = col }
}

struct BoardSnapshot: Equatable {
    let size: Int
    let grid: [[Stone?]]
    let stones: [BoardPosition: Stone]
}

struct MoveRef: Equatable { let color: Stone; let x, y: Int }

struct RenderStone: Identifiable, Equatable {
    let id: BoardPosition; let color: Stone; let offset: CGPoint
}

struct KeychainHelper {
    static func save(service: String, account: String, data: Data) -> OSStatus {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service as CFString, kSecAttrAccount: account as CFString, kSecValueData: data]
        SecItemDelete(query as CFDictionary); return SecItemAdd(query as CFDictionary, nil)
    }
    static func load(service: String, account: String) -> Data? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service as CFString, kSecAttrAccount: account as CFString, kSecReturnData: kCFBooleanTrue!, kSecMatchLimit: kSecMatchLimitOne]
        var item: AnyObject?; let status = SecItemCopyMatching(query as CFDictionary, &item); return status == noErr ? (item as? Data) : nil
    }
}

struct SGFNode { var props: [String:[String]] }
struct SGFTree { let nodes: [SGFNode] }
enum SGFError: Error { case parseError(String) }

enum SGFParser {
    static func parse(text: String) throws -> SGFTree {
        let s = text.replacingOccurrences(of: "\r", with: "")
        var i = s.startIndex
        func peek() -> Character? { i < s.endIndex ? s[i] : nil }
        func advance() { if i < s.endIndex { i = s.index(after: i) } }
        func skipWhitespace() { while let cc = peek(), cc.isWhitespace { advance() } }
        var nodes: [SGFNode] = []
        skipWhitespace(); guard peek() == "(" else { throw SGFError.parseError("Missing '('") }
        func consumeSubtree() throws {
            advance(); skipWhitespace()
            while let c = peek() {
                if c == ";" { advance(); nodes.append(try parseNode()); skipWhitespace() }
                else if c == "(" { try skipSubtree(); skipWhitespace() }
                else if c == ")" { advance(); break } else { advance() }
            }
        }
        func parseNode() throws -> SGFNode {
            var props: [String:[String]] = [:]
            skipWhitespace(); while let c = peek(), c.isLetter {
                let startKey = i; while let cc = peek(), cc.isLetter { advance() }
                let key = String(s[startKey..<i]).uppercased()
                var values: [String] = []
                skipWhitespace(); while peek() == "[" {
                    advance(); var val = ""
                    while let cc = peek() {
                        if cc == "\\" { advance(); if let nxt = peek() { val.append(nxt); advance() } }
                        else if cc == "]" { advance(); break } else { val.append(cc); advance() }
                    }
                    values.append(val); skipWhitespace()
                }
                props[key] = values; skipWhitespace()
            }
            return SGFNode(props: props)
        }
        func skipSubtree() throws { advance(); var d = 0; while let cc = peek() { advance(); if cc == "(" { d += 1 } else if cc == ")" { if d == 0 { break } else { d -= 1 } } } }
        try consumeSubtree(); return SGFTree(nodes: nodes)
    }
}

struct ChallengerInfo: Codable, Hashable {
    let id: Int; let username: String; let ranking: Double?; let professional: Bool
    var displayRank: String { guard let r = ranking else { return "?" }; let rank = Int(round(r)); return rank < 30 ? "\(30 - rank)k" : "\(rank - 29)d" }
}
struct ChallengeGameInfo: Codable, Hashable { let ranked: Bool; let width, height: Int; let rules: String }
struct OGSChallenge: Identifiable, Decodable {
    let id: Int; let name: String?; let challenger: ChallengerInfo; let game: ChallengeGameInfo; let time_per_move: Int?
    var speedCategory: String { guard let tpm = time_per_move else { return "live" }; if tpm < 30 { return "blitz" }; if tpm > 43200 { return "correspondence" }; return "live" }
    var timeControlDisplay: String { guard let tpm = time_per_move else { return "No limit" }; if tpm < 60 { return "\(tpm)s / move" }; if tpm < 3600 { return "\(tpm / 60)m / move" }; return "\(tpm / 3600)h / move" }
    var boardSize: String { "\(game.width)x\(game.height)" }
    enum CodingKeys: String, CodingKey { case challenge_id, name, user_id, username, ranking, professional, width, height, ranked, rules, time_per_move }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .challenge_id); name = try? c.decode(String.self, forKey: .name); time_per_move = try? c.decode(Int.self, forKey: .time_per_move)
        challenger = ChallengerInfo(id: (try? c.decode(Int.self, forKey: .user_id)) ?? 0, username: (try? c.decode(String.self, forKey: .username)) ?? "Unknown", ranking: try? c.decode(Double.self, forKey: .ranking), professional: (try? c.decode(Bool.self, forKey: .professional)) ?? false)
        game = ChallengeGameInfo(ranked: (try? c.decode(Bool.self, forKey: .ranked)) ?? false, width: (try? c.decode(Int.self, forKey: .width)) ?? 19, height: (try? c.decode(Int.self, forKey: .height)) ?? 19, rules: (try? c.decode(String.self, forKey: .rules)) ?? "japanese")
    }
}

struct SGFGame {
    struct Info { var event, playerBlack, playerWhite, blackRank, whiteRank, result, date, timeLimit, overtime, komi, ruleset: String? }
    var boardSize: Int = 19; var info: Info = .init(); var setup: [(Stone, Int, Int)] = []; var moves: [(Stone, (Int,Int)?)] = []
    static func from(tree: SGFTree) -> SGFGame {
        var g = SGFGame(); for node in tree.nodes { for (k, vals) in node.props { switch k {
                case "SZ": if let v = vals.first { if let colon = v.firstIndex(of: ":") { g.boardSize = Int(v[..<colon]) ?? 19 } else { g.boardSize = Int(v) ?? 19 } }
                case "PB": g.info.playerBlack = vals.first; case "PW": g.info.playerWhite = vals.first
                case "AB": for v in vals { if let (x,y) = SGFCoordinates.parse(v) { g.setup.append((.black, x, y)) } }
                case "AW": for v in vals { if let (x,y) = SGFCoordinates.parse(v) { g.setup.append((.white, x, y)) } }
                case "B": g.moves.append((.black, SGFCoordinates.parse(vals.first ?? ""))); case "W": g.moves.append((.white, SGFCoordinates.parse(vals.first ?? "")))
                default: continue
        } } }; return g
    }
}

struct SGFGameWrapper: Identifiable, Hashable {
    let id = UUID(); let url: URL; let game: SGFGame
    var title: String? { if let event = game.info.event, !event.isEmpty { return event }; return url.lastPathComponent }
    static func == (lhs: SGFGameWrapper, rhs: SGFGameWrapper) -> Bool { lhs.id == rhs.id }; func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SGFCoordinates {
    static func parse(_ s: String) -> (Int, Int)? { guard s.count >= 2 else { return nil }; let chars = Array(s.lowercased()); let x = Int(chars[0].asciiValue ?? 0) - 97; let y = Int(chars[1].asciiValue ?? 0) - 97; return (x >= 0 && x < 25 && y >= 0 && y < 25) ? (x, y) : nil }
    static func toSGF(x: Int, y: Int) -> String { "\(Character(UnicodeScalar(97 + x)!))\(Character(UnicodeScalar(97 + y)!))" }
}

struct NetworkLogEntry: Identifiable { let id = UUID(); let timestamp = Date(); let direction, content: String; let isHeartbeat: Bool }
struct GameInfo: Codable, Hashable { let id: Int; let name: String?; let width, height: Int; let rules: String; let ranked: Bool; let handicap: Int; let komi: String?; let started: String? }
enum ViewMode: String, CaseIterable, Identifiable { case view2D = "2D", view3D = "3D"; var id: String { rawValue }; var displayName: String { self == .view2D ? "2D Board" : "3D Board" } }
enum OGSBrowserTab: String, CaseIterable { case challenge = "Challenge", watch = "Watch" }
enum BoardSizeCategory: String, CaseIterable, Identifiable { case size19 = "19", size13 = "13", size9 = "9", other = "Other"; var id: String { rawValue } }
enum GameSpeedFilter: String, CaseIterable, Identifiable { case all = "All Speeds", live = "Live", blitz = "Blitz", correspondence = "Correspondence"; var id: String { rawValue } }

struct ChallengeSetup: Codable {
    var name = "Friendly Match"; var size = 19; var rules = "japanese"; var ranked = true; var handicap = 0; var color = "automatic"; var minRank = 0; var maxRank = 38; var timeControl = "byoyomi"; var mainTime = 600; var periods = 5; var periodTime = 30; var initialTime = 600; var increment = 30; var maxTime = 1200; var perMove = 30
    func toDictionary() -> [String: Any] { ["game": ["name": name, "rules": rules, "ranked": ranked, "width": size, "height": size], "challenger_color": color] }
    static func load() -> ChallengeSetup { ChallengeSetup() }; func save() {}
}
