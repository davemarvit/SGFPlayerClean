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
    
    var sortedGames: [SGFGameWrapper] {
        switch gameSortMethod {
        case .defaultIndex:
            return games
        case .name:
            return games.sorted { 
                let name1 = "\($0.game.info.playerBlack ?? "") \($0.game.info.playerWhite ?? "")"
                let name2 = "\($1.game.info.playerBlack ?? "") \($1.game.info.playerWhite ?? "")"
                return name1.caseInsensitiveCompare(name2) == .orderedAscending 
            }
        case .date:
            return games.sorted { 
                let d1 = $0.game.info.date ?? ""
                let d2 = $1.game.info.date ?? ""
                return d1 > d2 // Descending latest first (YYYY-MM-DD typical format)
            }
        }
    }
    
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
    @Published var loadingStatus: String = "Idle" // Diagnostic Status
    @Published var lastDebugLog: String = "Waiting for Move..."
    
    // AI Integration Flags
    var isAIAvailable: Bool {
        return rightPanelTab == .ai && (!isOnlineMode || ogsClient.isGameFinished)
    }
    
    // UI Persistence
    @Published var showRightPanel: Bool = UserDefaults.standard.object(forKey: "showRightPanel") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showRightPanel, forKey: "showRightPanel") }
    }
    
    @Published var rightPanelTab: PanelTab = .local
    enum PanelTab: String { case local = "Local", online = "Online", ai = "AI" }
    
    @Published var gameSortMethod: GameSortMethod = GameSortMethod(rawValue: UserDefaults.standard.string(forKey: "gameSortMethod") ?? "Default") ?? .defaultIndex {
        didSet { UserDefaults.standard.set(gameSortMethod.rawValue, forKey: "gameSortMethod") }
    }
    enum GameSortMethod: String, CaseIterable {
        case defaultIndex = "Default"
        case name = "Name"
        case date = "Date"
    }
    
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
        let bVM = BoardViewModel(player: player, ogsClient: ogsClient, isAIAllowed: { [weak self] in
            // Must capture weakly and dynamically evaluate
            return self?.isAIAvailable == true
        })
        self.boardVM = bVM
        self.ogsGame = OGSGameViewModel(ogsClient: ogsClient, player: player, timeControl: timeControl)
        
        // Audio Binding
        bVM.onPlaySound = { [weak self] type in
            self?.playSound(type)
        }
        
        // Initialize Audio
        setupAudio()
        
        // Defer process launch until initialization finishes. Engine state belongs to the main queue;
        // model loading and analysis run in the child process, and pipe I/O uses its own queues.
        DispatchQueue.main.async {
            KataGoEngine.shared.start()
        }
        
        // Auto-load previously opened local games directory
        if let bookmarkData = UserDefaults.standard.data(forKey: "folderURLBookmark") {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if !isStale {
                    print("💾 Restoring Local Library: \(url.lastPathComponent)")
                    AppSettings.shared.folderURL = url
                    self.loadFolder(url, autoSelect: true)
                }
            } catch {
                print("❌ Failed to resolve folder bookmark: \(error)")
            }
        }
        
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
                guard let self, gid == self.ogsClient.activeGameID,
                      self.ogsClient.isConnected || gid == 999999 else { return }
                let isOnline = (gid != nil)
                
                // Only change mode if we are actually entering/leaving a game
                // If we are already online (restored), and gid is nil, that's fine (Lobby).
                // Wait: If gid becomes nil (game ends), we stay in Online Mode (Lobby).
                // If gid becomes non-nil, we are definitely in Online Mode.
                
                if let id = gid {
                    self.isOnlineMode = true
                } 
                // Note: We DO NOT auto-switch to Local Mode just because activeGameID is nil.
                // The user must explicitly disconnect or switch modes.
                // However, we DO want to persist the "Online" state.
                
                // Let's defer "Offline" switch to user action, OR ensure we track "Intended Mode".
                // Current logic: If activeGameID is valid, we are Online.
                // If activeGameID is nil, we might be consistently in Online Lobby.
                
                if isOnline {
                     self.isOnlineMode = true
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
            print("⏳ Persistence detected. Connection deferred to handleStartup().")
        }
        
        // Auto-Connect when switching tab to Online
        $rightPanelTab
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] tab in
                guard let self = self, self.rightPanelTab == tab else { return }
                
                if tab == .ai {
                    // Kickstart analysis immediately if user views AI tab
                    self.boardVM?.triggerFullGameAnalysis()
                } else if tab == .online {
                    if self.isOnlineMode { return } // Already online
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
                    
                } else if tab == .local {
                    if !self.isOnlineMode { return } // Already offline
                    print("🚪 Switching to Local Mode")
                    self.ogsClient.disconnect()
                    self.isOnlineMode = false
                    UserDefaults.standard.set(false, forKey: "isOnlineModePersistent")
                    
                    // 3. Restore or Start New
                    self.player.clear() // Ensure clean slate first
                    self.boardVM?.resetToEmpty() // Also reset the view model properly to clear ghost stones
                    
                    if let snap = self.savedLocalSnapshot {
                        print("♻️ Restoring Local Game...")
                        self.player.restoreSnapshot(snap)
                        // Sync BoardVM after restoring
                        self.boardVM?.syncState()
                    } else if AppSettings.shared.startGameOnLaunch {
                        print("✨ Starting New Game (StartOnLaunch)")
                        self.startInstantGame()
                    }
                }
                // If tab == .ai, do nothing to the game state.
            }.store(in: &cancellables)
        // This prevents the "confusing local game" issue when waking up in online mode.
        // FIX: Always attempt to load the folder in background so it's ready if we switch to Local.
        if let url = AppSettings.shared.folderURL {
             print("📂 Auto-loading saved folder: \(url.path)")
             // Update status before calling (function will overwrite it, but good for tracing)
             self.loadingStatus = "Startup: Loading Folder..."
             loadFolder(url, autoSelect: !wasOnline)
        } else {
             self.loadingStatus = "Startup: No Folder Set"
        }
        
        if !wasOnline {
            // Enhanced Startup Logic: Prioritize Folder > Instant Game
            // Only start "Instant Game" if we are definitively NOT restoring online mode.
            if AppSettings.shared.folderURL == nil && AppSettings.shared.startGameOnLaunch {
                self.loadingStatus = "Startup: Instant Game"
                self.startInstantGame()
            }
        } else {
            // If we ARE restoring Online Mode, ensure UI reflects it
            self.rightPanelTab = .online
            self.loadingStatus = "Startup: Resuming Online" // (This might be overwritten by loadFolder's status, which is fine)
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
    
    // Defer network operations until View is active
    func handleStartup() {
        let wasOnline = UserDefaults.standard.bool(forKey: "isOnlineModePersistent")
        if wasOnline {
            print("🚀 Executing Startup Connection (Persistent Mode)")
            // Force delay to ensure socket/network stack is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.isOnlineMode else { return }
                self.ogsClient.connect()
            }
        }
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
        
        switch type {
        case .place:
            let delay = (viewMode == .view3D && AppSettings.shared.showDropInAnimation) ? 0.15 : 0.0
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let p = self?.clickPlayer else { return }
                    if p.isPlaying { p.stop(); p.currentTime = 0 }
                    p.play()
                }
            } else {
                guard let player = clickPlayer else { return }
                if player.isPlaying {
                    player.stop()
                    player.currentTime = 0
                }
                player.play()
            }
            
        case .captureSingle, .captureMultiple:
            // In 3D mode, the SceneManager3D handles capture sounds via precise physics collisions.
            if viewMode == .view3D { return }
            
            // Delay capture sounds slightly so they sound like they are hitting the bowl
            let delayTime: TimeInterval = type == .captureSingle ? 0.25 : 0.4
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delayTime) { [weak self] in
                guard let self = self else { return }
                let player = type == .captureSingle ? self.captureSinglePlayer : self.captureMultiPlayer
                guard let p = player else { return }
                
                if p.isPlaying {
                    p.stop()
                    p.currentTime = 0
                }
                p.play()
            }
        }
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
        // FIX: Do not auto-advance if we are in Online Mode (Chat/Spectating) or AI Analysis mode
        guard !isOnlineMode, rightPanelTab != .ai, !player.isPlaying, player.currentIndex == player.maxIndex else { return }
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
                    guard let self, let root = rootJson else { return }
                    let data = (root["gamedata"] as? [String: Any]) ?? root
                    NotificationCenter.default.post(self.ogsClient.makeGameNotification(
                        name: NSNotification.Name("OGSGameDataReceived"), userInfo: ["gameData": data]))
                }
            } else {
                NSLog("[OGS-UI] ❌ Accept Failed for ID \(id): \(error?.localizedDescription ?? "Unknown")")
                // Only a missing challenge justifies removing it. Timeouts, cancellation,
                // and authentication failures do not establish that it disappeared.
                if let error, case OGSHTTPError.status(404) = error {
                    self.ogsClient.forceRemoveChallenge(id: id)
                }
            }
        }
    }
    
    func resumeOnlineGame(id: Int) {
        // SIMULATION INTERCEPT
        if id == 999999 {
            simulateOGSLoad()
            return
        }

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
            guard let self, let root = rootJson else { return }
            let data = (root["gamedata"] as? [String: Any]) ?? root
            NotificationCenter.default.post(self.ogsClient.makeGameNotification(
                name: NSNotification.Name("OGSGameDataReceived"), userInfo: ["gameData": data]))
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
        guard ogsClient.acceptsGameNotification(notification) else { return }
        guard let userInfo = notification.userInfo, let gameData = userInfo["gameData"] as? [String: Any] else { return }
        
        // NSLog("[OGS-DEBUG] handleOGSGameLoad Entry. isRequestingUndo: \(ogsClient.isRequestingUndo)")
        // print("🔥🔥🔥 BUILD VERIFICATION: v4.886 - TRACER ACTIVE 🔥🔥🔥")
        
        let gameID = robustInt(gameData["game_id"]) ?? robustInt(gameData["id"]) ?? 0
        // NSLog("[OGS-DEBUG] 🚨 AppModel received GameData for \(gameID). Active: \(ogsClient.activeGameID ?? -1)")
        guard gameID == ogsClient.activeGameID else {
            NSLog("[OGS-DEBUG] ❌ Game ID Mismatch. Ignoring.")
            return
        }
        
        // Scoring can change without a new move/version, so apply it before replay guards.
        ogsClient.applyScoringSnapshot(gameData)

        // FORCE SYNC: Always reload board when full game data is received
        // This ensures undo/redo states are correctly reflected without caching issues
        if true {
             // AUTO-SWITCH to Online Mode if data arrives
             if !self.isOnlineMode {
                 NSLog("[OGS-SYNC] 🔀 Auto-Switching to Online Mode due to Game Data")
                 self.isOnlineMode = true
             }
             
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
            
            // SIMULATION OVERRIDE: If ID is 999999, bypass version guards
            if gameID == 999999 {
                NSLog("[OGS-SYNC] 🧪 SIMULATION DETECTED. Bypassing version guards.")
            } else {
                 // STRICT MONOTONICITY: Only accept NEWER versions
                let engineMoves = boardVM?.engine.maxIndex ?? 0
                let isUndo = moves.count < engineMoves
                
                if incomingVersion <= engineVersion && !isUndo && engineMoves > 0 && userInfo["reconcileMoves"] as? Bool != true {
                    return
                }
            }
            
            // Force reset undo flag if we accepted a valid packet
             ogsClient.isRequestingUndo = false
            
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
             
             let stateVersion = robustInt(gameData["state_version"]) ?? robustInt(gameData["move_number"]) ?? 0
             
             boardVM?.initializeOnlineGame(width: width, height: height, initialStones: initialStones, nextPlayer: initialTurnColor, stateVersion: stateVersion)
             
             let moveHistory = gameData["moves"] as? [[Any]] ?? []
             let handicap = robustInt(gameData["handicap"]) ?? 0
             let isFreeHandicap = (gameData["free_handicap_placement"] as? Bool) ?? false
             // Heuristic: If handicap > 0 but initial_state is empty, assume moves contain placement
             let movesContainHandicap = isFreeHandicap || (handicap > 0 && initialStones.isEmpty)
             
             var turnColor = initialTurnColor // FIX: Restore variable
             
             for (idx, m) in moveHistory.enumerated() {
                 if m.count >= 2, let x = robustInt(m[0]), let y = robustInt(m[1]) {
                     
                     // Determine Color
                     let colorToPlay: Stone
                     if movesContainHandicap && idx < handicap {
                         colorToPlay = .black
                     } else {
                         colorToPlay = turnColor
                     }
                     
                     if x == -1 && y == -1 { // OGS represents passes as [-1, -1] in move history
                         // Handle Pass
                         boardVM?.handleRemotePass(color: colorToPlay)
                     } else if x >= 0 && y >= 0 {
                         boardVM?.handleRemoteMove(x: x, y: y, color: colorToPlay)
                     }
                     
                     // Prepare Next Turn
                     if movesContainHandicap && idx < handicap {
                         // Inside setup phase:
                         // If this was the last setup stone, next is White.
                         // Otherwise, stay Black.
                         if idx == handicap - 1 {
                             turnColor = .white
                         } else {
                             turnColor = .black
                         }
                     } else {
                         // Normal Play: Alternate
                         turnColor = colorToPlay.opponent
                     }
                 }
             }
             
             ogsClient.lastKnownRemoteMoveNumber = moveHistory.count

             // Update Player Names
             let players = gameData["players"] as? [String: Any]
             let blackObj = players?["black"] as? [String: Any]
             let whiteObj = players?["white"] as? [String: Any]
             
             self.ogsClient.blackPlayerName = blackObj?["username"] as? String ?? "Black"
             self.ogsClient.blackPlayerID = robustInt(blackObj?["id"])
             
             self.ogsClient.whitePlayerName = whiteObj?["username"] as? String ?? "White"
             self.ogsClient.whitePlayerID = robustInt(whiteObj?["id"])
             
             // FIX: Eagerly set currentPlayerID after parsing historical moves so we don't lock the UI waiting for a clock packet. 
             // We use `turnColor` which accurately tracks the next player considering handicap logic.
             if turnColor == .black {
                 self.ogsClient.currentPlayerID = self.ogsClient.blackPlayerID
             } else {
                 self.ogsClient.currentPlayerID = self.ogsClient.whitePlayerID
             }
             
             // Sync Captures to OGSClient (Engine Authority)
             // FIX: Engine 'blackStonesCaptured' means "number of black stones removed from board" (Prisoners for White)
             self.ogsClient.blackCaptures = boardVM?.engine.whiteStonesCaptured ?? 0
             self.ogsClient.whiteCaptures = boardVM?.engine.blackStonesCaptured ?? 0
             
             NSLog("[OGS-SYNC] 💀 Sync Check: Removed Stones Count = \(self.ogsClient.removedStones.count). Phase: \(self.ogsClient.phase ?? "nil")")
             
             // Share scoring decoding with socket updates; finished games retain their marks.
             self.ogsClient.applyScoringSnapshot(gameData)

        }
        
        boardVM?.syncState()
        self.objectWillChange.send()
    }
    
    // MARK: - Local Verification / Simulation
    func simulateOGSLoad() {
        NSLog("[OGS-SIM] 🧪 Starting Offline OGS Simulation...")
        
        let dummyMoves: [[Any]] = [
            [15, 3], [3, 15], [2, 2], [16, 16], [3, 2], [16, 2] // Added [3, 2] for dead stone test
        ]
        
        // Mock OGS "gamedata" payload
        let mockData: [String: Any] = [
            "game_id": 999999,
            "phase": "stone removal", // TRIGGER SCORING MODE
            "name": "Simulation Game",
            "width": 19,
            "height": 19,
            "moves": dummyMoves,
            "state_version": 100,
            "initial_player": "black",
            "removed_stones": ["cc", "dc"], // 3-3 and 4-3 marked dead
            "players": [ 
                "black": ["id": 101, "username": "SimBlack", "ranking": 30],
                "white": ["id": 102, "username": "SimWhite", "ranking": 29]
            ],
            "time_control": ["system": "byoyomi", "main_time": 600]
        ]
        
        // Manually trigger the notification to simulate internal dispatch
        // We set activeGameID first so the guard in handleOGSGameLoad passes
        self.ogsClient.activeGameID = 999999
        self.ogsClient.playerID = 101 // Pretend we are Black
        
        // Ensure we aren't blocked by stale version logic
        self.boardVM?.engine.highestKnownStateVersion = 0
        
        let notification = ogsClient.makeGameNotification(name: NSNotification.Name("OGSGameDataReceived"),
            userInfo: ["gameData": mockData], offlineSimulation: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(notification)
            NSLog("[OGS-SIM] 📨 Mock Data Posted.")
        }
    }
    
    private func handleOGSMoveUpdate(_ notification: Notification) {
        guard ogsClient.acceptsGameNotification(notification),
              let info = notification.userInfo, let engine = boardVM?.engine else { return }
        if let id = robustInt(info["game_id"]), id != ogsClient.activeGameID { return }
        guard currentActiveInternalGameID == ogsClient.activeGameID, isOnlineMode else {
            ogsClient.requestMoveResync(); return
        }
        guard let number = robustInt(info["move_number"]), number > 0 else {
            ogsClient.requestMoveResync(); return
        }
        let position: (Int, Int)?
        if let move = info["move"] as? [Any], move.count >= 2,
           let x = robustInt(move[0]), let y = robustInt(move[1]) { position = (x, y) }
        else if let move = info["move"] as? String {
            position = (move == ".." || move == "pass") ? (-1, -1) : SGFCoordinates.parse(move)
        } else { position = nil }
        guard let (x, y) = position else { ogsClient.requestMoveResync(); return }

        let color: Stone
        if let id = robustInt(info["player_id"]) {
            if id == ogsClient.blackPlayerID { color = .black }
            else if id == ogsClient.whitePlayerID { color = .white }
            else { ogsClient.requestMoveResync(); return }
        } else {
            // History knows the initial player and any handicap placements; avoid parity guesses.
            color = engine.playerToMove(at: number - 1)
        }
        let captures = engine.blackStonesCaptured + engine.whiteStonesCaptured
        switch engine.applyOnlineMove(color: color, x: x, y: y, moveNumber: number) {
        case .duplicate: return
        case .needsResync: ogsClient.requestMoveResync()
        case .applied:
            // Capture counters describe the viewed position while reviewing history.
            guard engine.currentIndex == engine.maxIndex else { return }
            ogsClient.blackCaptures = engine.whiteStonesCaptured
            ogsClient.whiteCaptures = engine.blackStonesCaptured
            let captured = engine.blackStonesCaptured + engine.whiteStonesCaptured - captures
            if x == -1 && y == -1 { SoundManager.shared.play("pass") }
            else if captured > 1 { playSound(.captureMultiple) }
            else if captured == 1 { playSound(.captureSingle) }
            else if color != ogsClient.playerColor { playSound(.place) }
        }
    }

    func selectGame(_ g: SGFGameWrapper) { 
        selection = g
        boardVM?.loadGame(g) 
        // Persist as last played
        AppSettings.shared.lastPlayedGameURL = g.url
        // Kickstart AI for the first view
        boardVM?.syncState()
    }
    func promptForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Load Games"
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                // 1. Persist (Only when user explicitly chooses)
                AppSettings.shared.folderURL = url
                // 2. Load
                self?.loadFolder(url)
            }
        }
    }
    
    func loadFolder(_ url: URL, autoSelect: Bool = true) {
        // 2. Clear current library
        self.games = []
        self.selection = nil
        self.loadingStatus = "Loading Folder..." 
        
        // 3. Background Load
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async { self.loadingStatus = "Requesting Access..." }
            
            // Security Scope
            let accessing = url.startAccessingSecurityScopedResource()
            if !accessing {
                DispatchQueue.main.async { 
                    self.loadingStatus = "❌ Access Denied (Security Scope)" 
                    AppSettings.shared.folderURL = nil
                }
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            DispatchQueue.main.async { self.loadingStatus = "Reading Directory..." }
            
            let fm = FileManager.default
            var foundURLs: [URL] = []
            
            do {
                // Check read access
                let _ = try fm.contentsOfDirectory(atPath: url.path)
                
                let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
                let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
                
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: options) {
                    for case let fileURL as URL in enumerator {
                       if fileURL.pathExtension.lowercased() == "sgf" {
                           foundURLs.append(fileURL)
                       }
                    }
                }
            } catch {
                let msg = "❌ Read Error: \(error.localizedDescription)"
                DispatchQueue.main.async { self.loadingStatus = msg }
                return
            }
            
            if foundURLs.isEmpty {
                 DispatchQueue.main.async { self.loadingStatus = "⚠️ Folder is empty (0 SGF files)." }
                 return
            }
            
            DispatchQueue.main.async { self.loadingStatus = "Found \(foundURLs.count) files. Parsing..." }
            
            // Sort & Shuffle
            foundURLs.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            if AppSettings.shared.shuffleGameOrder { foundURLs.shuffle() }
            
            // Parse Code
            var loaded: [SGFGameWrapper] = []
            var parseErrors = 0
            var hasAutoSelected = false
            let batchSize = 25
            
            for (index, sgfURL) in foundURLs.enumerated() {
                do {
                    let data = try Data(contentsOf: sgfURL)
                    let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    let tree = try SGFParser.parse(text: text)
                    let game = SGFGame.from(tree: tree)
                    loaded.append(SGFGameWrapper(url: sgfURL, game: game))
                    
                    if loaded.count == batchSize {
                        let batch = loaded
                        DispatchQueue.main.async {
                            self.games = batch
                            self.loadingStatus = "Loaded \(batch.count)..."
                            
                            if autoSelect && !hasAutoSelected {
                                hasAutoSelected = true
                                var checkAutoPlay = AppSettings.shared.startGameOnLaunch
                                if let lastURL = AppSettings.shared.lastPlayedGameURL,
                                   let restored = batch.first(where: { $0.url == lastURL }) {
                                    self.selectGame(restored)
                                } else if let first = batch.first {
                                    self.selectGame(first)
                                } else {
                                    checkAutoPlay = false
                                }
                                if checkAutoPlay && self.selection != nil { 
                                     DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.boardVM?.startAutoPlay() }
                                }
                            }
                        }
                    } else if loaded.count > batchSize, loaded.count % 100 == 0 {
                        let batch = loaded
                        DispatchQueue.main.async { self.games = batch; self.loadingStatus = "Loaded \(batch.count)..." }
                    }
                } catch {
                    print("Failed to parse \(sgfURL.lastPathComponent): \(error)")
                    parseErrors += 1
                }
            }
            
            // 4. Update Main Actor (Final Flush)
            DispatchQueue.main.async {
                self.games = loaded
                
                if autoSelect && !hasAutoSelected {
                    var checkAutoPlay = AppSettings.shared.startGameOnLaunch
                    if let lastURL = AppSettings.shared.lastPlayedGameURL,
                       let restored = loaded.first(where: { $0.url == lastURL }) {
                        self.selectGame(restored)
                    } else if let first = loaded.first {
                        self.selectGame(first)
                    } else {
                        checkAutoPlay = false
                    }
                    if checkAutoPlay && self.selection != nil { 
                         DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.boardVM?.startAutoPlay() }
                    }
                }
                
                if loaded.isEmpty { self.loadingStatus = "❌ Failed to parse ALL files." }
                else if parseErrors > 0 { self.loadingStatus = "✅ Loaded \(loaded.count) games. (\(parseErrors) failed)" }
                else { self.loadingStatus = "✅ Loaded \(loaded.count) games." }
                
                print("📚 Loaded \(loaded.count) games from \(url.lastPathComponent)")
            }
        }
    }
}
