import XCTest
@testable import SGFPlayerNetworking

final class GoRulesTests: XCTestCase {
    func testTwoPassStatusFollowsVisibleHistoryAndResetsOnPlacement() throws {
        let p = SGFPlayer()
        p.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9];B[aa];W[];B[])")))
        XCTAssertFalse(p.lastTwoMovesWerePasses)
        p.seek(to: 3)
        XCTAssertTrue(p.lastTwoMovesWerePasses)
        p.seek(to: 2)
        XCTAssertFalse(p.lastTwoMovesWerePasses)
        p.seek(to: 3)
        XCTAssertNil(p.tryPlayMove(color: .white, x: 1, y: 1))
        XCTAssertFalse(p.lastTwoMovesWerePasses)
        XCTAssertNil(p.tryPlayMove(color: .black, x: -1, y: -1))
        XCTAssertFalse(p.lastTwoMovesWerePasses)
        XCTAssertNil(p.tryPlayMove(color: .white, x: -1, y: -1))
        XCTAssertTrue(p.lastTwoMovesWerePasses)
        p.reset()
        XCTAssertFalse(p.lastTwoMovesWerePasses)
    }

    private func player(_ rules: String = "japanese", online: Bool = false,
                        setup: [(Stone, Int, Int)] = [], size: Int = 5) -> SGFPlayer {
        var game = SGFGame()
        game.boardSize = size; game.setup = setup; game.info.rules = rules; game.analysisOnline = online
        let player = SGFPlayer(); player.load(game: game)
        return player
    }
    private let koSetup: [(Stone, Int, Int)] = [
        (.black,1,0),(.black,0,1),(.black,1,2),
        (.white,1,1),(.white,2,0),(.white,3,1),(.white,2,2)]

    func testKoRejectsRecaptureWithoutChangingBoardHistoryOrCaptures() {
        for rules in ["japanese", "korean", "chinese", "aga", "nz", "tromp-taylor"] {
            let p = player(rules, online: true, setup: koSetup)
            XCTAssertNil(p.tryPlayMove(color: .black, x: 2, y: 1), rules)
            XCTAssertEqual(p.koPoint, BoardPosition(1,1), rules)
            let before = p.board
            XCTAssertEqual(p.tryPlayMove(color: .white, x: 1, y: 1), .ko, rules)
            XCTAssertEqual(p.board, before)
            XCTAssertEqual(p.maxIndex, 1); XCTAssertEqual(p.capturesByBlack, 1)
        }
    }

    func testKoThreatAndResponsePermitRecapture() {
        let p = player("chinese", online: true, setup: koSetup)
        XCTAssertNil(p.tryPlayMove(color: .black, x: 2, y: 1))
        XCTAssertNil(p.tryPlayMove(color: .white, x: 4, y: 4))
        XCTAssertNil(p.koPoint)
        XCTAssertNil(p.tryPlayMove(color: .black, x: 4, y: 3))
        XCTAssertNil(p.tryPlayMove(color: .white, x: 1, y: 1))
        XCTAssertEqual(p.capturesByWhite, 1)
        XCTAssertEqual(p.koPoint, BoardPosition(1,2))
    }

    func testPassClearsSimpleKoButNotSuperkoHistory() {
        for rules in ["japanese", "chinese", "aga"] {
            let p = player(rules, online: true, setup: koSetup)
            XCTAssertNil(p.tryPlayMove(color: .black, x: 2, y: 1))
            XCTAssertNil(p.tryPlayMove(color: .white, x: -1, y: -1))
            XCTAssertNil(p.koPoint)
            XCTAssertNil(p.tryPlayMove(color: .black, x: -1, y: -1))
            XCTAssertEqual(p.moveRejection(color: .white, x: 1, y: 1), rules == "japanese" ? nil : .superko)
            XCTAssertEqual(p.capturesByBlack, 1); XCTAssertEqual(p.capturesByWhite, 0)
        }
    }

    func testSnapbackIsNotMistakenForKo() {
        let p = player(setup: [(.black,0,0),(.black,1,0),(.black,0,2),
            (.white,0,1),(.white,2,0),(.white,2,1),(.white,1,2)], size: 3)
        XCTAssertNil(p.tryPlayMove(color: .black, x: 1, y: 1))
        XCTAssertNil(p.koPoint)
        XCTAssertNil(p.tryPlayMove(color: .white, x: 0, y: 1))
        XCTAssertEqual(p.capturesByWhite, 4)
    }

    func testSuicideDependsOnRulesAndCountsRemovedStonesOnce() {
        for rules in ["japanese", "korean", "chinese", "aga", "nz", "tromp-taylor"] {
            let p = player(rules, online: true, setup: [(.black,0,0),(.white,0,1),(.white,1,1),(.white,2,0)], size: 3)
            let allowed = ["nz", "tromp-taylor"].contains(rules)
            XCTAssertEqual(p.tryPlayMove(color: .black, x: 1, y: 0), allowed ? nil : .suicide, rules)
            XCTAssertEqual(p.capturesByWhite, allowed ? 2 : 0)
            if allowed {
                p.seek(to: 0); XCTAssertEqual(p.capturesByWhite, 0)
                p.seek(to: 1); XCTAssertEqual(p.capturesByWhite, 2)
            }
        }
    }

    func testSituationalAndPositionalSuperkoDifferForSameBoardDifferentTurn() {
        let setup: [(Stone,Int,Int)] = [(.white,0,1),(.white,1,0),(.white,2,1),(.white,1,2)]
        let positional = player("tromp-taylor", setup: setup, size: 3)
        XCTAssertEqual(positional.moveRejection(color: .black, x: 1, y: 1), .superko)
        // OGS permits self-capture under NZ; the player to move changes, so this is not SSK.
        let situational = player("nz", online: true, setup: setup, size: 3)
        XCTAssertNil(situational.moveRejection(color: .black, x: 1, y: 1))
    }

    func testCaptureIntoSurroundedPointIsLegalAndGroupIsCountedOnce() {
        let p = player(setup: [(.white,0,0),(.white,1,0),(.white,0,1),
            (.black,2,0),(.black,0,2),(.black,2,1),(.black,1,2)], size: 3)
        XCTAssertFalse(p.isSuicide(color: .black, x: 1, y: 1))
        XCTAssertNil(p.tryPlayMove(color: .black, x: 1, y: 1))
        XCTAssertEqual(p.capturesByBlack, 3)
    }

    func testKoSurvivesSeekSnapshotAndUndoWithoutRememberingDiscardedFuture() throws {
        let p = player(setup: koSetup)
        XCTAssertNil(p.tryPlayMove(color: .black, x: 2, y: 1))
        let saved = p.createSnapshot()
        p.seek(to: 0); XCTAssertNil(p.koPoint)
        p.seek(to: 1); XCTAssertEqual(p.koPoint, BoardPosition(1,1))
        p.clear(); p.restoreSnapshot(saved)
        XCTAssertEqual(p.moveRejection(color: .white, x: 1, y: 1), .ko)
        let data: [String: Any] = ["width":5,"rules":"japanese","moves":[],
            "initial_state":["black":"baab bc".replacingOccurrences(of: " ", with: ""),"white":"bbcadbcc"]]
        let snapshot = try XCTUnwrap(OGSGameSnapshot(data))
        XCTAssertEqual(p.reconcileOnlineSnapshot(snapshot, recovery: true), .applied)
        XCTAssertNil(p.koPoint)
        XCTAssertNil(p.tryPlayMove(color: .black, x: 2, y: 1))
    }

    func testInvalidInputAndHistoricalClickNeverChangeHistory() {
        let p = player()
        XCTAssertEqual(p.tryPlayMove(color: .black, x: -1, y: 0), .outside)
        XCTAssertEqual(p.tryPlayMove(color: .white, x: 0, y: 0), .wrongTurn)
        XCTAssertNil(p.tryPlayMove(color: .black, x: 0, y: 0))
        XCTAssertEqual(p.tryPlayMove(color: .white, x: 0, y: 0), .occupied)
        p.seek(to: 0)
        XCTAssertEqual(p.tryPlayMove(color: .black, x: 1, y: 1), .history)
        XCTAssertEqual(p.maxIndex, 1)
    }

    func testHandicapCannotPassBeforePlacementCompletes() throws {
        let snapshot = try XCTUnwrap(OGSGameSnapshot(["width":9,"moves":[],"handicap":2,"free_handicap_placement":true]))
        let p = SGFPlayer(); _ = p.reconcileOnlineSnapshot(snapshot, newGame: true)
        XCTAssertEqual(p.tryPlayMove(color: .black, x: -1, y: -1), .handicapPass)
        XCTAssertNil(p.tryPlayMove(color: .black, x: 2, y: 2))
        XCTAssertNil(p.tryPlayMove(color: .black, x: 6, y: 6))
        XCTAssertNil(p.tryPlayMove(color: .white, x: -1, y: -1))
    }

    func testOGSCustomLegalityAndScoringOverridesReachAnalysisSettings() throws {
        let snapshot = try XCTUnwrap(OGSGameSnapshot(["width":9,"moves":[],"rules":"japanese",
            "allow_self_capture":true,"score_territory_in_seki":true]))
        XCTAssertEqual(snapshot.game.analysisSettings.playRules?.allowsSelfCapture, true)
        XCTAssertFalse(snapshot.game.analysisSettings.analysisRulesSupported)
        let normal = try XCTUnwrap(OGSGameSnapshot(["width":9,"moves":[],"rules":"japanese",
            "allow_superko":true,"allow_ko":false,"superko_algorithm":"noresult",
            "score_territory":true,"score_stones":false,"score_prisoners":true,"score_territory_in_seki":false]))
        XCTAssertTrue(normal.game.analysisSettings.analysisRulesSupported)
        var custom = normal.game.analysisSettings
        custom.ruleOverrides?.scoreStones = true
        XCTAssertFalse(custom.analysisRulesSupported)
    }

    func testRulePoliciesAndCustomOverridesAreExplicit() {
        let cases: [(String, GoRulePolicy.Repetition, Bool)] = [
            ("japanese",.simple,false),("korean",.simple,false),("chinese-ogs",.positional,false),
            ("aga",.situational,false),("bga",.situational,false),("nz",.situational,true),
            ("tromp-taylor",.positional,true),("stone-scoring",.simple,false)]
        for (name, ko, suicide) in cases {
            let settings = GameAnalysisSettings(rules: name, komi: 0)
            XCTAssertEqual(settings.playRules?.repetition, ko)
            XCTAssertEqual(settings.playRules?.allowsSelfCapture, suicide)
            XCTAssertTrue(settings.analysisRulesSupported)
        }
        var custom = GameAnalysisSettings(rules: "japanese", komi: 6.5)
        custom.ruleOverrides = GoRuleOverrides(allowSelfCapture: true)
        XCTAssertEqual(custom.playRules?.allowsSelfCapture, true)
        XCTAssertFalse(custom.analysisRulesSupported)
        XCTAssertNotNil(custom.notice)
        custom.ruleOverrides = GoRuleOverrides(allowKo: true, allowSuperko: false)
        XCTAssertNil(custom.playRules)
        XCTAssertFalse(custom.analysisRulesSupported)
        XCTAssertNil(GameAnalysisSettings(rules: "ing").playRules)
    }
}
