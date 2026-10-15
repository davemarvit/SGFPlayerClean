import Foundation
import Combine
import CryptoKit

/// State and published values are owned by the main queue. Pipe and cache I/O are serialized separately.
class KataGoEngine: ObservableObject {
    static let shared = KataGoEngine()
    @Published private(set) var isEngineRunning = false
    @Published var currentAnalysisData: [Int: AIAnalysis] = [:]
    @Published private(set) var engineStartupError: String?

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

    init(executableURL: URL? = nil, modelURL: URL? = nil, cacheDirectory: URL? = nil,
         scheduler: OGSConnectionScheduler = OGSMainQueueScheduler()) {
        executableOverride = executableURL
        modelOverride = modelURL
        self.scheduler = scheduler
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SGFPlayerClean/AICache")
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        restartTask?.cancel(); restartTask = nil
        guard process == nil else { return }
        engineStartupError = nil
        let fm = FileManager.default
        let executable = executableOverride ?? URL(fileURLWithPath:
            UserDefaults.standard.string(forKey: "customKataGoPath") ?? "/opt/homebrew/bin/katago")
        guard fm.isExecutableFile(atPath: executable.path) else {
            engineStartupError = "KataGo executable not found or not executable."; return
        }
        let customModel = UserDefaults.standard.string(forKey: "customAIModelPath")
        let model = modelOverride?.path ?? customModel.flatMap { fm.fileExists(atPath: $0) ? $0 : nil }
            ?? Bundle.main.path(forResource: "kata1-b18", ofType: "bin.gz") ?? "/tmp/default_model.bin.gz"
        guard fm.fileExists(atPath: model) else { engineStartupError = "Neural network model not found."; return }
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
        processGeneration += 1
        requests.removeAll()
        pendingVisits.removeAll()
        readers.removeAll() // Each reader cancels and closes only its own descriptor.
        let oldInput = input
        input = nil
        writeQueue.async { try? oldInput?.close() }
        process = nil
        isEngineRunning = false
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        restartTask?.cancel(); restartTask = nil
        cacheSaveTask?.cancel(); cacheSaveTask = nil
        saveAnalysisCache(for: currentGameId)
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
        cacheSaveTask?.cancel(); cacheSaveTask = nil
        requests.removeAll()
        pendingVisits.removeAll()
        fingerprints.removeAll()
        currentAnalysisData.removeAll()
    }

    private struct Cache: Codable {
        let analyses: [Int: AIAnalysis]
        let fingerprints: [Int: String]
    }

    private func cacheURL(for gameID: String) -> URL {
        // Fixed-length names avoid slashes, path traversal, and very long local SGF paths.
        cacheDirectory.appendingPathComponent("v2-\(digest(Data(gameID.utf8))).json")
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func saveAnalysisCache(for gameID: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard gameID == currentGameId, gameID != "local", !currentAnalysisData.isEmpty else { return }
        let snapshot = Cache(analyses: currentAnalysisData, fingerprints: fingerprints)
        let url = cacheURL(for: gameID)
        cacheQueue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            } catch { NSLog("[AI] Cache write failed: \(error.localizedDescription)") }
        }
    }

    @discardableResult
    func loadAnalysisCache(for gameID: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        saveAnalysisCache(for: currentGameId)
        currentGameId = gameID
        invalidateAnalysis()
        guard gameID != "local" else { return false }
        let url = cacheURL(for: gameID)
        // Ordered after pending writes; apply synchronously so a deferred old load cannot replace a new game.
        guard let loaded = cacheQueue.sync(execute: { () -> Cache? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Cache.self, from: data)
        }) else { return false }
        currentAnalysisData = loaded.analyses
        fingerprints = loaded.fingerprints
        return true
    }

    private func scheduleCacheSave() {
        cacheSaveTask?.cancel()
        cacheSaveTask = scheduler.schedule(after: 5) { [weak self] in
            guard let self else { return }
            self.saveAnalysisCache(for: self.currentGameId)
        }
    }

    /// One unique ID per request: results can arrive out of order, even at the same turn.
    func analyzeGame(id: String, initialStones: [(color: String, x: Int, y: Int)],
                     moves: [(color: String, x: Int, y: Int)], size: Int = 19,
                     komi: Double = 6.5, maxVisits: Int = 100) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isEngineRunning, id == currentGameId, (2...19).contains(size),
              komi.isFinite, (-400...400).contains(komi), maxVisits > 0 else { return }
        func coordinates(_ value: (color: String, x: Int, y: Int), allowPass: Bool) -> [String]? {
            guard value.color == "B" || value.color == "W" else { return nil }
            if allowPass && value.x == -1 && value.y == -1 { return [value.color, "pass"] }
            guard (0..<size).contains(value.x), (0..<size).contains(value.y) else { return nil }
            let letters = Array("ABCDEFGHJKLMNOPQRST")
            return [value.color, "\(letters[value.x])\(size - value.y)"]
        }
        let jsonMoves = moves.compactMap { coordinates($0, allowPass: true) }
        let jsonInitial = initialStones.compactMap { coordinates($0, allowPass: false) }
        guard jsonMoves.count == moves.count, jsonInitial.count == initialStones.count else { return }
        let turn = moves.count
        var query: [String: Any] = ["rules": "chinese", "komi": komi, "boardXSize": size, "boardYSize": size,
            "initialStones": jsonInitial, "moves": jsonMoves, "includePolicy": false, "includeOwnership": true,
            "analyzeTurns": [turn]]
        guard let position = try? JSONSerialization.data(withJSONObject: query, options: .sortedKeys) else { return }
        let fingerprint = digest(position)
        if fingerprints[turn] == fingerprint {
            if (currentAnalysisData[turn]?.rootInfo?.visits ?? 0) >= maxVisits { return }
            if requests[turn] != nil, (pendingVisits[turn] ?? 0) >= maxVisits { return }
        }
        if let previous = fingerprints[turn], previous != fingerprint {
            // Undo/variation at a known turn invalidates that turn and all its descendants.
            currentAnalysisData = currentAnalysisData.filter { $0.key < turn }
            fingerprints = fingerprints.filter { $0.key < turn }
            requests = requests.filter { $0.key < turn }
            pendingVisits = pendingVisits.filter { $0.key < turn }
        }
        let requestID = UUID().uuidString
        requests[turn] = requestID
        pendingVisits[turn] = maxVisits
        fingerprints[turn] = fingerprint
        query["id"] = requestID
        query["maxVisits"] = maxVisits
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

    // Internal for offline protocol fixtures; production calls arrive from the fenced stdout reader.
    func receiveAnalysisLine(_ data: Data) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = error["error"] as? String, let id = error["id"] as? String,
           let turn = requests.first(where: { $0.value == id })?.key {
            requests.removeValue(forKey: turn); pendingVisits.removeValue(forKey: turn)
            engineStartupError = "Analysis failed: \(message)"
            return
        }
        guard let analysis = try? JSONDecoder().decode(AIAnalysis.self, from: data),
              requests[analysis.turnNumber] == analysis.id else { return }
        currentAnalysisData[analysis.turnNumber] = analysis
        if analysis.isDuringSearch != true {
            requests.removeValue(forKey: analysis.turnNumber)
            pendingVisits.removeValue(forKey: analysis.turnNumber)
        }
        scheduleCacheSave()
    }

    deinit {
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
                  let player = engine.moveColor(at: t) else { continue }
            
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

