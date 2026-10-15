// ========================================================
// FILE: ./ViewModels/BoardViewModel.swift
// VERSION: v8.214 (Clean Rewrite)
// ========================================================
import Foundation
import SwiftUI
import Combine

class BoardViewModel: ObservableObject {
    @Published var isOnlineContext: Bool = false
    @Published var moveError: String?
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
    }
    func localViewState() -> LocalViewState {
        LocalViewState(scoring: localScoring, handicap: localHandicap, dismissedAtIndex: scoringDismissedAtIndex)
    }
    func restoreLocalViewState(_ state: LocalViewState) {
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
    
    private var jitterEngine: StoneJitter
    private var isSyncing = false
    private var lastObservedMoveIndex: Int = 0
    private var fullGameAnalysisTask: Task<Void, Swift.Error>?
    private var cancellables = Set<AnyCancellable>()
    private var stateSyncTimer: Timer?
    private var scrubTimer: Timer?
    private var pendingScrubIndex: Int?
    
    init(player: SGFPlayer, ogsClient: OGSClient, isAIAllowed: (() -> Bool)? = nil) {
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
        KataGoEngine.shared.$isEngineRunning.receive(on: RunLoop.main).sink { [weak self] isRunning in
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
        guard stateSyncTimer == nil else { return }
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in self?.syncState() }
        stateSyncTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func beginScrubbing() {
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
        stateSyncTimer?.invalidate()
        scrubTimer?.invalidate()
    }
    
    func resetToEmpty() {
        cancelScrubbing()
        localScoring = nil; scoringDismissedAtIndex = nil; localHandicap = 0
        fullGameAnalysisTask?.cancel()
        if KataGoEngine.shared.currentGameId != "local" {
            KataGoEngine.shared.saveAnalysisCache(for: KataGoEngine.shared.currentGameId)
        }
        KataGoEngine.shared.currentGameId = "local"
        KataGoEngine.shared.invalidateAnalysis()
        
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
        if KataGoEngine.shared.currentGameId != "local" {
            KataGoEngine.shared.saveAnalysisCache(for: KataGoEngine.shared.currentGameId)
        }
        KataGoEngine.shared.invalidateAnalysis()
        
        self.isOnlineContext = false
        
        let newGameId = wrapper.url.path.replacingOccurrences(of: "/", with: "_")
        self.engine.load(game: wrapper.game)
        _ = KataGoEngine.shared.loadAnalysisCache(for: newGameId, game: engine)
        self.jitterEngine = StoneJitter(boardSize: self.boardSize, eccentricity: CGFloat(AppSettings.shared.jitterMultiplier))
        self.lastObservedMoveIndex = self.engine.currentIndex
        self.syncState()
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
        let ai = KataGoEngine.shared.evaluateGameQuality(upTo: totalMoves, engine: engine)
        let jumps = ai.filter { $0.key > currentMoveIndex && ($0.value.quality == .poor || $0.value.quality == .disastrous) }
        if let nextMistake = jumps.keys.min() {
            seekToMove(nextMistake)
        } else {
            goToEnd()
        }
    }
    
    func seekPrevMistake() {
        let ai = KataGoEngine.shared.evaluateGameQuality(upTo: totalMoves, engine: engine)
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
        if let rejection = engine.tryPlayMove(color: engine.turn, x: -1, y: -1) {
            moveError = rejection.rawValue
            return
        }
        ghostPosition = nil
        moveError = nil
        if KataGoEngine.shared.isEngineRunning { triggerFullGameAnalysis() }
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
        _ = KataGoEngine.shared.loadAnalysisCache(for: String(gameID), game: engine)
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
        if KataGoEngine.shared.isEngineRunning {
            self.triggerFullGameAnalysis()
        }
    }
    
    func syncState() {
        stateSyncTimer?.invalidate(); stateSyncTimer = nil
        synchronizeLocalScoring()
        moveError = nil
        koPoint = engine.koPoint
        let idx = self.engine.currentIndex
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
        guard KataGoEngine.shared.isEngineRunning else { return }
        if let allowed = isAIAllowed, !allowed() { return }
        
        let payload = self.engine.getCurrentAIPayload()
        let gameId = isOnlineContext ? (ogsClient.activeGameID.map { String($0) } ?? "local") : KataGoEngine.shared.currentGameId
        
        KataGoEngine.shared.analyzeGame(
            id: gameId,
            initialStones: payload.initial,
            moves: payload.moves,
            size: self.boardSize,
            maxVisits: 50,
            settings: engine.analysisSettings
        )
    }
    func updateAnalysisPermission() {
        fullGameAnalysisTask?.cancel()
        KataGoEngine.shared.invalidateAnalysis()
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
            
            let gameId = self.isOnlineContext ? (self.ogsClient.activeGameID.map { String($0) } ?? "local") : KataGoEngine.shared.currentGameId
            
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
                    while KataGoEngine.shared.hasPendingAnalysis || self.isScrubbing {
                        try await Task.sleep(nanoseconds: 100_000_000)
                        try Task.checkCancellation()
                        guard self.isAIAllowed?() != false else { return }
                        guard KataGoEngine.shared.currentGameId == gameId else { return }
                    }
                    guard KataGoEngine.shared.isEngineRunning else { return }
                    let existingVisits = KataGoEngine.shared.currentAnalysisData[i]?.rootInfo?.visits ?? 0
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
                    guard KataGoEngine.shared.currentGameId == gameId else { return }
                    let payload = self.engine.getAIPayload(at: i)
                    KataGoEngine.shared.analyzeGame(
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
