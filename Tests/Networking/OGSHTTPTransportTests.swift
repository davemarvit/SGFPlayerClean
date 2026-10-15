import XCTest
@testable import SGFPlayerNetworking

final class OGSHTTPTransportTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPFixtureProtocol.self]
        return URLSession(configuration: config)
    }

    func testURLSessionDeliversResponseOnMainQueue() {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let done = expectation(description: "HTTP response")
        let transport = OGSURLSessionHTTPTransport(session: session)
        _ = transport.get(URLRequest(url: URL(string: "https://ogs-reader.test/success")!)) { result in
            XCTAssertTrue(Thread.isMainThread)
            do {
                let response = try result.get()
                XCTAssertEqual(String(data: try response.validatedData(), encoding: .utf8), #"{"id":123}"#)
            } catch { XCTFail("Unexpected error: \(error)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testHTTPFailureIsRejectedBeforeJSONRead() {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let done = expectation(description: "HTTP failure")
        let reader = OGSJSONReader(transport: OGSURLSessionHTTPTransport(session: session))
        reader.load(URLRequest(url: URL(string: "https://ogs-reader.test/unauthorized")!)) { result in
            guard case .failure(let error) = result,
                  case OGSHTTPError.status(401) = error else {
                XCTFail("A valid JSON body must not hide an HTTP failure")
                done.fulfill()
                return
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testReturnedOperationCancelsURLSessionTask() {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let done = expectation(description: "Cancelled task")
        let transport = OGSURLSessionHTTPTransport(session: session)
        let task = transport.get(URLRequest(url: URL(string: "https://ogs-reader.test/pending")!)) { result in
            XCTAssertTrue(Thread.isMainThread)
            guard case .failure(let error) = result else {
                XCTFail("Expected cancellation")
                done.fulfill()
                return
            }
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
            done.fulfill()
        }
        task.cancel()
        wait(for: [done], timeout: 3)
    }
}

/// Intercepts every test request inside URLSession; no OGS or external network traffic.
private final class HTTPFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "ogs-reader.test" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if url.path == "/pending" { return }
        let status = url.path == "/unauthorized" ? 401 : 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"id":123}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
