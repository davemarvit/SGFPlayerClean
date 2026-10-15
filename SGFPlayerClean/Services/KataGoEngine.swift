import Foundation
import Combine
import SwiftUI

class KataGoEngine: ObservableObject {
    static let shared = KataGoEngine()
    
    private var process: Process?
    private var inPipe: Pipe?
    private var outPipe: Pipe?
    private var errPipe: Pipe?
    
    @Published var isEngineRunning = false
    @Published var currentAnalysisData: [Int: AIAnalysis] = [:] // Map Turn Number -> Analysis
    @Published var engineStartupError: String? = nil
    
    private var lastStderrString: String = "" // Keep track of the last stderr line for crash reporting
    
    var currentGameId: String = "local"
    
    private var readSource: DispatchSourceRead?
    private var isTerminating = false
    private var cacheSaveWorkItem: DispatchWorkItem?
    
    // Default installed via Homebrew. We will allow users to override in Settings later.
    private var katagoPath: String {
        return UserDefaults.standard.string(forKey: "customKataGoPath") ?? "/opt/homebrew/bin/katago"
    }
    
    private var defaultModelPath: String? {
        // Fallback to bundled or expected model
        return Bundle.main.path(forResource: "kata1-b18", ofType: "bin.gz") ?? "/tmp/default_model.bin.gz" 
        // We will improve path resolution later. For dev we can hardcode /Users/Dave... if necessary
    }
    
    private var configPath: String? {
        return Bundle.main.path(forResource: "analysis", ofType: "cfg")
    }

    /// Starts the background KataGo analysis daemon
    func start() {
        guard process == nil else { return } // Already running
        engineStartupError = nil
        lastStderrString = "Unknown Engine Crash."
        isTerminating = false
        
        // Safety Check
        let fm = FileManager.default
        if !fm.fileExists(atPath: katagoPath) {
            NSLog("[AI] ❌ KataGo executable not found at \(katagoPath)")
            engineStartupError = "KataGo executable not found."
            return
        }
        
        let customModel = UserDefaults.standard.string(forKey: "customAIModelPath")
        let modelArg = (customModel != nil && fm.fileExists(atPath: customModel!)) ? customModel! : (defaultModelPath ?? "")
        guard !modelArg.isEmpty, fm.fileExists(atPath: modelArg) else {
             NSLog("[AI] ❌ KataGo Model not found at \(modelArg)")
             engineStartupError = "Neural network model not found."
             return
        }
        
        let p = Process()
        p.executableURL = URL(fileURLWithPath: katagoPath)
        
        // Ensure KataGo has a writable working directory, otherwise it crashes trying to create `logs`
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let katagoWorkDir = cacheURL.appendingPathComponent("SGFPlayerClean/KataGoWork")
        try? FileManager.default.createDirectory(at: katagoWorkDir, withIntermediateDirectories: true, attributes: nil)
        p.currentDirectoryURL = katagoWorkDir
        
        var args = ["analysis", "-model", modelArg]
        if let cfg = configPath, fm.fileExists(atPath: cfg) {
            args.append(contentsOf: ["-config", cfg])
        }
        
        p.arguments = args
        
        inPipe = Pipe()
        outPipe = Pipe()
        errPipe = Pipe()
        
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        
        p.terminationHandler = { [weak self] _ in
             NSLog("[AI] ⚠️ KataGo process terminated.")
             DispatchQueue.main.async {
                 self?.isEngineRunning = false
                 self?.process = nil
                 if self?.isTerminating == false {
                     self?.engineStartupError = "Crash: \(self?.lastStderrString ?? "Unknown Error")"
                 }
             }
        }
        
        do {
            try p.run()
            process = p
            
            DispatchQueue.main.async { self.isEngineRunning = true }
             NSLog("[AI] ✅ KataGo Engine Started Successfully (PID: \(p.processIdentifier))")
            
            startListening(outPipe!)
            startListeningError(errPipe!)
            
        } catch {
             NSLog("[AI] ❌ Failed to start KataGo: \(error)")
             engineStartupError = "Failed to launch process: \(error.localizedDescription)"
        }
    }
    
    func stop() {
        isTerminating = true
        inPipe?.fileHandleForWriting.closeFile()
        process?.terminate()
        process = nil
        readSource?.cancel()
        readSource = nil
        
        saveAnalysisCache(for: currentGameId)
        
        DispatchQueue.main.async {
             self.isEngineRunning = false
             self.currentAnalysisData.removeAll()
        }
        NSLog("[AI] 🛑 KataGo Engine Stopped")
    }
    
    // MARK: - Caching
    func saveAnalysisCache(for gameId: String) {
        guard !currentAnalysisData.isEmpty else { return }
        guard gameId != "local" else { return }
        
        // Use a background queue so we don't stall the UI
        let dataToSave = currentAnalysisData
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(dataToSave)
                let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                let dir = urls[0].appendingPathComponent("SGFPlayerClean/AICache")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
                
                let safeName = gameId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "backup"
                let fileURL = dir.appendingPathComponent("\(safeName).json")
                try data.write(to: fileURL)
                NSLog("[AI] 💾 Saved analysis cache to \(fileURL.lastPathComponent)")
            } catch {
                NSLog("[AI] ❌ Failed to save cache: \(error)")
            }
        }
    }
    
    func loadAnalysisCache(for gameId: String) -> Bool {
        // Save the old cache before loading the new one
        if self.currentGameId != "local" && !self.currentAnalysisData.isEmpty {
            saveAnalysisCache(for: self.currentGameId)
        }
        
        guard gameId != "local" else { return false }
        self.currentGameId = gameId
        
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("SGFPlayerClean/AICache")
        let safeName = gameId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "backup"
        let fileURL = dir.appendingPathComponent("\(safeName).json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode([Int: AIAnalysis].self, from: data)
            DispatchQueue.main.async {
                self.currentAnalysisData = loaded
            }
            NSLog("[AI] 📂 Loaded analysis cache for \(gameId)")
            return true
        } catch {
            return false
        }
    }
    
    func restart() {
        self.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.start()
        }
    }
    
    // MARK: - I/O Handling
    
    private func startListening(_ pipe: Pipe) {
        let fd = pipe.fileHandleForReading.fileDescriptor
        
        // Use GCD to monitor file descriptor asynchronously without blocking
        readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .userInitiated))
        
        var buffer = Data()
        
        readSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty {
                self.readSource?.cancel()
                return
            }
            
            buffer.append(data)
            self.processBuffer(&buffer)
        }
        
        readSource?.resume()
    }
    
    private func startListeningError(_ pipe: Pipe) {
        let fd = pipe.fileHandleForReading.fileDescriptor
        let errSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .utility))
        
        errSource.setEventHandler { [weak self] in
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty {
                errSource.cancel()
                return
            }
            if let stringData = String(data: data, encoding: .utf8) {
                for line in stringData.components(separatedBy: "\n") where !line.isEmpty {
                    NSLog("[AI-ERR] \(line)")
                    self?.lastStderrString = line
                }
            }
        }
        errSource.resume()
    }
    
    private func processBuffer(_ buffer: inout Data) {
        // KataGo outputs exactly one JSON object per line (\n separated)
        guard let stringData = String(data: buffer, encoding: .utf8) else { return }
        
        var lines = stringData.components(separatedBy: "\n")
        
        // If the string doesn't end with a newline, the last element is incomplete
        if !stringData.hasSuffix("\n") {
            let incomplete = lines.removeLast()
            buffer = incomplete.data(using: .utf8) ?? Data()
        } else {
            // It perfectly ended with a newline. Swift's split leaves an empty trailing element.
            buffer = Data()
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if trimmed.hasPrefix("{") {
                parseJSONResponse(trimmed)
            } else {
                NSLog("[AI Output]: \(trimmed)")
            }
        }
    }
    
    private func parseJSONResponse(_ jsonStr: String) {
        guard let data = jsonStr.data(using: .utf8) else { return }
        do {
            let decoder = JSONDecoder()
            let analysis = try decoder.decode(AIAnalysis.self, from: data)
            
            DispatchQueue.main.async {
                self.currentAnalysisData[analysis.turnNumber] = analysis
                self.scheduleCacheSave()
            }
        } catch {
            // Ignore partial parse failures if it's info or warning JSON
             NSLog("[AI] ❌ JSON Parse Error: \(error)")
        }
    }
    
    private func scheduleCacheSave() {
        cacheSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.saveAnalysisCache(for: self.currentGameId)
        }
        cacheSaveWorkItem = item
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5.0, execute: item)
    }
    
    // MARK: - Command Generation
    
    /// Translates our 1-indexed moves or BoardPositions to standard SGF letter coordinates (e.g. Q16, A1, etc.)
    /// KataGo format: A-T skipping I, 1-19 (1 is bottom)
    private func formatCoords(x: Int, y: Int, size: Int = 19) -> String {
        let letters = "ABCDEFGHJKLMNOPQRST" // Standard GTP skip I
        guard x >= 0, x < letters.count, y >= 0, y < size else { return "pass" } // KataGo uses 0-based index or letter
        let letter = String(letters[letters.index(letters.startIndex, offsetBy: x)])
        // KataGo uses standard mathematical Y (1 is bottom). But UI uses 0 at top. 
        // Wait! In KataGo JSON, y coordinate is usually just standard SGF or GTP?
        // KataGo JSON protocol expects GTP standard! letter + (size - y)
        let gtpY = size - y
        return "\(letter)\(gtpY)"
    }
    
    /// Requests analysis for the current path of a game up to the specified turn limit
    func analyzeGame(id: String, initialStones: [(color: String, x: Int, y: Int)], moves: [(color: String, x: Int, y: Int)], size: Int = 19, komi: Double = 6.5, maxVisits: Int = 100) {
        
        var jsonMoves: [[String]] = []
        for m in moves {
            let coord = formatCoords(x: m.x, y: m.y, size: size)
            jsonMoves.append([m.color, coord]) // "B", "Q16"
        }
        
        var jsonInitial: [[String]] = []
        for s in initialStones {
            let coord = formatCoords(x: s.x, y: s.y, size: size)
            jsonInitial.append([s.color, coord])
        }
        
        let turn = moves.count
        
        // We only care about analyzing the CURRENT turn for live feedback.
        let query: [String: Any] = [
            "id": "\(id)_t\(turn)",
            "rules": "chinese", // Usually safe default
            "komi": komi,
            "boardXSize": size,
            "boardYSize": size,
            "initialStones": jsonInitial,
            "moves": jsonMoves,
            "includePolicy": false, // We just want winrate + score lead
            "includeOwnership": true, // To draw heatmaps later!
            "maxVisits": maxVisits,
            "analyzeTurns": [turn] // Just analyze the current node!
        ]
        
        do {
             let data = try JSONSerialization.data(withJSONObject: query, options: [])
             if let str = String(data: data, encoding: .utf8) {
                 sendQuery(str)
             }
        } catch {
             NSLog("[AI] Failed to serialize JSON query: \(error)")
        }
    }
    
    private func sendQuery(_ json: String) {
        guard let inPipe = inPipe else { return }
        let payload = json + "\n"
        if let data = payload.data(using: .utf8) {
            do {
                 // write is deprecated but straightforward for small payloads. Alternatively use writeableData.
                if #available(macOS 10.15.4, *) {
                    try inPipe.fileHandleForWriting.write(contentsOf: data)
                } else {
                    inPipe.fileHandleForWriting.write(data)
                }
            } catch {
                NSLog("[AI] Error writing to KataGo pipe: \(error)")
                // Engine might have died
                stop()
            }
        }
    }
}

extension KataGoEngine {
    /// Computes the winrate and score deltas for all historical moves analyzed so far to rank their quality
    func evaluateGameQuality(upTo maxIndex: Int, engine: SGFPlayer) -> [Int: MoveEvaluation] {
        var evaluations: [Int: MoveEvaluation] = [:]
        
        // We need data for turn N and N+1 to evaluate the move made at N.
        for t in 0..<maxIndex {
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
            let winDelta = (1.0 - wNext) - wPrev // > 0 is good
            
            let sPrev = cur.scoreLead
            let sNext = next.scoreLead
            // Same perspective inversion logic for score.
            let scoreDelta = -sNext - sPrev
            
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

