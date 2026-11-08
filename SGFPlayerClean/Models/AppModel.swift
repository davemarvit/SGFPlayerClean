// ========================================================
// FILE: ./Models/AppModel.swift
// VERSION: v4.886 (Clean Rebuild)
// ========================================================
import Foundation
import SwiftUI
import Combine
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("viewMode") var viewMode: ViewMode = .view2D
    let recenter3DRequested = PassthroughSubject<Void, Never>()
    @Published var games: [SGFGameWrapper] = []
    
    var sortedGames: [SGFGameWrapper] {
        guard gameSortMethod != .defaultIndex else { return games }
        func key(_ wrapper: SGFGameWrapper) -> String {
            let info = wrapper.game.info
            let value: String?
            switch gameSortMethod {
            case .name: value = info.playerBlack
            case .whitePlayer: value = info.playerWhite
            case .date, .oldestDate: value = info.date
            case .defaultIndex: value = nil
            }
            return value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        // Preserve collection order for ties; missing metadata always goes last.
        return games.enumerated().sorted { left, right in
            let lhs = key(left.element), rhs = key(right.element)
            if lhs.isEmpty != rhs.isEmpty { return !lhs.isEmpty }
            let comparison = lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: .current)
            if comparison == .orderedSame { return left.offset < right.offset }
            return gameSortMethod == .date ? comparison == .orderedDescending : comparison == .orderedAscending
        }.map(\.element)
    }

    @Published var selection: SGFGameWrapper? = nil
    @Published var player = SGFPlayer()
    @Published var ogsClient: OGSClient
    @Published var layoutVM = LayoutViewModel()
    @Published var timeControl = TimeControlManager()
    @Published var ogsGame: OGSGameViewModel?
    @Published var isOnlineMode: Bool = false
    @Published var isCreatingChallenge: Bool = false
    @Published var challengeAcceptanceError: String?
    @Published private(set) var isAcceptingChallenge = false
    @Published var showDebugDashboard: Bool = false
    @Published var boardVM: BoardViewModel?
    @Published var isTypingInChat: Bool = false // Global flag to disable shortcuts
    @Published var loadingStatus: String = "Idle" // Diagnostic Status
    @Published var lastDebugLog: String = "Waiting for Move..."
    
    @Published var aiAnalysisEnabled = false { didSet { refreshAIPolicy() } }
    var aiUnavailableReason: String? {
        if !AppSettings.shared.analysisEnabled { return "Analysis is turned off in Settings." }
        if isChangingMode { return "Changing board…" }
        if mode == .playOnline || mode == .localPlay { return "AI results are hidden until the game finishes." }
        if unfinishedLocalAnalysisIDs.contains(where: { analysisEngine.currentGameId == $0 || analysisEngine.currentGameId.hasPrefix($0 + "#") }) { return "Finish the local game to reveal its AI review." }
        if ogsClient.hasOngoingAccountGame { return "AI is unavailable while you have an ongoing online game." }
        if boardVM?.localScoringVisible == true { return "Resume play or close scoring to use AI." }
        if mode == .observe && (ogsClient.activeGameID == nil || boardVM?.isOnlineContext != true ||
            (ogsClient.blackPlayerID ?? 0) <= 0 || (ogsClient.whitePlayerID ?? 0) <= 0) {
            return "Choose a game and wait for its players to load."
        }
        return nil
    }
    var isAIAvailable: Bool { aiAnalysisEnabled && aiUnavailableReason == nil }
    @Published private(set) var keepAnalyzing = false

    func setKeepAnalyzing(_ enabled: Bool) {
        guard enabled != keepAnalyzing else { return }
        if enabled {
            guard mode == .review, isAIAvailable else { return }
            backgroundAnalysis.stop()
            backgroundReviewStatus = nil
            boardVM?.suspendAutomaticAnalysis()
            analysisEngine.pauseAnalysis()
            analysisEngine.retryFailedAnalysis()
            keepAnalyzing = true
            updateContinuousAnalysis()
        } else {
            stopKeepingAnalysis()
            boardVM?.resumeAutomaticAnalysis()
        }
    }

    /// Explicit review work uses the same opening-to-end sweep for imported and
    /// just-finished games. It replaces a selected-position continuous search.
    func analyzeFullGame() {
        guard mode == .review, aiUnavailableReason == nil, let vm = boardVM else { return }
        stopKeepingAnalysis()
        backgroundAnalysis.stop()
        backgroundReviewStatus = nil
        vm.suspendAutomaticAnalysis()
        vm.cancelVariationPreview()
        analysisEngine.pauseAnalysis()
        analysisEngine.retryFailedAnalysis()
        if !analysisEngine.isEngineRunning { analysisEngine.start() }
        aiAnalysisEnabled = true
        vm.triggerFullGameAnalysis()
    }

    private func stopKeepingAnalysis() {
        if keepAnalyzing { keepAnalyzing = false }
        analysisEngine.stopContinuousAnalysis()
    }

    private func updateContinuousAnalysis() {
        guard keepAnalyzing else { return }
        guard mode == .review, isAIAvailable, let vm = boardVM else {
            stopKeepingAnalysis(); return
        }
        guard !player.isPlaying, !vm.isScrubbing else {
            analysisEngine.stopContinuousAnalysis(); return
        }
        if analysisEngine.continuousAnalysisTurn != player.currentIndex {
            analysisEngine.stopContinuousAnalysis()
        }
        if !analysisEngine.isEngineRunning && analysisEngine.engineStartupError == nil { analysisEngine.start() }
        let payload = player.getCurrentAIPayload()
        analysisEngine.analyzeGame(id: analysisEngine.currentGameId, initialStones: payload.initial,
            moves: payload.moves, size: player.board.size, settings: player.analysisSettings, continuous: true)
    }
    @Published private(set) var backgroundReviewStatus: String?
    @Published private(set) var completedGameResult: String?
    @Published private(set) var completedGameSaveURL: URL?
    @Published private(set) var completedGameSaveError: String?
    private let injectedGamesDirectory: URL?
    private var completedGamesDirectory: URL { injectedGamesDirectory ?? AppSettings.shared.savedGamesFolderURL }
    private var pendingArchiveActions: [() -> Void] = []
    private var choosingSaveFolder = false
    private var pendingCompletedGame: (id: String, data: Data, name: String)?
    private let backgroundAnalysis: BackgroundGameAnalysis
    private let analysisEngine: KataGoEngine
    private let analysisResources = AnalysisResourceMonitor()
    private var analysisTimer: Timer?
    private var lastAnalysisTick: TimeInterval?
    private var armedOnlineReview: Int?
    private var terminalSnapshotID: Int?
    private var requestedTerminalSnapshotID: Int?
    @Published private(set) var postGameChatID: Int?
    private var openingPostGameReview = false
    private var reviewedOnlineGames = Set<Int>()

    func closePostGameChat() {
        guard postGameChatID != nil else { return }
        ogsClient.leaveViewedGame()
        postGameChatID = nil
        ogsClient.observationOnly = mode != .playOnline
        isTypingInChat = false
    }
    private var unfinishedLocalAnalysisIDs = Set<String>()
    private var completedAnalysisIDs = Set<String>()
    private var completionResults: [String: String] = [:]

    var usesAdaptiveAnalysis: Bool {
        keepAnalyzing || mode == .playOnline || mode == .localPlay
    }
    private var lastAIAvailability = false
    private var isChangingMode = false
    private func refreshAIPolicy(restartAnalysis: Bool = false) {
        let available = isAIAvailable
        if !available || mode != .review { stopKeepingAnalysis() }
        if available && !usesAdaptiveAnalysis && !analysisEngine.isEngineRunning && analysisEngine.engineStartupError == nil {
            analysisEngine.start()
        }
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
        case oldestDate = "Oldest Date"
        case whitePlayer = "White Player"

        var label: String {
            switch self {
            case .defaultIndex: return "Collection order"
            case .name: return "Black player (A–Z)"
            case .whitePlayer: return "White player (A–Z)"
            case .date: return "Date (newest first)"
            case .oldestDate: return "Date (oldest first)"
            }
        }
    }

    private var libraryLoadID = UUID()
    
    private var cancellables: Set<AnyCancellable> = []
    private var currentActiveInternalGameID: Int? = nil
    @Published var resumableGameID: Int? = nil
    private struct LaunchPosition: Codable {
        var version = 1
        let mode: String
        let sgf: String
        let originalSGF: String?
        let sourceURL: URL?
        let analysisID: String
        let selectedNode: Int?
        let activeLeaf: Int?
        let moveIndex: Int
        let analysisSettings: GameAnalysisSettings
        let freeHandicapPlacement: Bool
    }
    private static let launchPositionKey = "lastBoardSessionV1"

    /// Save the real game, never the temporary hover continuation. Keeping the
    /// SGF itself also permits recovery after its source is moved or disconnected.
    func saveLaunchPosition() {
        guard !mode.usesOGS, !isChangingMode, let vm = boardVM else { return }
        let snapshot = player.createSnapshot()
        var game = SGFGame()
        game.info = selection?.game.info ?? SGFGame.Info()
        game.boardSize = snapshot.size; game.moves = snapshot.moves; game.setup = snapshot.setup
        game.initialPlayer = snapshot.initialPlayer
        game.info.rules = snapshot.analysisSettings.rules
        game.info.komi = String(snapshot.analysisSettings.effectiveKomi)
        game.handicap = vm.localViewState().handicap
        var document = mode == .review ? vm.reviewTree : nil
        document?.followPlayback(index: snapshot.currentIndex)
        let state = LaunchPosition(mode: mode.rawValue,
            sgf: SGFWriter.serialize(document?.source ?? ReviewTree.linearTree(game)),
            originalSGF: document?.originalSGF, sourceURL: selection?.url,
            analysisID: document?.baseAnalysisID ?? analysisEngine.currentGameId,
            selectedNode: document?.selectedID, activeLeaf: document?.activePath.last,
            moveIndex: snapshot.currentIndex, analysisSettings: snapshot.analysisSettings,
            freeHandicapPlacement: snapshot.freeHandicapMoves > 0)
        guard let data = try? JSONEncoder().encode(state),
              data != UserDefaults.standard.data(forKey: Self.launchPositionKey) else { return }
        UserDefaults.standard.set(data, forKey: Self.launchPositionKey)
    }

    private func restoreLaunchPosition() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.launchPositionKey),
              let state = try? JSONDecoder().decode(LaunchPosition.self, from: data),
              state.version == 1, state.mode == mode.rawValue, !mode.usesOGS,
              let source = try? SGFParser.parse(text: state.sgf), !source.branches.isEmpty else { return false }
        var game = SGFGame.from(tree: source)
        guard (2...19).contains(game.boardSize), state.moveIndex >= 0 else { return false }
        game.analysisOnline = state.analysisSettings.online
        game.whiteHandicapBonus = state.analysisSettings.whiteHandicapBonus
        game.ruleOverrides = state.analysisSettings.ruleOverrides
        game.freeHandicapPlacement = state.freeHandicapPlacement
        let url = state.sourceURL ?? URL(fileURLWithPath: "/tmp/RestoredGame.sgf")
        let wrapper = SGFGameWrapper(url: url, game: game)
        var document: ReviewTree?
        if mode == .review {
            var tree = ReviewTree(game: game, analysisID: state.analysisID,
                                  filename: url.lastPathComponent, originalSGF: state.originalSGF)
            guard let selected = state.selectedNode, tree.nodes.indices.contains(selected),
                  tree.nodes[selected].moveNumber == state.moveIndex else { return false }
            if let leaf = state.activeLeaf, tree.nodes.indices.contains(leaf) { tree.select(leaf) }
            tree.select(selected)
            document = tree
        } else if state.moveIndex > game.moves.count { return false }
        selection = state.sourceURL == nil && game.moves.isEmpty && game.setup.isEmpty ? nil : wrapper
        boardVM?.restoreLaunchPosition(wrapper, document: document, moveIndex: state.moveIndex)
        if mode == .localPlay { beginLocalAnalysisSession() }
        player.pause()
        return true
    }

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

    init(ogsClient injectedClient: OGSClient? = nil, defaultMode: AppMode = .localPlay,
         analysisEngine: KataGoEngine = .shared,
         completedGamesDirectory: URL? = nil) {
        self.injectedGamesDirectory = completedGamesDirectory
        self.analysisEngine = analysisEngine
        self.backgroundAnalysis = BackgroundGameAnalysis(engine: analysisEngine)
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
        }, analysisEngine: analysisEngine)
        bVM.canNavigateReview = { [weak self] in self?.mode == .review }
        bVM.canPreviewAnalysis = { [weak self] in self?.mode == .review && self?.isAIAvailable == true }
        bVM.canEditLocally = { [weak self] in self?.mode == .localPlay }
        bVM.usesAdaptiveAnalysis = { [weak self] in self?.usesAdaptiveAnalysis == true }
        self.boardVM = bVM
        bVM.onReviewEdited = { [weak self] document in self?.saveEditedReview(document) }
        Publishers.CombineLatest3(bVM.$currentMoveIndex, bVM.$isScrubbing, player.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateContinuousAnalysis() }
            .store(in: &cancellables)
        self.ogsGame = OGSGameViewModel(ogsClient: ogsClient, player: player, timeControl: timeControl)
        
        // Audio Binding
        bVM.onPlaySound = { [weak self] type in
            self?.playSound(type)
        }
        
        // Initialize Audio
        setupAudio()
        
        // Launch analysis only when work is permitted. An unplugged laptop with
        // battery saving enabled need not load the neural network just to play.
        
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
            DispatchQueue.main.async { [weak self] in
                self?.refreshAIPolicy()
                self?.updatePlayedGameAnalysis()
            }
        }.store(in: &cancellables)
        
        setupAudio()
        setupOGSObservers()
        // willTerminate is synchronous on the main thread. Do not defer the flush
        // to a queue that may never run after the app exits.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.saveLaunchPosition()
                UserDefaults.standard.synchronize()
                analysisEngine.stop()
            }.store(in: &cancellables)
        
        // CONDITION: Only connect if we restore Online Mode
        if wasOnline {
            print("⏳ Persistence detected. Connection deferred to handleStartup().")
        }
        
        let restoredPosition = !wasOnline && restoreLaunchPosition()
        // Populate the library independently. Its first batch must never choose
        // the launch board or overwrite a restored standalone SGF/variation.
        if let url = AppSettings.shared.folderURL {
            loadFolder(url, autoSelect: false)
        } else { loadingStatus = "Startup: No Folder Set" }
        if !wasOnline && !restoredPosition {
            if startupMode == .localPlay && AppSettings.shared.startGameOnLaunch { startInstantGame() }
            else if startupMode == .review { boardVM?.prepareReviewTreeFromCurrentPosition(restoreDraft: false) }
        }
        // Debounce redraw bursts, but flush synchronously at quit. Read the state
        // after Published values and review-tree selection have finished updating.
        player.objectWillChange.merge(with: bVM.objectWillChange)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveLaunchPosition() }
            .store(in: &cancellables)

        ogsClient.observationOnly = mode != .playOnline
        // Master mute/volume applies to every stone player, including active clips.
        let settings = AppSettings.shared
        // Deliver after @Published has stored the new value, so every permission
        // check sees the same master setting. Stop the process, including pending
        // restarts, while retaining its flushed analysis cache on disk.
        settings.$analysisEnabled.removeDuplicates().dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    self.backgroundAnalysis.stop()
                    self.backgroundReviewStatus = nil
                    self.boardVM?.updateAnalysisPermission()
                    self.analysisEngine.stop()
                } else {
                    _ = self.analysisEngine.loadAnalysisCache(for: self.analysisEngine.currentGameId, game: self.player)
                }
                self.refreshAIPolicy(restartAnalysis: enabled)
                self.objectWillChange.send()
                self.updatePlayedGameAnalysis()
            }.store(in: &cancellables)
        if !settings.analysisEnabled { analysisEngine.stop() }
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
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updatePlayedGameAnalysis()
        }
        timer.tolerance = 0.1
        analysisTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit { analysisTimer?.invalidate() }


    
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
        beginLocalAnalysisSession()
        // Create Dummy Wrapper for UI
        var newGame = SGFGame()
        newGame.boardSize = 19
        newGame.info.event = "Instant Game"
        newGame.info.date = SGFGame.Info.formattedGameDate(Date())
        
        let dummyURL = URL(fileURLWithPath: "/tmp/InstantGame.sgf")
        let wrapper = SGFGameWrapper(url: dummyURL, game: newGame)
        
        self.selection = wrapper
    }
    
    private func saveCurrentBoard(for previous: AppMode) {
        if previous.usesOGS {
            if let id = ogsClient.activeGameID { onlineBoards[previous] = id }
        } else {
            savedBoards[previous] = SavedBoard(snapshot: player.createSnapshot(), selection: selection,
                                             analysisID: analysisEngine.currentGameId, viewState: boardVM?.localViewState())
        }
    }

    private func changeMode(from previous: AppMode) {
        stopKeepingAnalysis()
        if previous == .localPlay { updateLocalReviewEligibility() }
        isChangingMode = true
        backgroundAnalysis.stop()
        backgroundReviewStatus = nil
        completedGameResult = nil
        completedGameSaveURL = nil
        completedGameSaveError = nil
        defer {
            if mode == .localPlay && !analysisEngine.currentGameId.hasPrefix("played-local-") { beginLocalAnalysisSession() }
            isChangingMode = false
            refreshAIPolicy(restartAnalysis: true)
        }
        player.pause()
        saveCurrentBoard(for: previous)
        if !openingPostGameReview {
            closePostGameChat()
            if previous.usesOGS { ogsClient.leaveViewedGame() }
        }
        isCreatingChallenge = false
        isTypingInChat = false
        currentActiveInternalGameID = nil
        ogsClient.observationOnly = mode != .playOnline && postGameChatID == nil
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
            _ = analysisEngine.loadAnalysisCache(for: saved.analysisID, game: player)
            completedGameResult = completionResults[saved.analysisID]
            if let state = saved.viewState { boardVM?.restoreLocalViewState(state) }
            if mode == .review { boardVM?.prepareReviewTreeFromCurrentPosition(info: selection?.game.info) }
            if completedGameResult != nil {
                completedGameSaveURL = archivedURL(id: boardVM?.reviewTree?.baseAnalysisID ?? saved.analysisID)
            }
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

    var suggestedReviewFilename: String {
        if let document = boardVM?.reviewTree { return reviewFilename(document) }
        return reviewName(for: (selection?.game.info ?? SGFGame.Info()).suggestedFilename)
    }

    private func reviewName(for filename: String) -> String {
        (filename as NSString).deletingPathExtension + "-review.sgf"
    }

    private func archivedURL(id: String, review: Bool = false) -> URL? {
        let key = review ? "savedReviewPathsV1" : "savedCompletedGamePathsV1"
        guard let path = (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id] else { return nil }
        let url = URL(fileURLWithPath: path)
        if let injectedGamesDirectory,
           url.deletingLastPathComponent().standardizedFileURL.path != injectedGamesDirectory.standardizedFileURL.path { return nil }
        return url
    }

    private func reviewFilename(_ document: ReviewTree) -> String {
        if let existing = archivedURL(id: document.baseAnalysisID, review: true) { return existing.lastPathComponent }
        return reviewName(for: archivedURL(id: document.baseAnalysisID)?.lastPathComponent ?? document.baseGame.info.suggestedFilename)
    }

    private func rememberArchivedURL(_ url: URL, id: String, review: Bool) {
        let key = review ? "savedReviewPathsV1" : "savedCompletedGamePathsV1"
        var paths = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        paths[id] = url.path
        // Loading an SGF uses its path as the analysis identity. Keep that alias
        // so reopening either the original or its review updates the same review.
        paths[url.path.replacingOccurrences(of: "/", with: "_")] = url.path
        if review, let original = archivedURL(id: id) {
            paths[original.path.replacingOccurrences(of: "/", with: "_")] = url.path
        }
        UserDefaults.standard.set(paths, forKey: key)
    }

    /// Reserve new filenames without replacing another game with the same players/date.
    /// Repeated completion notifications reuse identical saved content; review edits
    /// update only the review file previously assigned to this document.
    private func archiveSGF(_ data: Data, id: String, filename: String, review: Bool = false) throws -> URL {
        let directory = review ? (archivedURL(id: id)?.deletingLastPathComponent() ?? completedGamesDirectory) : completedGamesDirectory
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if review, let url = archivedURL(id: id, review: true) {
            if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
            return url
        }
        if let url = archivedURL(id: id, review: review), let existing = try? Data(contentsOf: url) {
            if existing == data { return url }
        }
        let stem = (filename as NSString).deletingPathExtension
        var number = 1
        while true {
            let name = number == 1 ? filename : "\(stem) (\(number)).sgf"
            let url = directory.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .withoutOverwriting)
                rememberArchivedURL(url, id: id, review: review)
                return url
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                number += 1
            }
        }
    }

    func retryCompletedGameSave() {
        guard let pending = pendingCompletedGame else { return }
        do {
            completedGameSaveURL = try archiveSGF(pending.data, id: pending.id, filename: pending.name)
            completedGameSaveError = nil
        } catch {
            completedGameSaveURL = nil
            completedGameSaveError = "Could not save the finished game: " + error.localizedDescription
        }
    }

    private func saveEditedReview(_ document: ReviewTree) {
        prepareAutomaticSave { [weak self] in self?.writeEditedReview(document) }
    }

    private func writeEditedReview(_ document: ReviewTree) {
        do {
            _ = try archiveSGF(Data(SGFWriter.serialize(document.source).utf8), id: document.baseAnalysisID,
                               filename: reviewFilename(document), review: true)
        } catch {
            boardVM?.reviewTreeError = "Could not save the review SGF. The draft is retained; use Save SGF. " + error.localizedDescription
        }
    }

    private func prepareAutomaticSave(_ action: @escaping () -> Void) {
        guard injectedGamesDirectory == nil, !UserDefaults.standard.bool(forKey: "savedGamesFolderConfigured") else {
            action(); return
        }
        pendingArchiveActions.append(action)
        guard !choosingSaveFolder else { return }
        choosingSaveFolder = true
        chooseGameSaveFolder(firstSave: true) { [weak self] in
            guard let self else { return }
            self.choosingSaveFolder = false
            let actions = self.pendingArchiveActions
            self.pendingArchiveActions.removeAll()
            actions.forEach { $0() }
        }
    }

    func chooseGameSaveFolder(firstSave: Bool = false, completion: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.title = "Choose where games are saved"
        panel.prompt = "Use This Folder"
        panel.message = "Finished games and reviews save automatically here. You can change this in Settings → Saved Games."
            + (firstSave ? " Cancel uses Documents/Quiet Go Games." : "")
        if firstSave { try? FileManager.default.createDirectory(at: completedGamesDirectory, withIntermediateDirectories: true) }
        panel.directoryURL = completedGamesDirectory
        let finished: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { AppSettings.shared.savedGamesFolderURL = url }
            if firstSave { UserDefaults.standard.set(true, forKey: "savedGamesFolderConfigured") }
            completion?()
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: finished) }
        else { panel.begin(completionHandler: finished) }
    }

    func rememberSGFSave(to url: URL, reviewID: String? = nil) {
        if injectedGamesDirectory == nil { AppSettings.shared.savedGamesFolderURL = url.deletingLastPathComponent() }
        if let reviewID {
            rememberArchivedURL(url, id: reviewID, review: true)
        }
    }

    func saveReviewSGF() {
        guard mode == .review, let vm = boardVM, let data = vm.reviewSGFData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]
        panel.title = "Save game with variations"
        panel.nameFieldStringValue = suggestedReviewFilename
        panel.directoryURL = completedGamesDirectory
        let reviewID = vm.reviewTree?.baseAnalysisID
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                self.rememberSGFSave(to: url, reviewID: reviewID)
            }
            catch { vm.reviewTreeError = "Could not save the SGF: " + error.localizedDescription }
        }
    }

    func copyCurrentBoard(to destination: AppMode) {
        guard !destination.usesOGS, destination != mode else { return }
        if mode == .localPlay { updateLocalReviewEligibility() }
        savedBoards[destination] = SavedBoard(snapshot: player.createSnapshot(), selection: selection,
                                              analysisID: analysisEngine.currentGameId, viewState: boardVM?.localViewState(includeTree: false))
        mode = destination
    }

    private func beginLocalAnalysisSession() {
        let id = "played-local-" + UUID().uuidString
        analysisEngine.currentGameId = id
        unfinishedLocalAnalysisIDs.insert(id)
    }

    private func updateLocalReviewEligibility() {
        if analysisEngine.currentGameId == "local" { beginLocalAnalysisSession() }
        guard boardVM?.localScoring?.isFinal != true || boardVM?.localScoring?.index != player.maxIndex else { return }
        let id = analysisEngine.currentGameId
        unfinishedLocalAnalysisIDs.insert(id)
        completedAnalysisIDs.remove(id)
        completionResults.removeValue(forKey: id)
        completedGameResult = nil
    }

    /// Called after accepted server state and by the resource timer. Never infer a
    /// finished online game from passes, a disconnect, or a local clock estimate.
    func updatePlayedGameAnalysis(resources: AnalysisResources? = nil, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !isChangingMode, let vm = boardVM else { return }
        if keepAnalyzing {
            updateContinuousAnalysis()
            if keepAnalyzing { return }
        }
        let delayed = lastAnalysisTick.map { now - $0 > 1.5 } ?? false
        lastAnalysisTick = now
        let ai = analysisEngine
        if mode == .localPlay { updateLocalReviewEligibility() }
        if mode == .playOnline, let id = ogsClient.activeGameID,
           currentActiveInternalGameID == id, vm.isOnlineContext, ogsClient.isAccountGameParticipant {
            if !ogsClient.isGameFinished {
                armedOnlineReview = id
                terminalSnapshotID = nil
                requestedTerminalSnapshotID = nil
            }
            if ogsClient.isGameFinished, !ogsClient.isReconcilingMoves,
               armedOnlineReview == id, !reviewedOnlineGames.contains(id) {
                // A phase-only notification can precede the final history/result.
                // Reconcile that snapshot before disconnecting from the game room.
                if ogsClient.activeGameOutcome == nil && terminalSnapshotID != id {
                    if requestedTerminalSnapshotID != id {
                        requestedTerminalSnapshotID = id
                        ogsClient.requestMoveResync()
                    }
                    return
                }
                reviewedOnlineGames.insert(id)
                armedOnlineReview = nil
                ogsClient.myActiveGames.remove(id)
                // Preserve player names and final result before leaving the online session.
                var game = SGFGame()
                game.info.playerBlack = ogsClient.blackPlayerName
                game.info.playerWhite = ogsClient.whitePlayerName
                game.info.event = "Online game"
                game.info.result = onlineSGFResult
                game.info.date = SGFGame.Info.formattedGameDate(Date())
                selection = SGFGameWrapper(url: URL(fileURLWithPath: "/played-games/ogs-\(id).sgf"), game: game)
                postGameChatID = id
                openingPostGameReview = true
                finishPlayedGame(result: ogsClient.activeGameOutcome ?? "Game finished")
                openingPostGameReview = false
            }
        } else if mode == .localPlay, !completedAnalysisIDs.contains(ai.currentGameId),
                  let score = vm.localScoring, score.isFinal,
                  vm.localScoringVisible, let result = score.result {
            var game = selection?.game ?? SGFGame()
            let margin = result.black.total - result.white.total
            game.info.result = margin == 0 ? "0" : (margin > 0 ? "B+" : "W+") + String(abs(margin))
            selection = SGFGameWrapper(url: selection?.url ?? URL(fileURLWithPath: "/played-games/Local.sgf"), game: game)
            finishPlayedGame(result: result.winnerDescription(blackName: selection?.game.info.playerBlack,
                                                             whiteName: selection?.game.info.playerWhite))
        }
        let playingOnline = mode == .playOnline && vm.isOnlineContext &&
            currentActiveInternalGameID == ogsClient.activeGameID && ogsClient.isAccountGameParticipant && !ogsClient.isGameFinished
        let playing = playingOnline || mode == .localPlay
        // Only hidden work during play belongs to the resource-throttled worker.
        // All visible Review sessions use BoardViewModel's whole-game sweep,
        // including games that have just finished.
        let shouldCompute = AppSettings.shared.analysisEnabled && playing && AppSettings.shared.analyzeDuringPlay
        guard shouldCompute else {
            backgroundAnalysis.stop()
            if backgroundReviewStatus != nil { backgroundReviewStatus = nil }
            return
        }
        backgroundAnalysis.tick(player: player, resources: resources ?? analysisResources.sample(),
            pauseOnBattery: AppSettings.shared.pauseAnalysisOnBattery, now: now, interfaceDelayed: delayed)
        if backgroundReviewStatus != nil { backgroundReviewStatus = nil }
    }

    private var onlineSGFResult: String? {
        guard let outcome = ogsClient.scoringOutcome?.lowercased() else { return nil }
        if ogsClient.activeGameResult?.title == "Draw" || ["draw", "jigo"].contains(outcome) { return "0" }
        if outcome.hasPrefix("b+") || outcome.hasPrefix("w+") { return outcome.uppercased() }
        guard let result = ogsClient.activeGameResult, let mine = ogsClient.playerColor else { return nil }
        let winner = result.isMe ? mine : mine.opponent
        let suffix: String
        if outcome.contains("resign") { suffix = "R" }
        else if outcome.contains("timeout") || outcome.contains("time out") { suffix = "T" }
        else if let margin = Double(outcome.replacingOccurrences(of: " points", with: "").replacingOccurrences(of: " point", with: "")) { suffix = String(margin) }
        else { return nil }
        return (winner == .black ? "B+" : "W+") + suffix
    }

    private func finishPlayedGame(result: String) {
        let id = analysisEngine.currentGameId
        let snapshot = player.createSnapshot()
        var finished = SGFGame()
        finished.info = selection?.game.info ?? SGFGame.Info()
        finished.boardSize = snapshot.size; finished.moves = snapshot.moves; finished.setup = snapshot.setup
        finished.initialPlayer = snapshot.initialPlayer
        finished.info.rules = snapshot.analysisSettings.rules
        finished.info.komi = String(snapshot.analysisSettings.effectiveKomi)
        finished.handicap = boardVM?.localViewState().handicap ?? 0
        pendingCompletedGame = (id, Data(SGFWriter.serialize(ReviewTree.linearTree(finished)).utf8), finished.info.suggestedFilename)
        backgroundAnalysis.stop()
        unfinishedLocalAnalysisIDs.remove(id)
        completedAnalysisIDs.insert(id)
        completionResults[id] = result
        player.pause()
        // At game end Review opens at the final position even if the player was
        // looking back at an earlier move. Keep the whole game, including passes.
        player.seek(to: player.maxIndex)
        // This game is already selected; leave the library closed when Review opens.
        showRightPanel = false
        copyCurrentBoard(to: .review)
        boardVM?.clearScoringForReview()
        completedGameResult = result
        aiAnalysisEnabled = true
        prepareAutomaticSave { [weak self] in self?.retryCompletedGameSave() }
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
        guard mode == .playOnline, !isAcceptingChallenge else { return }
        isAcceptingChallenge = true
        challengeAcceptanceError = nil
        ogsClient.lastError = nil
        let account = ogsClient.username ?? "this account"
        
        // Verified: Helper methods restored in Client v16.305
        self.ogsClient.acceptChallenge(challengeID: id) { [weak self] (newGameID: Int?, error: Error?) in
            guard let self = self else { return }
            self.isAcceptingChallenge = false
            
            if let gid = newGameID {
                self.ogsClient.myActiveGames.insert(gid)
                if self.mode == .playOnline { self.resumeOnlineGame(id: gid) }
            } else {
                let message: String
                if case OGSHTTPError.status(403)? = error {
                    message = "OGS did not allow \(account) to accept this challenge. Check the challenge's rank restrictions and that you are using the intended account."
                } else {
                    message = "Could not accept as \(account): \(error?.localizedDescription ?? "No game was returned by OGS.")"
                }
                self.ogsClient.lastError = message
                if self.mode == .playOnline { self.challengeAcceptanceError = message }
                NSLog("[OGS-UI] ❌ Accept Failed for ID \(id): \(error?.localizedDescription ?? "Unknown")")
                // Only a missing challenge justifies removing it. Timeouts, cancellation,
                // and authentication failures do not establish that it disappeared.
                if (error as? OGSHTTPError)?.statusCode == 404 {
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
        if ogsClient.isGameFinished { terminalSnapshotID = id }
        if ogsClient.isAccountGameParticipant && !ogsClient.isGameFinished { ogsClient.myActiveGames.insert(id) }
        ogsClient.isRequestingUndo = false
        ogsClient.isReconcilingMoves = false
        let next = boardVM.engine.playerToMove(at: boardVM.engine.maxIndex)
        ogsClient.currentPlayerID = next == .black ? ogsClient.blackPlayerID : ogsClient.whitePlayerID
        // The sidebar/lids follow the viewed board, not scoring prisoners or a later clock packet.
        boardVM.finishOnlineGameLoad(gameID: id)
        refreshAIPolicy(restartAnalysis: true)
        updatePlayedGameAnalysis()
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
        stopKeepingAnalysis()
        closePostGameChat()
        mode = .review
        completedGameResult = nil
        backgroundReviewStatus = nil
        backgroundAnalysis.stop()
        selection = g
        let id = g.url.path.replacingOccurrences(of: "/", with: "_")
        let canonical = archivedURL(id: id, review: true)
        let savedReview = canonical.flatMap { url in
            url.path == g.url.path ? nil : try? String(contentsOf: url, encoding: .utf8)
        }
        boardVM?.loadGame(g, savedReviewSGF: savedReview)
        // Persist as last played
        AppSettings.shared.lastPlayedGameURL = g.url
        // Kickstart AI for the first view
        boardVM?.syncState()
        boardVM?.triggerFullGameAnalysis()
    }
    static func makeSGFOpenPanel(folderOnly: Bool = false) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folderOnly
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "sgf") ?? .data]
        panel.prompt = "Open"
        panel.title = folderOnly ? "Choose an SGF folder" : "Open an SGF game or folder"
        panel.message = "Select a folder to load all its games, or open a folder and select an SGF to review just that game."
        return panel
    }

    func promptForSGFs() { presentSGFOpenPanel(folderOnly: false) }
    func promptForFolder() { presentSGFOpenPanel(folderOnly: true) }

    private func presentSGFOpenPanel(folderOnly: Bool) {
        let panel = Self.makeSGFOpenPanel(folderOnly: folderOnly)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self?.openSGFSelection(url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not open SGF"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    func openSGFSelection(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            AppSettings.shared.folderURL = url
            loadFolder(url)
        } else {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let wrapper = SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: text)))
            // An earlier folder scan must not replace this explicitly chosen game.
            libraryLoadID = UUID()
            games = [wrapper]
            selectGame(wrapper)
            loadingStatus = "Loaded 1 game."
        }
    }

    func loadFolder(_ url: URL, autoSelect: Bool = true) {
        let loadID = UUID()
        libraryLoadID = loadID
        // 2. Clear current library
        self.games = []
        if autoSelect { self.selection = nil }
        self.loadingStatus = "Loading Folder..." 
        
        // 3. Background Load
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                guard self.libraryLoadID == loadID else { return }
                self.loadingStatus = "Requesting Access..."
            }
            
            // Security Scope
            let accessing = url.startAccessingSecurityScopedResource()
            // Unscoped readable URLs are valid in the non-sandboxed Mac app.
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            DispatchQueue.main.async {
                guard self.libraryLoadID == loadID else { return }
                self.loadingStatus = "Reading Directory..."
            }

            let fm = FileManager.default
            var foundURLs: [URL] = []
            
            do {
                // Check read access
                let _ = try fm.contentsOfDirectory(atPath: url.path)
                
                let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
                let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
                
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: options) {
                    for case let fileURL as URL in enumerator {
                       if fileURL.pathExtension.lowercased() == "sgf",
                          (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                           foundURLs.append(fileURL)
                       }
                    }
                }
            } catch {
                let msg = "❌ Read Error: \(error.localizedDescription)"
                DispatchQueue.main.async {
                    guard self.libraryLoadID == loadID else { return }
                    self.loadingStatus = msg
                }
                return
            }
            
            if foundURLs.isEmpty {
                 DispatchQueue.main.async {
                     guard self.libraryLoadID == loadID else { return }
                     self.loadingStatus = "⚠️ Folder is empty (0 SGF files)."
                 }
                 return
            }
            
            DispatchQueue.main.async {
                guard self.libraryLoadID == loadID else { return }
                self.loadingStatus = "Found \(foundURLs.count) files. Parsing..."
            }
            
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
                            guard self.libraryLoadID == loadID else { return }
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
                        DispatchQueue.main.async {
                            guard self.libraryLoadID == loadID else { return }
                            self.games = batch; self.loadingStatus = "Loaded \(batch.count)..."
                        }
                    }
                } catch {
                    print("Failed to parse \(sgfURL.lastPathComponent): \(error)")
                    parseErrors += 1
                }
            }
            
            // 4. Update Main Actor (Final Flush)
            DispatchQueue.main.async {
                guard self.libraryLoadID == loadID else { return }
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
