import XCTest
@testable import SGFPlayerNetworking

final class OGSConnectionControllerTests: XCTestCase {
    private var scheduler: TestScheduler!
    private var sockets: [TestSocket]!
    private var controller: OGSConnectionController!
    private var messages: [String]!
    private var errors: [Error]!

    override func setUp() {
        super.setUp()
        scheduler = TestScheduler()
        sockets = []
        messages = []
        errors = []
        controller = OGSConnectionController(scheduler: scheduler) { [unowned self] in
            let socket = TestSocket()
            self.sockets.append(socket)
            return socket
        }
        controller.onMessage = { [unowned self] in self.messages.append($0) }
        controller.onError = { [unowned self] in self.errors.append($0) }
    }

    override func tearDown() {
        controller.disconnect()
        controller = nil
        super.tearDown()
    }

    func testRepeatedConnectKeepsOneSocketAndOneReceiveLoop() {
        controller.connect()
        controller.connect()
        XCTAssertEqual(sockets.count, 1)
        let socket = sockets[0]
        socket.onOpen?()
        socket.deliver(.success("first"))
        socket.deliver(.success("second"))
        XCTAssertEqual(messages, ["first", "second"])
        XCTAssertEqual(socket.receivers.count, 1)
        XCTAssertEqual(socket.resumeCount, 1)
    }

    func testReceiveFailureReconnectsAndCanReceiveAgain() {
        controller.connect()
        sockets[0].onOpen?()
        sockets[0].deliver(.failure(URLError(.networkConnectionLost)))
        XCTAssertEqual(controller.state, .reconnecting(delay: 1))
        XCTAssertTrue(sockets[0].cancelled)
        scheduler.advance(by: 1)
        XCTAssertEqual(sockets.count, 2)
        sockets[1].onOpen?()
        sockets[1].deliver(.success("new game snapshot"))
        XCTAssertEqual(messages, ["new game snapshot"])
        XCTAssertEqual(controller.state, .connected)
    }

    func testDisconnectCancelsRetryEvenIfCancelledWorkRuns() {
        controller.connect()
        sockets[0].deliver(.failure(URLError(.notConnectedToInternet)))
        let retry = scheduler.jobs.last!
        controller.disconnect()
        retry.action() // A callback already dequeued when cancellation occurred.
        scheduler.advance(by: 60)
        XCTAssertEqual(sockets.count, 1)
        XCTAssertEqual(controller.state, .disconnected)
    }

    func testOldSocketCallbacksCannotAffectReplacement() {
        controller.connect()
        let old = sockets[0]
        let oldOpen = old.onOpen!
        let oldClose = old.onClose!
        controller.disconnect()
        controller.connect()
        sockets[1].onOpen?()
        oldOpen()
        oldClose(URLError(.networkConnectionLost))
        old.deliver(.success("stale game state"))
        XCTAssertEqual(controller.state, .connected)
        XCTAssertTrue(messages.isEmpty)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(old.receivers.count, 0)
        XCTAssertEqual(sockets[1].receivers.count, 1)
    }

    func testReceiveAndCloseFailureScheduleOnlyOneRetry() {
        controller.connect()
        let socket = sockets[0]
        let close = socket.onClose!
        socket.deliver(.failure(URLError(.networkConnectionLost)))
        close(nil)
        scheduler.advance(by: 1)
        XCTAssertEqual(sockets.count, 2)
        XCTAssertEqual(errors.count, 1)
    }

    func testUnexpectedCleanCloseAlsoReconnects() {
        controller.connect()
        sockets[0].onOpen?()
        sockets[0].onClose?(nil)
        XCTAssertEqual(controller.state, .reconnecting(delay: 1))
    }

    func testOpenTimeoutRecoversFromConnectionThatNeverOpens() {
        controller.connect()
        scheduler.advance(by: 15)
        XCTAssertEqual(controller.state, .reconnecting(delay: 1))
        XCTAssertTrue(sockets[0].cancelled)
    }

    func testBackoffIsCappedAndConnectDoesNotBypassIt() {
        controller.connect()
        for delay in [1.0, 2, 4, 8, 16, 30, 30] {
            sockets.last!.onOpen?() // Rapid open/close must not reset the backoff.
            sockets.last!.deliver(.failure(URLError(.networkConnectionLost)))
            XCTAssertEqual(controller.state, .reconnecting(delay: delay))
            let count = sockets.count
            controller.connect()
            XCTAssertEqual(sockets.count, count)
            scheduler.advance(by: delay)
            XCTAssertEqual(sockets.count, count + 1)
        }
    }

    func testMissingPongDetectsHalfOpenConnection() {
        controller.connect()
        sockets[0].onOpen?()
        scheduler.advance(by: 10)
        XCTAssertEqual(sockets[0].pings.count, 1)
        scheduler.advance(by: 10)
        XCTAssertEqual(controller.state, .reconnecting(delay: 1))
        XCTAssertTrue(sockets[0].cancelled)
    }

    func testPongCancelsDeadlineAndResetsBackoff() {
        controller.connect()
        sockets[0].deliver(.failure(URLError(.networkConnectionLost)))
        scheduler.advance(by: 1)
        sockets[1].onOpen?()
        scheduler.advance(by: 10)
        sockets[1].pings.removeFirst()(nil)
        scheduler.advance(by: 9)
        XCTAssertEqual(controller.state, .connected)
        sockets[1].deliver(.failure(URLError(.networkConnectionLost)))
        XCTAssertEqual(controller.state, .reconnecting(delay: 1))
    }

    func testLatePongCannotReviveDisconnectedConnection() {
        controller.connect()
        sockets[0].onOpen?()
        scheduler.advance(by: 10)
        let pong = sockets[0].pings.removeFirst()
        controller.disconnect()
        pong(nil)
        scheduler.advance(by: 60)
        XCTAssertEqual(controller.state, .disconnected)
        XCTAssertEqual(sockets.count, 1)
    }

    func testSendFailureRecoversWithoutReplayingMove() {
        controller.connect()
        sockets[0].onOpen?()
        controller.send("game/move")
        sockets[0].sends.removeFirst()(URLError(.networkConnectionLost))
        scheduler.advance(by: 1)
        sockets[1].onOpen?()
        XCTAssertEqual(sockets[0].sentMessages, ["game/move"])
        XCTAssertTrue(sockets[1].sentMessages.isEmpty)
        XCTAssertEqual(errors.count, 1)
    }

    func testDisconnectedSendIsReportedAndNotQueued() {
        controller.send("game/move")
        XCTAssertEqual(errors.count, 1)
        controller.connect()
        sockets[0].onOpen?()
        XCTAssertTrue(sockets[0].sentMessages.isEmpty)
    }

    func testObserverCanDisconnectWhileReceiving() {
        controller.onMessage = { [unowned self] _ in self.controller.disconnect() }
        controller.connect()
        sockets[0].onOpen?()
        sockets[0].deliver(.success("finished"))
        XCTAssertEqual(controller.state, .disconnected)
        XCTAssertEqual(sockets[0].receivers.count, 0)
    }

    func testObserverCanCancelConnectionBeforeSocketStarts() {
        controller.onStateChange = { [unowned self] state in
            if state == .connecting { self.controller.disconnect() }
        }
        controller.connect()
        scheduler.advance(by: 60)
        XCTAssertEqual(controller.state, .disconnected)
        XCTAssertEqual(sockets[0].resumeCount, 0)
        XCTAssertTrue(sockets[0].receivers.isEmpty)
    }

    func testObserverCanDisconnectOnOpenWithoutLeavingHeartbeatWork() {
        controller.onStateChange = { [unowned self] state in
            if state == .connected { self.controller.disconnect() }
        }
        controller.connect()
        sockets[0].onOpen?()
        XCTAssertEqual(controller.state, .disconnected)
        XCTAssertTrue(scheduler.jobs.allSatisfy { $0.cancelled })
    }

    func testBackgroundCallbacksAreDeliveredOnMainQueue() {
        controller.connect()
        let socket = sockets[0]
        let received = expectation(description: "Message delivered on main queue")
        controller.onMessage = { text in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(text, "background message")
            received.fulfill()
        }
        DispatchQueue.global().async {
            socket.onOpen?()
            socket.deliver(.success("background message"))
        }
        wait(for: [received], timeout: 2)
        XCTAssertEqual(controller.state, .connected)
    }
}

private final class TestSocket: OGSWebSocket {
    var onOpen: (() -> Void)?
    var onClose: ((Error?) -> Void)?
    var receivers: [(Result<String, Error>) -> Void] = []
    var sends: [(Error?) -> Void] = []
    var pings: [(Error?) -> Void] = []
    var sentMessages: [String] = []
    var resumeCount = 0
    var cancelled = false

    func resume() { resumeCount += 1 }
    func receive(_ completion: @escaping (Result<String, Error>) -> Void) { receivers.append(completion) }
    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        sentMessages.append(text)
        sends.append(completion)
    }
    func ping(_ completion: @escaping (Error?) -> Void) { pings.append(completion) }
    func cancel() { cancelled = true }
    func deliver(_ result: Result<String, Error>) { receivers.removeFirst()(result) }
}

final class TestScheduler: OGSConnectionScheduler {
    final class Job: OGSCancellable {
        let due: TimeInterval
        let action: () -> Void
        var cancelled = false
        init(due: TimeInterval, action: @escaping () -> Void) { self.due = due; self.action = action }
        func cancel() { cancelled = true }
    }
    var now: TimeInterval = 0
    var jobs: [Job] = []
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> OGSCancellable {
        let job = Job(due: now + delay, action: action)
        jobs.append(job)
        return job
    }
    func advance(by interval: TimeInterval) {
        let end = now + interval
        while let job = jobs.filter({ !$0.cancelled && $0.due <= end }).min(by: { $0.due < $1.due }) {
            now = job.due
            job.cancelled = true
            job.action()
        }
        now = end
    }
}
