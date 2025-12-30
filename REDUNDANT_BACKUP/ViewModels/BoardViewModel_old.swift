//
//  BoardViewModel.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Manages game state, navigation, and local SGF file playback
//
//  ARCHITECTURE:
//  - Single source of truth for board state
//  - No UI logic (that belongs in Views)
//  - Works for both 2D and 3D modes
//  - Local mode is PRIMARY use case
//

import Foundation
import Combine

/// Manages the state and logic for displaying and navigating Go games
/// Supports both local SGF playback and OGS live games
class BoardViewModel: ObservableObject {

    // MARK: - Published State

    /// Current position in the game (0 = start, moves.count = end)
    @Published var currentMoveIndex: Int = 0

    /// All stones currently on the board (key = position, value = stone color)
    @Published var stones: [BoardPosition: Stone] = [:]

    /// Position of the last move played (for highlighting)
    @Published var lastMovePosition: BoardPosition?

    /// Number of black stones captured by white
    @Published var blackCapturedCount: Int = 0

    /// Number of white stones captured by black
    @Published var whiteCapturedCount: Int = 0

    /// Whether auto-play is currently running
    @Published var isAutoPlaying: Bool = false

    /// Current game loaded (nil if no game)
    @Published var currentGame: SGFGameWrapper?

    /// Board size (9, 13, or 19)
    @Published var boardSize: Int = 19

    // MARK: - Dependencies

    /// SGF player engine (from AppModel) - handles SGF parsing and game logic
    private var sgfPlayer: SGFPlayer?

    /// Sound manager for move sounds (optional)
    private var soundManager: SoundManager?

    /// Auto-play timer
    private var autoPlayTimer: Timer?

    /// Auto-play speed (seconds between moves)
    var autoPlaySpeed: TimeInterval = 1.0

    // MARK: - Internal State

    /// Cache of board state at each move (optimization)
    /// Key = move index, Value = board state
    private var boardStateCache: [Int: [BoardPosition: Stone]] = [:]

    /// Cache of captures at each move (optimization)
    /// Key = move index, Value = (black captured, white captured)
    private var captureCache: [Int: (black: Int, white: Int)] = [:]

    // MARK: - Initialization

    init(sgfPlayer: SGFPlayer? = nil, soundManager: SoundManager? = nil) {
        self.sgfPlayer = sgfPlayer
        self.soundManager = soundManager
    }

    // MARK: - Public API - Game Loading

    /// Load a local SGF game and reset to start position
    /// This is the PRIMARY use case - local SGF playback
    func loadGame(_ game: SGFGameWrapper) {
        // Stop auto-play if running
        stopAutoPlay()

        // Clear caches
        boardStateCache.removeAll()
        captureCache.removeAll()

        // Store game
        currentGame = game

        // Reset to start
        currentMoveIndex = 0
        stones.removeAll()
        lastMovePosition = nil
        blackCapturedCount = 0
        whiteCapturedCount = 0

        // Get board size from game
        if let gameSize = game.size {
            boardSize = gameSize
        } else {
            boardSize = 19 // Default
        }

        // If we have an SGFPlayer, wire it up
        if let player = sgfPlayer {
            // TODO: Wire up to player.board and player.moves
            // For now, this is a placeholder
            updateBoardState()
        }
    }

    /// Load game state from OGS (for live games)
    func loadOGSGameState(_ gameState: OGSGameState) {
        // Stop auto-play
        stopAutoPlay()

        // Clear caches
        boardStateCache.removeAll()
        captureCache.removeAll()

        // Update from OGS state
        boardSize = gameState.width

        // TODO: Parse OGS moves and populate stones
        // This will be implemented in Phase 3

        updateBoardState()
    }

    // MARK: - Public API - Move Navigation

    /// Jump to a specific move index
    func seekToMove(_ index: Int) {
        guard let player = sgfPlayer else { return }

        // Clamp to valid range
        let maxIndex = player.totalMoves
        let targetIndex = max(0, min(index, maxIndex))

        // Update index
        currentMoveIndex = targetIndex

        // Update board state
        updateBoardState()

        // Play sound
        soundManager?.playStoneSound()
    }

    /// Move forward one move
    func nextMove() {
        guard let player = sgfPlayer else { return }

        if currentMoveIndex < player.totalMoves {
            seekToMove(currentMoveIndex + 1)
        }
    }

    /// Move backward one move
    func previousMove() {
        if currentMoveIndex > 0 {
            seekToMove(currentMoveIndex - 1)
        }
    }

    /// Jump to start of game
    func goToStart() {
        seekToMove(0)
    }

    /// Jump to end of game
    func goToEnd() {
        guard let player = sgfPlayer else { return }
        seekToMove(player.totalMoves)
    }

    // MARK: - Public API - Auto-Play

    /// Toggle auto-play on/off
    func toggleAutoPlay() {
        if isAutoPlaying {
            stopAutoPlay()
        } else {
            startAutoPlay()
        }
    }

    /// Start auto-play mode
    func startAutoPlay() {
        guard !isAutoPlaying else { return }
        guard let player = sgfPlayer else { return }
        guard currentMoveIndex < player.totalMoves else { return }

        isAutoPlaying = true

        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: autoPlaySpeed, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if self.currentMoveIndex < player.totalMoves {
                self.nextMove()
            } else {
                // Reached end
                self.stopAutoPlay()
            }
        }
    }

    /// Stop auto-play mode
    func stopAutoPlay() {
        isAutoPlaying = false
        autoPlayTimer?.invalidate()
        autoPlayTimer = nil
    }

    // MARK: - Internal Logic - Board State

    /// Update the board state based on current move index
    /// Uses cache when available for performance
    private func updateBoardState() {
        // Check cache first
        if let cached = boardStateCache[currentMoveIndex] {
            stones = cached

            if let cachedCaptures = captureCache[currentMoveIndex] {
                blackCapturedCount = cachedCaptures.black
                whiteCapturedCount = cachedCaptures.white
            }

            updateLastMovePosition()
            return
        }

        // Not cached - calculate from SGFPlayer
        guard let player = sgfPlayer else {
            stones.removeAll()
            lastMovePosition = nil
            blackCapturedCount = 0
            whiteCapturedCount = 0
            return
        }

        // Get board state at current index
        // TODO: Wire this to player.board
        // For now, placeholder

        // Calculate captures
        let captures = calculateCapturedStones()
        blackCapturedCount = captures.black
        whiteCapturedCount = captures.white

        // Cache results
        boardStateCache[currentMoveIndex] = stones
        captureCache[currentMoveIndex] = captures

        // Update last move
        updateLastMovePosition()
    }

    /// Update the last move position for highlighting
    private func updateLastMovePosition() {
        guard let player = sgfPlayer else {
            lastMovePosition = nil
            return
        }

        // TODO: Get last move from player.moves[currentMoveIndex]
        // For now, placeholder
        lastMovePosition = nil
    }

    /// Calculate captured stones at current position
    /// Returns (black captured, white captured)
    private func calculateCapturedStones() -> (black: Int, white: Int) {
        // TODO: Reference old ContentView.swift lines 793-850
        // This is complex logic involving:
        // 1. Finding groups with no liberties
        // 2. Counting captured stones
        // 3. Tracking cumulative captures

        // For now, return zeros
        // Will implement in Phase 1.3 when we wire up to SGFPlayer
        return (black: 0, white: 0)
    }

    // MARK: - Public API - OGS Integration (Phase 3)

    /// Place a stone at a position (for OGS live games)
    func placeStone(at position: BoardPosition, color: Stone) {
        // This will be implemented in Phase 3
        // For now, placeholder
    }

    /// Handle opponent's move (for OGS live games)
    func handleOpponentMove(at position: BoardPosition, color: Stone) {
        // This will be implemented in Phase 3
        // For now, placeholder
    }

    // MARK: - Cleanup

    deinit {
        stopAutoPlay()
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

/// Represents a stone color
enum Stone: String, Codable {
    case black = "B"
    case white = "W"

    var opponent: Stone {
        switch self {
        case .black: return .white
        case .white: return .black
        }
    }
}

// MARK: - Placeholder Types (from old codebase)

/// Wrapper for SGF game metadata
/// TODO: Reference actual SGFGameWrapper from old code
struct SGFGameWrapper {
    let title: String?
    let blackPlayer: String?
    let whitePlayer: String?
    let size: Int?
    let handicap: Int?
    let komi: Double?
    let result: String?
    let date: String?

    // Add other metadata as needed
}

/// SGF Player engine
/// TODO: Reference actual SGFPlayer from old code
class SGFPlayer {
    var totalMoves: Int { 0 }
    var board: [[Stone?]] { [] }
    var moves: [Any] { [] }
    var currentIndex: Int = 0
}

/// Sound manager
/// TODO: Reference actual SoundManager from old code
class SoundManager {
    func playStoneSound() {
        // Placeholder
    }
}

/// OGS game state
/// TODO: Reference actual OGS types from old code
struct OGSGameState {
    let width: Int
    let height: Int
    let moves: [[Int]]
}
