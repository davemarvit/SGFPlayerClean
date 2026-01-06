// ========================================================
// FILE: ./Models/SGFPlayerEngine.swift
// VERSION: v8.200 (Debug Instrumentation)
// ========================================================
import Foundation
import Combine
import QuartzCore

final class SGFPlayer: ObservableObject {
    @Published var board: BoardSnapshot
    @Published var lastMove: MoveRef? = nil
    @Published var isPlaying: Bool = false
    @Published var currentIndex: Int = 0
    @Published var whiteStonesCaptured: Int = 0
    @Published var blackStonesCaptured: Int = 0
    let moveProcessed = PassthroughSubject<Void, Never>()
    
    private var _moves: [(Stone, (Int,Int)?)] = []
    private var _baseSetup: [(Stone, Int, Int)] = []
    private var baseSize: Int = 19
    private var initialPlayer: Stone = .black
    var serverMoveNumber: Int = 0
    private var timer: AnyCancellable?
    
    init() {
        self.board = BoardSnapshot(size: 19, grid: Array(repeating: Array(repeating: nil, count: 19), count: 19), stones: [:])
    }
    
    var turn: Stone {
        if let last = lastMove { return last.color == .black ? .white : .black }
        return initialPlayer
    }
    var maxIndex: Int { _moves.count }
    
    func loadOnline(size: Int, setup: [BoardPosition: Stone], nextPlayer: Stone, startMoveNumber: Int) {
        print("🔍 [Engine v8.200] loadOnline. Size: \(size), Setup Count: \(setup.count)")
        self.baseSize = size
        self._moves = []
        self._baseSetup = setup.map { ($1, $0.col, $0.row) }
        self.initialPlayer = nextPlayer
        self.serverMoveNumber = startMoveNumber
        self.reset()
    }
    
    func applyOnlineMove(color: Stone, x: Int, y: Int, moveNumber: Int) {
        guard moveNumber > serverMoveNumber || (moveNumber == serverMoveNumber && lastMove == nil) else { return }
        self.serverMoveNumber = moveNumber
        self.playMoveOptimistically(color: color, x: x, y: y)
    }
    
    func clear() {
        pause()
        _moves = []; _baseSetup = []; currentIndex = 0
        whiteStonesCaptured = 0; blackStonesCaptured = 0; serverMoveNumber = 0
        syncSnapshot(grid: Array(repeating: Array(repeating: nil, count: baseSize), count: baseSize))
        moveProcessed.send()
    }
    
    func reset() {
        pause()
        currentIndex = 0; whiteStonesCaptured = 0; blackStonesCaptured = 0
        var grid = Array(repeating: Array(repeating: Stone?.none, count: baseSize), count: baseSize)
        var stones: [BoardPosition: Stone] = [:]
        
        print("🔍 [Engine] Resetting. Base Setup Items: \(_baseSetup.count)")
        
        for (stone, x, y) in _baseSetup where x < baseSize && y < baseSize {
            grid[y][x] = stone
            stones[BoardPosition(y, x)] = stone
        }
        
        self.lastMove = nil
        syncSnapshot(grid: grid)
        print("✅ [Engine] Reset complete. Grid has \(stones.count) stones.")
        moveProcessed.send()
    }
    
    func playMoveOptimistically(color: Stone, x: Int, y: Int) {
        _moves.append((color, (x, y)))
        apply(moveAt: _moves.count - 1)
        currentIndex = _moves.count
        moveProcessed.send()
    }
    
    private func apply(moveAt i: Int) {
        let (color, coord) = _moves[i]
        var g = board.grid
        guard let (x, y) = coord else { syncSnapshot(grid: g); return }
        
        if x >= 0, y >= 0, x < baseSize, y < baseSize {
            g[y][x] = color
            let opponent = color.opponent
            var captured = 0
            var processed = Set<Point>()
            
            for (nx, ny) in [(x-1, y), (x+1, y), (x, y-1), (x, y+1)] where nx >= 0 && nx < baseSize && ny >= 0 && ny < baseSize {
                let p = Point(x: nx, y: ny)
                if g[ny][nx] == opponent && !processed.contains(p) {
                    var visited = Set<Point>()
                    let group = collectGroup(from: p, color: opponent, grid: g, visited: &visited)
                    processed.formUnion(visited)
                    if liberties(of: group, in: g).isEmpty {
                        captured += group.count
                        for s in group { g[s.y][s.x] = nil }
                    }
                }
            }
            if color == .black { whiteStonesCaptured += captured } else { blackStonesCaptured += captured }
            
            var sV = Set<Point>()
            let sG = collectGroup(from: Point(x: x, y: y), color: color, grid: g, visited: &sV)
            if liberties(of: sG, in: g).isEmpty {
                if color == .black { blackStonesCaptured += sG.count } else { whiteStonesCaptured += sG.count }
                for s in sG { g[s.y][s.x] = nil }
            }
            
            self.lastMove = MoveRef(color: color, x: x, y: y)
            syncSnapshot(grid: g)
        }
    }
    
    // MARK: - Playback Logic
    func stepForward() { guard currentIndex < _moves.count else { pause(); return }; apply(moveAt: currentIndex); currentIndex += 1; moveProcessed.send() }
    func stepBackward() { guard currentIndex > 0 else { return }; seek(to: currentIndex - 1) }
    func seek(to idx: Int) {
        let target = max(0, min(idx, _moves.count))
        if target < currentIndex {
            reset()
            for i in 0..<target { apply(moveAt: i) }
        } else {
            for i in currentIndex..<target { apply(moveAt: i) }
        }
        currentIndex = target
        moveProcessed.send()
    }
    
    func play() { if isPlaying { return }; isPlaying = true; timer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.stepForward() } }
    func pause() { isPlaying = false; timer?.cancel(); timer = nil }
    
    private func syncSnapshot(grid: [[Stone?]]) {
        var flat: [BoardPosition: Stone] = [:]
        for r in 0..<baseSize {
            for c in 0..<baseSize {
                if let s = grid[r][c] { flat[BoardPosition(r, c)] = s }
            }
        }
        self.board = BoardSnapshot(size: baseSize, grid: grid, stones: flat)
    }
    
    private struct Point: Hashable { let x, y: Int }
    
    private func collectGroup(from start: Point, color: Stone, grid: [[Stone?]], visited: inout Set<Point>) -> [Point] {
        var stack = [start]; var group: [Point] = []; let h = grid.count; let w = grid[0].count
        while let p = stack.popLast() {
            if visited.contains(p) { continue }
            visited.insert(p)
            guard p.y < h, p.x < w, grid[p.y][p.x] == color else { continue }
            group.append(p)
            for (nx, ny) in [(p.x-1, p.y), (p.x+1, p.y), (p.x, p.y-1), (p.x, p.y+1)] where nx >= 0 && nx < w && ny >= 0 && ny < h {
                if grid[ny][nx] == color { stack.append(Point(x: nx, y: ny)) }
            }
        }
        return group
    }
    
    private func liberties(of group: [Point], in grid: [[Stone?]]) -> [Point] {
        var libs = Set<Point>(); let h = grid.count; let w = grid[0].count
        for p in group {
            for (nx, ny) in [(p.x-1, p.y), (p.x+1, p.y), (p.x, p.y-1), (p.x, p.y+1)] where nx >= 0 && nx < w && ny >= 0 && ny < h {
                if grid[ny][nx] == nil { libs.insert(Point(x: nx, y: ny)) }
            }
        }
        return Array(libs)
    }
    
    func load(game: SGFGame) {
        self.baseSize = game.boardSize
        self._baseSetup = game.setup
        self._moves = game.moves
        self.initialPlayer = .black
        self.serverMoveNumber = 0
        self.reset()
    }
}
