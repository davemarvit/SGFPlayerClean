import Foundation
import Combine
import CryptoKit

/// State and published values are owned by the main queue. Pipe and cache I/O are serialized separately.
class KataGoEngine: ObservableObject {
    static let shared = KataGoEngine()
    @Published private(set) var isEngineRunning = false
    @Published var currentAnalysisData: [Int: AIAnalysis] = [:]
    @Published private(set) var engineStartupError: String?
    @Published private(set) var analysisNotice: String?
    @Published private(set) var analysisError: String?
    @Published private(set) var analysisWarning: String?
    var hasPendingAnalysis: Bool { !requests.isEmpty || hoverRequest != nil }
    private var failedPositions = Set<String>()
    private var requestTimeouts: [Int: OGSCancellable] = [:]
    private var contextFingerprint: String?
    struct HoverFailure: Error { let message: String }
    private struct HoverRequest {
        let id: String
        let key: String
        let turn: Int
        let move: String
        let completion: (Result<AIMoveInfo, HoverFailure>) -> Void
    }
    private var hoverRequest: HoverRequest?
    private var hoverTimeout: OGSCancellable?
    private var hoverContinuations: [String: AIMoveInfo] = [:]


    var currentGameId = "local" {
        didSet { if currentGameId != oldValue { invalidateAnalysis() } }
    }
    private var process: Process?
    private var input: FileHandle?
    private var readers: [KataGoLineReader] = []
    private var processGeneration = 0
    private var restartTask: OGSCancellable?
    private var cacheSaveTask: OGSCancellable?
    private var lastStderr = "Unknown engine error."
    private var requests: [Int: String] = [:]
    private var pendingVisits: [Int: Int] = [:]
    private var fingerprints: [Int: String] = [:]
    private let writeQueue = DispatchQueue(label: "SGFPlayer.KataGo.input")
    private let cacheQueue = DispatchQueue(label: "SGFPlayer.KataGo.cache", qos: .utility)
    private let scheduler: OGSConnectionScheduler
    private let executableOverride: URL?
    private let modelOverride: URL?
    private let cacheDirectory: URL
    private let legacyImportDirectories: [URL]
    private var analysisEngineIdentity: String?
    private var runningEngineIdentity: String?
    private var assetSignature: String?
    private var assetIdentity: String?

    init(executableURL: URL? = nil, modelURL: URL? = nil, cacheDirectory: URL? = nil,
         scheduler: OGSConnectionScheduler = OGSMainQueueScheduler(), legacyImportDirectories: [URL]? = nil) {
        executableOverride = executableURL
        modelOverride = modelURL
        self.scheduler = scheduler
        #if SGF_OGS_REVIEW
        let cacheFolder = "com.davemarvit.SGFPlayerClean.ogs-review/AICache"
        #elseif SGF_OFFLINE_REVIEW
        let cacheFolder = "com.davemarvit.SGFPlayerClean.offline-review/AICache"
        #else
        let cacheFolder = "SGFPlayerClean/AICache"
        #endif
        let resolvedCacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFolder)
        self.cacheDirectory = resolvedCacheDirectory
        self.legacyImportDirectories = legacyImportDirectories ?? (cacheDirectory == nil ?
            ["main", "ogs-review", "offline-review"].map {
                resolvedCacheDirectory.appendingPathComponent("ReviewImports/\($0)")
            } : [])
    }

    private var executableURL: URL {
        executableOverride ?? URL(fileURLWithPath: UserDefaults.standard.string(forKey: "customKataGoPath") ?? "/opt/homebrew/bin/katago")
    }
    private var modelURL: URL {
        if let modelOverride { return modelOverride }
        if let path = UserDefaults.standard.string(forKey: "customAIModelPath"), FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.url(forResource: "kata1-b18", withExtension: "bin.gz") ?? URL(fileURLWithPath: "/tmp/default_model.bin.gz")
    }
    /// Hash contents once per asset change, including replacements at the same path.
    /// Captured at process launch so an on-disk replacement cannot relabel old results.
    private func configuredEngineIdentity() -> String? {
        let urls = [executableURL, modelURL, Bundle.main.url(forResource: "analysis", withExtension: "cfg")]
        var signature = ""
        for url in urls {
            guard let url else { signature += "none;"; continue }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path) else { return nil }
            signature += "\(url.resolvingSymlinksInPath().path):\(attributes[.size] ?? 0):\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0): \(attributes[.systemFileNumber] ?? 0);"
        }
        if signature == assetSignature { return assetIdentity }
        var hashes: [String] = []
        for url in urls {
            if let url {
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
                hashes.append(digest(data))
            } else { hashes.append(digest(Data())) }
        }
        let identity = digest(Data(("katago-cache-v4\n" + hashes.joined(separator: "\n")).utf8))
        assetSignature = signature; assetIdentity = identity
        return identity
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        restartTask?.cancel(); restartTask = nil
        guard process == nil else { return }
        engineStartupError = nil
        let fm = FileManager.default
        let executable = executableURL
        guard fm.isExecutableFile(atPath: executable.path) else {
            engineStartupError = "KataGo executable not found or not executable."; return
        }
        let model = modelURL.path
        guard fm.fileExists(atPath: model) else { engineStartupError = "Neural network model not found."; return }
        guard let identity = configuredEngineIdentity() else { engineStartupError = "Could not identify the analysis engine and model."; return }
        if analysisEngineIdentity != nil && analysisEngineIdentity != identity { flushAnalysisCache(); invalidateAnalysis() }
        runningEngineIdentity = identity
        analysisEngineIdentity = identity
        let p = Process()
        p.executableURL = executable
        // Tests supply a temporary cache root; no application cache or working model is touched.
        let work = cacheDirectory.appendingPathComponent("KataGoWork", isDirectory: true)
        do { try fm.createDirectory(at: work, withIntermediateDirectories: true) }
        catch { engineStartupError = error.localizedDescription; return }
        p.currentDirectoryURL = work
        p.arguments = ["analysis", "-model", model]
        if let config = Bundle.main.path(forResource: "analysis", ofType: "cfg") {
            p.arguments! += ["-config", config]
        }
        #if SGF_OFFLINE_REVIEW || SGF_OGS_REVIEW
        // KataGo also writes tuning data outside our analysis cache by default.
        p.arguments! += ["-override-config", "homeDataDir=\(work.appendingPathComponent("EngineData").path)"]
        #endif
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        processGeneration += 1
        let generation = processGeneration
        lastStderr = "Unknown engine error."
        p.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            DispatchQueue.main.async {
                guard let self, self.processGeneration == generation else { return }
                self.releaseProcess()
                self.engineStartupError = "KataGo exited (\(status)): \(self.lastStderr)"
            }
        }
        do {
            try p.run()
            process = p
            input = stdin.fileHandleForWriting
            // The child has its own descriptors. Close the parent's unused pipe ends.
            try? stdin.fileHandleForReading.close()
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            readers = [KataGoLineReader(stdout.fileHandleForReading) { [weak self] line in
                DispatchQueue.main.async {
                    guard let self, self.processGeneration == generation else { return }
                    self.receiveAnalysisLine(line)
                }
            }, KataGoLineReader(stderr.fileHandleForReading) { [weak self] line in
                DispatchQueue.main.async {
                    guard let self, self.processGeneration == generation else { return }
                    self.lastStderr = String(decoding: line, as: UTF8.self)
                }
            }]
            isEngineRunning = true
        } catch {
            p.terminationHandler = nil
            for pipe in [stdin, stdout, stderr] {
                try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close()
            }
            engineStartupError = "Failed to launch process: \(error.localizedDescription)"
        }
    }

    private func releaseProcess() {
        cancelHoverAnalysis(message: "AI engine stopped. Move away and try again.")
        processGeneration += 1
        requestTimeouts.values.forEach { $0.cancel() }; requestTimeouts.removeAll()
        requests.removeAll()
        pendingVisits.removeAll()
        readers.removeAll() // Each reader cancels and closes only its own descriptor.
        let oldInput = input
        input = nil
        writeQueue.async { try? oldInput?.close() }
        process = nil
        runningEngineIdentity = nil
        isEngineRunning = false
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        restartTask?.cancel(); restartTask = nil
        flushAnalysisCache()
        let oldProcess = process
        releaseProcess() // Fence callbacks before terminating, even if start() follows immediately.
        if oldProcess?.isRunning == true { oldProcess?.terminate() }
        invalidateAnalysis()
    }

    func restart() {
        stop()
        let generation = processGeneration
        restartTask = scheduler.schedule(after: 1) { [weak self] in
            guard let self, self.processGeneration == generation else { return }
            self.start()
        }
    }

    func invalidateAnalysis() {
        cancelHoverAnalysis()
        hoverContinuations.removeAll()
        analysisWarning = nil
        analysisError = nil
        failedPositions.removeAll()
        cacheSaveTask?.cancel(); cacheSaveTask = nil
        requestTimeouts.values.forEach { $0.cancel() }; requestTimeouts.removeAll()
        requests.removeAll()
        pendingVisits.removeAll()
        fingerprints.removeAll()
        contextFingerprint = nil
        currentAnalysisData.removeAll()
        analysisEngineIdentity = nil
    }

    /// Fence late replies when AI is hidden without discarding completed work.
    func pauseAnalysis() {
        cancelHoverAnalysis()
        saveAnalysisCache(for: currentGameId)
        requestTimeouts.values.forEach { $0.cancel() }; requestTimeouts.removeAll()
        requests.removeAll(); pendingVisits.removeAll()
    }

    /// Synchronous barrier used on normal quit and engine replacement: atomic writes
    /// must finish before macOS terminates the process.
    func flushAnalysisCache() {
        dispatchPrecondition(condition: .onQueue(.main))
        cacheSaveTask?.cancel(); cacheSaveTask = nil
        saveAnalysisCache(for: currentGameId)
        cacheQueue.sync {}
    }

    private struct Cache: Codable {
        let analyses: [Int: AIAnalysis]
        let fingerprints: [Int: String]
        let contextFingerprint: String?
        let warning: String?
        var engineIdentity: String?

        func merging(_ older: Cache) -> Cache {
            guard engineIdentity == older.engineIdentity, contextFingerprint == older.contextFingerprint else { return self }
            var analyses = older.analyses
            var fingerprints = older.fingerprints
            for (turn, analysis) in self.analyses {
                if fingerprints[turn] == self.fingerprints[turn],
                   (analyses[turn]?.rootInfo?.visits ?? 0) > (analysis.rootInfo?.visits ?? 0) { continue }
                analyses[turn] = analysis; fingerprints[turn] = self.fingerprints[turn]
            }
            return Cache(analyses: analyses, fingerprints: fingerprints, contextFingerprint: contextFingerprint,
                           warning: warning, engineIdentity: engineIdentity)
        }
    }

    private func cacheURL(for gameID: String, identity: String) -> URL {
        // Fixed-length names avoid slashes, path traversal, and very long local SGF paths.
        cacheDirectory.appendingPathComponent("v4-\(digest(Data(gameID.utf8)))-\(identity).json")
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func saveAnalysisCache(for gameID: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        saveHoverCache(for: gameID)
        guard gameID == currentGameId, gameID != "local", !currentAnalysisData.isEmpty,
              let identity = analysisEngineIdentity else { return }
        let snapshot = Cache(analyses: currentAnalysisData, fingerprints: fingerprints, contextFingerprint: contextFingerprint,
                             warning: analysisWarning, engineIdentity: identity)
        let url = cacheURL(for: gameID, identity: identity)
        cacheQueue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let older = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
                try JSONEncoder().encode(older.map { snapshot.merging($0) } ?? snapshot).write(to: url, options: .atomic)
            } catch { NSLog("[AI] Cache write failed: \(error.localizedDescription)") }
        }
    }

    @discardableResult
    func loadAnalysisCache(for gameID: String, game: SGFPlayer? = nil) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        saveAnalysisCache(for: currentGameId)
        currentGameId = gameID
        invalidateAnalysis()
        analysisNotice = game?.analysisSettings.notice
        guard gameID != "local", let identity = runningEngineIdentity ?? configuredEngineIdentity() else { return false }
        analysisEngineIdentity = identity
        let hoverURL = hoverCacheURL(for: gameID, identity: identity)
        hoverContinuations = cacheQueue.sync {
            (try? Data(contentsOf: hoverURL)).flatMap { try? JSONDecoder().decode([String: AIMoveInfo].self, from: $0) } ?? [:]
        }
        let url = cacheURL(for: gameID, identity: identity)
        let legacyName = "v3-\(digest(Data(gameID.utf8))).json"
        struct LegacyManifest: Decodable { let engineIdentity: String; let files: [String: String] }
        // Ordered after pending writes; apply synchronously so a deferred old load cannot replace a new game.
        guard let loaded = cacheQueue.sync(execute: { () -> Cache? in
            var candidates: [Cache] = []
            if let data = try? Data(contentsOf: url), let cache = try? JSONDecoder().decode(Cache.self, from: data),
               cache.engineIdentity == identity { candidates.append(cache) }
            // Legacy v3 files lack engine identity. Only import copies whose exact
            // bytes and engine/model/config were checked during the migration.
            for folder in legacyImportDirectories {
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                      let manifest = try? JSONDecoder().decode(LegacyManifest.self, from: data), manifest.engineIdentity == identity,
                      let bytes = try? Data(contentsOf: folder.appendingPathComponent(legacyName)),
                      manifest.files[legacyName] == self.digest(bytes),
                      var cache = try? JSONDecoder().decode(Cache.self, from: bytes) else { continue }
                cache.engineIdentity = identity
                candidates.append(cache)
            }
            // Validate before merging so an unrelated position/rules cannot displace
            // a matching result merely because it has more visits.
            if let game {
                candidates = candidates.map { candidate in
                    let valid = candidate.analyses.filter { turn, _ in
                        guard (0...game.maxIndex).contains(turn) else { return false }
                        let payload = game.getAIPayload(at: turn)
                        guard let query = self.positionQuery(initialStones: payload.initial, moves: payload.moves,
                            size: game.board.size, settings: game.analysisSettings),
                            let bytes = try? JSONSerialization.data(withJSONObject: query, options: .sortedKeys) else { return false }
                        return candidate.fingerprints[turn] == self.digest(bytes)
                    }
                    return Cache(analyses: valid, fingerprints: candidate.fingerprints.filter { valid[$0.key] != nil },
                                 contextFingerprint: candidate.contextFingerprint, warning: candidate.warning, engineIdentity: identity)
                }.filter { !$0.analyses.isEmpty }
            }
            return candidates.reduce(nil) { result, cache in result.map { cache.merging($0) } ?? cache }
        }) else { return !hoverContinuations.isEmpty }
        let valid = loaded.analyses
        currentAnalysisData = valid
        fingerprints = loaded.fingerprints.filter { valid[$0.key] != nil }
        contextFingerprint = valid.isEmpty ? nil : loaded.contextFingerprint
        analysisWarning = valid.isEmpty ? nil : loaded.warning
        analysisEngineIdentity = identity
        if !valid.isEmpty { saveAnalysisCache(for: gameID) }
        return !valid.isEmpty
    }

    private func scheduleCacheSave() {
        guard cacheSaveTask == nil else { return }
        cacheSaveTask = scheduler.schedule(after: 5) { [weak self] in
            guard let self else { return }
            self.cacheSaveTask = nil
            self.saveAnalysisCache(for: self.currentGameId)
        }
    }

    private func positionQuery(initialStones: [(color: String, x: Int, y: Int)],
                               moves: [(color: String, x: Int, y: Int)], size: Int,
                               settings: GameAnalysisSettings) -> [String: Any]? {
        let komi = settings.effectiveKomi
        guard settings.analysisRulesSupported, let rules = settings.kataRules, komi.isFinite, (-400...400).contains(komi),
              (komi * 2).rounded() == komi * 2, (2...19).contains(size) else { return nil }
        func coordinates(_ value: (color: String, x: Int, y: Int), allowPass: Bool) -> [String]? {
            guard value.color == "B" || value.color == "W" else { return nil }
            if allowPass && value.x == -1 && value.y == -1 { return [value.color, "pass"] }
            guard (0..<size).contains(value.x), (0..<size).contains(value.y) else { return nil }
            let letters = Array("ABCDEFGHJKLMNOPQRST")
            return [value.color, "\(letters[value.x])\(size - value.y)"]
        }
        let jsonMoves = moves.compactMap { coordinates($0, allowPass: true) }
        let jsonInitial = initialStones.compactMap { coordinates($0, allowPass: false) }
        guard jsonMoves.count == moves.count, jsonInitial.count == initialStones.count else { return nil }
        var query: [String: Any] = ["rules": rules, "komi": komi, "boardXSize": size, "boardYSize": size,
            "initialStones": jsonInitial, "moves": jsonMoves, "includePolicy": false, "includeOwnership": true,
            "analyzeTurns": [moves.count], "initialPlayer": settings.initialPlayer == .black ? "B" : "W"]
        if let bonus = settings.whiteHandicapBonus { query["whiteHandicapBonus"] = bonus }
        return query
    }

    /// One unique ID per request: results can arrive out of order, even at the same turn.
    func analyzeGame(id: String, initialStones: [(color: String, x: Int, y: Int)],
                     moves: [(color: String, x: Int, y: Int)], size: Int = 19,
                     komi: Double = 6.5, maxVisits: Int = 100, settings: GameAnalysisSettings? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        let settings = settings ?? GameAnalysisSettings(rules: "chinese", komi: komi)
        guard id == currentGameId else { return }
        analysisNotice = settings.notice
        let komi = settings.effectiveKomi
        guard settings.analysisRulesSupported, komi.isFinite, (-400...400).contains(komi),
              (komi * 2).rounded() == komi * 2 else { invalidateAnalysis(); return }
        guard isEngineRunning, (2...19).contains(size), maxVisits > 0 else { return }
        guard var query = positionQuery(initialStones: initialStones, moves: moves, size: size, settings: settings) else { return }
        let turn = moves.count
        var context = query
        context.removeValue(forKey: "moves"); context.removeValue(forKey: "analyzeTurns")
        guard let contextData = try? JSONSerialization.data(withJSONObject: context, options: .sortedKeys) else { return }
        let contextKey = digest(contextData)
        if contextFingerprint != contextKey {
            if contextFingerprint != nil { saveAnalysisCache(for: currentGameId); invalidateAnalysis() }
            contextFingerprint = contextKey
        }
        analysisEngineIdentity = runningEngineIdentity
        guard let position = try? JSONSerialization.data(withJSONObject: query, options: .sortedKeys) else { return }
        let fingerprint = digest(position)
        guard !failedPositions.contains(fingerprint) else { return }
        if fingerprints[turn] == fingerprint {
            if (currentAnalysisData[turn]?.rootInfo?.visits ?? 0) >= maxVisits { return }
            if requests[turn] != nil, (pendingVisits[turn] ?? 0) >= maxVisits { return }
        }
        if let previous = fingerprints[turn], previous != fingerprint {
            // Undo/variation at a known turn invalidates that turn and all its descendants.
            currentAnalysisData = currentAnalysisData.filter { $0.key < turn }
            fingerprints = fingerprints.filter { $0.key < turn }
            for key in Array(requestTimeouts.keys) where key >= turn { requestTimeouts.removeValue(forKey: key)?.cancel() }
            requests = requests.filter { $0.key < turn }
            pendingVisits = pendingVisits.filter { $0.key < turn }
        }
        requestTimeouts.removeValue(forKey: turn)?.cancel()
        let requestID = UUID().uuidString
        requests[turn] = requestID
        pendingVisits[turn] = maxVisits
        fingerprints[turn] = fingerprint
        requestTimeouts[turn] = scheduler.schedule(after: 120) { [weak self] in
            guard let self, self.requests[turn] == requestID else { return }
            self.failRequest(turn: turn, message: "Analysis timed out. Retry when the engine is ready.")
        }
        query["id"] = requestID
        query["maxVisits"] = maxVisits
        sendQuery(query)
    }

    private func sendQuery(_ query: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: query), let input else { return }
        data.append(10)
        let generation = processGeneration
        writeQueue.async { [weak self] in
            do { try input.write(contentsOf: data) }
            catch {
                DispatchQueue.main.async {
                    guard let self, self.processGeneration == generation else { return }
                    self.stop()
                    self.engineStartupError = "Could not send analysis: \(error.localizedDescription)"
                }
            }
        }
    }

    // Forced-move results are intentionally separate from whole-position scores:
    // restricting the root search would otherwise distort the graph and quality labels.
    private func hoverCacheURL(for gameID: String, identity: String) -> URL {
        cacheDirectory.appendingPathComponent("hover-v1-\(digest(Data(gameID.utf8)))-\(identity).json")
    }

    private func saveHoverCache(for gameID: String) {
        guard gameID == currentGameId, gameID != "local", !hoverContinuations.isEmpty,
              let identity = analysisEngineIdentity else { return }
        let snapshot = hoverContinuations
        let url = hoverCacheURL(for: gameID, identity: identity)
        cacheQueue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                var merged = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: AIMoveInfo].self, from: $0) } ?? [:]
                for (key, candidate) in snapshot where candidate.visits >= (merged[key]?.visits ?? 0) {
                    merged[key] = candidate
                }
                try JSONEncoder().encode(merged).write(to: url, options: .atomic)
            } catch { NSLog("[AI] Hover cache write failed: \(error.localizedDescription)") }
        }
    }

    private func hoverQuery(game: SGFPlayer, point: BoardPosition) -> (query: [String: Any], key: String, move: String)? {
        guard (0..<game.board.size).contains(point.col), (0..<game.board.size).contains(point.row),
              game.moveRejection(color: game.turn, x: point.col, y: point.row) == nil else { return nil }
        let payload = game.getCurrentAIPayload()
        guard let query = positionQuery(initialStones: payload.initial, moves: payload.moves,
            size: game.board.size, settings: game.analysisSettings),
            let bytes = try? JSONSerialization.data(withJSONObject: query, options: .sortedKeys) else { return nil }
        let move = "\(Array("ABCDEFGHJKLMNOPQRST")[point.col])\(game.board.size - point.row)"
        // The key covers the entire history, rules/komi and requested intersection.
        return (query, digest(bytes) + ":" + move, move)
    }

    func cachedHoverAnalysis(game: SGFPlayer, point: BoardPosition) -> AIMoveInfo? {
        guard let query = hoverQuery(game: game, point: point) else { return nil }
        return hoverContinuations[query.key]
    }

    func analyzeHover(game: SGFPlayer, point: BoardPosition,
                      completion: @escaping (Result<AIMoveInfo, HoverFailure>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancelHoverAnalysis()
        guard let request = hoverQuery(game: game, point: point) else {
            completion(.failure(HoverFailure(message: "AI preview is unavailable for this move or ruleset."))); return
        }
        if let cached = hoverContinuations[request.key] { completion(.success(cached)); return }
        guard isEngineRunning else {
            completion(.failure(HoverFailure(message: "AI engine is unavailable. Move away and try again when it is ready."))); return
        }
        var query = request.query
        var context = query
        context.removeValue(forKey: "moves"); context.removeValue(forKey: "analyzeTurns")
        guard let bytes = try? JSONSerialization.data(withJSONObject: context, options: .sortedKeys) else { return }
        let contextKey = digest(bytes)
        if contextFingerprint != contextKey {
            if contextFingerprint != nil { saveAnalysisCache(for: currentGameId); invalidateAnalysis() }
            contextFingerprint = contextKey
        }
        analysisEngineIdentity = runningEngineIdentity
        let id = UUID().uuidString
        hoverRequest = HoverRequest(id: id, key: request.key, turn: game.currentIndex, move: request.move, completion: completion)
        query["id"] = id
        query["maxVisits"] = 100
        query["priority"] = 100
        query["analysisPVLen"] = 12
        query["includeOwnership"] = false
        query["allowMoves"] = [["player": game.turn == .black ? "B" : "W", "moves": [request.move], "untilDepth": 1]]
        hoverTimeout = scheduler.schedule(after: 30) { [weak self] in
            guard self?.hoverRequest?.id == id else { return }
            self?.cancelHoverAnalysis(message: "AI preview timed out. Move away and try again.")
        }
        sendQuery(query)
    }

    /// Stop obsolete GPU work as well as fencing its asynchronous response.
    func cancelHoverAnalysis(message: String = "AI preview cancelled.") {
        hoverTimeout?.cancel(); hoverTimeout = nil
        guard let request = hoverRequest else { return }
        hoverRequest = nil
        if isEngineRunning { sendQuery(["id": UUID().uuidString, "action": "terminate", "terminateId": request.id]) }
        request.completion(.failure(HoverFailure(message: message)))
    }

    private func receiveHoverLine(_ data: Data) -> Bool {
        guard let request = hoverRequest,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["id"] as? String == request.id else { return false }
        if let warning = json["warning"] as? String { analysisWarning = "KataGo: " + warning; return true }
        if let message = json["error"] as? String {
            cancelHoverAnalysis(message: "AI preview failed: " + message); return true
        }
        // Wrong-turn and partial replies cannot finish the pending request.
        guard let analysis = try? JSONDecoder().decode(AIAnalysis.self, from: data),
              analysis.turnNumber == request.turn, analysis.isDuringSearch != true else { return true }
        guard let candidate = analysis.moveInfos?.first(where: { $0.move == request.move }),
              candidate.visits > 0, candidate.winrate.isFinite, (0...1).contains(candidate.winrate), candidate.scoreLead.isFinite,
              let pv = candidate.pv, pv.count > 1, pv.first == request.move else {
            cancelHoverAnalysis(message: "No continuation was returned for this move. Move away to retry."); return true
        }
        hoverTimeout?.cancel(); hoverTimeout = nil
        hoverRequest = nil
        hoverContinuations[request.key] = candidate
        // Save completed hover work immediately; the quit barrier also drains it.
        saveHoverCache(for: currentGameId)
        request.completion(.success(candidate))
        return true
    }

    // Internal for offline protocol fixtures; production calls arrive from the fenced stdout reader.
    func receiveAnalysisLine(_ data: Data) {
        dispatchPrecondition(condition: .onQueue(.main))
        if receiveHoverLine(data) { return }
        if let warning = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = warning["warning"] as? String, let id = warning["id"] as? String,
           requests.values.contains(id) {
            analysisWarning = "KataGo: " + message
            return
        }
        if let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = error["error"] as? String, let id = error["id"] as? String,
           let turn = requests.first(where: { $0.value == id })?.key {
            failRequest(turn: turn, message: "Analysis failed: \(message)")
            return
        }
        guard let analysis = try? JSONDecoder().decode(AIAnalysis.self, from: data),
              requests[analysis.turnNumber] == analysis.id else { return }
        guard let root = analysis.rootInfo, root.visits > 0, root.winrate.isFinite,
              (0...1).contains(root.winrate), root.scoreLead.isFinite else {
            failRequest(turn: analysis.turnNumber, message: "KataGo returned an invalid analysis result.")
            return
        }
        currentAnalysisData[analysis.turnNumber] = analysis
        if analysis.isDuringSearch != true {
            requestTimeouts.removeValue(forKey: analysis.turnNumber)?.cancel()
            requests.removeValue(forKey: analysis.turnNumber)
            pendingVisits.removeValue(forKey: analysis.turnNumber)
        }
        scheduleCacheSave()
    }

    private func failRequest(turn: Int, message: String) {
        requestTimeouts.removeValue(forKey: turn)?.cancel()
        requests.removeValue(forKey: turn); pendingVisits.removeValue(forKey: turn)
        if let fingerprint = fingerprints[turn] { failedPositions.insert(fingerprint) }
        currentAnalysisData.removeValue(forKey: turn)
        analysisError = message
    }

    func retryFailedAnalysis() {
        failedPositions.removeAll()
        analysisError = nil
    }

    deinit {
        requestTimeouts.values.forEach { $0.cancel() }
        hoverTimeout?.cancel()
        restartTask?.cancel(); cacheSaveTask?.cancel()
        if process?.isRunning == true { process?.terminate() }
        let oldInput = input
        writeQueue.async { try? oldInput?.close() }
    }
}

/// Handles partial lines and split UTF-8 without retaining the engine or another process's pipe.
private final class KataGoLineReader {
    private let source: DispatchSourceRead
    private let handle: FileHandle
    private var buffer = Data()
    private let receive: (Data) -> Void

    init(_ handle: FileHandle, receive: @escaping (Data) -> Void) {
        self.handle = handle
        self.receive = receive
        source = DispatchSource.makeReadSource(fileDescriptor: handle.fileDescriptor,
            queue: DispatchQueue(label: "SGFPlayer.KataGo.reader", qos: .utility))
        source.setCancelHandler { try? handle.close() }
        source.setEventHandler { [weak self] in self?.read() }
        source.resume()
    }

    private func read() {
        let data = handle.availableData
        if data.isEmpty {
            if !buffer.isEmpty { receive(buffer); buffer.removeAll() }
            source.cancel()
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            receive(Data(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
    }

    deinit { source.cancel() }
}

extension KataGoEngine {
    /// Computes the winrate and score deltas for all historical moves analyzed so far to rank their quality
    func evaluateGameQuality(upTo maxIndex: Int, engine: SGFPlayer) -> [Int: MoveEvaluation] {
        var evaluations: [Int: MoveEvaluation] = [:]
        
        // We need data for turn N and N+1 to evaluate the move made at N.
        for t in 0..<max(0, min(maxIndex, engine.maxIndex)) {
            guard let cur = currentAnalysisData[t]?.rootInfo,
                  let next = currentAnalysisData[t+1]?.rootInfo,
                  let player = engine.moveColor(at: t),
                  cur.visits > 0, next.visits > 0,
                  cur.winrate.isFinite, next.winrate.isFinite,
                  (0...1).contains(cur.winrate), (0...1).contains(next.winrate),
                  cur.scoreLead.isFinite, next.scoreLead.isFinite else { continue }
            
            let wPrev = cur.winrate
            let wNext = next.winrate
            
            // KataGo winrate is strictly from the perspective of the player to move.
            // At turn `t`, player `t` is about to move. Winrate for `t` is wPrev.
            // At turn `t+1`, player `t+1` (opponent) is about to move. Winrate for opponent is wNext.
            // So after player `t` moves, their resulting winrate is (1.0 - wNext).
            // The value of their move is (1.0 - wNext) - wPrev.
            let samePlayer = engine.playerToMove(at: t + 1) == player
            let winDelta = (samePlayer ? wNext : 1.0 - wNext) - wPrev
            
            let sPrev = cur.scoreLead
            let sNext = next.scoreLead
            // Same perspective inversion logic for score.
            let scoreDelta = (samePlayer ? sNext : -sNext) - sPrev
            
            let quality: MoveQuality
            if winDelta < -0.20 || scoreDelta < -8.0 {
                quality = .disastrous
            } else if winDelta < -0.10 || scoreDelta < -4.0 {
                quality = .poor
            } else if winDelta < -0.05 || scoreDelta < -2.0 {
                quality = .mediocre
            } else if winDelta < -0.015 || scoreDelta < -0.5 {
                quality = .good
            } else {
                quality = .excellent
            }
            
            evaluations[t] = MoveEvaluation(turn: t, quality: quality, winDelta: winDelta, scoreDelta: scoreDelta, player: player)
        }
        
        return evaluations
    }
}

