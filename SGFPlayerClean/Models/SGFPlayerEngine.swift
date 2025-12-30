// MARK: - File: SGFPlayerEngine.swift (v8.106)
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
    @Published var playInterval: Double = 0.75
    let moveProcessed = PassthroughSubject<Void, Never>()
    private var _moves: [(Stone, (Int,Int)?)] = []
    private var _baseSetup: [(Stone, Int, Int)] = []
    private var timer: AnyCancellable?
    private var baseSize: Int = 19
    
    init() { self.board = BoardSnapshot(size: 19, grid: Array(repeating: Array(repeating: nil, count: 19), count: 19), stones: [:]) }
    var maxIndex: Int { _moves.count }
    var turn: Stone { if let last = lastMove { return last.color == .black ? .white : .black }; return .black }
    func load(game: SGFGame) { self.baseSize = game.boardSize; self._baseSetup = game.setup; self._moves = game.moves; self.reset() }
    func clear() { pause(); _moves = []; _baseSetup = []; currentIndex = 0; whiteStonesCaptured = 0; blackStonesCaptured = 0; syncSnapshot(grid: Array(repeating: Array(repeating: nil, count: baseSize), count: baseSize)); moveProcessed.send() }
    func reset() { pause(); currentIndex = 0; whiteStonesCaptured = 0; blackStonesCaptured = 0; var grid = Array(repeating: Array(repeating: Stone?.none, count: baseSize), count: baseSize); var stones: [BoardPosition: Stone] = [:]; for (stone, x, y) in _baseSetup where x < baseSize && y < baseSize { grid[y][x] = stone; stones[BoardPosition(y, x)] = stone }; syncSnapshot(grid: grid); moveProcessed.send() }
    func play() { guard !isPlaying && currentIndex < _moves.count else { return }; isPlaying = true; timer = Timer.publish(every: playInterval, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.stepForward() } }
    func pause() { isPlaying = false; timer?.cancel(); timer = nil }
    func stepForward() { guard currentIndex < _moves.count else { pause(); return }; apply(moveAt: currentIndex); currentIndex += 1; moveProcessed.send() }
    func stepBackward() { guard currentIndex > 0 else { return }; seek(to: currentIndex - 1) }
    func seek(to idx: Int) { let target = max(0, min(idx, _moves.count)); if target < currentIndex { reset(); for i in 0..<target { apply(moveAt: i) } } else { for i in currentIndex..<target { apply(moveAt: i) } }; currentIndex = target; moveProcessed.send() }
    func playMoveOptimistically(color: Stone, x: Int, y: Int) { _moves.append((color, (x, y))); apply(moveAt: _moves.count - 1); currentIndex = _moves.count; moveProcessed.send() }

    private func apply(moveAt i: Int) {
        let start = CACurrentMediaTime()
        let (color, coord) = _moves[i]; var g = board.grid
        guard let (x, y) = coord else { syncSnapshot(grid: g); return }
        if x >= 0, y >= 0, x < board.size, y < board.size {
            g[y][x] = color; let opponent = color.opponent; var captured = 0; var processed = Set<Point>()
            for (nx, ny) in [(x-1, y), (x+1, y), (x, y-1), (x, y+1)] where nx >= 0 && nx < board.size && ny >= 0 && ny < board.size {
                let p = Point(x: nx, y: ny); if g[ny][nx] == opponent && !processed.contains(p) {
                    var visited = Set<Point>(); let group = collectGroup(from: p, color: opponent, grid: g, visited: &visited); processed.formUnion(visited)
                    if liberties(of: group, in: g).isEmpty { captured += group.count; for stone in group { g[stone.y][stone.x] = nil } }
                }
            }
            if color == .black { whiteStonesCaptured += captured } else { blackStonesCaptured += captured }
            var sVisited = Set<Point>(); let sGroup = collectGroup(from: Point(x: x, y: y), color: color, grid: g, visited: &sVisited)
            if liberties(of: sGroup, in: g).isEmpty { if color == .black { blackStonesCaptured += sGroup.count } else { whiteStonesCaptured += sGroup.count }; for stone in sGroup { g[stone.y][stone.x] = nil } }
            self.lastMove = MoveRef(color: color, x: x, y: y); syncSnapshot(grid: g)
        }
        let end = CACurrentMediaTime(); if end-start > 0.01 { print(String(format: "⚙️ Engine Process: %.3fs", end-start)) }
    }
    
    private func syncSnapshot(grid: [[Stone?]]) {
        var flat: [BoardPosition: Stone] = [:]; for r in 0..<baseSize { for c in 0..<baseSize { if let s = grid[r][c] { flat[BoardPosition(r, c)] = s } } }
        self.board = BoardSnapshot(size: baseSize, grid: grid, stones: flat)
    }
    private struct Point: Hashable { let x, y: Int }
    private func collectGroup(from start: Point, color: Stone, grid: [[Stone?]], visited: inout Set<Point>) -> [Point] {
        var stack = [start], group: [Point] = [], h = grid.count, w = grid[0].count
        while let p = stack.popLast() {
            if visited.contains(p) { continue }; visited.insert(p); guard p.y < h, p.x < w, grid[p.y][p.x] == color else { continue }; group.append(p)
            for (nx, ny) in [(p.x-1, p.y), (p.x+1, p.y), (p.x, p.y-1), (p.x, p.y+1)] where nx >= 0 && nx < w && ny >= 0 && ny < h { if grid[ny][nx] == color { stack.append(Point(x: nx, y: ny)) } }
        }
        return group
    }
    private func liberties(of group: [Point], in grid: [[Stone?]]) -> [Point] {
        var libs = Set<Point>(), h = grid.count, w = grid[0].count
        for p in group { for (nx, ny) in [(p.x-1, p.y), (p.x+1, p.y), (p.x, p.y-1), (p.x, p.y+1)] where nx >= 0 && nx < w && ny >= 0 && ny < h { if grid[ny][nx] == nil { libs.insert(Point(x: nx, y: ny)) } } }
        return Array(libs)
    }
}
