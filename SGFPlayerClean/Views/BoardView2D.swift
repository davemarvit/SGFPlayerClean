//
//  BoardView2D.swift
//  SGFPlayerClean
//
//  Created: 2025-11-28
//  Purpose: Renders the 2D Go board with textures and proper Z-ordering
//

import SwiftUI

struct BoardView2D: View {
    @ObservedObject var boardVM: BoardViewModel
    @ObservedObject var layoutVM: LayoutViewModel
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        ZStack {
            // LAYER 1: Board Texture
            Image("board_kaya")
                .resizable()
            
            // LAYER 2: Grid Lines & Star Points
            Canvas { context, size in
                let cellWidth = size.width / CGFloat(boardVM.boardSize + 1)
                let cellHeight = size.height / CGFloat(boardVM.boardSize + 1)
                
                // Grid
                let path = Path { p in
                    for col in 0..<boardVM.boardSize {
                        let x = CGFloat(col + 1) * cellWidth
                        p.move(to: CGPoint(x: x, y: cellHeight))
                        p.addLine(to: CGPoint(x: x, y: size.height - cellHeight))
                    }
                    for row in 0..<boardVM.boardSize {
                        let y = CGFloat(row + 1) * cellHeight
                        p.move(to: CGPoint(x: cellWidth, y: y))
                        p.addLine(to: CGPoint(x: size.width - cellWidth, y: y))
                    }
                }
                context.stroke(path, with: .color(.black.opacity(0.8)), lineWidth: 1.0)
                
                // Star Points
                let stars = getStarPoints(for: boardVM.boardSize)
                for star in stars {
                    let x = CGFloat(star.col + 1) * cellWidth
                    let y = CGFloat(star.row + 1) * cellHeight
                    let rect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                    context.fill(Path(ellipseIn: rect), with: .color(.black))
                }
            }
            
            // LAYER 3: Stones & Markers
            GeometryReader { geometry in
                let cellWidth = geometry.size.width / CGFloat(boardVM.boardSize + 1)
                let cellHeight = geometry.size.height / CGFloat(boardVM.boardSize + 1)
                
                // Iterate through all known stones
                ForEach(Array(boardVM.stones.keys), id: \.self) { position in
                    if let stone = boardVM.stones[position] {
                        
                        // Calculate position
                        let offset = boardVM.getJitterOffset(forPosition: position)
                        let x = (CGFloat(position.col + 1) + offset.x) * cellWidth
                        let y = (CGFloat(position.row + 1) + offset.y) * cellHeight
                        
                        // Check if this is the last move
                        let isLastMove = (position == boardVM.lastMovePosition)
                        
                        // ZStack for this specific intersection
                        ZStack {
                            // 1. Glow (Underneath)
                            if isLastMove && settings.showBoardGlow {
                                Circle()
                                    .fill(Color.orange.opacity(0.6))
                                    .frame(width: cellWidth * 1.4, height: cellHeight * 1.4)
                                    .blur(radius: 4)
                            }
                            
                            // 2. The Stone Image
                            StoneView2D(color: stone, position: position)
                                .frame(width: cellWidth * 0.95, height: cellHeight * 0.95)
                                .shadow(color: .black.opacity(0.4), radius: 1, x: 1, y: 1)
                            
                            // 3. Top Markers (On top of stone)
                            if isLastMove {
                                Group {
                                    if settings.showLastMoveCircle {
                                        Circle()
                                            .stroke(Color.red, lineWidth: 2)
                                            .frame(width: cellWidth * 0.5, height: cellHeight * 0.5)
                                    }
                                    
                                    if settings.showLastMoveDot {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: cellWidth * 0.25, height: cellHeight * 0.25)
                                    }
                                    
                                    if settings.showMoveNumbers {
                                        Text("\(boardVM.currentMoveIndex)")
                                            // Font size 0.45 to fit 3 digits
                                            .font(.system(size: cellWidth * 0.45, weight: .bold))
                                            .foregroundColor(stone == .black ? .white : .black)
                                    }
                                }
                            }
                        }
                        .position(x: x, y: y)
                        // Explicit Z-Index ensures stones are layered correctly if they overlap slightly due to jitter
                        .zIndex(1)
                    }
                }
                
                // DEBUG: Check for "Ghost Marker" (Last move set, but no stone at that position)
                if let last = boardVM.lastMovePosition, boardVM.stones[last] == nil {
                    let _ = print("⚠️ MISSING STONE at \(last.col), \(last.row) for move \(boardVM.currentMoveIndex)")
                }
            }
        }
        .aspectRatio(1.0 / 1.0773, contentMode: .fit)
    }
    
    private func getStarPoints(for size: Int) -> [BoardPosition] {
        switch size {
        case 19:
            return [(3,3), (3,9), (3,15), (9,3), (9,9), (9,15), (15,3), (15,9), (15,15)]
                .map { BoardPosition($0.1, $0.0) }
        case 13:
            return [(3,3), (3,9), (6,6), (9,3), (9,9)]
                .map { BoardPosition($0.1, $0.0) }
        case 9:
            return [(2,2), (2,6), (4,4), (6,2), (6,6)]
                .map { BoardPosition($0.1, $0.0) }
        default:
            return []
        }
    }
}
