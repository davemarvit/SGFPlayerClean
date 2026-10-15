import Foundation
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct MainConfigurationCheck {
    static func main() throws {
        let identifier = "com.davemarvit.SGFPlayerClean.ogs-ui-probe"
        require(Bundle.main.bundleIdentifier == identifier, "Wrong fixture identity")
        let store = OGSReviewSessionStore.defaultStore()
        require(store.fileURL.deletingLastPathComponent().lastPathComponent == identifier,
                "Session store must follow the current bundle identity")
        defer { try? store.clear() }
        guard let cookie = HTTPCookie(properties: [.name: "sessionid", .value: "main-release-fixture",
            .domain: ".online-go.com", .path: "/", .secure: "TRUE", .discard: "TRUE"]) else {
            throw NSError(domain: "MainConfiguration", code: 1)
        }
        try store.save([cookie])
        // This calls the real production convenience initializer. It must use
        // the same persistent private cookie handling as the tested review app.
        let client = OGSClient()
        guard let session = Mirror(reflecting: client).children.first(where: { $0.label == "urlSession" })?.value as? URLSession else {
            throw NSError(domain: "MainConfiguration", code: 2)
        }
        let storage = session.configuration.httpCookieStorage
        require(storage !== HTTPCookieStorage.shared, "Main app must have a private cookie jar")
        require(storage?.cookies?.contains(where: { $0.name == "sessionid" && $0.value == "main-release-fixture" }) == true,
                "Normal app initializer did not restore the saved session")
        session.invalidateAndCancel()
        client.disconnect()
        print("PASS: Normal Release initializer restores a bundle-scoped persistent login into a private cookie jar. Fixture-only session; network denied.")
    }
}
