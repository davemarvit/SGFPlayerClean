import XCTest
import Combine
@testable import SGFPlayerNetworking

/// A local script exercises the actual Process and pipe code. No KataGo model, GPU, or network is used.
final class KataGoEngineTests: XCTestCase {
    private var directory: URL!
    private var engine: KataGoEngine!
    private var scheduler: TestScheduler!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sgf-katago-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-katago")
        let script = #"""
        #!/usr/bin/python3
        import json, sys, pathlib, os
        root = pathlib.Path(__file__).parent
        for line in sys.stdin:
            q = json.loads(line)
            with (root / "requests.jsonl").open("a") as f:
                f.write(json.dumps(q) + "\n")
            if (root / "crash").exists():
                sys.stderr.write("fixture engine failure\n"); sys.stderr.flush()
                sys.exit(23)
            if (root / "hold").exists():
                continue
            result = dict(id=q["id"], turnNumber=len(q["moves"]), isDuringSearch=False,
                rootInfo=dict(visits=q["maxVisits"], winrate=0.7, scoreLead=2.5), note="☃")
            data = (json.dumps(result, ensure_ascii=False) + "\n").encode()
            split = data.index("☃".encode()) + 1
            os.write(1, b"not json\n" + data[:split])
            os.write(1, data[split:])
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let model = directory.appendingPathComponent("fixture-model")
        try Data().write(to: model)
        scheduler = TestScheduler()
        engine = KataGoEngine(executableURL: executable, modelURL: model,
            cacheDirectory: directory.appendingPathComponent("cache"), scheduler: scheduler)
        engine.currentGameId = "game-a"
    }

    override func tearDownWithError() throws {
        engine.stop()
        engine = nil
        // Do not race pending cache I/O with temporary-directory removal.
        // These uniquely named directories are disposable and never touch the user's caches.
        scheduler = nil
    }

    private func eventually(_ description: String, _ condition: @escaping () -> Bool) {
        if condition() { return }
        let done = expectation(description: description)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
            if condition() { timer.invalidate(); done.fulfill() }
        }
        wait(for: [done], timeout: 5)
        timer.invalidate()
    }

    private func queries(_ count: Int) -> [[String: Any]] {
        let url = directory.appendingPathComponent("requests.jsonl")
        var result: [[String: Any]] = []
        eventually("\(count) queries written") {
            let text = (try? String(contentsOf: url)) ?? ""
            result = text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            return result.count >= count
        }
        return result
    }

    private func hold() throws { try Data().write(to: directory.appendingPathComponent("hold")) }
    private func analyze(id: String = "game-a", visits: Int = 50, x: Int? = nil) {
        engine.analyzeGame(id: id, initialStones: [], moves: x.map { [("B", $0, 0)] } ?? [], size: 9, maxVisits: visits)
    }
    private func response(_ query: [String: Any], visits: Int = 50, turn: Int? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": query["id"]!,
            "turnNumber": turn ?? (query["moves"] as! [[String]]).count,
            "isDuringSearch": false, "rootInfo": ["winrate": 0.7, "scoreLead": 2.5, "visits": visits]])
    }

    func testFailedPositionIsNotAutomaticallyResubmittedAndManualRetryWorks() throws {
        try hold(); engine.start(); analyze()
        let first = queries(1)[0]
        engine.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id":first["id"]!, "error":"illegal ko move"]))
        XCTAssertEqual(engine.analysisError, "Analysis failed: illegal ko move")
        analyze()
        let drained = expectation(description: "No automatic retry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(queries(1).count, 1)
        engine.retryFailedAnalysis(); analyze()
        XCTAssertEqual(queries(2).count, 2)
        XCTAssertNil(engine.analysisError)
    }

    func testTimedOutReplyIsIgnoredAndDoesNotResubmitUntilRetry() throws {
        try hold(); engine.start(); analyze()
        let first = queries(1)[0]
        scheduler.advance(by: 121)
        XCTAssertTrue(engine.analysisError?.contains("timed out") == true)
        engine.receiveAnalysisLine(try response(first))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
        engine.retryFailedAnalysis(); analyze()
        let retry = queries(2)[1]
        engine.receiveAnalysisLine(try response(retry))
        XCTAssertNotNil(engine.currentAnalysisData[0])
        scheduler.advance(by: 121)
        XCTAssertNil(engine.analysisError)
    }

    func testCustomRulesDoNotSilentlyAnalyzeWithDifferentPreset() throws {
        try hold(); engine.start()
        engine.analyzeGame(id: "game-a", initialStones: [], moves: [], size: 9,
            settings: GameAnalysisSettings(rules: "japanese", komi: 6.5,
                ruleOverrides: GoRuleOverrides(allowSelfCapture: true)))
        XCTAssertTrue(engine.analysisNotice?.contains("custom rule") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("requests.jsonl").path))
    }

    func testInvalidWinRateDoesNotEnterCacheOrDisplay() throws {
        try hold(); engine.start(); analyze()
        let query = queries(1)[0]
        engine.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id":query["id"]!, "turnNumber":0,
            "rootInfo":["winrate":2,"scoreLead":1,"visits":50]]))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
        XCTAssertNotNil(engine.analysisError)
    }

    func testRulesWarningsAreVisibleOnlyForCurrentRequests() throws {
        try hold(); engine.start(); analyze()
        let q = queries(1)[0]
        XCTAssertTrue(engine.hasPendingAnalysis)
        engine.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id":"old", "warning":"old rules"]))
        XCTAssertNil(engine.analysisWarning)
        engine.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id":q["id"]!, "warning":"rules approximated"]))
        XCTAssertEqual(engine.analysisWarning, "KataGo: rules approximated")
        engine.receiveAnalysisLine(try response(q))
        XCTAssertFalse(engine.hasPendingAnalysis)
        engine.currentGameId = "other"
        XCTAssertNil(engine.analysisWarning)
    }

    func testMissingCacheStillUpdatesMetadataNotice() {
        let player = SGFPlayer()
        var game = SGFGame(); game.info.rules = "unknown rules"
        player.load(game: game)
        XCTAssertFalse(engine.loadAnalysisCache(for: "never-cached", game: player))
        XCTAssertTrue(engine.analysisNotice?.contains("unsupported rules") == true)
    }

    func testMissingExecutableFailsWithoutLeavingRunningState() {
        let missing = KataGoEngine(executableURL: directory.appendingPathComponent("missing"), cacheDirectory: directory)
        missing.start()
        XCTAssertFalse(missing.isEngineRunning)
        XCTAssertNotNil(missing.engineStartupError)
        missing.stop()
    }

    func testQualityPreservesPerspectiveForConsecutiveHandicapMoves() {
        let player = SGFPlayer()
        var game = SGFGame()
        game.moves = [(.black, (0, 0)), (.black, (2, 2)), (.white, (4, 4))]
        player.load(game: game)
        engine.currentAnalysisData = [
            0: AIAnalysis(id: "a", isDuringSearch: false, turnNumber: 0, moveInfos: nil,
                          rootInfo: AIRootInfo(winrate: 0.8, scoreLead: 5, visits: 100)),
            1: AIAnalysis(id: "b", isDuringSearch: false, turnNumber: 1, moveInfos: nil,
                          rootInfo: AIRootInfo(winrate: 0.75, scoreLead: 4, visits: 100))]
        let quality = engine.evaluateGameQuality(upTo: 1, engine: player)[0]!
        XCTAssertEqual(quality.winDelta, -0.05, accuracy: 0.0001)
        XCTAssertEqual(quality.scoreDelta, -1)
        XCTAssertTrue(engine.evaluateGameQuality(upTo: -1, engine: player).isEmpty)
    }

    func testActualQueryUsesRulesKomiInitialPlayerAndHandicapBonus() throws {
        try hold(); engine.start()
        let settings = GameAnalysisSettings(rules: "Japanese", komi: 0.5, initialPlayer: .white, online: true, whiteHandicapBonus: "0")
        engine.analyzeGame(id: "game-a", initialStones: [("B", 2, 2), ("B", 6, 6)], moves: [], size: 9, settings: settings)
        let query = queries(1)[0]
        XCTAssertEqual(query["rules"] as? String, "japanese")
        XCTAssertEqual(query["komi"] as? Double, 0.5)
        XCTAssertEqual(query["initialPlayer"] as? String, "W")
        XCTAssertEqual(query["whiteHandicapBonus"] as? String, "0")
        XCTAssertEqual(query["initialStones"] as? [[String]], [["B","C7"],["B","G3"]])
        XCTAssertNil(engine.analysisNotice)
    }

    func testRulesAndKomiChangesInvalidateAllTurnsAndPendingReplies() throws {
        try hold(); engine.start()
        engine.analyzeGame(id: "game-a", initialStones: [], moves: [], size: 9,
            settings: GameAnalysisSettings(rules: "chinese", komi: 7.5, online: true))
        let old = queries(1)[0]
        XCTAssertEqual(old["rules"] as? String, "chinese-ogs")
        engine.receiveAnalysisLine(try response(old))
        engine.analyzeGame(id: "game-a", initialStones: [], moves: [("B", 0, 0)], size: 9,
            settings: GameAnalysisSettings(rules: "japanese", komi: 0))
        let changed = queries(2)[1]
        XCTAssertEqual(changed["komi"] as? Double, 0)
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
        engine.receiveAnalysisLine(try response(old))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
        engine.receiveAnalysisLine(try response(changed))
        XCTAssertNotNil(engine.currentAnalysisData[1])
    }

    func testUnknownRulesAndInvalidKomiDoNotSilentlyUseChineseDefaults() throws {
        try hold(); engine.start()
        for settings in [GameAnalysisSettings(rules: "Ing", komi: 8),
                         GameAnalysisSettings(rules: "japanese", komi: .nan),
                         GameAnalysisSettings(rules: "japanese", komi: 6.25)] {
            engine.analyzeGame(id: "game-a", initialStones: [], moves: [], size: 9, settings: settings)
            XCTAssertTrue(engine.analysisNotice?.contains("unavailable") == true)
        }
        analyze()
        XCTAssertEqual(queries(1).count, 1)
    }

    func testMissingMetadataIsExplicitAndZeroKomiIsPreserved() {
        engine.start()
        engine.analyzeGame(id: "game-a", initialStones: [], moves: [], size: 9, settings: GameAnalysisSettings())
        XCTAssertTrue(engine.analysisNotice?.contains("assumes") == true)
        let query = queries(1)[0]
        XCTAssertEqual(query["komi"] as? Double, 6.5)
        XCTAssertEqual(GameAnalysisSettings(rules: "New_Zealand", komi: 0).kataRules, "new-zealand")
        XCTAssertEqual(GameAnalysisSettings(rules: "AGA", komi: 0).effectiveKomi, 0)
    }

    func testCacheLoadRejectsChangedRulesAndTurnsBeyondUndoBeforePublishing() throws {
        try hold(); engine.start()
        let player = SGFPlayer()
        var game = SGFGame()
        game.boardSize = 9; game.info.rules = "japanese"; game.info.komi = "0.5"
        game.moves = [(.black, (0,0)), (.white, (1,1))]
        player.load(game: game)
        for turn in 0...2 {
            let payload = player.getAIPayload(at: turn)
            engine.analyzeGame(id: "game-a", initialStones: payload.initial, moves: payload.moves,
                size: 9, settings: player.analysisSettings)
            let query = queries(turn + 1)[turn]
            engine.receiveAnalysisLine(try response(query))
        }
        engine.saveAnalysisCache(for: "game-a")
        game.moves.removeLast()
        player.load(game: game)
        XCTAssertTrue(engine.loadAnalysisCache(for: "game-a", game: player))
        XCTAssertEqual(Set(engine.currentAnalysisData.keys), [0,1])
        game.info.komi = "7.5"
        player.load(game: game)
        XCTAssertFalse(engine.loadAnalysisCache(for: "game-a", game: player))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
    }

    func testRealPipesDecodeSplitUTF8AndInvalidLines() {
        engine.start()
        XCTAssertTrue(engine.isEngineRunning)
        analyze(x: 8)
        eventually("Analysis received") { self.engine.currentAnalysisData[1] != nil }
        XCTAssertEqual(engine.currentAnalysisData[1]?.rootInfo?.visits, 50)
        let query = queries(1)[0]
        XCTAssertEqual(query["moves"] as? [[String]], [["B", "J9"]])
        XCTAssertNil(engine.engineStartupError)
    }

    func testLateOtherGameAndWrongTurnResponsesAreIgnored() throws {
        try hold(); engine.start(); analyze()
        let first = queries(1)[0]
        engine.receiveAnalysisLine(try response(first, turn: 4))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
        engine.currentGameId = "game-b"
        analyze(id: "game-b")
        let second = queries(2)[1]
        engine.receiveAnalysisLine(try response(first))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
        engine.receiveAnalysisLine(try response(second))
        XCTAssertEqual(engine.currentAnalysisData[0]?.id, second["id"] as? String)
        engine.currentGameId = "game-a"
        engine.receiveAnalysisLine(try response(first))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty, "Switching back cannot revive an old request")
    }

    func testSameTurnUpgradeIgnoresOldResultAndCoalescesPendingRequest() throws {
        try hold(); engine.start(); analyze(visits: 25)
        let first = queries(1)[0]
        analyze(visits: 100); analyze(visits: 100)
        let second = queries(2)[1]
        XCTAssertNotEqual(first["id"] as? String, second["id"] as? String)
        engine.receiveAnalysisLine(try response(second, visits: 100))
        engine.receiveAnalysisLine(try response(first, visits: 25))
        XCTAssertEqual(engine.currentAnalysisData[0]?.rootInfo?.visits, 100)
        analyze(visits: 25)
        // A subsequent different turn is a write-queue barrier for the suppressed duplicate queries.
        analyze(x: 1)
        XCTAssertEqual(queries(3).count, 3)
    }

    func testStopThenStartFencesOldTerminationAndResponse() throws {
        try hold(); engine.start(); analyze()
        let first = queries(1)[0]
        engine.stop(); engine.start(); analyze()
        let second = queries(2)[1]
        engine.receiveAnalysisLine(try response(first))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
        engine.receiveAnalysisLine(try response(second))
        XCTAssertTrue(engine.isEngineRunning)
        XCTAssertNil(engine.engineStartupError)
        XCTAssertEqual(engine.currentAnalysisData[0]?.id, second["id"] as? String)
    }

    func testStopCancelsScheduledRestart() {
        engine.start(); engine.restart(); engine.stop()
        scheduler.advance(by: 2)
        XCTAssertFalse(engine.isEngineRunning)
    }

    func testCrashPublishesFailureAndCanRestart() throws {
        try Data().write(to: directory.appendingPathComponent("crash"))
        engine.start(); analyze()
        eventually("Crash observed") { !self.engine.isEngineRunning }
        XCTAssertTrue(engine.engineStartupError?.contains("23") == true)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("crash"))
        engine.start(); analyze()
        eventually("Restart analysis") { self.engine.currentAnalysisData[0] != nil }
        XCTAssertNil(engine.engineStartupError)
    }

    func testCacheWritesAreOrderedAtomicAndCannotEscapeCacheDirectory() throws {
        let gameID = "../../nested/game-☃"
        engine.currentGameId = gameID
        try hold(); engine.start(); analyze(id: gameID, visits: 25)
        let first = queries(1)[0]
        engine.receiveAnalysisLine(try response(first, visits: 25))
        engine.saveAnalysisCache(for: gameID)
        analyze(id: gameID, visits: 100)
        let second = queries(2)[1]
        engine.receiveAnalysisLine(try response(second, visits: 100))
        engine.saveAnalysisCache(for: gameID)
        XCTAssertTrue(engine.loadAnalysisCache(for: gameID))
        XCTAssertEqual(engine.currentAnalysisData[0]?.rootInfo?.visits, 100)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("cache").path)
        XCTAssertEqual(files.filter { $0.hasSuffix(".json") }.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("nested").path))
        XCTAssertFalse(engine.loadAnalysisCache(for: "missing"))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
        XCTAssertFalse(engine.loadAnalysisCache(for: "local"))
        XCTAssertEqual(engine.currentGameId, "local")
    }

    func testChangedPositionInvalidatesCachedTurnAndDescendants() throws {
        try hold(); engine.start(); analyze(x: 0)
        let first = queries(1)[0]
        engine.receiveAnalysisLine(try response(first))
        analyze(x: 1)
        let second = queries(2)[1]
        XCTAssertNil(engine.currentAnalysisData[1])
        engine.receiveAnalysisLine(try response(first))
        XCTAssertNil(engine.currentAnalysisData[1])
        engine.receiveAnalysisLine(try response(second))
        XCTAssertEqual(engine.currentAnalysisData[1]?.id, second["id"] as? String)
    }

    func testInvalidCoordinatesAndWrongGameDoNotBecomePassQueries() {
        engine.start()
        analyze(id: "other"); analyze(x: 9); analyze(x: -1)
        engine.analyzeGame(id: "game-a", initialStones: [("B", -1, -1)], moves: [], size: 9)
        analyze()
        XCTAssertEqual(queries(1).count, 1)
    }

    func testCurrentQueryErrorIsVisibleButStaleErrorIsIgnored() throws {
        try hold(); engine.start(); analyze()
        let query = queries(1)[0]
        engine.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id": "unknown", "error": "old error"]))
        XCTAssertNil(engine.engineStartupError)
        engine.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id": query["id"]!, "error": "bad rules"]))
        XCTAssertEqual(engine.analysisError, "Analysis failed: bad rules")
    }
}
