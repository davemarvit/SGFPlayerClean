import XCTest
@testable import SGFPlayerNetworking

final class AIMovePresentationTests: XCTestCase {
    private func candidate(_ move: String, visits: Int, win: Double, score: Double, order: Int? = nil) -> AIMoveInfo {
        AIMoveInfo(move: move, visits: visits, winrate: win, scoreLead: score, pv: nil, order: order)
    }

    func testOneVisitOptimisticOutlierIsNotBestButKeepsPointLossColor() {
        // Reproduces the saved position after move 144: Q11 had a higher raw
        // winrate despite one visit and a 43-point deficit to the root.
        let best = candidate("H13", visits: 231, win: 0.99, score: 71.78, order: 0)
        let outlier = candidate("Q11", visits: 1, win: 0.999, score: 28.02, order: 4)
        XCTAssertEqual(AIMovePresentation.ranked([outlier, best]).map(\.move), ["H13", "Q11"])
        let sample = MoveLossPalette.sample(pointsLost: 71.35 - outlier.scoreLead)
        XCTAssertEqual(sample.red, 0.447); XCTAssertEqual(sample.green, 0.129); XCTAssertEqual(sample.blue, 0.42)
        XCTAssertEqual(MoveLossPalette.sample(pointsLost: 71.35 - best.scoreLead).green, 0.588)
    }

    func testLegacyRankingUsesVisitsAndPreservesOldCacheDecoding() throws {
        let data = Data(#"{"move":"D4","visits":100,"winrate":0.6,"scoreLead":2}"#.utf8)
        let legacy = try JSONDecoder().decode(AIMoveInfo.self, from: data)
        XCTAssertNil(legacy.order)
        let outlier = candidate("Q16", visits: 1, win: 0.99, score: -20)
        XCTAssertEqual(AIMovePresentation.ranked([outlier, legacy]).first?.move, "D4")
    }

    func testHistoricalLossPreservesRecommendationAndMeasuredColor() throws {
        let best = candidate("D4", visits: 1, win: 0.99, score: 0, order: 0)
        let analysis = AIAnalysis(id: "test", isDuringSearch: false, turnNumber: 0,
            moveInfos: [best], rootInfo: AIRootInfo(winrate: 0.9, scoreLead: 0, visits: 500))
        let evaluation = MoveEvaluation(turn: 0, quality: .disastrous, winDelta: -0.5, scoreDelta: -20, player: .black)
        let hints = HistoricalMoveHints.candidates(analysis: analysis, evaluation: evaluation,
            position: BoardPosition(5, 3), size: 9)
        let played = try XCTUnwrap(hints.first)
        XCTAssertEqual(played.order, 0)
        XCTAssertEqual(played.scoreLead, -20)
        XCTAssertEqual(MoveLossPalette.sample(pointsLost: -played.scoreLead).red, 0.447)
    }

    func testTenDisplayedSuggestionsFollowEngineOrder() {
        let moves = (0..<12).map { candidate("A\($0 + 1)", visits: 20, win: Double($0) / 12, score: 0, order: $0) }
        let analysis = AIAnalysis(id: "test", isDuringSearch: false, turnNumber: 0, moveInfos: moves.reversed(), rootInfo: nil)
        XCTAssertEqual(HistoricalMoveHints.candidates(analysis: analysis, evaluation: nil, position: nil, size: 19).map(\.order), Array(0..<10))
    }
}
