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
        } else if path.hasSuffix("/sgf") {
            body = "(;SZ[9]PB[Black]PW[White];B[aa];W[bb])"
        } else if path.contains("/games/") {
            let id = Int(path.split(separator: "/").last!) ?? 9
            body = "{\"id\":\(id),\"width\":9,\"height\":9,\"phase\":\"play\",\"rules\":\"japanese\",\"komi\":6.5,\"initial_player\":\"black\",\"moves\":[[0,0],[1,1]],\"players\":{\"black\":{\"id\":\((id == 7 || id == 17) ? 99 : 10),\"username\":\"Black\"},\"white\":{\"id\":11,\"username\":\"White\"}}}"
            if Self.finalGameID == id {
                body = body.replacingOccurrences(of: "\"phase\":\"play\"", with: "\"phase\":\"finished\",\"outcome\":\"Resignation\",\"winner\":99")
                    .replacingOccurrences(of: "[[0,0],[1,1]]", with: "[[0,0],[1,1],[2,2]]")
            }
        } else { body = "{\"results\":[],\"next\":null}" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: path.hasSuffix("/sgf") ? ["Content-Disposition": "attachment; filename=7-000-White-Black.sgf"] : nil)!, cacheStoragePolicy: .notAllowed)
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

@main struct AnalysisSwitchCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.removeObject(forKey: "folderURLBookmark")
        UserDefaults.standard.removeObject(forKey: "lastAppMode")
        UserDefaults.standard.set(false, forKey: "isOnlineModePersistent")
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.analysisEnabled = false
        AppSettings.shared.analyzeDuringPlay = true
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
            let deadline = Date().addingTimeInterval(10)
            while ai.hasPendingAnalysis && Date() < deadline { settle(0.02) }
            require(!ai.currentAnalysisData.isEmpty, "Fixture must have completed analysis (running=\(ai.isEngineRunning), pending=\(ai.hasPendingAnalysis), id=\(ai.currentGameId), startup=\(ai.engineStartupError ?? "none"), error=\(ai.analysisError ?? "none"))")
        }
        settle()
        require(!ai.isEngineRunning, "Saved off preference prevents engine startup")
        app.newLocalGame()
        app.player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9]RU[Chinese]KM[6.5];B[aa];W[bb])")))
        app.player.seek(to: 2); vm.syncState()
        for time in [0.0,1,2] { app.updatePlayedGameAnalysis(resources: AnalysisResources(), now: time) }
        require(!ai.isEngineRunning && !ai.hasPendingAnalysis, "Master off overrides background-play preference")
        AppSettings.shared.analysisEnabled = true; settle()
        app.updatePlayedGameAnalysis(resources: AnalysisResources(), now: 10)
        require(ai.isEngineRunning, "Enabling resumes hidden local analysis")
        AppSettings.shared.analyzeDuringPlay = false
        app.updatePlayedGameAnalysis(resources: AnalysisResources())
        seed()
        let localID = ai.currentGameId
        let savedVisits = ai.currentAnalysisData[1]?.rootInfo?.visits
        require(savedVisits == 800, "Deep completed results are available before disabling")
        let pending = app.player.getCurrentAIPayload()
        ai.analyzeGame(id:localID,initialStones:pending.initial,moves:pending.moves,
                       size:app.player.board.size,maxVisits:1600,settings:app.player.analysisSettings)
        require(ai.hasPendingAnalysis,"There is active work when the switch is turned off")
        AppSettings.shared.analysisEnabled = false; settle()
        require(!ai.isEngineRunning && !ai.hasPendingAnalysis, "Disabling shuts down the active engine and pending work")
        AppSettings.shared.analyzeDuringPlay = true
        require(!UserDefaults.standard.bool(forKey: "analysisEnabled"), "Off preference is persisted")
        vm.passLocally(); settle(); vm.passLocally(); settle(); vm.confirmLocalScore(); settle(0.65)
        require(app.mode == .review && app.completedGameResult != nil, "Game completion still opens Review")
        require(!app.isAIAvailable && !ai.isEngineRunning,
                "Postgame Review cannot override master off")
        require(vm.canPreviewAnalysis?() == false && vm.matchingMistakeMoves.isEmpty,
                "Disabled analysis cannot leak hover or mistake feedback")
        AppSettings.shared.analysisEnabled = true; settle()
        require(app.isAIAvailable && app.showsAnalysisWorkspace, "Re-enabling restores Review results")
        require(ai.currentGameId == localID && (ai.currentAnalysisData[1]?.rootInfo?.visits ?? 0) >= (savedVisits ?? 0),
                "Re-enabling reloads saved depth without losing completed analysis")
        AppSettings.shared.analysisEnabled = false; settle()
        for mode in [AppMode.observe, .playOnline, .localPlay, .review] {
            app.mode = mode; app.aiAnalysisEnabled = true; settle()
            app.updatePlayedGameAnalysis(resources: AnalysisResources())
            require(!ai.isEngineRunning && !app.isAIAvailable, "Mode switches and AI toolbar cannot override master off")
        }
        // A newly constructed app reads the same saved off preference.
        app.mode = .localPlay; settle()
        let restartedAI = KataGoEngine(executableURL: executable, modelURL: model, cacheDirectory: temp.appendingPathComponent("restart-cache"))
        let restartSocket = ModeSocket()
        let restartedClient = OGSClient(session: URLSession(configuration: config, delegate:nil, delegateQueue:.main), socketFactory:{ restartSocket })
        let restarted = AppModel(ogsClient: restartedClient, analysisEngine: restartedAI)
        restarted.aiAnalysisEnabled = true; settle()
        require(!restartedAI.isEngineRunning && !restarted.isAIAvailable, "New app model honors saved off setting")
        restartedClient.disconnect(); restartedAI.stop()
        print("PASS: master switch persists, stops active/background work, survives modes and game completion, and restores cached analysis")
    }
}
