//
//  BoardView2D.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Renders the Go board grid and stones
//
//  ARCHITECTURE:
//  - Pure UI component
//  - Receives state from BoardViewModel
//  - Receives layout from LayoutViewModel
//  - Handles click events to place stones
//

import SwiftUI

struct BoardView2D: View {

    // MARK: - Dependencies

    /// Board state (stones, move index, etc.)
    @ObservedObject var boardVM: BoardViewModel

    /// Layout calculations (board size, positions)
    @ObservedObject var layoutVM: LayoutViewModel

    // MARK: - Body

    var body: some View {
        ZStack {
            // Board background (wood texture)
            boardBackground

            // Grid lines
            boardGrid

            // Star points (hoshi)
            starPoints

            // Stones layer
            stonesLayer

            // Last move indicator
            lastMoveIndicator

            // Click handler (for stone placement - disabled for Phase 1)
            clickHandler
        }
        .frame(
            width: layoutVM.boardFrame.width,
            height: layoutVM.boardFrame.height
        )
        .position(
            x: layoutVM.boardFrame.midX,
            y: layoutVM.boardFrame.midY
        )
    }

    // MARK: - Board Background

    private var boardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.85, green: 0.7, blue: 0.4),
                        Color(red: 0.8, green: 0.65, blue: 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    // MARK: - Grid Lines

    private var boardGrid: some View {
        Canvas { context, size in
            let lineCount = boardVM.boardSize
            let spacing = size.width / CGFloat(lineCount - 1)

            let linePath = Path { path in
                // Horizontal lines
                for i in 0..<lineCount {
                    let y = CGFloat(i) * spacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }

                // Vertical lines
                for i in 0..<lineCount {
                    let x = CGFloat(i) * spacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }

            context.stroke(
                linePath,
                with: .color(.black.opacity(0.6)),
                lineWidth: 1.5
            )
        }
        .frame(
            width: layoutVM.boardFrame.width,
            height: layoutVM.boardFrame.height
        )
    }

    // MARK: - Star Points

    private var starPoints: some View {
        Canvas { context, size in
            let positions = getStarPointPositions(boardSize: boardVM.boardSize)
            let spacing = size.width / CGFloat(boardVM.boardSize - 1)
            let starRadius: CGFloat = 4

            for (row, col) in positions {
                let x = CGFloat(col) * spacing
                let y = CGFloat(row) * spacing

                context.fill(
                    Circle().path(in: CGRect(
                        x: x - starRadius,
                        y: y - starRadius,
                        width: starRadius * 2,
                        height: starRadius * 2
                    )),
                    with: .color(.black)
                )
            }
        }
        .frame(
            width: layoutVM.boardFrame.width,
            height: layoutVM.boardFrame.height
        )
    }

    /// Get star point positions for given board size
    private func getStarPointPositions(boardSize: Int) -> [(row: Int, col: Int)] {
        switch boardSize {
        case 9:
            return [
                (2, 2), (2, 6),
                (4, 4),
                (6, 2), (6, 6)
            ]
        case 13:
            return [
                (3, 3), (3, 9),
                (6, 6),
                (9, 3), (9, 9)
            ]
        case 19:
            return [
                (3, 3), (3, 9), (3, 15),
                (9, 3), (9, 9), (9, 15),
                (15, 3), (15, 9), (15, 15)
            ]
        default:
            return []
        }
    }

    // MARK: - Stones Layer

    private var stonesLayer: some View {
        ZStack {
            ForEach(Array(boardVM.stones.keys), id: \.self) { position in
                if let stone = boardVM.stones[position] {
                    StoneView(
                        color: stone,
                        size: layoutVM.getStoneSize(boardSize: boardVM.boardSize)
                    )
                    .position(
                        layoutVM.boardToScreen(
                            row: position.row,
                            col: position.col,
                            boardSize: boardVM.boardSize
                        )
                    )
                }
            }
        }
        .frame(
            width: layoutVM.boardFrame.width,
            height: layoutVM.boardFrame.height
        )
    }

    // MARK: - Last Move Indicator

    private var lastMoveIndicator: some View {
        Group {
            if let lastPos = boardVM.lastMovePosition {
                Circle()
                    .stroke(Color.red, lineWidth: 2)
                    .frame(
                        width: layoutVM.getStoneSize(boardSize: boardVM.boardSize) * 0.4,
                        height: layoutVM.getStoneSize(boardSize: boardVM.boardSize) * 0.4
                    )
                    .position(
                        layoutVM.boardToScreen(
                            row: lastPos.row,
                            col: lastPos.col,
                            boardSize: boardVM.boardSize
                        )
                    )
            }
        }
        .frame(
            width: layoutVM.boardFrame.width,
            height: layoutVM.boardFrame.height
        )
    }

    // MARK: - Click Handler

    private var clickHandler: some View {
        // PHASE 3: Click handler disabled for Phase 1
        // Will be re-enabled for OGS live games in Phase 3
        // For now, just return empty view to avoid gesture tracking overhead
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(false)
    }

    private func handleClick(at location: CGPoint) {
        // Convert screen coordinates to board coordinates
        guard let coords = layoutVM.screenToBoard(location, boardSize: boardVM.boardSize) else {
            return
        }

        let position = BoardPosition(coords.row, coords.col)

        // TODO: In Phase 3, this will place stones in OGS games
        // For now, just log
        print("Clicked board at (\(coords.row), \(coords.col))")

        // If OGS game is active, place stone
        // boardVM.placeStone(at: position, color: currentPlayerColor)
    }
}

// MARK: - Stone View

struct StoneView: View {
    let color: Stone
    let size: CGFloat

    var body: some View {
        ZStack {
            // Stone shadow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .black.opacity(0.1),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size * 1.1, height: size * 1.1)
                .offset(x: 2, y: 2)

            // Stone body
            Circle()
                .fill(
                    RadialGradient(
                        colors: color == .black ? [
                            Color(white: 0.2),
                            Color(white: 0.05)
                        ] : [
                            Color(white: 1.0),
                            Color(white: 0.9)
                        ],
                        center: UnitPoint(x: 0.4, y: 0.4),
                        startRadius: 0,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(
                            color == .black
                                ? Color.white.opacity(0.1)
                                : Color.black.opacity(0.1),
                            lineWidth: 1
                        )
                )
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        BoardView2D(
            boardVM: {
                let vm = BoardViewModel()
                // Add some test stones
                vm.stones[BoardPosition(3, 3)] = .black
                vm.stones[BoardPosition(3, 15)] = .white
                vm.stones[BoardPosition(9, 9)] = .black
                vm.lastMovePosition = BoardPosition(9, 9)
                return vm
            }(),
            layoutVM: {
                let vm = LayoutViewModel()
                vm.calculateLayout(
                    containerSize: CGSize(width: 1000, height: 800),
                    boardSize: 19
                )
                return vm
            }()
        )
    }
    .frame(width: 1000, height: 800)
}
