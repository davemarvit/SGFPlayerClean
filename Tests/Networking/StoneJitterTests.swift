import XCTest
@testable import SGFPlayerNetworking

final class StoneJitterTests: XCTestCase {
    private func game() -> SGFGame {
        var game = SGFGame()
        game.boardSize = 19
        game.moves = (0..<100).map { i in
            (i.isMultiple(of: 2) ? .black : .white, (i % 19, i / 19))
        }
        return game
    }

    private func offsets(_ jitter: StoneJitter, _ player: SGFPlayer) -> [BoardPosition: CGPoint] {
        jitter.prepare(player: player)
        return player.board.stones.reduce(into: [:]) { result, item in
            let p = item.key
            result[p] = jitter.offset(forX: p.col, y: p.row, moveIndex: player.currentIndex, stones: player.board.stones)
        }
    }

    func testSkippingAndRewindingMatchSequentialLayouts() {
        let player = SGFPlayer(); player.load(game: game())
        let sequential = StoneJitter()
        var expected: [Int: [BoardPosition: CGPoint]] = [:]
        for index in 0...100 {
            player.seek(to: index)
            expected[index] = offsets(sequential, player)
        }
        let jumping = StoneJitter()
        for index in [93, 92, 93, 10, 100, 0, 92] {
            player.seek(to: index)
            XCTAssertEqual(offsets(jumping, player), expected[index], "Layout depends on navigation at move \(index)")
        }
    }

    func testNewStoneStillJigglesNeighborsButNotDistantStones() {
        var game = SGFGame()
        game.setup = [(.black, 0, 0), (.black, 17, 17)]
        game.moves = [(.white, (0, 1))]
        let player = SGFPlayer(); player.load(game: game)
        let jitter = StoneJitter(eccentricity: 0)
        let before = offsets(jitter, player)
        player.stepForward()
        let after = offsets(jitter, player)
        XCTAssertNotEqual(before[BoardPosition(0, 0)], after[BoardPosition(0, 0)])
        XCTAssertEqual(before[BoardPosition(17, 17)], after[BoardPosition(17, 17)])
    }

    func testReplacementHistoryAtSameIndexInvalidatesOffsets() {
        let player = SGFPlayer(); player.load(game: game()); player.seek(to: 93)
        let reused = StoneJitter(); _ = offsets(reused, player)
        var replacement = game()
        replacement.moves[92] = (.black, (18, 18))
        player.load(game: replacement); player.seek(to: 93)
        XCTAssertEqual(offsets(reused, player), offsets(StoneJitter(), player))
    }

    func testChangingEccentricityRebuildsConsistentHistory() {
        let player = SGFPlayer(); player.load(game: game()); player.seek(to: 92)
        let reused = StoneJitter(); _ = offsets(reused, player)
        reused.setEccentricity(0.4)
        XCTAssertEqual(offsets(reused, player), offsets(StoneJitter(eccentricity: 0.4), player))
        player.stepForward()
        XCTAssertEqual(offsets(reused, player), offsets(StoneJitter(eccentricity: 0.4), player))
    }

    func testCapturePassAppendUndoAndNewSetupRetainCorrectLayouts() throws {
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text:
            "(;SZ[9]PL[W]AB[aa][ba]AW[ca][ab];W[bb];B[])")))
        let jitter = StoneJitter(boardSize: 9)
        player.seek(to: 2)
        let captured = offsets(jitter, player)
        XCTAssertEqual(player.currentIndex, 2)
        XCTAssertEqual(player.capturesByWhite, 2, "Preparing layouts must not change the source player")
        XCTAssertNil(captured[BoardPosition(0, 0)])
        player.seek(to: 1)
        XCTAssertEqual(offsets(jitter, player), captured, "A pass must not jiggle stones")
        player.seek(to: 2)
        player.playMoveOptimistically(color: .white, x: 8, y: 8)
        XCTAssertEqual(offsets(jitter, player), offsets(StoneJitter(boardSize: 9), player))
        player.seek(to: 0)
        XCTAssertEqual(offsets(jitter, player), offsets(StoneJitter(boardSize: 9), player))
        var replacement = SGFGame()
        replacement.boardSize = 13
        replacement.setup = [(.white, 12, 12)]
        player.load(game: replacement)
        XCTAssertEqual(offsets(jitter, player), offsets(StoneJitter(boardSize: 13), player))
    }
}
