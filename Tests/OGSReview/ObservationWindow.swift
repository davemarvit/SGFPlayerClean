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
    var onOpen: (() -> Void)?
    var onClose: ((Error?) -> Void)?
    var receiver: ((Result<String, Error>) -> Void)?
    func resume() {}
    func receive(_ completion: @escaping (Result<String, Error>) -> Void) { receiver = completion }
    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        completion(nil)
        if text.contains("gamelist/query") {
            let id = text.dropFirst(2).prefix { $0.isNumber }
            let reply = "43\(id)" + #"[{"size":1,"results":[{"id":9,"black":{"username":"Alice"},"white":{"username":"Bob"},"width":19,"height":19}]}]"#
            DispatchQueue.main.async { self.receiver?(.success(reply)) }
        }
    }
    func ping(_ completion: @escaping (Error?) -> Void) { completion(nil) }
    func cancel() {}
}

@MainActor final class ObservationFixture: ObservableObject {
    let model: AppModel
    @Published var showSheet = false
    var started = false
    var sheetCompleted = false
    private let socket: BrowserSocketFixture
    private var changes: AnyCancellable?

    init() {
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe")
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        let socket = BrowserSocketFixture()
        self.socket = socket
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserHTTPFixture.self]
        config.httpCookieStorage = nil
        model = AppModel(ogsClient: OGSClient(session: URLSession(configuration: config, delegate: nil, delegateQueue: .main),
                                    socketFactory: { socket }))
    }

    func ready() {
        model.ogsClient.connect()
        socket.onOpen?()
        model.ogsClient.username = "Review Fixture"
        model.ogsClient.isAuthenticated = true
        model.ogsClient.isSocketAuthenticated = true
        model.ogsClient.isConnected = true
    }

    func press(_ title: String, in window: NSWindow) {
        guard let host = window.contentView else { fail("Missing content view") }
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fail("Cannot capture view") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        do { try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request]) }
        catch { fail("Cannot locate button: \(error)") }
        guard let label = request.results?.first(where: {
            $0.topCandidates(1).first?.string.lowercased() == title.lowercased()
        }) else { fail("Button text not found: \(title)") }
        let box = label.boundingBox
        let point = NSPoint(x: host.bounds.width * box.midX,
                            y: host.bounds.height * (host.isFlipped ? 1 - box.midY : box.midY))
        let location = host.convert(point, to: nil)
        window.makeKeyAndOrderFront(nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: type, location: location,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { fail("Cannot make mouse event") }
            return event
        }
        // Mouse-down may enter a nested tracking loop; queue mouse-up first.
        NSApplication.shared.postEvent(event(.leftMouseUp), atStart: false)
        window.sendEvent(event(.leftMouseDown))
    }

    func escape(in window: NSWindow) {
        func editable(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap(editable).first
        }
        if let host = window.contentView, let field = editable(host) { window.makeFirstResponder(field) }
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { fail("Cannot make Escape event") }
        NSApplication.shared.sendEvent(event)
    }

    func check() async {
        guard !started else { return }
        started = true
        func settle() async { try? await Task.sleep(nanoseconds: 600_000_000) }
        await settle()
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
            fail("No main SwiftUI window")
        }
        showSheet = true
        await settle()
        guard let cancelledSheet = window.attachedSheet else { fail("Cancel sheet missing") }
        press("Cancel", in: cancelledSheet)
        await settle()
        require(!showSheet && window.attachedSheet == nil && window.isVisible, "Cancel must close only its sheet")
        require(model.ogsClient.activeGameID == nil && !sheetCompleted, "Cancel must not observe a game")
        ready()
        await settle()
        require(model.ogsClient.observedGames.first?.blackName == "Alice", "Fixture game list did not arrive")
        press("Observe Game", in: window)
        await settle()
        require(model.ogsClient.activeGameID == 7, "Sidebar did not run the real observation action")
        require(window.isVisible, "Sidebar Observe closed the main window")

        showSheet = true
        await settle()
        ready()
        await settle()
        guard let sheet = window.attachedSheet else { fail("Observation sheet missing") }
        press("Observe Game", in: sheet)
        await settle()
        require(model.ogsClient.activeGameID == 8 && sheetCompleted)
        require(!showSheet && window.attachedSheet == nil, "Observe sheet did not close")
        require(window.isVisible, "Sheet Observe closed the main window")
        showSheet = true
        await settle()
        guard let listSheet = window.attachedSheet else { fail("Game list sheet missing") }
        press("Observe", in: listSheet)
        await settle()
        require(model.ogsClient.activeGameID == 9, "Row must observe its game ID")
        require(!showSheet && window.attachedSheet == nil && window.isVisible, "Row Observe must close only its sheet")
        showSheet = true
        await settle()
        guard let escapeSheet = window.attachedSheet else { fail("Escape sheet missing") }
        escape(in: escapeSheet)
        await settle()
        require(!showSheet && window.attachedSheet == nil && window.isVisible, "Escape must close only its sheet")
        require(model.ogsClient.activeGameID == 9, "Escape must not change the observed game")
        model.ogsClient.disconnect()
        print("PASS: Cancel, Escape while editing, manual Observe in sidebar/sheet, and live-game row Observe close only the sheet and preserve the correct game/main window. All networking denied; list supplied by fake socket.")
        exit(0)
    }
}

@main struct ObservationWindowCheck: App {
    @StateObject private var fixture = ObservationFixture()
    var body: some Scene {
        WindowGroup {
            OGSObservationBrowserView(gameLink: "7")
                .environmentObject(fixture.model)
                .frame(width: 560, height: 620)
                .sheet(isPresented: $fixture.showSheet) {
                    OGSObservationBrowserView(gameLink: "8", didObserve: {
                        fixture.sheetCompleted = true
                        fixture.showSheet = false
                    }, onCancel: { fixture.showSheet = false })
                    .environmentObject(fixture.model)
                    .frame(width: 560, height: 620)
                }
                .task { await fixture.check() }
        }
    }
}
