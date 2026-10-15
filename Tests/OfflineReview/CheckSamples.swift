import Foundation
@testable import SGFPlayerNetworking

@main
struct CheckSamples {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        func load(_ file: String) throws -> SGFPlayer {
            let text = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
            let game = SGFGame.from(tree: try SGFParser.parse(text: text))
            let player = SGFPlayer()
            player.load(game: game)
            return player
        }
        let ko = try load("01 Ko and one capture.sgf")
        ko.stepForward()
        precondition(ko.koPoint == BoardPosition(1, 1))
        precondition(ko.capturesByBlack == 1 && ko.capturesByWhite == 0)
        precondition(ko.tryPlayMove(color: .white, x: 1, y: 1) == .ko)
        ko.stepBackward()
        precondition(ko.capturesByBlack == 0 && ko.koPoint == nil)

        let handicap = try load("02 Two stone handicap.sgf")
        precondition(handicap.turn == .white)
        precondition(handicap.board.stones.count == 2)

        let japanese = try load("03 Japanese self capture.sgf")
        precondition(japanese.tryPlayMove(color: .black, x: 1, y: 0) == .suicide)
        let nz = try load("04 New Zealand self capture.sgf")
        precondition(nz.tryPlayMove(color: .black, x: 1, y: 0) == nil)
        precondition(nz.capturesByWhite == 2)
        print("All four bundled sample games passed their rule and capture checks.")
    }
}
