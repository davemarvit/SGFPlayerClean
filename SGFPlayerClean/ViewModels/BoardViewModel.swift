// ========================================================
// FILE: ./ViewModels/BoardViewModel.swift
// VERSION: v8.214 (Clean Rewrite)
// ========================================================
import Foundation
import SwiftUI
import Combine

class BoardViewModel: ObservableObject {
    @Published var isOnlineContext: Bool = false
    @Published var lastMovePosition: BoardPosition?
    @Published var currentMoveIndex: Int = 0
    @Published var stonesToRender: [RenderStone] = []
    @Published var ghostPosition: BoardPosition?
    @Published var ghostColor: Stone?
    @Published var blackCapturedCount: Int = 0
    @Published var whiteCapturedCount: Int = 0
    @Published var isAutoPlaying: Bool = false
    @Published var totalMoves: Int = 0
    @Published var territoryPoints: [BoardPosition: Stone] = [:]
    @Published var aiAnalysisProgress: Double = 0.0
    
    let onRequestUpdate3D = PassthroughSubject<Void, Never>()
    var engine: SGFPlayer
    var ogsClient: OGSClient
    var onPlaySound: ((AppModel.SoundType) -> Void)?
    var isAIAllowed: (() -> Bool)?
    
    private var jitterEngine: StoneJitter
    private var isSyncing = false
    private var lastObservedMoveIndex: Int = 0
    private var fullGameAnalysisTask: Task<Void, Swift.Error>?
    private var cancellables = Set<AnyCancellable>()
    
    init(player: SGFPlayer, ogsClient: OGSClient, isAIAllowed: (() -> Bool)? = nil) {
        self.engine = player
        self.ogsClient = ogsClient
        self.isAIAllowed = isAIAllowed
        self.jitterEngine = StoneJitter(boardSize: player.board.size, eccentricity: CGFloat(AppSettings.shared.jitterMultiplier))
        
        player.moveProcessed.receive(on: RunLoop.main).sink { [weak self] in self?.syncState() }.store(in: &cancellables)
        
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
        
        // FIX: Sync Captures from OGSClient
        ogsClient.$blackCaptures.receive(on: RunLoop.main).sink { [weak self] val in
            if self?.isOnlineContext == true { self?.blackCapturedCount = val }
        }.store(in: &cancellables)
        
        ogsClient.$whiteCaptures.receive(on: RunLoop.main).sink { [weak self] val in
             if self?.isOnlineContext == true { self?.whiteCapturedCount = val }
        }.store(in: &cancellables)
        
        // Trigger initial analysis once engine boots up
        KataGoEngine.shared.$isEngineRunning.receive(on: RunLoop.main).sink { [weak self] isRunning in
            if isRunning {
                self?.requestAnalysisIfNeeded()
            }
        }.store(in: &cancellables)
    }
    
    var boardSize: Int { self.engine.board.size }
    
    func resetToEmpty() {
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
        fullGameAnalysisTask?.cancel()
        if KataGoEngine.shared.currentGameId != "local" {
            KataGoEngine.shared.saveAnalysisCache(for: KataGoEngine.shared.currentGameId)
        }
        KataGoEngine.shared.invalidateAnalysis()
        
        self.isOnlineContext = false
        
        let newGameId = wrapper.url.path.replacingOccurrences(of: "/", with: "_")
        _ = KataGoEngine.shared.loadAnalysisCache(for: newGameId)
        
        self.engine.load(game: wrapper.game)
        self.jitterEngine = StoneJitter(boardSize: self.boardSize)
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
    
    func handleRemoteMove(x: Int, y: Int, color: Stone) {
        self.engine.playMoveOptimistically(color: color, x: x, y: y)
    }
    
    func handleRemotePass(color: Stone) {
        SoundManager.shared.play("pass")
        self.engine.playMoveOptimistically(color: color, x: -1, y: -1)
    }
    
    func initializeOnlineGame(width: Int, height: Int, initialStones: [BoardPosition: Stone], nextPlayer: Stone, stateVersion: Int) {
        fullGameAnalysisTask?.cancel()
        _ = KataGoEngine.shared.loadAnalysisCache(for: ogsClient.activeGameID.map(String.init) ?? "local")
        self.stonesToRender = []
        self.objectWillChange.send()
        self.isOnlineContext = true
        self.jitterEngine = StoneJitter(boardSize: width)
        self.engine.clear()
        NSLog("[OGS-BVM] 🧹 Engine Cleared. Loading Online Game (Version: \(stateVersion))")
        self.engine.loadOnline(size: width, setup: initialStones, nextPlayer: nextPlayer, stateVersion: stateVersion)
        self.isSyncing = false
        Task { @MainActor in self.syncState() }
    }
    
    func placeStone(at pos: BoardPosition) {
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
            guard ogsClient.isConnected, ogsClient.isSocketAuthenticated, ogsClient.isGameParticipant,
                  engine.currentIndex == engine.maxIndex else { return }
            // SECURITY CHECK 1: Engine Consistency
            // If the local engine already knows it's the opponent's turn, we must block consecutive plays locally.
            // This prevents rapidly placing multiple stones if the server's turn packet is delayed.
            let myColor = ogsClient.playerColor ?? .white
            if self.engine.turn != myColor {
                NSLog("[Input] Ignored: Engine Turn Sync. Engine Turn is \(self.engine.turn), but my color is \(myColor). Waiting for opponent.")
                return
            }
            
            // SECURITY CHECK 2: Server Authority
            // Normally, we trust the strict ID Check
            var serverSaysMyTurn = (ogsClient.playerID != nil && ogsClient.playerID == ogsClient.currentPlayerID)
            
            // FALLBACK: If the clock payload or gameData missed the explicit ID toggle but the engine is perfectly aligned
            if !serverSaysMyTurn {
                if self.engine.turn == myColor {
                    serverSaysMyTurn = true
                    NSLog("[OGS-SYNC] ⚠️ Warning: currentPlayerID out of sync (\(ogsClient.currentPlayerID ?? -1)), but Engine Turn (\(myColor)) aligned. Allowing move.")
                }
            }
            
            guard serverSaysMyTurn else {
                NSLog("[Input] Ignored: Not My Turn (Server Authority). MyID: \(ogsClient.playerID ?? -1). Current: \(ogsClient.currentPlayerID ?? -1).")
                return
            }
            
            if pos.row < self.engine.board.grid.count, 
               pos.col < self.engine.board.grid[0].count,
               self.engine.board.grid[pos.row][pos.col] != nil {
                NSLog("[Input] Ignored: Spot Occupied.")
                return
            }
            
            if self.engine.isSuicide(color: myColor, x: pos.col, y: pos.row) {
                NSLog("[Input] Ignored: Suicide Move.")
                return
            }
            
            let oldB = self.engine.blackStonesCaptured
            let oldW = self.engine.whiteStonesCaptured
            
            self.ghostPosition = nil
            self.engine.playMoveOptimistically(color: myColor, x: pos.col, y: pos.row)
            
            let newB = self.engine.blackStonesCaptured
            let newW = self.engine.whiteStonesCaptured
            let captured = (newB - oldB) + (newW - oldW)
            
            if captured > 1 { onPlaySound?(.captureMultiple) }
            else if captured == 1 { onPlaySound?(.captureSingle) }
            else { onPlaySound?(.place) }
            
            self.ogsClient.sendMove(gameID: self.ogsClient.activeGameID ?? 0, x: pos.col, y: pos.row)
        } else {
             if pos.row < self.engine.board.grid.count, 
                pos.col < self.engine.board.grid[0].count,
                self.engine.board.grid[pos.row][pos.col] != nil {
                 return
             }
             if self.engine.isSuicide(color: self.engine.turn, x: pos.col, y: pos.row) { return }
             self.engine.playMoveOptimistically(color: self.engine.turn, x: pos.col, y: pos.row)
        }
        
        // Trigger background analysis sweep immediately after a move is registered (only if engine is running)
        if KataGoEngine.shared.isEngineRunning {
            self.triggerFullGameAnalysis()
        }
    }
    
    func syncState() {
        let idx = self.engine.currentIndex
        NSLog("[OGS-UI-DEBUG] 🎨 syncState Entry. Index: \(idx). Online: \(isOnlineContext)")
        let last = self.engine.lastMove.flatMap { m -> BoardPosition? in
            if m.x < 0 || m.y < 0 { return nil }
            return BoardPosition(m.y, m.x)
        }
        let snap = self.engine.board
        
        self.jitterEngine.prepare(forMove: idx, stones: snap.stones)
        var list: [RenderStone] = []
        for (pos, col) in snap.stones {
            let off = self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: idx, stones: snap.stones)
            var rs = RenderStone(id: pos, color: col, offset: off)
            
            if isOnlineContext {
               let p = ogsClient.phase
               if (OGSScoring.isScoring(p) || p == "finished") && engine.currentIndex == engine.maxIndex {
                   if ogsClient.removedStones.contains(pos) { rs.isDead = true }
               }
            }
            list.append(rs)
        }
        let safeList = list.sorted {
            if $0.id.row != $1.id.row { return $0.id.row < $1.id.row }
            return $0.id.col < $1.id.col
        }
        
        self.stonesToRender = safeList
        
        if isOnlineContext {
           let p = ogsClient.phase
           if (OGSScoring.isScoring(p) || p == "finished") && self.engine.currentIndex == self.engine.maxIndex {
                let t = ogsClient.scoreSummary?.positions(width: snap.size, height: snap.size)
                    ?? self.engine.calculateTerritory(deadStones: ogsClient.removedStones)

                // Debug Territory
                if !t.isEmpty {
                     let counts = t.values.reduce(into: ["Black":0, "White":0]) { $0[$1 == .black ? "Black":"White", default: 0] += 1 }
                     NSLog("[OGS-TERRITORY] 🏳️🏴 Calculated: \(counts). Dead Stones: \(ogsClient.removedStones.count)")
                }

                self.territoryPoints = t
           } else {
               self.territoryPoints = [:]
           }
        } else {
            self.territoryPoints = [:]
        }
        
        if !isOnlineContext {
             if idx == (self.lastObservedMoveIndex + 1) {
                 let oldBlack = self.blackCapturedCount
                 let oldWhite = self.whiteCapturedCount
                 let newBlack = self.engine.whiteStonesCaptured
                 let newWhite = self.engine.blackStonesCaptured
                 
                 let captured = (newBlack - oldBlack) + (newWhite - oldWhite)
                 
                 if captured > 0 { 
                     if captured > 1 { onPlaySound?(.captureMultiple) }
                     else { onPlaySound?(.captureSingle) }
                 } else { 
                     onPlaySound?(.place) 
                 }
             }
        }
        self.lastObservedMoveIndex = idx
        
        self.lastMovePosition = last
        self.currentMoveIndex = idx
        
        if isOnlineContext {
            // Use Server's authoritative capture counts
            self.blackCapturedCount = ogsClient.blackCaptures
            self.whiteCapturedCount = ogsClient.whiteCaptures
            
            // Debug Log for Critical Zero-Capture Issue
            // NSLog("[OGS-SYNC] 🔄 Sync Captures: B:\(self.blackCapturedCount) W:\(self.whiteCapturedCount) (Client: \(ogsClient.blackCaptures)/\(ogsClient.whiteCaptures))")
            self.whiteCapturedCount = ogsClient.whiteCaptures
        } else {
            // Use Local Engine's calculated counts
            self.blackCapturedCount = self.engine.whiteStonesCaptured
            self.whiteCapturedCount = self.engine.blackStonesCaptured
        }
        
        self.isAutoPlaying = self.engine.isPlaying
        self.totalMoves = self.engine.maxIndex
        self.onRequestUpdate3D.send()
        self.objectWillChange.send()
        
        self.requestAnalysisIfNeeded()
    }
    
    private func requestAnalysisIfNeeded() {
        guard KataGoEngine.shared.isEngineRunning else { return }
        if let allowed = isAIAllowed, !allowed() { return }
        
        let payload = self.engine.getCurrentAIPayload()
        let gameId = isOnlineContext ? (ogsClient.activeGameID.map { String($0) } ?? "local") : KataGoEngine.shared.currentGameId
        
        KataGoEngine.shared.analyzeGame(
            id: gameId,
            initialStones: payload.initial,
            moves: payload.moves,
            size: self.boardSize,
            komi: 6.5, // Could be extracted from game info if available
            maxVisits: 50 // Fast background sync sweep
        )
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
                    guard KataGoEngine.shared.currentGameId == gameId else { return }
                    let payload = self.engine.getAIPayload(at: i)
                    KataGoEngine.shared.analyzeGame(
                        id: gameId,
                        initialStones: payload.initial,
                        moves: payload.moves,
                        size: self.boardSize,
                        komi: 6.5,
                        maxVisits: depth
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
        guard isOnlineContext && engine.turn == ogsClient.playerColor else {
            self.ghostPosition = nil
            return
        }
        
        let p = ogsClient.phase ?? "unknown"
        if OGSScoring.isScoring(p) || p == "finished" || ogsClient.isGameFinished {
            self.ghostPosition = nil
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
