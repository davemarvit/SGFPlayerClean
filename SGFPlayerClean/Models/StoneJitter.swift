//
//  StoneJitter.swift
//  SGFPlayerClean
//
//  Created: 2025-11-22
//  Purpose: Deterministic stone position jitter with collision detection
//
//  ARCHITECTURE:
//  - Gaussian distribution using Box-Muller transform
//  - Seeded RNG for deterministic, stable positions
//  - Two-tier caching: initial jitter + collision-adjusted final offsets
//  - Collision detection with neighbor push-back
//  - Cell aspect ratio aware (15:14 ratio)
//

import Foundation
import CoreGraphics

/// Manages jitter (random offset) for stone positioning on the board
/// Provides natural-looking stone placement with collision avoidance
class StoneJitter {

    // MARK: - Configuration

    /// Jitter parameters (tuned from old SGFPlayer)
    private struct Preset {
        var sigma: CGFloat = 0.12         // Standard deviation in radius units
        var clamp: CGFloat = 0.25         // Maximum offset per axis in radius units
        var minDistance: CGFloat = 1.05   // Minimum distance between stone centers (grid units) - based on black stone diameter (22.2mm / 22mm cell = 1.009, plus small clearance)
        var pushStrength: CGFloat = 0.6   // Collision displacement strength - increased for stronger push
    }

    // MARK: - Properties

    /// Board size (19x19, 13x13, or 9x9)
    private let boardSize: Int

    /// Jitter multiplier (0.0 to 2.0, from user settings)
    private var eccentricity: CGFloat

    /// Effective parameters (preset * eccentricity)
    private var sigma: CGFloat
    private var clamp: CGFloat
    private var minDistance: CGFloat
    private var pushStrength: CGFloat

    /// Cell aspect ratio (height/width) - matches old codebase
    private let cellAspectRatio: CGFloat = 23.7 / 22.0

    /// Initial jitter cache (stable, position-based)
    private var initialJitter: [[CGPoint?]]

    /// Final offset cache (collision-adjusted)
    private var finalOffsets: [[CGPoint?]]

    /// Last prepared move index (for cache invalidation)
    private var lastPreparedMove: Int = .min

    // MARK: - Initialization

    init(boardSize: Int = 19, eccentricity: CGFloat = 1.0) {
        self.boardSize = boardSize
        self.eccentricity = eccentricity

        // Initialize caches
        self.initialJitter = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        self.finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)

        // Compute effective parameters
        let preset = Preset()
        self.sigma = preset.sigma * eccentricity
        self.clamp = preset.clamp * eccentricity
        self.minDistance = preset.minDistance
        self.pushStrength = preset.pushStrength
    }

    // MARK: - Public API

    /// Prepare jitter for a specific move index
    /// Call this when the move changes to invalidate affected caches
    func prepare(forMove moveIndex: Int, stones: [BoardPosition: Stone]) {
        guard moveIndex != lastPreparedMove else { return }

        // DON'T clear cache when scrubbing - stones should stay in their positions
        // Only the new stone placement will trigger collision detection

        lastPreparedMove = moveIndex
    }

    /// Get jitter offset for a stone at (x, y)
    /// Returns offset in grid units (will be multiplied by cell size for pixels)
    func offset(forX x: Int, y: Int, moveIndex: Int, stones: [BoardPosition: Stone]) -> CGPoint {
        // Early exit if no jitter
        guard eccentricity > 0.001 else { return .zero }
        guard x >= 0, x < boardSize, y >= 0, y < boardSize else { return .zero }

        // Check if we have a cached final offset
        if let cached = finalOffsets[y][x] {
            return cached
        }

        // Get or generate initial jitter
        let initial = getInitialJitter(x: x, y: y, moveIndex: moveIndex)

        // ALWAYS apply collision detection when there's jitter
        let final = resolveCollisions(x: x, y: y, initial: initial, stones: stones, depth: 0)

        // Cache the final offset
        finalOffsets[y][x] = final

        return final
    }

    /// Update eccentricity (jitter multiplier)
    func setEccentricity(_ value: CGFloat) {
        guard value != eccentricity else { return }

        eccentricity = value

        // Recompute effective parameters
        let preset = Preset()
        sigma = preset.sigma * eccentricity
        clamp = preset.clamp * eccentricity

        // Clear final offsets (initial jitter stays the same)
        clearFinalOffsetsOnly()
    }

    // MARK: - Initial Jitter Generation

    /// Get or generate initial jitter for a position
    private func getInitialJitter(x: Int, y: Int, moveIndex: Int) -> CGPoint {
        // Check cache first
        if let cached = initialJitter[y][x] {
            return cached
        }

        // Generate using Box-Muller transform
        let offset = generateGaussianOffset(x: x, y: y, moveIndex: moveIndex)

        // Cache and return
        initialJitter[y][x] = offset
        return offset
    }

    /// Generate Gaussian-distributed offset using Box-Muller transform
    private func generateGaussianOffset(x: Int, y: Int, moveIndex: Int) -> CGPoint {
        // Seed the RNG deterministically based on position
        // This ensures the same position always gets the same jitter
        let seed = UInt64(x) * 73856093 + UInt64(y) * 19349663 + UInt64(moveIndex) * 83492791

        var rng = SeededRandomNumberGenerator(seed: seed)

        // Box-Muller transform for Gaussian distribution
        let u1 = CGFloat.random(in: 0.0...1.0, using: &rng)
        let u2 = CGFloat.random(in: 0.0...1.0, using: &rng)

        let magnitude = sqrt(-2.0 * log(max(u1, 1e-10)))
        let angle = 2.0 * .pi * u2

        var dx = magnitude * cos(angle) * sigma
        var dy = magnitude * sin(angle) * sigma

        // Clamp to maximum offset
        dx = max(-clamp, min(clamp, dx))
        dy = max(-clamp, min(clamp, dy))

        return CGPoint(x: dx, y: dy)
    }

    // MARK: - Collision Detection

    /// Resolve collisions with neighboring stones - EXACT old codebase implementation
    private func resolveCollisions(x: Int, y: Int, initial: CGPoint, stones: [BoardPosition: Stone], depth: Int) -> CGPoint {
        guard depth < 3 else { return initial }  // Allow more cascade iterations
        guard x >= 0, y >= 0, x < boardSize, y < boardSize else { return initial }

        var offset = initial

        // Get position of center stone (cx, cy)
        let centerPos = CGPoint(
            x: CGFloat(x) + offset.x,
            y: CGFloat(y) + offset.y
        )

        // Check only orthogonal neighbors (4-connected) - key for realistic collision
        let adjacentPositions = [
            (x-1, y), (x+1, y),  // horizontal neighbors
            (x, y-1), (x, y+1)   // vertical neighbors
        ]

        for (nx, ny) in adjacentPositions {
            guard nx >= 0, ny >= 0, nx < boardSize, ny < boardSize else { continue }
            guard stones[BoardPosition(ny, nx)] != nil else { continue }
            guard nx != x || ny != y else { continue }

            // Get neighboring stone's offset
            let neighborOffset = finalOffsets[ny][nx] ?? getInitialJitter(x: nx, y: ny, moveIndex: lastPreparedMove)
            let neighborPos = CGPoint(
                x: CGFloat(nx) + neighborOffset.x,
                y: CGFloat(ny) + neighborOffset.y
            )

            // Calculate distance between stone centers accounting for aspect ratio
            let dx = neighborPos.x - centerPos.x
            let dy = neighborPos.y - centerPos.y

            // Normalize for cell aspect ratio: vertical spacing is 23.7mm, horizontal is 22mm
            let normalizedDy = dy / cellAspectRatio  // convert to horizontal units
            let distance = hypot(dx, normalizedDy)  // use hypot for accuracy

            // Check if stones are too close (collision)
            if distance < minDistance && distance > 0.001 {
                // Calculate push direction (accounting for aspect ratio)
                let normalizedDistance = hypot(dx, normalizedDy)
                let pushDir = CGPoint(
                    x: dx / normalizedDistance,
                    y: normalizedDy / normalizedDistance * cellAspectRatio  // convert back to actual cell units
                )

                // Calculate how much to push apart
                let overlap = minDistance - distance
                let pushAmount = overlap * pushStrength

                // SYMMETRIC PUSH: Push both stones apart equally (CRITICAL!)
                let halfPushAmount = pushAmount * 0.5

                // Push neighbor away from center
                var newNeighborOffset = neighborOffset
                newNeighborOffset.x += pushDir.x * halfPushAmount
                newNeighborOffset.y += pushDir.y * halfPushAmount

                // Push center away from neighbor (opposite direction)
                offset.x -= pushDir.x * halfPushAmount
                offset.y -= pushDir.y * halfPushAmount

                // Clamp both offsets
                newNeighborOffset.x = max(-clamp, min(clamp, newNeighborOffset.x))
                newNeighborOffset.y = max(-clamp, min(clamp, newNeighborOffset.y))
                offset.x = max(-clamp, min(clamp, offset.x))
                offset.y = max(-clamp, min(clamp, offset.y))

                // Update neighbor's final offset in cache
                finalOffsets[ny][nx] = newNeighborOffset

                // Chain reaction: recursively check if pushed stone now collides with others
                _ = resolveCollisions(x: nx, y: ny, initial: newNeighborOffset, stones: stones, depth: depth + 1)
            }
        }

        return offset
    }

    // MARK: - Cache Management

    /// Clear final offsets in regions affected by stone changes
    private func clearAffectedRegions(stones: [BoardPosition: Stone]) {
        // For simplicity, clear all (could be optimized to only clear affected regions)
        finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
    }

    /// Clear only final offsets (keep initial jitter)
    private func clearFinalOffsetsOnly() {
        finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
    }

    /// Clear all caches (both initial and final)
    func clearAll() {
        initialJitter = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        finalOffsets = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        lastPreparedMove = .min
    }
}

// MARK: - Seeded Random Number Generator

/// Simple seeded RNG for deterministic random values
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // LCG (Linear Congruential Generator)
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
