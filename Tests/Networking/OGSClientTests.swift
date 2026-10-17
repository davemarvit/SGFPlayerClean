import XCTest
import Combine
@testable import SGFPlayerNetworking

final class OGSClientTests: XCTestCase {
    private var client: OGSClient!
    private var session: URLSession!
    private var socket: TestSocket!
    private var scoringScheduler: TestScheduler!

    override func setUp() {
        ClientHTTPFixture.configHandler = nil
        socket = TestSocket()
        scoringScheduler = TestScheduler()
        ClientHTTPFixture.handler = { fixture in
            XCTFail("Unexpected request: \(fixture.request.url!.path)")
            fixture.respond(status: 500, body: "{}")
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClientHTTPFixture.self]
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
        client = OGSClient(session: session, socketFactory: { [socket = socket!] in socket }, scoringScheduler: scoringScheduler)
        let ready = expectation(description: "Fixture identity loaded")
        let observation = client.$isAuthenticated.filter { $0 }.sink { _ in ready.fulfill() }
        wait(for: [ready], timeout: 3)
        observation.cancel()
    }

    override func tearDown() {
        client.disconnect()
        session.invalidateAndCancel()
        client = nil
        session = nil
        socket = nil
        ClientHTTPFixture.handler = nil
        ClientHTTPFixture.configHandler = nil
    }

    private func connect() {
        client.connect()
        socket.onOpen?()
    }

    private func drainMainQueue() {
        let drained = expectation(description: "Queued updates processed")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 3)
    }

    func testLoginWaitsForValidatedCredentials() {
        connect()
        client.isSocketAuthenticated = true
        let configRequested = expectation(description: "Config requested")
        var held: ClientHTTPFixture?
        ClientHTTPFixture.handler = { $0.respond(status: 204, body: "") }
        ClientHTTPFixture.configHandler = { held = $0; configRequested.fulfill() }
        var completed = false
        let done = expectation(description: "Credentials loaded")
        client.login(username: "second", password: "fixture") { success, error in
            completed = true
            XCTAssertTrue(success)
            XCTAssertNil(error)
            XCTAssertEqual(self.client.playerID, 2)
            XCTAssertEqual(self.client.userJWT, "new-token")
            done.fulfill()
        }
        XCTAssertFalse(client.isConnected)
        XCTAssertFalse(client.isSocketAuthenticated)
        XCTAssertNil(client.playerID)
        wait(for: [configRequested], timeout: 3)
        XCTAssertFalse(completed)
        held?.respond(status: 200, body: #"{"user":{"id":2,"username":"second"},"user_jwt":"new-token"}"#)
        wait(for: [done], timeout: 3)
    }

    func testLoginRejectsAnonymousMissingAndFailedConfig() {
        for (status, body) in [(200, "{}"), (200, #"{"user":{"id":0},"user_jwt":"guest"}"#),
                               (200, #"{"user":{"id":2},"user_jwt":" "}"#), (503, "{}")] {
            ClientHTTPFixture.handler = { $0.respond(status: 200, body: "{}") }
            ClientHTTPFixture.configHandler = { $0.respond(status: status, body: body) }
            let done = expectation(description: "Rejected invalid identity")
            client.login(username: "fixture", password: "fixture") { success, error in
                XCTAssertFalse(success); XCTAssertNotNil(error); done.fulfill()
            }
            wait(for: [done], timeout: 3)
            XCTAssertFalse(client.isAuthenticated)
            XCTAssertNil(client.userJWT)
            XCTAssertNil(client.playerID)
        }
    }

    func testLogoutDuringConfigCannotRestoreIdentityOrReportSuccess() {
        let requested = expectation(description: "Config held")
        var held: ClientHTTPFixture?
        ClientHTTPFixture.handler = { $0.respond(status: 200, body: "{}") }
        ClientHTTPFixture.configHandler = { held = $0; requested.fulfill() }
        let done = expectation(description: "Cancelled once")
        done.assertForOverFulfill = true
        client.login(username: "fixture", password: "fixture") { success, error in
            XCTAssertFalse(success); XCTAssertNotNil(error); done.fulfill()
        }
        wait(for: [requested], timeout: 3)
        client.logout()
        held?.respond(status: 200, body: #"{"user":{"id":2},"user_jwt":"late"}"#)
        wait(for: [done], timeout: 3)
        drainMainQueue()
        XCTAssertFalse(client.isAuthenticated)
        XCTAssertNil(client.playerID)
    }

    func testAnonymousRefreshClearsPreviousIdentity() {
        ClientHTTPFixture.configHandler = { $0.respond(status: 200, body: #"{"user":{"id":0},"user_jwt":""}"#) }
        let done = expectation(description: "Refreshed")
        client.fetchUserConfig { success, _ in XCTAssertFalse(success); done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertNil(client.playerID)
        XCTAssertNil(client.userJWT)
        XCTAssertFalse(client.isSocketAuthenticated)
    }

    func testSocketAuthenticationWaitsForNamespaceAndDoesNotSpam() {
        connect()
        socket.deliver(.success(#"42["notification",{}]"#))
        drainMainQueue()
        XCTAssertFalse(client.isSocketAuthenticated)
        socket.deliver(.success("40"))
        socket.deliver(.success("40"))
        XCTAssertEqual(socket.sentMessages.filter { $0.contains("authenticate") }.count, 1)
        scoringScheduler.advance(by: 15)
        XCTAssertNotNil(client.lastError)
        XCTAssertFalse(client.isSocketAuthenticated)
        socket.deliver(.success(#"42["authenticated",{}]"#))
        drainMainQueue()
        XCTAssertTrue(client.isSocketAuthenticated)
    }

    func testMoveResyncCoalescesReadsAndFencesQueuedSnapshotAgainstNewMove() {
        connect()
        client.activeGameID = 7
        var held: ClientHTTPFixture?
        let requested = expectation(description: "One snapshot read")
        ClientHTTPFixture.handler = { held = $0; requested.fulfill() }
        var snapshot: Notification?
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name("OGSGameDataReceived"), object: nil, queue: nil) { snapshot = $0 }
        defer { NotificationCenter.default.removeObserver(observer) }
        client.requestMoveResync()
        client.requestMoveResync()
        wait(for: [requested], timeout: 3)
        let delivered = expectation(description: "Snapshot delivered")
        let second = NotificationCenter.default.addObserver(forName: Notification.Name("OGSGameDataReceived"), object: nil, queue: nil) { _ in delivered.fulfill() }
        defer { NotificationCenter.default.removeObserver(second) }
        held?.respond(status: 200, body: #"{"id":7,"moves":[[0,0]]}"#)
        wait(for: [delivered], timeout: 3)
        XCTAssertTrue(client.acceptsGameNotification(snapshot!))
        socket.deliver(.success(#"42["game/7/move",{"move_number":2,"move":[1,1]}]"#))
        XCTAssertFalse(client.acceptsGameNotification(snapshot!))
    }

    func testMovePacketsLeaveCaptureAndTurnUpdatesToBoardReconciliation() {
        connect()
        client.activeGameID = 7
        client.blackPlayerID = 1; client.whitePlayerID = 2; client.currentPlayerID = 1
        let packet = #"42["game/7/move",{"move_number":1,"move":[0,0],"player_id":1,"captured":[{"x":1,"y":0}]}]"#
        socket.deliver(.success(packet))
        drainMainQueue()
        XCTAssertEqual(client.blackCaptures, 0)
        XCTAssertEqual(client.currentPlayerID, 1)
        socket.deliver(.success(packet))
        socket.deliver(.success(#"42["game/7/move",{"move_number":1,"move":[0,0]}]"#))
        drainMainQueue()
        XCTAssertEqual(client.blackCaptures, 0)
        XCTAssertEqual(client.currentPlayerID, 1)
        XCTAssertEqual(client.lastKnownRemoteMoveNumber, 1)
        client.activeGameID = 8
        XCTAssertNil(client.lastKnownRemoteMoveNumber)
        XCTAssertEqual(client.currentStateVersion, 0)
    }

    func testMoveDuringSnapshotReadDiscardsOldResponseAndReadsAgain() {
        connect(); client.activeGameID = 7
        let firstRequested = expectation(description: "First snapshot")
        let secondRequested = expectation(description: "Fresh snapshot")
        var held: ClientHTTPFixture?
        var calls = 0
        ClientHTTPFixture.handler = { fixture in
            calls += 1
            if calls == 1 { held = fixture; firstRequested.fulfill() }
            else { secondRequested.fulfill(); fixture.respond(status: 200, body: #"{"id":7,"moves":[[0,0],[1,1]]}"#) }
        }
        let posted = expectation(description: "Only fresh snapshot delivered")
        posted.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name("OGSGameDataReceived"), object: nil, queue: nil) { note in
            let game = note.userInfo?["gameData"] as? [String: Any]
            XCTAssertEqual((game?["moves"] as? [[Int]])?.count, 2)
            posted.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        client.requestMoveResync()
        wait(for: [firstRequested], timeout: 3)
        socket.deliver(.success(#"42["game/7/move",{"move_number":2,"move":[1,1]}]"#))
        held?.respond(status: 200, body: #"{"id":7,"moves":[[0,0]]}"#)
        wait(for: [secondRequested, posted], timeout: 3)
        XCTAssertEqual(calls, 2)
    }

    func testIdentityRefreshKeepsCredentialsOnTransientFailureButRevokesOnUnauthorized() {
        for status in [503, 401] {
            ClientHTTPFixture.configHandler = { $0.respond(status: status, body: "{}") }
            let done = expectation(description: "Config failed")
            client.fetchUserConfig { success, _ in XCTAssertFalse(success); done.fulfill() }
            wait(for: [done], timeout: 3)
            XCTAssertEqual(client.isAuthenticated, status == 503)
            XCTAssertEqual(client.playerID, status == 503 ? 1 : nil)
        }
    }

    func testUndoAcceptedPayloadVariantsUseFencedRecoveryInsteadOfLocalGuess() {
        connect(); client.activeGameID = 7
        for payload in ["5", "\"5\"", #"{"move_number":5,"undo_move_count":2}"#] {
            let delivered = expectation(description: "Post-undo snapshot")
            ClientHTTPFixture.handler = { fixture in
                XCTAssertEqual(fixture.request.httpMethod, "GET")
                fixture.respond(status: 200, body: #"{"id":7,"width":9,"moves":[[0,0]]}"#)
            }
            let observer = NotificationCenter.default.addObserver(forName: Notification.Name("OGSGameDataReceived"), object: nil, queue: nil) { note in
                XCTAssertEqual(note.userInfo?["reconcileMoves"] as? Bool, true)
                XCTAssertTrue(self.client.acceptsGameNotification(note))
                delivered.fulfill()
            }
            socket.deliver(.success("42[\"game/7/undo_accepted\",\(payload)]"))
            wait(for: [delivered], timeout: 3)
            XCTAssertTrue(client.isReconcilingMoves, "Remain blocked until the board accepts the snapshot")
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func testUndoRequestedAndCancelledSupportLegacyAndObjectPayloads() {
        connect(); client.activeGameID = 7
        client.blackPlayerID = 1; client.whitePlayerID = 2; client.whitePlayerName = "Opponent"
        for payload in ["3", "\"3\"", #"{"move_number":"3","requested_by":2}"#] {
            socket.deliver(.success("42[\"game/7/undo_requested\",\(payload)]"))
            XCTAssertEqual(client.undoRequestedMoveNumber, 3)
            XCTAssertEqual(client.undoRequestedUsername, "Opponent")
            socket.deliver(.success(#"42["game/7/undo_canceled",{}]"#))
            drainMainQueue()
            XCTAssertNil(client.undoRequestedMoveNumber)
        }
    }

    func testFullSnapshotCannotChangeMetadataBeforeHistoryAdmission() {
        connect(); client.activeGameID = 7
        client.blackCaptures = 3; client.komi = 7.5; client.phase = "play"
        socket.deliver(.success(#"42["game/7/gamedata",{"id":7,"moves":[],"phase":"finished","komi":0.5,"state_version":500,"prisoners":{"black":99}}]"#))
        drainMainQueue()
        XCTAssertEqual(client.phase, "play")
        XCTAssertEqual(client.komi, 7.5)
        XCTAssertEqual(client.blackCaptures, 3)
        XCTAssertEqual(client.currentStateVersion, 0)
    }

    func testUnauthenticatedAcceptDoesNotLeaveLobbyBusy() {
        client.userJWT = nil
        client.acceptChallenge(challengeID: 7) { id, error in
            XCTAssertNil(id)
            XCTAssertNotNil(error)
        }
        XCTAssertFalse(client.isSearchingForGame)
    }

    func testAcceptRejectsErrorStatusEvenWithGameIDInBody() {
        ClientHTTPFixture.handler = { $0.respond(status: 403, body: #"{"id":99}"#) }
        let done = expectation(description: "Accept failed")
        client.acceptChallenge(challengeID: 7) { id, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNil(id)
            XCTAssertNotNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        XCTAssertFalse(client.isSearchingForGame)
    }

    func testAcceptSuccessRetainsRequestAndResponseFormats() {
        ClientHTTPFixture.handler = { fixture in
            XCTAssertEqual(fixture.request.httpMethod, "POST")
            XCTAssertEqual(fixture.request.url?.path, "/api/v1/challenges/7/accept")
            XCTAssertEqual(fixture.request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
            fixture.respond(status: 200, body: #"{"game_id":"99"}"#)
        }
        let done = expectation(description: "Accepted")
        client.acceptChallenge(challengeID: 7) { id, error in
            XCTAssertEqual(id, 99)
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        XCTAssertFalse(client.isSearchingForGame, "The accepted game ID is ready; do not wait for another notification")
    }

    func testAcceptPreservesServerRejectionReasonAndStatus() {
        for status in [403, 404] {
            ClientHTTPFixture.handler = { $0.respond(status: status, body: #"{"detail":"Challenge rank restriction"}"#) }
            let done = expectation(description: "Rejection explained")
            client.acceptChallenge(challengeID: 7) { id, error in
                XCTAssertNil(id)
                XCTAssertEqual((error as? OGSHTTPError)?.statusCode, status)
                XCTAssertEqual(error?.localizedDescription, "Challenge rank restriction")
                done.fulfill()
            }
            wait(for: [done], timeout: 3)
            XCTAssertFalse(client.isSearchingForGame)
        }
    }

    func testFailedCreateReleasesBusyFlagWithoutStartingKeepalive() {
        connect()
        for (status, body) in [(500, #"{"id":99}"#), (200, "invalid"), (200, #"{"detail":"declined"}"#)] {
            ClientHTTPFixture.handler = { $0.respond(status: status, body: body) }
            let done = expectation(description: "Creation failed")
            client.createChallenge(setup: ChallengeSetup()) { success, error in
                XCTAssertFalse(success)
                XCTAssertNotNil(error)
                done.fulfill()
            }
            wait(for: [done], timeout: 3)
            XCTAssertFalse(client.isSearchingForGame)
            XCTAssertFalse(socket.sentMessages.contains { $0.contains("challenge/keepalive") })
        }
    }

    func testNetworkFailureReleasesBusyFlag() {
        ClientHTTPFixture.handler = { $0.fail(URLError(.timedOut)) }
        let done = expectation(description: "Transport failed")
        client.createChallenge(setup: ChallengeSetup()) { success, error in
            XCTAssertFalse(success)
            XCTAssertNotNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        XCTAssertFalse(client.isSearchingForGame)
    }

    func testSuccessfulCreateStartsExistingKeepaliveAndCancelClearsBusy() {
        connect()
        ClientHTTPFixture.handler = { fixture in
            XCTAssertEqual(fixture.request.httpMethod, "POST")
            fixture.respond(status: 201, body: #"{"challenge_id":7,"game":99}"#)
        }
        let done = expectation(description: "Created")
        client.createChallenge(setup: ChallengeSetup()) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        XCTAssertTrue(client.isSearchingForGame)
        XCTAssertTrue(socket.sentMessages.contains { $0.contains("challenge/keepalive") })
        client.userJWT = nil // Local cleanup must work even if credentials have expired.
        client.cancelChallenge(challengeID: 7)
        XCTAssertFalse(client.isSearchingForGame)
    }

    func testDuplicateRequestDoesNotSendAnotherPOSTOrClearPendingFlag() {
        let requested = expectation(description: "First POST received")
        var held: ClientHTTPFixture?
        ClientHTTPFixture.handler = { held = $0; requested.fulfill() }
        let done = expectation(description: "First request completed")
        client.acceptChallenge(challengeID: 7) { _, _ in done.fulfill() }
        wait(for: [requested], timeout: 3)
        client.acceptChallenge(challengeID: 8) { id, error in
            XCTAssertNil(id)
            XCTAssertNotNil(error)
        }
        XCTAssertTrue(client.isSearchingForGame)
        held?.respond(status: 200, body: #"{"id":99}"#)
        wait(for: [done], timeout: 3)
    }

    func testCancelledOldRequestCannotClearNewRequestState() {
        let requested = expectation(description: "Old POST received")
        ClientHTTPFixture.handler = { _ in requested.fulfill() }
        let cancelled = expectation(description: "Old POST cancelled")
        client.acceptChallenge(challengeID: 7) { id, error in
            XCTAssertNil(id)
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
            cancelled.fulfill()
        }
        wait(for: [requested], timeout: 3)
        client.disconnect()
        XCTAssertFalse(client.isSearchingForGame)
        let newRequested = expectation(description: "New POST received")
        var held: ClientHTTPFixture?
        ClientHTTPFixture.handler = { held = $0; newRequested.fulfill() }
        let done = expectation(description: "New POST completed")
        client.acceptChallenge(challengeID: 8) { id, error in
            XCTAssertEqual(id, 88)
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [cancelled, newRequested], timeout: 3)
        XCTAssertTrue(client.isSearchingForGame)
        held?.respond(status: 200, body: #"{"id":88}"#)
        wait(for: [done], timeout: 3)
    }

    func testSGFDownloadRejectsHTTPErrorAndPreservesValidBytes() {
        for status in [404, 200] {
            let body = "(;SZ[9];B[aa])"
            ClientHTTPFixture.handler = { $0.respond(status: status, body: body) }
            let done = expectation(description: "SGF download")
            client.fetchSGF(gameID: 7) { data in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(data, status == 200 ? Data(body.utf8) : nil)
                done.fulfill()
            }
            wait(for: [done], timeout: 3)
        }
    }

    func testOtherGameEventCannotChangeVersionOrPhase() {
        connect()
        client.activeGameID = 7
        client.currentStateVersion = 5
        socket.deliver(.success(#"42["game/99/clock",{"state_version":999,"phase":"finished"}]"#))
        drainMainQueue()
        XCTAssertEqual(client.currentStateVersion, 5)
        XCTAssertFalse(client.isGameFinished)
    }

    func testQueuedScoringUpdateIsDiscardedAfterChangingGames() {
        connect()
        client.activeGameID = 7
        socket.deliver(.success(#"42["game/7/phase","stone removal"]"#))
        socket.deliver(.success(#"42["game/7/stone_removal",{"removed":"aa"}]"#))
        client.activeGameID = 8
        drainMainQueue()
        XCTAssertTrue(client.removedStones.isEmpty)
    }

    func testQueuedAuthenticationCannotRestoreDisconnectedSocket() {
        connect()
        socket.deliver(.success(#"42["authenticated",{}]"#))
        client.disconnect()
        drainMainQueue()
        XCTAssertFalse(client.isSocketAuthenticated)
        XCTAssertFalse(client.isSubscribedToSeekgraph)
    }

    func testQueuedGameUpdateCannotSurviveSwitchAwayAndBack() {
        connect()
        client.activeGameID = 7
        socket.deliver(.success(#"42["game/7/phase","stone removal"]"#))
        socket.deliver(.success(#"42["game/7/stone_removal",{"removed":"aa"}]"#))
        client.activeGameID = 8
        client.activeGameID = 7
        drainMainQueue()
        XCTAssertTrue(client.removedStones.isEmpty)
    }

    func testLogoutInvalidatesPendingLoginResult() {
        let requested = expectation(description: "Login received")
        ClientHTTPFixture.handler = { _ in requested.fulfill() }
        let done = expectation(description: "Login cancelled")
        client.login(username: "fixture", password: "fixture-password") { success, _ in
            XCTAssertFalse(success)
            done.fulfill()
        }
        wait(for: [requested], timeout: 3)
        client.logout()
        wait(for: [done], timeout: 3)
        XCTAssertFalse(client.isAuthenticated)
        XCTAssertNil(client.userJWT)
        XCTAssertNil(client.username)
    }

    private func startScoring() {
        connect()
        client.activeGameID = 7
        client.blackPlayerID = 1
        client.whitePlayerID = 2
        client.isSocketAuthenticated = true
        socket.deliver(.success(#"42["game/7/phase","stone removal"]"#))
    }

    func testStandalonePhaseEventsEnterScoringAndResumePlay() {
        startScoring()
        XCTAssertTrue(client.isScoringPhase)
        client.removedStones = [BoardPosition(0, 0)]
        socket.deliver(.success(#"42["game/7/phase","play"]"#))
        XCTAssertFalse(client.isScoringPhase)
        XCTAssertTrue(client.removedStones.isEmpty)
        XCTAssertFalse(client.isGameFinished)
    }

    func testRemovalDeltasAddAndReviveWithoutFullSnapshot() {
        startScoring()
        socket.deliver(.success(#"42["game/7/removed_stones",{"removed":true,"stones":"aabb"}]"#))
        XCTAssertEqual(client.removedStones, [BoardPosition(0, 0), BoardPosition(1, 1)])
        socket.deliver(.success(#"42["game/7/removed_stones",{"removed":false,"stones":"aa"}]"#))
        XCTAssertEqual(client.removedStones, [BoardPosition(1, 1)])
    }

    func testExplicitEmptyFinalRemovalsClearButOmittedRemovalsPreserve() {
        startScoring()
        client.removedStones = [BoardPosition(0, 0)]
        client.applyScoringSnapshot(["game_id": 7, "phase": "finished"])
        XCTAssertEqual(client.removedStones, [BoardPosition(0, 0)])
        client.applyScoringSnapshot(["game_id": 7, "phase": "finished", "removed": ""])
        XCTAssertTrue(client.removedStones.isEmpty)
    }

    func testMalformedRemovalCannotPartiallyReplaceValidMarks() {
        startScoring()
        client.removedStones = [BoardPosition(0, 0)]
        for value in ["a", "bb!a", "ZZ"] {
            client.applyScoringSnapshot(["game_id": 7, "removed": value])
            XCTAssertEqual(client.removedStones, [BoardPosition(0, 0)])
        }
    }

    func testAcceptWaitsForOwnMatchingConfirmationAndUsesServerSekiMode() {
        startScoring()
        client.applyScoringSnapshot(["game_id": 7, "removed": "aa", "strict_seki_mode": true])
        client.acceptScore(gameID: 7)
        XCTAssertEqual(client.scoreAcceptance, .submitting)
        XCTAssertFalse(client.isScoreAccepted)
        XCTAssertTrue(socket.sentMessages.last?.contains("\"strict_seki_mode\":true") == true)
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"player_id":2,"stones":"aa","strict_seki_mode":true}]"#))
        XCTAssertFalse(client.isScoreAccepted)
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"player_id":1,"stones":"bb","strict_seki_mode":true}]"#))
        XCTAssertFalse(client.isScoreAccepted)
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"player_id":1,"stones":"aa","strict_seki_mode":true}]"#))
        XCTAssertTrue(client.isScoreAccepted)
        scoringScheduler.advance(by: 20)
        XCTAssertTrue(client.isScoreAccepted)
    }

    func testChangedMarksInvalidateConfirmedAcceptance() {
        startScoring()
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"player_id":1,"stones":""}]"#))
        XCTAssertTrue(client.isScoreAccepted)
        socket.deliver(.success(#"42["game/7/removed_stones",{"all_removed":"aa"}]"#))
        XCTAssertEqual(client.scoreAcceptance, .none)
    }

    func testScoringSnapshotRestoresOwnAcceptance() {
        startScoring()
        client.applyScoringSnapshot(["game_id": 7, "removed": "aa", "players": [
            "black": ["id": 1, "accepted_stones": "aa", "accepted_strict_seki_mode": false]
        ]])
        XCTAssertTrue(client.isScoreAccepted)
    }

    func testScoringTimeoutReleasesControlsWithoutReplayingCommand() {
        startScoring()
        client.acceptScore(gameID: 7)
        let count = socket.sentMessages.count
        scoringScheduler.advance(by: 15)
        XCTAssertEqual(client.scoreAcceptance, .none)
        XCTAssertNotNil(client.scoringError)
        XCTAssertEqual(socket.sentMessages.count, count)
    }

    func testOldScoringTimeoutCannotCancelNewSubmission() {
        startScoring()
        client.acceptScore(gameID: 7)
        let timeout = scoringScheduler.jobs.last!
        client.removedStones = [BoardPosition(0, 0)]
        client.acceptScore(gameID: 7)
        timeout.action()
        XCTAssertEqual(client.scoreAcceptance, .submitting)
        XCTAssertNil(client.scoringError)
    }

    func testResumeSendsOnlyResumeAndWaitsForPhase() {
        startScoring()
        let count = socket.sentMessages.count
        client.rejectScore(gameID: 7)
        XCTAssertEqual(socket.sentMessages.count, count + 1)
        XCTAssertTrue(socket.sentMessages.last!.contains("game/removed_stones/reject"))
        XCTAssertEqual(client.phase, "stone removal")
        XCTAssertEqual(client.scoreAcceptance, .resuming)
        XCTAssertFalse(socket.sentMessages.contains { $0.contains("game/undo/request") })
        socket.deliver(.success(#"42["game/7/phase","play"]"#))
        XCTAssertEqual(client.scoreAcceptance, .none)
    }

    func testSpectatorDisconnectedAndWrongGameCannotSendScoringActions() {
        startScoring()
        for mode in 0..<3 {
            if mode == 0 { client.playerID = 99 }
            if mode == 1 { client.playerID = 1 }
            if mode == 2 { client.disconnect() }
            let gameID = mode == 1 ? 88 : 7
            let count = socket.sentMessages.count
            client.acceptScore(gameID: gameID)
            client.rejectScore(gameID: gameID)
            client.sendRemovedStones(gameID: gameID, stones: "aa", removed: true)
            XCTAssertEqual(socket.sentMessages.count, count)
            XCTAssertEqual(client.scoreAcceptance, .none)
        }
    }

    func testMarkRequestBlocksAcceptUntilServerUpdates() {
        startScoring()
        client.sendRemovedStones(gameID: 7, stones: "aa", removed: true)
        XCTAssertEqual(client.scoreAcceptance, .updating)
        let count = socket.sentMessages.count
        client.acceptScore(gameID: 7)
        XCTAssertEqual(socket.sentMessages.count, count)
        socket.deliver(.success(#"42["game/7/removed_stones",{"all_removed":"aa"}]"#))
        XCTAssertEqual(client.scoreAcceptance, .none)
        client.acceptScore(gameID: 7)
        XCTAssertEqual(client.scoreAcceptance, .submitting)
    }

    func testChangingGamesClearsScoringStateAndParticipantIdentity() {
        startScoring()
        client.applyScoringSnapshot(["removed": "aa", "score": ["black": ["total": 10], "white": ["total": 6.5]]])
        client.acceptScore(gameID: 7)
        client.activeGameID = 8
        XCTAssertTrue(client.removedStones.isEmpty)
        XCTAssertNil(client.scoreSummary)
        XCTAssertEqual(client.scoreAcceptance, .none)
        XCTAssertFalse(client.isGameParticipant)
        scoringScheduler.advance(by: 20)
        XCTAssertNil(client.scoringError)
    }

    func testFinalAcceptanceCarriesScoreAndResultWithoutRebuildingBoard() {
        startScoring()
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"player_id":1,"stones":"aa","phase":"finished","winner":1,"outcome":"3.5 points","score":{"black":{"total":40},"white":{"total":36.5}}}]"#))
        XCTAssertTrue(client.isGameFinished)
        XCTAssertEqual(client.scoreSummary?.black.total, 40)
        XCTAssertEqual(client.removedStones, [BoardPosition(0, 0)])
        XCTAssertEqual(client.activeGameResult?.title, "You Win")
        XCTAssertTrue(client.showsScoringMarks)
        XCTAssertNotNil(client.scoringDisplaySummary)
    }

    func testNonPointsResultsHideCachedScoringAndResetWithNextGame() {
        startScoring()
        client.applyScoringSnapshot(["game_id": 7, "removed": "aa", "score": [
            "black": ["total": 10, "scoring_positions": "bb"],
            "white": ["total": 6.5, "scoring_positions": "cc"]]])
        XCTAssertTrue(client.showsScoringMarks)
        for outcome in ["Resignation", "Timeout", "Cancellation", "Abandoned", "Void"] {
            client.applyScoringSnapshot(["game_id": 7, "phase": "finished", "outcome": outcome])
            XCTAssertFalse(client.showsScoringMarks, outcome)
            XCTAssertNil(client.scoringDisplaySummary, outcome)
            XCTAssertNotNil(client.scoreSummary, "Keep server data; suppress only its presentation")
        }
        client.activeGameID = 8
        XCTAssertNil(client.scoringOutcome)
        XCTAssertNil(client.scoringDisplaySummary)
        client.applyScoringSnapshot(["game_id": 8, "phase": "stone removal"])
        XCTAssertTrue(client.showsScoringMarks)
        client.applyScoringSnapshot(["game_id": 8, "phase": "finished"])
        XCTAssertFalse(client.showsScoringMarks, "A finished phase alone is not a scored result")
    }

    func testSpectatorResultAndZeroWinnerAreNotPersonalLosses() {
        startScoring()
        client.playerID = 99
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"phase":"finished","winner":1,"outcome":"Resignation"}]"#))
        XCTAssertEqual(client.activeGameResult?.title, "Game Over")
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"phase":"finished","winner":0,"outcome":"0 points"}]"#))
        XCTAssertEqual(client.activeGameResult?.title, "Draw")
    }

    func testQueuedNotificationsAreRejectedAfterDisconnectAndGameSwitch() {
        connect()
        client.activeGameID = 7
        let notification = client.makeGameNotification(name: Notification.Name("OGSMoveReceived"), userInfo: ["move": "aa"])
        XCTAssertTrue(client.acceptsGameNotification(notification))
        client.activeGameID = 8
        client.activeGameID = 7
        XCTAssertFalse(client.acceptsGameNotification(notification))
        let latest = client.makeGameNotification(name: notification.name, userInfo: [:])
        XCTAssertTrue(client.acceptsGameNotification(latest))
        client.disconnect()
        XCTAssertFalse(client.acceptsGameNotification(latest))
    }

    func testUnscopedNotificationIsRejected() {
        connect()
        client.activeGameID = 7
        let notification = Notification(name: Notification.Name("OGSMoveReceived"), object: nil, userInfo: ["move": "aa"])
        XCTAssertFalse(client.acceptsGameNotification(notification))
    }

    func testOfflineSimulationRemainsExplicitAndIsInvalidatedByGameSwitch() {
        client.activeGameID = 999999
        let notification = client.makeGameNotification(name: Notification.Name("OGSGameDataReceived"), userInfo: [:], offlineSimulation: true)
        XCTAssertTrue(client.acceptsGameNotification(notification))
        client.activeGameID = nil
        XCTAssertFalse(client.acceptsGameNotification(notification))
    }

    func testChatViewModelRejectsQueuedChatAfterLeavingGame() {
        connect()
        client.activeGameID = 7
        let model = OGSGameViewModel(ogsClient: client, player: SGFPlayer(), timeControl: TimeControlManager())
        let notification = client.makeGameNotification(name: Notification.Name("OGSChatReceived"),
            userInfo: ["username": "fixture", "body": "Old game chat", "date": 1])
        NotificationCenter.default.post(notification)
        client.disconnect()
        drainMainQueue()
        XCTAssertTrue(model.chatMessages.isEmpty)
    }

    func testChatViewModelStillAcceptsCurrentGameChat() {
        connect()
        client.activeGameID = 7
        let model = OGSGameViewModel(ogsClient: client, player: SGFPlayer(), timeControl: TimeControlManager())
        NotificationCenter.default.post(client.makeGameNotification(name: Notification.Name("OGSChatReceived"),
            userInfo: ["username": "fixture", "body": "Current game chat", "date": 1]))
        drainMainQueue()
        XCTAssertEqual(model.chatMessages.map(\.message), ["Current game chat"])
    }

    func testLobbyNotificationsForAnotherGameCannotChangeScoringOrVersion() {
        startScoring()
        socket.deliver(.success(#"42["game/7/phase","play"]"#))
        client.currentStateVersion = 5
        socket.deliver(.success(#"42["active_game",{"id":99,"phase":"stone removal","state_version":999,"black_id":1,"white_id":3}]"#))
        socket.deliver(.success(#"42["notification",{"game_id":99,"type":"gameStarted","phase":"finished","outcome":"Resignation"}]"#))
        drainMainQueue()
        XCTAssertEqual(client.phase, "play")
        XCTAssertEqual(client.currentStateVersion, 5)
        XCTAssertFalse(client.isGameFinished)
        XCTAssertFalse(client.canEditScore)
    }

    func testCurrentGameScoringUpdateStillApplies() {
        connect()
        client.activeGameID = 7
        socket.deliver(.success(#"42["game/7/phase","stone removal"]"#))
        socket.deliver(.success(#"42["game/7/stone_removal",{"removed":"aa"}]"#))
        drainMainQueue()
        XCTAssertEqual(client.removedStones, [BoardPosition(0, 0)])
    }
    func testObservationReviewBlocksMutationsButCanAuthenticateAndObserve() {
        client.disconnect()
        socket = TestSocket()
        client = OGSClient(session: session, socketFactory: { [socket = socket!] in socket },
                           scoringScheduler: scoringScheduler, observationOnly: true)
        let ready = expectation(description: "Observer fixture identity loaded")
        let observation = client.$isAuthenticated.filter { $0 }.sink { _ in ready.fulfill() }
        wait(for: [ready], timeout: 3)
        observation.cancel()
        connect()
        socket.deliver(.success("0{}"))
        socket.deliver(.success("40{}"))
        XCTAssertTrue(socket.sentMessages.contains { $0.contains("authenticate") })
        client.isSocketAuthenticated = true
        client.activeGameID = 7
        client.playerID = 1; client.blackPlayerID = 1
        client.connectToGame(gameID: 7)
        XCTAssertTrue(socket.sentMessages.contains { $0.contains("game/connect") })
        XCTAssertFalse(client.isGameParticipant, "Even one's own game is observation only")
        let before = socket.sentMessages
        client.sendMove(gameID: 7, x: 0, y: 0)
        client.sendPass(gameID: 7)
        client.resignGame(gameID: 7)
        client.sendChat(gameID: 7, text: "must not be sent")
        client.sendUndoRequest(gameID: 7, moveNumber: 2)
        client.sendUndoAccept(gameID: 7, moveNumber: 2)
        client.sendUndoReject(gameID: 7)
        client.phase = "stone removal"
        client.acceptScore(gameID: 7)
        client.rejectScore(gameID: 7)
        client.sendRemovedStones(gameID: 7, stones: "aa", removed: true)
        client.startAutomatch()
        client.cancelChallenge(challengeID: 9)
        client.startChallengeKeepAlive(challengeID: 9, gameID: 7)
        var acceptBlocked = false, createBlocked = false
        client.acceptChallenge(challengeID: 9) { id, error in acceptBlocked = id == nil && error != nil }
        client.createChallenge(setup: ChallengeSetup()) { success, error in createBlocked = !success && error != nil }
        XCTAssertTrue(acceptBlocked && createBlocked)
        XCTAssertFalse(client.isSearchingForGame)
        XCTAssertEqual(socket.sentMessages, before)
        drainMainQueue() // Unexpected REST mutations fail through ClientHTTPFixture.handler.
    }

    func testAccountParticipationSurvivesReadOnlyModeAndLeavingBoard() {
        connect(); client.isSocketAuthenticated = true
        client.activeGameID = 7
        client.blackPlayerID = client.playerID
        client.whitePlayerID = 2
        XCTAssertTrue(client.isGameParticipant)
        XCTAssertTrue(client.hasOngoingAccountGame)
        client.observationOnly = true
        XCTAssertFalse(client.isGameParticipant)
        XCTAssertTrue(client.isAccountGameParticipant)
        XCTAssertTrue(client.hasOngoingAccountGame)
        client.leaveViewedGame()
        XCTAssertTrue(client.isConnected)
        XCTAssertTrue(client.isAuthenticated)
        XCTAssertNil(client.activeGameID)
        XCTAssertTrue(client.hasOngoingAccountGame)
        XCTAssertTrue(client.myActiveGames.contains(7))
        XCTAssertTrue(socket.sentMessages.contains { $0.contains("game/disconnect") })
        socket.deliver(.success(#"42["active_game",{"id":7,"phase":"finished"}]"#))
        drainMainQueue()
        XCTAssertFalse(client.hasOngoingAccountGame)
    }

    func testPlayModeEnablesMovesAndObserveModeBlocksThemAgain() {
        connect(); client.isSocketAuthenticated = true
        client.activeGameID = 7; client.phase = "play"
        client.blackPlayerID = client.playerID
        client.observationOnly = true
        let before = socket.sentMessages.count
        client.sendMove(gameID: 7, x: 0, y: 0)
        XCTAssertEqual(socket.sentMessages.count, before)
        client.observationOnly = false
        client.sendMove(gameID: 7, x: 0, y: 0)
        XCTAssertEqual(socket.sentMessages.count, before + 1)
        XCTAssertTrue(socket.sentMessages.last!.contains("game/move"))
        client.observationOnly = true
        client.sendPass(gameID: 7)
        XCTAssertEqual(socket.sentMessages.count, before + 1)
    }

    func testGameCommandsRequireCurrentReadyParticipantAndCorrectPhase() {
        connect(); client.isSocketAuthenticated = true
        client.activeGameID = 7; client.phase = "play"
        client.blackPlayerID = client.playerID
        func assertBlocked(_ id: Int = 7, file: StaticString = #filePath, line: UInt = #line) {
            let count = socket.sentMessages.count
            client.sendMove(gameID: id, x: 0, y: 0)
            client.sendPass(gameID: id)
            client.resignGame(gameID: id)
            client.sendUndoRequest(gameID: id, moveNumber: 3)
            XCTAssertEqual(socket.sentMessages.count, count, file: file, line: line)
        }
        assertBlocked(8)
        client.isSocketAuthenticated = false; assertBlocked(); client.isSocketAuthenticated = true
        client.isConnected = false; assertBlocked(); client.isConnected = true
        client.isReconcilingMoves = true; assertBlocked(); client.isReconcilingMoves = false
        client.observationOnly = true; assertBlocked(); client.observationOnly = false
        client.blackPlayerID = 200; assertBlocked(); client.blackPlayerID = client.playerID
        client.phase = nil; assertBlocked()
        client.phase = "finished"; assertBlocked()
        client.phase = "play"; client.isGameFinished = true; assertBlocked(); client.isGameFinished = false
        let before = socket.sentMessages.count
        client.resignGame(gameID: 7)
        XCTAssertEqual(socket.sentMessages.count, before + 1)
        XCTAssertTrue(socket.sentMessages.last!.contains("game/resign"))
        client.phase = "stone removal"
        client.sendMove(gameID: 7, x: 0, y: 0); client.sendPass(gameID: 7)
        XCTAssertEqual(socket.sentMessages.count, before + 1)
        XCTAssertTrue(client.canResign)
    }

    func testNewGameClearsOldClockTurnAndUndoState() {
        client.activeGameID = 7
        client.blackPlayerName = "Old opponent"; client.blackPlayerRank = 35
        client.blackTimeRemaining = 3; client.whiteTimeRemaining = 4
        client.blackClockPeriods = 2; client.whiteClockPeriodTime = 30
        client.blackPeriodLength = 30; client.currentPlayerID = 1
        client.activeGameTimeControl = "Old time control"; client.currentHandicap = 4
        client.undoRequestedUsername = "Old opponent"; client.undoRequestedMoveNumber = 6
        client.isRequestingUndo = true; client.lastUndoneMoveNumber = 5
        client.activeGameID = 8
        XCTAssertNil(client.blackPlayerName); XCTAssertNil(client.blackPlayerRank)
        XCTAssertNil(client.blackTimeRemaining); XCTAssertNil(client.whiteTimeRemaining)
        XCTAssertNil(client.blackClockPeriods); XCTAssertNil(client.whiteClockPeriodTime)
        XCTAssertNil(client.blackPeriodLength); XCTAssertNil(client.currentPlayerID)
        XCTAssertNil(client.activeGameTimeControl); XCTAssertEqual(client.currentHandicap, 0)
        XCTAssertNil(client.undoRequestedUsername); XCTAssertNil(client.undoRequestedMoveNumber)
        XCTAssertNil(client.lastUndoneMoveNumber); XCTAssertFalse(client.isRequestingUndo)
        XCTAssertFalse(client.canResign); XCTAssertFalse(client.canPlayMoves)
    }

    func testChatRefusesDisconnectedWrongGameAndBlankMessages() {
        connect(); client.isSocketAuthenticated = true; client.activeGameID = 7
        let count = socket.sentMessages.count
        XCTAssertFalse(client.sendChat(gameID: 7, text: "  \n"))
        XCTAssertFalse(client.sendChat(gameID: 8, text: "Wrong game"))
        client.isSocketAuthenticated = false
        XCTAssertFalse(client.sendChat(gameID: 7, text: "Keep this draft"))
        client.isSocketAuthenticated = true; client.observationOnly = true
        XCTAssertFalse(client.sendChat(gameID: 7, text: "Observe is read only"))
        XCTAssertEqual(socket.sentMessages.count, count)
        client.observationOnly = false
        XCTAssertTrue(client.sendChat(gameID: 7, text: "Hello"))
        XCTAssertEqual(socket.sentMessages.count, count + 1)
    }

    func testUndoRequiresNonzeroMoveAndMatchingIncomingRequest() {
        connect(); client.isSocketAuthenticated = true
        client.activeGameID = 7; client.phase = "play"; client.blackPlayerID = client.playerID
        let before = socket.sentMessages.count
        client.sendUndoRequest(gameID: 7, moveNumber: 0)
        client.sendUndoAccept(gameID: 7, moveNumber: 3)
        client.sendUndoReject(gameID: 7)
        XCTAssertEqual(socket.sentMessages.count, before)
        client.undoRequestedMoveNumber = 3; client.undoRequestedUsername = "Opponent"
        client.sendUndoAccept(gameID: 7, moveNumber: 4)
        XCTAssertEqual(socket.sentMessages.count, before)
        client.sendUndoAccept(gameID: 7, moveNumber: 3)
        XCTAssertEqual(socket.sentMessages.count, before + 1)
        client.sendUndoAccept(gameID: 7, moveNumber: 3)
        XCTAssertEqual(socket.sentMessages.count, before + 1)
        socket.deliver(.failure(URLError(.networkConnectionLost)))
        XCTAssertFalse(client.isRequestingUndo)
        XCTAssertNil(client.undoRequestedMoveNumber)
    }

    func testInvalidChallengeDoesNotStartRequest() {
        var setup = ChallengeSetup(); setup.periodTime = 0
        var completed = false
        client.createChallenge(setup: setup) { ok, error in
            completed = true; XCTAssertFalse(ok); XCTAssertNotNil(error)
        }
        XCTAssertTrue(completed)
        XCTAssertFalse(client.isSearchingForGame)
    }

    func testLobbyDeleteFlagsAndMixedBatchesUseChallengeIDForBothEventNames() {
        connect(); client.isSocketAuthenticated = true
        for event in ["seekgraph/global", "seek_graph/global"] {
            client.refreshChallengeLobby()
            socket.deliver(.success("42[\"\(event)\",[{\"challenge_id\":1,\"username\":\"Keep\"},{\"challenge_id\":7,\"username\":\"Remove\"}]]"))
            drainMainQueue(); drainMainQueue()
            XCTAssertEqual(Set(client.availableGames.map(\.id)), [1, 7])
            socket.deliver(.success("42[\"\(event)\",[{\"challenge_id\":7,\"delete\":true},{\"challenge_id\":8,\"username\":\"New\"}]]"))
            drainMainQueue(); drainMainQueue()
            XCTAssertEqual(Set(client.availableGames.map(\.id)), [1, 8], "Boolean true must not remove challenge 1")
            socket.deliver(.success("42[\"\(event)\",{\"challenge_id\":8,\"game_started\":true}]"))
            socket.deliver(.success("42[\"\(event)\",{\"challenge_id\":8,\"username\":\"Stale late add\"}]"))
            drainMainQueue(); drainMainQueue()
            XCTAssertEqual(client.availableGames.map(\.id), [1], "Started/deleted challenges cannot immediately reappear")
            // Tombstones intentionally span a subscription refresh. Use a new client/socket for the next spelling.
            client.disconnect()
            socket = TestSocket()
            client = OGSClient(session: session, socketFactory: { [socket = socket!] in socket }, scoringScheduler: scoringScheduler)
            let ready = expectation(description: "New fixture identity loaded")
            let subscription = client.$isAuthenticated.filter { $0 }.sink { _ in ready.fulfill() }
            wait(for: [ready], timeout: 3); subscription.cancel()
            connect(); client.isSocketAuthenticated = true
        }
    }

    func testLobbyReturningRequestsFreshSubscriptionAndEmptyBatchKeepsItEmpty() {
        connect(); client.isSocketAuthenticated = true
        client.subscribeToSeekgraph()
        socket.deliver(.success(#"42["seekgraph/global",[{"challenge_id":7,"username":"Old"}]]"#))
        drainMainQueue(); drainMainQueue()
        XCTAssertEqual(client.availableGames.map(\.id), [7])
        client.activeGameID = 99
        client.isGameFinished = true
        client.leaveViewedGame()
        client.refreshChallengeLobby()
        XCTAssertTrue(client.availableGames.isEmpty)
        let messages = socket.sentMessages.filter { $0.contains("seek_graph/") }
        XCTAssertTrue(messages.suffix(2).first!.contains("seek_graph/disconnect"))
        XCTAssertTrue(messages.last!.contains("seek_graph/connect"))
        socket.deliver(.success(#"42["seekgraph/global",[]]"#))
        drainMainQueue(); drainMainQueue()
        XCTAssertTrue(client.availableGames.isEmpty, "An empty fresh subscription must not retain the old challenge")
        XCTAssertTrue(client.isConnected && client.isAuthenticated)
        XCTAssertFalse(socket.sentMessages.contains { $0.contains("game/resign") || $0.contains("challenge/remove") })
    }

    func testLobbyRefreshFencesQueuedOldBatchAndDoesNotClearPartialLiveUpdates() {
        connect(); client.isSocketAuthenticated = true
        socket.deliver(.success(#"42["seekgraph/global",[{"id":7,"username":"Old"}]]"#))
        client.refreshChallengeLobby()
        drainMainQueue(); drainMainQueue()
        XCTAssertTrue(client.availableGames.isEmpty)
        socket.deliver(.success(#"42["seekgraph/global",[{"id":8,"username":"A"}]]"#))
        socket.deliver(.success(#"42["seek_graph/global",[{"id":9,"username":"B"}]]"#))
        socket.deliver(.success(#"42["seekgraph/global",[]]"#))
        drainMainQueue(); drainMainQueue()
        XCTAssertEqual(Set(client.availableGames.map(\.id)), [8, 9], "Incremental batches must merge")
        socket.deliver(.success(#"42["seekgraph/global",{"delete":8}]"#))
        drainMainQueue(); drainMainQueue()
        XCTAssertEqual(client.availableGames.map(\.id), [9])
        socket.deliver(.success(#"42["seekgraph/global",{"id":9,"delete":false,"username":"B"}]"#))
        drainMainQueue(); drainMainQueue()
        XCTAssertEqual(client.availableGames.map(\.id), [9], "False is not a deletion")
    }

    func testLobbyGameAndChallengeIdentifiersAreNotInterchangeable() {
        connect(); client.isSocketAuthenticated = true
        client.finishedGameIDs = [7, 99]
        socket.deliver(.success(#"42["seekgraph/global",[{"challenge_id":7,"game_id":100,"username":"Unrelated challenge"},{"challenge_id":8,"game_id":99,"username":"Finished game"}]]"#))
        drainMainQueue(); drainMainQueue()
        XCTAssertEqual(client.availableGames.map(\.id), [7])
        socket.deliver(.success(#"42["seekgraph/global",{"game_id":100,"game_started":true}]"#))
        drainMainQueue(); drainMainQueue()
        XCTAssertTrue(client.availableGames.isEmpty)
    }

    func testConfirmedAcceptanceRemovesChallengeWithoutWaitingForSocketDelete() {
        connect(); client.isSocketAuthenticated = true
        socket.deliver(.success(#"42["seekgraph/global",[{"challenge_id":7,"username":"Opponent"}]]"#))
        drainMainQueue(); drainMainQueue()
        ClientHTTPFixture.handler = { $0.respond(status: 200, body: #"{"game_id":99}"#) }
        let done = expectation(description: "Accepted and removed")
        client.acceptChallenge(challengeID: 7) { id, error in
            XCTAssertEqual(id, 99); XCTAssertNil(error)
            XCTAssertTrue(self.client.availableGames.isEmpty)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        socket.deliver(.success(#"42["seekgraph/global",{"challenge_id":7,"username":"Late old row"}]"#))
        drainMainQueue(); drainMainQueue()
        XCTAssertTrue(client.availableGames.isEmpty)
    }

    func testForbiddenChallengeCancellationDoesNotHideChallengeAndRetryCanRemoveIt() {
        connect(); client.isSocketAuthenticated = true
        socket.deliver(.success(#"42["seek_graph/global",[{"id":7,"user_id":1,"username":"fixture","width":19,"height":19,"time_per_move":60}]]"#))
        drainMainQueue(); drainMainQueue()
        XCTAssertTrue(client.availableGames.contains { $0.id == 7 })
        ClientHTTPFixture.handler = { $0.respond(status: 403, body: "{}") }
        let failed = expectation(description: "Cancellation failure surfaced")
        let subscription = client.$lastError.compactMap { $0 }.sink { error in
            XCTAssertTrue(error.contains("403")); failed.fulfill()
        }
        client.cancelChallenge(challengeID: 7)
        wait(for: [failed], timeout: 3); subscription.cancel()
        drainMainQueue()
        XCTAssertTrue(client.availableGames.contains { $0.id == 7 }, "403 does not mean the challenge is gone")
        ClientHTTPFixture.handler = { $0.respond(status: 204, body: "") }
        let removed = expectation(description: "Confirmed cancellation removes challenge")
        let listSubscription = client.$availableGames.dropFirst().filter { $0.allSatisfy { $0.id != 7 } }
            .sink { _ in removed.fulfill() }
        client.cancelChallenge(challengeID: 7)
        wait(for: [removed], timeout: 3); listSubscription.cancel()
        XCTAssertNil(client.lastError)
    }

    func testReviewCookiesAreInMemoryAndSeparateFromOtherSessions() throws {
        let first = OGSClient.reviewSessionConfiguration()
        let second = OGSClient.reviewSessionConfiguration()
        let firstStore = try XCTUnwrap(first.httpCookieStorage)
        let secondStore = try XCTUnwrap(second.httpCookieStorage)
        XCTAssertFalse(firstStore === HTTPCookieStorage.shared)
        XCTAssertFalse(firstStore === secondStore)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "review-fixture.invalid",
            .path: "/", .name: "session", .value: "fixture-only"]))
        firstStore.setCookie(cookie)
        XCTAssertEqual(firstStore.cookies?.count, 1)
        XCTAssertTrue(secondStore.cookies?.isEmpty ?? true)
        XCTAssertNil(first.urlCredentialStorage?.allCredentials.first)
    }

    func testReviewLoginPersistsAcrossFreshClientsAndLogoutRemovesIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("SessionCookies.plist")
        func freshClient() {
            client.disconnect()
            session.invalidateAndCancel()
            let config = OGSClient.reviewSessionConfiguration()
            config.protocolClasses = [ClientHTTPFixture.self]
            session = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
            client = OGSClient(session: session, socketFactory: { [socket = socket!] in socket },
                observationOnly: true, reviewSessionStore: OGSReviewSessionStore(fileURL: url))
        }
        ClientHTTPFixture.configHandler = { [unowned self] fixture in
            let saved = self.session.configuration.httpCookieStorage?.cookies?.contains { $0.name == "sessionid" } == true
            fixture.respond(status: 200, body: saved ? #"{"user":{"id":2,"username":"review"},"user_jwt":"fresh-fixture-token"}"# : "{}")
        }
        freshClient()
        let anonymous = expectation(description: "Initial guest check")
        client.fetchUserConfig { ok, _ in XCTAssertFalse(ok); anonymous.fulfill() }
        wait(for: [anonymous], timeout: 3)
        ClientHTTPFixture.handler = { [unowned self] fixture in
            XCTAssertEqual(fixture.request.url?.path, "/api/v0/login")
            let cookie = HTTPCookie(properties: [.name: "sessionid", .value: "fixture-session",
                .domain: "online-go.com", .path: "/", .discard: "TRUE"])!
            self.session.configuration.httpCookieStorage?.setCookie(cookie)
            fixture.respond(status: 204, body: "")
        }
        let signedIn = expectation(description: "Login persisted")
        client.login(username: "review", password: "never-save-this-password") { ok, _ in
            XCTAssertTrue(ok); signedIn.fulfill()
        }
        wait(for: [signedIn], timeout: 3)
        XCTAssertEqual(try OGSReviewSessionStore(fileURL: url).load().map(\.name), ["sessionid"])
        let saved = try Data(contentsOf: url)
        XCTAssertNil(saved.range(of: Data("never-save-this-password".utf8)))
        XCTAssertNil(saved.range(of: Data("fresh-fixture-token".utf8)))
        freshClient() // A new client/session/store, with no login call or password.
        let restored = expectation(description: "Saved session validated")
        let observation = client.$isAuthenticated.filter { $0 }.sink { _ in restored.fulfill() }
        wait(for: [restored], timeout: 3); observation.cancel()
        XCTAssertEqual(client.username, "review")
        XCTAssertEqual(client.userJWT, "fresh-fixture-token")
        client.logout()
        XCTAssertFalse(client.isAuthenticated)
        XCTAssertTrue(try OGSReviewSessionStore(fileURL: url).load().isEmpty)
        XCTAssertTrue(session.configuration.httpCookieStorage?.cookies?.isEmpty ?? true)
        freshClient()
        let loggedOut = expectation(description: "Restart stays logged out")
        client.fetchUserConfig { ok, _ in XCTAssertFalse(ok); loggedOut.fulfill() }
        wait(for: [loggedOut], timeout: 3)
    }

    func testReviewLogoutRejectsLateValidationAndTransientFailureKeepsSavedSession() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OGSReviewSessionStore(fileURL: folder.appendingPathComponent("cookies.plist"))
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "sessionid", .value: "fixture",
            .domain: "online-go.com", .path: "/"]))
        try store.save([cookie])
        client.disconnect()
        client = OGSClient(session: session, socketFactory: { [socket = socket!] in socket }, reviewSessionStore: store)
        ClientHTTPFixture.configHandler = { $0.respond(status: 503, body: "{}") }
        let failed = expectation(description: "Temporary failure")
        client.fetchUserConfig { ok, _ in XCTAssertFalse(ok); failed.fulfill() }
        wait(for: [failed], timeout: 3)
        XCTAssertEqual(try store.load().count, 1)
        var held: ClientHTTPFixture?
        let requested = expectation(description: "Held validation")
        ClientHTTPFixture.configHandler = { held = $0; requested.fulfill() }
        client.fetchUserConfig()
        wait(for: [requested], timeout: 3)
        client.logout()
        held?.respond(status: 200, body: #"{"user":{"id":2,"username":"review"},"user_jwt":"late-token"}"#)
        drainMainQueue()
        XCTAssertFalse(client.isAuthenticated)
        XCTAssertTrue(try store.load().isEmpty)
        try store.save([cookie])
        ClientHTTPFixture.configHandler = { $0.respond(status: 401, body: "{}") }
        let revoked = expectation(description: "Revoked session")
        client.fetchUserConfig { ok, _ in XCTAssertFalse(ok); revoked.fulfill() }
        wait(for: [revoked], timeout: 3)
        XCTAssertTrue(try store.load().isEmpty)
    }

    private func lastGameListRequest() throws -> (Int, [String: Any]) {
        let packet = try XCTUnwrap(socket.sentMessages.last { $0.contains("gamelist/query") })
        let body = packet.dropFirst(2)
        let digits = body.prefix { $0.isNumber }
        let id = try XCTUnwrap(Int(digits))
        let args = try JSONSerialization.jsonObject(with: Data(body.dropFirst(digits.count).utf8)) as! [Any]
        XCTAssertEqual(packet.prefix(2), "42")
        XCTAssertEqual(args.count, 2, "Ack ID belongs in the frame, not in the event arguments")
        XCTAssertEqual(args[0] as? String, "gamelist/query")
        return (id, args[1] as! [String: Any])
    }

    func testObservationListQueriesReadOnlyPageAndParsesPlayers() throws {
        client.disconnect()
        client = OGSClient(session: session, socketFactory: { [socket = socket!] in socket },
            scoringScheduler: scoringScheduler, observationOnly: true)
        connect(); client.isSocketAuthenticated = true
        client.fetchObservedGames()
        let (id, query) = try lastGameListRequest()
        XCTAssertEqual(query["list"] as? String, "live")
        XCTAssertEqual(query["sort_by"] as? String, "rank")
        XCTAssertEqual(query["from"] as? Int, 0)
        XCTAssertEqual(query["limit"] as? Int, 20)
        client.fetchObservedGames()
        XCTAssertEqual(socket.sentMessages.filter { $0.contains("gamelist/query") }.count, 1)
        socket.deliver(.success("43\(id)" + #"[{"size":43,"results":[{"id":7,"black":{"username":"Alice"},"white":{"username":"Bob"},"width":19,"height":19},{"id":7},{"id":0},{"id":8,"phase":"finished"},{"id":9,"ended":"yesterday"},{"id":10,"players":{"black":{"username":"Carol"},"white":{"username":"Dave"}},"ended":null}]}]"#))
        XCTAssertFalse(client.isLoadingObservedGames)
        XCTAssertEqual(client.observedGames.map(\.id), [7, 10])
        XCTAssertEqual(client.observedGames.first?.blackName, "Alice")
        XCTAssertEqual(client.observedGames.first?.whiteName, "Bob")
        XCTAssertEqual(client.observedGames.first?.boardSize, "19×19")
        XCTAssertEqual(client.observedGames.last?.whiteName, "Dave")
        XCTAssertNil(client.activeGameID, "Browsing must not join a game")
        XCTAssertEqual(client.observedGamesTotal, 43)
        client.fetchObservedGames(page: 1)
        let (next, nextQuery) = try lastGameListRequest()
        XCTAssertEqual(nextQuery["from"] as? Int, 20)
        socket.deliver(.success("43\(next)" + #"[{"size":43,"results":[]}]"#))
        XCTAssertEqual(client.observedGamesPage, 1)
        XCTAssertEqual(client.observedGames.map(\.id), [7, 10])
        XCTAssertFalse(client.hasMoreObservedGames)
    }

    func testObservationListTimeoutAndErrorAllowRetryAndIgnoreLateReply() throws {
        connect(); client.isSocketAuthenticated = true
        client.fetchObservedGames()
        let (oldID, _) = try lastGameListRequest()
        scoringScheduler.advance(by: 12)
        XCTAssertFalse(client.isLoadingObservedGames)
        XCTAssertNotNil(client.observedGamesError)
        socket.deliver(.success("43\(oldID)" + #"[{"size":1,"results":[{"id":7}]}]"#))
        XCTAssertTrue(client.observedGames.isEmpty)
        client.fetchObservedGames()
        let (id, _) = try lastGameListRequest()
        XCTAssertNotEqual(id, oldID)
        socket.deliver(.success("43\(id)[null,{\"message\":\"fixture failure\"}]"))
        XCTAssertFalse(client.isLoadingObservedGames)
        XCTAssertNotNil(client.observedGamesError)
        client.fetchObservedGames()
        let (retry, _) = try lastGameListRequest()
        socket.deliver(.success("43\(retry)" + #"[{"size":0,"results":[]}]"#))
        XCTAssertNil(client.observedGamesError)
        XCTAssertTrue(client.observedGames.isEmpty)
    }

    func testObservationListAppendsSortedBatchesRetriesAndRefreshes() throws {
        connect(); client.isSocketAuthenticated = true
        client.fetchObservedGames()
        let (first, _) = try lastGameListRequest()
        socket.deliver(.success("43\(first)" + #"[{"size":50,"results":[{"id":7,"black":{"ranking":25},"white":{"ranking":30}},{"id":8,"black":{"ranking":32}}]}]"#))
        XCTAssertEqual(client.observedGames.map(\.id), [8, 7])
        XCTAssertTrue(client.hasMoreObservedGames)
        client.loadMoreObservedGames()
        let (next, query) = try lastGameListRequest()
        XCTAssertEqual(query["from"] as? Int, 20)
        client.loadMoreObservedGames()
        XCTAssertEqual(try lastGameListRequest().0, next)
        scoringScheduler.advance(by: 12)
        XCTAssertEqual(client.observedGames.map(\.id), [8, 7])
        XCTAssertNotNil(client.observedGamesError)
        client.loadMoreObservedGames()
        let (retry, _) = try lastGameListRequest()
        socket.deliver(.success("43\(next)" + #"[{"size":50,"results":[{"id":99}]}]"#))
        XCTAssertTrue(client.isLoadingObservedGames)
        socket.deliver(.success("43\(retry)" + #"[{"size":50,"results":[{"id":9,"white":{"ranking":35}},{"id":7,"black":{"ranking":25},"white":{"ranking":30},"json":{"moves":[[0,0],[1,1]]}}]}]"#))
        XCTAssertEqual(client.observedGames.map(\.id), [9, 8, 7])
        XCTAssertEqual(client.observedGames.last?.moveCount, 2)
        XCTAssertNil(client.observedGamesError)
        client.loadMoreObservedGames()
        let (last, lastQuery) = try lastGameListRequest()
        XCTAssertEqual(lastQuery["from"] as? Int, 40)
        socket.deliver(.success("43\(last)" + #"[{"size":40,"results":[]}]"#))
        XCTAssertFalse(client.hasMoreObservedGames)
        client.loadMoreObservedGames()
        XCTAssertEqual(try lastGameListRequest().0, last)
        client.fetchObservedGames()
        let (refresh, _) = try lastGameListRequest()
        socket.deliver(.success("43\(refresh)" + #"[{"size":1,"results":[{"id":10}]}]"#))
        XCTAssertEqual(client.observedGames.map(\.id), [10])
        XCTAssertFalse(client.hasMoreObservedGames)
    }

    func testObservationListSupersededPageAndLogoutCannotRepopulate() throws {
        connect(); client.isSocketAuthenticated = true
        client.fetchObservedGames()
        let (first, _) = try lastGameListRequest()
        socket.deliver(.success("43\(first)" + #"[{"size":50,"results":[{"id":7}]}]"#))
        client.loadMoreObservedGames()
        let (old, _) = try lastGameListRequest()
        client.fetchObservedGames() // Refresh supersedes the pending append.
        let (current, _) = try lastGameListRequest()
        socket.deliver(.success("43\(old)" + #"[{"size":50,"results":[{"id":8}]}]"#))
        XCTAssertTrue(client.isLoadingObservedGames)
        XCTAssertEqual(client.observedGames.map(\.id), [7])
        socket.deliver(.success("43\(current)" + #"[{"size":50,"results":[{"id":9}]}]"#))
        XCTAssertEqual(client.observedGamesPage, 0)
        XCTAssertEqual(client.observedGames.map(\.id), [9])
        client.loadMoreObservedGames()
        let (pending, _) = try lastGameListRequest()
        client.logout()
        socket.deliver(.success("43\(pending)" + #"[{"size":50,"results":[{"id":8}]}]"#))
        XCTAssertTrue(client.observedGames.isEmpty)
        XCTAssertFalse(client.isLoadingObservedGames)
        XCTAssertFalse(client.hasMoreObservedGames)
        let sent = socket.sentMessages.count
        client.fetchObservedGames()
        XCTAssertEqual(socket.sentMessages.count, sent)
        XCTAssertNotNil(client.observedGamesError)
    }

    func testObservedClockDetailsAreLazyBoundedCachedAndIndependentOfActiveGame() throws {
        connect(); client.isSocketAuthenticated = true
        client.activeGameID = 99
        client.fetchObservedGames()
        let (id, _) = try lastGameListRequest()
        socket.deliver(.success("43\(id)" + #"[{"size":4,"results":[{"id":7},{"id":8},{"id":9},{"id":10}]}]"#))
        var held: [ClientHTTPFixture] = []
        let firstThree = expectation(description: "At most three concurrent metadata reads")
        firstThree.expectedFulfillmentCount = 3
        let fourth = expectation(description: "Queued row starts after a slot opens")
        ClientHTTPFixture.handler = { fixture in
            XCTAssertEqual(fixture.request.httpMethod, "GET")
            held.append(fixture)
            if held.count <= 3 { firstThree.fulfill() } else { fourth.fulfill() }
        }
        XCTAssertTrue(held.isEmpty, "Listing alone must not download every game's detail")
        for row in client.observedGames { client.loadObservedTimeControl(for: row) }
        wait(for: [firstThree], timeout: 3)
        XCTAssertEqual(held.count, 3)
        let path = held[0].request.url!.lastPathComponent
        let loaded = expectation(description: "Full clock displayed")
        let observation = client.$observedTimeControls.filter { $0[Int(path)!] == "20m + 5×30s" }.sink { _ in loaded.fulfill() }
        held[0].respond(status: 200, body: #"{"gamedata":{"time_control":{"system":"byoyomi","main_time":1200,"periods":5,"period_time":30}}}"#)
        wait(for: [loaded, fourth], timeout: 3)
        observation.cancel()
        for row in client.observedGames { client.loadObservedTimeControl(for: row) }
        XCTAssertEqual(held.count, 4, "Repeated appearances reuse the cached/in-flight read")
        XCTAssertEqual(client.activeGameID, 99)
        XCTAssertFalse(socket.sentMessages.contains { $0.contains("game/connect") })
        client.disconnect()
        drainMainQueue()
        XCTAssertTrue(client.observedTimeControls.isEmpty)
    }

    func testObservedClockFailureRequiresRefreshAndOldCompletionIsDiscarded() throws {
        connect(); client.isSocketAuthenticated = true
        client.fetchObservedGames()
        let (id, _) = try lastGameListRequest()
        socket.deliver(.success("43\(id)" + #"[{"size":1,"results":[{"id":7}]}]"#))
        let failed = expectation(description: "Failure shown on row")
        let observation = client.$observedTimeControls.filter { $0[7]?.contains("Retrying") == true }.sink { _ in failed.fulfill() }
        var requests = 0
        ClientHTTPFixture.handler = { fixture in requests += 1; fixture.respond(status: 503, body: "{}") }
        client.loadObservedTimeControl(for: client.observedGames[0])
        wait(for: [failed], timeout: 3); observation.cancel()
        client.loadObservedTimeControl(for: client.observedGames[0]); drainMainQueue()
        XCTAssertEqual(requests, 1)
        client.fetchObservedGames()
        let (refresh, _) = try lastGameListRequest()
        socket.deliver(.success("43\(refresh)" + #"[{"size":1,"results":[{"id":7}]}]"#))
        let requested = expectation(description: "Refresh permits retry")
        ClientHTTPFixture.handler = { fixture in
            requests += 1
            // Completion is queued, then invalidated before it can touch the new list.
            fixture.respond(status: 200, body: #"{"gamedata":{"time_control":{"system":"none"}}}"#)
            self.client.disconnect()
            requested.fulfill()
        }
        client.loadObservedTimeControl(for: client.observedGames[0])
        wait(for: [requested], timeout: 3); drainMainQueue()
        XCTAssertEqual(requests, 2)
        XCTAssertTrue(client.observedTimeControls.isEmpty)
    }

    func testAutomaticObservedRefreshPreservesLoadedDepthAndCommitsAtomically() throws {
        connect(); client.isSocketAuthenticated = true
        func reply(_ ids: [Int], total: Int = 45, moves: Int = 1) throws {
            let (id, _) = try lastGameListRequest()
            let rows = ids.map { ["id": $0, "move_number": moves] }
            let data = try JSONSerialization.data(withJSONObject: [["size": total, "results": rows]])
            socket.deliver(.success("43\(id)" + String(decoding: data, as: UTF8.self)))
        }
        client.fetchObservedGames(); try reply(Array(1...20))
        client.loadMoreObservedGames(); try reply(Array(21...40))
        let old = client.observedGames.map(\.id)
        client.refreshObservedGames()
        let (first, _) = try lastGameListRequest()
        client.refreshObservedGames(); client.loadMoreObservedGames()
        XCTAssertEqual(try lastGameListRequest().0, first, "Coalesce refresh and pagination")
        try reply(Array(2...21), moves: 9)
        XCTAssertEqual(try lastGameListRequest().1["from"] as? Int, 20)
        XCTAssertEqual(client.observedGames.map(\.id), old, "Keep old list until every loaded batch arrives")
        XCTAssertTrue(client.isLoadingObservedGames)
        try reply(Array(22...41), moves: 9)
        XCTAssertEqual(Set(client.observedGames.map(\.id)), Set(2...41))
        XCTAssertEqual(client.observedGamesPage, 1)
        XCTAssertTrue(client.hasMoreObservedGames)
        XCTAssertTrue(client.observedGames.allSatisfy { $0.moveCount == 9 })
        XCTAssertFalse(client.isLoadingObservedGames)
        client.refreshObservedGames()
        try reply([42], total: 1)
        XCTAssertEqual(client.observedGames.map(\.id), [42], "Finished games disappear; a shorter list ends early")
        XCTAssertEqual(client.observedGamesPage, 0)
        XCTAssertFalse(client.hasMoreObservedGames)
        XCTAssertNil(client.activeGameID)
    }

    func testAutomaticObservedRefreshTimeoutCancellationAndLogoutFenceReplies() throws {
        connect(); client.isSocketAuthenticated = true
        client.fetchObservedGames()
        let (initial, _) = try lastGameListRequest()
        socket.deliver(.success("43\(initial)" + #"[{"size":1,"results":[{"id":7}]}]"#))
        client.refreshObservedGames()
        let (cancelled, _) = try lastGameListRequest()
        client.cancelObservedGamesRefresh()
        socket.deliver(.success("43\(cancelled)" + #"[{"size":1,"results":[{"id":8}]}]"#))
        XCTAssertEqual(client.observedGames.map(\.id), [7])
        XCTAssertFalse(client.isLoadingObservedGames)
        client.refreshObservedGames()
        let (timedOut, _) = try lastGameListRequest()
        scoringScheduler.advance(by: 12)
        XCTAssertNotNil(client.observedGamesError)
        XCTAssertEqual(client.observedGames.map(\.id), [7])
        client.refreshObservedGames()
        let (current, _) = try lastGameListRequest()
        socket.deliver(.success("43\(timedOut)" + #"[{"size":1,"results":[{"id":9}]}]"#))
        XCTAssertTrue(client.isLoadingObservedGames)
        client.logout()
        socket.deliver(.success("43\(current)" + #"[{"size":1,"results":[{"id":10}]}]"#))
        XCTAssertTrue(client.observedGames.isEmpty)
        XCTAssertFalse(client.isLoadingObservedGames)
        let sent = socket.sentMessages.count
        client.refreshObservedGames()
        XCTAssertEqual(socket.sentMessages.count, sent)
    }

    func testAutomaticObservedRefreshRetainsSuccessfulAndInFlightTimeControls() throws {
        connect(); client.isSocketAuthenticated = true
        func reply() throws {
            let (id, _) = try lastGameListRequest()
            socket.deliver(.success("43\(id)" + #"[{"size":2,"results":[{"id":7},{"id":8}]}]"#))
        }
        client.refreshObservedGames(); try reply()
        var held: ClientHTTPFixture?
        let requested = expectation(description: "Detail in flight")
        ClientHTTPFixture.handler = { fixture in held = fixture; requested.fulfill() }
        client.loadObservedTimeControl(for: client.observedGames[0])
        wait(for: [requested], timeout: 3)
        client.refreshObservedGames(); try reply()
        let loaded = expectation(description: "Detail survives refresh")
        let subscription = client.$observedTimeControls.filter { $0[7] == "No time limit" }.sink { _ in loaded.fulfill() }
        held?.respond(status: 200, body: #"{"gamedata":{"time_control":{"system":"none"}}}"#)
        wait(for: [loaded], timeout: 3); subscription.cancel()
        client.refreshObservedGames(); try reply()
        XCTAssertEqual(client.observedTimeControls[7], "No time limit")
        ClientHTTPFixture.handler = { _ in XCTFail("Successful time control should stay cached") }
        client.loadObservedTimeControl(for: client.observedGames[0]); drainMainQueue()
    }

    func testObservedWinnerIncludesActualColorForEitherPlayer() {
        startScoring(); client.playerID = 99
        client.blackPlayerName = "Alice"; client.whitePlayerName = "Bob"
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"phase":"finished","winner":1,"outcome":"3.5 points"}]"#))
        XCTAssertEqual(client.activeGameResult?.subtitle, "Alice [Black] wins")
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"phase":"finished","winner":2,"outcome":"Resignation"}]"#))
        XCTAssertEqual(client.activeGameResult?.subtitle, "Bob [White] wins")
        XCTAssertEqual(client.activeGameOutcome, "Bob [White] wins by Resignation")
        socket.deliver(.success(#"42["game/7/removed_stones_accepted",{"phase":"finished","winner":0,"outcome":"0 points"}]"#))
        XCTAssertEqual(client.activeGameResult?.title, "Draw")
    }

    func testObserveGameInputAcceptsOnlyPositiveIDsAndOGSGameLinks() {
        for input in ["12345", " 12345\n", "https://online-go.com/game/12345",
                      "https://online-go.com/game/12345/?move=20", "https://www.online-go.com/game/12345"] {
            XCTAssertEqual(OGSClient.observationGameID(input), 12345, input)
        }
        for input in ["", "0", "-1", "1.5", "https://other.example/game/12345",
                      "https://online-go.com.evil.example/game/12345", "https://online-go.com/player/12345",
                      "https://user@online-go.com/game/12345", "https://online-go.com/game/12345/extra",
                      "9999999999999999999999999"] {
            XCTAssertNil(OGSClient.observationGameID(input), input)
        }
    }

}

/// All URLs, including production-looking OGS URLs, are intercepted. There is no network fallback.
private final class ClientHTTPFixture: URLProtocol {
    static var handler: ((ClientHTTPFixture) -> Void)?
    static var configHandler: ((ClientHTTPFixture) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.main.async {
            if self.request.url?.path == "/api/v1/ui/config" {
                if let handler = Self.configHandler { handler(self) }
                else { self.respond(status: 200, body: #"{"user":{"id":1,"username":"fixture"},"user_jwt":"fixture-token"}"#) }
            } else if let handler = Self.handler { handler(self) }
            else { self.fail(URLError(.unsupportedURL)) }
        }
    }
    override func stopLoading() {}
    func respond(status: Int, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    func fail(_ error: Error) { client?.urlProtocol(self, didFailWithError: error) }
}
