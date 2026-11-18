import Foundation

/// Offline check of deferred minimal SGF exports against original saved games.
/// Uses the app's parser and authoritative rules engine, never the Python helper.
@main enum StoneIdentitySGFAudit {
    struct Pair:Decodable {let original:String;let resolved:String}
    static func main() throws {
        let pairs=try JSONDecoder().decode([Pair].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        var results=[[String:Any]]()
        for pair in pairs {
            let original=SGFGame.from(tree:try SGFParser.parse(text:String(contentsOfFile:pair.original,encoding:.utf8)))
            let resolved=SGFGame.from(tree:try SGFParser.parse(text:String(contentsOfFile:pair.resolved,encoding:.utf8)))
            precondition(original.boardSize==resolved.boardSize && original.moves.count==resolved.moves.count)
            let expected=SGFPlayer();expected.load(game:original)
            var initial=resolved;initial.moves=[];initial.sourceTree=nil
            let rebuilt=SGFPlayer();rebuilt.load(game:initial)
            for (offset,move) in resolved.moves.enumerated() {
                let old=original.moves[offset]
                precondition(move.0==old.0 && move.1?.0==old.1?.0 && move.1?.1==old.1?.1)
                guard let point=move.1 else {fatalError("This offline prototype does not export passes")}
                precondition(rebuilt.tryPlayMove(color:move.0,x:point.0,y:point.1)==nil)
                expected.seek(to:offset+1)
                precondition(rebuilt.board==expected.board)
                precondition(rebuilt.blackStonesCaptured==expected.blackStonesCaptured &&
                             rebuilt.whiteStonesCaptured==expected.whiteStonesCaptured)
            }
            results.append(["resolved":pair.resolved,"moves":resolved.moves.count,
                            "allIntermediateBoardsAndCapturesMatch":true,
                            "scope":"Minimal offline move export; original game metadata and clock sidecars are untouched."])
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
