// MARK: - File: SGFPlayerEngine.swift (v4.208)
import Foundation
import Combine

final class SGFPlayer: ObservableObject {
    @Published var board: BoardSnapshot = .init(size: 19, grid: Array(repeating: Array(repeating: nil, count: 19), count: 19))
    @Published var lastMove: MoveRef? = nil
    @Published var isPlaying: Bool = false
    @Published var currentIndex: Int = 0
    @Published var blackCaptured: Int = 0
    @Published var whiteCaptured: Int = 0
    @Published var playInterval: Double = 0.75
    
    private var _moves: [(Stone,(Int,Int)?)] = []
    private var _baseSetup: [(Stone,Int,Int)] = []
    private var timer: AnyCancellable?; private var baseSize: Int = 19
    var maxIndex: Int { _moves.count }; var moves: [(Stone,(Int,Int)?)] { _moves }
    var turn: Stone { if let last = lastMove { return last.color == .black ? .white : .black }; return .black }

    func load(game: SGFGame) { self.baseSize = game.boardSize; self._baseSetup = game.setup; self._moves = game.moves; self.reset() }
    func clear() { pause(); _moves = []; _baseSetup = []; currentIndex = 0; blackCaptured = 0; whiteCaptured = 0; board = .init(size: baseSize, grid: Array(repeating: Array(repeating: nil, count: baseSize), count: baseSize)); lastMove = nil }
    func reset() { pause(); currentIndex = 0; blackCaptured = 0; whiteCaptured = 0; var grid = Array(repeating: Array(repeating: Stone?.none, count: baseSize), count: baseSize); for (stone, x, y) in _baseSetup where x < baseSize && y < baseSize { grid[y][x] = stone }; board = .init(size: baseSize, grid: grid); lastMove = nil }
    func play() { guard !isPlaying && currentIndex < _moves.count else { return }; isPlaying = true; timer = Timer.publish(every: playInterval, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.stepForward() } }
    func pause() { isPlaying = false; timer?.cancel(); timer = nil }
    func stepForward() { guard currentIndex < _moves.count else { pause(); return }; apply(moveAt: currentIndex); currentIndex += 1 }
    func stepBack() { guard currentIndex > 0 else { return }; let target = currentIndex - 1; reset(); if target > 0 { for i in 0..<target { apply(moveAt: i) } }; currentIndex = target }
    func seek(to idx: Int) { pause(); let target = max(0, min(idx, _moves.count)); reset(); if target > 0 { for i in 0..<target { apply(moveAt: i) } }; currentIndex = target }
    func playMoveOptimistically(color: Stone, x: Int, y: Int) { _moves.append((color, (x, y))); apply(moveAt: _moves.count - 1); currentIndex = _moves.count; objectWillChange.send() }

    private func apply(moveAt i: Int) {
        let (color, coord) = _moves[i]
        guard let (x, y) = coord, x >= 0, y >= 0, x < board.size, y < board.size else { lastMove = nil; return }
        var g = board.grid; g[y][x] = color; let opp = color.opponent; let neighbors = [(x-1, y), (x+1, y), (x, y-1), (x, y+1)]
        for (nx, ny) in neighbors where nx >= 0 && nx < board.size && ny >= 0 && ny < board.size {
            if g[ny][nx] == opp {
                var visited = Set<Point>(); let group = collectGroup(from: Point(x: nx, y: ny), color: opp, grid: g, visited: &visited)
                if liberties(of: group, in: g).isEmpty {
                    if color == .black { blackCaptured += group.count } else { whiteCaptured += group.count }
                    for p in group { g[p.y][p.x] = nil }
                }
            }
        }
        board = .init(size: board.size, grid: g); lastMove = .init(color: color, x: x, y: y)
    }
    private struct Point: Hashable { let x, y: Int }
    private func collectGroup(from start: Point, color: Stone, grid: [[Stone?]], visited: inout Set<Point>) -> [Point] {
        var stack = [start], group: [Point] = []
        while let p = stack.popLast() {
            if visited.contains(p) { continue }; visited.insert(p); guard grid[p.y][p.x] == color else { continue }; group.append(p)
            let neighbors = [(p.x-1, p.y), (p.x+1, p.y), (p.x, p.y-1), (p.x, p.y+1)]
            for (nx, ny) in neighbors where nx >= 0 && nx < grid.count && ny >= 0 && ny < grid.count { if grid[ny][nx] == color { stack.append(Point(x: nx, y: ny)) } }
        }
        return group
    }
    private func liberties(of group: [Point], in grid: [[Stone?]]) -> [Point] {
        var libs = Set<Point>()
        for p in group {
            let neighbors = [(p.x-1, p.y), (p.x+1, p.y), (p.x, p.y-1), (p.x, p.y+1)] // p.y-1 Corrected
            for (nx, ny) in neighbors where nx >= 0 && nx < grid.count && ny >= 0 && ny < grid.count { if grid[ny][nx] == nil { libs.insert(Point(x: nx, y: ny)) } }
        }
        return Array(libs)
    }
}
