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
        self.jitterEngine = StoneJitter(boardSize: player.board.size)
        player.moveProcessed.receive(on: RunLoop.main).sink { [weak self] in self?.syncState() }.store(in: &cancellables)
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
    
    func handleRemoteMove(x: Int, y: Int, color: Stone) {
        self.engine.playMoveOptimistically(color: color, x: x, y: y)
    }
    
    func initializeOnlineGame(width: Int, height: Int, initialStones: [BoardPosition: Stone], nextPlayer: Stone, stateVersion: Int) {
        self.isOnlineContext = true
        self.jitterEngine = StoneJitter(boardSize: width)
        self.engine.loadOnline(size: width, setup: initialStones, nextPlayer: nextPlayer, stateVersion: stateVersion)
        self.isSyncing = false
        Task { @MainActor in self.syncState() }
    }
    
    func placeStone(at pos: BoardPosition) {
        if isOnlineContext {
            let myColor = ogsClient.playerColor ?? .white
            guard self.engine.turn == myColor else { return }
            
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
        if isSyncing { return }
        isSyncing = true
        let idx = self.engine.currentIndex
        let last = self.engine.lastMove.map { BoardPosition($0.y, $0.x) }
        let snap = self.engine.board
        
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
