import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
private func require(_ ok: @autoclosure () -> Bool, _ message: String) { if !ok() { fail(message) } }

private final class LobbyHTTP: URLProtocol {
    static var pendingAcceptance: LobbyHTTP?
    static var acceptanceCount = 0
    func rejectAcceptance() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"detail":"This account cannot accept this challenge."}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let body: String
        let status = 200
        if path.hasSuffix("/accept") {
            Self.acceptanceCount += 1; Self.pendingAcceptance = self; return
        }
        if path == "/api/v1/ui/config" {
            body = #"{"user":{"id":99,"username":"TestingAccount","ranking":25},"user_jwt":"fixture"}"#
        } else { body = "{\"results\":[],\"next\":null}" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class LobbySocket: OGSWebSocket {
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

@MainActor final class LobbyFixture: ObservableObject {
    let model: AppModel
    private let socket = LobbySocket()
    var started = false
    init() {
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe", "Wrong fixture identity")
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        UserDefaults.standard.removeObject(forKey: "last_challenge_setup")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LobbyHTTP.self]; config.httpCookieStorage = nil
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
        func settle() async { try? await Task.sleep(nanoseconds: 400_000_000) }
        await settle()
        model.mode = .playOnline
        let client = model.ogsClient
        socket.onOpen?(); client.isSocketAuthenticated = true
        model.showOnlineBrowser(); await settle()
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { fail("Missing lobby window") }
        // Waiting for an opponent on an existing challenge must not disable actions.
        client.startAutomatch() // Fake socket only; sets the general waiting flag.
        UserDefaults.standard.set(true, forKey: "ogs_filter_ineligible")
        socket.receiver?(.success(#"42["seekgraph/global",[{"challenge_id":401,"username":"LockedPlayer","user_id":401,"width":19,"height":19,"ranked":true,"time_per_move":13,"min_rank":30},{"challenge_id":402,"username":"EligiblePlayer","user_id":402,"width":19,"height":19,"ranked":true,"time_per_move":13}]]"#))
        await settle()
        let lobbyText = text(in: window, save: "/private/tmp/sgf-lobby-locked-preview.png")
        require(lobbyText.contains("locked") && lobbyText.contains("requires at least"), "Locked row missing: \(lobbyText)")
        press("LOCKED", in: window); await settle()
        require(LobbyHTTP.acceptanceCount == 0, "Locked button must not send an acceptance")
        press("ACCEPT", in: window); await settle()
        require(LobbyHTTP.acceptanceCount == 1 && model.isAcceptingChallenge, "Accept must send once and show progress")
        press("ACCEPT", in: window); await settle()
        require(LobbyHTTP.acceptanceCount == 1, "Pending acceptance must disable repeated clicks")
        LobbyHTTP.pendingAcceptance?.rejectAcceptance(); await settle()
        guard let rejection = window.attachedSheet else { fail("Acceptance rejection must show an alert") }
        let rejectionText = text(in: rejection, save: "/private/tmp/sgf-lobby-rejection-preview.png")
        require(rejectionText.contains("could not accept") && rejectionText.contains("testingaccount") && rejectionText.contains("this account cannot accept"),
                "Rejection alert must name the account and preserve OGS's explanation: \(rejectionText)")
        press("OK", in: rejection); await settle()
        require(window.attachedSheet == nil && !model.isAcceptingChallenge && !client.isSearchingForGame, "Rejection must dismiss and release busy state")
        require(client.availableGames.contains { $0.id == 402 }, "A forbidden response must not delete the challenge")
        client.disconnect()
        print("PASS: LOCKED label and rank explanation, disabled locked clicks, active acceptance while waiting for an opponent, duplicate-click suppression, and account-specific server rejection alert. Network denied; fixtures only.")
        exit(0)
    }

}

@main struct LobbyControlsCheck: App {
    @StateObject private var fixture = LobbyFixture()
    var body: some Scene {
        WindowGroup {
            RightPanelView().environmentObject(fixture.model).frame(width: 320, height: 620)
                .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark)
                .task { await fixture.check() }
        }
    }
}
