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
    
    // MARK: - Snapshot
    struct LocalGameSnapshot {
        let moves: [(Stone, (Int,Int)?)]
        let setup: [(Stone, Int, Int)]
        let size: Int
        let currentIndex: Int
        let initialPlayer: Stone
        let stateVersion: Int
        let capturedWhite: Int
        let capturedBlack: Int
    }
    
    func createSnapshot() -> LocalGameSnapshot {
        return LocalGameSnapshot(
            moves: _moves,
            setup: _baseSetup,
            size: baseSize,
            currentIndex: currentIndex,
            initialPlayer: initialPlayer,
            stateVersion: highestKnownStateVersion,
            capturedWhite: whiteStonesCaptured,
            capturedBlack: blackStonesCaptured
        )
    }
    
    func restoreSnapshot(_ snapshot: LocalGameSnapshot) {
        baseSize = snapshot.size
        _moves = snapshot.moves
        _baseSetup = snapshot.setup
        initialPlayer = snapshot.initialPlayer
        highestKnownStateVersion = snapshot.stateVersion
        reset(sync: false)

        // Rebuild only the position that was visible when local mode was left.
        let index = max(0, min(snapshot.currentIndex, _moves.count))
        var grid = board.grid
        for i in 0..<index { apply(moveAt: i, to: &grid, updateSnapshot: false) }
        whiteStonesCaptured = snapshot.capturedWhite
        blackStonesCaptured = snapshot.capturedBlack
        currentIndex = index
        syncSnapshot(grid: grid)
        moveProcessed.send()
    }

    private var _moves: [(Stone, (Int,Int)?)] = []
    private var _baseSetup: [(Stone, Int, Int)] = []
    private var baseSize: Int = 19
    private var initialPlayer: Stone = .black
    
    /// Generates the payload data required by the AI Engine for the current move index
    func getCurrentAIPayload() -> (initial: [(color: String, x: Int, y: Int)], moves: [(color: String, x: Int, y: Int)]) {
        return getAIPayload(at: currentIndex)
    }
    
    /// Generates the payload data required by the AI Engine for a specific historical index
    func getAIPayload(at limitIndex: Int) -> (initial: [(color: String, x: Int, y: Int)], moves: [(color: String, x: Int, y: Int)]) {
        let initialStones = _baseSetup.map { (color: Stone, x: Int, y: Int) -> (color: String, x: Int, y: Int) in
            return (color == .black ? "B" : "W", x, y)
        }
        
        var history: [(color: String, x: Int, y: Int)] = []
        let safeLimit = max(0, min(limitIndex, _moves.count))
        for i in 0..<safeLimit {
            let (color, coord) = _moves[i]
            let cStr = (color == .black) ? "B" : "W"
            if let (x, y) = coord, x >= 0, y >= 0 {
                history.append((cStr, x, y))
            } else {
                history.append((cStr, -1, -1)) // Pass
            }
        }
        return (initialStones, history)
    }
    
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
    
    /// Identifies the player who made the move at the exact target index
    func moveColor(at index: Int) -> Stone? {
        guard index >= 0 && index < _moves.count else { return nil }
        return _moves[index].0
    }
    
    /// Identifies the player to move at the given state index (0 = before first move)
    func playerToMove(at stateIndex: Int) -> Stone {
        let index = max(0, stateIndex)
        if index < _moves.count {
            return _moves[index].0
        }
        if let last = _moves.last {
            return last.0 == .black ? .white : .black
        }
        return initialPlayer
    }
    
    var maxIndex: Int { _moves.count }
    
    /// Returns the coordinate of the actual next historical move in the playback queue, if any
    var nextHistoricalMovePosition: BoardPosition? {
        guard currentIndex >= 0, currentIndex < _moves.count else { return nil }
        let (_, coord) = _moves[currentIndex]
        guard let (x, y) = coord, x >= 0, y >= 0 else { return nil }
        return BoardPosition(y, x) // UI represents BoardPosition as (row, col) == (y, x)
    }
    
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
            NSLog("[OGS-ENGINE-DEBUG] 🚫 REJECTING Out-of-Order Move \(moveNumber) (Expected \(expected)). Sync Needed?")
            return
        }
        
        NSLog("[OGS-ENGINE-DEBUG] ✅ Applying Online Move \(moveNumber) (Color: \(color), X:\(x), Y:\(y))")
        self.playMoveOptimistically(color: color, x: x, y: y)
    }
    

    func playMoveOptimistically(color: Stone, x: Int, y: Int) {
        _moves.append((color, (x, y)))
        var g = board.grid
        apply(moveAt: _moves.count - 1, to: &g)
        currentIndex = _moves.count
        moveProcessed.send()
    }
    
    private func apply(moveAt i: Int, to grid: inout [[Stone?]], updateSnapshot: Bool = true) {
        let (color, coord) = _moves[i]
        guard let (x, y) = coord else { 
            self.lastMove = MoveRef(color: color, x: -1, y: -1)
            if updateSnapshot { syncSnapshot(grid: grid) }
            return 
        }
        
        if x >= 0, y >= 0, x < baseSize, y < baseSize {
            grid[y][x] = color
            let opponent = color.opponent
            var captured = 0
            var processed = Set<Point>()
            
            for (nx, ny) in [(x-1, y), (x+1, y), (x, y-1), (x, y+1)] where nx >= 0 && nx < baseSize && ny >= 0 && ny < baseSize {
                let p = Point(x: nx, y: ny)
                if grid[ny][nx] == opponent && !processed.contains(p) {
                    var visited = Set<Point>()
                    let group = collectGroup(from: p, color: opponent, grid: grid, visited: &visited)
                    processed.formUnion(visited)
                    if liberties(of: group, in: grid).isEmpty {
                        captured += group.count
                        for s in group { grid[s.y][s.x] = nil }
                    }
                }
            }
            if color == .black { whiteStonesCaptured += captured } else { blackStonesCaptured += captured }
            
            var sV = Set<Point>()
            let sG = collectGroup(from: Point(x: x, y: y), color: color, grid: grid, visited: &sV)
            if liberties(of: sG, in: grid).isEmpty {
                if color == .black { blackStonesCaptured += sG.count } else { whiteStonesCaptured += sG.count }
                for s in sG { grid[s.y][s.x] = nil }
            }
            
            self.lastMove = MoveRef(color: color, x: x, y: y)
            if updateSnapshot { syncSnapshot(grid: grid) }
        } else {
            self.lastMove = MoveRef(color: color, x: -1, y: -1)
            if updateSnapshot { syncSnapshot(grid: grid) }
        }
    }
    
    func stepForward() { guard currentIndex >= 0, currentIndex < _moves.count else { pause(); return }; var g = board.grid; apply(moveAt: currentIndex, to: &g); currentIndex += 1; moveProcessed.send() }
    func stepBackward() { guard currentIndex > 0 else { return }; seek(to: currentIndex - 1) }
    func seek(to idx: Int) {
        let target = max(0, min(idx, _moves.count))
        var g: [[Stone?]]
        if currentIndex < 0 || target < currentIndex {
            reset(sync: false)
            g = board.grid
            for i in 0..<target { apply(moveAt: i, to: &g, updateSnapshot: false) }
        } else {
            g = board.grid
            for i in currentIndex..<target { apply(moveAt: i, to: &g, updateSnapshot: false) }
        }
        syncSnapshot(grid: g)
        currentIndex = target
        moveProcessed.send()
    }
    
    func play() { if isPlaying { return }; isPlaying = true; timer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.stepForward() } }
    func pause() { isPlaying = false; timer?.cancel(); timer = nil }
    
    func clear() {
        pause()
        _moves = []; _baseSetup = []; currentIndex = 0
        lastMove = nil; initialPlayer = .black
        whiteStonesCaptured = 0; blackStonesCaptured = 0; highestKnownStateVersion = 0
        syncSnapshot(grid: Array(repeating: Array(repeating: nil, count: baseSize), count: baseSize))
        moveProcessed.send()
    }
    
    func reset(sync: Bool = true) {
        pause()
        currentIndex = 0; whiteStonesCaptured = 0; blackStonesCaptured = 0
        var grid = Array(repeating: Array(repeating: Stone?.none, count: baseSize), count: baseSize)
        
        for (stone, x, y) in _baseSetup where x >= 0 && y >= 0 && x < baseSize && y < baseSize {
            grid[y][x] = stone
        }
        
        self.lastMove = nil
        if sync {
            syncSnapshot(grid: grid)
            moveProcessed.send()
        } else {
            // Write directly to internal state without publishing if we are about to simulate
            self.board = BoardSnapshot(size: baseSize, grid: grid, stones: [:])
        }
    }
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
        guard pos.row >= 0, pos.col >= 0, pos.row < baseSize, pos.col < baseSize, let color = grid[pos.row][pos.col] else { return [] }
        
        var visited = Set<Point>()
        let pts = collectGroup(from: Point(x: pos.col, y: pos.row), color: color, grid: grid, visited: &visited)
        return Set(pts.map { BoardPosition($0.y, $0.x) })
    }
    
    private func collectGroup(from start: Point, color: Stone, grid: [[Stone?]], visited: inout Set<Point>) -> [Point] {
        var stack = [start]; var group: [Point] = []; let h = grid.count; let w = grid[0].count
        while let p = stack.popLast() {
            if visited.contains(p) { continue }
            visited.insert(p)
            guard p.y >= 0, p.x >= 0, p.y < h, p.x < w, grid[p.y][p.x] == color else { continue }
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
            if pos.row >= 0 && pos.col >= 0 && pos.row < size && pos.col < size {
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
                    // DEBUG: Log weird large fills
                    if region.count > 100 {
                        // NSLog("[TERRITORY-DEBUG] Large Region (\(region.count)) Colors: \(boundaryColors)")
                    }
                    
                    if boundaryColors.count == 1, let owner = boundaryColors.first {
                        for pt in region {
                            territory[BoardPosition(pt.y, pt.x)] = owner
                        }
                    }
                }
            }
        }
        // NSLog("[TERRITORY-FINAL] Dead: \(deadStones.count) -> Terr: \(territory.count)")
        return territory
    }
}
