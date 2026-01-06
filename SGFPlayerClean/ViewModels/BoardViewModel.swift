// ========================================================
// FILE: ./ViewModels/BoardViewModel.swift
// VERSION: v8.200 (Debug Instrumentation)
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
    
    // Debug: Track sync state
    private var isSyncing = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init(player: SGFPlayer, ogsClient: OGSClient) {
        self.engine = player; self.ogsClient = ogsClient
        self.jitterEngine = StoneJitter(boardSize: player.board.size)
        player.moveProcessed.receive(on: RunLoop.main).sink { [weak self] in self?.syncState() }.store(in: &cancellables)
    }
    
    var boardSize: Int { self.engine.board.size }
    
    func loadGame(_ wrapper: SGFGameWrapper) {
        print("🔍 [BoardVM] Loading local game.")
        self.isOnlineContext = false
        self.engine.load(game: wrapper.game)
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
    func undoLastOnlineMove() { engine.stepBackward() }
    
    func resetToEmpty() {
        print("🔍 [BoardVM] Resetting to empty.")
        engine.clear()
        self.isOnlineContext = false
        self.syncState()
    }
    
    func handleRemoteMove(x: Int, y: Int, playerId: Int?) {
        let color: Stone = (playerId == ogsClient.blackPlayerID) ? .black : .white
        self.engine.playMoveOptimistically(color: color, x: x, y: y)
    }
    
    func initializeOnlineGame(width: Int, height: Int, initialStones: [BoardPosition: Stone], nextTurn: Stone, moveNumber: Int) {
        print("🔍 [BoardVM v8.200] initializeOnlineGame called. Stones: \(initialStones.count)")
        self.isOnlineContext = true
        // Engine loadOnline calls reset(), which should populate the board from initialStones
        self.engine.loadOnline(size: width, setup: initialStones, nextPlayer: nextTurn, startMoveNumber: moveNumber)
        
        // Force immediate sync
        self.syncState()
        self.objectWillChange.send()
    }
    
    func placeStone(at pos: BoardPosition) {
        if isOnlineContext {
            let nextMoveNum = self.engine.serverMoveNumber + 1
            print("🔍 [BoardVM] Sending Move: \(pos.col),\(pos.row) #\(nextMoveNum)")
            self.ogsClient.sendMove(gameID: self.ogsClient.activeGameID ?? 0, x: pos.col, y: pos.row, moveNumber: nextMoveNum)
        }
    }
    
    func syncState() {
        if isSyncing {
            print("⚠️ [BoardVM] Sync SKIPPED (Already syncing)")
            return
        }
        isSyncing = true
        
        let idx = self.engine.currentIndex
        let last = self.engine.lastMove.map { BoardPosition($0.y, $0.x) }
        let snap = self.engine.board
        
        // Logging for debug
        if snap.stones.count > 0 {
            print("🔍 [BoardVM] Syncing frame \(idx). Stone count: \(snap.stones.count)")
        }
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            self.jitterEngine.prepare(forMove: idx, stones: snap.stones)
            var list: [RenderStone] = []
            for (pos, col) in snap.stones {
                let off = self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: idx, stones: snap.stones)
                list.append(RenderStone(id: pos, color: col, offset: off))
            }
            let safeList = list
            await MainActor.run {
                self.stonesToRender = safeList
                self.lastMovePosition = last
                self.currentMoveIndex = idx
                self.blackCapturedCount = self.engine.whiteStonesCaptured
                self.whiteCapturedCount = self.engine.blackStonesCaptured
                self.isAutoPlaying = self.engine.isPlaying
                self.totalMoves = self.engine.maxIndex
                
                self.isSyncing = false
                self.onRequestUpdate3D.send()
                self.objectWillChange.send()
            }
        }
    }
    
    func updateGhostStone(at pos: BoardPosition?) { self.ghostPosition = pos; self.ghostColor = self.engine.turn }
    func clearGhostStone() { self.ghostPosition = nil }
    
    func getJitterOffset(forPosition pos: BoardPosition) -> CGPoint {
        return self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: self.currentMoveIndex, stones: self.engine.board.stones)
    }
}
