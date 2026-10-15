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
        XCTAssertTrue(client.isSearchingForGame)
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
