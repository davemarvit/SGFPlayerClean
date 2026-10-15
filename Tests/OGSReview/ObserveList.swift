import SwiftUI
import Vision
import Combine
@testable import SGF_Player_OGS_Review

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}
private func require(_ condition: @autoclosure () -> Bool, _ message: String = "Check failed") {
    if !condition() { fail(message) }
}

private final class BrowserHTTPFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let config = request.url?.path == "/api/v1/ui/config"
        let body = config ? #"{"user":{"id":99,"username":"Review Fixture"},"user_jwt":"fixture"}"# : "{}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: config ? 200 : 404,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class BrowserSocketFixture: OGSWebSocket {
    var offsets: [Int] = []
    var onOpen: (() -> Void)?
    var onClose: ((Error?) -> Void)?
    var receiver: ((Result<String, Error>) -> Void)?
    func resume() {}
    func receive(_ completion: @escaping (Result<String, Error>) -> Void) { receiver = completion }
    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        completion(nil)
        if text.contains("gamelist/query") {
            let id = text.dropFirst(2).prefix { $0.isNumber }
            let args = try! JSONSerialization.jsonObject(with: Data(text.dropFirst(2 + id.count).utf8)) as! [Any]
            let query = args[1] as! [String: Any]
            let offset = query["from"] as! Int
            offsets.append(offset)
            var rows: [[String: Any]] = []
            for i in offset..<min(offset + 20, 53) {
                let black: [String: Any] = ["username": i == 0 ? "Alice" : "Player \(i)", "ranking": 35.0 - Double(i) / 100]
                let white: [String: Any] = ["username": "Bob", "ranking": 30]
                let time: [String: Any] = ["system": "byoyomi", "main_time": 1200, "periods": 5, "period_time": 30]
                let snapshot: [String: Any] = ["moves": Array(repeating: [0, 0], count: 93), "time_control": time]
                rows.append(["id": 1001 + i, "black": black, "white": white, "width": 19, "height": 19, "json": snapshot])
            }
            let data = try! JSONSerialization.data(withJSONObject: [["size": 53, "results": rows]])
            let reply = "43\(id)" + String(data: data, encoding: .utf8)!
            DispatchQueue.main.async { self.receiver?(.success(reply)) }
        }
    }
    func ping(_ completion: @escaping (Error?) -> Void) { completion(nil) }
    func cancel() {}
}

@main struct ObserveListCheck {
    @MainActor static func main() throws {
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        let socket = BrowserSocketFixture()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserHTTPFixture.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config, delegate: nil, delegateQueue: .main), socketFactory: { socket })
        let model = AppModel(ogsClient: client)
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
        model.mode = .observe; socket.onOpen?(); settle()
        client.isSocketAuthenticated = true
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 560, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.orderOut(nil); client.disconnect() }
        let host = NSHostingView(rootView: OGSObservationBrowserView(onCancel: {})
            .environmentObject(model).frame(width: 560, height: 700).background(Color(nsColor: .windowBackgroundColor)))
        window.contentView = host; window.orderFront(nil); settle()
        func capture(_ path: String) throws -> [VNRecognizedTextObservation] {
            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return request.results ?? []
        }
        let labels = try capture("/private/tmp/sgf-observe-list-preview.png")
        let text = labels.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        for label in ["alice", "6d", "93 moves", "20m", "30s", "strongest player first"] {
            require(text.contains(label), "Missing \(label): \(text)")
        }
        require(!text.contains("1001") && !text.contains("page 1") && !text.contains("previous"), text)
        require(socket.offsets == [0] && client.observedGames.count == 20, "Initial display must not eagerly fetch everything: \(socket.offsets)")
        func scrollView(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap(scrollView).first
        }
        guard let scroll = scrollView(host), let document = scroll.documentView else { fail("Missing scrolling list") }
        for expected in [40, 53] {
            // Lazy stacks estimate their document height; repeat until the footer enters view.
            for _ in 0..<4 where client.observedGames.count < expected {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                scroll.reflectScrolledClipView(scroll.contentView); settle()
            }
            require(client.observedGames.count == expected, "Scroll did not append next batch: \(client.observedGames.count), requests \(socket.offsets)")
        }
        require(socket.offsets == [0, 20, 40] && !client.hasMoreObservedGames, "Stop at final batch")
        require(Set(client.observedGames.map(\.id)).count == 53, "Unique rows")
        require(client.activeGameID == nil, "Browsing must not observe or join")
        window.contentView = NSHostingView(rootView: OGSCreateChallengeView(isPresented: .constant(true))
            .environmentObject(model).frame(width: 380, height: 700).background(Color(nsColor: .windowBackgroundColor)))
        settle()
        let buttons = try capture("/private/tmp/sgf-challenge-preview.png")
        func label(_ name: String) -> VNRecognizedTextObservation? {
            buttons.first { $0.topCandidates(1).first?.string.lowercased() == name }
        }
        guard let cancel = label("cancel"), let issue = label("issue") else { fail("Missing challenge actions") }
        require(cancel.boundingBox.midX < issue.boundingBox.midX, "Cancel left, Issue right")
        print("PASS: Observe metadata, ranks, no displayed IDs/pages, real scrolling loads 20+20+13 rows and stops; challenge action order. Network denied.")
    }
}
