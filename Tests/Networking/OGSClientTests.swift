import XCTest
import Combine
@testable import SGFPlayerNetworking

final class OGSClientTests: XCTestCase {
    private var client: OGSClient!
    private var session: URLSession!
    private var socket: TestSocket!

    override func setUp() {
        socket = TestSocket()
        ClientHTTPFixture.handler = { fixture in
            XCTFail("Unexpected request: \(fixture.request.url!.path)")
            fixture.respond(status: 500, body: "{}")
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClientHTTPFixture.self]
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
        client = OGSClient(session: session, socketFactory: { [socket = socket!] in socket })
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

    func testCurrentGameScoringUpdateStillApplies() {
        connect()
        client.activeGameID = 7
        socket.deliver(.success(#"42["game/7/stone_removal",{"removed":"aa"}]"#))
        drainMainQueue()
        XCTAssertEqual(client.removedStones, [BoardPosition(0, 0)])
    }
}

/// All URLs, including production-looking OGS URLs, are intercepted. There is no network fallback.
private final class ClientHTTPFixture: URLProtocol {
    static var handler: ((ClientHTTPFixture) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.main.async {
            if self.request.url?.path == "/api/v1/ui/config" {
                self.respond(status: 200, body: #"{"user":{"id":1,"username":"fixture"},"user_jwt":"fixture-token"}"#)
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
