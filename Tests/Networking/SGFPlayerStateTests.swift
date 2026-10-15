import XCTest
@testable import SGFPlayerNetworking

final class SGFPlayerStateTests: XCTestCase {
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
