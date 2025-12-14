//
//  BoardView2D.swift
//  SGFPlayerClean
//
//  Updated (v3.67):
//  - Fixes Compilation Error: 'SafeImage' logic refactored.
//  - Uses "board_kaya" asset.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BoardView2D: View {
    @ObservedObject var boardVM: BoardViewModel
    @ObservedObject var layoutVM: LayoutViewModel
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 0. Board Background (Safe Texture)
                ZStack {
                    Color(red: 0.85, green: 0.68, blue: 0.40)
                    // FIX: Pass resizingMode to init, do not chain .resizable() on the custom View
                    SafeImage(name: "board_kaya", resizingMode: .tile)
                        .opacity(0.8)
                }
                .cornerRadius(4)
                .shadow(radius: 4)
                
                // 1. Grid
                BoardGridShape(boardSize: boardVM.boardSize)
                    .stroke(Color.black.opacity(0.8), lineWidth: 1)
                    .padding(20)
                
                // 2. Star Points
                ForEach(starPoints(size: boardVM.boardSize), id: \.self) { point in
                    Circle()
                        .fill(Color.black)
                        .frame(width: starPointSize(for: geometry.size), height: starPointSize(for: geometry.size))
                        .position(position(for: point, in: geometry.size))
                }
                
                // 3. Stones
                ForEach(Array(boardVM.stones).sorted(by: { $0.key.row < $1.key.row }), id: \.key) { (pos, color) in
                    StoneView2D(color: color, position: pos)
                        .frame(width: stoneSize(for: geometry.size), height: stoneSize(for: geometry.size))
                        .position(position(for: pos, in: geometry.size))
                        .offset(
                            x: boardVM.getJitterOffset(forPosition: pos).x,
                            y: boardVM.getJitterOffset(forPosition: pos).y
                        )
                }
                
                // 4. Ghost Stone
                if let ghostPos = boardVM.ghostPosition, let color = boardVM.ghostColor {
                    StoneView2D(color: color, position: ghostPos)
                        .opacity(0.5)
                        .frame(width: stoneSize(for: geometry.size), height: stoneSize(for: geometry.size))
                        .position(position(for: ghostPos, in: geometry.size))
                }
                
                // 5. Last Move Marker
                if let lastMove = boardVM.lastMovePosition {
                    Circle()
                        .stroke(boardVM.stones[lastMove] == .black ? Color.white : Color.black, lineWidth: 2)
                        .frame(width: stoneSize(for: geometry.size) * 0.5, height: stoneSize(for: geometry.size) * 0.5)
                        .position(position(for: lastMove, in: geometry.size))
                }
                
                // 6. Interaction Layer
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let pos = coordinate(at: location, in: geometry.size)
                        boardVM.placeStone(at: pos)
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let pos = coordinate(at: location, in: geometry.size)
                            boardVM.updateGhostStone(at: pos)
                        case .ended:
                            boardVM.clearGhostStone()
                        }
                    }
            }
        }
    }
    
    // MARK: - Layout Helpers
    private func starPoints(size: Int) -> [BoardPosition] {
        if size == 19 {
            return [
                (3,3), (3,9), (3,15),
                (9,3), (9,9), (9,15),
                (15,3), (15,9), (15,15)
            ].map { BoardPosition($0.0, $0.1) }
        }
        return []
    }
    
    private func position(for pos: BoardPosition, in size: CGSize) -> CGPoint {
        let usableWidth = size.width - 40
        let usableHeight = size.height - 40
        let stepX = usableWidth / CGFloat(boardVM.boardSize - 1)
        let stepY = usableHeight / CGFloat(boardVM.boardSize - 1)
        
        return CGPoint(
            x: 20 + CGFloat(pos.col) * stepX,
            y: 20 + CGFloat(pos.row) * stepY
        )
    }
    
    private func coordinate(at point: CGPoint, in size: CGSize) -> BoardPosition {
        let usableWidth = size.width - 40
        let usableHeight = size.height - 40
        let stepX = usableWidth / CGFloat(boardVM.boardSize - 1)
        let stepY = usableHeight / CGFloat(boardVM.boardSize - 1)
        
        let col = Int(round((point.x - 20) / stepX))
        let row = Int(round((point.y - 20) / stepY))
        
        let clampedCol = max(0, min(boardVM.boardSize - 1, col))
        let clampedRow = max(0, min(boardVM.boardSize - 1, row))
        
        return BoardPosition(clampedRow, clampedCol)
    }
    
    private func starPointSize(for size: CGSize) -> CGFloat {
        return ((size.width - 40) / CGFloat(boardVM.boardSize)) * 0.15
    }
    
    private func stoneSize(for size: CGSize) -> CGFloat {
        return ((size.width - 40) / CGFloat(boardVM.boardSize)) * 0.95
    }
}

// MARK: - Safe Image Helper
struct SafeImage: View {
    let name: String
    let resizingMode: Image.ResizingMode?
    
    init(name: String, resizingMode: Image.ResizingMode? = nil) {
        self.name = name
        self.resizingMode = resizingMode
    }
    
    var body: some View {
        if hasImage(named: name) {
            if let mode = resizingMode {
                Image(name).resizable(resizingMode: mode)
            } else {
                Image(name).resizable()
            }
        } else {
            EmptyView()
        }
    }
    
    private func hasImage(named: String) -> Bool {
        #if os(macOS)
        return NSImage(named: named) != nil
        #else
        return UIImage(named: named) != nil
        #endif
    }
}

// MARK: - Board Grid Shape
struct BoardGridShape: Shape {
    let boardSize: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let stepX = rect.width / CGFloat(boardSize - 1)
        let stepY = rect.height / CGFloat(boardSize - 1)
        
        for col in 0..<boardSize {
            let x = CGFloat(col) * stepX
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        for row in 0..<boardSize {
            let y = CGFloat(row) * stepY
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        return path
    }
}
