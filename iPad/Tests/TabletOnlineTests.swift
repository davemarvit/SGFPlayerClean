import XCTest
@testable import QuietGo_iPad

@MainActor final class TabletOnlineTests: XCTestCase {
    private var fixture: TabletOnlineFixture!
    private var game: TabletGame!
    private var online: TabletOnline { game.online! }
    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }
    private func connect(join: Bool = true) async throws {
        fixture = TabletOnlineFixture(); fixture.authenticated = true
        game = TabletGame(restore: false)
        game.newGame(size: 13); game.pick(BoardPosition(3,3)); game.play()
        game.startOnline(client: fixture.client)
        try await waitUntil { self.online.client.isSocketAuthenticated }
        if join { online.join(7001); try await waitUntil { self.online.loadedGameID == 7001 && !self.online.client.isReconcilingMoves } }
    }
    override func tearDown() { MainActor.assumeIsolated { fixture?.close(); game = nil; fixture = nil } }

    func testLoginJoinMoveEchoAndLocalRestoration() async throws {
        fixture = TabletOnlineFixture(); game = TabletGame(restore: false)
        game.newGame(size: 13); game.pick(BoardPosition(3,3)); game.play()
        let local = game.exportedSGF
        game.startOnline(client: fixture.client)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(online.client.isAuthenticated)
        online.login(username: "test", password: "fixture")
        try await waitUntil { self.online.client.isSocketAuthenticated }
        online.join(7001); try await waitUntil { self.online.canMove }
        XCTAssertEqual(game.player.board.size,9)
        game.tap(at: BoardPosition(2,2)); game.tap(at: BoardPosition(3,3)); game.play(pass:true)
        try await waitUntil { self.game.player.currentIndex == 1 }
        XCTAssertEqual(fixture.sent.filter { $0.contains("\"game/move\"") }.count,1)
        XCTAssertFalse(online.canMove)
        fixture.appendMove(x:6,y:6); try await waitUntil { self.online.canMove }
        XCTAssertEqual(game.player.board.stones[BoardPosition(6,6)],.white)
        let count = game.player.currentIndex
        game.select(0); game.newGame(size:19); game.beginScoring()
        XCTAssertEqual(game.player.currentIndex,count); XCTAssertNil(game.scoring)
        XCTAssertThrowsError(try game.load(text:"(;SZ[9])",name:"Blocked"))
        game.leaveOnline()
        XCTAssertEqual(game.exportedSGF,local); XCTAssertEqual(game.player.currentIndex,1)
        XCTAssertEqual(game.player.board.size,13); XCTAssertFalse(game.canAnalyze)
        XCTAssertTrue(online.client.myActiveGames.contains(7001))
    }
    func testObserveListLiveUpdatesReconnectAndReadOnlyOwnGame() async throws {
        try await connect(join: false)
        online.browse(observing: true)
        try await waitUntil { self.online.client.observedGames.count == 1 }
        XCTAssertEqual(online.client.observedGames.first?.blackName, "Observed black")
        // Even the signed-in player's own game must stay read-only in Observe.
        online.join(7001, observing: true)
        try await waitUntil { self.online.loadedGameID == 7001 && !self.online.client.isReconcilingMoves }
        XCTAssertEqual(online.status, "Spectating")
        XCTAssertFalse(online.canMove); XCTAssertFalse(online.client.canResign)
        XCTAssertFalse(online.client.canEditScore); XCTAssertFalse(online.client.canSendChat)
        game.tap(at: BoardPosition(2,2)); game.play(pass: true)
        XCTAssertFalse(fixture.sent.contains { $0.contains("\"game/move\"") })
        fixture.appendMove(x: 2, y: 2)
        try await waitUntil { self.game.player.currentIndex == 1 }
        online.suspend(); online.resume()
        try await waitUntil { self.online.client.isSocketAuthenticated && !self.online.client.isReconcilingMoves }
        XCTAssertTrue(online.client.observationOnly); XCTAssertFalse(online.canMove)
        online.join(7001) // Explicit Play action restores normal player permissions.
        try await waitUntil { self.online.loadedGameID == 7001 && !self.online.client.isReconcilingMoves }
        XCTAssertFalse(online.client.observationOnly); XCTAssertTrue(online.client.isGameParticipant)
        game.leaveOnline()
        XCTAssertEqual(game.player.board.size, 13); XCTAssertEqual(game.player.currentIndex, 1)
    }
    func testPlayerRanksHandleRatingsProfessionalsMissingDataAndGameSwitches() async throws {
        try await connect()
        XCTAssertEqual(online.playerLabel(.black), "iPad test player (3d)")
        XCTAssertEqual(online.playerLabel(.white), "Test opponent (1d)")
        fixture.blackRankData = ["ratings": ["overall": ["rating": 2000.0, "deviation": 70.0]]]
        fixture.whiteRankData = ["ranking": 1039, "professional": true]
        fixture.stateVersion += 1
        fixture.sockets.last?.event("game/7001/gamedata", fixture.snapshot)
        try await waitUntil { self.online.blackRankLabel == "1d" && self.online.whiteRankLabel == "3p" }
        fixture.blackRankData = [:]; fixture.whiteRankData = [:]; fixture.stateVersion += 1
        fixture.sockets.last?.event("game/7001/gamedata", fixture.snapshot)
        try await waitUntil { self.online.blackRankLabel == "Rank unavailable" && self.online.whiteRankLabel == "Rank unavailable" }
        online.browse(observing: true)
        try await waitUntil { self.online.client.observedGames.count == 1 }
        fixture.stateVersion += 1
        fixture.sockets.last?.event("game/7001/gamedata", fixture.snapshot)
        try await waitUntil { self.online.blackRankLabel == "3d" && self.online.whiteRankLabel == "1d" }
        online.join(9999, observing: true)
        XCTAssertEqual(online.playerLabel(.black), "Loading player…", "Never display the previous game's identity while joining another")
    }
    func testUnconfirmedMoveReconnectDoesNotResend() async throws {
        try await connect(); fixture.echoMoves = false
        game.pick(BoardPosition(2,2)); game.play()
        try await waitUntil { self.fixture.sent.contains { $0.contains("\"game/move\"") } }
        XCTAssertTrue(online.awaitingMove); XCTAssertFalse(online.canMove)
        // An ordinary same-position snapshot is not an acknowledgement.
        fixture.sockets.last?.event("game/7001/gamedata",fixture.snapshot)
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertTrue(online.awaitingMove)
        online.suspend()
        XCTAssertFalse(online.canMove); XCTAssertNil(game.selectedPoint)
        // The server accepted the move while its echo was lost.
        fixture.moves = [[2,2]]; fixture.stateVersion += 1
        online.resume()
        try await waitUntil { self.game.player.currentIndex == 1 && !self.online.client.isReconcilingMoves }
        XCTAssertFalse(online.awaitingMove)
        XCTAssertEqual(fixture.sent.filter { $0.contains("\"game/move\"") }.count,1)
        XCTAssertFalse(online.canMove)
    }
    func testGapResyncDuplicateAndUndo() async throws {
        try await connect()
        fixture.moves = [[2,2],[6,6]]; fixture.stateVersion = 3
        fixture.sockets.last?.event("game/7001/move",["move":[6,6],"move_number":2,"player_id":202,"state_version":3])
        try await waitUntil { self.game.player.currentIndex == 2 && !self.online.client.isReconcilingMoves }
        fixture.sockets.last?.event("game/7001/move",["move":[6,6],"move_number":2,"player_id":202,"state_version":3])
        try await Task.sleep(for:.milliseconds(100)); XCTAssertEqual(game.player.currentIndex,2)
        fixture.moves = [[2,2]]; fixture.stateVersion = 4
        fixture.sockets.last?.event("game/7001/undo_accepted",["move_number":1])
        try await waitUntil { self.game.player.currentIndex == 1 && !self.online.client.isReconcilingMoves }
        XCTAssertNil(game.player.board.stones[BoardPosition(6,6)])
        XCTAssertFalse(online.canMove)
    }
    func testScoringAndSpectatorCannotPlay() async throws {
        try await connect()
        fixture.moves = [[2,2],[6,6]]; fixture.stateVersion = 3; fixture.phase = "stone removal"
        fixture.sockets.last?.event("game/7001/gamedata",fixture.snapshot)
        try await waitUntil { self.online.client.canEditScore }
        XCTAssertFalse(online.canMove)
        game.pick(BoardPosition(2,2))
        try await waitUntil { self.online.client.removedStones.contains(BoardPosition(2,2)) }
        XCTAssertTrue(game.deadStones.contains(BoardPosition(2,2)))
        XCTAssertEqual(game.player.currentIndex,2)
        online.client.acceptScore(gameID:7001)
        try await waitUntil { self.online.client.scoreAcceptance == .confirmed }
        online.client.rejectScore(gameID:7001)
        try await waitUntil { self.online.client.phase == "play" }
        online.client.playerID = 303
        XCTAssertFalse(online.canMove)
        let before = fixture.sent.count
        game.pick(BoardPosition(3,3)); game.play(pass:true)
        XCTAssertEqual(fixture.sent.count,before)
    }
    func testCreateChallengeAutomaticallyOpensStartedGame() async throws {
        try await connect(join:false)
        var setup = ChallengeSetup(); setup.ranked = false; setup.size = 9
        online.create(setup)
        try await waitUntil { !self.online.busy }
        XCTAssertTrue(fixture.requests.contains("POST /api/v1/challenges"))
        XCTAssertTrue(online.showLobby)
        fixture.sockets.last?.event("active_game",["game_id":7001,"phase":"play","black_id":101,"white_id":202])
        try await waitUntil { self.online.canMove }
        XCTAssertFalse(online.showLobby)
        XCTAssertEqual(online.loadedGameID,7001)
    }
    func testAcceptChallengeOpensReturnedGameOnce() async throws {
        try await connect(join:false)
        let challenge = try JSONDecoder().decode(OGSChallenge.self,from:Data(#"{"id":9001,"width":9,"height":9,"username":"opponent","user_id":202}"#.utf8))
        online.accept(challenge); online.accept(challenge)
        try await waitUntil { self.online.canMove }
        XCTAssertEqual(fixture.requests.filter { $0 == "POST /api/v1/challenges/9001/accept" }.count,1)
        XCTAssertFalse(online.showLobby)
    }
    func testMissingMoveConfirmationRefreshesWithoutResending() async throws {
        try await connect(); fixture.echoMoves = false
        game.pick(BoardPosition(2,2)); game.play()
        try await waitUntil { self.fixture.sent.contains { $0.contains("\"game/move\"") } }
        let reads = fixture.requests.filter { $0 == "GET /api/v1/games/7001" }.count
        try await Task.sleep(for:.seconds(10.2))
        try await waitUntil { !self.online.awaitingMove && !self.online.client.isReconcilingMoves }
        XCTAssertGreaterThan(fixture.requests.filter { $0 == "GET /api/v1/games/7001" }.count,reads)
        XCTAssertEqual(fixture.sent.filter { $0.contains("\"game/move\"") }.count,1)
        XCTAssertEqual(game.player.currentIndex,0)
        XCTAssertTrue(online.canMove)
    }
    func testOldGamePacketsCannotReplaceCurrentBoard() async throws {
        try await connect()
        let old = online.client.makeGameNotification(name:Notification.Name("OGSGameDataReceived"),userInfo:["gameData":fixture.snapshot])
        online.lobby()
        online.receiveSnapshot(old)
        XCTAssertNil(online.loadedGameID)
        XCTAssertEqual(game.player.currentIndex,0)
        XCTAssertFalse(online.canMove)
    }
}
