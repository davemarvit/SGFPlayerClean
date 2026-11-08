import SwiftUI
import Vision
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
        let game = request.url?.path.contains("/games/") == true
        let body = config ? #"{"user":{"id":99,"username":"Review Fixture"},"user_jwt":"fixture"}"# :
            game ? #"{"id":9,"width":19,"height":19,"phase":"play","rules":"japanese","komi":6.5,"initial_player":"black","moves":[[0,0],[1,1]],"players":{"black":{"id":10,"username":"Alice"},"white":{"id":11,"username":"Bob"}}}"# : "{}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: config || game ? 200 : 404,
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

@MainActor final class ModeActionsFixture: ObservableObject {
    let model: AppModel
    var started = false
    private let socket: BrowserSocketFixture

    init() {
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe")
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil
        AppSettings.shared.stoneVolume = 0
        let socket = BrowserSocketFixture()
        self.socket = socket
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserHTTPFixture.self]
        config.httpCookieStorage = nil
        model = AppModel(ogsClient: OGSClient(session: URLSession(configuration: config, delegate: nil, delegateQueue: .main),
                                    socketFactory: { socket }))
        model.viewMode = ProcessInfo.processInfo.environment["MODE_ACTIONS_VIEW"] == "2D" ? .view2D : .view3D
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
        func normalized(_ value: String) -> String { String(value.lowercased().filter { $0.isLetter || $0.isNumber }) }
        guard let label = request.results?.first(where: {
            normalized($0.topCandidates(1).first?.string ?? "") == normalized(title)
        }) else {
            print("Visible text:", request.results?.compactMap { $0.topCandidates(1).first?.string } ?? [])
            fail("Button text not found: \(title)")
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

    func pressMode(_ mode: AppMode, in window: NSWindow) {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let control = window.contentView.flatMap({ descendants($0).compactMap { $0 as? NSSegmentedControl }.first }),
              let index = (0..<control.segmentCount).first(where: { control.label(forSegment: $0) == mode.rawValue }) else { fail("Missing mode control") }
        let point = NSPoint(x: (CGFloat(index) + 0.5) * control.bounds.width / CGFloat(control.segmentCount), y: control.bounds.midY)
        let location = control.convert(point, to: nil)
        window.makeKeyAndOrderFront(nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        }
        NSApplication.shared.postEvent(event(.leftMouseUp), atStart: false)
        window.sendEvent(event(.leftMouseDown))
    }

    func check() async {
        guard !started else { return }
        started = true
        func settle() async { try? await Task.sleep(nanoseconds: 400_000_000) }
        await settle()
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { fail("No main window") }
        _ = (UnifiedInteractiveSceneView.lastActiveView as? UnifiedSCNView)?.finishCameraArrival?()
        await settle()
        model.showRightPanel = false
        pressMode(.observe, in: window)
        await settle()
        require(model.mode == .observe && window.attachedSheet != nil, "Observe opens game browser with sidebar hidden")
        press("Cancel", in: window.attachedSheet!)
        await settle()
        require(window.attachedSheet == nil, "Cancel dismisses browser")
        pressMode(.observe, in: window)
        await settle()
        require(window.attachedSheet != nil, "Already-selected Observe reopens browser")
        ready()
        await settle()
        press("Observe", in: window.attachedSheet!)
        await settle()
        require(model.ogsClient.activeGameID == 9 && window.attachedSheet == nil, "Choosing game observes it and dismisses browser")
        pressMode(.observe, in: window)
        await settle()
        require(window.attachedSheet != nil, "Observe can change games while watching")
        press("Cancel", in: window.attachedSheet!)
        await settle()
        require(model.ogsClient.activeGameID == 9, "Cancel preserves watched game")
        pressMode(.review, in: window)
        await settle()
        require(model.mode == .review && model.player.maxIndex == 2 && model.boardVM!.reviewTree != nil,
                "Review copies observed game history")

        let text = "(;GM[1]FF[4]SZ[9]PB[Collection Black]PW[Collection White];B[aa];W[bb])"
        let game = SGFGame.from(tree: try! SGFParser.parse(text: text))
        let wrapper = SGFGameWrapper(url: URL(fileURLWithPath: "/tmp/mode-actions-collection.sgf"), game: game)
        model.games = [wrapper]
        model.selectGame(wrapper)
        model.mode = .localPlay
        model.boardVM!.placeStone(at: BoardPosition(2, 2))
        await settle()
        let snapshot = model.player.createSnapshot()
        require(model.player.maxIndex == 1, "Local game fixture")
        pressMode(.review, in: window)
        await settle()
        require(model.mode == .review && model.player.maxIndex == 1 && model.player.currentIndex == snapshot.currentIndex,
                "Review copies current game instead of restoring old collection game")
        require(model.player.board.stones[BoardPosition(2, 2)] == .black && model.boardVM!.reviewTree != nil, "Review retains board and creates tree")
        let tree = model.boardVM!.reviewTree!
        pressMode(.review, in: window)
        await settle()
        require(model.boardVM!.reviewTree!.nodes.count == tree.nodes.count && model.player.maxIndex == 1, "Repeated Review preserves current review")
        model.showRightPanel = false
        await settle()
        press("Choose game…", in: window)
        await settle()
        require(model.showRightPanel && model.player.maxIndex == 1, "Choose game reveals collection without replacing current game")
        // Use the same production selection action as each existing collection row.
        model.selectGame(wrapper)
        await settle()
        require(model.selection?.id == wrapper.id && model.player.maxIndex == 2 && model.player.currentIndex == 2,
                "Collection selection opens chosen game paused at the main-line end")
        pressMode(.localPlay, in: window)
        await settle()
        require(model.player.maxIndex == 1 && model.player.board.stones[BoardPosition(2, 2)] == .black, "Original local game remains available")
        model.ogsClient.disconnect()
        print("PASS: Full \(model.viewMode) window: Observe opens/reopens browser, selects game, preserves on cancel; Review uses current board, repeat preserves review, Choose game reveals library, collection selection and local game preserved.")
        exit(0)
    }
}

@main struct ModeActionsCheck: App {
    @StateObject private var fixture = ModeActionsFixture()
    var body: some Scene {
        WindowGroup {
            ContentView()
            .environmentObject(fixture.model)
            .frame(width: 1100, height: 700)
            .task { await fixture.check() }
        }
    }
}
