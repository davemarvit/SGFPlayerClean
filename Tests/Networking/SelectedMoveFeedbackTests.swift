import XCTest
@testable import SGFPlayerNetworking

final class SelectedMoveFeedbackTests: XCTestCase {
    private func game(_ sgf: String) throws -> SGFPlayer {
        let player = SGFPlayer(); player.load(game: SGFGame.from(tree: try SGFParser.parse(text: sgf)))
        return player
    }
    private func root(_ turn: Int, score: Double, win: Double, visits: Int = 100) -> AIAnalysis {
        AIAnalysis(id: "test", isDuringSearch: false, turnNumber: turn, moveInfos: nil,
                   rootInfo: AIRootInfo(winrate: win, scoreLead: score, visits: visits))
    }
    func testSelectedMoveUsesBeforeAfterAndMoversPerspective() throws {
        let player = try game("(;SZ[19];B[dd];W[jk];B[pp])")
        let data = [0: root(0, score: 4, win: 0.7), 1: root(1, score: -2, win: 0.35),
                    2: root(2, score: 5.2, win: 0.8), 3: root(3, score: -4, win: 0.3)]
        XCTAssertNil(SelectedMoveFeedback(engine: player, analyses: data))
        player.seek(to: 1)
        let black = try XCTUnwrap(SelectedMoveFeedback(engine: player, analyses: data))
        XCTAssertEqual(black.moveNumber, 1); XCTAssertEqual(black.player, .black)
        XCTAssertEqual(black.location, "D16"); XCTAssertTrue(black.hasStone)
        XCTAssertEqual(black.pointsLost, 2)
        XCTAssertEqual(black.winBefore, 0.7); XCTAssertEqual(black.winAfter, 0.65)
        player.seek(to: 2)
        let white = try XCTUnwrap(SelectedMoveFeedback(engine: player, analyses: data))
        XCTAssertEqual(white.moveNumber, 2); XCTAssertEqual(white.location, "K9")
        XCTAssertEqual(try XCTUnwrap(white.pointsLost), 3.2, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(white.winAfter), 0.2, accuracy: 0.00001)
        XCTAssertEqual(white.chanceText, "Win chance: 35.0% → 20.0% (−15.0 percentage points)")
        player.seek(to: 1)
        XCTAssertEqual(SelectedMoveFeedback(engine: player, analyses: data)?.title, black.title)
    }
    func testPassPendingAndInvalidAnalysisAreExplicit() throws {
        let player = try game("(;SZ[9];B[];W[aa])"); player.seek(to: 1)
        let pending = try XCTUnwrap(SelectedMoveFeedback(engine: player, analyses: [:]))
        XCTAssertEqual(pending.location, "Pass"); XCTAssertFalse(pending.hasStone)
        XCTAssertNil(pending.pointsLost); XCTAssertNil(pending.chanceText)
        for invalid in [root(1, score: .nan, win: 0.3), root(1, score: 0, win: 1.1), root(1, score: 0, win: 0.3, visits: 0)] {
            let data = [0: root(0, score: 0, win: 0.5), 1: invalid]
            XCTAssertNil(SelectedMoveFeedback(engine: player, analyses: data)?.pointsLost)
        }
    }
    func testHandicapDoesNotInvertConsecutiveBlackMovePerspective() throws {
        let player = SGFPlayer()
        let snapshot = try XCTUnwrap(OGSGameSnapshot(["width":9,"moves":[[2,2],[6,6],[2,6]],"handicap":3,"free_handicap_placement":true]))
        _ = player.reconcileOnlineSnapshot(snapshot, newGame: true)
        player.seek(to: 1)
        let data = [0: root(0, score: 4, win: 0.8), 1: root(1, score: 2, win: 0.7)]
        let move = try XCTUnwrap(SelectedMoveFeedback(engine: player, analyses: data))
        XCTAssertEqual(move.pointsLost, 2); XCTAssertEqual(move.winAfter, 0.7)
    }
    func testAllowedSelfCaptureDoesNotInventAStoneAndGainsAreNotLosses() throws {
        let player = try game("(;SZ[5]RU[New Zealand]AW[ba][ab];B[aa])")
        player.seek(to: 1)
        let data = [0: root(0, score: 0, win: 0.5), 1: root(1, score: -1, win: 0.4)]
        let move = try XCTUnwrap(SelectedMoveFeedback(engine: player, analyses: data))
        XCTAssertEqual(move.location, "A5"); XCTAssertFalse(move.hasStone)
        XCTAssertEqual(move.pointsLost, 0)
        XCTAssertEqual(move.chanceText, "Win chance: 50.0% → 60.0% (+10.0 percentage points)")
    }
}
