import XCTest
import Combine
import CryptoKit
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
            if "action" in q:
                print(json.dumps(q), flush=True); continue
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

    private func queries(_ count: Int, includePositionCancellations: Bool = false) -> [[String: Any]] {
        let url = directory.appendingPathComponent("requests.jsonl")
        var result: [[String: Any]] = []
        eventually("\(count) queries written") {
            let text = (try? String(contentsOf: url)) ?? ""
            result = text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            if !includePositionCancellations {
                result = result.filter { !(($0["id"] as? String)?.hasPrefix("cancel-position-") ?? false) }
            }
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
    private func newEngine(imports: [URL] = []) -> KataGoEngine {
        KataGoEngine(executableURL: directory.appendingPathComponent("fake-katago"),
            modelURL: directory.appendingPathComponent("fixture-model"),
            cacheDirectory: directory.appendingPathComponent("cache"), legacyImportDirectories: imports)
    }
    private func savedCache() throws -> URL {
        try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("cache"),
            includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("v4-") })
    }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func testPauseKeepsResultsAndFencesPendingReplies() throws {
        try hold(); engine.start(); analyze(visits: 100)
        engine.receiveAnalysisLine(try response(queries(1)[0], visits: 100))
        analyze(x: 1)
        let late = queries(2)[1]
        engine.pauseAnalysis()
        XCTAssertEqual(engine.currentAnalysisData[0]?.rootInfo?.visits, 100)
        XCTAssertFalse(engine.hasPendingAnalysis)
        engine.receiveAnalysisLine(try response(late))
        XCTAssertNil(engine.currentAnalysisData[1])
        analyze(visits: 50); analyze(x: 2)
        XCTAssertEqual(queries(3).count, 3, "Completed analysis is not requested again")
    }

    func testStopFlushesLatestResultAndFreshProcessLoadsWithoutStartingEngine() throws {
        try hold(); engine.start(); analyze(visits: 250)
        engine.receiveAnalysisLine(try response(queries(1)[0], visits: 250))
        // Quit before the five-second periodic save has fired.
        engine.stop()
        let fresh = newEngine()
        XCTAssertTrue(fresh.loadAnalysisCache(for: "game-a"))
        XCTAssertEqual(fresh.currentAnalysisData[0]?.rootInfo?.visits, 250)
        XCTAssertFalse(fresh.isEngineRunning)
        fresh.stop()
    }

    func testContinuousResultsDoNotPostponePeriodicSave() throws {
        try hold(); engine.start()
        for index in 0..<4 {
            analyze(visits: (index + 1) * 50)
            engine.receiveAnalysisLine(try response(queries(index + 1)[index], visits: (index + 1) * 50))
            scheduler.advance(by: 1)
        }
        scheduler.advance(by: 1)
        eventually("Periodic cache saved during continuous analysis") {
            ((try? FileManager.default.contentsOfDirectory(atPath: self.directory.appendingPathComponent("cache").path)) ?? [])
                .contains { $0.hasPrefix("v4-") }
        }
        let data = try Data(contentsOf: savedCache())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let analyses = try XCTUnwrap(json["analyses"] as? [String: Any])
        XCTAssertNotNil(analyses["0"])
    }

    func testModelReplacementAtSamePathCannotReuseOldAnalysis() throws {
        try hold(); engine.start(); analyze()
        engine.receiveAnalysisLine(try response(queries(1)[0])); engine.stop()
        try Data("different model".utf8).write(to: directory.appendingPathComponent("fixture-model"))
        let fresh = newEngine()
        XCTAssertFalse(fresh.loadAnalysisCache(for: "game-a"))
        XCTAssertTrue(fresh.currentAnalysisData.isEmpty)
        fresh.stop()
    }

    func testApprovedLegacyImportMergesDeeperResultsAndRejectsTampering() throws {
        try hold(); engine.start(); analyze(visits: 250)
        engine.receiveAnalysisLine(try response(queries(1)[0], visits: 250)); engine.flushAnalysisCache()
        let cache = try savedCache()
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any])
        let identity = try XCTUnwrap(legacy.removeValue(forKey: "engineIdentity") as? String)
        let bytes = try JSONSerialization.data(withJSONObject: legacy)
        let folder = directory.appendingPathComponent("review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "v3-" + hash(Data("game-a".utf8)) + ".json"
        try bytes.write(to: folder.appendingPathComponent(name))
        let manifest: [String: Any] = ["engineIdentity":identity, "files":[name:hash(bytes)]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        engine.stop(); try FileManager.default.removeItem(at: cache)
        let imported = newEngine(imports: [folder])
        XCTAssertTrue(imported.loadAnalysisCache(for: "game-a"))
        XCTAssertEqual(imported.currentAnalysisData[0]?.rootInfo?.visits, 250)
        imported.flushAnalysisCache()
        // A shallow partial save cannot replace the deeper compatible on-disk result.
        imported.currentAnalysisData[0] = AIAnalysis(id: "shallow", isDuringSearch: false, turnNumber: 0,
            moveInfos: nil, rootInfo: AIRootInfo(winrate: 0.6, scoreLead: 1, visits: 25))
        imported.stop()
        let fresh = newEngine()
        XCTAssertTrue(fresh.loadAnalysisCache(for: "game-a"))
        XCTAssertEqual(fresh.currentAnalysisData[0]?.rootInfo?.visits, 250)
        fresh.stop(); try FileManager.default.removeItem(at: cache)
        try (bytes + Data(" ".utf8)).write(to: folder.appendingPathComponent(name))
        let tampered = newEngine(imports: [folder])
        XCTAssertFalse(tampered.loadAnalysisCache(for: "game-a"))
        tampered.stop()
        try bytes.write(to: folder.appendingPathComponent(name))
        try Data("another model".utf8).write(to: directory.appendingPathComponent("fixture-model"))
        let incompatible = newEngine(imports: [folder])
        XCTAssertFalse(incompatible.loadAnalysisCache(for: "game-a"))
        incompatible.stop()
    }

    private func hoverGame(_ sgf: String = "(;SZ[9]RU[Japanese]KM[6.5];B[aa];W[bb])", turn: Int = 0) throws -> SGFPlayer {
        let game = SGFPlayer()
        game.load(game: SGFGame.from(tree: try SGFParser.parse(text: sgf)))
        game.seek(to: turn)
        return game
    }
    private func hoverResponse(_ query: [String: Any], pv: [String] = ["C7", "D6", "E5"], turn: Int? = nil) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: response(query, visits: 100, turn: turn)) as? [String: Any])
        json["moveInfos"] = [["move":pv[0], "visits":100, "winrate":0.4, "scoreLead":-2.5, "pv":pv]]
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testHoverForcesOnlyRootMoveAndPreservesWholePositionAnalysis() throws {
        try hold(); engine.start()
        let game = try hoverGame(turn: 1)
        let payload = game.getCurrentAIPayload()
        engine.analyzeGame(id: "game-a", initialStones: payload.initial, moves: payload.moves,
            size: 9, settings: game.analysisSettings)
        let ordinary = queries(1)[0]
        engine.receiveAnalysisLine(try response(ordinary))
        let original = game.board
        var received: AIMoveInfo?
        engine.analyzeHover(game: game, point: BoardPosition(2,2)) { received = try? $0.get() }
        let query = queries(2)[1]
        let allowed = try XCTUnwrap((query["allowMoves"] as? [[String: Any]])?.first)
        XCTAssertEqual(allowed["moves"] as? [String], ["C7"])
        XCTAssertEqual(allowed["player"] as? String, "W")
        XCTAssertEqual(allowed["untilDepth"] as? Int, 1)
        XCTAssertEqual(query["priority"] as? Int, 100)
        XCTAssertEqual(query["moves"] as? [[String]], [["B","A9"]])
        XCTAssertEqual(query["rules"] as? String, "japanese")
        XCTAssertEqual(query["komi"] as? Double, 6.5)
        XCTAssertTrue(engine.hasPendingAnalysis)
        engine.receiveAnalysisLine(try hoverResponse(query, turn: 0))
        XCTAssertNil(received, "A different turn cannot finish the hover")
        engine.receiveAnalysisLine(try hoverResponse(query))
        XCTAssertEqual(received?.pv, ["C7","D6","E5"])
        XCTAssertEqual(engine.currentAnalysisData[1]?.id, ordinary["id"] as? String)
        XCTAssertEqual(engine.currentAnalysisData[1]?.rootInfo?.scoreLead, 2.5)
        XCTAssertEqual(game.board, original); XCTAssertEqual(game.currentIndex, 1); XCTAssertEqual(game.maxIndex, 2)
        XCTAssertFalse(engine.hasPendingAnalysis)
    }

    func testHoverOnlyCacheSurvivesQuitAndReloadAndDoesNotSendAnotherQuery() throws {
        try hold(); engine.start()
        let game = try hoverGame()
        engine.analyzeHover(game: game, point: BoardPosition(2,2)) { _ in }
        engine.receiveAnalysisLine(try hoverResponse(queries(1)[0]))
        XCTAssertTrue(engine.currentAnalysisData.isEmpty, "Forced search must not become whole-game analysis")
        engine.stop()
        let fresh = newEngine()
        XCTAssertTrue(fresh.loadAnalysisCache(for: "game-a", game: game))
        XCTAssertEqual(fresh.cachedHoverAnalysis(game: game, point: BoardPosition(2,2))?.pv?.count, 3)
        var reused = false
        fresh.analyzeHover(game: game, point: BoardPosition(2,2)) { reused = (try? $0.get()) != nil }
        XCTAssertTrue(reused, "Cached continuation is usable even before engine startup")
        fresh.start()
        let payload = game.getCurrentAIPayload()
        fresh.analyzeGame(id: "game-a", initialStones: payload.initial, moves: payload.moves, size: 9, settings: game.analysisSettings)
        _ = queries(2)
        XCTAssertNotNil(fresh.cachedHoverAnalysis(game: game, point: BoardPosition(2,2)), "Starting background analysis must retain hover-only cache")
        fresh.stop()
        let changedKomi = try hoverGame("(;SZ[9]RU[Japanese]KM[0.5])")
        XCTAssertNil(fresh.cachedHoverAnalysis(game: changedKomi, point: BoardPosition(2,2)))
        let reload = newEngine()
        XCTAssertTrue(reload.loadAnalysisCache(for: "game-a", game: game))
        XCTAssertNil(reload.cachedHoverAnalysis(game: changedKomi, point: BoardPosition(2,2)))
        game.seek(to: 1)
        XCTAssertNil(reload.cachedHoverAnalysis(game: game, point: BoardPosition(2,2)))
        reload.stop()
        try Data("different-model".utf8).write(to: directory.appendingPathComponent("fixture-model"))
        let changedModel = newEngine()
        XCTAssertFalse(changedModel.loadAnalysisCache(for: "game-a", game: game))
        XCTAssertNil(changedModel.cachedHoverAnalysis(game: game, point: BoardPosition(2,2)))
        changedModel.stop()
    }

    func testHoverCancellationSendsTerminateAndIgnoresLateReplies() throws {
        try hold(); engine.start()
        let game = try hoverGame()
        var firstFinished = false
        engine.analyzeHover(game: game, point: BoardPosition(2,2)) { result in
            if case .success = result { XCTFail("Cancelled hover delivered a result") }
            firstFinished = true
        }
        let first = queries(1)[0]
        engine.cancelHoverAnalysis()
        XCTAssertTrue(firstFinished)
        let cancellation = queries(2)[1]
        XCTAssertEqual(cancellation["action"] as? String, "terminate")
        XCTAssertEqual(cancellation["terminateId"] as? String, first["id"] as? String)
        engine.receiveAnalysisLine(try hoverResponse(first))
        XCTAssertNil(engine.cachedHoverAnalysis(game: game, point: BoardPosition(2,2)))
        engine.analyzeHover(game: game, point: BoardPosition(2,2)) { _ in }
        let second = queries(3)[2]
        engine.currentGameId = "different-game"
        engine.receiveAnalysisLine(try hoverResponse(second))
        XCTAssertNil(engine.cachedHoverAnalysis(game: game, point: BoardPosition(2,2)))
    }

    func testHoverErrorsTimeoutAndMalformedResultsCanBeRetried() throws {
        try hold(); engine.start()
        let game = try hoverGame()
        var message: String?
        func request() {
            engine.analyzeHover(game: game, point: BoardPosition(2,2)) {
                if case .failure(let error) = $0 { message = error.message }
            }
        }
        request()
        let first = queries(1)[0]
        engine.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id":first["id"]!,"error":"fixture error"]))
        XCTAssertTrue(message?.contains("fixture error") == true)
        XCTAssertFalse(engine.hasPendingAnalysis)
        request()
        let second = queries(3)[2] // error cancellation then new query
        engine.receiveAnalysisLine(try hoverResponse(second, pv: ["C7"]))
        XCTAssertTrue(message?.contains("No continuation") == true)
        request()
        _ = queries(5)
        scheduler.advance(by: 31)
        XCTAssertTrue(message?.contains("timed out") == true)
        XCTAssertNil(engine.cachedHoverAnalysis(game: game, point: BoardPosition(2,2)))
        XCTAssertFalse(engine.hasPendingAnalysis)
    }

    func testHoverRejectsOccupiedKoAndOffBoardMovesBeforeRequesting() throws {
        engine.start()
        let game = try hoverGame("(;SZ[5]RU[Japanese]AB[ba][ab][bc]AW[bb][ca][db][cc];B[cb])", turn: 1)
        for point in [BoardPosition(1,1), BoardPosition(1,2), BoardPosition(-1,-1), BoardPosition(5,5)] {
            var rejected = false
            engine.analyzeHover(game: game, point: point) { if case .failure = $0 { rejected = true } }
            XCTAssertTrue(rejected)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("requests.jsonl").path))
    }

    func testBackgroundSearchBoundsTimeAndPreservesDeeperResults() throws {
        try hold(); engine.start()
        engine.analyzeGame(id: "game-a", initialStones: [], moves: [], size: 9,
            maxVisits: 3200, backgroundTimeLimit: 2)
        let first = queries(1)[0]
        XCTAssertEqual(first["priority"] as? Int, -100)
        XCTAssertEqual((first["overrideSettings"] as? [String: Double])?["maxTime"], 2)
        engine.receiveAnalysisLine(try response(first, visits: 1200))
        engine.analyzeGame(id: "game-a", initialStones: [], moves: [], size: 9,
            maxVisits: 12800, backgroundTimeLimit: 4)
        let second = queries(2)[1]
        engine.receiveAnalysisLine(try response(second, visits: 800))
        XCTAssertEqual(engine.currentAnalysisData[0]?.rootInfo?.visits, 1200)
        XCTAssertFalse(engine.hasPendingAnalysis)
        engine.analyzeGame(id: "game-a", initialStones: [], moves: [], size: 9, maxVisits: 12800)
        let third = queries(3)[2]
        engine.receiveAnalysisLine(try JSONSerialization.data(withJSONObject: ["id": third["id"]!, "error": "fixture failure"]))
        XCTAssertEqual(engine.currentAnalysisData[0]?.rootInfo?.visits, 1200, "Failed upgrade retains completed analysis")
    }

    func testPauseTerminatesActualPositionSearchAndKeepsCompletedWork() throws {
        try hold(); engine.start(); analyze()
        let first = queries(1)[0]
        engine.receiveAnalysisLine(try response(first))
        analyze(x: 2)
        let pending = queries(2)[1]
        engine.pauseAnalysis()
        let messages = queries(3, includePositionCancellations: true)
        XCTAssertTrue(messages.contains { $0["action"] as? String == "terminate" && $0["terminateId"] as? String == pending["id"] as? String })
        engine.receiveAnalysisLine(try response(pending))
        XCTAssertNil(engine.currentAnalysisData[1])
        XCTAssertNotNil(engine.currentAnalysisData[0])
    }

    func testAdaptiveAnalysisCoversAllMovesDeepensAndHandlesUndo() throws {
        try hold(); engine.start()
        let game = try hoverGame("(;SZ[9]RU[Japanese]KM[6.5];B[aa];W[bb];B[cc])")
        let worker = BackgroundGameAnalysis(engine: engine)
        worker.tick(player: game, resources: AnalysisResources(), pauseOnBattery: true, now: 0)
        for n in 0..<12 {
            let time = Double(n * 4 + 1)
            worker.tick(player: game, resources: AnalysisResources(), pauseOnBattery: true, now: time)
            let query = queries(n + 1)[n]
            XCTAssertEqual((query["moves"] as? [[String]])?.count, n % 4)
            let depth = try XCTUnwrap(query["maxVisits"] as? Int)
            engine.receiveAnalysisLine(try response(query, visits: depth))
            worker.tick(player: game, resources: AnalysisResources(), pauseOnBattery: true, now: time + 0.5)
            XCTAssertFalse(engine.hasPendingAnalysis, "Rest after completing each bounded search")
        }
        XCTAssertEqual(engine.currentAnalysisData.count, 4)
        XCTAssertTrue(engine.currentAnalysisData.values.allSatisfy { ($0.rootInfo?.visits ?? 0) >= 800 }, "Deepens beyond the old 500-visit ceiling")
        XCTAssertEqual(game.currentIndex, 0, "Background analysis never navigates the user's board")
        let shorter = try hoverGame("(;SZ[9]RU[Japanese]KM[6.5];B[aa];W[dd])")
        worker.tick(player: shorter, resources: AnalysisResources(onBattery: true), pauseOnBattery: true, now: 50)
        XCTAssertNotNil(engine.currentAnalysisData[1])
        XCTAssertNil(engine.currentAnalysisData[2]); XCTAssertNil(engine.currentAnalysisData[3])
        worker.stop()
    }

    func testBatteryThermalLoadAndInterfacePressurePauseAndResume() throws {
        try hold(); engine.start()
        let game = try hoverGame()
        let worker = BackgroundGameAnalysis(engine: engine)
        worker.tick(player: game, resources: AnalysisResources(), pauseOnBattery: true, now: 0)
        worker.tick(player: game, resources: AnalysisResources(), pauseOnBattery: true, now: 1)
        let pending = queries(1)[0]
        worker.tick(player: game, resources: AnalysisResources(onBattery: true), pauseOnBattery: true, now: 1.5)
        XCTAssertFalse(engine.hasPendingAnalysis)
        XCTAssertEqual(worker.status, "Paused to save battery")
        XCTAssertEqual(queries(2, includePositionCancellations: true).last?["terminateId"] as? String, pending["id"] as? String)
        engine.receiveAnalysisLine(try response(pending)); XCTAssertTrue(engine.currentAnalysisData.isEmpty)
        worker.tick(player: game, resources: AnalysisResources(onBattery: true), pauseOnBattery: false, now: 5)
        XCTAssertTrue(engine.hasPendingAnalysis, "User can opt into analysis on battery")
        for reading in [AnalysisResources(lowPower: true), AnalysisResources(thermal: .fair),
                        AnalysisResources(thermal: .serious), AnalysisResources(cpuBusy: 0.9), AnalysisResources(memoryPressure: true)] {
            worker.tick(player: game, resources: reading, pauseOnBattery: false, now: 6)
            XCTAssertFalse(engine.hasPendingAnalysis)
            XCTAssertTrue(worker.status.hasPrefix("Paused"))
        }
        worker.tick(player: game, resources: AnalysisResources(), pauseOnBattery: false, now: 10, interfaceDelayed: true)
        XCTAssertFalse(engine.hasPendingAnalysis)
        worker.tick(player: game, resources: AnalysisResources(), pauseOnBattery: false, now: 14)
        XCTAssertTrue(engine.hasPendingAnalysis)
        worker.stop(); XCTAssertFalse(engine.hasPendingAnalysis)
    }

    func testBatterySavingDoesNotEvenLaunchEngine() throws {
        let game = try hoverGame()
        let worker = BackgroundGameAnalysis(engine: engine)
        worker.tick(player: game, resources: AnalysisResources(onBattery: true), pauseOnBattery: true, now: 0)
        XCTAssertFalse(engine.isEngineRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("requests.jsonl").path))
        worker.stop()
    }

    func testConfirmedLocalScoringSettingsInvalidateIncompatibleReviewCache() throws {
        try hold(); engine.start()
        let game = try hoverGame("(;SZ[9]RU[Chinese]KM[6.5];B[aa])")
        let payload = game.getCurrentAIPayload()
        engine.analyzeGame(id: "game-a", initialStones: payload.initial, moves: payload.moves,
            size: 9, settings: game.analysisSettings)
        engine.receiveAnalysisLine(try response(queries(1)[0]))
        engine.flushAnalysisCache()
        game.confirmAnalysisSettings(rules: "Chinese", komi: "6.5")
        XCTAssertTrue(engine.loadAnalysisCache(for: "game-a", game: game), "Unchanged rules retain analysis")
        game.confirmAnalysisSettings(rules: "Japanese", komi: "0.5")
        XCTAssertFalse(engine.loadAnalysisCache(for: "game-a", game: game), "Confirmed rules/komi must not reveal incompatible analysis")
        XCTAssertTrue(engine.currentAnalysisData.isEmpty)
    }

}
