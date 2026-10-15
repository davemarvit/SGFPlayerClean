// MARK: - File: StoneJitter.swift (v5.102 Restore)
import Foundation
import CoreGraphics

class StoneJitter {
    private struct Preset {
        var sigma: CGFloat = 0.12
        var clamp: CGFloat = 0.25
        var minDistance: CGFloat = 1.0 // Reduced from 1.05 to allow "just touching"
        var pushStrength: CGFloat = 0.5
    }
    
    private var boardSize: Int
    private var eccentricity: CGFloat
    private var sigma: CGFloat
    private var clamp: CGFloat
    private var minDistance: CGFloat
    private var pushStrength: CGFloat
    private let cellAspectRatio: CGFloat = 23.7 / 22.0
    
    private var finalOffsets: [[CGPoint?]]
    
    init(boardSize: Int = 19, eccentricity: CGFloat = 1.0) {
        self.boardSize = boardSize
        self.eccentricity = eccentricity
        self.finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        
        let preset = Preset()
        self.sigma = preset.sigma * eccentricity
        self.clamp = preset.clamp * eccentricity
        self.minDistance = preset.minDistance
        self.pushStrength = preset.pushStrength
    }
    
    // History for physics persistence
    private var history: [Int: [[CGPoint?]]] = [:]
    
    private struct Placement: Equatable {
        let color: Stone
        let x: Int
        let y: Int
    }
    private var sourceSetup: [Placement] = []
    private var sourceMoves: [Placement]?
    private var replay: SGFPlayer?

    /// Layout belongs to the recorded history, not the sequence of frames the user saw.
    /// Build missing frames in order without publishing them to the app or requesting AI.
    func prepare(player: SGFPlayer) {
        let snapshot = player.createSnapshot()
        if snapshot.size != boardSize {
            boardSize = snapshot.size
            clearAll()
        }
        let setup = snapshot.setup.map { Placement(color: $0.0, x: $0.1, y: $0.2) }
            .sorted { ($0.y, $0.x, $0.color.rawValue) < ($1.y, $1.x, $1.color.rawValue) }
        let moves = snapshot.moves.map { Placement(color: $0.0, x: $0.1?.0 ?? -1, y: $0.1?.1 ?? -1) }
        if replay == nil || setup != sourceSetup || moves != sourceMoves {
            if setup == sourceSetup, let oldMoves = sourceMoves {
                let sharedCount = zip(oldMoves, moves).prefix { $0 == $1 }.count
                // Preserve the unchanged prefix; discard changed/undone future positions.
                history = history.filter { $0.key <= sharedCount }
            } else {
                history.removeAll()
            }
            sourceSetup = setup
            sourceMoves = moves
            var game = SGFGame()
            game.boardSize = snapshot.size
            game.setup = snapshot.setup
            game.moves = snapshot.moves
            game.initialPlayer = snapshot.initialPlayer
            let player = SGFPlayer()
            player.load(game: game)
            replay = player
            if let last = history.keys.max() { player.seek(to: last) }
        }
        guard let replay else { return }
        let target = max(0, min(snapshot.currentIndex, moves.count))
        if let cached = history[target] {
            finalOffsets = cached
            return
        }
        if history[0] == nil { prepareFrame(forMove: 0, stones: replay.board.stones) }
        while replay.currentIndex < target {
            replay.stepForward()
            prepareFrame(forMove: replay.currentIndex, stones: replay.board.stones)
        }
    }

    private func prepareFrame(forMove moveIndex: Int, stones: [BoardPosition: Stone]) {
        // If we already have a calculated state for this exact move index (e.g. undo/redo), reuse it.
        if let cachedFrame = history[moveIndex] {
            finalOffsets = cachedFrame
            return
        }
        
        
        // 1. Initialize Current Offsets
        var currentOffsets: [[CGPoint?]] = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        let hasPreviousState = (moveIndex > 0) && (history[moveIndex - 1] != nil)
        let previousState = hasPreviousState ? history[moveIndex - 1]! : nil
        
        // Track newly added stones to "Wake Up" the simulation locally
        var activeStones: Set<BoardPosition> = []
        
        for (pos, _) in stones {
            if let prev = previousState, let oldOffset = prev[pos.row][pos.col] {
                // Keep inertia
                currentOffsets[pos.row][pos.col] = oldOffset
            } else {
                // New Stone found!
                currentOffsets[pos.row][pos.col] = getInitialJitter(x: pos.col, y: pos.row, moveIndex: moveIndex)
                activeStones.insert(pos)
            }
        }
        
        // 2. Iterative Collision Resolution (Wake-Up Propagation)
        // We only process 'active' stones. If an active stone pushes a sleeper, the sleeper wakes up.
        let passes = 5 // More passes allowed because we process fewer stones
        var workingOffsets = currentOffsets
        
        for _ in 0..<passes {
            if activeStones.isEmpty { break }
            var nextActiveStones: Set<BoardPosition> = []
            
            // Process currently active stones
            // Set iteration order changes between instances/processes. A stable order
            // keeps collision corrections reproducible after seeking or rebuilding.
            for pos in activeStones.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) {
                guard let current = workingOffsets[pos.row][pos.col] else { continue }
                
                // Resolve against neighbors
                let (adjusted, wokenNeighbors) = resolveCollisionsWakeUp(x: pos.col, y: pos.row, current: current, workingOffsets: &workingOffsets, stones: stones)
                
                // If we moved, we stay active for next pass to settle
                if adjusted != current {
                    workingOffsets[pos.row][pos.col] = adjusted
                    nextActiveStones.insert(pos)
                }
                
                // Add any neighbors we pushed to the active set
                nextActiveStones.formUnion(wokenNeighbors)
            }
            activeStones = nextActiveStones
        }
        
        // 3. Store Final
        finalOffsets = workingOffsets
        history[moveIndex] = workingOffsets
    }
    
    func offset(forX x: Int, y: Int, moveIndex: Int, stones: [BoardPosition: Stone]) -> CGPoint {
        // Prepare should have been called already by syncState on MainActor
        if let cached = finalOffsets[y][x] { return cached }
        // Fallback
        return getInitialJitter(x: x, y: y, moveIndex: moveIndex)
    }
    
    func setEccentricity(_ value: CGFloat) {
        guard value != eccentricity else { return }
        eccentricity = value
        let preset = Preset()
        sigma = preset.sigma * eccentricity
        clamp = preset.clamp * eccentricity
        // Clear history because physics parameters changed; world must be re-simulated.
        clearAll()
    }
    
    private func getInitialJitter(x: Int, y: Int, moveIndex: Int) -> CGPoint {
        // Deterministic RNG based on position/move
        let seed = UInt64(x) * 73856093 + UInt64(y) * 19349663 + UInt64(moveIndex) * 83492791
        var rng = SeededRandomNumberGenerator(seed: seed)
        
        let u1 = CGFloat.random(in: 0...1, using: &rng)
        let u2 = CGFloat.random(in: 0...1, using: &rng)
        let mag = sqrt(-2.0 * log(max(u1, 1e-10)))
        let ang = 2.0 * .pi * u2
        
        let dx = max(-clamp, min(clamp, mag * cos(ang) * sigma))
        let dy = max(-clamp, min(clamp, mag * sin(ang) * sigma))
        
        return CGPoint(x: dx, y: dy)
    }
    
    // Returns (NewOffset, [NeighborsPushed])
    private func resolveCollisionsWakeUp(x: Int, y: Int, current: CGPoint, workingOffsets: inout [[CGPoint?]], stones: [BoardPosition: Stone]) -> (CGPoint, [BoardPosition]) {
        var offset = current
        var woken: [BoardPosition] = []
        let centerPos = CGPoint(x: CGFloat(x) + offset.x, y: CGFloat(y) + offset.y)
        let neighbors = [(x-1, y), (x+1, y), (x, y-1), (x, y+1), (x-1, y-1), (x+1, y+1), (x-1, y+1), (x+1, y-1)]
        
        for (nx, ny) in neighbors {
            guard nx >= 0, ny >= 0, nx < boardSize, ny < boardSize else { continue }
            guard stones[BoardPosition(ny, nx)] != nil else { continue }
            
            // Get neighbor's CURRENT live position from working set
            guard var nOff = workingOffsets[ny][nx] else { continue }
            
            let nPos = CGPoint(x: CGFloat(nx) + nOff.x, y: CGFloat(ny) + nOff.y)
            let dx = nPos.x - centerPos.x
            let dy = (nPos.y - centerPos.y) / cellAspectRatio
            let dist = hypot(dx, dy)
            
            if dist < minDistance && dist > 0.001 {
                let overlap = minDistance - dist
                let pushDir = CGPoint(x: dx / dist, y: (dy / dist) * cellAspectRatio)
                
                // NEW PHYSICS: Newton's Third Law (Action-Reaction)
                // WE push THEM away (Wake them up!)
                // If we assume equal mass, we split the overlap correction relative to movement freedom?
                // Simple approach: We move back 50%, They move away 50%.
                
                let correction = overlap * 0.5 * pushStrength
                
                // Move Self Back
                offset.x -= pushDir.x * correction
                offset.y -= pushDir.y * correction
                
                // Move Neighbor Away (Directly Modify Working Set)
                nOff.x += pushDir.x * correction
                nOff.y += pushDir.y * correction
                workingOffsets[ny][nx] = nOff // Commit neighbor move
                
                woken.append(BoardPosition(ny, nx))
            }
        }
        return (offset, woken)
    }
    
    func clearAll() {
        // Clear cache and history
        replay = nil
        sourceMoves = nil
        sourceSetup = []
        history.removeAll()
        finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
