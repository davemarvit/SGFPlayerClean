//
//  BoardViewModel.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Manages game state, navigation, and local SGF file playback
//  WIRED TO REAL SGFPLAYER - Phase 1.3
//

import Foundation
import Combine

/// Manages the state and logic for displaying and navigating Go games
/// Wraps SGFPlayer to provide clean ViewModel interface
class BoardViewModel: ObservableObject {

    // MARK: - Published State

    /// Current position in the game (0 = start, moves.count = end)
    @Published var currentMoveIndex: Int = 0

    /// All stones currently on the board (key = position, value = stone color)
    @Published var stones: [BoardPosition: Stone] = [:]

    /// Position of the last move played (for highlighting)
    @Published var lastMovePosition: BoardPosition?

    /// Number of white stones captured by black
    @Published var blackCapturedCount: Int = 0

    /// Number of black stones captured by white
    @Published var whiteCapturedCount: Int = 0

    /// Whether auto-play is currently running
    @Published var isAutoPlaying: Bool = false

    /// Current game loaded (nil if no game)
    @Published var currentGame: SGFGameWrapper?

    /// Board size (9, 13, or 19)
    @Published var boardSize: Int = 19

    // MARK: - Dependencies

    /// SGF player engine - handles SGF parsing and game logic
    private var player: SGFPlayer

    /// Auto-play speed (seconds between moves)
    var autoPlaySpeed: TimeInterval = 0.75

    // MARK: - Internal State

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(player: SGFPlayer) {
        self.player = player

        // Subscribe to SGFPlayer state changes
        setupPlayerObservers()
    }

    /// Convenience init for standalone use
    convenience init() {
        self.init(player: SGFPlayer())
    }

    // MARK: - Setup

    private func setupPlayerObservers() {
        // Observe player's board changes
        player.$board
            .sink { [weak self] board in
                self?.updateStones(from: board)
            }
            .store(in: &cancellables)

        // Observe player's current index changes
        player.$currentIndex
            .sink { [weak self] index in
                self?.currentMoveIndex = index
            }
            .store(in: &cancellables)

        // Observe player's last move changes
        player.$lastMove
            .sink { [weak self] moveRef in
                self?.updateLastMove(from: moveRef)
            }
            .store(in: &cancellables)

        // Observe player's capture counts
        player.$blackCaptured
            .sink { [weak self] count in
                self?.blackCapturedCount = count
            }
            .store(in: &cancellables)

        player.$whiteCaptured
            .sink { [weak self] count in
                self?.whiteCapturedCount = count
            }
            .store(in: &cancellables)

        // Observe playing state
        player.$isPlaying
            .sink { [weak self] isPlaying in
                self?.isAutoPlaying = isPlaying
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API - Game Loading

    /// Load a local SGF game and reset to start position
    /// This is the PRIMARY use case - local SGF playback
    func loadGame(_ game: SGFGameWrapper) {
        print("📖 BoardViewModel: Loading game: \(game.title ?? "Untitled")")

        // Store game metadata
        currentGame = game
        boardSize = game.size

        // Load into SGFPlayer
        player.load(game: game.game)

        print("📖 BoardViewModel: Game loaded - \(player.maxIndex) moves, board size \(boardSize)")

        // Update our state from player
        updateStones(from: player.board)
        updateLastMove(from: player.lastMove)
        blackCapturedCount = player.blackCaptured
        whiteCapturedCount = player.whiteCaptured
        currentMoveIndex = player.currentIndex
    }

    /// Clear the current game
    func clearGame() {
        currentGame = nil
        player.clear()
        stones.removeAll()
        lastMovePosition = nil
        blackCapturedCount = 0
        whiteCapturedCount = 0
        currentMoveIndex = 0
    }

    // MARK: - Public API - Move Navigation

    /// Jump to a specific move index
    func seekToMove(_ index: Int) {
        print("🔍 BoardViewModel: Seeking to move \(index)")
        player.seek(to: index)
        // State updates automatically via observers
    }

    /// Move forward one move
    func nextMove() {
        if currentMoveIndex < player.maxIndex {
            player.stepForward()
        }
    }

    /// Move backward one move
    func previousMove() {
        if currentMoveIndex > 0 {
            player.stepBack()
        }
    }

    /// Jump to start of game
    func goToStart() {
        seekToMove(0)
    }

    /// Jump to end of game
    func goToEnd() {
        seekToMove(player.maxIndex)
    }

    // MARK: - Public API - Auto-Play

    /// Toggle auto-play on/off
    func toggleAutoPlay() {
        player.togglePlay()
        // isAutoPlaying updates automatically via observer
    }

    /// Start auto-play mode
    func startAutoPlay() {
        player.setPlayInterval(autoPlaySpeed)
        player.play()
    }

    /// Stop auto-play mode
    func stopAutoPlay() {
        player.pause()
    }

    // MARK: - Internal State Updates

    /// Update stones dictionary from player's board grid
    private func updateStones(from board: BoardSnapshot) {
        var newStones: [BoardPosition: Stone] = [:]

        for (y, row) in board.grid.enumerated() {
            for (x, stone) in row.enumerated() {
                if let stone = stone {
                    newStones[BoardPosition(y, x)] = stone
                }
            }
        }

        stones = newStones
        print("🔄 BoardViewModel: Updated \(newStones.count) stones on board")
    }

    /// Update last move position from player's MoveRef
    private func updateLastMove(from moveRef: MoveRef?) {
        if let move = moveRef {
            lastMovePosition = BoardPosition(move.y, move.x)
        } else {
            lastMovePosition = nil
        }
    }

    // MARK: - Public API - OGS Integration (Phase 3)

    /// Place a stone at a position (for OGS live games)
    func placeStone(at position: BoardPosition, color: Stone) {
        // Use optimistic placement
        player.playMoveOptimistically(color: color, x: position.col, y: position.row)
    }

    // MARK: - Cleanup

    deinit {
        stopAutoPlay()
        cancellables.removeAll()
    }
}

// MARK: - Supporting Types

/// Represents a position on the Go board
struct BoardPosition: Hashable, Codable {
    let row: Int
    let col: Int

    init(_ row: Int, _ col: Int) {
        self.row = row
        self.col = col
    }

    /// Create from SGF coordinates (e.g., "dd" for D4)
    init?(sgf: String, boardSize: Int) {
        guard sgf.count == 2 else { return nil }

        let chars = Array(sgf)
        guard let first = chars[0].asciiValue,
              let second = chars[1].asciiValue else {
            return nil
        }

        // SGF uses 'a' = 0, 'b' = 1, etc.
        let col = Int(first - Character("a").asciiValue!)
        let row = Int(second - Character("a").asciiValue!)

        guard col >= 0, col < boardSize,
              row >= 0, row < boardSize else {
            return nil
        }

        self.row = row
        self.col = col
    }

    /// Convert to human-readable coordinates (e.g., "D4")
    func toHumanReadable(boardSize: Int) -> String {
        let colChar = Character(UnicodeScalar(65 + col)!) // A, B, C...
        let rowNum = boardSize - row // 1-based from bottom

        // Skip 'I' in Go notation
        let adjustedCol = col >= 8 ? Character(UnicodeScalar(66 + col)!) : colChar

        return "\(adjustedCol)\(rowNum)"
    }
}
