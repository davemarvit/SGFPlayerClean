// MARK: - File: StoneJitter.swift (v3.220)
//
//  Created: 2025-11-22
//  Purpose: Deterministic stone position jitter with collision detection
//
//  Note: Logic preserved exactly from the original implementation.
//  Updated to use centralized types from OGSModels.swift.
//

import Foundation
import CoreGraphics

/// Manages jitter (random offset) for stone positioning on the board
/// Provides natural-looking stone placement with collision avoidance
class StoneJitter {

    // MARK: - Configuration

    private struct Preset {
        var sigma: CGFloat = 0.12         // Standard deviation in radius units
        var clamp: CGFloat = 0.25         // Maximum offset per axis in radius units
        var minDistance: CGFloat = 1.05   // Minimum distance between stone centers
        var pushStrength: CGFloat = 0.6   // Collision displacement strength
    }

    // MARK: - Properties

    private let boardSize: Int
    private var eccentricity: CGFloat
    private var sigma: CGFloat
    private var clamp: CGFloat
    private var minDistance: CGFloat
    private var pushStrength: CGFloat

    /// Cell aspect ratio (height/width) - matches traditional Go boards
    private let cellAspectRatio: CGFloat = 23.7 / 22.0

    private var initialJitter: [[CGPoint?]]
    private var finalOffsets: [[CGPoint?]]
    private var lastPreparedMove: Int = .min

    // MARK: - Initialization

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

    // MARK: - Public API

    /// Prepare jitter for a specific move index
    func prepare(forMove moveIndex: Int, stones: [BoardPosition: Stone]) {
        guard moveIndex != lastPreparedMove else { return }
        lastPreparedMove = moveIndex
        // Clear final offsets to recalculate collisions for the current board state
        clearFinalOffsetsOnly()
    }

    /// Get jitter offset for a stone at (x, y)
    func offset(forX x: Int, y: Int, moveIndex: Int, stones: [BoardPosition: Stone]) -> CGPoint {
        guard eccentricity > 0.001 else { return .zero }
        guard x >= 0, x < boardSize, y >= 0, y < boardSize else { return .zero }

        if let cached = finalOffsets[y][x] {
            return cached
        }

        let initial = getInitialJitter(x: x, y: y, moveIndex: moveIndex)
        let final = resolveCollisions(x: x, y: y, initial: initial, stones: stones, depth: 0)

        finalOffsets[y][x] = final
        return final
    }

    func setEccentricity(_ value: CGFloat) {
        guard value != eccentricity else { return }
        eccentricity = value
        let preset = Preset()
        sigma = preset.sigma * eccentricity
        clamp = preset.clamp * eccentricity
        clearFinalOffsetsOnly()
    }

    // MARK: - Initial Jitter Generation

    private func getInitialJitter(x: Int, y: Int, moveIndex: Int) -> CGPoint {
        if let cached = initialJitter[y][x] {
            return cached
        }

        let offset = generateGaussianOffset(x: x, y: y, moveIndex: moveIndex)
        initialJitter[y][x] = offset
        return offset
    }

    private func generateGaussianOffset(x: Int, y: Int, moveIndex: Int) -> CGPoint {
        let seed = UInt64(x) * 73856093 + UInt64(y) * 19349663 + UInt64(moveIndex) * 83492791
        var rng = SeededRandomNumberGenerator(seed: seed)

        let u1 = CGFloat.random(in: 0.0...1.0, using: &rng)
        let u2 = CGFloat.random(in: 0.0...1.0, using: &rng)

        let magnitude = sqrt(-2.0 * log(max(u1, 1e-10)))
        let angle = 2.0 * .pi * u2

        var dx = magnitude * cos(angle) * sigma
        var dy = magnitude * sin(angle) * sigma

        dx = max(-clamp, min(clamp, dx))
        dy = max(-clamp, min(clamp, dy))

        return CGPoint(x: dx, y: dy)
    }

    // MARK: - Collision Detection

    private func resolveCollisions(x: Int, y: Int, initial: CGPoint, stones: [BoardPosition: Stone], depth: Int) -> CGPoint {
        guard depth < 3 else { return initial }
        guard x >= 0, y >= 0, x < boardSize, y < boardSize else { return initial }

        var offset = initial
        let centerPos = CGPoint(x: CGFloat(x) + offset.x, y: CGFloat(y) + offset.y)

        let adjacentPositions = [
            (x-1, y), (x+1, y),
            (x, y-1), (x, y+1)
        ]

        for (nx, ny) in adjacentPositions {
            guard nx >= 0, ny >= 0, nx < boardSize, ny < boardSize else { continue }
            // Uses the global Stone/BoardPosition from OGSModels
            guard stones[BoardPosition(ny, nx)] != nil else { continue }
            guard nx != x || ny != y else { continue }

            let neighborOffset = finalOffsets[ny][nx] ?? getInitialJitter(x: nx, y: ny, moveIndex: lastPreparedMove)
            let neighborPos = CGPoint(x: CGFloat(nx) + neighborOffset.x, y: CGFloat(ny) + neighborOffset.y)

            let dx = neighborPos.x - centerPos.x
            let dy = neighborPos.y - centerPos.y

            let normalizedDy = dy / cellAspectRatio
            let distance = hypot(dx, normalizedDy)

            if distance < minDistance && distance > 0.001 {
                let normalizedDistance = hypot(dx, normalizedDy)
                let pushDir = CGPoint(
                    x: dx / normalizedDistance,
                    y: normalizedDy / normalizedDistance * cellAspectRatio
                )

                let overlap = minDistance - distance
                let pushAmount = overlap * pushStrength
                let halfPushAmount = pushAmount * 0.5

                // Update center offset
                offset.x -= pushDir.x * halfPushAmount
                offset.y -= pushDir.y * halfPushAmount

                offset.x = max(-clamp, min(clamp, offset.x))
                offset.y = max(-clamp, min(clamp, offset.y))
            }
        }

        return offset
    }

    // MARK: - Cache Management

    private func clearFinalOffsetsOnly() {
        finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
    }

    func clearAll() {
        initialJitter = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        lastPreparedMove = .min
    }
}

// MARK: - Seeded Random Number Generator

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        self.state = seed
    }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
