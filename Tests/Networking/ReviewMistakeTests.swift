import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class ReviewMistakeTests: XCTestCase {
    private func evaluation(_ turn: Int, _ color: Stone, _ loss: Double) -> MoveEvaluation {
        MoveEvaluation(turn: turn, quality: .excellent, winDelta: 0, scoreDelta: -loss, player: color)
    }
    func testPointOnlyInclusiveFiltersReturnPlaybackIndices() {
        let evals = [evaluation(0, .black, 2), evaluation(1, .white, 5), evaluation(2, .black, 1.99), evaluation(4, .black, .nan)]
        XCTAssertEqual(MistakeFilter().moveNumbers(in: evals), [1,2])
        XCTAssertEqual(MistakeFilter(players: .white, minimumLoss: 2).moveNumbers(in: evals), [2])
        XCTAssertEqual(MistakeFilter(players: .black, minimumLoss: 2).moveNumbers(in: evals), [1])
        XCTAssertTrue(MistakeFilter(minimumLoss: 6).moveNumbers(in: evals).isEmpty)
        XCTAssertTrue(MistakeFilter(minimumLoss: .nan).moveNumbers(in: evals).isEmpty)
    }
    private func analysis(_ turn: Int, prior: Double? = 1, score: Double = -1) -> AIAnalysis {
        var move = AIMoveInfo(move: "D4", visits: 100, winrate: 0.5, scoreLead: score, pv: nil)
        move.prior = prior; move.order = 0
        return AIAnalysis(id: "test", isDuringSearch: false, turnNumber: turn, moveInfos: [move],
                          rootInfo: AIRootInfo(winrate: 0.5, scoreLead: 0, visits: 100))
    }
    func testKaTrainWeightedAccuracyAndMeanLoss() throws {
        // Easy zero-loss move has weight .05, one-point loss in a hard position has weight 1.
        let evals = [evaluation(0, .black, 0), evaluation(1, .white, 8), evaluation(2, .black, 1)]
        let data = [0: analysis(0, score: 0), 1: analysis(1), 2: analysis(2)]
        let black = AIPlayerPerformance(player: .black, evaluations: evals, analyses: data)
        XCTAssertEqual(try XCTUnwrap(black.meanPointLoss), 0.5, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(black.accuracy), 100 * pow(0.75, 1/1.05), accuracy: 0.00001)
        let white = AIPlayerPerformance(player: .white, evaluations: evals, analyses: data)
        XCTAssertEqual(try XCTUnwrap(white.accuracy), 100 * pow(0.75, 8), accuracy: 0.00001)
    }
    func testLegacyAndInvalidPriorsDoNotInventAccuracy() throws {
        let evals = [evaluation(0, .white, 2)]
        for prior in [nil, -1, 0, Double.nan, Double.infinity] as [Double?] {
            let stats = AIPlayerPerformance(player: .white, evaluations: evals, analyses: [0: analysis(0, prior: prior)])
            XCTAssertNil(stats.accuracy)
            XCTAssertEqual(stats.meanPointLoss, 2)
        }
        XCTAssertNil(AIPlayerPerformance(player: .black, evaluations: [], analyses: [:]).accuracy)
        let legacy = Data(#"{"move":"D4","visits":10,"winrate":0.5,"scoreLead":0}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(AIMoveInfo.self, from: legacy).prior)
        let original = analysis(0)
        let restored = try JSONDecoder().decode(AIAnalysis.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.moveInfos?.first?.prior, 1)
        XCTAssertEqual(restored.moveInfos?.first?.order, 0)
    }
    func testPileVariesBetweenLidsAndGamesAndKeepsPrefixes() {
        let seed = CapturePileLayout.lidSeed(game: 123, whiteStones: false)
        let small = CapturePileLayout.stones(count: 12, seed: seed)
        let large = CapturePileLayout.stones(count: 100, seed: seed)
        XCTAssertEqual(small, Array(large.prefix(12)))
        XCTAssertEqual(small, CapturePileLayout.stones(count: 12, seed: seed))
        XCTAssertNotEqual(small, CapturePileLayout.stones(count: 12, seed: CapturePileLayout.lidSeed(game: 123, whiteStones: true)))
        XCTAssertNotEqual(small, CapturePileLayout.stones(count: 12, seed: CapturePileLayout.lidSeed(game: 124, whiteStones: false)))
        XCTAssertTrue(CapturePileLayout.stones(count: -1, seed: seed).isEmpty)
        for stone in large {
            XCTAssertLessThanOrEqual(hypot(stone.x, stone.y), 0.340001)
            XCTAssertTrue(stone.height.isFinite && stone.height >= 0)
            XCTAssertTrue((0.82...1).contains(stone.tilt))
        }
    }
    func testCaptureSeedSurvivesPlaybackAndSnapshotButChangesWithGame() throws {
        let p = SGFPlayer(); p.setCaptureIdentity("game-one")
        let seed = p.captureSeed
        p.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9];B[aa];W[bb])")))
        p.seek(to: 2); p.seek(to: 0); p.setCaptureIdentity("game-one")
        XCTAssertEqual(p.captureSeed, seed)
        let snapshot = p.createSnapshot()
        p.setCaptureIdentity("game-two"); XCTAssertNotEqual(p.captureSeed, seed)
        p.restoreSnapshot(snapshot); XCTAssertEqual(p.captureSeed, seed)
        p.clear(); XCTAssertNotEqual(p.captureSeed, seed)
    }
    func testSeeded3DPilesStayInsideStaticLidsAcrossGameAndSizeChanges() throws {
        let scene = SceneManager3D()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene.scene; renderer.pointOfView = scene.cameraNode
        var time = 0.0
        for (seed, size) in [(UInt64(123), 19), (456, 9), (789, 13), (123, 19)] {
            scene.updateBoardSize(size)
            scene.updateCapturedStones(black: 70, white: 70, seed: seed)
            SCNTransaction.flush()
            for _ in 0..<180 {
                _ = renderer.snapshot(atTime: time, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
                time += 1.0 / 60
            }
            for name in ["black-player-lid", "white-player-lid"] {
                let lid = try XCTUnwrap(scene.scene.rootNode.childNode(withName: name, recursively: true))
                XCTAssertEqual(lid.physicsBody?.type, .static)
                let stones = lid.childNodes.filter { $0.name?.hasPrefix("captured-") == true }
                XCTAssertEqual(stones.count, 70)
                for stone in stones {
                    let position = stone.presentation.position
                    XCTAssertTrue(position.x.isFinite && position.y.isFinite && position.z.isFinite)
                    XCTAssertLessThan(hypot(Double(position.x), Double(position.z)), 3.5)
                    XCTAssertGreaterThan(position.y, -0.1)
                    XCTAssertLessThan(position.y, 4.5)
                }
            }
        }
    }

}
