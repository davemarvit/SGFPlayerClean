//
//  SimpleBowlView.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Display captured stones in bowls with simple random placement
//
//  SIMPLIFICATION (Phase 1):
//  - NO physics simulation (too complex, buggy)
//  - Random placement within bowl circle
//  - Fast and simple
//  - Can add physics later (Phase 6) if desired
//

import SwiftUI

struct SimpleBowlView: View {

    // MARK: - Configuration

    /// Bowl center position
    let center: CGPoint

    /// Bowl radius
    let radius: CGFloat

    /// Stone color in this bowl
    let stoneColor: Stone

    /// Number of stones to display
    let stoneCount: Int

    /// Stone size
    let stoneSize: CGFloat

    // MARK: - State

    /// Random stone positions (generated once, cached)
    @State private var stonePositions: [CGPoint] = []

    // MARK: - Body

    var body: some View {
        ZStack {
            // Bowl container (circle)
            bowlContainer

            // Stones (randomly placed)
            stonesLayer
        }
        .onChange(of: stoneCount) { oldCount, newCount in
            generateStonePositions()
        }
        .onChange(of: center) { oldCenter, newCenter in
            generateStonePositions()
        }
        .onChange(of: radius) { oldRadius, newRadius in
            generateStonePositions()
        }
        .onAppear {
            generateStonePositions()
        }
    }

    // MARK: - Bowl Container

    private var bowlContainer: some View {
        ZStack {
            // Bowl shadow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .black.opacity(0.2),
                            .black.opacity(0.1),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius * 1.2
                    )
                )
                .frame(width: radius * 2.2, height: radius * 2.2)
                .position(center)
                .offset(x: 3, y: 3)

            // Bowl outline
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.4, green: 0.3, blue: 0.2),
                            Color(red: 0.3, green: 0.2, blue: 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 8
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)

            // Bowl interior
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.25, green: 0.2, blue: 0.15),
                            Color(red: 0.2, green: 0.15, blue: 0.1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
        }
    }

    // MARK: - Stones Layer

    private var stonesLayer: some View {
        ZStack {
            ForEach(Array(stonePositions.enumerated()), id: \.offset) { index, position in
                StoneView(
                    color: stoneColor,
                    size: stoneSize
                )
                .position(position)
                .zIndex(Double(index)) // Stack stones naturally
            }
        }
    }

    // MARK: - Stone Position Generation

    /// Generate random positions for stones within the bowl
    /// Simple random placement - no physics, no collision detection
    private func generateStonePositions() {
        var positions: [CGPoint] = []

        for i in 0..<stoneCount {
            // Random angle
            let angle = Double.random(in: 0...(2 * .pi))

            // Random distance from center (0 to 80% of radius to stay within bowl)
            // Use square root to get more uniform distribution
            let distance = sqrt(Double.random(in: 0...1)) * Double(radius * 0.8)

            // Calculate position
            let x = center.x + CGFloat(cos(angle) * distance)
            let y = center.y + CGFloat(sin(angle) * distance)

            // Add some slight randomness to make stones not perfectly circular
            let jitterX = CGFloat.random(in: -stoneSize * 0.1...stoneSize * 0.1)
            let jitterY = CGFloat.random(in: -stoneSize * 0.1...stoneSize * 0.1)

            positions.append(CGPoint(
                x: x + jitterX,
                y: y + jitterY
            ))
        }

        // Animate position changes
        withAnimation(.easeInOut(duration: 0.3)) {
            stonePositions = positions
        }
    }
}

// MARK: - Bowls Container View

/// Container for both upper and lower bowls
struct BowlsView: View {

    @ObservedObject var boardVM: BoardViewModel
    @ObservedObject var layoutVM: LayoutViewModel

    var body: some View {
        ZStack {
            // Upper bowl (black captures - white stones)
            if boardVM.blackCapturedCount > 0 {
                SimpleBowlView(
                    center: layoutVM.upperBowlCenter,
                    radius: layoutVM.bowlRadius,
                    stoneColor: .white, // White stones captured by black
                    stoneCount: boardVM.blackCapturedCount,
                    stoneSize: layoutVM.getStoneSize(boardSize: boardVM.boardSize) * 0.8
                )
            }

            // Lower bowl (white captures - black stones)
            if boardVM.whiteCapturedCount > 0 {
                SimpleBowlView(
                    center: layoutVM.lowerBowlCenter,
                    radius: layoutVM.bowlRadius,
                    stoneColor: .black, // Black stones captured by white
                    stoneCount: boardVM.whiteCapturedCount,
                    stoneSize: layoutVM.getStoneSize(boardSize: boardVM.boardSize) * 0.8
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Empty Bowls") {
    ZStack {
        Color.black.ignoresSafeArea()

        SimpleBowlView(
            center: CGPoint(x: 300, y: 200),
            radius: 80,
            stoneColor: .white,
            stoneCount: 0,
            stoneSize: 20
        )

        SimpleBowlView(
            center: CGPoint(x: 300, y: 400),
            radius: 80,
            stoneColor: .black,
            stoneCount: 0,
            stoneSize: 20
        )
    }
    .frame(width: 600, height: 600)
}

#Preview("Bowls with Stones") {
    ZStack {
        Color.black.ignoresSafeArea()

        SimpleBowlView(
            center: CGPoint(x: 300, y: 200),
            radius: 80,
            stoneColor: .white,
            stoneCount: 15,
            stoneSize: 18
        )

        SimpleBowlView(
            center: CGPoint(x: 300, y: 400),
            radius: 80,
            stoneColor: .black,
            stoneCount: 8,
            stoneSize: 18
        )
    }
    .frame(width: 600, height: 600)
}

#Preview("Many Captures") {
    ZStack {
        Color.black.ignoresSafeArea()

        SimpleBowlView(
            center: CGPoint(x: 300, y: 300),
            radius: 100,
            stoneColor: .black,
            stoneCount: 50,
            stoneSize: 16
        )
    }
    .frame(width: 600, height: 600)
}
