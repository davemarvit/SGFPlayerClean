// MARK: - File: BoardViewModel.swift
import Foundation
import Combine
import SwiftUI

class BoardViewModel: ObservableObject {

    // MARK: - Published State
    @Published var currentMoveIndex: Int = 0
    @Published var stones: [BoardPosition: Stone] = [:]
    @Published var lastMovePosition: BoardPosition?
    @Published var blackCapturedCount: Int = 0
    @Published var whiteCapturedCount: Int = 0
    @Published var isAutoPlaying: Bool = false
    @Published var currentGame: SGFGameWrapper?
    @Published var boardSize: Int = 19
    
    // NEW: Ghost Stone State
    @Published var ghostPosition: BoardPosition?
    @Published var ghostColor: Stone?

    // NEW: Handicap State
    var isHandicapGame: Bool = false

    var totalMoves: Int { return player.maxIndex }

    // MARK: - Dependencies
    var player: SGFPlayer
    weak var ogsClient: OGSClient?
    var autoPlaySpeed: TimeInterval = 0.75
    private var jitter: StoneJitter
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(player: SGFPlayer, ogsClient: OGSClient? = nil) {
        self.player = player
        self.ogsClient = ogsClient
        self.jitter = StoneJitter(boardSize: 19, eccentricity: AppSettings.shared.jitterMultiplier)
        setupPlayerObservers()
        setupSettingsObservers()
        setupOGSObservers()
    }

    private func setupPlayerObservers() {
        player.$board.receive(on: RunLoop.main).sink { [weak self] board in self?.updateStones(from: board) }.store(in: &cancellables)
        player.$currentIndex.receive(on: RunLoop.main).sink { [weak self] index in self?.currentMoveIndex = index }.store(in: &cancellables)
        player.$lastMove.receive(on: RunLoop.main).sink { [weak self] moveRef in self?.updateLastMove(from: moveRef) }.store(in: &cancellables)
        player.$blackCaptured.receive(on: RunLoop.main).sink { [weak self] count in self?.blackCapturedCount = count }.store(in: &cancellables)
        player.$whiteCaptured.receive(on: RunLoop.main).sink { [weak self] count in self?.whiteCapturedCount = count }.store(in: &cancellables)
        player.$isPlaying.receive(on: RunLoop.main).sink { [weak self] isPlaying in self?.isAutoPlaying = isPlaying }.store(in: &cancellables)
    }

    private func setupSettingsObservers() {
        AppSettings.shared.$jitterMultiplier.receive(on: RunLoop.main).sink { [weak self] m in self?.jitter.setEccentricity(m); self?.objectWillChange.send() }.store(in: &cancellables)
        AppSettings.shared.$moveInterval.receive(on: RunLoop.main).sink { [weak self] i in self?.autoPlaySpeed = i; self?.player.setPlayInterval(i) }.store(in: &cancellables)
    }
    
    private func setupOGSObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleRemoteMoveNotification(_:)), name: NSNotification.Name("OGSMoveReceived"), object: nil)
    }

    // MARK: - Game Loading
    func loadGame(_ game: SGFGameWrapper) {
        DispatchQueue.main.async {
            print("📖 BoardViewModel: Loading game: \(game.title ?? "Untitled")")
            self.currentGame = game
            self.boardSize = game.size
            self.isHandicapGame = false
            self.jitter = StoneJitter(boardSize: self.boardSize, eccentricity: AppSettings.shared.jitterMultiplier)
            
            self.player.load(game: game.game)
            
            self.updateStones(from: self.player.board)
            self.updateLastMove(from: self.player.lastMove)
            self.currentMoveIndex = self.player.currentIndex
        }
    }
    
    // MARK: - Logic: Color Calculation
    var nextTurnColor: Stone {
        // Look at previous move to determine next turn
        if currentMoveIndex > 0 && currentMoveIndex <= player.moves.count {
            let lastMoveColor = player.moves[currentMoveIndex - 1].0
            return (lastMoveColor == .black) ? .white : .black
        }
        return isHandicapGame ? .white : .black
    }

    // MARK: - User Input & Ghost
    
    func updateGhostStone(at position: BoardPosition) {
        guard let client = ogsClient, client.isConnected, client.activeGameID != nil else {
            clearGhostStone()
            return
        }
        
        guard let myColor = client.playerColor else {
            clearGhostStone()
            return
        }
        
        if nextTurnColor != myColor {
            clearGhostStone()
            return
        }
        
        guard stones[position] == nil else {
            clearGhostStone()
            return
        }
        
        self.ghostPosition = position
        self.ghostColor = nextTurnColor
    }
    
    func clearGhostStone() {
        self.ghostPosition = nil
        self.ghostColor = nil
    }
    
    func placeStone(at position: BoardPosition) {
        guard let client = ogsClient else { return }
        
        print("BoardVM: 🖱️ placeStone requested at \(position)")
        
        guard let gameID = client.activeGameID, client.isConnected else {
            print("BoardVM: ❌ Rejected - Not connected or no active game.")
            return
        }
        
        guard let myColor = client.playerColor else {
            print("BoardVM: ❌ Rejected - Player color unknown.")
            return
        }
        
        guard nextTurnColor == myColor else {
            print("BoardVM: ❌ Rejected - Not my turn. Me: \(myColor), Next: \(nextTurnColor)")
            return
        }
        
        // Success
        client.sendMove(gameID: gameID, x: position.col, y: position.row)
        clearGhostStone()
    }

    // MARK: - Remote Input (OGS)
    
    @objc private func handleRemoteMoveNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let x = userInfo["x"] as? Int,
              let y = userInfo["y"] as? Int else { return }
        handleRemoteMove(x: x, y: y)
    }
    
    private func handleRemoteMove(x: Int, y: Int) {
        DispatchQueue.main.async {
            if let _ = self.stones[BoardPosition(y, x)] { return }
            
            let color = self.nextTurnColor
            print("BoardVM: 📥 Remote Move: \(color) at \(x), \(y)")
            
            self.player.playMoveOptimistically(color: color, x: x, y: y)
        }
    }

    // MARK: - Navigation
    func seekToMove(_ index: Int) { player.seek(to: index) }
    func goToMove(_ index: Int) { seekToMove(index) }
    func nextMove() { if currentMoveIndex < player.maxIndex { player.stepForward() } }
    func previousMove() { if currentMoveIndex > 0 { player.stepBack() } }
    func goToStart() { seekToMove(0) }
    func goToEnd() { seekToMove(player.maxIndex) }

    // MARK: - Auto-Play
    func toggleAutoPlay() { player.togglePlay() }
    
    func startAutoPlay() {
        DispatchQueue.main.async {
            self.player.setPlayInterval(self.autoPlaySpeed)
            self.player.play()
        }
    }
    
    func stopAutoPlay() { player.pause() }

    // MARK: - Helpers
    private func updateStones(from board: BoardSnapshot) {
        var newStones: [BoardPosition: Stone] = [:]
        for (y, row) in board.grid.enumerated() {
            for (x, stone) in row.enumerated() {
                if let stone = stone { newStones[BoardPosition(y, x)] = stone }
            }
        }
        self.stones = newStones
    }

    private func updateLastMove(from moveRef: MoveRef?) {
        if let move = moveRef {
            lastMovePosition = BoardPosition(move.y, move.x)
            jitter.prepare(forMove: currentMoveIndex, stones: stones)
        } else {
            lastMovePosition = nil
        }
    }

    func getJitterOffset(forPosition position: BoardPosition) -> CGPoint {
        return jitter.offset(forX: position.col, y: position.row, moveIndex: currentMoveIndex, stones: stones)
    }
}
