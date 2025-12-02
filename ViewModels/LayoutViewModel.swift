//
//  LayoutViewModel.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Manages responsive layout calculations for 2D view
//
//  ARCHITECTURE:
//  - Calculates board size, position, and bowl positions
//  - Handles window resize
//  - NO side effects (pure calculations)
//  - Used by ContentView2D (GeometryReader stays in view)
//

import Foundation
import SwiftUI

/// Manages layout calculations for the 2D board view
/// Calculates board size, position, and bowl positions based on window size
class LayoutViewModel: ObservableObject {

    // MARK: - Published State

    /// The calculated board frame (position and size)
    @Published var boardFrame: CGRect = .zero

    /// Center point of the board
    @Published var boardCenter: CGPoint = .zero

    /// X coordinate of board center (used for centering playback controls)
    @Published var boardCenterX: CGFloat = 0

    /// Upper bowl center (for captured black stones)
    @Published var upperBowlCenter: CGPoint = .zero

    /// Lower bowl center (for captured white stones)
    @Published var lowerBowlCenter: CGPoint = .zero

    /// Bowl radius (size of capture bowls)
    @Published var bowlRadius: CGFloat = 100

    /// Current window size
    @Published var windowSize: CGSize = .zero

    // MARK: - Configuration

    /// Minimum board size (pixels)
    let minBoardSize: CGFloat = 200

    /// Maximum board size (pixels)
    let maxBoardSize: CGFloat = 1200

    /// Spacing above board (for game info overlay)
    let topSpacing: CGFloat = 80

    /// Spacing below board (for playback controls)
    let bottomSpacing: CGFloat = 100

    /// Spacing on sides
    let sideSpacing: CGFloat = 40

    /// Bowl size as fraction of board size
    let bowlSizeFraction: CGFloat = 0.15

    // MARK: - Public API

    /// Calculate layout for given container size and board size
    /// Call this from GeometryReader in ContentView2D
    func calculateLayout(
        containerSize: CGSize,
        boardSize: Int = 19,
        leftPanelWidth: CGFloat? = nil
    ) {
        // Prevent infinite loop - only update if size changed
        guard containerSize != windowSize else { return }

        // Store window size
        windowSize = containerSize

        // Use left panel width if provided (for HStack layout with right panel)
        // Otherwise use full container width
        let availableWidth = leftPanelWidth ?? containerSize.width
        let availableHeight = containerSize.height

        // Calculate available space for board (accounting for spacing)
        let maxWidth = availableWidth - (sideSpacing * 2)
        let maxHeight = availableHeight - topSpacing - bottomSpacing

        // Board should be square - use smaller dimension
        var boardDimension = min(maxWidth, maxHeight)

        // Clamp to min/max
        boardDimension = max(minBoardSize, min(maxBoardSize, boardDimension))

        // Calculate board frame (centered horizontally in available space)
        let boardX = (availableWidth - boardDimension) / 2
        let boardY = topSpacing + (maxHeight - boardDimension) / 2

        boardFrame = CGRect(
            x: boardX,
            y: boardY,
            width: boardDimension,
            height: boardDimension
        )

        // Calculate board center
        boardCenter = CGPoint(
            x: boardFrame.midX,
            y: boardFrame.midY
        )
        boardCenterX = boardCenter.x

        // Calculate bowl positions and size
        calculateBowlLayout(boardDimension: boardDimension)
    }

    /// Handle window resize
    /// Call this from .onChange(of: geometry.size)
    func handleResize(newSize: CGSize, boardSize: Int = 19, leftPanelWidth: CGFloat? = nil) {
        // Recalculate layout
        calculateLayout(
            containerSize: newSize,
            boardSize: boardSize,
            leftPanelWidth: leftPanelWidth
        )
    }

    // MARK: - Internal Calculations

    /// Calculate bowl positions and size
    private func calculateBowlLayout(boardDimension: CGFloat) {
        // Bowl size based on board size
        bowlRadius = boardDimension * bowlSizeFraction

        // Upper bowl (above board, centered)
        let upperY = boardFrame.minY - bowlRadius - 20
        upperBowlCenter = CGPoint(
            x: boardCenter.x,
            y: upperY
        )

        // Lower bowl (below board, centered)
        let lowerY = boardFrame.maxY + bowlRadius + 20
        lowerBowlCenter = CGPoint(
            x: boardCenter.x,
            y: lowerY
        )
    }

    /// Get stone size for the current board size
    func getStoneSize(boardSize: Int = 19) -> CGFloat {
        // Stone size is board dimension divided by number of lines
        let gridSpacing = boardFrame.width / CGFloat(boardSize - 1)
        return gridSpacing * 0.48 // Slightly smaller than grid spacing
    }

    /// Convert board coordinates to screen coordinates
    func boardToScreen(row: Int, col: Int, boardSize: Int = 19) -> CGPoint {
        let gridSpacing = boardFrame.width / CGFloat(boardSize - 1)

        let x = boardFrame.minX + (CGFloat(col) * gridSpacing)
        let y = boardFrame.minY + (CGFloat(row) * gridSpacing)

        return CGPoint(x: x, y: y)
    }

    /// Convert screen coordinates to board coordinates
    func screenToBoard(_ point: CGPoint, boardSize: Int = 19) -> (row: Int, col: Int)? {
        // Check if point is within board bounds
        guard boardFrame.contains(point) else {
            return nil
        }

        let gridSpacing = boardFrame.width / CGFloat(boardSize - 1)

        let relativeX = point.x - boardFrame.minX
        let relativeY = point.y - boardFrame.minY

        let col = Int(round(relativeX / gridSpacing))
        let row = Int(round(relativeY / gridSpacing))

        // Clamp to valid range
        let clampedCol = max(0, min(boardSize - 1, col))
        let clampedRow = max(0, min(boardSize - 1, row))

        return (row: clampedRow, col: clampedCol)
    }

    // MARK: - 70/30 Split Layout (Phase 2)

    /// Calculate layout for 70% left panel / 30% right panel
    func calculateSplitLayout(containerSize: CGSize, boardSize: Int = 19) {
        let leftPanelWidth = containerSize.width * 0.7

        calculateLayout(
            containerSize: containerSize,
            boardSize: boardSize,
            leftPanelWidth: leftPanelWidth
        )
    }
}

// MARK: - Supporting Types

/// Layout result (if we need to return a struct instead of updating @Published)
/// For now, we use @Published properties directly
struct ResponsiveLayout {
    let boardFrame: CGRect
    let boardCenter: CGPoint
    let boardCenterX: CGFloat
    let upperBowlCenter: CGPoint
    let lowerBowlCenter: CGPoint
    let bowlRadius: CGFloat
    let stoneSize: CGFloat

    static let zero = ResponsiveLayout(
        boardFrame: .zero,
        boardCenter: .zero,
        boardCenterX: 0,
        upperBowlCenter: .zero,
        lowerBowlCenter: .zero,
        bowlRadius: 0,
        stoneSize: 0
    )
}

// MARK: - Reference Implementation
// This is based on ContentView.swift lines 928-1023 (calculateResponsiveLayout)
// But with NO side effects - all pure calculations
// GeometryReader stays in ContentView2D, calls these methods
