// MARK: - File: BoardViewModel.swift (v8.123)
import Foundation
import SwiftUI
import Combine
import QuartzCore

class BoardViewModel: ObservableObject {
    @Published var isOnlineContext: Bool = false
    @Published var lastMovePosition: BoardPosition?
    @Published var currentMoveIndex: Int = 0
    @Published var totalMoves: Int = 0
    @Published var isAutoPlaying: Bool = false
    @Published var blackCapturedCount: Int = 0
    @Published var whiteCapturedCount: Int = 0
    @Published var stonesToRender: [RenderStone] = []
    @Published var ghostPosition: BoardPosition?
    @Published var ghostColor: Stone?
    @Published var currentGame: SGFGameWrapper?
    
    let onRequestUpdate3D = PassthroughSubject<Void, Never>()
    
    var engine: SGFPlayer; var ogsClient: OGSClient
    private var jitterEngine: StoneJitter
    private var syncTask: Task<Void, Never>?
    private var isSyncing = false
    private var cancellables = Set<AnyCancellable>()

    init(player: SGFPlayer, ogsClient: OGSClient) {
        self.engine = player; self.ogsClient = ogsClient
        self.jitterEngine = StoneJitter(boardSize: player.board.size)
        player.moveProcessed.receive(on: RunLoop.main).sink { [weak self] in self?.syncState() }.store(in: &cancellables)
    }
    
    var boardSize: Int { self.engine.board.size }
    var stones: [BoardPosition: Stone] { self.engine.board.stones }

    func stepForward() { self.engine.stepForward() }
    func stepBackward() { self.engine.stepBackward() }
    func stepForwardTen() { for _ in 0..<10 { self.engine.stepForward() } }
    func stepBackwardTen() { for _ in 0..<10 { self.engine.stepBackward() } }
    func goToStart() { self.engine.seek(to: 0) }
    func goToEnd() { self.engine.seek(to: self.engine.maxIndex) }
    func play() { self.engine.play() }
    func pause() { self.engine.pause() }
    func stopAutoPlay() { pause() }
    func undoLastOnlineMove() { self.engine.stepBackward() }
    func toggleAutoPlay() { if self.isAutoPlaying { pause() } else { play() } }
    func seekToMove(_ index: Int) { self.engine.seek(to: index) }
    func resetToEmpty() { self.engine.clear(); self.isOnlineContext = false; self.syncState() }
    func loadGame(_ wrapper: SGFGameWrapper) { self.isOnlineContext = false; self.currentGame = wrapper; self.engine.load(game: wrapper.game) }
    func handleRemoteMove(x: Int, y: Int, playerId: Int?) { self.engine.playMoveOptimistically(color: (playerId == ogsClient.blackPlayerID) ? .black : .white, x: x, y: y) }
    func initializeOnlineGame(width: Int, height: Int, initialStones: [BoardPosition: Stone]) { self.engine.clear(); self.isOnlineContext = true; self.syncState() }
    func placeStone(at pos: BoardPosition) { if isOnlineContext { self.ogsClient.sendMove(gameID: self.ogsClient.activeGameID ?? 0, x: pos.col, y: pos.row) } }
    
    func syncState() {
        if isSyncing { return }; isSyncing = true
        syncTask?.cancel()
        let idx = self.engine.currentIndex; let last = self.engine.lastMove.map { BoardPosition($0.y, $0.x) }
        let snap = self.engine.board; let blackC = self.engine.whiteStonesCaptured; let whiteC = self.engine.blackStonesCaptured

        syncTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            self.jitterEngine.prepare(forMove: idx, stones: snap.stones)
            var list: [RenderStone] = []
            for (pos, col) in snap.stones {
                if Task.isCancelled { break }
                let off = self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: idx, stones: snap.stones)
                list.append(RenderStone(id: pos, color: col, offset: off))
            }
            await MainActor.run {
                defer { self.isSyncing = false }
                if Task.isCancelled { return }
                self.currentMoveIndex = idx; self.stonesToRender = list; self.lastMovePosition = last
                self.blackCapturedCount = blackC; self.whiteCapturedCount = whiteC
                self.totalMoves = self.engine.maxIndex; self.isAutoPlaying = self.engine.isPlaying
                self.onRequestUpdate3D.send()
                self.objectWillChange.send()
            }
        }
    }
    func getJitterOffset(forPosition pos: BoardPosition) -> CGPoint { return self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: self.currentMoveIndex, stones: self.stones) }
    func updateGhostStone(at pos: BoardPosition?) { self.ghostPosition = pos; self.ghostColor = self.engine.turn }
    func clearGhostStone() { self.ghostPosition = nil }
}
