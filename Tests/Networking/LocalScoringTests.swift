import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class LocalScoringTests: XCTestCase {
    private func fixture(_ rules: String = "Japanese", komi: String? = "6.5", handicap: Int = 0) -> (SGFPlayer, LocalScoringSession) {
        var game = SGFGame()
        game.boardSize = 7; game.info.rules = rules; game.info.komi = komi; game.handicap = handicap
        game.setup = (0..<7).flatMap { [(.black, 2, $0), (.white, 4, $0)] }
        game.setup += [(.white, 0, 0), (.white, 0, 1)]
        let player = SGFPlayer(); player.load(game: game)
        player.whiteStonesCaptured = 3; player.blackStonesCaptured = 4
        return (player, LocalScoringSession(player: player, handicap: handicap))
    }

    func testTerritoryDeadGroupsAndNeutralRegionsWithoutMutatingBoardOrCaptures() throws {
        let (player, initial) = fixture()
        let board = player.board
        var scoring = initial
        XCTAssertNil(scoring.territory[BoardPosition(2, 0)], "Mixed-color boundary has no owner")
        scoring.toggleDeadGroup(at: BoardPosition(0, 0))
        XCTAssertEqual(scoring.deadStones, [BoardPosition(0,0), BoardPosition(1,0)])
        let result = try XCTUnwrap(scoring.result)
        XCTAssertEqual(result.black.territory, 14)
        XCTAssertEqual(result.white.territory, 14)
        XCTAssertNil(result.territory[BoardPosition(3,3)], "Dame is not territory")
        XCTAssertEqual(result.black.markedDead, 2)
        XCTAssertEqual(result.black.total, 19)
        XCTAssertEqual(result.white.total, 24.5)
        XCTAssertEqual(result.winnerDescription(blackName: "Dave", whiteName: "Alice"), "Alice White wins by 5.5 points")
        XCTAssertEqual(player.board, board)
        XCTAssertEqual(player.capturesByBlack, 3); XCTAssertEqual(player.capturesByWhite, 4)
        scoring.toggleNeutralArea(at: BoardPosition(2,0))
        XCTAssertEqual(scoring.result?.black.territory, 0, "Manual seki/neutral marking excludes the entire enclosed region")
        XCTAssertEqual(scoring.result?.black.total, 5)
        scoring.toggleNeutralArea(at: BoardPosition(6,1))
        XCTAssertEqual(scoring.result?.black.territory, 14)
        scoring.toggleDeadGroup(at: BoardPosition(1,0))
        XCTAssertTrue(scoring.deadStones.isEmpty)
        XCTAssertEqual(scoring.result?.black.territory, 0)
    }

    func testAreaScoringDoesNotDoubleCountPrisonersOrMarkedDeadStones() throws {
        for rules in ["Chinese", "Chinese-OGS", "Chinese-KGS", "AGA", "BGA", "New Zealand", "Tromp-Taylor"] {
            var (_, scoring) = fixture(rules)
            scoring.toggleDeadGroup(at: BoardPosition(0,0))
            let result = try XCTUnwrap(scoring.result)
            XCTAssertEqual(result.black.total, 21, rules)
            XCTAssertEqual(result.white.total, 27.5, rules)
            XCTAssertEqual(result.black.livingStones, 7)
            XCTAssertEqual(result.white.livingStones, 7)
        }
    }

    func testHandicapCompensationByRulesAndExplicitOverride() throws {
        for (rules, bonus) in [("Chinese", 2.0), ("Chinese-OGS", 2), ("Chinese-KGS", 2),
                              ("AGA", 1), ("BGA", 1), ("Japanese", 0), ("Korean", 0), ("New Zealand", 0)] {
            var (_, scoring) = fixture(rules, handicap: 2)
            scoring.toggleDeadGroup(at: BoardPosition(0,0))
            XCTAssertEqual(scoring.result?.white.handicap, bonus, rules)
            XCTAssertEqual(scoring.result?.white.total, (scoring.rule.territoryScoring ? 24.5 : 27.5) + bonus, rules)
            scoring.handicapBonusOverride = 0
            XCTAssertEqual(scoring.result?.white.handicap, 0)
        }
        XCTAssertEqual(LocalScoringRule.chinese.handicapBonus(1), 0)
        XCTAssertEqual(LocalScoringRule.aga.handicapBonus(0), 0)
    }

    func testMissingUnsupportedRulesAndInvalidKomiRequireExplicitCorrection() {
        for rules in ["", "Ing", "stone-scoring", "aga-button"] {
            var (_, scoring) = fixture(rules)
            XCTAssertNil(scoring.result, rules)
            scoring.rule = .japanese
            XCTAssertNotNil(scoring.result)
        }
        for komi in [nil, "bad", "NaN", "inf", "6.25", "401"] as [String?] {
            var (_, scoring) = fixture(komi: komi)
            XCTAssertNil(scoring.result)
            scoring.komiText = "0"
            XCTAssertNotNil(scoring.result)
        }
        var (_, scoring) = fixture(komi: "-2.5")
        XCTAssertEqual(scoring.result?.white.komi, -2.5)
        scoring.invalidHandicapBonus = true
        XCTAssertNil(scoring.result)
    }

    func testFinalMarksAreFrozenAndEmptyBoardIsNeutral() throws {
        var (_, scoring) = fixture()
        scoring.isFinal = true
        scoring.toggleDeadGroup(at: BoardPosition(0,0))
        scoring.toggleNeutralArea(at: BoardPosition(0,6))
        XCTAssertTrue(scoring.deadStones.isEmpty && scoring.neutralPoints.isEmpty)
        var game = SGFGame(); game.info.rules = "Japanese"; game.info.komi = "0"
        let p = SGFPlayer(); p.load(game: game)
        let empty = LocalScoringSession(player: p, handicap: 0)
        XCTAssertTrue(empty.territory.isEmpty)
        XCTAssertEqual(empty.result?.winnerDescription(blackName: nil, whiteName: nil), "Draw")
    }

    func testTerritoryDotsHaveIndependentColorsAndFadingEdges() throws {
        let scene = SceneManager3D()
        scene.updateTerritory(points: [BoardPosition(1,1): .black, BoardPosition(2,2): .white])
        let black = try XCTUnwrap(scene.scene.rootNode.childNode(withName: "territory-black", recursively: true))
        let white = try XCTUnwrap(scene.scene.rootNode.childNode(withName: "territory-white", recursively: true))
        XCTAssertTrue(black.geometry is SCNPlane && white.geometry is SCNPlane)
        XCTAssertFalse(black.geometry?.firstMaterial === white.geometry?.firstMaterial)
        for (node, expected) in [(black, CGFloat(0)), (white, CGFloat(1))] {
            let texture = try XCTUnwrap(node.geometry?.firstMaterial?.diffuse.contents as? NSImage)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(texture.tiffRepresentation)))
            let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide/2, y: bitmap.pixelsHigh/2)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(center.redComponent, expected, accuracy: 0.05)
            XCTAssertGreaterThan(center.alphaComponent, 0.85)
            XCTAssertLessThan(bitmap.colorAt(x: 0, y: 0)!.alphaComponent, 0.05)
        }
        scene.updateTerritory(points: [:])
        XCTAssertNil(scene.scene.rootNode.childNode(withName: "territory-black", recursively: true))
        XCTAssertNil(scene.scene.rootNode.childNode(withName: "territory-white", recursively: true))
    }
}
