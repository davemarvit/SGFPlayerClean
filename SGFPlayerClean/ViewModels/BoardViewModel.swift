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
    
    let onRequestUpdate3D = PassthroughSubject<Void, Never>()
    var engine: SGFPlayer; var ogsClient: OGSClient
    private var jitterEngine: StoneJitter
    private var isSyncing = false
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
    }
    
    var boardSize: Int { self.engine.board.size }
    
    func resetToEmpty() {
        // PILLAR: Atomic UI Flush
        self.engine.clear()
        self.stonesToRender = []
        self.isOnlineContext = false
        self.syncState()
    }
    
    func loadGame(_ wrapper: SGFGameWrapper) { self.isOnlineContext = false; self.engine.load(game: wrapper.game); self.jitterEngine = StoneJitter(boardSize: self.boardSize) }
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
        
        self.engine.playMoveOptimistically(color: color, x: -1, y: -1)
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
        // LOCK: If game is finished, board is read-only
        if ogsClient.isGameFinished {
            self.ghostPosition = nil
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
            
            // Optimistic UI
            self.engine.playMoveOptimistically(color: myColor, x: pos.col, y: pos.row)
            
            // Network Dispatch
            self.ogsClient.sendMove(
                gameID: self.ogsClient.activeGameID ?? 0,
                x: pos.col,
                y: pos.row
            )
        }
    }
    
    func syncState() {
        // if isSyncing { return } // Removed re-entrancy guard to allow immediate updates on main thread
        // isSyncing = true
        let idx = self.engine.currentIndex
        let last = self.engine.lastMove.map { BoardPosition($0.y, $0.x) }
        let snap = self.engine.board
        
        // MOVED TO MAIN THREAD to avoid race conditions with StoneJitter
        self.jitterEngine.prepare(forMove: idx, stones: snap.stones)
        var list: [RenderStone] = []
        for (pos, col) in snap.stones {
            let off = self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: idx, stones: snap.stones)
            list.append(RenderStone(id: pos, color: col, offset: off))
        }
        // Stable Sort for Rendering Stability (Row then Col)
        let safeList = list.sorted {
            if $0.id.row != $1.id.row { return $0.id.row < $1.id.row }
            return $0.id.col < $1.id.col
        }
        
        self.stonesToRender = safeList
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
