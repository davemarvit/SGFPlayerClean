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
    
    private var readSource: DispatchSourceRead?
    private var isTerminating = false
    
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
                     self?.engineStartupError = "KataGo crashed unexpectedly."
                 }
             }
        }
        
        do {
            try p.run()
            process = p
            
            DispatchQueue.main.async { self.isEngineRunning = true }
             NSLog("[AI] ✅ KataGo Engine Started Successfully (PID: \(p.processIdentifier))")
            
            startListening(outPipe!)
            
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
        
        DispatchQueue.main.async {
             self.isEngineRunning = false
             self.currentAnalysisData.removeAll()
        }
        NSLog("[AI] 🛑 KataGo Engine Stopped")
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
    
    private func processBuffer(_ buffer: inout Data) {
        // KataGo outputs one JSON object per line (\n separated)
        guard let stringData = String(data: buffer, encoding: .utf8) else { return }
        let lines = stringData.components(separatedBy: "\n")
        
        // Keep the last incomplete line
        if lines.last?.isEmpty == false {
            if let last = lines.last?.data(using: .utf8) {
                buffer = last
            } else { buffer = Data() }
        } else {
            buffer = Data()
        }
        
        for i in 0..<(lines.count - 1) { // -1 because the last element is the remainder
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("{") {
                parseJSONResponse(line)
            } else {
                // Warning or init message from KataGo (stderr might also bleed here if piped identically, though we pipe split)
                NSLog("[AI Output]: \(line)")
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
            }
        } catch {
            // Ignore partial parse failures if it's info or warning JSON
             NSLog("[AI] JSON Parse Warning: \(error) on string: \(jsonStr.prefix(100))...")
        }
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
            "action": "analyze",
            "compileMoves": [],
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
