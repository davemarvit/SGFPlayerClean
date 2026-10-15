import XCTest
@testable import SGFPlayerNetworking

final class SGFPlayerStateTests: XCTestCase {
    func testOnlineEchoesAndDuplicatePassesDoNotAppend() {
        let player = SGFPlayer()
        player.playMoveOptimistically(color: .black, x: -1, y: -1)
        XCTAssertEqual(player.applyOnlineMove(color: .black, x: -1, y: -1, moveNumber: 1), .duplicate)
        XCTAssertEqual(player.applyOnlineMove(color: .white, x: -1, y: -1, moveNumber: 2), .applied)
        XCTAssertEqual(player.applyOnlineMove(color: .white, x: -1, y: -1, moveNumber: 2), .duplicate)
        XCTAssertEqual(player.maxIndex, 2)
    }

    func testOutOfOrderConflictAndMalformedMovesLeaveBoardUntouched() {
        let player = SGFPlayer()
        player.playMoveOptimistically(color: .black, x: 0, y: 0)
        let board = player.board
        for (x, y, number) in [(1, 1, 3), (1, 1, 1), (-1, 0, 2), (19, 0, 2), (0, 0, 0)] {
            XCTAssertEqual(player.applyOnlineMove(color: .white, x: x, y: y, moveNumber: number), .needsResync)
            XCTAssertEqual(player.board, board)
            XCTAssertEqual(player.maxIndex, 1)
        }
    }

    func testRemoteMoveWhileReviewingUsesLiveBoardAndPreservesView() {
        let player = SGFPlayer()
        player.load(game: game())
        player.seek(to: 1)
        let viewed = player.board
        XCTAssertEqual(player.applyOnlineMove(color: .black, x: 3, y: 3, moveNumber: 5), .applied)
        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertEqual(player.board, viewed)
        // Duplicate detection uses history even when the visible last move is different.
        XCTAssertEqual(player.applyOnlineMove(color: .white, x: 2, y: 2, moveNumber: 4), .duplicate)
        player.seek(to: 5)
        XCTAssertEqual(player.board.stones.count, 4)
        XCTAssertEqual(player.board.stones[BoardPosition(3, 3)], .black)
    }

    private func game() -> SGFGame {
        var game = SGFGame()
        game.boardSize = 9
        game.moves = [(.black, (0, 0)), (.white, (1, 1)), (.black, nil), (.white, (2, 2))]
        return game
    }

    func testSnapshotRestoresViewedPositionAndRemainingMoves() {
        let player = SGFPlayer()
        player.load(game: game())
        player.seek(to: 2)
        let board = player.board
        let move = player.lastMove
        let snapshot = player.createSnapshot()
        player.loadOnline(size: 19, setup: [:], nextPlayer: .white, stateVersion: 100)
        player.restoreSnapshot(snapshot)
        XCTAssertEqual(player.currentIndex, 2)
        XCTAssertEqual(player.board, board)
        XCTAssertEqual(player.lastMove, move)
        XCTAssertEqual(player.maxIndex, 4)
        XCTAssertEqual(player.highestKnownStateVersion, 0)
        player.stepForward()
        XCTAssertEqual(player.currentIndex, 3)
        XCTAssertEqual(player.lastMove, MoveRef(color: .black, x: -1, y: -1))
    }

    func testSnapshotAtStartRestoresInitialTurn() {
        let player = SGFPlayer()
        player.load(game: game())
        let snapshot = player.createSnapshot()
        player.loadOnline(size: 13, setup: [:], nextPlayer: .white, stateVersion: 4)
        player.restoreSnapshot(snapshot)
        XCTAssertEqual(player.currentIndex, 0)
        XCTAssertTrue(player.board.stones.isEmpty)
        XCTAssertNil(player.lastMove)
        XCTAssertEqual(player.turn, .black)
    }

    func testSnapshotAtPassAndEndMatchesSavedState() {
        for index in [3, 4] {
            let player = SGFPlayer()
            player.load(game: game())
            player.seek(to: index)
            let board = player.board
            let move = player.lastMove
            let snapshot = player.createSnapshot()
            player.clear()
            player.restoreSnapshot(snapshot)
            XCTAssertEqual(player.currentIndex, index)
            XCTAssertEqual(player.board, board)
            XCTAssertEqual(player.lastMove, move)
        }
    }

    func testSnapshotRestoresCaptureCountsWithBoard() {
        let player = SGFPlayer()
        var game = SGFGame()
        game.boardSize = 9
        game.setup = [(.white, 0, 0), (.black, 1, 0)]
        game.moves = [(.black, (0, 1)), (.white, (8, 8))]
        player.load(game: game)
        player.stepForward()
        XCTAssertEqual(player.whiteStonesCaptured, 1)
        let snapshot = player.createSnapshot()
        let board = player.board
        player.clear()
        player.restoreSnapshot(snapshot)
        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertEqual(player.board, board)
        XCTAssertEqual(player.whiteStonesCaptured, 1)
        XCTAssertEqual(player.blackStonesCaptured, 0)
    }

    func testInvalidSetupAndBoardPositionsAreIgnored() {
        let player = SGFPlayer()
        var game = game()
        game.setup = [(.black, -1, 0), (.white, 0, -1), (.black, 9, 0), (.white, 1, 1)]
        player.load(game: game)
        XCTAssertEqual(player.board.stones, [BoardPosition(1, 1): .white])
        for pos in [BoardPosition(-1, 0), BoardPosition(0, -1), BoardPosition(9, 0)] {
            XCTAssertTrue(player.getGroup(at: pos).isEmpty)
        }
        XCTAssertEqual(player.calculateTerritory(deadStones: [BoardPosition(-1, 0)]),
                       player.calculateTerritory(deadStones: []))
    }

    func testNegativePlaybackIndexCanBeRecoveredWithoutArrayAccess() {
        let player = SGFPlayer()
        player.load(game: game())
        XCTAssertEqual(player.playerToMove(at: -1), .black)
        player.currentIndex = -1
        XCTAssertNil(player.nextHistoricalMovePosition)
        player.stepForward()
        XCTAssertTrue(player.board.stones.isEmpty)
        player.seek(to: 1)
        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertEqual(player.board.stones, [BoardPosition(0, 0): .black])
    }

    func testClearRemovesPreviousTurnAndLastMove() {
        let player = SGFPlayer()
        player.load(game: game())
        player.stepForward()
        player.clear()
        XCTAssertNil(player.lastMove)
        XCTAssertEqual(player.turn, .black)
        XCTAssertTrue(player.board.stones.isEmpty)
    }
}
