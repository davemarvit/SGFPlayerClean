// MARK: - File: SGFKit.swift
import Foundation

// Lightweight SGF AST (MVP: flattens to the main line; ignores variations)
struct SGFTree { let nodes: [SGFNode] }
struct SGFNode { var props: [String:[String]] }

enum SGFError: Error { case parseError(String) }

enum SGFParser {
    static func parse(text: String) throws -> SGFTree {
        // Normalize line endings
        let s = text.replacingOccurrences(of: "\r", with: "")
        var i = s.startIndex

        @inline(__always) func peek() -> Character? { i < s.endIndex ? s[i] : nil }
        @inline(__always) func advance() { if i < s.endIndex { i = s.index(after: i) } }
        @inline(__always) func skipWhitespace() { while let c = peek(), c.isWhitespace { advance() } }

        var nodes: [SGFNode] = []
        skipWhitespace()
        guard peek() == "(" else { throw SGFError.parseError("Missing '(' at start") }
        _ = try consumeSubtree() // parse the outer tree, collecting the main line nodes
        return SGFTree(nodes: nodes)

        func consumeSubtree() throws {
            guard peek() == "(" else { throw SGFError.parseError("Expected '('") }
            advance() // '('
            skipWhitespace()
            while let c = peek() {
                if c == ";" {
                    advance()
                    nodes.append(try parseNode())
                    skipWhitespace()
                } else if c == "(" {
                    try skipSubtree()     // skip variation
                    skipWhitespace()
                } else if c == ")" {
                    advance(); break
                } else {
                    advance() // tolerate junk
                }
            }
        }

        func parseNode() throws -> SGFNode {
            var props: [String:[String]] = [:]
            skipWhitespace()
            while let c = peek(), c.isLetter {
                let key = parseIdent()
                var values: [String] = []
                skipWhitespace()
                while peek() == "[" {
                    values.append(parseValue())
                    skipWhitespace()
                }
                if !values.isEmpty { props[key, default: []].append(contentsOf: values) }
                skipWhitespace()
            }
            return SGFNode(props: props)
        }

        func parseIdent() -> String {
            let start = i
            while let c = peek(), c.isLetter { advance() }
            return String(s[start..<i]).uppercased()
        }

        func parseValue() -> String {
            precondition(peek() == "[")
            advance() // '['
            var out = ""
            while let c = peek() {
                advance()
                if c == "\\" {
                    if let next = peek() { out.append(next); advance() }
                } else if c == "]" {
                    break
                } else {
                    out.append(c)
                }
            }
            return out
        }

        func skipSubtree() throws {
            guard peek() == "(" else { return }
            advance()
            var depth = 0
            while let c = peek() {
                advance()
                if c == "(" { depth += 1 }
                else if c == ")" {
                    if depth == 0 { break } else { depth -= 1 }
                }
            }
        }
    }
}

// MARK: - SGF → Game model (MVP)
struct SGFGame {
    struct Info {
        var event: String?
        var playerBlack: String?
        var playerWhite: String?
        var blackRank: String?
        var whiteRank: String?
        var result: String?
        var date: String?       // DT
        var timeLimit: String?  // TM
        var overtime: String?   // OT
        var komi: String?       // KM
        var ruleset: String?    // RU
    }

    var boardSize: Int = 19
    var info: Info = .init(event: nil, playerBlack: nil, playerWhite: nil, blackRank: nil, whiteRank: nil, result: nil, date: nil, timeLimit: nil, overtime: nil, komi: nil, ruleset: nil)
    var setup: [(Stone, Int, Int)] = []      // AB/AW
    var moves: [(Stone, (Int,Int)?)] = []    // B/W; pass = nil

    static func from(tree: SGFTree) -> SGFGame {
        var g = SGFGame()

        for node in tree.nodes {
            for (k, vals) in node.props {
                switch k {
                case "SZ":
                    if let v = vals.first {
                        if let colon = v.firstIndex(of: ":") {
                            let left = Int(v[..<colon]) ?? 19
                            let right = Int(v[v.index(after: colon)...]) ?? left
                            g.boardSize = max(2, min(25, min(left, right)))
                        } else if let sz = Int(v) {
                            g.boardSize = max(2, min(25, sz))
                        }
                    }
                case "EV": g.info.event = vals.first
                case "PB": g.info.playerBlack = vals.first
                case "PW": g.info.playerWhite = vals.first
                case "BR": g.info.blackRank = vals.first
                case "WR": g.info.whiteRank = vals.first
                case "RE": g.info.result = vals.first
                case "DT": g.info.date = vals.first
                case "TM": g.info.timeLimit = vals.first
                case "OT": g.info.overtime = vals.first
                case "KM": g.info.komi = vals.first
                case "RU": g.info.ruleset = vals.first

                case "AB":
                    for v in vals { if let (x,y) = parseCoord(v) { g.setup.append((.black, x, y)) } }
                case "AW":
                    for v in vals { if let (x,y) = parseCoord(v) { g.setup.append((.white, x, y)) } }

                case "B":
                    let v = vals.first ?? ""
                    g.moves.append((.black, parseCoord(v)))
                case "W":
                    let v = vals.first ?? ""
                    g.moves.append((.white, parseCoord(v)))

                default:
                    continue
                }
            }
        }
        return g
    }
}

// SGF coords: two lowercase letters; 'aa' => (0,0). Empty => pass.
private func parseCoord(_ s: String) -> (Int,Int)? {
    if s.isEmpty { return nil } // pass
    let chars = Array(s)
    guard chars.count == 2,
          let ax = chars[0].asciiValue, let ay = chars[1].asciiValue else { return nil }
    let x = Int(ax) - 97
    let y = Int(ay) - 97
    guard x >= 0, y >= 0 else { return nil }
    return (x, y)
}
