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
    @Published var isTypingInChat: Bool = false // Global flag to disable shortcuts
    
    // UI Persistence
    @Published var rightPanelTab: PanelTab = .local
    enum PanelTab: String { case local = "Local", online = "Online" }
    
    private var cancellables: Set<AnyCancellable> = []
    private var currentActiveInternalGameID: Int? = nil
    @Published var resumableGameID: Int? = nil
    private var savedLocalSnapshot: SGFPlayer.LocalGameSnapshot? = nil
    
    // Audio
    enum SoundType { case place, captureSingle, captureMultiple }
    private var clickPlayer: AVAudioPlayer?
    private var captureSinglePlayer: AVAudioPlayer?
    private var captureMultiPlayer: AVAudioPlayer?
    // private var stoneClickPlayer: AVAudioPlayer? // Replaced by above

    init() {
        let bVM = BoardViewModel(player: player, ogsClient: ogsClient)
        self.boardVM = bVM
        self.ogsGame = OGSGameViewModel(ogsClient: ogsClient, player: player, timeControl: timeControl)
        
        // Audio Binding
        bVM.onPlaySound = { [weak self] type in
            self?.playSound(type)
        }
        
        // Initialize Audio
        setupAudio()
        
        // PERSISTENCE CHECK: Restore online mode state
        let wasOnline = UserDefaults.standard.bool(forKey: "isOnlineModePersistent")
        if wasOnline {
            print("💾 Restoring Online Mode State (User was online)")
            self.isOnlineMode = true
        }

        ogsClient.$activeGameID
            .receive(on: RunLoop.main)
            .dropFirst() // FIX: Ignore initial 'nil' to prevent overwriting persistence restore
            .sink { [weak self] gid in
                let isOnline = (gid != nil)
                
                // Only change mode if we are actually entering/leaving a game
                // If we are already online (restored), and gid is nil, that's fine (Lobby).
                // Wait: If gid becomes nil (game ends), we stay in Online Mode (Lobby).
                // If gid becomes non-nil, we are definitely in Online Mode.
                
                if let id = gid {
                    self?.isOnlineMode = true
                } 
                // Note: We DO NOT auto-switch to Local Mode just because activeGameID is nil.
                // The user must explicitly disconnect or switch modes.
                // However, we DO want to persist the "Online" state.
                
                // Let's defer "Offline" switch to user action, OR ensure we track "Intended Mode".
                // Current logic: If activeGameID is valid, we are Online.
                // If activeGameID is nil, we might be consistently in Online Lobby.
                
                if isOnline {
                     self?.isOnlineMode = true
                     UserDefaults.standard.set(true, forKey: "isOnlineModePersistent")
                }
            }.store(in: &cancellables)
            
        ogsClient.$myActiveGames
            .receive(on: RunLoop.main)
            .sink { [weak self] games in
                // Auto-detect resumable games from lobby events
                if let first = games.first {
                    self?.resumableGameID = first
                } else {
                    self?.resumableGameID = nil
                }
            }.store(in: &cancellables)

        ogsClient.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        
        setupAudio()
        setupOGSObservers()
        
        // CONDITION: Only connect if we restore Online Mode
        if wasOnline {
            print("🚀 Auto-Connecting to OGS (Persistent Mode)")
            self.ogsClient.connect()
        }
        
        // Auto-Connect when switching tab to Online
        $rightPanelTab
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] tab in
                guard let self = self else { return }
                
                if tab == .online {
                    print("🚀 Switching to Online Tab")
                    // 1. Snapshot Local State
                    if !self.isOnlineMode {
                        self.savedLocalSnapshot = self.player.createSnapshot()
                        print("💾 Local Game Saved (Moves: \(self.savedLocalSnapshot?.moves.count ?? 0))")
                    }
                    
                    // 2. Connect & Clear
                    self.boardVM?.resetToEmpty() // FIX: Ensures UI (glow) clears along with engine
                    self.ogsClient.connect()
                    self.isOnlineMode = true
                    UserDefaults.standard.set(true, forKey: "isOnlineModePersistent")
                    
                } else {
                    print("🚪 Switching to Local Mode")
                    self.ogsClient.disconnect()
                    self.isOnlineMode = false
                    UserDefaults.standard.set(false, forKey: "isOnlineModePersistent")
                    
                    // 3. Restore or Start New
                    self.player.clear() // Ensure clean slate first
                    
                    if let snap = self.savedLocalSnapshot {
                        print("♻️ Restoring Local Game...")
                        self.player.restoreSnapshot(snap)
                    } else if AppSettings.shared.startGameOnLaunch {
                        print("✨ Starting New Game (StartOnLaunch)")
                        self.startInstantGame()
                    }
                }
            }.store(in: &cancellables)
        // This prevents the "confusing local game" issue when waking up in online mode.
        if !wasOnline {
            // Priority: Start Instant Game if enabled (guarantees playable board)
            if AppSettings.shared.startGameOnLaunch {
                self.startInstantGame()
            }
            
            // Then attempt to load folder (async)
            if let url = AppSettings.shared.folderURL {
                print("📂 Auto-loading saved folder: \(url.path)")
                loadFolder(url)
            }
        }
        
        setupAutoAdvance()
        
        // Sync Stone Volume
        AppSettings.shared.$stoneVolume
            .receive(on: RunLoop.main)
            .sink { [weak self] vol in
                let f = Float(vol)
                self?.clickPlayer?.volume = f
                self?.captureSinglePlayer?.volume = f
                self?.captureMultiPlayer?.volume = f
            }.store(in: &cancellables)
    }
    
    private func startInstantGame() {
        self.player.reset()
        // Create Dummy Wrapper for UI
        var newGame = SGFGame()
        newGame.boardSize = 19
        newGame.info.event = "Instant Game"
        newGame.info.date = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        
        let dummyURL = URL(fileURLWithPath: "/tmp/InstantGame.sgf")
        let wrapper = SGFGameWrapper(url: dummyURL, game: newGame)
        
        self.selection = wrapper
    }
    
    // MARK: - Audio
    private func setupAudio() {
        // macOS does not require AVAudioSession configuration for simple playback
        NSLog("[SOUND] Audio Setup: Loading Assets...")

        // Load Sound Assets
        // Note: filenames must match exactly (case-sensitive on device, usually loose on Sim)
        self.clickPlayer = loadSound("Stone_click_1.mp3")
        self.captureSinglePlayer = loadSound("Capture_single.mp3")
        self.captureMultiPlayer = loadSound("Capture_multiple.mp3")
        
        // Apply Initial Volume
        let v = Float(AppSettings.shared.stoneVolume)
        clickPlayer?.volume = v
        captureSinglePlayer?.volume = v
        captureMultiPlayer?.volume = v
    }
    
    private func loadSound(_ name: String) -> AVAudioPlayer? {
        // Look in main bundle
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            NSLog("[SOUND] ❌ Audio file not found in Bundle: \(name)")
            return nil
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            NSLog("[SOUND] Loaded: \(name)")
            return p
        } catch {
            NSLog("[SOUND] ❌ Failed to create player for \(name): \(error)")
            return nil
        }
    }
    
    func playSound(_ type: SoundType) {
        // Simple overlap logic: stop before play? Or mix?
        // standard stones usually cut off previous click?
        // Let's allow mix for rapid play, but maybe re-trigger.
        
        var p: AVAudioPlayer?
        switch type {
        case .place: p = clickPlayer
        case .captureSingle: p = captureSinglePlayer
        case .captureMultiple: p = captureMultiPlayer
        }
        
        guard let player = p else {
             NSLog("[SOUND] ⚠️ Request to play \(type) but player is nil")
             return
        }
        
        // NSLog("[SOUND] Playing: \(type)") // Silenced to reduce noise
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    private func setupAutoAdvance() {
        player.$isPlaying
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                if !isPlaying { self?.handlePlaybackStopped() }
            }
            .store(in: &cancellables)
    }
    
    private func handlePlaybackStopped() {
        guard player.currentIndex == player.maxIndex, player.maxIndex > 0 else { return }
        
        print("🏁 Game Finished. Auto-advancing in 3s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.tryAutoAdvance()
        }
    }
    
    private func tryAutoAdvance() {
        // Re-check state to ensure user didn't start scrubbing or playing again
        // FIX: Do not auto-advance if we are in Online Mode (Chat/Spectating)
        guard !isOnlineMode, !player.isPlaying, player.currentIndex == player.maxIndex else { return }
        playNextGame()
    }
    
    func playNextGame() {
        guard let current = selection, let idx = games.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIdx = (idx + 1) % games.count
        let nextGame = games[nextIdx]
        
        print("⏭️ Auto-Advancing to: \(nextGame.url.lastPathComponent)")
        selectGame(nextGame)
        
        // Short delay to ensure load completes before playing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.boardVM?.startAutoPlay()
        }
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
                
                let color: Stone
                if let pid = robustInt(userInfo["player_id"]) {
                    color = (pid == ogsClient.blackPlayerID) ? .black : .white
                } else {
                    color = (ogsClient.currentHandicap > 0) ? ((mn % 2 == 0) ? .black : .white) : ((mn % 2 == 0) ? .white : .black)
                }
                
                // Sound Trigger (Online)
                // We rely on the Engine's truth because OGS's 'removed' payload is often empty/unreliable.
                let oldB = boardVM?.engine.blackStonesCaptured ?? 0
                let oldW = boardVM?.engine.whiteStonesCaptured ?? 0
                
                // Apply Move
                boardVM?.handleRemoteMove(x: x, y: y, color: color)
                
                // Check Engine Diff
                let newB = boardVM?.engine.blackStonesCaptured ?? 0
                let newW = boardVM?.engine.whiteStonesCaptured ?? 0
                let captured = (newB - oldB) + (newW - oldW)
                
                if captured > 1 { self.playSound(.captureMultiple) }
                else if captured == 1 { self.playSound(.captureSingle) }
                else { 
                    // Prevent double-playing 'place' for self (handled optimistically)
                    let myColor = ogsClient.playerColor ?? .white
                    if color != myColor {
                        self.playSound(.place) 
                    }
                }
            }
        }
    }
    
    func selectGame(_ g: SGFGameWrapper) { selection = g; boardVM?.loadGame(g) }
    func promptForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Load Games"
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.loadFolder(url)
            }
        }
    }
    
    func loadFolder(_ url: URL) {
        // 1. Update Settings
        AppSettings.shared.folderURL = url
        
        // 2. Clear current library
        self.games = []
        self.selection = nil
        
        // 3. Background Load
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Security Scope: Essential for App Sandbox access to user-selected folder
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            
            let fm = FileManager.default
            var foundURLs: [URL] = []
            
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "sgf" {
                        foundURLs.append(fileURL)
                    }
                }
            }
            
            // Sort
            foundURLs.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            
            // Shuffle?
            if AppSettings.shared.shuffleGameOrder {
                foundURLs.shuffle()
            }
            
            // Parse Code
            var loaded: [SGFGameWrapper] = []
            for sgfURL in foundURLs {
                do {
                    let data = try Data(contentsOf: sgfURL)
                    // Try UTF8, fallback to lossy
                    let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    
                    let tree = try SGFParser.parse(text: text)
                    let game = SGFGame.from(tree: tree)
                    loaded.append(SGFGameWrapper(url: sgfURL, game: game))
                } catch {
                    print("Failed to parse \(sgfURL.lastPathComponent): \(error)")
                }
            }
            
            // 4. Update Main Actor
            DispatchQueue.main.async {
                self.games = loaded
                print("📚 Loaded \(loaded.count) games from \(url.lastPathComponent)")
                
                // Auto-Behavior
                // Auto-Behavior
                if AppSettings.shared.startGameOnLaunch, let first = loaded.first {
                    self.selectGame(first)
                    // Trigger Playback
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.boardVM?.startAutoPlay()
                    }
                } else {
                    if let first = loaded.first {
                        self.selection = first
                    }
                }
            }
        }
    }
}
