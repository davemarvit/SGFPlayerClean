import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private final class ModeHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let body: String
        if path == "/api/v1/ui/config" {
            body = #"{"user":{"id":99,"username":"TestingAccount","ranking":25},"user_jwt":"fixture"}"#
        } else if path == "/api/v1/challenges/8/accept" {
            require(request.httpMethod == "POST", "Challenge acceptance must use POST")
            body = #"{"id":7}"#
        } else if path.contains("/games/") {
            let id = Int(path.split(separator: "/").last!) ?? 9
            body = "{\"id\":\(id),\"width\":9,\"height\":9,\"phase\":\"play\",\"rules\":\"japanese\",\"komi\":6.5,\"initial_player\":\"black\",\"moves\":[[0,0],[1,1]],\"players\":{\"black\":{\"id\":\(id == 7 ? 99 : 10),\"username\":\"Black\"},\"white\":{\"id\":11,\"username\":\"White\"}}}"
        } else { body = "{\"results\":[],\"next\":null}" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class ModeSocket: OGSWebSocket {
    var onOpen: (() -> Void)?
    var onClose: ((Error?) -> Void)?
    var receiver: ((Result<String, Error>) -> Void)?
    var messages: [String] = []
    var cancellations = 0
    func resume() {}
    func receive(_ completion: @escaping (Result<String, Error>) -> Void) { receiver = completion }
    func send(_ text: String, completion: @escaping (Error?) -> Void) { messages.append(text); completion(nil) }
    func ping(_ completion: @escaping (Error?) -> Void) { completion(nil) }
    func cancel() { cancellations += 1 }
}

@main struct ModeCheck {
    @MainActor static func main() throws {
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe", "Wrong fixture identity")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.removeObject(forKey: "folderURLBookmark")
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil
        AppSettings.shared.stoneVolume = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModeHTTP.self]; config.httpCookieStorage = nil
        let socket = ModeSocket()
        let client = OGSClient(session: URLSession(configuration: config, delegate: nil, delegateQueue: .main), socketFactory: { socket })
        let model = AppModel(ogsClient: client)
        let vm = model.boardVM!
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        settle()
        require(model.mode == .localPlay, "Initial local mode")
        vm.placeStone(at: BoardPosition(2, 2)); settle()
        require(model.player.maxIndex == 1, "Local Play accepts moves")
        let text = "(;GM[1]FF[4]SZ[9]RU[Japanese]KM[6.5];B[aa];W[bb])"
        let game = SGFGame.from(tree: try SGFParser.parse(text: text))
        let fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sgf")
        try text.write(to: fixtureURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let wrapper = SGFGameWrapper(url: fixtureURL, game: game)
        model.selectGame(wrapper); settle()
        model.player.seek(to: 1); settle()
        vm.placeStone(at: BoardPosition(3, 3))
        require(model.mode == .review && model.player.maxIndex == 2 && model.player.currentIndex == 1,
                "Review must preserve history and reject edits")
        model.mode = .localPlay; settle()
        require(model.player.maxIndex == 1 && model.player.board.stones[BoardPosition(2, 2)] == .black,
                "Local board survives Review")
        model.aiAnalysisEnabled = true
        require(model.isAIAvailable, "AI available in Local Play")
        let index = model.player.currentIndex
        model.aiAnalysisEnabled = false
        require(model.player.currentIndex == index && !model.isAIAvailable, "AI toggle must not navigate")
        model.aiAnalysisEnabled = true
        model.mode = .review; settle()
        require(model.player.currentIndex == 1 && model.player.maxIndex == 2 && model.isAIAvailable,
                "Review position and AI survive round trip")
        model.mode = .playOnline
        socket.onOpen?(); client.isSocketAuthenticated = true; settle()
        require(!client.observationOnly && !model.isAIAvailable, "Play enables participation and disables AI")
        require(client.isConnected && client.username == "TestingAccount", "Fixture signed in")
        model.mode = .observe; settle()
        require(client.observationOnly && !model.isAIAvailable, "Observe waits for game identity")
        model.resumeOnlineGame(id: 9); settle()
        require(vm.isOnlineContext && model.player.maxIndex == 2, "Observed game loads")
        require(model.isAIAvailable && !client.isAccountGameParticipant, "AI allowed for observing other players")
        model.mode = .playOnline; settle()
        model.joinOnlineGame(id: 8); settle()
        require(client.activeGameID == 7 && !client.isSearchingForGame, "Accepted challenge must open its game")
        require(client.isAccountGameParticipant && client.isGameParticipant && !model.isAIAvailable, "Own online game disables AI")
        model.mode = .observe; settle()
        require(!model.isAIAvailable && client.hasOngoingAccountGame, "Changing to Observe cannot enable AI for a participant")
        model.mode = .localPlay; settle()
        require(!model.isAIAvailable && model.player.maxIndex == 1, "Local position preserved; ongoing online play still disables AI")
        let localIndex = model.player.currentIndex
        socket.receiver?(.success(#"42["game/7/move",{"move":"cc","move_number":3}]"#)); settle()
        require(model.player.currentIndex == localIndex && model.player.maxIndex == 1, "Late remote move must not edit local board")
        model.mode = .review; settle()
        require(!model.isAIAvailable, "Review cannot bypass ongoing-game restriction")
        socket.receiver?(.success(#"42["active_game",{"id":7,"phase":"finished"}]"#)); settle()
        require(model.isAIAvailable, "Finished game releases AI restriction")
        require(socket.cancellations == 0 && client.isSocketAuthenticated, "Mode switches must keep connection and login")
        model.copyCurrentBoard(to: .localPlay); settle()
        require(model.player.currentIndex == 1 && model.player.maxIndex == 2, "Continue locally copies review history")
        model.newLocalGame(); settle()
        require(model.player.maxIndex == 0, "New Game clears only local board")
        model.mode = .review; settle()
        require(model.player.maxIndex == 2 && model.player.currentIndex == 1, "New local game preserves review")

        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.orderOut(nil); client.disconnect() }
        func render<V: View>(_ view: V) throws -> String {
            let host = NSHostingView(rootView: view.environmentObject(model)
                .frame(width: 1000, height: 700).background(Color(nsColor: .windowBackgroundColor)))
            window.contentView = host; window.orderFront(nil); settle()
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/sgf-four-modes-preview.png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        }
        let controls = try render(AppModeControls()).replacingOccurrences(of: "al analysis", with: "ai analysis")
        for label in ["play online", "local play", "observe", "review", "ai analysis", "testingaccount", "log out"] {
            require(controls.contains(label), "Missing control \(label): \(controls)")
        }
        model.mode = .playOnline; model.showOnlineBrowser(); settle()
        let fixtures = #"[{"id":1,"username":"NineRated","user_id":10,"width":9,"height":9,"ranked":true,"time_per_move":60},{"id":2,"username":"Nineteen","user_id":11,"width":19,"height":19,"ranked":false,"time_per_move":60},{"id":3,"username":"Correspondence","user_id":12,"width":9,"height":9,"ranked":true,"time_per_move":86400},{"id":4,"username":"Ineligible","user_id":13,"width":9,"height":9,"ranked":true,"time_per_move":60,"min_rank":40}]"#
        client.availableGames = try JSONDecoder().decode([OGSChallenge].self, from: Data(fixtures.utf8))
        UserDefaults.standard.set("9", forKey: "ogs_filter_sizes")
        UserDefaults.standard.set("Live", forKey: "ogs_filter_speed")
        UserDefaults.standard.set(true, forKey: "ogs_filter_ranked")
        UserDefaults.standard.set(false, forKey: "ogs_filter_ineligible")
        let lobby = try render(RightPanelView().frame(width: 320, height: 620))
        require(lobby.contains("ninerated") && lobby.contains("accept") && lobby.contains("create"), "Lobby missing: \(lobby)")
        require(!lobby.contains("nineteen") && !lobby.contains("correspondence"), "Size/speed filters failed")
        require(lobby.components(separatedBy: "ineligible").count == 2, "Ineligible challenge should be filtered; only toggle should remain")
        for key in ["ogs_filter_sizes", "ogs_filter_speed", "ogs_filter_ranked", "ogs_filter_ineligible"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        model.viewMode = .view2D
        let fullUI = try render(ContentView())
        require(fullUI.contains("play online") && fullUI.contains("testingaccount") && fullUI.contains("lobby"), "Full app controls missing: \(fullUI)")
        print("PASS: Four modes, independent AI, real account participation, no mode-driven logout, separate board positions, late-event isolation, username, and restored lobby filters. Network denied; fake transports only.")
    }
}
