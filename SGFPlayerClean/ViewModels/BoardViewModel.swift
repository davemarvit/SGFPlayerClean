// MARK: - File: BoardViewModel.swift (v4.208)
import Foundation
import SwiftUI
import Combine

class BoardViewModel: ObservableObject {
    @Published var isOnlineContext: Bool = false
    @Published var lastMovePosition: BoardPosition?
    @Published var currentMoveIndex: Int = 0
    @Published var totalMoves: Int = 0
    @Published var isAutoPlaying: Bool = false
    @Published var whiteCapturedCount: Int = 0
    @Published var blackCapturedCount: Int = 0
    @Published var ghostPosition: BoardPosition?
    @Published var ghostColor: Stone?
    @Published var currentGame: SGFGameWrapper?
    @Published var isProcessingMove: Bool = false
    
    var engine: SGFPlayer; var ogsClient: OGSClient
    private var jitterEngine: StoneJitter
    private var cancellables = Set<AnyCancellable>()
    
    init(player: SGFPlayer, ogsClient: OGSClient) {
        self.engine = player; self.ogsClient = ogsClient
        self.jitterEngine = StoneJitter(boardSize: player.board.size)
        player.objectWillChange.sink { [weak self] _ in self?.syncState() }.store(in: &cancellables)
    }
    
    func previousMove() { self.engine.stepBack(); self.syncState() }
    func nextMove() { self.engine.stepForward(); self.syncState() }
    func stepBackward() { previousMove() }; func stepForward() { nextMove() }
    func goToStart() { self.engine.seek(to: 0); self.syncState() }
    func goToEnd() { self.engine.seek(to: self.engine.maxIndex); self.syncState() }
    func play() { self.engine.play(); self.syncState() }
    func pause() { self.engine.pause(); self.syncState() }
    func toggleAutoPlay() { if self.isAutoPlaying { pause() } else { play() } }
    func seekToMove(_ index: Int) { self.engine.seek(to: index); self.syncState() }
    func handleRemoteMove(x: Int, y: Int, playerId: Int?) {
        let color: Stone = (playerId == ogsClient.blackPlayerID) ? .black : .white
        self.engine.playMoveOptimistically(color: color, x: x, y: y); self.syncState()
    }
    func resetToEmpty() { self.engine.clear(); self.isOnlineContext = false; self.syncState() }
    var boardSize: Int { self.engine.board.size }; var nextTurnColor: Stone { self.engine.turn }
    var stones: [BoardPosition: Stone] {
        self.engine.board.grid.enumerated().reduce(into: [:]) { dict, row in
            for (x, stone) in row.element.enumerated() { if let s = stone { dict[BoardPosition(row.offset, x)] = s } }
        }
    }
    func placeStone(at pos: BoardPosition) {
        if isOnlineContext { self.ogsClient.sendMove(gameID: self.ogsClient.activeGameID ?? 0, x: pos.col, y: pos.row) }
        else { self.engine.playMoveOptimistically(color: self.engine.turn, x: pos.col, y: pos.row) }
    }
    func syncState() {
        DispatchQueue.main.async {
            self.currentMoveIndex = self.engine.currentIndex; self.totalMoves = self.engine.moves.count
            self.isAutoPlaying = self.engine.isPlaying; self.blackCapturedCount = self.engine.blackCaptured; self.whiteCapturedCount = self.engine.whiteCaptured
            self.jitterEngine.prepare(forMove: self.currentMoveIndex, stones: self.stones)
            if let last = self.engine.lastMove { self.lastMovePosition = BoardPosition(last.y, last.x) }
            self.objectWillChange.send()
        }
    }
    func loadGame(_ wrapper: SGFGameWrapper) { self.isOnlineContext = false; self.currentGame = wrapper; self.engine.load(game: wrapper.game); self.syncState() }
    func initializeOnlineGame(width: Int, height: Int, initialStones: [BoardPosition: Stone]) { self.engine.clear(); self.isOnlineContext = true; self.syncState() }
    func getJitterOffset(forPosition pos: BoardPosition) -> CGPoint { self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: self.currentMoveIndex, stones: self.stones) }
    func updateGhostStone(at pos: BoardPosition?) { self.ghostPosition = pos; self.ghostColor = self.engine.turn }
    func clearGhostStone() { self.ghostPosition = nil }
    func stopAutoPlay() { self.engine.pause(); self.syncState() }
    func undoLastOnlineMove() { self.engine.stepBack(); self.syncState() }
}
