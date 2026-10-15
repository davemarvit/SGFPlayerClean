import XCTest
@testable import SGFPlayerNetworking

final class OGSHTTPReaderTests: XCTestCase {
    private struct Item: Decodable, Equatable { let id: Int }
    private var http: TestHTTPTransport!
    private var scheduler: TestScheduler!
    private var reader: OGSPaginatedReader<Item>!
    private var results: [Result<[Item], Error>]!
    private let root = URLRequest(url: URL(string: "https://online-go.com/api/v1/challenges/")!)

    override func setUp() {
        http = TestHTTPTransport()
        scheduler = TestScheduler()
        results = []
        reader = OGSPaginatedReader(transport: http, scheduler: scheduler, now: { [unowned self] in
            Date(timeIntervalSince1970: self.scheduler.now)
        })
    }

    private func load() -> Bool {
        reader.load(root) { [unowned self] in self.results.append($0) }
    }

    func testPagesProduceOnlyOneCompleteSnapshot() throws {
        XCTAssertTrue(load())
        http.reply(0, #"{"results":[{"id":1}],"next":"?page=2"}"#)
        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(load())
        scheduler.advance(by: 1)
        XCTAssertEqual(http.requests[1].url?.query, "page=2")
        http.reply(1, #"{"results":[{"id":2}],"next":null}"#)
        XCTAssertEqual(try results[0].get(), [Item(id: 1), Item(id: 2)])
        XCTAssertFalse(reader.isLoading)
    }

    func testPlainArrayAndEmptyCompleteListAreAccepted() throws {
        _ = load()
        http.reply(0, #"[{"id":3}]"#)
        XCTAssertEqual(try results[0].get(), [Item(id: 3)])
        _ = load()
        http.reply(1, #"{"results":[],"next":null}"#)
        XCTAssertEqual(try results[1].get(), [])
    }

    func testFailedLaterPageNeverPrunesUsingPartialData() {
        _ = load()
        http.reply(0, #"{"results":[{"id":1}],"next":"?page=2"}"#)
        scheduler.advance(by: 1)
        http.reply(1, #"{"detail":"server error"}"#, status: 500)
        XCTAssertEqual(results.count, 1)
        XCTAssertThrowsError(try results[0].get())
        XCTAssertTrue(load(), "A failed operation must release the single-flight guard")
    }

    func testMalformedLaterPageNeverReturnsPartialData() {
        _ = load()
        http.reply(0, #"{"results":[{"id":1}],"next":"?page=2"}"#)
        scheduler.advance(by: 1)
        http.reply(1, #"{"results":[{"wrong":2}],"next":null}"#)
        XCTAssertThrowsError(try results[0].get())
    }

    func testNetworkFailureDoesNotReturnAccumulatedPages() {
        _ = load()
        http.reply(0, #"{"results":[{"id":1}],"next":"?page=2"}"#)
        scheduler.advance(by: 1)
        http.completions[1](.failure(URLError(.timedOut)))
        XCTAssertThrowsError(try results[0].get())
    }

    func testRepeatedPollsDoNotOverlap() {
        XCTAssertTrue(load())
        for _ in 0..<20 { XCTAssertFalse(load()) }
        XCTAssertEqual(http.requests.count, 1)
    }

    func testCancelStopsDeferredPageEvenIfItsClosureRuns() {
        _ = load()
        http.reply(0, #"{"results":[{"id":1}],"next":"?page=2"}"#)
        let deferred = scheduler.jobs.last!
        reader.cancel()
        deferred.action()
        scheduler.advance(by: 30)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertTrue(results.isEmpty)
    }

    func testLateResponseCannotPublishIntoNewSession() throws {
        _ = load()
        reader.cancel()
        XCTAssertTrue(http.tasks[0].cancelled)
        XCTAssertTrue(load())
        http.reply(0, #"[{"id":111}]"#)
        XCTAssertTrue(results.isEmpty)
        http.reply(1, #"[{"id":222}]"#)
        XCTAssertEqual(try results[0].get(), [Item(id: 222)])
    }

    func testCancelCancelsCurrentPageRequest() {
        _ = load()
        http.reply(0, #"{"results":[{"id":1}],"next":"?page=2"}"#)
        scheduler.advance(by: 1)
        reader.cancel()
        XCTAssertTrue(http.tasks[1].cancelled)
        http.reply(1, #"[{"id":2}]"#)
        XCTAssertTrue(results.isEmpty)
    }

    func testRateLimitHonorsRetryAfterAcrossReconnect() {
        _ = load()
        http.reply(0, "{}", status: 429, headers: ["Retry-After": "120"])
        reader.cancel() // Disconnect must not bypass the server's cooldown.
        scheduler.advance(by: 119)
        XCTAssertFalse(load())
        scheduler.advance(by: 1)
        XCTAssertTrue(load())
        XCTAssertEqual(http.requests.count, 2)
    }

    func testRetryAfterHTTPDateAndUnavailableResponse() {
        _ = load()
        http.reply(0, "{}", status: 503, headers: ["Retry-After": "Thu, 01 Jan 1970 00:01:00 GMT"])
        scheduler.advance(by: 59)
        XCTAssertFalse(load())
        scheduler.advance(by: 1)
        XCTAssertTrue(load())
    }

    func testMalformedRetryAfterUsesIncreasingBoundedCooldown() {
        for (index, expected) in [30.0, 60, 120, 240, 300, 300].enumerated() {
            XCTAssertTrue(load())
            http.reply(index, "{}", status: 429, headers: ["Retry-After": "nonsense"])
            scheduler.advance(by: expected - 1)
            XCTAssertFalse(load())
            scheduler.advance(by: 1)
        }
    }

    func testSuccessfulSnapshotResetsThrottleBackoff() {
        _ = load()
        http.reply(0, "{}", status: 429)
        scheduler.advance(by: 30)
        _ = load()
        http.reply(1, "[]")
        _ = load()
        http.reply(2, "{}", status: 429)
        XCTAssertEqual(reader.retryNotBefore.timeIntervalSince1970, 60)
    }

    func testPaginationCannotLoopOrForwardAuthToAnotherOrigin() {
        for link in [root.url!.absoluteString, "https://example.com/page", "http://online-go.com/page"] {
            _ = load()
            let index = http.requests.count - 1
            http.reply(index, "{\"results\":[{\"id\":1}],\"next\":\"\(link)\"}")
            scheduler.advance(by: 1)
            XCTAssertEqual(http.requests.count, index + 1)
            XCTAssertThrowsError(try results.last!.get())
        }
    }

    func testPaginationHasFinitePageLimit() {
        reader = OGSPaginatedReader(transport: http, scheduler: scheduler, maximumPages: 2)
        _ = load()
        http.reply(0, #"{"results":[],"next":"?page=2"}"#)
        scheduler.advance(by: 1)
        http.reply(1, #"{"results":[],"next":"?page=3"}"#)
        scheduler.advance(by: 1)
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertThrowsError(try results[0].get())
    }

    func testPaginationPreservesHeaders() {
        var request = root
        request.setValue("Bearer fixture-token", forHTTPHeaderField: "Authorization")
        reader.load(request) { _ in }
        http.reply(0, #"{"results":[],"next":"?page=2"}"#)
        scheduler.advance(by: 1)
        XCTAssertEqual(http.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
    }

    func testLatestJSONRequestCancelsAndCompletesPreviousCallerOnce() throws {
        let json = OGSJSONReader(transport: http)
        var oldResults: [Result<[String: Any], Error>] = []
        var newResults: [Result<[String: Any], Error>] = []
        json.load(root) { oldResults.append($0) }
        json.load(root) { newResults.append($0) }
        XCTAssertTrue(http.tasks[0].cancelled)
        XCTAssertEqual(oldResults.count, 1)
        XCTAssertThrowsError(try oldResults[0].get())
        http.reply(0, #"{"game_id":1}"#)
        http.reply(1, #"{"game_id":2}"#)
        XCTAssertEqual(oldResults.count, 1)
        XCTAssertEqual(try newResults[0].get()["game_id"] as? Int, 2)
    }

    func testLogoutCancellationCannotRestoreUserFromLateConfig() {
        let json = OGSJSONReader(transport: http)
        var values: [Result<[String: Any], Error>] = []
        json.load(root) { values.append($0) }
        json.cancel()
        http.reply(0, #"{"user_jwt":"fixture-token"}"#)
        XCTAssertEqual(values.count, 1)
        XCTAssertThrowsError(try values[0].get())
    }

    func testJSONReaderRejectsHTTPErrorAndNonObjectJSON() {
        let json = OGSJSONReader(transport: http)
        var values: [Result<[String: Any], Error>] = []
        json.load(root) { values.append($0) }
        http.reply(0, #"{"user_jwt":"must-not-apply"}"#, status: 401)
        json.load(root) { values.append($0) }
        http.reply(1, "[]")
        XCTAssertEqual(values.count, 2)
        for value in values { XCTAssertThrowsError(try value.get()) }
    }

    func testReentrantCancellationKeepsNewestRequest() throws {
        let json = OGSJSONReader(transport: http)
        var newest: [Result<[String: Any], Error>] = []
        var superseded: [Result<[String: Any], Error>] = []
        json.load(root) { _ in json.load(self.root) { newest.append($0) } }
        json.load(root) { superseded.append($0) }
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertThrowsError(try superseded[0].get())
        http.reply(1, #"{"newest":true}"#)
        XCTAssertEqual(try newest[0].get()["newest"] as? Bool, true)
    }
}

final class TestHTTPTransport: OGSHTTPTransport {
    final class Task: OGSCancellable {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    var tasks: [Task] = []
    var requests: [URLRequest] = []
    var completions: [(Result<OGSHTTPResponse, Error>) -> Void] = []
    func get(_ request: URLRequest, completion: @escaping (Result<OGSHTTPResponse, Error>) -> Void) -> OGSCancellable {
        let task = Task()
        tasks.append(task); requests.append(request); completions.append(completion)
        return task
    }
    func reply(_ index: Int, _ body: String, status: Int = 200, headers: [String: String] = [:]) {
        completions[index](.success(OGSHTTPResponse(data: Data(body.utf8), response:
            HTTPURLResponse(url: requests[index].url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)))
    }
}
