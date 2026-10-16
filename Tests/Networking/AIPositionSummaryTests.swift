import XCTest
@testable import SGFPlayerNetworking

final class AIPositionSummaryTests: XCTestCase {
    func testBothTurnsGiveSameBlackPerspectiveAndLabel() throws {
        let black = try XCTUnwrap(AIPositionSummary(root: AIRootInfo(winrate: 0.72, scoreLead: 7.5, visits: 100), playerToMove: .black))
        let white = try XCTUnwrap(AIPositionSummary(root: AIRootInfo(winrate: 0.28, scoreLead: -7.5, visits: 100), playerToMove: .white))
        XCTAssertEqual(black.blackWinrate, white.blackWinrate, accuracy: 0.00001)
        XCTAssertEqual(black.blackScoreLead, white.blackScoreLead)
        XCTAssertEqual(black.label, "B+7.5 · B 72%")
        XCTAssertEqual(white.label, black.label)
    }
    func testWhiteLeadAndZeroScore() throws {
        let white = try XCTUnwrap(AIPositionSummary(root: AIRootInfo(winrate: 0.825, scoreLead: 2, visits: 100), playerToMove: .white))
        XCTAssertEqual(white.label, "W+2 · W 82.5%")
        let even = try XCTUnwrap(AIPositionSummary(root: AIRootInfo(winrate: 0.5, scoreLead: 0, visits: 100), playerToMove: .black))
        XCTAssertEqual(even.label, "B+0 · B 50%")
        let zero = try XCTUnwrap(AIPositionSummary(root: AIRootInfo(winrate: 0.65, scoreLead: -0.0, visits: 100), playerToMove: .white))
        XCTAssertEqual(zero.label, "W+0 · W 65%")
    }
    func testScoreLeaderProbabilityIsNotAlwaysMaximumWinrate() throws {
        let divergent = try XCTUnwrap(AIPositionSummary(root: AIRootInfo(winrate: 0.4, scoreLead: 0.2, visits: 100), playerToMove: .black))
        XCTAssertEqual(divergent.label, "B+0.2 · B 40%")
        XCTAssertEqual(divergent.leadingWinrate, 0.4)
    }
    func testInvalidAndUnsearchedValuesDoNotAppearAsEstimates() {
        for (rate, score, visits) in [(Double.nan, 1.0, 100), (0.5, Double.infinity, 100), (1.1, 0, 100), (-0.1, 0, 100), (0.5, 0, 0)] {
            XCTAssertNil(AIPositionSummary(root: AIRootInfo(winrate: rate, scoreLead: score, visits: visits), playerToMove: .black))
        }
    }
}
