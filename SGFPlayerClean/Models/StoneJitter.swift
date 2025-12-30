// MARK: - File: StoneJitter.swift (v5.101)
import Foundation
import CoreGraphics

class StoneJitter {
    private struct Preset {
        var sigma: CGFloat = 0.12
        var clamp: CGFloat = 0.25
        var minDistance: CGFloat = 1.05
        var pushStrength: CGFloat = 0.6
    }
    
    private let boardSize: Int
    private var eccentricity: CGFloat
    private var sigma: CGFloat
    private var clamp: CGFloat
    private var minDistance: CGFloat
    private var pushStrength: CGFloat
    private let cellAspectRatio: CGFloat = 23.7 / 22.0
    
    private var initialJitter: [[CGPoint?]]
    private var finalOffsets: [[CGPoint?]]
    private var lastPreparedMove: Int = .min
    
    init(boardSize: Int = 19, eccentricity: CGFloat = 1.0) {
        self.boardSize = boardSize
        self.eccentricity = eccentricity
        self.initialJitter = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        self.finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        
        let preset = Preset()
        self.sigma = preset.sigma * eccentricity
        self.clamp = preset.clamp * eccentricity
        self.minDistance = preset.minDistance
        self.pushStrength = preset.pushStrength
    }
    
    func prepare(forMove moveIndex: Int, stones: [BoardPosition: Stone]) {
        guard moveIndex != lastPreparedMove else { return }
        lastPreparedMove = moveIndex
        finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
    }
    
    func offset(forX x: Int, y: Int, moveIndex: Int, stones: [BoardPosition: Stone]) -> CGPoint {
        guard eccentricity > 0.001 else { return .zero }
        guard x >= 0, x < boardSize, y >= 0, y < boardSize else { return .zero }
        
        if let cached = finalOffsets[y][x] { return cached }
        
        let initial = getInitialJitter(x: x, y: y, moveIndex: moveIndex)
        let final = resolveCollisions(x: x, y: y, initial: initial, stones: stones)
        finalOffsets[y][x] = final
        return final
    }
    
    func setEccentricity(_ value: CGFloat) {
        guard value != eccentricity else { return }
        eccentricity = value
        let preset = Preset()
        sigma = preset.sigma * eccentricity
        clamp = preset.clamp * eccentricity
        clearAll()
    }
    
    private func getInitialJitter(x: Int, y: Int, moveIndex: Int) -> CGPoint {
        if let cached = initialJitter[y][x] { return cached }
        
        let seed = UInt64(x) * 73856093 + UInt64(y) * 19349663 + UInt64(moveIndex) * 83492791
        var rng = SeededRandomNumberGenerator(seed: seed)
        
        let u1 = CGFloat.random(in: 0...1, using: &rng)
        let u2 = CGFloat.random(in: 0...1, using: &rng)
        let mag = sqrt(-2.0 * log(max(u1, 1e-10)))
        let ang = 2.0 * .pi * u2
        
        let dx = max(-clamp, min(clamp, mag * cos(ang) * sigma))
        let dy = max(-clamp, min(clamp, mag * sin(ang) * sigma))
        
        let point = CGPoint(x: dx, y: dy)
        initialJitter[y][x] = point
        return point
    }
    
    private func resolveCollisions(x: Int, y: Int, initial: CGPoint, stones: [BoardPosition: Stone]) -> CGPoint {
        var offset = initial
        let centerPos = CGPoint(x: CGFloat(x) + offset.x, y: CGFloat(y) + offset.y)
        let neighbors = [(x-1, y), (x+1, y), (x, y-1), (x, y+1)]
        
        for (nx, ny) in neighbors {
            guard nx >= 0, ny >= 0, nx < boardSize, ny < boardSize else { continue }
            // Speed Fix: Using the pre-passed dictionary is now O(1) per neighbor
            guard stones[BoardPosition(ny, nx)] != nil else { continue }
            
            let nOff = initialJitter[ny][nx] ?? getInitialJitter(x: nx, y: ny, moveIndex: lastPreparedMove)
            let nPos = CGPoint(x: CGFloat(nx) + nOff.x, y: CGFloat(ny) + nOff.y)
            
            let dx = nPos.x - centerPos.x
            let dy = (nPos.y - centerPos.y) / cellAspectRatio
            let dist = hypot(dx, dy)
            
            if dist < minDistance && dist > 0.001 {
                let overlap = minDistance - dist
                let pushDir = CGPoint(x: dx / dist, y: (dy / dist) * cellAspectRatio)
                offset.x -= pushDir.x * overlap * 0.3
                offset.y -= pushDir.y * overlap * 0.3
            }
        }
        return offset
    }
    
    func clearAll() {
        initialJitter = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        lastPreparedMove = .min
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
