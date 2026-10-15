import XCTest
@testable import SGFPlayerNetworking

final class GameReconciliationTests: XCTestCase {
    private func snapshot(moves: [[Int]], version: Int? = nil, extra: [String: Any] = [:]) throws -> OGSGameSnapshot {
        var data: [String: Any] = ["width": 9, "height": 9, "moves": moves]
        data.merge(extra) { _, new in new }
        if let version { data["state_version"] = version }
        return try XCTUnwrap(OGSGameSnapshot(data))
    }

    func testFixedHandicapIsSetupAndWhitePlaysFirst() throws {
        let snapshot = try snapshot(moves: [], extra: ["handicap": 2, "initial_state": ["black": "ccgg"],
            "free_handicap_placement": false, "rules": "japanese", "komi": "0.5"])
        let player = SGFPlayer()
        XCTAssertEqual(player.reconcileOnlineSnapshot(snapshot, newGame: true), .applied)
        XCTAssertEqual(player.maxIndex, 0)
        XCTAssertEqual(player.board.stones.count, 2)
        XCTAssertEqual(player.turn, .white)
        XCTAssertEqual(player.analysisSettings.initialPlayer, .white)
        XCTAssertEqual(player.analysisSettings.effectiveKomi, 0.5)
        XCTAssertEqual(player.applyOnlineMove(color: .white, x: 0, y: 0, moveNumber: 1), .applied)
        XCTAssertEqual(player.turn, .black)
        XCTAssertEqual(player.capturesByWhite, 0)
    }

    func testFreeHandicapKeepsBlackTurnUntilPlacementComplete() throws {
        let player = SGFPlayer()
        let data = try snapshot(moves: [[2, 2]], extra: ["handicap": 3, "free_handicap_placement": true])
        XCTAssertEqual(player.reconcileOnlineSnapshot(data, newGame: true), .applied)
        XCTAssertEqual(player.turn, .black)
        XCTAssertEqual(player.applyOnlineMove(color: .black, x: 6, y: 6, moveNumber: 2), .applied)
        XCTAssertEqual(player.turn, .black)
        XCTAssertEqual(player.applyOnlineMove(color: .black, x: 2, y: 6, moveNumber: 3), .applied)
        XCTAssertEqual(player.turn, .white)
        let full = try snapshot(moves: [[2,2],[6,6],[2,6],[4,4]], extra: ["handicap": 3, "free_handicap_placement": true])
        XCTAssertEqual(full.game.moves.map { $0.0 }, [.black, .black, .black, .white])
        XCTAssertEqual(player.reconcileOnlineSnapshot(full), .applied)
        XCTAssertEqual(player.turn, .black)
    }

    func testHandicapDoesNotInventPlacementMovesWhenFlagIsFalse() throws {
        let full = try snapshot(moves: [[0,0],[1,1]], extra: ["handicap": 2, "free_handicap_placement": false])
        XCTAssertEqual(full.game.moves.map { $0.0 }, [.white, .black])
        let explicit = try snapshot(moves: [[0,0]], extra: ["handicap": 2, "initial_player": "black"])
        XCTAssertEqual(explicit.game.moves.first?.0, .black)
    }

    func testShorterHistoryIsNotAssumedToBeUndo() throws {
        let player = SGFPlayer()
        XCTAssertEqual(player.reconcileOnlineSnapshot(try snapshot(moves: [[0,0],[1,1],[2,2]], version: 10), newGame: true), .applied)
        let board = player.board
        XCTAssertEqual(player.reconcileOnlineSnapshot(try snapshot(moves: [[0,0]], version: 9)), .stale)
        XCTAssertEqual(player.reconcileOnlineSnapshot(try snapshot(moves: [[0,0],[1,1]])), .needsResync)
        XCTAssertEqual(player.board, board)
        XCTAssertEqual(player.reconcileOnlineSnapshot(try snapshot(moves: [[0,0]], version: 11)), .applied)
        XCTAssertEqual(player.maxIndex, 1)
        XCTAssertEqual(player.highestKnownStateVersion, 11)
    }

    func testMoveNumbersAreNotStateVersionsAndMoveEventsAdvanceRevision() throws {
        let player = SGFPlayer()
        let initial = try snapshot(moves: [[0,0]], extra: ["move_number": 500])
        XCTAssertNil(initial.stateVersion)
        XCTAssertEqual(player.reconcileOnlineSnapshot(initial, newGame: true), .applied)
        XCTAssertEqual(player.highestKnownStateVersion, 0)
        player.recordOnlineVersion(20)
        XCTAssertEqual(player.reconcileOnlineSnapshot(try snapshot(moves: [[0,0]], version: 19), recovery: true), .stale)
        XCTAssertEqual(player.highestKnownStateVersion, 20)
    }

    func testRecoveryCorrectsOptimisticMoveAndPreservesHistoricalView() throws {
        let player = SGFPlayer()
        _ = player.reconcileOnlineSnapshot(try snapshot(moves: [[0,0],[1,1],[2,2]]), newGame: true)
        player.playMoveOptimistically(color: .white, x: 3, y: 3)
        XCTAssertEqual(player.reconcileOnlineSnapshot(try snapshot(moves: [[0,0],[1,1],[2,2]])), .needsResync)
        player.seek(to: 1)
        XCTAssertEqual(player.reconcileOnlineSnapshot(try snapshot(moves: [[0,0],[1,1]]), recovery: true), .applied)
        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertEqual(player.maxIndex, 2)
        XCTAssertEqual(player.board.stones.count, 1)
    }

    func testUndoRestoresCapturedStonesAndCaptureCounts() throws {
        let setup: [String: Any] = ["initial_state": ["white": "aaba", "black": "caab"]]
        let player = SGFPlayer()
        _ = player.reconcileOnlineSnapshot(try snapshot(moves: [[1,1]], version: 1, extra: setup), newGame: true)
        XCTAssertEqual(player.capturesByBlack, 2)
        XCTAssertEqual(player.capturesByWhite, 0)
        XCTAssertNil(player.board.stones[BoardPosition(0,0)])
        player.seek(to: 0)
        XCTAssertEqual(player.capturesByBlack, 0)
        player.seek(to: 1)
        XCTAssertEqual(player.capturesByBlack, 2)
        _ = player.reconcileOnlineSnapshot(try snapshot(moves: [], version: 2, extra: setup), recovery: true)
        XCTAssertEqual(player.capturesByBlack, 0)
        XCTAssertEqual(player.board.stones[BoardPosition(0,0)], .white)
        XCTAssertNil(player.lastMove)
    }

    func testWhiteCapturesBlackAndCountsDoNotIncludeDeadStoneMarks() throws {
        let player = SGFPlayer()
        let data = try snapshot(moves: [[0,1]], extra: ["initial_player": "white",
            "initial_state": ["black": "aa", "white": "ba"],
            "removed": "ba", "score": ["white": ["prisoners": 99]]])
        _ = player.reconcileOnlineSnapshot(data, newGame: true)
        XCTAssertEqual(player.capturesByWhite, 1)
        XCTAssertEqual(player.capturesByBlack, 0)
    }

    func testMalformedHistoryIsRejectedAsAWhole() {
        let invalid: [[String: Any]] = [
            ["moves": [[0,0],[9,0]], "width": 9], ["moves": [[-1,0]]],
            ["moves": [[true,0]]], ["width": 9, "height": 13, "moves": []],
            ["moves": [[-1,-1]], "handicap": 2, "free_handicap_placement": true],
            ["moves": [], "initial_state": ["black": "aa", "white": "aa"]],
            ["moves": [], "initial_state": ["move_number": 5]], ["width": 9],
            ["moves": [[0,0,0,1,["edited": true]]]]]
        for data in invalid { XCTAssertNil(OGSGameSnapshot(data), "\(data)") }
    }

    func testSGFRulesKomiInitialPlayerAndSnapshotRestoration() throws {
        let tree = try SGFParser.parse(text: "(;SZ[9]RU[Japanese]KM[0.5]HA[2]PL[W]AB[cc][gg];W[aa])")
        let game = SGFGame.from(tree: tree)
        let player = SGFPlayer()
        player.load(game: game)
        XCTAssertEqual(player.turn, .white)
        XCTAssertEqual(player.analysisSettings.kataRules, "japanese")
        XCTAssertEqual(player.analysisSettings.effectiveKomi, 0.5)
        let saved = player.createSnapshot()
        player.clear()
        player.restoreSnapshot(saved)
        XCTAssertEqual(player.analysisSettings, game.analysisSettings)
        XCTAssertEqual(player.turn, .white)
    }

    func testOGSHandicapCompensationAndChineseKoMapping() throws {
        let normal = try snapshot(moves: [], extra: ["rules": "chinese", "komi": 7.5, "score_handicap": true])
        XCTAssertEqual(normal.game.analysisSettings.kataRules, "chinese-ogs")
        XCTAssertEqual(normal.game.analysisSettings.whiteHandicapBonus, "N")
        let aga = try snapshot(moves: [], extra: ["rules": "aga", "score_handicap": true, "aga_handicap_scoring": true])
        XCTAssertEqual(aga.game.analysisSettings.whiteHandicapBonus, "N-1")
        let none = try snapshot(moves: [], extra: ["rules": "chinese", "score_handicap": false])
        XCTAssertEqual(none.game.analysisSettings.whiteHandicapBonus, "0")
    }
}
