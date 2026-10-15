import XCTest
@testable import SGFPlayerNetworking

final class OGSReviewSessionStoreTests: XCTestCase {
    func testSessionCookiesSurviveNewStoreAndStayPrivate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("review/SessionCookies.plist")
        let store = OGSReviewSessionStore(fileURL: url)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "sessionid", .value: "fixture-only",
            .domain: ".online-go.com", .path: "/", .secure: "TRUE", .discard: "TRUE",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE"]))
        XCTAssertTrue(cookie.isSessionOnly)
        try store.save([cookie])
        let restored = try XCTUnwrap(OGSReviewSessionStore(fileURL: url).load().first)
        XCTAssertEqual(restored.name, cookie.name)
        XCTAssertEqual(restored.value, cookie.value)
        XCTAssertEqual(restored.domain, cookie.domain)
        XCTAssertEqual(restored.path, cookie.path)
        XCTAssertEqual(restored.isSecure, cookie.isSecure)
        XCTAssertEqual(restored.isHTTPOnly, cookie.isHTTPOnly)
        let fm = FileManager.default
        XCTAssertEqual((try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try fm.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let other = OGSReviewSessionStore(fileURL: folder.appendingPathComponent("other/SessionCookies.plist"))
        XCTAssertTrue(try other.load().isEmpty)
        try store.clear()
        XCTAssertTrue(try OGSReviewSessionStore(fileURL: url).load().isEmpty)
    }

    func testExpiredAndUnrelatedCookiesAreNotRestored() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OGSReviewSessionStore(fileURL: folder.appendingPathComponent("cookies.plist"))
        let valid = try XCTUnwrap(HTTPCookie(properties: [.name: "csrftoken", .value: "fixture",
            .domain: "online-go.com", .path: "/", .expires: Date().addingTimeInterval(3600)]))
        let unrelated = try XCTUnwrap(HTTPCookie(properties: [.name: "session", .value: "unrelated",
            .domain: "not-online-go.com", .path: "/"]))
        let expired = try XCTUnwrap(HTTPCookie(properties: [.name: "expired", .value: "fixture",
            .domain: "online-go.com", .path: "/", .expires: Date().addingTimeInterval(-3600)]))
        try store.save([valid, unrelated, expired])
        XCTAssertEqual(try store.load().map(\.name), ["csrftoken"])
        // Also filter a file containing an expired cookie (e.g. time passed after saving).
        let records = [expired.properties!.reduce(into: [String: Any]()) { $0[$1.key.rawValue] = $1.value }]
        try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0).write(to: store.fileURL)
        XCTAssertTrue(try store.load().isEmpty)
        try Data("corrupt fixture".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }
}
