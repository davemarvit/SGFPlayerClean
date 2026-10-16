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
    @Published var ogsClient: OGSClient
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
    
    @Published var aiAnalysisEnabled = false { didSet { refreshAIPolicy() } }
    var aiUnavailableReason: String? {
        if isChangingMode { return "Changing board…" }
        if mode == .playOnline { return "AI is unavailable in Play Online." }
        if ogsClient.hasOngoingAccountGame { return "AI is unavailable while you have an ongoing online game." }
        if boardVM?.localScoringVisible == true { return "Resume play or close scoring to use AI." }
        if mode == .observe && (ogsClient.activeGameID == nil || boardVM?.isOnlineContext != true ||
            (ogsClient.blackPlayerID ?? 0) <= 0 || (ogsClient.whitePlayerID ?? 0) <= 0) {
            return "Choose a game and wait for its players to load."
        }
        return nil
    }
    var isAIAvailable: Bool { aiAnalysisEnabled && aiUnavailableReason == nil }
    private var lastAIAvailability = false
    private var isChangingMode = false
    private func refreshAIPolicy(restartAnalysis: Bool = false) {
        let available = isAIAvailable
        guard available != lastAIAvailability else {
            if available && restartAnalysis {
                boardVM?.syncState()
                boardVM?.triggerFullGameAnalysis()
            }
            return
        }
        lastAIAvailability = available
        boardVM?.updateAnalysisPermission()
        objectWillChange.send()
    }
    
    // UI Persistence
    @Published var showRightPanel: Bool = UserDefaults.standard.object(forKey: "showRightPanel") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showRightPanel, forKey: "showRightPanel") }
    }
    
    @Published var mode: AppMode = .localPlay {
        didSet { if mode != oldValue { changeMode(from: oldValue) } }
    }
    
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
    private struct SavedBoard {
        let snapshot: SGFPlayer.LocalGameSnapshot
        let selection: SGFGameWrapper?
        let analysisID: String
        let viewState: BoardViewModel.LocalViewState?
    }
    private var savedBoards: [AppMode: SavedBoard] = [:]
    private var onlineBoards: [AppMode: Int] = [:]
    
    // Audio
    enum SoundType { case place, captureSingle, captureMultiple }
    private var audioGeneration = 0
    private var clickPlayer: AVAudioPlayer?
    private var captureSinglePlayer: AVAudioPlayer?
    private var captureMultiPlayer: AVAudioPlayer?
    // private var stoneClickPlayer: AVAudioPlayer? // Replaced by above

    init(ogsClient injectedClient: OGSClient? = nil, defaultMode: AppMode = .localPlay) {
        let savedMode = UserDefaults.standard.string(forKey: "lastAppMode").flatMap(AppMode.init(rawValue:))
        #if SGF_OFFLINE_REVIEW
        // The offline build must never restore an online workspace.
        let startupMode = savedMode.flatMap { $0.usesOGS ? nil : $0 } ?? .localPlay
        #else
        let startupMode = savedMode ?? (UserDefaults.standard.bool(forKey: "isOnlineModePersistent") ? .playOnline : defaultMode)
        #endif
        _mode = Published(initialValue: startupMode)
        isOnlineMode = startupMode.usesOGS
        UserDefaults.standard.set(startupMode.rawValue, forKey: "lastAppMode")
        UserDefaults.standard.set(startupMode.usesOGS, forKey: "isOnlineModePersistent")
        self.ogsClient = injectedClient ?? OGSClient()
        self.ogsClient.observationOnly = startupMode != .playOnline
        #if SGF_OFFLINE_REVIEW || SGF_OGS_REVIEW
        UserDefaults.standard.register(defaults: ["startGameOnLaunch": true])
        #endif
        let bVM = BoardViewModel(player: player, ogsClient: ogsClient, isAIAllowed: { [weak self] in
            // Must capture weakly and dynamically evaluate
            return self?.isAIAvailable == true
        })
        bVM.canNavigateReview = { [weak self] in self?.mode == .review }
        bVM.canPreviewAnalysis = { [weak self] in self?.mode == .review && self?.isAIAvailable == true }
        bVM.canEditLocally = { [weak self] in self?.mode == .localPlay }
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
                }
            } catch {
                print("❌ Failed to resolve folder bookmark: \(error)")
            }
        }
        
        let wasOnline = startupMode.usesOGS

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

        ogsClient.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            DispatchQueue.main.async { [weak self] in self?.refreshAIPolicy() }
        }.store(in: &cancellables)
        
        setupAudio()
        setupOGSObservers()
        // willTerminate is synchronous on the main thread. Do not defer the flush
        // to a queue that may never run after the app exits.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { _ in KataGoEngine.shared.stop() }.store(in: &cancellables)
        
        // CONDITION: Only connect if we restore Online Mode
        if wasOnline {
            print("⏳ Persistence detected. Connection deferred to handleStartup().")
        }
        
        // This prevents the "confusing local game" issue when waking up in online mode.
        // FIX: Always attempt to load the folder in background so it's ready if we switch to Local.
        if let url = AppSettings.shared.folderURL {
             print("📂 Auto-loading saved folder: \(url.path)")
             // Update status before calling (function will overwrite it, but good for tracing)
             self.loadingStatus = "Startup: Loading Folder..."
             // Loading the library must not replace a restored Local Play tab.
             loadFolder(url, autoSelect: startupMode == .review || (savedMode == nil && !wasOnline))
        } else {
             self.loadingStatus = "Startup: No Folder Set"
        }
        
        if !wasOnline {
            // Enhanced Startup Logic: Prioritize Folder > Instant Game
            // Only start "Instant Game" if we are definitively NOT restoring online mode.
            if startupMode == .localPlay && AppSettings.shared.folderURL == nil && AppSettings.shared.startGameOnLaunch {
                self.loadingStatus = "Startup: Instant Game"
                self.startInstantGame()
            }
        } else {
            self.loadingStatus = "Startup: Resuming Online" // (This might be overwritten by loadFolder's status, which is fine)
        }
        
        ogsClient.observationOnly = mode != .playOnline
        // Master mute/volume applies to every stone player, including active clips.
        let settings = AppSettings.shared
        Publishers.CombineLatest3(settings.$stoneVolume, settings.$masterVolume, settings.$isMuted)
            .sink { [weak self] stone, master, muted in
                guard let self else { return }
                let silent = muted || master == 0
                if silent { self.audioGeneration += 1 }
                for player in [self.clickPlayer, self.captureSinglePlayer, self.captureMultiPlayer].compactMap({ $0 }) {
                    player.volume = silent ? 0 : Float(stone * master)
                    if silent { player.stop(); player.currentTime = 0 }
                }
            }.store(in: &cancellables)
    }
    
    // Defer network operations until View is active
    func handleStartup() {
        if mode.usesOGS {
            print("🚀 Executing Startup Connection (Persistent Mode)")
            // Force delay to ensure socket/network stack is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.isOnlineMode else { return }
                self.ogsClient.connect()
            }
        }
    }
    
    private func startInstantGame() {
        self.boardVM?.resetToEmpty()
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
    
    private func saveCurrentBoard(for previous: AppMode) {
        if previous.usesOGS {
            if let id = ogsClient.activeGameID { onlineBoards[previous] = id }
        } else {
            savedBoards[previous] = SavedBoard(snapshot: player.createSnapshot(), selection: selection,
                                             analysisID: KataGoEngine.shared.currentGameId, viewState: boardVM?.localViewState())
        }
    }

    private func changeMode(from previous: AppMode) {
        isChangingMode = true
        defer { isChangingMode = false; refreshAIPolicy(restartAnalysis: true) }
        player.pause()
        saveCurrentBoard(for: previous)
        if previous.usesOGS { ogsClient.leaveViewedGame() }
        isCreatingChallenge = false
        isTypingInChat = false
        currentActiveInternalGameID = nil
        ogsClient.observationOnly = mode != .playOnline
        isOnlineMode = mode.usesOGS
        UserDefaults.standard.set(mode.rawValue, forKey: "lastAppMode")
        UserDefaults.standard.set(mode.usesOGS, forKey: "isOnlineModePersistent")
        boardVM?.resetToEmpty()
        selection = nil
        if mode.usesOGS {
            ogsClient.connect()
            if let id = onlineBoards[mode] { resumeOnlineGame(id: id) }
        } else if let saved = savedBoards[mode] {
            selection = saved.selection
            player.restoreSnapshot(saved.snapshot)
            _ = KataGoEngine.shared.loadAnalysisCache(for: saved.analysisID, game: player)
            if let state = saved.viewState { boardVM?.restoreLocalViewState(state) }
            if mode == .review { boardVM?.prepareReviewTreeFromCurrentPosition(info: selection?.game.info) }
            boardVM?.syncState()
        } else if mode == .localPlay { startInstantGame() }
        else if mode == .review { boardVM?.prepareReviewTreeFromCurrentPosition() }
    }

    var hasLocalGameToReplace: Bool {
        let snapshot = mode == .localPlay ? player.createSnapshot() : savedBoards[.localPlay]?.snapshot
        return snapshot.map { !$0.moves.isEmpty || !$0.setup.isEmpty } ?? false
    }

    func newLocalGame() {
        mode = .localPlay
        startInstantGame()
        boardVM?.syncState()
    }

    var showsAnalysisWorkspace: Bool { isAIAvailable || (mode == .review && boardVM?.reviewTree != nil) }

    func saveReviewSGF() {
        guard mode == .review, let vm = boardVM, let data = vm.reviewSGFData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]
        panel.title = "Save game with variations"
        let name = (vm.reviewTree?.filename as NSString?)?.deletingPathExtension ?? "Game"
        panel.nameFieldStringValue = name + "-review.sgf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic) }
            catch { vm.reviewTreeError = "Could not save the SGF: " + error.localizedDescription }
        }
    }

    func copyCurrentBoard(to destination: AppMode) {
        guard !destination.usesOGS, destination != mode else { return }
        savedBoards[destination] = SavedBoard(snapshot: player.createSnapshot(), selection: selection,
                                              analysisID: KataGoEngine.shared.currentGameId, viewState: boardVM?.localViewState(includeTree: false))
        mode = destination
    }

    func showOnlineBrowser() {
        if let id = ogsClient.activeGameID { onlineBoards[mode] = id }
        ogsClient.leaveViewedGame()
        boardVM?.resetToEmpty()
        currentActiveInternalGameID = nil
    }

    var returnToOnlineGameID: Int? {
        if let id = onlineBoards[mode] { return id }
        return mode == .playOnline ? resumableGameID : nil
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
        let v = Float(AppSettings.shared.effectiveStoneVolume)
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
        guard !AppSettings.shared.soundIsSilent else { return }
        let generation = audioGeneration
        switch type {
        case .place:
            let delay = (viewMode == .view3D && AppSettings.shared.showDropInAnimation) ? 0.15 : 0.0
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.audioGeneration == generation,
                          !AppSettings.shared.soundIsSilent, let p = self.clickPlayer else { return }
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
            // The played stone still lands on the board. Capture audio follows the move,
            // rather than depending on SceneKit reporting a sufficiently strong lid collision.
            if viewMode == .view3D { playSound(.place) }
            
            // Delay capture sounds slightly so they sound like they are hitting the bowl
            let delayTime: TimeInterval = type == .captureSingle ? 0.25 : 0.4
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delayTime) { [weak self] in
                guard let self, self.audioGeneration == generation,
                      !AppSettings.shared.soundIsSilent else { return }
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
    private func robustInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }
    
    func joinOnlineGame(id: Int) {
        guard mode == .playOnline else { return }
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
                self.ogsClient.myActiveGames.insert(gid)
                if self.mode == .playOnline { self.resumeOnlineGame(id: gid) }
            } else {
                self.ogsClient.lastError = error?.localizedDescription ?? "Could not accept this challenge."
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
        guard mode.usesOGS else { return }
        onlineBoards[mode] = id
        ogsClient.leaveViewedGame()
        // The observation review must treat every entered ID as an actual game.
        #if !SGF_OGS_REVIEW
        // SIMULATION INTERCEPT
        if id == 999999 {
            simulateOGSLoad()
            return
        }
        #endif

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
        guard mode.usesOGS, ogsClient.acceptsGameNotification(notification), let info = notification.userInfo,
              let data = info["gameData"] as? [String: Any], let boardVM else { return }
        let id = robustInt(data["game_id"]) ?? robustInt(data["id"]) ?? ogsClient.activeGameID
        guard let id, id == ogsClient.activeGameID else { return }
        guard let snapshot = OGSGameSnapshot(data) else {
            ogsClient.lastError = "Cannot load this game history: incomplete, malformed, or unsupported board data."
            return
        }
        let newGame = currentActiveInternalGameID != id || !boardVM.isOnlineContext
        switch boardVM.engine.reconcileOnlineSnapshot(snapshot, recovery: info["reconcileMoves"] as? Bool == true, newGame: newGame) {
        case .stale:
            if info["reconcileMoves"] as? Bool == true {
                ogsClient.lastError = "OGS returned an older game state. Reconnect to refresh."
            }
            return
        case .needsResync: ogsClient.requestMoveResync(); return
        case .applied: break
        }
        currentActiveInternalGameID = id
        onlineBoards[mode] = id
        isOnlineMode = true
        ogsClient.applyAcceptedGameData(data)
        if ogsClient.isAccountGameParticipant && !ogsClient.isGameFinished { ogsClient.myActiveGames.insert(id) }
        ogsClient.isRequestingUndo = false
        ogsClient.isReconcilingMoves = false
        let next = boardVM.engine.playerToMove(at: boardVM.engine.maxIndex)
        ogsClient.currentPlayerID = next == .black ? ogsClient.blackPlayerID : ogsClient.whitePlayerID
        // The sidebar/lids follow the viewed board, not scoring prisoners or a later clock packet.
        boardVM.finishOnlineGameLoad(gameID: id)
        refreshAIPolicy(restartAnalysis: true)
        objectWillChange.send()
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
        case .duplicate:
            engine.recordOnlineVersion(robustInt(info["state_version"]))
            return
        case .needsResync: ogsClient.requestMoveResync()
        case .applied:
            engine.recordOnlineVersion(robustInt(info["state_version"]))
            let next = engine.playerToMove(at: engine.maxIndex)
            ogsClient.currentPlayerID = next == .black ? ogsClient.blackPlayerID : ogsClient.whitePlayerID
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
        mode = .review
        selection = g
        boardVM?.loadGame(g) 
        // Persist as last played
        AppSettings.shared.lastPlayedGameURL = g.url
        // Kickstart AI for the first view
        boardVM?.syncState()
        boardVM?.triggerFullGameAnalysis()
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
                            
                            if autoSelect && !hasAutoSelected && !self.mode.usesOGS {
                                hasAutoSelected = true
                                if let lastURL = AppSettings.shared.lastPlayedGameURL,
                                   let restored = batch.first(where: { $0.url == lastURL }) {
                                    self.selectGame(restored)
                                } else if let first = batch.first {
                                    self.selectGame(first)
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
                
                if autoSelect && !hasAutoSelected && !self.mode.usesOGS {
                    if let lastURL = AppSettings.shared.lastPlayedGameURL,
                       let restored = loaded.first(where: { $0.url == lastURL }) {
                        self.selectGame(restored)
                    } else if let first = loaded.first {
                        self.selectGame(first)
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
