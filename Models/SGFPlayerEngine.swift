// MARK: - File: SGFPlayerEngine.swift
import Foundation
import Combine

extension Notification.Name {
    static let gameDidFinish = Notification.Name("gameDidFinish")
}

// Reference to the last played move (kept for engine/UI coordination)
struct MoveRef: Equatable { let color: Stone; let x: Int; let y: Int }

final class SGFPlayer: ObservableObject {
    // Public, read-only state the UI renders
    @Published private(set) var board: BoardSnapshot =
        .init(size: 19, grid: Array(repeating: Array(repeating: nil, count: 19), count: 19))
    @Published private(set) var lastMove: MoveRef? = nil
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentIndex: Int = 0   // index into moves (0…maxIndex)
    @Published private(set) var lastCaptureCount: Int = 0  // Number of stones captured in last move
    @Published private(set) var blackCaptured: Int = 0     // Total stones captured by black
    @Published private(set) var whiteCaptured: Int = 0     // Total stones captured by white

    @Published var playInterval: Double = 0.75          // seconds per move (configurable)
    var maxIndex: Int { max(0, moves.count) }

    // Public access to move data for capture counting
    var moves: [(Stone,(Int,Int)?)] { _moves }
    var baseSetup: [(Stone,Int,Int)] { _baseSetup }

    // Internal model snapshot for the current game
    private var _moves: [(Stone,(Int,Int)?)] = []       // pass = nil
    private var baseSize: Int = 19
    private var _baseSetup: [(Stone,Int,Int)] = []      // AB/AW
    private var timer: AnyCancellable?

    // Load a new SGF game
    func load(game: SGFGame) {
        let prevMoveCount = _moves.count
        let prevStoneCount = board.grid.flatMap { $0 }.compactMap { $0 }.count

        print("🔍 LOAD: Loading game with board size \(game.boardSize), \(game.moves.count) moves")
        print("🔍 LOAD: Previous state: \(prevMoveCount) moves, \(prevStoneCount) stones on board")
        print("🔍 LOAD: New state: \(game.moves.count) moves")

        if game.moves.isEmpty && prevMoveCount > 0 {
            print("🔍 LOAD: ⚠️⚠️⚠️ WARNING: Loading game with 0 moves when previous had \(prevMoveCount) moves!")
            print("🔍 LOAD: ⚠️⚠️⚠️ This will CLEAR THE BOARD with \(prevStoneCount) stones!")
            print("🔍 LOAD: ⚠️⚠️⚠️ Call stack: \(Thread.callStackSymbols.prefix(10))")
        }

        baseSize = game.boardSize
        _baseSetup = game.setup
        _moves = game.moves
        print("🔍 LOAD: First 5 moves: \(Array(_moves.prefix(5)))")
        reset()
    }

    /// Place a move optimistically (for OGS live play before server confirms)
    /// This provides instant visual feedback - the stone appears immediately
    /// When the server responds, load() will overwrite with authoritative state
    func playMoveOptimistically(color: Stone, x: Int, y: Int) {
        print("⚡️ OPTIMISTIC: Playing \(color) at (\(x), \(y)) - instant visual feedback")

        // Append to internal moves array
        _moves.append((color, (x, y)))

        // Apply it immediately (updates board snapshot and triggers UI refresh)
        apply(moveAt: _moves.count - 1)
        currentIndex = _moves.count

        print("⚡️ OPTIMISTIC: Stone placed! currentIndex now \(currentIndex)")
        print("⚡️ OPTIMISTIC: Server will correct if move is rejected (rare)")
    }

    // Clear everything - completely empty board with no game loaded
    func clear() {
        pause()
        _baseSetup = []
        _moves = []
        currentIndex = 0
        blackCaptured = 0
        whiteCaptured = 0
        lastCaptureCount = 0
        // Create completely empty board
        let grid = Array(repeating: Array(repeating: Stone?.none, count: baseSize), count: baseSize)
        board = .init(size: baseSize, grid: grid)
        lastMove = nil
    }

    // Reset to initial position (before first move)
    func reset() {
        pause()
        currentIndex = 0
        blackCaptured = 0
        whiteCaptured = 0
        lastCaptureCount = 0
        var grid = Array(repeating: Array(repeating: Stone?.none, count: baseSize), count: baseSize)
        for (stone, x, y) in _baseSetup where x < baseSize && y < baseSize {
            grid[y][x] = stone
        }
        board = .init(size: baseSize, grid: grid)
        lastMove = nil
    }

    // Playback controls
    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        timer = Timer.publish(every: playInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.stepForward()
            }
    }

    func pause() {
        isPlaying = false
        timer?.cancel()
        timer = nil
    }

    func stepForward() {
        guard currentIndex < _moves.count else {
            pause()
            // Notify that game has finished
            NotificationCenter.default.post(name: .gameDidFinish, object: nil)
            return
        }
        apply(moveAt: currentIndex)
        currentIndex += 1
    }

    func stepBack() {
        guard currentIndex > 0 else { return }
        // Recompute from the initial position (simple + robust)
        let target = currentIndex - 1
        reset()
        if target > 0 {
            for i in 0..<target { apply(moveAt: i) }
        }
        currentIndex = target
    }

    func seek(to idx: Int) {
        let clamped = max(0, min(idx, _moves.count))
        print("🔍 SEEK: Seeking to move \(idx), clamped to \(clamped), total moves: \(_moves.count)")

        // Stop playback when seeking manually
        if isPlaying {
            print("🔍 SEEK: WAS PLAYING - calling pause()")
            pause()
            print("🔍 SEEK: pause() complete - isPlaying now: \(isPlaying)")
        } else {
            print("🔍 SEEK: Was NOT playing - isPlaying: \(isPlaying)")
        }

        reset()
        if clamped > 0 {
            for i in 0..<clamped {
                print("🔍 SEEK: Applying move \(i)")
                apply(moveAt: i)
            }
        }
        currentIndex = clamped
        print("🔍 SEEK: Final currentIndex: \(currentIndex), board stones: \(board.grid.flatMap { $0 }.compactMap { $0 }.count)")

        // Notify SwiftUI observers that state has changed
        objectWillChange.send()
        print("🔍 SEEK: Notified SwiftUI observers")
    }

    // Update interval on the fly; restarts timer if currently playing
    func setPlayInterval(_ v: Double) {
        playInterval = max(0.05, v)
        if isPlaying { pause(); play() }
    }

    // Apply a single move: place stone, capture opponent groups without liberties,
    // then (if needed) remove own group if it has no liberties (supports suicide SGFs).
    private func apply(moveAt i: Int) {
        let (color, coord) = _moves[i]
        print("🔍 APPLY: Move \(i): \(color) at \(coord ?? (nil, nil))")
        print("🔍 TIMING DEBUG: apply() called on player \(Unmanaged.passUnretained(self).toOpaque())")
        guard let (x, y) = coord,
              x >= 0, y >= 0,
              x < board.size, y < board.size else {
            // pass
            print("🔍 APPLY: Move \(i) is a PASS or invalid")
            lastMove = nil
            return
        }

        print("🔍 APPLY: Placing \(color) stone at (\(x), \(y))")
        // If position already occupied, overwrite (SGFs should be legal; this is defensive)
        var g = board.grid
        g[y][x] = color
        print("🔍 APPLY: Grid updated, stone placed at [\(y)][\(x)]")

        // Capture adjacent opponent groups with no liberties
        let opp: Stone = (color == .black ? .white : .black)
        let neighbors = neighborsOf(x, y, size: board.size)
        var capturedAny = false
        var totalCaptured = 0
        for (nx, ny) in neighbors {
            if g[ny][nx] == opp {
                var visited = Set<Point>()
                let group = collectGroup(from: Point(x: nx, y: ny), color: opp, grid: g, visited: &visited)
                if liberties(of: group, in: g).isEmpty {
                    // remove group
                    totalCaptured += group.count
                    for p in group { g[p.y][p.x] = nil }
                    capturedAny = true
                }
            }
        }
        lastCaptureCount = totalCaptured

        // Update total captures for the capturing player
        if totalCaptured > 0 {
            if color == .black {
                blackCaptured += totalCaptured
            } else {
                whiteCaptured += totalCaptured
            }
        }

        // If own group has no liberties after opponent captures, remove it too (suicide handling)
        var visited = Set<Point>()
        let ownGroup = collectGroup(from: Point(x: x, y: y), color: color, grid: g, visited: &visited)
        if liberties(of: ownGroup, in: g).isEmpty && !capturedAny {
            // Standard Japanese/Chinese rules would forbid this move,
            // but some SGFs may include suicide: support by removing own group.
            for p in ownGroup { g[p.y][p.x] = nil }
        }

        board = .init(size: board.size, grid: g)
        lastMove = .init(color: color, x: x, y: y)

        // REMOVED: Force objectWillChange.send() - this was causing GeometryReader infinite loop
        // SwiftUI automatically detects board.grid changes via @Published properties

        let totalStones = g.flatMap { $0 }.compactMap { $0 }.count
        print("🔍 APPLY: Move \(i) complete. Total stones on board: \(totalStones)")
        print("🔍 BOARD UPDATE: Board grid updated, SimpleBoardView will refresh automatically")
    }
}

// MARK: - Capture helpers
private struct Point: Hashable { let x: Int; let y: Int }

private func neighborsOf(_ x: Int, _ y: Int, size: Int) -> [(Int,Int)] {
    var out: [(Int,Int)] = []
    if x > 0 { out.append((x-1, y)) }
    if x < size-1 { out.append((x+1, y)) }
    if y > 0 { out.append((x, y-1)) }
    if y < size-1 { out.append((x, y+1)) }
    return out
}

private func collectGroup(from start: Point, color: Stone, grid: [[Stone?]], visited: inout Set<Point>) -> [Point] {
    var stack = [start]
    var group: [Point] = []
    while let p = stack.popLast() {
        if visited.contains(p) { continue }
        visited.insert(p)
        guard grid[p.y][p.x] == color else { continue }
        group.append(p)
        for (nx, ny) in neighborsOf(p.x, p.y, size: grid.count) {
            let np = Point(x: nx, y: ny)
            if !visited.contains(np) && grid[ny][nx] == color {
                stack.append(np)
            }
        }
    }
    return group
}

private func liberties(of group: [Point], in grid: [[Stone?]]) -> [Point] {
    var libs = Set<Point>()
    let size = grid.count
    for p in group {
        for (nx, ny) in neighborsOf(p.x, p.y, size: size) {
            if grid[ny][nx] == nil { libs.insert(Point(x: nx, y: ny)) }
        }
    }
    return Array(libs)
}
