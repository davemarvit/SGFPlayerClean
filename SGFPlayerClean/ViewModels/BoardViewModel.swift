// MARK: - File: BoardViewModel.swift
//
//  Architecture: Split-State Controller (v3.70)
//  - v3.70: Adds Online Replay History for "Surgical Undo".
//  - Stores move list to allow rebuilding state locally without server reload.
//

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
    @Published var boardSize: Int = 19
    @Published var currentGame: SGFGameWrapper?
    
    @Published var ghostPosition: BoardPosition?
    @Published var ghostColor: Stone?
    @Published var isProcessingMove: Bool = false

    // FLAGS
    var isHandicapGame: Bool = false
    @Published var isOnlineContext: Bool = false
    
    // ONLINE HISTORY (For Local Replay)
    private var onlineHandicapStones: [BoardPosition: Stone] = [:]
    private var onlineMoveHistory: [(x: Int, y: Int, color: Stone)] = []
    
    var totalMoves: Int { return player.maxIndex }
    
    // MARK: - Dependencies
    var player: SGFPlayer
    weak var ogsClient: OGSClient?
    var autoPlaySpeed: TimeInterval = 0.75
    private var jitter: StoneJitter
    private var cancellables = Set<AnyCancellable>()
    private var onlineLogic = OnlineGameLogic()
    
    // MARK: - Computed Logic
    var isMyTurn: Bool {
        if !isOnlineContext { return true }
        if isProcessingMove { return false }
        guard let client = ogsClient, client.isConnected,
              let myID = client.playerID,
              let currentID = client.currentPlayerID else { return false }
        return myID == currentID
    }
    
    var nextTurnColor: Stone {
        if isOnlineContext, let client = ogsClient {
            if isMyTurn, let myColor = client.playerColor { return myColor }
            if let currentID = client.currentPlayerID {
                if currentID == client.blackPlayerID { return .black }
                if currentID == client.whitePlayerID { return .white }
            }
            return onlineLogic.lastColor == .black ? .white : .black
        }
        
        if currentMoveIndex > 0 && currentMoveIndex <= player.moves.count {
            let lastMoveColor = player.moves[currentMoveIndex - 1].0
            return (lastMoveColor == Stone.black) ? Stone.white : Stone.black
        }
        return isHandicapGame ? Stone.white : Stone.black
    }

    // MARK: - Initialization
    init(player: SGFPlayer, ogsClient: OGSClient? = nil) {
        self.player = player
        self.ogsClient = ogsClient
        self.jitter = StoneJitter(boardSize: 19, eccentricity: AppSettings.shared.jitterMultiplier)
        setupObservers()
    }

    private func setupObservers() {
        player.$board.receive(on: RunLoop.main).sink { [weak self] board in
            guard let self = self else { return }
            if !self.isOnlineContext {
                self.updateLocalStones(from: board)
            }
        }.store(in: &cancellables)
        
        player.$currentIndex.receive(on: RunLoop.main).sink { [weak self] index in self?.currentMoveIndex = index }.store(in: &cancellables)
        player.$lastMove.receive(on: RunLoop.main).sink { [weak self] moveRef in self?.updateLastMove(from: moveRef) }.store(in: &cancellables)
        player.$blackCaptured.receive(on: RunLoop.main).sink { [weak self] count in self?.blackCapturedCount = count }.store(in: &cancellables)
        player.$whiteCaptured.receive(on: RunLoop.main).sink { [weak self] count in self?.whiteCapturedCount = count }.store(in: &cancellables)
        player.$isPlaying.receive(on: RunLoop.main).sink { [weak self] isPlaying in self?.isAutoPlaying = isPlaying }.store(in: &cancellables)
        
        ogsClient?.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRemoteMoveNotification(_:)), name: NSNotification.Name("OGSMoveReceived"), object: nil)
    }

    // MARK: - State Management
    func resetToEmpty() {
        DispatchQueue.main.async {
            print("📖 BoardVM: 🧹 Forced Reset")
            self.stones = [:]
            self.currentMoveIndex = 0
            self.lastMovePosition = nil
            self.ghostPosition = nil
            self.blackCapturedCount = 0
            self.whiteCapturedCount = 0
            self.isOnlineContext = false
            self.onlineLogic.reset(size: self.boardSize)
            
            self.onlineMoveHistory.removeAll()
            self.onlineHandicapStones.removeAll()
            
            self.objectWillChange.send()
        }
    }

    // MARK: - Game Loading
    func loadGame(_ game: SGFGameWrapper) {
        self.isOnlineContext = false
        loadLocalGame(game)
    }
    
    func loadLocalGame(_ game: SGFGameWrapper) {
        DispatchQueue.main.async {
            print("📖 BoardVM: Loading LOCAL game")
            self.currentGame = game
            self.boardSize = game.size
            self.player.load(game: game.game)
            self.updateLocalStones(from: self.player.board)
            self.updateLastMove(from: self.player.lastMove)
            self.currentMoveIndex = self.player.currentIndex
        }
    }
    
    func initializeOnlineGame(width: Int, height: Int, initialStones: [BoardPosition: Stone]) {
        DispatchQueue.main.async {
            print("📖 BoardVM: Initializing ONLINE game logic (Stones: \(initialStones.count))")
            self.isOnlineContext = true
            self.boardSize = width
            self.isHandicapGame = !initialStones.isEmpty
            
            self.onlineLogic.reset(size: width)
            self.onlineLogic.stones = initialStones
            
            // Replay Support
            self.onlineHandicapStones = initialStones
            self.onlineMoveHistory.removeAll()
            
            if !initialStones.isEmpty {
                self.onlineLogic.lastColor = .black
                print("📖 BoardVM: Handicap Detected. Set lastColor = Black.")
            }
            
            self.stones = initialStones
            self.lastMovePosition = nil
            self.currentMoveIndex = 0
            self.jitter = StoneJitter(boardSize: width, eccentricity: AppSettings.shared.jitterMultiplier)
            
            self.objectWillChange.send()
        }
    }

    // MARK: - User Input
    func updateGhostStone(at position: BoardPosition) {
        if isOnlineContext {
            guard isMyTurn else { clearGhostStone(); return }
        }
        guard stones[position] == nil else { clearGhostStone(); return }
        self.ghostPosition = position
        
        if isOnlineContext, let myColor = ogsClient?.playerColor {
            self.ghostColor = myColor
        } else {
            self.ghostColor = nextTurnColor
        }
    }
    
    func clearGhostStone() {
        self.ghostPosition = nil
        self.ghostColor = nil
    }
    
    func placeStone(at position: BoardPosition) {
        clearGhostStone()
        
        if isOnlineContext {
            guard let client = ogsClient, let gameID = client.activeGameID else { return }
            guard isMyTurn else { return }
            guard let myColor = client.playerColor else { return }
            
            print("📖 BoardVM: 🖱️ Clicked at \(position.col), \(position.row). Placing \(myColor)...")
            isProcessingMove = true
            scheduleSafetyUnlock()
            
            onlineLogic.place(at: position, color: myColor)
            self.stones = onlineLogic.stones
            self.lastMovePosition = position
            
            // HISTORY
            self.onlineMoveHistory.append((position.col, position.row, myColor))
            
            self.currentMoveIndex += 1
            
            self.objectWillChange.send()
            
            client.sendMove(gameID: gameID, x: position.col, y: position.row)
            return
        }
        
        let color = nextTurnColor
        player.playMoveOptimistically(color: color, x: position.col, y: position.row)
    }
    
    func passTurn() {
        clearGhostStone()
        if isOnlineContext, let client = ogsClient, let gameID = client.activeGameID {
            guard isMyTurn else { return }
            isProcessingMove = true
            scheduleSafetyUnlock()
            self.lastMovePosition = nil
            
            // HISTORY: Pass is -1, -1
            if let myColor = client.playerColor {
                self.onlineMoveHistory.append((-1, -1, myColor))
            }
            
            self.currentMoveIndex += 1
            client.sendPass(gameID: gameID)
            return
        }
        player.playMoveOptimistically(color: nextTurnColor, x: -1, y: -1)
    }
    
    func requestUndo() {
        if isOnlineContext, let client = ogsClient, let gameID = client.activeGameID {
            print("📖 BoardVM: Requesting Undo (Move: \(currentMoveIndex))")
            client.sendUndoRequest(gameID: gameID, moveNumber: currentMoveIndex)
        } else {
            previousMove()
        }
    }
    
    // MARK: - Online Replay Logic (The Surgical Fix)
    func undoLastOnlineMove() {
        guard isOnlineContext, !onlineMoveHistory.isEmpty else { return }
        
        print("📖 BoardVM: ⏪ Performing Local Undo (Replay). History size: \(onlineMoveHistory.count) -> \(onlineMoveHistory.count - 1)")
        
        // 1. Remove last move
        onlineMoveHistory.removeLast()
        
        // 2. Reset Logic to Handicap State
        onlineLogic.reset(size: boardSize)
        onlineLogic.stones = onlineHandicapStones
        if !onlineHandicapStones.isEmpty { onlineLogic.lastColor = .black }
        
        // 3. Replay History
        var newLastMove: BoardPosition? = nil
        
        for (x, y, color) in onlineMoveHistory {
            if x < 0 {
                // Pass
                newLastMove = nil
                onlineLogic.lastColor = color
            } else {
                let pos = BoardPosition(y, x)
                onlineLogic.place(at: pos, color: color)
                newLastMove = pos
            }
        }
        
        // 4. Update Published State
        self.stones = onlineLogic.stones
        self.lastMovePosition = newLastMove
        self.currentMoveIndex = onlineMoveHistory.count
        
        self.objectWillChange.send()
    }
    
    func resignGame() {
        if isOnlineContext, let client = ogsClient, let gameID = client.activeGameID {
            print("📖 BoardVM: 🏳️ Resigning Game \(gameID)")
            client.resignGame(gameID: gameID)
        }
    }
    
    private func scheduleSafetyUnlock() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if let self = self, self.isProcessingMove { self.isProcessingMove = false }
        }
    }

    // MARK: - Remote Input Handling
    @objc private func handleRemoteMoveNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let x = userInfo["x"] as? Int,
              let y = userInfo["y"] as? Int else { return }
        
        let playerId = userInfo["player_id"] as? Int
        handleRemoteMove(x: x, y: y, playerId: playerId)
    }
    
    internal func handleRemoteMove(x: Int, y: Int, playerId: Int?) {
        DispatchQueue.main.async {
            let isOptimisticEcho = (self.isProcessingMove && self.lastMovePosition == BoardPosition(y, x))
            
            self.isProcessingMove = false
            
            // If this is an echo, we already incremented the counter in placeStone.
            if isOptimisticEcho {
                print("📖 BoardVM: 🗣️ Optimistic Echo. Counter is already: \(self.currentMoveIndex)")
                return
            }
            
            var color: Stone
            if let pid = playerId, let client = self.ogsClient, pid != -1 {
                if pid == client.whitePlayerID { color = .white }
                else if pid == client.blackPlayerID { color = .black }
                else { color = (self.onlineLogic.lastColor == .black) ? .white : .black }
            } else {
                color = (self.onlineLogic.lastColor == .black) ? .white : .black
            }
            
            // HISTORY CHECK: Don't add if already latest in history (Rare race condition)
            if let last = self.onlineMoveHistory.last, last.x == x, last.y == y {
                return
            }
            
            // Add to history
            self.onlineMoveHistory.append((x, y, color))
            
            if x < 0 || y < 0 {
                // Remote Pass
                self.lastMovePosition = nil
                self.onlineLogic.lastColor = color
                self.currentMoveIndex += 1
                return
            }
            
            let pos = BoardPosition(y, x)
            
            print("📖 BoardVM: 📥 Remote Move Placed: \(color) at \(x),\(y)")
            self.onlineLogic.place(at: pos, color: color)
            self.stones = self.onlineLogic.stones
            self.lastMovePosition = pos
            
            self.currentMoveIndex += 1
            
            self.clearGhostStone()
            self.objectWillChange.send()
        }
    }

    // MARK: - Helpers
    private func updateLocalStones(from board: BoardSnapshot) {
        var newStones: [BoardPosition: Stone] = [:]
        for (y, row) in board.grid.enumerated() {
            for (x, s) in row.enumerated() {
                if let s = s { newStones[BoardPosition(y, x)] = s }
            }
        }
        self.stones = newStones
    }

    private func updateLastMove(from moveRef: MoveRef?) {
        if let move = moveRef {
            if move.x < 0 || move.y < 0 { lastMovePosition = nil }
            else { lastMovePosition = BoardPosition(move.y, move.x) }
            jitter.prepare(forMove: currentMoveIndex, stones: stones)
        } else {
            lastMovePosition = nil
        }
    }
    
    func startAutoPlay() { DispatchQueue.main.async { self.player.setPlayInterval(self.autoPlaySpeed); self.player.play() } }
    func stopAutoPlay() { player.pause() }
    func seekToMove(_ index: Int) { player.seek(to: index) }
    func goToMove(_ index: Int) { seekToMove(index) }
    func nextMove() { if currentMoveIndex < player.maxIndex { player.stepForward() } }
    func previousMove() { if currentMoveIndex > 0 { player.stepBack() } }
    func goToStart() { seekToMove(0) }
    func goToEnd() { seekToMove(player.maxIndex) }
    func toggleAutoPlay() { player.togglePlay() }
    func getJitterOffset(forPosition position: BoardPosition) -> CGPoint {
        return jitter.offset(forX: position.col, y: position.row, moveIndex: currentMoveIndex, stones: stones)
    }
}

// MARK: - Internal Module: Online Game Logic
private class OnlineGameLogic {
    var stones: [BoardPosition: Stone] = [:]
    var boardSize: Int = 19
    var lastColor: Stone?
    
    func reset(size: Int) {
        self.stones = [:]
        self.boardSize = size
        self.lastColor = nil
    }
    
    func place(at position: BoardPosition, color: Stone) {
        self.stones[position] = color
        self.lastColor = color
        
        let opponent = (color == .black) ? Stone.white : Stone.black
        let neighbors = getNeighbors(of: position)
        
        for neighbor in neighbors {
            if stones[neighbor] == opponent {
                if countLiberties(at: neighbor, color: opponent) == 0 {
                    removeGroup(at: neighbor, color: opponent)
                }
            }
        }
        
        // Suicide check
        if countLiberties(at: position, color: color) == 0 {
            // Note: In real Go, this might be invalid, but OGS handles rules.
            // We just clear the group to match visual expectation if it happens.
            removeGroup(at: position, color: color)
        }
    }
    
    private func getNeighbors(of pos: BoardPosition) -> [BoardPosition] {
        let deltas = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        var result: [BoardPosition] = []
        for (dr, dc) in deltas {
            let r = pos.row + dr
            let c = pos.col + dc
            if r >= 0 && r < boardSize && c >= 0 && c < boardSize {
                result.append(BoardPosition(r, c))
            }
        }
        return result
    }
    
    private func countLiberties(at start: BoardPosition, color: Stone) -> Int {
        var visited: Set<BoardPosition> = []
        var stack: [BoardPosition] = [start]
        var liberties = 0
        visited.insert(start)
        
        while !stack.isEmpty {
            let current = stack.removeLast()
            for neighbor in getNeighbors(of: current) {
                if let stone = stones[neighbor] {
                    if stone == color && !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        stack.append(neighbor)
                    }
                } else {
                    liberties += 1
                }
            }
        }
        return liberties
    }
    
    private func removeGroup(at start: BoardPosition, color: Stone) {
        var visited: Set<BoardPosition> = []
        var group: [BoardPosition] = [start]
        var pointer = 0
        visited.insert(start)
        
        while pointer < group.count {
            let current = group[pointer]
            pointer += 1
            for neighbor in getNeighbors(of: current) {
                if stones[neighbor] == color && !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    group.append(neighbor)
                }
            }
        }
        for pos in group { stones[pos] = nil }
    }
}
