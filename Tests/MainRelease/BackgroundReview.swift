import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private final class ModeHTTP: URLProtocol {
    static var finalGameID: Int?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        var body: String
        var status = 200
        if path == "/api/v1/ui/config" {
            body = #"{"user":{"id":99,"username":"TestingAccount","ranking":25},"user_jwt":"fixture"}"#
        } else if path == "/api/v1/challenges/8/accept" {
            require(request.httpMethod == "POST", "Challenge acceptance must use POST")
            body = #"{"id":7}"#
        } else if path == "/api/v1/challenges/403/accept" {
            status = 403
            body = #"{"detail":"Your rank does not meet this challenge's restrictions."}"#
        } else if path == "/api/v1/challenges/404/accept" {
            status = 404
            body = #"{"detail":"This challenge is no longer available."}"#
        } else if path == "/api/v1/challenges/400/accept" {
            status = 403
            body = "{}"
        } else if path.contains("/games/") {
            let id = Int(path.split(separator: "/").last!) ?? 9
            body = "{\"id\":\(id),\"width\":9,\"height\":9,\"phase\":\"play\",\"rules\":\"japanese\",\"komi\":6.5,\"initial_player\":\"black\",\"moves\":[[0,0],[1,1]],\"players\":{\"black\":{\"id\":\((id == 7 || id == 17) ? 99 : 10),\"username\":\"Black\"},\"white\":{\"id\":11,\"username\":\"White\"}}}"
            if Self.finalGameID == id {
                body = body.replacingOccurrences(of: "\"phase\":\"play\"", with: "\"phase\":\"finished\",\"outcome\":\"Resignation\",\"winner\":99")
                    .replacingOccurrences(of: "[[0,0],[1,1]]", with: "[[0,0],[1,1],[2,2]]")
            }
        } else { body = "{\"results\":[],\"next\":null}" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
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
    var lobbyFixture: String?
    func resume() {}
    func receive(_ completion: @escaping (Result<String, Error>) -> Void) { receiver = completion }
    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        messages.append(text); completion(nil)
        if text.contains("seek_graph/connect"), let fixture = lobbyFixture {
            DispatchQueue.main.async { self.receiver?(.success("42[\"seekgraph/global\",\(fixture)]")) }
        }
    }
    func ping(_ completion: @escaping (Error?) -> Void) { completion(nil) }
    func cancel() { cancellations += 1 }
}

@main struct BackgroundReviewCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.removeObject(forKey: "folderURLBookmark")
        UserDefaults.standard.removeObject(forKey: "lastAppMode")
        UserDefaults.standard.set(false, forKey: "isOnlineModePersistent")
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.analyzeDuringPlay = false
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("background-review-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let executable = temp.appendingPathComponent("fixture-engine")
        try #"""
        #!/usr/bin/python3
        import sys,json,pathlib
        for line in sys.stdin:
            q=json.loads(line)
            if 'action' in q: continue
            print(json.dumps(dict(id=q['id'],turnNumber=len(q['moves']),isDuringSearch=False,
                rootInfo=dict(visits=q['maxVisits'],winrate=0.6,scoreLead=2.5))),flush=True)
        """#.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath: executable.path)
        let model = temp.appendingPathComponent("model"); try Data().write(to: model)
        let ai = KataGoEngine(executableURL: executable, modelURL: model, cacheDirectory: temp.appendingPathComponent("cache"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModeHTTP.self]; config.httpCookieStorage = nil
        let socket = ModeSocket()
        let client = OGSClient(session: URLSession(configuration: config, delegate: nil, delegateQueue: .main), socketFactory: { socket })
        let app = AppModel(ogsClient: client, analysisEngine: ai)
        defer { client.disconnect(); ai.stop() }
        let vm = app.boardVM!
        func settle(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func seed() {
            ai.start()
            for i in 0...app.player.maxIndex {
                let payload = app.player.getAIPayload(at: i)
                ai.analyzeGame(id: ai.currentGameId, initialStones: payload.initial, moves: payload.moves,
                    size: app.player.board.size, maxVisits: 800, settings: app.player.analysisSettings)
            }
            let deadline = Date().addingTimeInterval(3)
            while ai.hasPendingAnalysis && Date() < deadline { settle(0.02) }
            require(!ai.currentAnalysisData.isEmpty, "Fixture must have completed analysis (running=\(ai.isEngineRunning), pending=\(ai.hasPendingAnalysis), id=\(ai.currentGameId), startup=\(ai.engineStartupError ?? "none"), error=\(ai.analysisError ?? "none"))")
        }
        app.newLocalGame()
        app.player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9]RU[Chinese]KM[6.5];B[aa];W[bb])")))
        app.player.seek(to: 2); vm.syncState()
        AppSettings.shared.analyzeDuringPlay = true
        app.updatePlayedGameAnalysis(resources: AnalysisResources(), now: 0)
        app.updatePlayedGameAnalysis(resources: AnalysisResources(), now: 1)
        require(ai.hasPendingAnalysis && ai.isEngineRunning && !app.aiAnalysisEnabled,
                "Playing schedules hidden analysis independently of the visible AI toggle (running=\(ai.isEngineRunning), pending=\(ai.hasPendingAnalysis), error=\(ai.engineStartupError ?? "none"))")
        AppSettings.shared.analyzeDuringPlay = false
        app.updatePlayedGameAnalysis(resources: AnalysisResources())
        require(!ai.hasPendingAnalysis, "Disabling realtime analysis stops computation")
        seed()
        let localID = ai.currentGameId
        app.aiAnalysisEnabled = true
        require(!app.isAIAvailable && !app.showsAnalysisWorkspace, "Local play hides graph and hints even when results exist")
        require(vm.selectedMoveFeedback == nil && vm.recentMoveQualityMarkers.isEmpty, "Local play hides move-quality feedback")
        require(vm.canPreviewAnalysis?() == false, "No hover analysis while playing")
        require(vm.matchingMistakeMoves.isEmpty, "Mistake navigation cannot leak hidden analysis")
        app.copyCurrentBoard(to: .review); settle()
        require(!app.isAIAvailable && vm.canPreviewAnalysis?() == false, "Manual Review cannot reveal unfinished local analysis")
        vm.placeStone(at: BoardPosition(3,3)); settle()
        require(!app.isAIAvailable, "Creating a variation cannot reveal the unfinished game")
        app.mode = .localPlay; settle()
        require(ai.currentGameId == localID && app.player.maxIndex == 2, "Return to original local game")
        vm.passLocally(); settle(); vm.passLocally(); settle()
        require(vm.localScoringVisible && !app.isAIAvailable && app.mode == .localPlay, "Two passes enter scoring without revealing AI")
        seed()
        let localVisits = ai.currentAnalysisData[1]?.rootInfo?.visits
        app.showRightPanel = true
        vm.confirmLocalScore(); settle(0.65)
        require(app.mode == .review, "Local completion transitions without a user action")
        require(!app.showRightPanel && app.showsAnalysisWorkspace, "Local completion closes the library and keeps analysis visible")
        app.updatePlayedGameAnalysis(resources: AnalysisResources(onBattery: true))
        require(app.mode == .review && app.isAIAvailable, "Final local score automatically opens AI Review")
        require(ai.currentGameId == localID && ai.currentAnalysisData[1]?.rootInfo?.visits == localVisits,
                "Automatic transfer preserves analysis depth and identity")
        require(app.player.maxIndex == 4 && app.player.currentIndex == 4 && vm.reviewTree?.nodes.count == 5,
                "Review preserves entire game including passes and opens at the final position")
        require(!vm.localScoringVisible && app.completedGameResult != nil, "Review clears scoring controls and retains result")
        require(app.backgroundReviewStatus == "Paused to save battery", "Review explains battery pause while keeping saved results visible")
        vm.goToStart(); settle()
        require(app.player.currentIndex == 0, "Review navigation works immediately")

        app.mode = .localPlay; settle(0.65)
        require(app.mode == .localPlay && vm.localScoring?.isFinal == true, "Returning to a finished local board does not repeatedly force Review")
        vm.reviewLocalScore()
        app.copyCurrentBoard(to: .review)
        require(!app.isAIAvailable, "Reopening scoring hides the old review immediately, even before the resource timer fires")
        app.mode = .localPlay; vm.confirmLocalScore(); settle(0.65)
        require(app.mode == .review && app.isAIAvailable, "Reconfirming the score reveals Review again")

        app.mode = .playOnline; socket.onOpen?(); client.isSocketAuthenticated = true; settle()
        app.resumeOnlineGame(id: 7); settle(0.3)
        require(vm.isOnlineContext && client.isAccountGameParticipant && app.player.maxIndex == 2, "Own online game loaded")
        seed()
        require(!app.isAIAvailable && !app.showsAnalysisWorkspace && vm.canPreviewAnalysis?() == false,
                "Online analysis remains hidden with populated cache")
        client.phase = "stone removal"; settle()
        require(app.mode == .playOnline && !app.isAIAvailable, "Online scoring cannot reveal AI")
        client.phase = "play"; settle()
        require(app.mode == .playOnline, "Resuming scoring stays in Play")
        let onlineVisits = ai.currentAnalysisData[1]?.rootInfo?.visits
        app.showRightPanel = true
        app.player.seek(to: 0)
        socket.receiver?(.success(#"42["game/7/removed_stones_accepted",{"phase":"finished","outcome":"Resignation","winner":99}]"#))
        settle(0.4)
        require(app.mode == .review && app.isAIAvailable, "Confirmed online result opens Review automatically")
        require(!app.showRightPanel && app.showsAnalysisWorkspace, "Online completion closes the library and keeps analysis visible")
        require(app.player.maxIndex == 2 && app.player.currentIndex == 2, "Final review includes full history even when viewing earlier moves")
        require(ai.currentGameId == "7" && ai.currentAnalysisData[1]?.rootInfo?.visits == onlineVisits,
                "Online analysis survives transfer without save/load interaction")
        require(app.selection?.game.info.playerBlack == "Black" && app.selection?.game.info.playerWhite == "White",
                "Player metadata survives leaving OGS")
        require(app.completedGameResult?.lowercased().contains("resignation") == true, "Result survives leaving OGS")
        require(client.isSocketAuthenticated && socket.cancellations == 0, "Review keeps the user signed in")
        // Render the real workspace in both board styles. The result must be
        // readable above the board even at a compact window size.
        for (style, width, height) in [(ViewMode.view2D, 1000.0, 700.0), (.view3D, 1440.0, 900.0)] {
            app.viewMode = style
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: ContentView().environmentObject(app)
                .frame(width: width, height: height).background(Color(nsColor: .windowBackgroundColor)))
            window.contentView = host; window.orderFront(nil); settle(0.5)
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let name = style == .view2D ? "2d" : "3d"
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: "/private/tmp/sgf-postgame-\(name).png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string.lowercased() }
            require(lines.contains(where: { $0.contains("game finished") }), "Finished-game heading is visible in \(name)")
            require(lines.contains(where: { $0.contains("resignation") }), "Actual result is readable in \(name)")
            require(!lines.contains(where: { $0.contains("select folder") }), "Game library is closed in \(name)")
            window.orderOut(nil)
        }
        vm.goToStart(); settle()
        require(app.completedGameResult != nil, "Result remains available while reviewing earlier moves")
        app.showRightPanel = true
        socket.receiver?(.success(#"42["game/7/removed_stones_accepted",{"phase":"finished","outcome":"Resignation","winner":99}]"#))
        settle()
        require(app.player.currentIndex == 0, "Repeated finish events do not reset review position")
        require(app.showRightPanel, "Repeated finish events respect a manually reopened library")
        app.mode = .observe; app.resumeOnlineGame(id: 9); settle(0.3)
        socket.receiver?(.success(#"42["game/9/removed_stones_accepted",{"phase":"finished","outcome":"Timeout","winner":10}]"#))
        settle()
        require(app.mode == .observe, "Observed games do not hijack the user's mode")
        app.mode = .playOnline; app.resumeOnlineGame(id: 17); settle(0.3)
        require(app.player.maxIndex == 2 && app.mode == .playOnline, "Second played game loaded")
        ModeHTTP.finalGameID = 17
        socket.receiver?(.success(#"42["game/17/phase","finished"]"#))
        settle(0.6)
        require(app.mode == .review && app.player.maxIndex == 3 && app.player.currentIndex == 3,
                "Phase-only finish reconciles final server history before opening Review")
        require(app.selection?.game.info.result == "B+R", "Review retains SGF result")
        require(UserDefaults.standard.bool(forKey: "analyzeDuringPlay") == false, "Realtime off preference persists")
        AppSettings.shared.pauseAnalysisOnBattery = false
        require(UserDefaults.standard.object(forKey: "pauseAnalysisOnBattery") as? Bool == false, "Battery preference persists")
        print("PASS: hidden cached results in local/online play, no early reveal during scoring or manual Review/variations, automatic final-result transition, full history and cached depth retained, metadata/result retained, battery pause, navigation, duplicate completion and observation isolation.")
    }
}
