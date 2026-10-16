import SwiftUI
import SceneKit
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class ResultsHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        require(request.httpMethod == "GET", "No game mutations in offline tests")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct ResultsMistakesLids {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.isMuted = true; AppSettings.shared.folderURL = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ResultsHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        let app = AppModel(ogsClient: client)
        defer { client.disconnect(); KataGoEngine.shared.stop() }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let text = "(;SZ[19]PB[Alice]PW[Bob]RU[Japanese];B[dd];W[pp];B[jj];W[jk];B[kk];W[kj])"
        let url = temporary.appendingPathComponent("review.sgf")
        try text.write(to: url, atomically: true, encoding: .utf8)
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: text))))
        let vm = app.boardVM!, ai = KataGoEngine.shared
        app.aiAnalysisEnabled = true
        func settle(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        settle()
        let scores: [Double] = [0,0,0,-1,4,-5,10]
        for turn in 0...6 {
            let score = scores[turn] * (turn.isMultiple(of: 2) ? 1 : -1)
            var candidate = AIMoveInfo(move: "D4", visits: 100, winrate: 0.5, scoreLead: score, pv: nil)
            candidate.prior = 1; candidate.order = 0
            ai.currentAnalysisData[turn] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: turn, moveInfos: [candidate],
                rootInfo: AIRootInfo(winrate: 0.5, scoreLead: score, visits: 100))
        }
        settle()
        vm.mistakeMinimumLoss = 4; vm.mistakePlayers = .both
        require(vm.matchingMistakeMoves == [4,5,6], "Point-loss filter must use played move numbers")
        vm.goToStart(); settle(); vm.seekNextMistake(); settle(); require(vm.currentMoveIndex == 4, "Forward lands AFTER the mistake")
        vm.seekNextMistake(); settle(); require(vm.currentMoveIndex == 5, "Next mistake")
        vm.seekPrevMistake(); settle(); require(vm.currentMoveIndex == 4, "Previous mistake")
        vm.mistakePlayers = .black; require(vm.matchingMistakeMoves == [5], "Black filter")
        vm.mistakePlayers = .white; require(vm.matchingMistakeMoves == [4,6], "White filter")
        vm.seekNextMistake(); settle(); require(vm.currentMoveIndex == 6 && vm.nextMistakeMove == nil, "No wrap at end")
        vm.seekNextMistake(); settle(); require(vm.currentMoveIndex == 6, "No surprise jump at end")
        vm.mistakeMinimumLoss = 20; vm.seekPrevMistake(); settle()
        require(vm.previousMistakeMove == nil && vm.currentMoveIndex == 6, "Empty filter does not jump to start")
        vm.mistakeMinimumLoss = 4; vm.mistakePlayers = .both
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.orderFront(nil); defer { window.orderOut(nil) }
        func capture<V: View>(_ view: V, size: CGSize, name: String) throws -> [VNRecognizedTextObservation] {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            window.setContentSize(size); window.contentView = host; settle(0.4)
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-results-\(name).png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return request.results ?? []
        }
        let evals = Array(ai.evaluateGameQuality(upTo: vm.totalMoves, engine: vm.engine).values)
        let stats = try capture(VStack(alignment: .leading, spacing: 16) {
            MistakeFilterView(vm: vm, analyzedCount: evals.count)
            MoveQualitySummaryView(evals: evals, analyses: ai.currentAnalysisData)
        }.padding().background(.black), size: CGSize(width: 320, height: 360), name: "filters")
        let words = stats.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        require(words.contains("3 matching") && words.contains("Accuracy") && words.contains("Average loss"), "Filter and statistics visible: \(words)")
        _ = try capture(HStack(spacing: 20) {
            SimpleLidView(stoneColor: .white, stoneCount: 55, stoneSize: 48, lidNumber: 2, lidSize: 320, seed: 123)
            SimpleLidView(stoneColor: .white, stoneCount: 55, stoneSize: 48, lidNumber: 2, lidSize: 320, seed: 456)
            SimpleLidView(stoneColor: .black, stoneCount: 55, stoneSize: 48, lidNumber: 1, lidSize: 320, seed: 123)
        }.padding().background(.gray), size: CGSize(width: 1040, height: 360), name: "lids")
        // Fixed footer remains available without closing a result at normal and short heights.
        app.mode = .playOnline; client.activeGameID = 91
        client.activeGameResult = .init(title: "You win!", subtitle: "Alice [Black] wins", method: "By resignation", isMe: true)
        client.applyScoringSnapshot(["game_id": 91, "phase": "finished", "outcome": "Resignation"])
        settle()
        for (height, scored) in [(700, false), (400, false), (400, true)] {
            if scored {
                client.applyScoringSnapshot(["game_id": 91, "outcome": "2.5 points", "score": [
                    "black": ["total": 20, "territory": 18, "prisoners": 2],
                    "white": ["total": 22.5, "territory": 14, "prisoners": 2, "komi": 6.5]]])
                settle()
                require(client.scoringDisplaySummary != nil, "Scored result fixture")
            }
            let result = try capture(ActiveGamePanel().environmentObject(app).background(.black),
                size: CGSize(width: 320, height: height), name: "result-\(height)-\(scored ? "scored" : "resign")")
            let all = result.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            require(all.contains("Save SGF") && all.contains("Review game") && all.contains("Back to lobby"), "Finished controls visible at \(height): \(all)")
            let save = result.first { $0.topCandidates(1).first?.string.contains("Save SGF") == true }!
            let banner = result.first { $0.topCandidates(1).first?.string.contains("You win") == true }
            if let banner { require(!save.boundingBox.intersects(banner.boundingBox), "Result never covers Save SGF") }
        }
        let scene = SceneManager3D()
        scene.updateCapturedStones(black: 55, white: 55, seed: 123)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene.scene; renderer.pointOfView = scene.cameraNode
        for step in 0..<180 {
            _ = renderer.snapshot(atTime: Double(step) / 60, with: CGSize(width: 96, height: 96), antialiasingMode: .none)
        }
        let image = renderer.snapshot(atTime: 3, with: CGSize(width: 900, height: 700), antialiasingMode: .multisampling4X)
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-results-lids3d.png"))
        print("PASS: point/player filters, inclusive thresholds, correct navigation indices, no wrap, statistics, varied lids and unobstructed finished-game controls at two window heights")
    }
}
