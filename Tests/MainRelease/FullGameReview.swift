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

@main struct FullGameReviewCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.removeObject(forKey: "folderURLBookmark")
        UserDefaults.standard.removeObject(forKey: "lastAppMode")
        UserDefaults.standard.set(false, forKey: "isOnlineModePersistent")
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.analysisEnabled = true
        AppSettings.shared.analyzeDuringPlay = false
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("background-review-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let executable = temp.appendingPathComponent("fixture-engine")
        try #"""
        #!/usr/bin/python3
        import sys,json,pathlib
        for line in sys.stdin:
            q=json.loads(line)
            with (pathlib.Path(__file__).parent/'requests.jsonl').open('a') as f: f.write(json.dumps(q)+'\n')
            if 'action' in q or q.get('maxVisits',0)>=1_000_000_000: continue
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
        func queries() -> [[String: Any]] {
            ((try? String(contentsOf: temp.appendingPathComponent("requests.jsonl"))) ?? "")
                .split(separator:"\n").compactMap { try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any] }
                .filter { $0["action"] == nil && ($0["maxVisits"] as? Int ?? 0)<1_000_000_000 }
        }
        func awaitCoverage() {
            let limit = Date().addingTimeInterval(8)
            while Date()<limit {
                if (0...app.player.maxIndex).allSatisfy({ (ai.currentAnalysisData[$0]?.rootInfo?.visits ?? 0)>=25 }) { return }
                settle(0.05)
            }
            require(false,"Every position must receive a first pass, including opening and final board: \(ai.currentAnalysisData.keys.sorted())")
        }
        app.newLocalGame()
        app.player.load(game:SGFGame.from(tree:try SGFParser.parse(text:"(;SZ[9]RU[Chinese]KM[6.5];B[aa];W[bb];B[cc];W[dd];B[ee];W[ff])")))
        app.player.seek(to:6); vm.syncState(); settle()
        require(ai.currentAnalysisData.isEmpty,"No background analysis has run during play")
        vm.passLocally(); settle(); vm.passLocally(); settle(); vm.confirmLocalScore(); settle(0.65)
        require(app.mode == .review && app.isAIAvailable && !app.usesAdaptiveAnalysis,"Finished local game starts foreground whole-game analysis")
        let finalIndex = app.player.currentIndex, finalBoard = app.player.board, history = vm.reviewSGFData()
        app.updatePlayedGameAnalysis(resources:AnalysisResources(onBattery:true,lowPower:true,cpuBusy:0.9))
        awaitCoverage()
        require(app.player.currentIndex == finalIndex && app.player.board == finalBoard && vm.reviewSGFData() == history,
                "Automatic whole-game analysis leaves the selected board and history unchanged")
        require(queries().contains { ($0["moves"] as? [[String]])?.isEmpty == true },"The empty opening is analyzed")
        app.setKeepAnalyzing(true); settle()
        require(app.keepAnalyzing && ai.continuousAnalysisTurn == finalIndex,"Position-only search is active before requesting the game")
        // Remove only disposable fixture results to prove the action fills every turn.
        ai.discardAnalysis(from:0)
        let firstQuery = queries().count
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:390,height:950),styleMask:[.titled],backing:.buffered,defer:false)
        let host=NSHostingView(rootView:AIWorkspacePanel(vm:vm,ai:ai).environmentObject(app))
        window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
        host.cacheDisplay(in:host.bounds,to:bitmap)
        let recognition=VNRecognizeTextRequest();recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage:bitmap.cgImage!).perform([recognition])
        let labels=recognition.results ?? []
        require(labels.contains { $0.topCandidates(1).first?.string.contains("Game coverage") == true },"Whole-game coverage is visible")
        guard let label=labels.first(where: { $0.topCandidates(1).first?.string.contains("Analyze full game") == true }) else {
            require(false,"Full-game action is visible");return
        }
        let box=label.boundingBox
        let point=host.convert(NSPoint(x:host.bounds.width*box.midX,y:host.bounds.height*(host.isFlipped ? 1-box.midY : box.midY)),to:nil)
        func event(_ type:NSEvent.EventType)->NSEvent {
            NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        NSApp.postEvent(event(.leftMouseUp),atStart:false)
        window.sendEvent(event(.leftMouseDown));window.sendEvent(event(.leftMouseUp));settle()
        require(!app.keepAnalyzing && ai.continuousAnalysisTurn == nil,"Full-game button stops the position-only search")
        awaitCoverage()
        let turns=queries().dropFirst(firstQuery).compactMap { ($0["moves"] as? [[String]])?.count }
        require(Array(turns.prefix(finalIndex+1)) == Array(0...finalIndex),"Explicit first pass proceeds from opening to final turn: \(turns)")
        require(app.player.currentIndex == finalIndex && vm.reviewSGFData() == history,"Explicit analysis keeps the current review position")

        app.mode = .playOnline; socket.onOpen?(); client.isSocketAuthenticated=true;settle()
        app.resumeOnlineGame(id:7);settle(0.3)
        require(vm.isOnlineContext && client.isAccountGameParticipant,"Online fixture is a live account game")
        socket.receiver?(.success(#"42["game/7/removed_stones_accepted",{"phase":"finished","outcome":"Resignation","winner":99}]"#))
        settle(0.4)
        require(app.mode == .review && app.isAIAvailable && !app.usesAdaptiveAnalysis,"Online completion also starts a whole-game sweep")
        awaitCoverage()
        require(Set(ai.currentAnalysisData.keys).isSuperset(of:Set(0...app.player.maxIndex)),"Online review covers every turn")
        AppSettings.shared.analysisEnabled=false;settle()
        app.analyzeFullGame();settle()
        require(!ai.isEngineRunning && !app.isAIAvailable,"Explicit analysis respects master off")
        AppSettings.shared.analysisEnabled=true;settle()
        app.mode = .localPlay;settle();let count=queries().count
        app.analyzeFullGame();settle()
        require(queries().count == count && !app.isAIAvailable,"Explicit full-game review cannot run during live play")
        print("PASS: local and online postgame automatic coverage; opening-first full-game button replaces continuous search; coverage display; board/history preserved; analysis-off and live-play restrictions")
    }
}
