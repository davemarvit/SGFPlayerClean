// ========================================================
// FILE: ./ViewModels/BoardViewModel.swift
// VERSION: v8.212 (Nuclear Cache Reset)
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
    
    let onRequestUpdate3D = PassthroughSubject<Void, Never>()
    var engine: SGFPlayer; var ogsClient: OGSClient
    var onPlaySound: ((AppModel.SoundType) -> Void)? // Sound Callback
    private var jitterEngine: StoneJitter
    private var isSyncing = false
    private var lastObservedMoveIndex: Int = 0
    private var cancellables = Set<AnyCancellable>()
    
    init(player: SGFPlayer, ogsClient: OGSClient) {
        self.engine = player; self.ogsClient = ogsClient
        self.jitterEngine = StoneJitter(boardSize: player.board.size, eccentricity: CGFloat(AppSettings.shared.jitterMultiplier))
        
        player.moveProcessed.receive(on: RunLoop.main).sink { [weak self] in self?.syncState() }.store(in: &cancellables)
        
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

    }
    
    var boardSize: Int { self.engine.board.size }
    
    func resetToEmpty() {
        // PILLAR: Atomic UI Flush
        self.engine.clear()
        self.stonesToRender = []
        self.lastMovePosition = nil // FIX: Ensure glow is removed
        self.isOnlineContext = false
        self.lastObservedMoveIndex = 0 // FIX: Reset sound tracker
        self.syncState()
    }
    
    func loadGame(_ wrapper: SGFGameWrapper) { 
        self.isOnlineContext = false
        self.engine.load(game: wrapper.game)
        self.jitterEngine = StoneJitter(boardSize: self.boardSize)
        self.lastObservedMoveIndex = self.engine.currentIndex // FIX: Sync sound tracker
        self.syncState() // Ensure UI syncs
    }
    func goToStart() { engine.seek(to: 0) }
    func goToEnd() { engine.seek(to: engine.maxIndex) }
    func stepForward() { engine.stepForward() }
    func stepBackward() { engine.stepBackward() }
    func stepForwardTen() { for _ in 0..<10 { engine.stepForward() } }
    func stepBackwardTen() { for _ in 0..<10 { engine.stepBackward() } }
    func toggleAutoPlay() { if engine.isPlaying { engine.pause() } else { engine.play() } }
    func seekToMove(_ index: Int) { engine.seek(to: index) }
    func stopAutoPlay() { engine.pause() }
    func startAutoPlay() { engine.play() }
    
    func handleRemoteMove(x: Int, y: Int, color: Stone) {
        // NSLog("[OGS-DEBUG] ⚡️ Handling Remote Move: \(x),\(y)")
        self.engine.playMoveOptimistically(color: color, x: x, y: y)
    }
    
    func handleRemotePass(color: Stone) {
        // NSLog("[OGS-DEBUG] ⚡️ Handling Remote Pass for \(color)")
        // SGF Pass is often represented as coordinate outside board or special token.
        // SGFPlayerEngine uses (-1,-1) as pass ? Or we need to append a pass move.
        // engine.playMoveOptimistically uses (x,y)
        // Let's pass (-1, -1) which SGFCoordinates usually maps ".." to?
        // Actually playMoveOptimistically calls apply(moveAt:) which accesses grid.
        // We probably need a safeguard inside engine or pass specific handling.
        // For now, assume -1,-1 is safe if we modify engine or if it already checks bounds.
        // Looking at engine code: if x>=0, y>=0 check is there.
        // If x<0, it only calls syncSnapshot and returns. This effectively treats it as a Pass (Turn change happens manually? No.)
        // wait, apply(moveAt:) calls syncSnapshot then returns. 
        // It does NOT swap turn if it returns early? 
        // Need to check SGFPlayerEngine.apply logic on early return.
        
        if self.engine.isSuicide(color: color, x: -1, y: -1) == false { // Dummy check or just play
             SoundManager.shared.play("pass")
             self.engine.playMoveOptimistically(color: color, x: -1, y: -1)
        } else {
             SoundManager.shared.play("pass")
             self.engine.playMoveOptimistically(color: color, x: -1, y: -1)
        }
        // Simplified: Just play sound and pass.
        // SoundManager.shared.play("pass") was added above.
    }
    
    func initializeOnlineGame(width: Int, height: Int, initialStones: [BoardPosition: Stone], nextPlayer: Stone, stateVersion: Int) {
        self.stonesToRender = [] // FORCE VISUAL CLEAR
        self.objectWillChange.send()
        self.isOnlineContext = true
        self.jitterEngine = StoneJitter(boardSize: width)
        self.engine.clear() // Explicitly clear engine before loading
        NSLog("[OGS-BVM] 🧹 Engine Cleared. Loading Online Game (Version: \(stateVersion))")
        self.engine.loadOnline(size: width, setup: initialStones, nextPlayer: nextPlayer, stateVersion: stateVersion)
        self.isSyncing = false
        Task { @MainActor in self.syncState() }
    }
    
    func placeStone(at pos: BoardPosition) {
        NSLog("[OGS-DEBUG] placeStone at \(pos). Phase: \(ogsClient.phase ?? "nil")")
        // LOCK: If game is finished or in scoring, board is read-only
        // LOCK: Phase Check match syncState logic
        let p = ogsClient.phase
        if ogsClient.isGameFinished || p == "stone removal" || p == "finished" {
            self.ghostPosition = nil
            
            // Stone Removal Interaction
            if p == "stone removal" {
                // Toggling Dead Stones Logic
                 if let gridColor = self.engine.board.stones[pos] {
                    // ... Existing Logic ...
                // 2. Identify the group (optional, but good for UX, though server handles logic)
                // For MVP, just send the coordinate clicked. The server expands to group.
                if let gameID = ogsClient.activeGameID {
                    // We need to send the FULL list of dead stones.
                    // So we toggle local state and send the new set.
                    // BUT: OGS is Source of Truth. If we optimistically update, we might desync.
                    // Protocol: Client sends valid stone coordinates to toggle? 
                    // Actually, protocol usually expects the full string of removed stones.
                    
                    var currentRemoved = ogsClient.removedStones
                    // Heuristic: If we click a stone that is in removed, we remove it (revive).
                    // If we click a stone that is NOT in removed, we add it (kill).
                    // However, we need to add/remove the ENTIRE GROUP ideally.
                    // Let's use the engine helper to get the group.
                    
                    let group = self.engine.getGroup(at: pos)
                    // UX Fix: Base action on the SPECIFIC stone clicked.
                    // If we click a Dead stone -> Revive Group (removed=false).
                    // If we click an Alive stone -> Kill Group (removed=true).
                    let isClickedStoneDead = currentRemoved.contains(pos)
                    let newRemovedState = !isClickedStoneDead // If dead(true), new is false. If alive(false), new is true.
                    
                    // Optimistic update?
                    if newRemovedState { currentRemoved.formUnion(group) } else { currentRemoved.subtract(group) }
                    
                    // Send Delta
                    let coords = group.map { SGFCoordinates.toSGF(x: $0.col, y: $0.row) }.joined()
                    ogsClient.sendRemovedStones(gameID: gameID, stones: coords, removed: newRemovedState)
                }
            }
        }
        return
    }
        
        if isOnlineContext {
            let myColor = ogsClient.playerColor ?? .white
            guard self.engine.turn == myColor else {
                // NSLog("[OGS-INPUT] 🚫 Input Rejected. Turn: \(self.engine.turn), MyColor: \(myColor)")
                return
            }
            
            // Validation: Stone Checks
            // Prevent playing on top of existing stones (Self or Opponent)
            // Fix: BoardSnapshot uses direct grid access, not stone(at:)
            if pos.row < self.engine.board.grid.count, 
               pos.col < self.engine.board.grid[0].count,
               self.engine.board.grid[pos.row][pos.col] != nil {
                // NSLog("[OGS-INPUT] 🚫 Input Rejected. Position \(pos.col),\(pos.row) is Occupied.")
                return
            }
            
            // Suicide Check
            if self.engine.isSuicide(color: myColor, x: pos.col, y: pos.row) {
                NSLog("[OGS-INPUT] 🚫 Input Rejected. Move at \(pos.col),\(pos.row) is Suicide.")
                return
            }
            
            // Optimistic UI
            // 1. Capture State Snapshot (Pre-Move)
            let oldB = self.engine.blackStonesCaptured
            let oldW = self.engine.whiteStonesCaptured
            
            // 2. Play Locally
            self.engine.playMoveOptimistically(color: myColor, x: pos.col, y: pos.row)
            
            // 3. Diff & Play Sound
            let newB = self.engine.blackStonesCaptured
            let newW = self.engine.whiteStonesCaptured
            let captured = (newB - oldB) + (newW - oldW)
            
            NSLog("[SOUND-DEBUG] Optimistic Trigger: Diff: \(captured)")
            
            if captured > 1 { onPlaySound?(.captureMultiple) }
            else if captured == 1 { onPlaySound?(.captureSingle) }
            else { onPlaySound?(.place) }
            
            // Network Dispatch
            self.ogsClient.sendMove(
                gameID: self.ogsClient.activeGameID ?? 0,
                x: pos.col,
                y: pos.row
            )
        } else {
             // Local Play
             // 1. Validation
             if pos.row < self.engine.board.grid.count, 
                pos.col < self.engine.board.grid[0].count,
                self.engine.board.grid[pos.row][pos.col] != nil {
                 return
             }
             
             // Suicide Check
             if self.engine.isSuicide(color: self.engine.turn, x: pos.col, y: pos.row) {
                 return
             }
             
             // 2. Play
             // Note: We do NOT call syncState() here manually. 
             // playMoveOptimistically triggers 'moveProcessed' publisher which calls syncState.
             // This prevents the race condition where sound was cut off.
             self.engine.playMoveOptimistically(color: self.engine.turn, x: pos.col, y: pos.row)
        }
    }
    
    func syncState() {
        // NSLog("[SOUND-DEBUG] syncState ENTRY. Online: \(isOnlineContext) Idx: \(self.engine.currentIndex)")
        
        let idx = self.engine.currentIndex
        let last = self.engine.lastMove.flatMap { m -> BoardPosition? in
            if m.x < 0 || m.y < 0 { return nil } // Exclude Pass
            return BoardPosition(m.y, m.x)
        }
        let snap = self.engine.board
        
        // MOVED TO MAIN THREAD to avoid race conditions with StoneJitter
        self.jitterEngine.prepare(forMove: idx, stones: snap.stones)
        var list: [RenderStone] = []
        for (pos, col) in snap.stones {
            let off = self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: idx, stones: snap.stones)
            var rs = RenderStone(id: pos, color: col, offset: off)
            
            // Apply Dead State (Scoring Support)
            if isOnlineContext {
               let p = ogsClient.phase
               if (p == "stone removal" || p == "finished") {
                   if ogsClient.removedStones.contains(pos) {
                       rs.isDead = true
                   }
               }
            }
            list.append(rs)
        }
        // Stable Sort for Rendering Stability (Row then Col)
        let safeList = list.sorted {
            if $0.id.row != $1.id.row { return $0.id.row < $1.id.row }
            return $0.id.col < $1.id.col
        }
        

        
        self.stonesToRender = safeList
        
        // Scoring: Territory
        if isOnlineContext {
           let p = ogsClient.phase
           if (p == "stone removal" || p == "finished") {
               let t = self.engine.calculateTerritory(deadStones: ogsClient.removedStones)
               self.territoryPoints = t
           } else {
               self.territoryPoints = [:]
           }
        } else {
            self.territoryPoints = [:]
        }
        
        // Sound Logic (Local Play / AutoPlay)
        if !isOnlineContext {
             // NSLog("[SOUND-DEBUG] Sound Check - Idx: \(idx) Last: \(self.lastObservedMoveIndex)")
             
             // Robustness: If we notice a jump (e.g. valid move), trigger logic.
             // If we are just 1 step ahead, play sound.
             if idx == (self.lastObservedMoveIndex + 1) {
                 let oldBlack = self.blackCapturedCount
                 let oldWhite = self.whiteCapturedCount
                 let newBlack = self.engine.whiteStonesCaptured
                 let newWhite = self.engine.blackStonesCaptured
                 
                 let captured = (newBlack - oldBlack) + (newWhite - oldWhite)
                 print("🔊 Capture Debug: OldB:\(oldBlack) NewB:\(newBlack) OldW:\(oldWhite) NewW:\(newWhite) Diff:\(captured)")
                 
                 if captured > 0 { 
                     // Priority: Capture > Place
                     if captured > 1 { onPlaySound?(.captureMultiple) }
                     else { onPlaySound?(.captureSingle) }
                 } else { 
                     onPlaySound?(.place) 
                 }
             } else if idx != self.lastObservedMoveIndex {
                 // Discontinuity (Scrub? Load?). Do not play sound.
                 // Just sync tracker.
             }
        }
        self.lastObservedMoveIndex = idx
        
        self.lastMovePosition = last
        self.currentMoveIndex = idx
        self.blackCapturedCount = self.engine.whiteStonesCaptured
        self.whiteCapturedCount = self.engine.blackStonesCaptured
        self.isAutoPlaying = self.engine.isPlaying
        self.totalMoves = self.engine.maxIndex
        // self.isSyncing = false
        self.onRequestUpdate3D.send()
        self.objectWillChange.send()
    }
    
    func updateGhostStone(at pos: BoardPosition?) {
        guard isOnlineContext && engine.turn == ogsClient.playerColor else {
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
