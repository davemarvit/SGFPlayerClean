// ========================================================
// FILE: ./Models/AppModel.swift
// VERSION: v4.886 (Clean Rebuild)
// ========================================================
import Foundation
import SwiftUI
import Combine
import AVFoundation

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("viewMode") var viewMode: ViewMode = .view2D
    @Published var games: [SGFGameWrapper] = []
    @Published var selection: SGFGameWrapper? = nil
    @Published var player = SGFPlayer()
    @Published var ogsClient = OGSClient()
    @Published var layoutVM = LayoutViewModel()
    @Published var timeControl = TimeControlManager()
    @Published var ogsGame: OGSGameViewModel?
    @Published var isOnlineMode: Bool = false
    @Published var isCreatingChallenge: Bool = false
    @Published var showDebugDashboard: Bool = false
    @Published var boardVM: BoardViewModel?
    
    private var cancellables: Set<AnyCancellable> = []
    private var currentActiveInternalGameID: Int? = nil
    @Published var resumableGameID: Int? = nil
    private var stoneClickPlayer: AVAudioPlayer?

    init() {
        let bVM = BoardViewModel(player: player, ogsClient: ogsClient)
        self.boardVM = bVM
        self.ogsGame = OGSGameViewModel(ogsClient: ogsClient, player: player, timeControl: timeControl)
        
        ogsClient.$activeGameID
            .receive(on: RunLoop.main)
            .sink { [weak self] gid in
                if gid != nil { self?.isOnlineMode = true }
            }.store(in: &cancellables)
            
        ogsClient.$myActiveGames
            .receive(on: RunLoop.main)
            .sink { [weak self] games in
                // Auto-detect resumable games from lobby events
                // Auto-detect resumable games from lobby events
                if let first = games.first {
                    self?.resumableGameID = first
                } else {
                    self?.resumableGameID = nil
                }
            }.store(in: &cancellables)

        ogsClient.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        setupAudio(); self.ogsClient.connect(); setupOGSObservers()
    }
    
    private func robustInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }
    
    func joinOnlineGame(id: Int) {
        // DEBUG TRACE: Who is calling joinOnlineGame?
        let trace = Thread.callStackSymbols.joined(separator: "\n")
        // NSLog("[OGS-CS] 🚀 joinOnlineGame CALLED for \(id). Stack:\n\(trace)")

        self.player.clear()
        self.boardVM?.resetToEmpty()
        self.currentActiveInternalGameID = nil
        self.isOnlineMode = false
        
        // Verified: Helper methods restored in Client v16.305
        self.ogsClient.acceptChallenge(challengeID: id) { [weak self] (newGameID: Int?, error: Error?) in
            guard let self = self else { return }
            if let gid = newGameID {
                self.ogsClient.fetchGameState(gameID: gid) { [weak self] (rootJson: [String: Any]?) in
                    guard let root = rootJson else { return }
                    let data = (root["gamedata"] as? [String: Any]) ?? root
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": data])
                    }
                }
            }
        }
    }
    
    func resumeOnlineGame(id: Int) {
        // NSLog("[OGS-CS] 🚀 resumeOnlineGame CALLED for \(id)")
        
        self.player.clear()
        self.boardVM?.resetToEmpty()
        self.currentActiveInternalGameID = nil
        self.isOnlineMode = false
        
        // Directly set Active ID so safeguards pass
        self.ogsClient.activeGameID = id
        
        // Connect Socket
        self.ogsClient.connectToGame(gameID: id)
        
        // Fetch State
        self.ogsClient.fetchGameState(gameID: id) { [weak self] rootJson in
            guard let root = rootJson else { return }
            let data = (root["gamedata"] as? [String: Any]) ?? root
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": data])
            }
        }
    }
    
    private func setupOGSObservers() {
        let nc = NotificationCenter.default
        nc.publisher(for: NSNotification.Name("OGSGameDataReceived")).receive(on: RunLoop.main).sink { [weak self] n in self?.handleOGSGameLoad_V2(n) }.store(in: &cancellables)
        nc.publisher(for: NSNotification.Name("OGSMoveReceived")).receive(on: RunLoop.main).sink { [weak self] n in self?.handleOGSMoveUpdate(n) }.store(in: &cancellables)
        // We rely on 'Expectation Filter' (Smart Guard) in handleOGSGameLoad now.
        // But for visual feedback, we still step backward locally.
        // Removed OGSUndoAcceptedLocal to rely exclusively on Server State
    }
    
    
    private func handleOGSGameLoad_V2(_ notification: Notification) {
        guard let userInfo = notification.userInfo, let gameData = userInfo["gameData"] as? [String: Any] else { return }
        
        // NSLog("[OGS-DEBUG] handleOGSGameLoad Entry. isRequestingUndo: \(ogsClient.isRequestingUndo)")
        // print("🔥🔥🔥 BUILD VERIFICATION: v4.886 - TRACER ACTIVE 🔥🔥🔥")
        
        let gameID = robustInt(gameData["game_id"]) ?? robustInt(gameData["id"]) ?? 0
        // NSLog("[OGS-DEBUG] 🚨 AppModel received GameData for \(gameID). Active: \(ogsClient.activeGameID ?? -1)")
        guard gameID == ogsClient.activeGameID else {
            NSLog("[OGS-DEBUG] ❌ Game ID Mismatch. Ignoring.")
            return
        }
        
        // FORCE SYNC: Always reload board when full game data is received
        // This ensures undo/redo states are correctly reflected without caching issues
        if true {
            currentActiveInternalGameID = gameID
            resumableGameID = gameID // Track for Resume Button
            
            NSLog("[OGS-TRACE] A: Start Parsing")
            let width = gameData["width"] as? Int ?? 19
            let height = gameData["height"] as? Int ?? 19
            let moves = (gameData["moves"] as? [[Any]]) ?? []
            NSLog("[OGS-TRACE] B: Moves Parsed (\(moves.count))")
            
            // VERSION GUARD (Deterministic - Engine Based)
            let incomingVersion = robustInt(gameData["state_version"]) ?? robustInt(gameData["move_number"]) ?? 0
            NSLog("[OGS-TRACE] C: Incoming Version Parsed (\(incomingVersion))")
            
            // Use Engine's version as Truth (Avoids OGSClient eager update race)
            let engineVersion = boardVM?.engine.highestKnownStateVersion ?? 0
            NSLog("[OGS-TRACE] D: Engine Current (\(engineVersion))")
            
            NSLog("[OGS-SYNC] 🔄 Packet Version: \(incomingVersion). Engine Version: \(engineVersion). Moves: \(moves.count)")
            
            // STRICT MONOTONICITY: Only accept NEWER versions
            // This blocks 'Pre-Undo' echoes (Same Version) and Stale packets (Lower Version)
            // EXCEPTION: If move count DECREASES, it is a valid UNDO (or reset). Accept it.
            let engineMoves = boardVM?.engine.maxIndex ?? 0
            let isUndo = moves.count < engineMoves
            
            if incomingVersion <= engineVersion && !isUndo && engineMoves > 0 {
                // NSLog("[OGS-SYNC] 🛡️ IGNORING STALE/EQUAL ECHO (v\(incomingVersion) <= v\(engineVersion)). Not an Undo (Incoming: \(moves.count) vs Engine: \(engineMoves)).")
                return
            }
            if isUndo {
                // NSLog("[OGS-SYNC] ↩️ Undo Detected (Incoming \(moves.count) < Engine \(engineMoves)). BYPASSING Version Guard.")
                // DO NOT disarm ghost guard here. Persist until next user move.
            }
            // else if incomingVersion > engineVersion { NSLog("[OGS-SYNC] ✅ New Version Detected (v\(incomingVersion) > v\(engineVersion)). Accepting.") }
            // If versions match (or incoming is higher), we accept.
            
            // Force reset undo flag if we accepted a valid packet
             ogsClient.isRequestingUndo = false
            
            // Legacy/Fallback Guard (Double Safety)
            // Legacy Guard Removed - Relying on Version Control


            var initialStones: [BoardPosition: Stone] = [:]
            
            if let state = gameData["initial_state"] as? [String: Any] {
                NSLog("[OGS-REST] Parsing Initial State")
                let white = state["white"] as? String ?? ""
                ["black", "white"].forEach { col in
                    if let str = state[col] as? String {
                        let color: Stone = col == "black" ? .black : .white
                        let chars = Array(str)
                        for i in stride(from: 0, to: chars.count, by: 2) {
                            if i + 1 < chars.count, let (x, y) = SGFCoordinates.parse(String(chars[i...i+1])) {
                                initialStones[BoardPosition(y, x)] = color
                            }
                        }
                    }
                }
            }
            
            let initialTurnColor: Stone = (gameData["initial_player"] as? String == "white") ? .white : .black
            // NSLog("[OGS-DEBUG] ♟️ Initial Player Raw: \(gameData["initial_player"] ?? "nil") -> Parsed: \(initialTurnColor)")
            
            let stateVersion = robustInt(gameData["state_version"]) ?? robustInt(gameData["move_number"]) ?? 0
            
            boardVM?.initializeOnlineGame(width: width, height: height, initialStones: initialStones, nextPlayer: initialTurnColor, stateVersion: stateVersion)
            
            let moveHistory = gameData["moves"] as? [[Any]] ?? []
            var turnColor = initialTurnColor
            for (idx, m) in moveHistory.enumerated() {
                if m.count >= 2, let x = robustInt(m[0]), let y = robustInt(m[1]) {
                    if x == -1 && y == -1 { // OGS represents passes as [-1, -1] in move history
                        // Handle Pass
                        // NSLog("[OGS-EVT] 🙈 Remote Pass Detected.")
                        boardVM?.handleRemotePass(color: turnColor)
                    } else if x >= 0 && y >= 0 {
                        boardVM?.handleRemoteMove(x: x, y: y, color: turnColor)
                    }
                    turnColor = turnColor.opponent
                }
            }
        }
        
        boardVM?.syncState()
        self.objectWillChange.send()
    }
    
    private func handleOGSMoveUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        if let gid = robustInt(userInfo["game_id"]), gid != ogsClient.activeGameID { return }
        
        NSLog("[OGS-EVT] 📩 Move Event Received. Payload: \(userInfo)")

        var x: Int = -1
        var y: Int = -1
        var isPass = false
        
        if let mArr = userInfo["move"] as? [Any], mArr.count >= 2 {
            x = robustInt(mArr[0]) ?? -1
            y = robustInt(mArr[1]) ?? -1
            if x == -1 && y == -1 { isPass = true }
        } else if let mStr = userInfo["move"] as? String {
            if mStr == ".." || mStr == "pass" { isPass = true }
            else if let (sx, sy) = SGFCoordinates.parse(mStr) { x = sx; y = sy }
        }
        
        if isPass {
            if let mn = robustInt(userInfo["move_number"]) {
                 let color: Stone
                 if let pid = robustInt(userInfo["player_id"]) {
                     color = (pid == ogsClient.blackPlayerID) ? .black : .white
                 } else {
                     color = (ogsClient.currentHandicap > 0) ? ((mn % 2 == 0) ? .black : .white) : ((mn % 2 == 0) ? .white : .black)
                 }
                boardVM?.handleRemotePass(color: color)
            }
        }
        else if x >= 0 && y >= 0 {
            if let mn = robustInt(userInfo["move_number"]) {
                // Ghost Guard Removed: We now rely on Strict Server Authority.
                // Any move sent by OGS is considered valid.
                
                let color: Stone
                if let pid = robustInt(userInfo["player_id"]) {
                    color = (pid == ogsClient.blackPlayerID) ? .black : .white
                } else {
                    color = (ogsClient.currentHandicap > 0) ? ((mn % 2 == 0) ? .black : .white) : ((mn % 2 == 0) ? .white : .black)
                }
                playStoneClickSound()
                boardVM?.handleRemoteMove(x: x, y: y, color: color)
            }
        }
    }
    
    private func setupAudio() { if let url = Bundle.main.url(forResource: "Stone_click_1", withExtension: "mp3") { stoneClickPlayer = try? AVAudioPlayer(contentsOf: url); stoneClickPlayer?.prepareToPlay() } }
    func playStoneClickSound() { stoneClickPlayer?.play() }
    func selectGame(_ g: SGFGameWrapper) { selection = g; boardVM?.loadGame(g) }
    func promptForFolder() { /* Implementation */ }
    func loadFolder(_ u: URL) { /* Implementation */ }
}
