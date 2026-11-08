import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct ContinuousAnalysisCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.removeObject(forKey: "folderURLBookmark")
        UserDefaults.standard.set("review", forKey: "lastAppMode")
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.analysisEnabled = true
        AppSettings.shared.analyzeDuringPlay = false
        AppSettings.shared.moveInterval = 10
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("continuous-analysis-\(UUID())")
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
        let model = temp.appendingPathComponent("model"); try Data().write(to: model)
        let ai = KataGoEngine(executableURL: executable, modelURL: model, cacheDirectory: temp.appendingPathComponent("cache"))
        let app = AppModel(analysisEngine: ai)
        defer { app.ogsClient.disconnect(); ai.stop() }
        let sgf = "(;SZ[9]RU[Japanese];B[aa];W[bb];B[cc])"
        let url = temp.appendingPathComponent("game.sgf")
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        let wrapper = SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf)))
        app.selectGame(wrapper)
        app.aiAnalysisEnabled = true
        let vm = app.boardVM!
        func settle(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        settle(); vm.seekToMove(1); settle()
        let original = app.player.board
        let history = vm.reviewSGFData()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 850),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: AIWorkspacePanel(vm: vm, ai: ai).environmentObject(app))
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        func capture() throws -> [VNRecognizedTextObservation] {
            settle(); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let recognition = VNRecognizeTextRequest(); recognition.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([recognition])
            try bitmap.representation(using: .png, properties: [:])!.write(to: temp.appendingPathComponent("controls.png"))
            return recognition.results ?? []
        }
        func pressToggle() throws {
            let text = try capture()
            guard let label = text.first(where: { $0.topCandidates(1).first?.string.contains("Keep analyzing") == true }) else {
                require(false, "Keep analyzing is visible at narrow panel width: \(text.compactMap { $0.topCandidates(1).first?.string })"); return
            }
            // The native switch sits immediately after its label on macOS.
            let point = NSPoint(x: host.bounds.width * label.boundingBox.maxX + 25,
                y: host.bounds.height * (host.isFlipped ? 1 - label.boundingBox.midY : label.boundingBox.midY))
            let location = host.convert(point, to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            NSApp.postEvent(event(.leftMouseUp), atStart: false)
            window.sendEvent(event(.leftMouseDown)); window.sendEvent(event(.leftMouseUp)); settle()
        }
        func queries() -> [[String: Any]] {
            ((try? String(contentsOf: temp.appendingPathComponent("requests.jsonl"))) ?? "")
                .split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        }
        func continuousQueries() -> [[String: Any]] { queries().filter { $0["maxVisits"] as? Int == 1_000_000_000 } }
        func report(_ query: [String: Any], visits: Int) throws {
            ai.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id": query["id"]!,
                "turnNumber": (query["moves"] as! [[String]]).count, "isDuringSearch": true,
                "rootInfo": ["winrate": 0.6, "scoreLead": 2, "visits": visits]]))
        }
        try pressToggle()
        require(app.keepAnalyzing && ai.continuousAnalysisTurn == 1, "Actual toggle starts current-position search")
        let first = continuousQueries().last!
        try report(first, visits: 800); try report(first, visits: 4500); settle()
        require(ai.currentAnalysisData[1]?.rootInfo?.visits == 4500, "Search deepens beyond automatic analysis")
        let labels = try capture().compactMap { $0.topCandidates(1).first?.string }
        require(labels.contains { $0.contains("4500") || $0.contains("4,500") }, "Live visit count is visible: \(labels)")
        app.updatePlayedGameAnalysis(); settle()
        require(continuousQueries().count == 1, "Refreshes do not restart ongoing search")
        require(app.player.board == original && vm.reviewSGFData() == history, "Analysis does not alter game or tree")
        vm.hoverAnalysis(at: BoardPosition(2, 2)); settle(0.65)
        let hover = queries().last { $0["allowMoves"] != nil }!
        require(app.keepAnalyzing && ai.continuousAnalysisTurn == nil,
                "Uncached hover yields the continuous worker without changing the user's toggle")
        require(queries().contains { $0["terminateId"] as? String == first["id"] as? String },
                "The running continuous query is terminated so KataGo can actually start the hover")
        app.updatePlayedGameAnalysis(); settle(0.65)
        require(continuousQueries().count == 1, "Real periodic ticks wait while the hover is pending")
        ai.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id": hover["id"]!,
            "turnNumber": 1, "isDuringSearch": false,
            "moveInfos": [["move": "C7", "visits": 100, "winrate": 0.6, "scoreLead": 2,
                           "pv": ["C7", "D6", "E5"]]]]))
        settle(0.05)
        require(vm.variationFrame?.numbers[BoardPosition(2, 2)] == 1, "Hover lands its first numbered stone")
        app.updatePlayedGameAnalysis(); settle(0.75)
        require(app.keepAnalyzing && ai.continuousAnalysisTurn == 1,
                "Continuous analysis automatically resumes after the continuation arrives")
        require(vm.variationFrame?.numbers[BoardPosition(3, 3)] == 2, "Numbered continuation advances while analysis resumes")
        require(app.player.board == original && vm.reviewSGFData() == history, "Hover leaves the actual game and tree intact")
        vm.hoverAnalysis(at: nil); settle()
        try pressToggle()
        require(!app.keepAnalyzing && ai.continuousAnalysisTurn == nil, "Actual toggle stops search")
        try report(first, visits: 9000)
        require(ai.currentAnalysisData[1]?.rootInfo?.visits == 4500, "Stopping retains depth and rejects stale reports")
        app.setKeepAnalyzing(true); settle()
        vm.seekToMove(2); settle()
        require(app.keepAnalyzing && ai.continuousAnalysisTurn == 2, "Search follows selected move")
        require(continuousQueries().last?["moves"] as? [[String]] == [["B", "A9"], ["W", "B8"]], "Search uses the real selected position")
        app.player.play(); settle()
        require(app.keepAnalyzing && ai.continuousAnalysisTurn == nil, "Playback pauses continuous work")
        app.player.pause(); settle()
        require(ai.continuousAnalysisTurn == app.player.currentIndex, "Pausing playback resumes at selected move")
        vm.beginScrubbing(); settle()
        require(ai.continuousAnalysisTurn == nil, "Scrubbing pauses work")
        vm.endScrubbing(at: 1); settle()
        require(ai.continuousAnalysisTurn == 1, "Scrub release resumes at exact final move")
        app.aiAnalysisEnabled = false; settle()
        require(!app.keepAnalyzing && ai.continuousAnalysisTurn == nil, "AI off cancels and clears the toggle")
        app.aiAnalysisEnabled = true; app.setKeepAnalyzing(true); settle()
        app.selectGame(wrapper); settle()
        require(!app.keepAnalyzing && ai.continuousAnalysisTurn == nil, "Opening a game clears demand analysis")
        app.setKeepAnalyzing(true); settle()
        app.mode = .localPlay; settle()
        app.setKeepAnalyzing(true)
        require(!app.keepAnalyzing && ai.continuousAnalysisTurn == nil, "Live-play restrictions apply to the toggle")
        print("PASS: real toggle clicks and live depth display, streaming, no duplicate searches, stop/late replies, navigation, playback, scrub, AI off, game replacement and live-play gating")
    }
}
