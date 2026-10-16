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
        let analysisSettings: GameAnalysisSettings
        let freeHandicapMoves: Int
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
            analysisSettings: analysisSettings,
            freeHandicapMoves: freeHandicapMoves,
            capturedWhite: whiteStonesCaptured,
            capturedBlack: blackStonesCaptured
        )
    }
    
    func restoreSnapshot(_ snapshot: LocalGameSnapshot) {
        baseSize = snapshot.size
        _moves = snapshot.moves
        _baseSetup = snapshot.setup
        initialPlayer = snapshot.initialPlayer
        analysisSettings = snapshot.analysisSettings
        freeHandicapMoves = snapshot.freeHandicapMoves
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
    private var freeHandicapMoves = 0
    private(set) var analysisSettings = GameAnalysisSettings()
    private var onlineStateVersion: Int?
    private struct PositionState { let key: String; let next: Stone }
    private var positionHistory: [PositionState] = []
    private var lastCapturedPoint: BoardPosition?
    var koPoint: BoardPosition? {
        guard let point = lastCapturedPoint,
              moveRejection(color: turn, x: point.col, y: point.row) == .ko else { return nil }
        return point
    }
    var capturesByBlack: Int { whiteStonesCaptured }
    var capturesByWhite: Int { blackStonesCaptured }
    
    /// Generates the payload data required by the AI Engine for the current move index
    func getCurrentAIPayload() -> (initial: [(color: String, x: Int, y: Int)], moves: [(color: String, x: Int, y: Int)]) {
        return getAIPayload(at: currentIndex)
    }
    
    /// Generates the payload data required by the AI Engine for a specific historical index
    func getAIPayload(at limitIndex: Int) -> (initial: [(color: String, x: Int, y: Int)], moves: [(color: String, x: Int, y: Int)]) {
        let initialStones = _baseSetup.sorted { ($0.2, $0.1, $0.0.rawValue) < ($1.2, $1.1, $1.0.rawValue) }.map { (color: Stone, x: Int, y: Int) -> (color: String, x: Int, y: Int) in
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
    private var playbackSettings: AnyCancellable?
    private var playbackInterval: TimeInterval = 0.5
    
    init() {
        self.board = BoardSnapshot(size: 19, grid: Array(repeating: Array(repeating: nil, count: 19), count: 19), stones: [:])
        positionHistory = [PositionState(key: positionKey(board.grid), next: initialPlayer)]
        playbackSettings = AppSettings.shared.$moveInterval.removeDuplicates().sink { [weak self] interval in
            guard let self = self else { return }
            // Match the settings slider's range, including protection against corrupt preferences.
            self.playbackInterval = interval.isFinite ? min(10, max(0.1, interval)) : 0.5
            if self.isPlaying { self.startPlaybackTimer() }
        }
    }
    
    var turn: Stone { playerToMove(at: currentIndex) }

    /// Identifies the player who made the move at the exact target index
    func moveColor(at index: Int) -> Stone? {
        guard index >= 0 && index < _moves.count else { return nil }
        return _moves[index].0
    }
    
    /// Historical move coordinate; passes have no board intersection.
    func movePosition(at index: Int) -> BoardPosition? {
        guard _moves.indices.contains(index), let (x, y) = _moves[index].1,
              x >= 0, y >= 0 else { return nil }
        return BoardPosition(y, x)
    }

    /// Identifies the player to move at the given state index (0 = before first move)
    func playerToMove(at stateIndex: Int) -> Stone {
        let index = max(0, stateIndex)
        if index < _moves.count {
            return _moves[index].0
        }
        if index < freeHandicapMoves { return .black }
        if let last = _moves.last {
            return last.0 == .black ? .white : .black
        }
        return initialPlayer
    }
    
    var maxIndex: Int { _moves.count }

    var lastTwoMovesWerePasses: Bool {
        guard currentIndex >= 2, currentIndex <= _moves.count else { return false }
        return _moves[(currentIndex - 2)..<currentIndex].allSatisfy { _, point in
            guard let (x, y) = point else { return true }
            return x == -1 && y == -1
        }
    }
    
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
        self.freeHandicapMoves = 0
        self.analysisSettings = GameAnalysisSettings(initialPlayer: nextPlayer, online: true)
        self.onlineStateVersion = stateVersion
        self.highestKnownStateVersion = stateVersion
        self.reset()
    }
    
    enum SnapshotResult { case applied, stale, needsResync }

    /// A shorter history is not proof of undo. Only a newer revision or a fenced recovery read
    /// may replace history; move_number is deliberately not used as a state version.
    func reconcileOnlineSnapshot(_ snapshot: OGSGameSnapshot, recovery: Bool = false,
                                 newGame: Bool = false) -> SnapshotResult {
        let incoming = snapshot.game
        if !newGame, let version = snapshot.stateVersion, let known = onlineStateVersion, version < known { return .stale }
        if !newGame && !recovery {
            let newer = snapshot.stateVersion.map { $0 > (onlineStateVersion ?? -1) } ?? false
            if !newer {
                let setup = Dictionary(uniqueKeysWithValues: incoming.setup.map { (BoardPosition($0.2, $0.1), $0.0) })
                let currentSetup = Dictionary(uniqueKeysWithValues: _baseSetup.map { (BoardPosition($0.2, $0.1), $0.0) })
                let prefixMatches = incoming.moves.count >= _moves.count && zip(_moves, incoming.moves).allSatisfy {
                    $0.0 == $1.0 && ($0.1?.0 ?? -1) == ($1.1?.0 ?? -1) && ($0.1?.1 ?? -1) == ($1.1?.1 ?? -1)
                }
                guard incoming.boardSize == baseSize, setup == currentSetup, prefixMatches else { return .needsResync }
            }
        }
        let viewed = currentIndex
        let reviewing = !newGame && viewed < _moves.count
        let knownVersion = onlineStateVersion
        load(game: incoming)
        freeHandicapMoves = snapshot.freeHandicapMoves
        onlineStateVersion = snapshot.stateVersion ?? (newGame ? nil : knownVersion)
        highestKnownStateVersion = onlineStateVersion ?? 0
        seek(to: reviewing ? min(viewed, maxIndex) : maxIndex)
        return .applied
    }

    func recordOnlineVersion(_ version: Int?) {
        if let version { onlineStateVersion = max(onlineStateVersion ?? version, version); highestKnownStateVersion = onlineStateVersion! }
    }

    enum OnlineMoveResult: Equatable { case applied, duplicate, needsResync }

    /// Compare server sequence numbers against history, including optimistic moves and passes.
    @discardableResult
    func applyOnlineMove(color: Stone, x: Int, y: Int, moveNumber: Int) -> OnlineMoveResult {
        guard moveNumber > 0,
              (x == -1 && y == -1) || (x >= 0 && x < baseSize && y >= 0 && y < baseSize) else {
            return .needsResync
        }
        if moveNumber <= _moves.count {
            let (existingColor, coord) = _moves[moveNumber - 1]
            let existingX = coord?.0 ?? -1, existingY = coord?.1 ?? -1
            return existingColor == color && existingX == x && existingY == y ? .duplicate : .needsResync
        }
        guard moveNumber == _moves.count + 1, color == playerToMove(at: _moves.count) else { return .needsResync }
        let viewedIndex = currentIndex
        let reviewing = viewedIndex < _moves.count
        playMoveOptimistically(color: color, x: x, y: y)
        if reviewing { seek(to: viewedIndex) }
        return .applied
    }

    func playMoveOptimistically(color: Stone, x: Int, y: Int) {
        // An incoming move belongs after the complete history, never on the viewed old board.
        if currentIndex != _moves.count { seek(to: _moves.count) }
        _moves.append((color, (x, y)))
        var g = board.grid
        apply(moveAt: _moves.count - 1, to: &g)
        currentIndex = _moves.count
        moveProcessed.send()
    }
    
    private struct Placement {
        var grid: [[Stone?]]
        var captured: [Point]
        var selfCaptured: Int
    }

    /// Shared by replay and legality checks so capture/suicide simulation cannot diverge.
    private func placement(color: Stone, x: Int, y: Int, on original: [[Stone?]]) -> Placement {
        var grid = original
        grid[y][x] = color
        var captured: [Point] = []
        for (nx, ny) in [(x-1,y), (x+1,y), (x,y-1), (x,y+1)]
            where nx >= 0 && ny >= 0 && nx < baseSize && ny < baseSize && grid[ny][nx] == color.opponent {
            var visited = Set<Point>()
            let group = collectGroup(from: Point(x: nx, y: ny), color: color.opponent, grid: grid, visited: &visited)
            if liberties(of: group, in: grid).isEmpty {
                captured += group
                for point in group { grid[point.y][point.x] = nil }
            }
        }
        var visited = Set<Point>()
        let own = collectGroup(from: Point(x: x, y: y), color: color, grid: grid, visited: &visited)
        let selfCaptured = liberties(of: own, in: grid).isEmpty ? own.count : 0
        if selfCaptured > 0 { for point in own { grid[point.y][point.x] = nil } }
        return Placement(grid: grid, captured: captured, selfCaptured: selfCaptured)
    }

    private func positionKey(_ grid: [[Stone?]]) -> String {
        String(grid.flatMap { row in row.map { stone -> Character in stone == .black ? "B" : stone == .white ? "W" : "." } })
    }

    private func apply(moveAt i: Int, to grid: inout [[Stone?]], updateSnapshot: Bool = true) {
        let (color, coord) = _moves[i]
        lastCapturedPoint = nil
        if let (x, y) = coord, x >= 0, y >= 0, x < baseSize, y < baseSize {
            let result = placement(color: color, x: x, y: y, on: grid)
            grid = result.grid
            if color == .black {
                whiteStonesCaptured += result.captured.count; blackStonesCaptured += result.selfCaptured
            } else {
                blackStonesCaptured += result.captured.count; whiteStonesCaptured += result.selfCaptured
            }
            if result.captured.count == 1, let point = result.captured.first {
                lastCapturedPoint = BoardPosition(point.y, point.x)
            }
            lastMove = MoveRef(color: color, x: x, y: y)
        } else { lastMove = MoveRef(color: color, x: -1, y: -1) }
        positionHistory.append(PositionState(key: positionKey(grid), next: playerToMove(at: i + 1)))
        if updateSnapshot { syncSnapshot(grid: grid) }
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
    
    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        startPlaybackTimer()
    }

    private func startPlaybackTimer() {
        // Changing speed must not publish a pause (which also triggers game auto-advance).
        timer?.cancel()
        timer = Timer.publish(every: playbackInterval, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.stepForward() }
    }
    func pause() { isPlaying = false; timer?.cancel(); timer = nil }
    
    func clear() {
        pause()
        _moves = []; _baseSetup = []; currentIndex = 0
        lastMove = nil; lastCapturedPoint = nil; initialPlayer = .black
        freeHandicapMoves = 0; onlineStateVersion = nil; analysisSettings = GameAnalysisSettings()
        whiteStonesCaptured = 0; blackStonesCaptured = 0; highestKnownStateVersion = 0
        syncSnapshot(grid: Array(repeating: Array(repeating: nil, count: baseSize), count: baseSize))
        positionHistory = [PositionState(key: positionKey(board.grid), next: initialPlayer)]
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
        lastCapturedPoint = nil
        positionHistory = [PositionState(key: positionKey(grid), next: initialPlayer)]
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
    enum MoveRejection: String, Equatable {
        case outside = "That point is outside the board."
        case occupied = "That point is occupied."
        case suicide = "Self-capture is not allowed under these rules."
        case ko = "Ko: play elsewhere before recapturing."
        case superko = "Superko: this move repeats an earlier position."
        case handicapPass = "Place the remaining handicap stones before passing."
        case history = "Return to the latest position before adding a move."
        case wrongTurn = "It is the other player's turn."
    }

    /// Applies only to new input. Recorded and server-confirmed history remains replayable.
    func moveRejection(color: Stone, x: Int, y: Int) -> MoveRejection? {
        if x == -1 && y == -1 { return currentIndex < freeHandicapMoves ? .handicapPass : nil }
        guard x >= 0, y >= 0, x < baseSize, y < baseSize else { return .outside }
        guard board.grid[y][x] == nil else { return .occupied }
        guard let rules = analysisSettings.playRules else { return nil }
        let result = placement(color: color, x: x, y: y, on: board.grid)
        if result.selfCaptured > 0 && !rules.allowsSelfCapture { return .suicide }
        let key = positionKey(result.grid)
        if rules.repetition != .none, positionHistory.count >= 2,
           positionHistory[positionHistory.count - 2].key == key { return .ko }
        switch rules.repetition {
        case .positional:
            if positionHistory.contains(where: { $0.key == key }) { return .superko }
        case .situational:
            let next = currentIndex + 1 < freeHandicapMoves ? Stone.black : color.opponent
            if positionHistory.contains(where: { $0.key == key && $0.next == next }) { return .superko }
        case .simple, .none: break
        }
        return nil
    }

    @discardableResult
    func tryPlayMove(color: Stone, x: Int, y: Int) -> MoveRejection? {
        guard currentIndex == maxIndex else { return .history }
        guard color == turn else { return .wrongTurn }
        if let rejection = moveRejection(color: color, x: x, y: y) { return rejection }
        playMoveOptimistically(color: color, x: x, y: y)
        return nil
    }

    func isSuicide(color: Stone, x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < baseSize, y < baseSize, board.grid[y][x] == nil else { return false }
        return placement(color: color, x: x, y: y, on: board.grid).selfCaptured > 0
    }

    func load(game: SGFGame) {
        self.baseSize = game.boardSize
        self._baseSetup = game.setup
        self._moves = game.moves
        self.analysisSettings = game.analysisSettings
        self.initialPlayer = analysisSettings.initialPlayer
        self.freeHandicapMoves = game.freeHandicapPlacement ? game.handicap : 0
        self.onlineStateVersion = nil
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
