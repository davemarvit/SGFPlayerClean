import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
private func require(_ ok: @autoclosure () -> Bool, _ message: String) { if !ok() { fail(message) } }

private final class PlayHTTP: URLProtocol {
    static var pendingChallenge: PlayHTTP?
    func finishChallenge() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"challenge_id":51,"game":52}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let body: String
        var status = 200
        if path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "api/v1/challenges",
           request.httpMethod == "POST" { Self.pendingChallenge = self; return }
        if path == "/api/v1/ui/config" {
            body = #"{"user":{"id":99,"username":"TestingAccount","ranking":25},"user_jwt":"fixture"}"#
        } else if path.hasSuffix("/sgf") {
            status = 503; body = "{}"
        } else if path.contains("/games/") {
            let id = Int(path.split(separator: "/").last!) ?? 9
            body = "{\"id\":\(id),\"width\":9,\"height\":9,\"phase\":\"play\",\"rules\":\"japanese\",\"komi\":6.5,\"initial_player\":\"black\",\"moves\":[],\"players\":{\"black\":{\"id\":99,\"username\":\"TestingAccount\"},\"white\":{\"id\":98,\"username\":\"Opponent\"}}}"
        } else { body = "{\"results\":[],\"next\":null}" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class PlaySocket: OGSWebSocket {
    var onOpen: (() -> Void)?
    var onClose: ((Error?) -> Void)?
    var receiver: ((Result<String, Error>) -> Void)?
    var messages: [String] = []
    func resume() {}
    func receive(_ completion: @escaping (Result<String, Error>) -> Void) { receiver = completion }
    func send(_ text: String, completion: @escaping (Error?) -> Void) { messages.append(text); completion(nil) }
    func ping(_ completion: @escaping (Error?) -> Void) { completion(nil) }
    func cancel() {}
}

@MainActor final class PlayFixture: ObservableObject {
    let model: AppModel
    private let socket = PlaySocket()
    var started = false
    init() {
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe", "Wrong fixture identity")
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        UserDefaults.standard.removeObject(forKey: "last_challenge_setup")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlayHTTP.self]; config.httpCookieStorage = nil
        let socket = self.socket
        model = AppModel(ogsClient: OGSClient(session: URLSession(configuration: config, delegate: nil, delegateQueue: .main), socketFactory: { socket }))
    }
    func press(_ title: String, in window: NSWindow) {
        guard let host = window.contentView else { fail("Missing content view") }
        host.layoutSubtreeIfNeeded()
        // Native alert buttons can reject first mouse while this background probe
        // is inactive. Exercise their real action without stealing the user's focus.
        func nativeButton(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.title == title { return button }
            return view.subviews.lazy.compactMap(nativeButton).first
        }
        if let button = nativeButton(host) {
            if button.isEnabled { button.performClick(nil) }
            return
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fail("Cannot capture view") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        do { try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request]) }
        catch { fail("Cannot locate button: \(error)") }
        func normalized(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "…", with: "")
                .replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        }
        guard let label = request.results?.first(where: {
            $0.topCandidates(3).contains { normalized($0.string) == normalized(title) }
        }) else {
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/sgf-play-controls-missing.png"))
            fail("Button text not found: \(title); visible: \((request.results ?? []).compactMap { $0.topCandidates(1).first?.string })")
        }
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


    func text(in window: NSWindow, save: String? = nil) -> String {
        let host = window.contentView!
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let save { try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: save)) }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        do { try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request]) }
        catch { fail("Cannot read game panel") }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
    }
    func check() async {
        guard !started else { return }; started = true
        func settle() async { try? await Task.sleep(nanoseconds: 250_000_000) }
        await settle()
        model.mode = .playOnline
        let client = model.ogsClient
        socket.onOpen?(); client.isSocketAuthenticated = true
        model.resumeOnlineGame(id: 9); await settle()
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { fail("Missing game window") }
        require(client.isGameParticipant && model.boardVM!.onlineMoveUnavailableReason == nil, "Fixture game not ready")
        let ready = text(in: window, save: "/private/tmp/sgf-play-controls-ready.png")
        for label in ["pass", "resign", "undo", "save sgf"] { require(ready.contains(label), "Missing \(label): \(ready)") }
        press("Pass", in: window); await settle()
        require(model.player.maxIndex == 1, "Pass did not advance the board")
        require(socket.messages.filter { $0.contains("game/move") }.count == 1, "Expected one pass packet")
        require(socket.messages.last(where: { $0.contains("game/move") })!.contains(".."), "Pass encoding")
        press("Pass", in: window); await settle()
        require(socket.messages.filter { $0.contains("game/move") }.count == 1, "Double pass was not blocked")
        model.boardVM!.goToStart(); await settle()
        require(text(in: window).contains("return to latest move"), "History needs live-position action")
        press("Return to latest move", in: window); await settle()
        require(model.player.currentIndex == 1, "Did not return to live position")

        press("Resign…", in: window); await settle()
        guard let alert = window.attachedSheet else { fail("Resign confirmation missing") }
        require(text(in: alert).contains("are you sure"), "Missing resignation warning")
        require(!socket.messages.contains { $0.contains("game/resign") }, "Opening alert resigned")
        press("Cancel", in: alert); await settle()
        require(window.attachedSheet == nil && !socket.messages.contains { $0.contains("game/resign") }, "Cancel must not resign")
        press("Resign…", in: window); await settle()
        model.resumeOnlineGame(id: 10); await settle(); await settle()
        require(window.attachedSheet == nil, "Changing games must dismiss stale confirmation")
        require(!socket.messages.contains { $0.contains("game/resign") }, "Game change resigned")

        client.isSocketAuthenticated = false; await settle()
        let offline = text(in: window)
        require(!offline.contains("reconnect") && offline.contains("testingaccount") && offline.contains("pass"), "Disconnect retains game panel; reconnect belongs in account toolbar: \(offline)")
        let count = socket.messages.filter { $0.contains("game/move") }.count
        press("Pass", in: window); await settle()
        require(socket.messages.filter { $0.contains("game/move") }.count == count, "Disconnected pass sent")
        client.isSocketAuthenticated = true; await settle()
        press("Save SGF", in: window); await settle()
        require(text(in: window).contains("could not download"), "Export failure was silent")
        require(window.attachedSheet == nil, "Failed export must not open a save panel")

        client.undoRequestedUsername = "Opponent"; client.undoRequestedMoveNumber = 1; await settle()
        press("Decline", in: window); await settle()
        require(socket.messages.contains { $0.contains("game/undo/cancel") }, "Undo decline missing")
        socket.receiver?(.success(#"42["game/10/undo_canceled",{}]"#)); await settle()
        require(client.undoRequestedUsername == nil, "Undo cancellation was not applied")
        press("Resign…", in: window); await settle()
        guard let confirmed = window.attachedSheet else { fail("Resign confirmation missing") }
        _ = text(in: confirmed, save: "/private/tmp/sgf-resign-confirmation.png")
        press("Resign Game", in: confirmed); await settle()
        let resignations = socket.messages.filter { $0.contains("game/resign") }
        require(resignations.count == 1 && resignations[0].contains("10"), "Confirmation must resign only its original game")
        socket.receiver?(.success(#"42["game/10/phase","finished"]"#)); await settle()
        require(!client.canPlayMoves && !client.canResign, "Finished game still accepts actions")
        model.showOnlineBrowser(); model.isCreatingChallenge = true; await settle()
        press("Issue", in: window); await settle()
        require(PlayHTTP.pendingChallenge != nil, "Create request was not held by fixture")
        press("Close", in: window); await settle()
        require(!model.isCreatingChallenge, "Close did not leave the submitted form")
        model.isCreatingChallenge = true; await settle()
        PlayHTTP.pendingChallenge?.finishChallenge(); await settle()
        require(model.isCreatingChallenge, "Late completion of an old challenge form dismissed the new form")
        client.disconnect()
        print("PASS: Actual Pass/Resign/Cancel clicks, duplicate-pass prevention, game-scoped resignation confirmation, live-position return, disconnected controls, export error, undo decline finished-game gating, and stale challenge-form completion. Network denied; fixtures only.")
        exit(0)
    }
}

@main struct PlayControlsCheck: App {
    @StateObject private var fixture = PlayFixture()
    var body: some Scene {
        WindowGroup {
            RightPanelView().environmentObject(fixture.model).frame(width: 320, height: 620)
                .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark)
                .task { await fixture.check() }
        }
    }
}
