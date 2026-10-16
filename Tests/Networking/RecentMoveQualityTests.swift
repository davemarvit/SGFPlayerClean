import XCTest
@testable import SGFPlayerNetworking

final class RecentMoveQualityTests: XCTestCase {
    private func player(_ sgf: String) throws -> SGFPlayer {
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: sgf)))
        player.seek(to: player.maxIndex)
        return player
    }
    private func evaluations(_ player: SGFPlayer) -> [Int: MoveEvaluation] {
        Dictionary(uniqueKeysWithValues: (0..<player.maxIndex).map {
            ($0, MoveEvaluation(turn: $0, quality: .poor, winDelta: -0.1,
                               scoreDelta: -Double($0), player: player.moveColor(at: $0)!))
        })
    }
    func testOnlyPreviousThreeMovesAndRewindUseCurrentBranchHistory() throws {
        let p = try player("(;SZ[9];B[aa];W[bb];B[cc];W[dd];B[ee];W[ff])")
        let values = evaluations(p)
        let markers = RecentMoveQualityMarker.markers(engine: p, evaluations: values)
        XCTAssertEqual(markers.map(\.id), [5,4,3])
        XCTAssertEqual(markers.map(\.pointsLost), [4,3,2])
        XCTAssertEqual(markers.first?.quality, .poor)
        XCTAssertEqual(markers.first?.label, "−4.0")
        p.seek(to: 2)
        XCTAssertEqual(RecentMoveQualityMarker.markers(engine: p, evaluations: values).map(\.id), [1])
        p.seek(to: 0)
        XCTAssertTrue(RecentMoveQualityMarker.markers(engine: p, evaluations: values).isEmpty)
    }
    func testCapturedStoneAndPassConsumeSlotsWithoutFloatingMarkers() throws {
        let p = try player("(;SZ[5]AB[ba];W[aa];B[ab];W[];B[ee])")
        XCTAssertNil(p.board.stones[BoardPosition(0,0)])
        let markers = RecentMoveQualityMarker.markers(engine: p, evaluations: evaluations(p))
        XCTAssertEqual(markers.map(\.id), [2])
        XCTAssertEqual(markers.first?.position, BoardPosition(1,0))
    }
    func testMissingNonfiniteAndFavorableResults() throws {
        let p = try player("(;SZ[9];B[aa];W[bb];B[cc];W[dd])")
        var values = evaluations(p)
        values[0] = nil
        values[1] = MoveEvaluation(turn: 1, quality: .excellent, winDelta: 0, scoreDelta: .nan, player: .white)
        values[2] = MoveEvaluation(turn: 2, quality: .excellent, winDelta: 0.1, scoreDelta: 1.5, player: .black)
        let markers = RecentMoveQualityMarker.markers(engine: p, evaluations: values)
        XCTAssertEqual(markers.map(\.id), [3])
        XCTAssertEqual(markers.first?.pointsLost, 0)
        XCTAssertEqual(markers.first?.label, "0")
    }
    func testQualityBandsAndInvalidAnalysisMatchTable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ai = KataGoEngine(executableURL: URL(fileURLWithPath: "/nonexistent/katago"), cacheDirectory: directory)
        let p = try player("(;SZ[9];B[aa];W[bb])")
        func root(_ turn: Int, _ score: Double, _ win: Double = 0.5, _ visits: Int = 100) -> AIAnalysis {
            AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: turn, moveInfos: nil,
                       rootInfo: AIRootInfo(winrate: win, scoreLead: score, visits: visits))
        }
        ai.currentAnalysisData[0] = root(0, 0)
        for (loss, expected) in [(0.0, MoveQuality.excellent), (1, .good), (3, .mediocre), (5, .poor), (9, .disastrous)] {
            ai.currentAnalysisData[1] = root(1, loss)
            let values = ai.evaluateGameQuality(upTo: 1, engine: p)
            XCTAssertEqual(values[0]?.quality, expected)
            XCTAssertEqual(RecentMoveQualityMarker.markers(engine: p, evaluations: values).first?.quality, expected)
        }
        ai.currentAnalysisData[1] = root(1, 0, 0.8)
        XCTAssertEqual(ai.evaluateGameQuality(upTo: 1, engine: p)[0]?.quality, .disastrous,
                       "Win probability loss also determines table and ring classification")
        for bad in [root(1, .nan), root(1, 0, .infinity), root(1, 0, 1.1), root(1, 0, 0.5, 0)] {
            ai.currentAnalysisData[1] = bad
            XCTAssertTrue(ai.evaluateGameQuality(upTo: 1, engine: p).isEmpty)
        }
    }
}
