// ========================================================
// FILE: ./ViewModels/BoardViewModel.swift
// VERSION: v8.214 (Clean Rewrite)
// ========================================================
import Foundation
import SwiftUI
import Combine
import CryptoKit

class BoardViewModel: ObservableObject {
    @Published var isOnlineContext: Bool = false
    @Published var moveError: String?
    @Published private(set) var reviewTree: ReviewTree?
    @Published var reviewTreeError: String?
    @Published private(set) var reviewDraftSaved = false
    private let reviewDraftDirectory: URL
    var canNavigateReview: (() -> Bool)?
    @Published var koPoint: BoardPosition?
    var ruleSummary: String {
        let name = engine.analysisSettings.rules ?? "Chinese (assumed)"
        return name + " · " + (engine.analysisSettings.playRules?.summary ?? "Local rule checks unavailable")
    }
    @Published var lastMovePosition: BoardPosition?
    @Published var currentMoveIndex: Int = 0
    @Published var stonesToRender: [RenderStone] = []
    @Published var ghostPosition: BoardPosition?
    @Published var ghostColor: Stone?
    @Published var blackCapturedCount: Int = 0
    @Published var whiteCapturedCount: Int = 0
    @Published var isAutoPlaying: Bool = false
    @Published var totalMoves: Int = 0
    @Published private(set) var isScrubbing = false
    @Published var territoryIsEstimate = false
    @Published var territoryPoints: [BoardPosition: Stone] = [:]
    @Published private(set) var localScoring: LocalScoringSession?
    private var localHandicap = 0
    private var scoringDismissedAtIndex: Int?
    struct LocalViewState {
        let scoring: LocalScoringSession?
        let handicap: Int
        let dismissedAtIndex: Int?
        let reviewTree: ReviewTree?
        let draftSaved: Bool
    }
    func localViewState(includeTree: Bool = true) -> LocalViewState {
        LocalViewState(scoring: localScoring, handicap: localHandicap, dismissedAtIndex: scoringDismissedAtIndex, reviewTree: includeTree ? reviewTree : nil, draftSaved: includeTree && reviewDraftSaved)
    }
    func restoreLocalViewState(_ state: LocalViewState) {
        reviewTree = state.reviewTree
        reviewDraftSaved = state.draftSaved
        localScoring = state.scoring
        localHandicap = state.handicap
        scoringDismissedAtIndex = state.dismissedAtIndex
        syncState()
    }
    var localScoringVisible: Bool {
        !isOnlineContext && localScoring?.index == engine.currentIndex && engine.currentIndex == engine.maxIndex
    }
    @Published var aiAnalysisProgress: Double = 0.0
    
    let onRequestUpdate3D = PassthroughSubject<Void, Never>()
    var engine: SGFPlayer
    var ogsClient: OGSClient
    var onPlaySound: ((AppModel.SoundType) -> Void)?
    var isAIAllowed: (() -> Bool)?
    var canEditLocally: (() -> Bool)?
    private let analysisEngine: KataGoEngine
    var canPreviewAnalysis: (() -> Bool)?
    @Published private(set) var variationFrame: AIVariationFrame?
    @Published private(set) var variationStatus: String?
    var isPreviewingVariation: Bool { variationFrame != nil }
    var recentMoveQualityMarkers: [RecentMoveQualityMarker] {
        guard canNavigateReview?() == true, isAIAllowed?() == true,
              !isPreviewingVariation, !localScoringVisible else { return [] }
        return RecentMoveQualityMarker.markers(engine: engine,
            evaluations: analysisEngine.evaluateGameQuality(upTo: currentMoveIndex, engine: engine))
    }
    var displayedStones: [RenderStone] {
        guard let frame = variationFrame else { return stonesToRender }
        let originals = Dictionary(uniqueKeysWithValues: stonesToRender.map { ($0.id, $0) })
        return frame.stones.map { position, color in
            // Keep original stones still; hypothetical moves start at the intersection.
            RenderStone(id: position, color: color,
                offset: frame.numbers[position] == nil && originals[position]?.color == color ? originals[position]!.offset : .zero)
        }.sorted { ($0.id.row, $0.id.col) < ($1.id.row, $1.id.col) }
    }
    private var variationTimer: Timer?
    private var variationHover: BoardPosition?
    private var variationGeneration = 0
    // Suppress placement/jitter animation on both entry and restoration.
    private(set) var restoringVariation = false

    func hoverAnalysis(at point: BoardPosition?) {
        guard canPreviewAnalysis?() == true, !isScrubbing, !engine.isPlaying, !localScoringVisible,
              let point else { cancelVariationPreview(); return }
        guard point != variationHover else { return }
        cancelVariationPreview()
        guard engine.moveRejection(color: engine.turn, x: point.col, y: point.row) == nil else { return }
        variationHover = point
        let generation = variationGeneration
        let index = engine.currentIndex
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self, self.variationGeneration == generation, self.engine.currentIndex == index,
                  self.canPreviewAnalysis?() == true, !self.engine.isPlaying else { return }
            self.beginVariationPreview(at: point, generation: generation)
        }
        variationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func beginVariationPreview(at point: BoardPosition, generation: Int) {
        let ai = analysisEngine
        let candidate = ai.cachedHoverAnalysis(game: engine, point: point)
            ?? ai.currentAnalysisData[engine.currentIndex]?.moveInfos?.first(where: {
                AIVariation.position($0.move, size: boardSize) == point && ($0.pv?.count ?? 0) > 1
            })
        if let candidate {
            let frames = AIVariation.frames(candidate: candidate, game: engine)
            if frames.count > 1 { showVariation(frames, step: 0, generation: generation); return }
        }
        variationStatus = "Computing AI preview…"
        ai.analyzeHover(game: engine, point: point) { [weak self] result in
            guard let self, self.variationGeneration == generation, self.canPreviewAnalysis?() == true else { return }
            switch result {
            case .success(let candidate):
                let frames = AIVariation.frames(candidate: candidate, game: self.engine)
                guard frames.count > 1 else {
                    self.variationStatus = "No legal continuation available for this move."; return
                }
                self.variationStatus = nil
                self.showVariation(frames, step: 0, generation: generation)
            case .failure(let error): self.variationStatus = error.message
            }
        }
    }

    private func showVariation(_ frames: [AIVariationFrame], step: Int, generation: Int) {
        guard variationGeneration == generation, canPreviewAnalysis?() == true, frames.indices.contains(step) else { return }
        variationFrame = frames[step]
        ghostPosition = nil
        onRequestUpdate3D.send()
        guard step + 1 < frames.count else { variationTimer = nil; return }
        let timer = Timer(timeInterval: 0.65, repeats: false) { [weak self] _ in
            self?.showVariation(frames, step: step + 1, generation: generation)
        }
        variationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancelVariationPreview() {
        variationGeneration += 1
        analysisEngine.cancelHoverAnalysis()
        variationStatus = nil
        variationTimer?.invalidate(); variationTimer = nil
        variationHover = nil
        guard variationFrame != nil else { return }
        restoringVariation = true
        variationFrame = nil
        onRequestUpdate3D.send()
        restoringVariation = false
    }

    
    private var jitterEngine: StoneJitter
    private var isSyncing = false
    private var lastObservedMoveIndex: Int = 0
    private var fullGameAnalysisTask: Task<Void, Swift.Error>?
    private var cancellables = Set<AnyCancellable>()
    private var stateSyncTimer: Timer?
    private var scrubTimer: Timer?
    private var pendingScrubIndex: Int?
    
    init(player: SGFPlayer, ogsClient: OGSClient, isAIAllowed: (() -> Bool)? = nil, analysisEngine: KataGoEngine = .shared, reviewDraftDirectory: URL? = nil) {
        self.reviewDraftDirectory = reviewDraftDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.davemarvit.SGFPlayerClean")
            .appendingPathComponent("ReviewDrafts", isDirectory: true)
        self.analysisEngine = analysisEngine
        self.engine = player
        self.ogsClient = ogsClient
        self.isAIAllowed = isAIAllowed
        self.jitterEngine = StoneJitter(boardSize: player.board.size, eccentricity: CGFloat(AppSettings.shared.jitterMultiplier))
        
        player.moveProcessed.sink { [weak self] in self?.scheduleStateSync() }.store(in: &cancellables)
        
        // Ensure UI stays in sync with Play/Pause toggles that don't trigger a move update
        player.$isPlaying.receive(on: RunLoop.main).sink { [weak self] val in
            self?.isAutoPlaying = val
        }.store(in: &cancellables)
        
        AppSettings.shared.$jitterMultiplier
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                self?.jitterEngine.setEccentricity(CGFloat(val))
                self?.syncState()
            }
            .store(in: &cancellables)
            
        // OGS Scoring Observers
        ogsClient.$removedStones.receive(on: RunLoop.main).sink { [weak self] _ in self?.syncState() }.store(in: &cancellables)
        ogsClient.$phase.receive(on: RunLoop.main).sink { [weak self] _ in self?.syncState() }.store(in: &cancellables)
        ogsClient.$scoreSummary.receive(on: RunLoop.main).sink { [weak self] _ in self?.syncState() }.store(in: &cancellables)
        ogsClient.$scoringOutcome.receive(on: RunLoop.main).sink { [weak self] _ in self?.syncState() }.store(in: &cancellables)
        ogsClient.$isGameFinished.receive(on: RunLoop.main).sink { [weak self] _ in self?.syncState() }.store(in: &cancellables)
        
        // Trigger initial analysis once engine boots up
        analysisEngine.$isEngineRunning.receive(on: RunLoop.main).sink { [weak self] isRunning in
            if isRunning {
                self?.requestAnalysisIfNeeded()
            }
        }.store(in: &cancellables)
    }
    
    var boardSize: Int { self.engine.board.size }

    /// Default-mode delivery waits for AppKit's slider tracking loop to finish. Use
    /// one common-mode callback and read the latest completed engine state instead.
    private func scheduleStateSync() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleStateSync() }
            return
        }
        cancelVariationPreview()
        guard stateSyncTimer == nil else { return }
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in self?.syncState() }
        stateSyncTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func beginScrubbing() {
        cancelVariationPreview()
        guard !isScrubbing else { return }
        isScrubbing = true
        engine.pause()
        // At most 5 previews per second, with only the latest requested move retained.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.applyPendingScrub() }
        scrubTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func scrub(to index: Int) {
        guard isScrubbing else { seekToMove(index); return }
        pendingScrubIndex = max(0, min(index, engine.maxIndex))
    }

    private func applyPendingScrub() {
        guard let index = pendingScrubIndex else { return }
        pendingScrubIndex = nil
        guard index != engine.currentIndex else { return }
        engine.seek(to: index)
        // Publish board, counts, and 3D scene from the same completed preview.
        syncState()
    }

    func endScrubbing(at index: Int) {
        guard isScrubbing else { return }
        scrubTimer?.invalidate(); scrubTimer = nil
        pendingScrubIndex = max(0, min(index, engine.maxIndex))
        applyPendingScrub() // Release always commits the exact final thumb position.
        isScrubbing = false
        requestAnalysisIfNeeded()
    }

    func cancelScrubbing() {
        scrubTimer?.invalidate(); scrubTimer = nil
        pendingScrubIndex = nil
        isScrubbing = false
    }

    deinit {
        variationTimer?.invalidate()
        stateSyncTimer?.invalidate()
        scrubTimer?.invalidate()
    }
    
    func resetToEmpty() {
        reviewTree = nil; reviewTreeError = nil; reviewDraftSaved = false
        cancelScrubbing()
        localScoring = nil; scoringDismissedAtIndex = nil; localHandicap = 0
        fullGameAnalysisTask?.cancel()
        if analysisEngine.currentGameId != "local" {
            analysisEngine.saveAnalysisCache(for: analysisEngine.currentGameId)
        }
        analysisEngine.currentGameId = "local"
        analysisEngine.invalidateAnalysis()
        
        self.engine.clear()
        self.stonesToRender = []
        self.lastMovePosition = nil
        self.isOnlineContext = false
        self.lastObservedMoveIndex = 0
        self.syncState()
    }
    
    func loadGame(_ wrapper: SGFGameWrapper) {
        cancelScrubbing()
        localScoring = nil; scoringDismissedAtIndex = nil; localHandicap = wrapper.game.handicap
        fullGameAnalysisTask?.cancel()
        if analysisEngine.currentGameId != "local" {
            analysisEngine.saveAnalysisCache(for: analysisEngine.currentGameId)
        }
        analysisEngine.invalidateAnalysis()
        
        self.isOnlineContext = false
        
        let newGameId = wrapper.url.path.replacingOccurrences(of: "/", with: "_")
        reviewTree = ReviewTree(game: wrapper.game, analysisID: newGameId, filename: wrapper.url.lastPathComponent)
        reviewTreeError = nil
        reviewDraftSaved = false
        if let original = reviewTree, let data = try? Data(contentsOf: reviewDraftURL(original)) {
            do {
                if let restored = try JSONDecoder().decode(ReviewDraft.self, from: data).restore(over: original) {
                    reviewTree = restored; reviewDraftSaved = true
                }
            } catch { reviewTreeError = "Could not restore the review draft: " + error.localizedDescription }
        }
        let playback: SGFGame
        do { playback = try reviewTree!.playbackGame() }
        catch { reviewTreeError = error.localizedDescription; playback = SGFGame() }
        self.engine.load(game: playback)
        if let document = reviewTree { engine.seek(to: document.nodes[document.selectedID].moveNumber) }
        _ = analysisEngine.loadAnalysisCache(for: reviewTree.map(reviewAnalysisID) ?? newGameId, game: engine)
        self.jitterEngine = StoneJitter(boardSize: self.boardSize, eccentricity: CGFloat(AppSettings.shared.jitterMultiplier))
        self.lastObservedMoveIndex = self.engine.currentIndex
        self.syncState()
    }
    
    func selectReviewNode(_ id: Int) {
        guard canNavigateReview?() == true, !isOnlineContext, var document = reviewTree,
              document.nodes.indices.contains(id) else { return }
        let previousPath = document.activePath
        document.select(id)
        activateReviewDocument(document, reload: previousPath != document.activePath)
    }

    private func activateReviewDocument(_ document: ReviewTree, reload: Bool, newMove: Bool = false) {
        let game: SGFGame
        do { game = try document.playbackGame() }
        catch { reviewTreeError = error.localizedDescription; return }
        cancelScrubbing(); cancelVariationPreview(); engine.pause()
        reviewTreeError = nil
        let index = document.nodes[document.selectedID].moveNumber
        if reload {
            fullGameAnalysisTask?.cancel()
            analysisEngine.pauseAnalysis()
            analysisEngine.saveAnalysisCache(for: analysisEngine.currentGameId)
            engine.load(game: game)
            engine.seek(to: index)
            let key = reviewAnalysisID(document)
            _ = analysisEngine.loadAnalysisCache(for: key, game: engine)
            // StoneJitter keeps the unchanged prefix stable across branch edits.
            localScoring = nil; scoringDismissedAtIndex = nil
        } else { engine.seek(to: index) }
        reviewTree = document
        if !newMove { lastObservedMoveIndex = index } // Navigation is silent; explicit moves retain normal audio.
        syncState()
        if reload { triggerFullGameAnalysis() }
    }

    var canCreateReviewVariation: Bool { canNavigateReview?() == true && !isOnlineContext && reviewTree != nil }

    func addReviewMove(at point: BoardPosition?) {
        guard canCreateReviewVariation, var document = reviewTree else { return }
        cancelScrubbing(); cancelVariationPreview(); engine.pause()
        document.followPlayback(index: engine.currentIndex)
        if let rejection = engine.moveRejection(color: engine.turn, x: point?.col ?? -1, y: point?.row ?? -1) {
            moveError = rejection.rawValue; return
        }
        let updated = document.addingMove(color: engine.turn, point: point)
        moveError = nil
        activateReviewDocument(updated, reload: true, newMove: updated.nodes.count > document.nodes.count)
        if reviewTreeError == nil { saveReviewDraft() }
    }

    private func reviewDraftURL(_ document: ReviewTree) -> URL {
        let digest = SHA256.hash(data: Data(document.baseAnalysisID.utf8)).map { String(format: "%02x", $0) }.joined()
        return reviewDraftDirectory.appendingPathComponent(digest + ".json")
    }

    private func saveReviewDraft() {
        guard let document = reviewTree else { return }
        do {
            try FileManager.default.createDirectory(at: reviewDraftDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(ReviewDraft(document)).write(to: reviewDraftURL(document), options: .atomic)
            reviewDraftSaved = true
        } catch {
            reviewDraftSaved = false
            reviewTreeError = "Could not save the review draft. Please use Save SGF: " + error.localizedDescription
        }
    }

    private func reviewAnalysisID(_ document: ReviewTree) -> String {
        if document.isMainLine { return document.baseAnalysisID }
        let positionKeys: Set<String> = ["B", "W", "AB", "AW", "AE", "PL", "SZ", "RU", "KM", "HA"]
        let properties = document.activePath.map { document.nodes[$0].properties.filter { positionKeys.contains($0.key) } }
        let data = (try? JSONSerialization.data(withJSONObject: properties, options: .sortedKeys)) ?? Data()
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return document.baseAnalysisID + "#variation-" + hash
    }

    func navigateReviewTree(vertical: Int = 0, horizontal: Int = 0) {
        guard let document = reviewTree else { return }
        let next = vertical != 0 ? document.neighbor(direction: vertical) : document.sibling(direction: horizontal)
        if let next { selectReviewNode(next) }
    }

    /// Snapshot export is independent of the selected path and any hover preview.
    func reviewSGFData() -> Data? {
        reviewTree.map { Data(SGFWriter.serialize($0.source).utf8) }
    }
    func writeReviewSGF(to url: URL) throws {
        guard let data = reviewSGFData() else { return }
        try data.write(to: url, options: .atomic)
    }

    func prepareReviewTreeFromCurrentPosition(info: SGFGame.Info? = nil) {
        guard reviewTree == nil else { return }
        let snapshot = engine.createSnapshot()
        var game = SGFGame()
        if let info { game.info = info }
        game.moves = snapshot.moves; game.setup = snapshot.setup; game.boardSize = snapshot.size
        game.initialPlayer = snapshot.initialPlayer; game.info.rules = snapshot.analysisSettings.rules
        game.info.komi = String(snapshot.analysisSettings.effectiveKomi)
        game.analysisOnline = snapshot.analysisSettings.online
        game.whiteHandicapBonus = snapshot.analysisSettings.whiteHandicapBonus
        game.ruleOverrides = snapshot.analysisSettings.ruleOverrides
        game.handicap = localHandicap
        game.freeHandicapPlacement = snapshot.freeHandicapMoves > 0
        var document = ReviewTree(game: game, analysisID: analysisEngine.currentGameId, filename: "Game.sgf")
        document.followPlayback(index: snapshot.currentIndex)
        reviewTree = document
        if let data = try? Data(contentsOf: reviewDraftURL(document)) {
            do {
                if let restored = try JSONDecoder().decode(ReviewDraft.self, from: data).restore(over: document) {
                    activateReviewDocument(restored, reload: true)
                    reviewDraftSaved = reviewTreeError == nil
                }
            } catch { reviewTreeError = "Could not restore the review draft: " + error.localizedDescription }
        }
    }

    func goToStart() { engine.seek(to: 0) }
    func goToEnd() { engine.seek(to: engine.maxIndex) }
    func stepForward() { engine.stepForward() }
    func stepBackward() { engine.stepBackward() }
    func stepForwardTen() { for _ in 0..<10 { engine.stepForward() } }
    func stepBackwardTen() { for _ in 0..<10 { engine.stepBackward() } }
    func toggleAutoPlay() { if engine.isPlaying { engine.pause() } else { engine.play() } }
    func seekToMove(_ index: Int) { engine.seek(to: index) }
    
    // MARK: - AI Mistake Seeking
    func seekNextMistake() {
        let ai = analysisEngine.evaluateGameQuality(upTo: totalMoves, engine: engine)
        let jumps = ai.filter { $0.key > currentMoveIndex && ($0.value.quality == .poor || $0.value.quality == .disastrous) }
        if let nextMistake = jumps.keys.min() {
            seekToMove(nextMistake)
        } else {
            goToEnd()
        }
    }
    
    func seekPrevMistake() {
        let ai = analysisEngine.evaluateGameQuality(upTo: totalMoves, engine: engine)
        let jumps = ai.filter { $0.key < currentMoveIndex && ($0.value.quality == .poor || $0.value.quality == .disastrous) }
        if let prevMistake = jumps.keys.max() {
            seekToMove(prevMistake)
        } else {
            goToStart()
        }
    }
    
    func stopAutoPlay() { engine.pause() }
    func startAutoPlay() { engine.play() }

    var localPassUnavailableReason: String? {
        if canCreateReviewVariation {
            return localScoringVisible ? "Resume play before passing again." : engine.moveRejection(color: engine.turn, x: -1, y: -1)?.rawValue
        }
        if canEditLocally?() == false { return "Switch to Local Play to add moves." }
        if isOnlineContext { return "Use the online game's Pass control." }
        if localScoringVisible { return "Resume play before passing again." }
        if engine.isPlaying { return "Pause playback before passing." }
        if engine.currentIndex != engine.maxIndex { return "Return to the latest position before passing." }
        return engine.moveRejection(color: engine.turn, x: -1, y: -1)?.rawValue
    }

    var localPassStatus: String? {
        if localScoringVisible { return nil }
        guard !isOnlineContext, let last = engine.lastMove, last.x == -1, last.y == -1 else { return nil }
        if engine.currentIndex == scoringDismissedAtIndex, engine.currentIndex == engine.maxIndex {
            return "Play resumed · \(engine.turn == .black ? "Black" : "White") to move"
        }
        return "\(last.color == .black ? "Black" : "White") passed · \(engine.turn == .black ? "Black" : "White") to move"
    }

    var onlineMoveUnavailableReason: String? {
        guard isOnlineContext else { return "No online game is open." }
        guard ogsClient.isConnected, ogsClient.isSocketAuthenticated else { return "Reconnect before playing." }
        guard ogsClient.isGameParticipant else { return "Observing — game actions are disabled." }
        guard !ogsClient.isReconcilingMoves else { return "Waiting for the refreshed game position." }
        guard ogsClient.canPlayMoves else { return "This game is not accepting moves." }
        guard engine.currentIndex == engine.maxIndex else { return "Return to the latest move before playing." }
        guard let color = ogsClient.playerColor, engine.turn == color else { return "Waiting for your opponent." }
        return nil
    }

    var onlinePassUnavailableReason: String? {
        if let reason = onlineMoveUnavailableReason { return reason }
        return engine.moveRejection(color: engine.turn, x: -1, y: -1)?.rawValue
    }

    func passOnline() {
        if let reason = onlinePassUnavailableReason { moveError = reason; return }
        guard let gameID = ogsClient.activeGameID, let color = ogsClient.playerColor else { return }
        if let rejection = engine.tryPlayMove(color: color, x: -1, y: -1) {
            moveError = rejection.rawValue
            return
        }
        moveError = nil
        SoundManager.shared.play("pass")
        ogsClient.sendPass(gameID: gameID)
    }

    func passLocally() {
        if let reason = localPassUnavailableReason { moveError = reason; return }
        if canCreateReviewVariation { addReviewMove(at: nil); return }
        if let rejection = engine.tryPlayMove(color: engine.turn, x: -1, y: -1) {
            moveError = rejection.rawValue
            return
        }
        ghostPosition = nil
        moveError = nil
        if analysisEngine.isEngineRunning { triggerFullGameAnalysis() }
    }
    
    private func synchronizeLocalScoring() {
        guard !isOnlineContext else { return }
        if let session = localScoring, session.index != engine.maxIndex { localScoring = nil }
        // Passing once after resumption must not pair with a pass from the previous round.
        if let resumed = scoringDismissedAtIndex, engine.currentIndex < resumed + 2 { return }
        guard engine.currentIndex == engine.maxIndex, engine.lastTwoMovesWerePasses,
              scoringDismissedAtIndex != engine.currentIndex, localScoring == nil else { return }
        localScoring = LocalScoringSession(player: engine, handicap: localHandicap)
        engine.pause()
        fullGameAnalysisTask?.cancel()
        ghostPosition = nil
    }

    func editLocalScoring(_ edit: (inout LocalScoringSession) -> Void) {
        guard localScoringVisible, var session = localScoring, !session.isFinal else { return }
        edit(&session)
        localScoring = session
        syncState()
    }

    func confirmLocalScore() {
        guard localScoringVisible, var session = localScoring, session.result != nil else { return }
        session.isFinal = true
        localScoring = session
        syncState()
    }

    func reviewLocalScore() {
        guard localScoringVisible else { return }
        localScoring?.isFinal = false
        syncState()
    }

    func resumeLocalPlay() {
        guard localScoringVisible else { return }
        scoringDismissedAtIndex = engine.currentIndex
        localScoring = nil
        syncState()
    }

    func handleRemoteMove(x: Int, y: Int, color: Stone) {
        self.engine.playMoveOptimistically(color: color, x: x, y: y)
    }
    
    func handleRemotePass(color: Stone) {
        SoundManager.shared.play("pass")
        self.engine.playMoveOptimistically(color: color, x: -1, y: -1)
    }
    
    func finishOnlineGameLoad(gameID: Int) {
        cancelScrubbing()
        localScoring = nil; scoringDismissedAtIndex = nil
        fullGameAnalysisTask?.cancel()
        _ = analysisEngine.loadAnalysisCache(for: String(gameID), game: engine)
        isOnlineContext = true
        jitterEngine = StoneJitter(boardSize: engine.board.size, eccentricity: CGFloat(AppSettings.shared.jitterMultiplier))
        isSyncing = false
        syncState()
    }

    func placeStone(at pos: BoardPosition) {
        if localScoringVisible {
            editLocalScoring { session in
                if session.tool == .deadGroups { session.toggleDeadGroup(at: pos) }
                else { session.toggleNeutralArea(at: pos) }
            }
            return
        }
        if canCreateReviewVariation { addReviewMove(at: pos); return }
        if !isOnlineContext && canEditLocally?() == false {
            moveError = "Switch to Local Play to add moves."
            return
        }
        let p = ogsClient.phase ?? "unknown"
        let isOnline = isOnlineContext
        let myColor = ogsClient.playerColor ?? .white
        let turn = self.engine.turn
        
        NSLog("[Input] Click at \(pos). Online: \(isOnline). Phase: \(p). Turn: \(turn). MyColor: \(myColor).")
        
        if isOnline {
             let resolvedColor = ogsClient.playerColor ?? .white
             // NSLog("[OGS-DEBUG-COLOR] Resolved: \(resolvedColor). MyID: \(ogsClient.playerID ?? -1).")
        }
        
        // Only the live online board accepts scoring edits; local playback is independent.
        if isOnline && (ogsClient.isGameFinished || ogsClient.isScoringPhase || p == "finished") {
            ghostPosition = nil
            guard ogsClient.canEditScore, engine.currentIndex == engine.maxIndex,
                  let gameID = ogsClient.activeGameID else { return }
            let group = engine.getGroup(at: pos)
            guard !group.isEmpty else { return }
            let coords = OGSScoring.encodePositions(group)
            ogsClient.sendRemovedStones(gameID: gameID, stones: coords, removed: !ogsClient.removedStones.contains(pos))
            return
        }

        // 2. Play Phase
        if isOnlineContext {
            if let reason = onlineMoveUnavailableReason { moveError = reason; return }
            guard let gameID = ogsClient.activeGameID, let myColor = ogsClient.playerColor else { return }
            // The reconciled engine turn prevents consecutive local moves while OGS
            // clock/current-player packets catch up with the board.
            let oldB = self.engine.blackStonesCaptured
            let oldW = self.engine.whiteStonesCaptured
            
            self.ghostPosition = nil
            if let rejection = engine.tryPlayMove(color: myColor, x: pos.col, y: pos.row) {
                moveError = rejection.rawValue
                return
            }
            moveError = nil
            
            let newB = self.engine.blackStonesCaptured
            let newW = self.engine.whiteStonesCaptured
            let captured = (newB - oldB) + (newW - oldW)
            
            if captured > 1 { onPlaySound?(.captureMultiple) }
            else if captured == 1 { onPlaySound?(.captureSingle) }
            else { onPlaySound?(.place) }
            
            self.ogsClient.sendMove(gameID: gameID, x: pos.col, y: pos.row)
        } else {
             if let rejection = engine.tryPlayMove(color: engine.turn, x: pos.col, y: pos.row) {
                 moveError = rejection.rawValue
                 return
             }
             moveError = nil
        }
        
        // Trigger background analysis sweep immediately after a move is registered (only if engine is running)
        if analysisEngine.isEngineRunning {
            self.triggerFullGameAnalysis()
        }
    }
    
    func syncState() {
        cancelVariationPreview()
        stateSyncTimer?.invalidate(); stateSyncTimer = nil
        synchronizeLocalScoring()
        moveError = nil
        koPoint = engine.koPoint
        let idx = self.engine.currentIndex
        if let document = reviewTree, document.nodes[document.selectedID].moveNumber != idx { reviewTree?.followPlayback(index: idx) }
        NSLog("[OGS-UI-DEBUG] 🎨 syncState Entry. Index: \(idx). Online: \(isOnlineContext)")
        let last = self.engine.lastMove.flatMap { m -> BoardPosition? in
            if m.x < 0 || m.y < 0 { return nil }
            return BoardPosition(m.y, m.x)
        }
        let snap = self.engine.board
        
        self.jitterEngine.prepare(player: engine)
        var list: [RenderStone] = []
        for (pos, col) in snap.stones {
            let off = self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: idx, stones: snap.stones)
            var rs = RenderStone(id: pos, color: col, offset: off)
            
            if isOnlineContext {
               if ogsClient.showsScoringMarks && engine.currentIndex == engine.maxIndex {
                   if ogsClient.removedStones.contains(pos) { rs.isDead = true }
               }
            }
            if localScoringVisible, localScoring?.deadStones.contains(pos) == true { rs.isDead = true }
            list.append(rs)
        }
        let safeList = list.sorted {
            if $0.id.row != $1.id.row { return $0.id.row < $1.id.row }
            return $0.id.col < $1.id.col
        }
        
        self.stonesToRender = safeList
        
        territoryIsEstimate = false
        if isOnlineContext {
           if ogsClient.showsScoringMarks && self.engine.currentIndex == self.engine.maxIndex {
                let serverPositions = ogsClient.scoringDisplaySummary?.positions(width: snap.size, height: snap.size)
                territoryIsEstimate = serverPositions == nil
                let t = serverPositions ?? self.engine.calculateTerritory(deadStones: ogsClient.removedStones)

                // Debug Territory
                if !t.isEmpty {
                     let counts = t.values.reduce(into: ["Black":0, "White":0]) { $0[$1 == .black ? "Black":"White", default: 0] += 1 }
                     NSLog("[OGS-TERRITORY] 🏳️🏴 Calculated: \(counts). Dead Stones: \(ogsClient.removedStones.count)")
                }

                self.territoryPoints = t
           } else {
               self.territoryPoints = [:]
           }
        } else if localScoringVisible, let scoring = localScoring {
            self.territoryPoints = scoring.territory
        } else {
            self.territoryPoints = [:]
        }
        
        if !isOnlineContext && !isScrubbing {
             if idx == (self.lastObservedMoveIndex + 1) {
                 let oldBlack = self.blackCapturedCount
                 let oldWhite = self.whiteCapturedCount
                 let newBlack = self.engine.whiteStonesCaptured
                 let newWhite = self.engine.blackStonesCaptured
                 
                 let captured = (newBlack - oldBlack) + (newWhite - oldWhite)
                 
                 if captured > 0 { 
                     if captured > 1 { onPlaySound?(.captureMultiple) }
                     else { onPlaySound?(.captureSingle) }
                 } else if last != nil {
                     onPlaySound?(.place) 
                 }
             }
        }
        self.lastObservedMoveIndex = idx
        
        self.lastMovePosition = last
        self.currentMoveIndex = idx
        
        self.blackCapturedCount = engine.capturesByBlack
        self.whiteCapturedCount = engine.capturesByWhite
        if isOnlineContext {
            ogsClient.blackCaptures = blackCapturedCount
            ogsClient.whiteCaptures = whiteCapturedCount
        }

        self.isAutoPlaying = self.engine.isPlaying
        self.totalMoves = self.engine.maxIndex
        self.onRequestUpdate3D.send()
        self.objectWillChange.send()
        
        self.requestAnalysisIfNeeded()
    }
    
    private func requestAnalysisIfNeeded() {
        guard !localScoringVisible, !isScrubbing else { return }
        guard analysisEngine.isEngineRunning else { return }
        if let allowed = isAIAllowed, !allowed() { return }
        
        let payload = self.engine.getCurrentAIPayload()
        let gameId = isOnlineContext ? (ogsClient.activeGameID.map { String($0) } ?? "local") : analysisEngine.currentGameId
        
        analysisEngine.analyzeGame(
            id: gameId,
            initialStones: payload.initial,
            moves: payload.moves,
            size: self.boardSize,
            maxVisits: 50,
            settings: engine.analysisSettings
        )
    }
    func updateAnalysisPermission() {
        cancelVariationPreview()
        fullGameAnalysisTask?.cancel()
        analysisEngine.pauseAnalysis()
        onRequestUpdate3D.send()
        objectWillChange.send()
        if isAIAllowed?() == true {
            requestAnalysisIfNeeded()
            triggerFullGameAnalysis()
        }
    }

    func triggerFullGameAnalysis() {
        if let allowed = isAIAllowed, !allowed() {
            fullGameAnalysisTask?.cancel()
            return
        }
        
        fullGameAnalysisTask?.cancel()
        fullGameAnalysisTask = Task { @MainActor in
            let total = self.totalMoves
            guard total > 0 else { return }
            
            let gameId = self.isOnlineContext ? (self.ogsClient.activeGameID.map { String($0) } ?? "local") : self.analysisEngine.currentGameId
            
            let targetDepths = [25, 50, 100, 250, 500]
            let totalOperations = Double(targetDepths.count * (total + 1))
            var completedOperations: Double = 0
            
            for depth in targetDepths {
                try Task.checkCancellation()
                
                var neededUpgrades = false
                
                // Sweep through all moves to see if they meet the current target depth
                for i in 0...total {
                    try Task.checkCancellation()
                    guard self.isAIAllowed?() != false else { return }
                    
                    // Do not build a large subprocess queue while the engine is still working.
                    while self.analysisEngine.hasPendingAnalysis || self.isScrubbing {
                        try await Task.sleep(nanoseconds: 100_000_000)
                        try Task.checkCancellation()
                        guard self.isAIAllowed?() != false else { return }
                        guard self.analysisEngine.currentGameId == gameId else { return }
                    }
                    guard self.analysisEngine.isEngineRunning else { return }
                    let existingVisits = self.analysisEngine.currentAnalysisData[i]?.rootInfo?.visits ?? 0
                    if existingVisits >= depth {
                        completedOperations += 1
                        let prog = completedOperations / totalOperations
                        self.aiAnalysisProgress = prog
                        continue // Already analyzed to this depth implicitly
                    }
                    
                    neededUpgrades = true
                    
                    // Yield runloop before heavy SGF processing to eliminate UI beachball lag
                    await Task.yield()
                    try Task.checkCancellation()
                    guard self.isAIAllowed?() != false else { return }
                    guard self.analysisEngine.currentGameId == gameId else { return }
                    let payload = self.engine.getAIPayload(at: i)
                    self.analysisEngine.analyzeGame(
                        id: gameId,
                        initialStones: payload.initial,
                        moves: payload.moves,
                        size: self.boardSize,
                        maxVisits: depth,
                        settings: engine.analysisSettings
                    )
                    
                    completedOperations += 1
                    let prog = completedOperations / totalOperations
                    self.aiAnalysisProgress = prog
                    
                    // Allow UI/Manual Analysis requests to jump the queue inherently because they fire without delay
                    // Sleep duration scales slightly with depth to give the engine time to process
                    let sleepMs: UInt64 = depth <= 50 ? 350 : 800
                    try await Task.sleep(nanoseconds: sleepMs * 1_000_000)
                }
                
                // If a full sweep happened and no moves needed upgrading, it's safe to immediately proceed to the next depth tier.
                if !neededUpgrades {
                    continue
                }
            }
        }
    }
    
    func updateGhostStone(at pos: BoardPosition?) {
        if localScoringVisible { ghostPosition = nil; return }
        guard isOnlineContext && engine.turn == ogsClient.playerColor else {
            self.ghostPosition = nil
            return
        }
        
        let p = ogsClient.phase ?? "unknown"
        if OGSScoring.isScoring(p) || p == "finished" || ogsClient.isGameFinished {
            self.ghostPosition = nil
            return
        }
        guard let pos, engine.moveRejection(color: engine.turn, x: pos.col, y: pos.row) == nil else {
            ghostPosition = nil
            return
        }
        self.ghostPosition = pos
        self.ghostColor = self.engine.turn
    }
    
    func clearGhostStone() { self.ghostPosition = nil }
    
    func getJitterOffset(forPosition pos: BoardPosition) -> CGPoint {
        return self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: self.currentMoveIndex, stones: self.engine.board.stones)
    }
}
