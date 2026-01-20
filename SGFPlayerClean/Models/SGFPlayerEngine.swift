// ========================================================
// FILE: ./Models/SGFPlayerEngine.swift
// VERSION: v8.201 (Turn Sync & Version Alignment)
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
    
    /// In online mode, this tracks the OGS 'state_version'
    var highestKnownStateVersion: Int = 0
    private var timer: AnyCancellable?
    
    init() {
        self.board = BoardSnapshot(size: 19, grid: Array(repeating: Array(repeating: nil, count: 19), count: 19), stones: [:])
    }
    
    var turn: Stone {
        // PILLAR: Turn Priority
        if let last = lastMove {
             NSLog("[OGS-TURN] Turn by Move: \(last.color.opponent) (Last: \(last.color)). History: \(_moves.count)")
             return last.color == .black ? .white : .black
        }
        NSLog("[OGS-TURN] Turn by Initial: \(initialPlayer)")
        return initialPlayer
    }
    
    var maxIndex: Int { _moves.count }
    
    // Updated loadOnline to separate MoveCount logic from StateVersion logic
    func loadOnline(size: Int, setup: [BoardPosition: Stone], nextPlayer: Stone, stateVersion: Int) {
        NSLog("[OGS-ENGINE] 🔍 loadOnline. Size: \(size), Turn: \(nextPlayer), Version: \(stateVersion)")
        self.baseSize = size
        self._moves = []
        self._baseSetup = setup.map { ($1, $0.col, $0.row) }
        self.initialPlayer = nextPlayer
        self.highestKnownStateVersion = stateVersion
        self.reset()
    }
    
    func applyOnlineMove(color: Stone, x: Int, y: Int, moveNumber: Int) {
        // LOGIC FIX: Enforce Sequential Consistency
        let expected = _moves.count + 1
        
        // Debug Log
        NSLog("[OGS-ENGINE] ⚡️ applyOnlineMove used. Move: \(moveNumber). Expected: \(expected). TopVersion: \(highestKnownStateVersion)")
        
        guard moveNumber == expected else {
            NSLog("[OGS-ENGINE] 🚫 REJECTING Out-of-Order Move \(moveNumber) (Expected \(expected)).")
            return
        }
        
        self.playMoveOptimistically(color: color, x: x, y: y)
    }
    
    func clear() {
        pause()
        _moves = []; _baseSetup = []; currentIndex = 0
        whiteStonesCaptured = 0; blackStonesCaptured = 0; highestKnownStateVersion = 0
        syncSnapshot(grid: Array(repeating: Array(repeating: nil, count: baseSize), count: baseSize))
        moveProcessed.send()
    }
    
    func reset() {
        pause()
        currentIndex = 0; whiteStonesCaptured = 0; blackStonesCaptured = 0
        var grid = Array(repeating: Array(repeating: Stone?.none, count: baseSize), count: baseSize)
        
        for (stone, x, y) in _baseSetup where x < baseSize && y < baseSize {
            grid[y][x] = stone
        }
        
        self.lastMove = nil
        syncSnapshot(grid: grid)
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
                        // NSLog("[SOUND-DEBUG] Engine: Captured Group of \(group.count) at \(group[0])")
                    }
                }
            }
            if color == .black { whiteStonesCaptured += captured } else { blackStonesCaptured += captured }
            // if captured > 0 { NSLog("[SOUND-DEBUG] Engine: Total Captured this move: \(captured). New Totals - B:\(blackStonesCaptured) W:\(whiteStonesCaptured)") }
            
            var sV = Set<Point>()
            let sG = collectGroup(from: Point(x: x, y: y), color: color, grid: g, visited: &sV)
            if liberties(of: sG, in: g).isEmpty {
                if color == .black { blackStonesCaptured += sG.count } else { whiteStonesCaptured += sG.count }
                for s in sG { g[s.y][s.x] = nil }
            }
            
            self.lastMove = MoveRef(color: color, x: x, y: y)
            syncSnapshot(grid: g)
        } else {
            // PASS HANDLING
            // If coords are invalid (e.g. -1), treat as Pass.
            // Crucial: Update lastMove so Turn logic flips!
            self.lastMove = MoveRef(color: color, x: x ?? -1, y: y ?? -1)
            syncSnapshot(grid: g)
        }
    }
    
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
    
    internal struct Point: Hashable { let x, y: Int }
    
    // MARK: - Public Group Helper
    func getGroup(at pos: BoardPosition) -> Set<BoardPosition> {
        let grid = self.board.grid
        guard pos.row < baseSize, pos.col < baseSize, let color = grid[pos.row][pos.col] else { return [] }
        
        var visited = Set<Point>()
        let pts = collectGroup(from: Point(x: pos.col, y: pos.row), color: color, grid: grid, visited: &visited)
        return Set(pts.map { BoardPosition($0.y, $0.x) })
    }
    
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
    
    // MARK: - Rules Enforcement
    func isSuicide(color: Stone, x: Int, y: Int) -> Bool {
        // 1. Simulate Move
        var g = board.grid
        guard x >= 0, y >= 0, x < baseSize, y < baseSize, g[y][x] == nil else { return false }
        g[y][x] = color
        
        // 2. Remove Captured Opponents
        let opponent = color.opponent
        var capturedAny = false
        for (nx, ny) in [(x-1, y), (x+1, y), (x, y-1), (x, y+1)] where nx >= 0 && nx < baseSize && ny >= 0 && ny < baseSize {
             if g[ny][nx] == opponent {
                 var visited = Set<Point>()
                 let group = collectGroup(from: Point(x: nx, y: ny), color: opponent, grid: g, visited: &visited)
                 // Check liberties of opponent group
                 if liberties(of: group, in: g).isEmpty {
                     capturedAny = true; break // Valid capture, so NOT suicide
                 }
             }
        }
        if capturedAny { return false }
        
        // 3. Check Self Liberties
        var myVisited = Set<Point>()
        let myGroup = collectGroup(from: Point(x: x, y: y), color: color, grid: g, visited: &myVisited)
        let myLibs = liberties(of: myGroup, in: g)
        
        // If 0 liberties and we didn't capture anything, it's suicide.
        return myLibs.isEmpty
    }
    
    func load(game: SGFGame) {
        self.baseSize = game.boardSize
        self._baseSetup = game.setup
        self._moves = game.moves
        self.initialPlayer = .black
        self.highestKnownStateVersion = 0
        self.reset()
    }
    
    // MARK: - Scoring Helpers
    func calculateTerritory(deadStones: Set<BoardPosition>) -> [BoardPosition: Stone] {
        var territory: [BoardPosition: Stone] = [:]
        let size = self.baseSize
        var grid = self.board.grid
        
        // 1. Remove Dead Stones from Grid View
        for pos in deadStones {
            if pos.row < size && pos.col < size {
                grid[pos.row][pos.col] = nil
            }
        }
        
        var visited = Set<Point>()
        
        for r in 0..<size {
            for c in 0..<size {
                let p = Point(x: c, y: r)
                if grid[r][c] == nil && !visited.contains(p) {
                    // Start Flood Fill
                    var region: [Point] = []
                    var boundaryColors = Set<Stone>()
                    var q = [p]
                    visited.insert(p)
                    
                    while !q.isEmpty {
                        let curr = q.removeFirst()
                        region.append(curr)
                        
                        for (nx, ny) in [(curr.x-1, curr.y), (curr.x+1, curr.y), (curr.x, curr.y-1), (curr.x, curr.y+1)] {
                            if nx >= 0 && nx < size && ny >= 0 && ny < size {
                                let neighbor = Point(x: nx, y: ny)
                                if let stone = grid[ny][nx] {
                                    boundaryColors.insert(stone)
                                } else if !visited.contains(neighbor) {
                                    visited.insert(neighbor)
                                    q.append(neighbor)
                                }
                            }
                        }
                    }
                    
                    // Determine Ownership
                    if boundaryColors.count == 1, let owner = boundaryColors.first {
                        for pt in region {
                            territory[BoardPosition(pt.y, pt.x)] = owner
                        }
                    }
                }
            }
        }
        return territory
    }
}
