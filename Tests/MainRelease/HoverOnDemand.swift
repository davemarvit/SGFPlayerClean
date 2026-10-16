import SwiftUI
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class HoverHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct HoverOnDemandCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0; AppSettings.shared.folderURL = nil
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("hover-demand-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let executable = temp.appendingPathComponent("fixture-engine")
        try #"""
        #!/usr/bin/python3
        import sys,json,pathlib
        root=pathlib.Path(__file__).parent
        for line in sys.stdin:
            q=json.loads(line)
            with (root/'requests.jsonl').open('a') as f: f.write(json.dumps(q)+'\n')
        """#.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let model = temp.appendingPathComponent("weights"); try Data().write(to: model)
        let ai = KataGoEngine(executableURL: executable, modelURL: model, cacheDirectory: temp.appendingPathComponent("cache"))
        ai.currentGameId = "hover-fixture"; ai.start()
        require(ai.isEngineRunning, "Temporary engine started")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HoverHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9]RU[Japanese]KM[6.5];B[aa];W[bb];B[cc])")))
        player.seek(to: 1)
        let vm = BoardViewModel(player: player, ogsClient: client, isAIAllowed: { false }, analysisEngine: ai)
        var allowed = true
        vm.canPreviewAnalysis = { allowed }
        var sounds = 0; vm.onPlaySound = { _ in sounds += 1 }
        func settle(_ time: Double = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(time)) }
        func queries() -> [[String: Any]] {
            let text = (try? String(contentsOf: temp.appendingPathComponent("requests.jsonl"))) ?? ""
            return text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        }
        func waitForQueryCount(_ count: Int) {
            let deadline = Date().addingTimeInterval(3)
            while queries().count < count && Date() < deadline { settle(0.02) }
            require(queries().count >= count, "Expected fixture query count")
        }
        func reply(_ query: [String: Any], move: String = "C7") throws {
            let result: [String: Any] = ["id": query["id"]!, "turnNumber":1, "isDuringSearch":false,
                "rootInfo":["visits":100,"winrate":0.5,"scoreLead":0],
                "moveInfos":[["move":move,"visits":100,"winrate":0.5,"scoreLead":0,"pv":[move,"D6","pass"]]]]
            ai.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: result))
        }
        settle(); sounds = 0
        let original = player.board
        vm.hoverAnalysis(at: BoardPosition(2,2)); settle(0.2); vm.hoverAnalysis(at: nil); settle(0.4)
        require(queries().isEmpty, "Quick rollover must not send requests")
        vm.hoverAnalysis(at: BoardPosition(2,2)); settle(0.55); waitForQueryCount(1)
        require(vm.variationStatus == "Computing AI preview…" && !vm.isPreviewingVariation, "Waiting status visible before result")
        try reply(queries()[0])
        require(vm.isPreviewingVariation && vm.variationStatus == nil, "New analysis starts preview without moving pointer")
        require(vm.variationFrame?.numbers[BoardPosition(2,2)] == 1, "Hovered move numbered first")
        require(player.board == original && player.currentIndex == 1 && player.maxIndex == 3 && sounds == 0,
            "On-demand analysis leaves actual game and audio alone")
        vm.hoverAnalysis(at: nil)
        vm.hoverAnalysis(at: BoardPosition(2,2)); settle(0.55)
        require(vm.isPreviewingVariation && queries().count == 1, "Second hover reuses computed continuation")
        vm.hoverAnalysis(at: nil)
        vm.hoverAnalysis(at: BoardPosition(4,4)); settle(0.55); waitForQueryCount(2)
        let stale = queries()[1]
        vm.hoverAnalysis(at: nil); waitForQueryCount(3)
        require(queries()[2]["action"] as? String == "terminate", "Leaving cancels actual computation")
        try reply(stale, move: "E5")
        require(!vm.isPreviewingVariation && vm.variationStatus == nil, "Late reply cannot restore dismissed preview")
        vm.hoverAnalysis(at: BoardPosition(4,4)); settle(0.55); waitForQueryCount(4)
        allowed = false; vm.updateAnalysisPermission()
        require(!ai.hasPendingAnalysis && vm.variationStatus == nil, "Permission change cancels hover work")
        vm.hoverAnalysis(at: BoardPosition(4,4)); settle(0.6)
        require(queries().filter { $0["allowMoves"] != nil }.count == 3, "Disallowed mode cannot submit hover analysis")
        ai.stop()
        let fresh = KataGoEngine(executableURL: executable, modelURL: model, cacheDirectory: temp.appendingPathComponent("cache"))
        require(fresh.loadAnalysisCache(for: "hover-fixture", game: player), "Computed preview saved on disk")
        require(fresh.cachedHoverAnalysis(game: player, point: BoardPosition(2,2))?.pv?.count == 3, "Continuation reusable after restart")
        fresh.stop()
        print("PASS: missing candidate triggers delayed analysis, waiting status, preview, cache reuse, cancellation, mode gate and persistence")
    }
}
