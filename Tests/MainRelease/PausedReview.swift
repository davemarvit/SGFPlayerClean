import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class OfflineHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        require(request.httpMethod == "GET", "No online mutations")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private struct KeyboardFixture: View {
    let app: AppModel
    @FocusState private var focused: Bool
    var body: some View {
        Color(red: 0.35, green: 0.4, blue: 0.25)
            .focused($focused)
            .keyboardShortcuts(boardVM: app.boardVM!, appModel: app)
            .onAppear { focused = true }
    }
}
@main struct PausedReviewCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.isMuted = true; AppSettings.shared.folderURL = nil
        AppSettings.shared.startGameOnLaunch = true; AppSettings.shared.moveInterval = 0.1
        AppSettings.shared.shuffleGameOrder = false
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        let app = AppModel(ogsClient: client)
        defer { client.disconnect(); KataGoEngine.shared.stop() }
        app.mode = .review; app.aiAnalysisEnabled = false
        let vm = app.boardVM!
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        func fixture(_ name: String) throws -> SGFGameWrapper {
            let text = "(;SZ[9]PB[\(name)]PW[Opponent];B[dd];W[ee];B[ff])"
            let url = temporary.appendingPathComponent(name + ".sgf")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: text)))
        }
        let first = try fixture("Alpha"), second = try fixture("Bravo")
        app.games = [first, second]; app.selection = nil
        func settle(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 1000), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua); window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        func host<V: View>(_ view: V, size: CGSize) -> NSHostingView<some View> {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            window.setContentSize(size); window.contentView = host; settle(0.3)
            host.layoutSubtreeIfNeeded(); return host
        }
        func clickText(_ text: String, in host: NSView) throws {
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            guard let item = request.results?.first(where: { $0.topCandidates(1).first?.string.contains(text) == true }) else {
                require(false, "Visible game row: \(text)"); return
            }
            let box = item.boundingBox
            let p = CGPoint(x: box.midX * host.bounds.width, y: (host.isFlipped ? 1 - box.midY : box.midY) * host.bounds.height)
            let point = host.convert(p, to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
                settle(0.025)
            }
        }
        let panel = host(RightPanelView().environmentObject(app), size: CGSize(width: 380, height: 700))
        try clickText("Bravo", in: panel); settle(0.8)
        require(app.selection?.id == second.id && !app.player.isPlaying && app.player.currentIndex == 0,
                "Clicking a Review library row opens it paused")
        vm.startAutoPlay(); settle(0.15)
        require(app.player.isPlaying && app.player.currentIndex > 0, "Explicit Play still advances")
        AppSettings.shared.moveInterval = 10
        app.selection = nil
        let settings = host(SettingsPanel(app: app, isPresented: .constant(true)), size: CGSize(width: 380, height: 1800))
        require(app.player.isPlaying, "Previous game is still playing before selection")
        try clickText("Alpha", in: settings); settle(0.8)
        require(app.selection?.id == first.id && !app.player.isPlaying && app.player.currentIndex == 0,
                "Settings library selection stops previous playback and remains paused")
        AppSettings.shared.moveInterval = 0.1
        vm.startAutoPlay(); settle(4.0)
        require(app.selection?.id == first.id && !app.player.isPlaying && app.player.currentIndex == 3,
                "Finishing playback stays on the same game without starting the next")
        app.selectGame(first); settle()
        let keyboard = host(KeyboardFixture(app: app), size: CGSize(width: 600, height: 400))
        func key(_ code: UInt16, _ characters: String) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                window.sendEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: code)!)
            }
            settle()
        }
        key(124, "\u{F703}")
        require(app.player.currentIndex == 1, "Right arrow retains keyboard navigation without the focus effect")
        key(123, "\u{F702}")
        require(app.player.currentIndex == 0, "Left arrow retains keyboard navigation")
        let bitmap = keyboard.bitmapImageRepForCachingDisplay(in: keyboard.bounds)!
        keyboard.cacheDisplay(in: keyboard.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-paused-focus.png"))
        print("PASS: real Review/settings library clicks, explicit playback, no auto-next, keyboard navigation with focus effect disabled")
    }
}
