//
//  BoardViewModel.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Manages game state, navigation, and local SGF file playback
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
    @Published var currentGame: SGFGameWrapper?
    @Published var boardSize: Int = 19

    var totalMoves: Int { return player.maxIndex }

    // MARK: - Dependencies
    var player: SGFPlayer
    var autoPlaySpeed: TimeInterval = 0.75
    private var jitter: StoneJitter
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(player: SGFPlayer) {
        self.player = player
        self.jitter = StoneJitter(boardSize: 19, eccentricity: AppSettings.shared.jitterMultiplier)
        setupPlayerObservers()
        setupSettingsObservers()
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

    // MARK: - Game Loading
    func loadGame(_ game: SGFGameWrapper) {
        // Ensure Main Thread
        DispatchQueue.main.async {
            print("📖 BoardViewModel: Loading game: \(game.title ?? "Untitled")")
            self.currentGame = game
            self.boardSize = game.size
            self.jitter = StoneJitter(boardSize: self.boardSize, eccentricity: AppSettings.shared.jitterMultiplier)
            
            self.player.load(game: game.game)
            
            // Force update local state immediately
            self.updateStones(from: self.player.board)
            self.updateLastMove(from: self.player.lastMove)
            self.currentMoveIndex = self.player.currentIndex
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
            print("▶️ BoardViewModel: Starting Auto-Play at \(self.autoPlaySpeed)s interval")
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
