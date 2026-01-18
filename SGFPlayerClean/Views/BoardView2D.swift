// MARK: - File: BoardView2D.swift (v8.103)
import SwiftUI

struct BoardView2D: View {
    @ObservedObject var boardVM: BoardViewModel
    @ObservedObject var layoutVM: LayoutViewModel
    let size: CGSize
    
    var body: some View {
        let margin = size.width * 0.065
        let gridW = size.width - (margin * 2)
        let gridH = size.height - (margin * 2)
        let bSize = boardVM.boardSize
        let cellP = gridW / CGFloat(max(1, bSize - 1))
        let rowP = gridH / CGFloat(max(1, bSize - 1))
        
        ZStack {
            ZStack {
                Color(red: 0.82, green: 0.65, blue: 0.4)
                SafeImage(name: "board_kaya.jpg", resizingMode: .stretch)
            }
            .frame(width: size.width, height: size.height)
            .cornerRadius(2)
            .shadow(color: .black.opacity(0.5), radius: 12, x: 20, y: 20)
            
            ZStack(alignment: .topLeading) {
                BoardGridShape(boardSize: bSize)
                    .stroke(Color.black.opacity(0.8), lineWidth: 1.0)
                
                ForEach(starPoints(size: bSize), id: \.self) { pt in
                    Circle().fill(Color.black)
                        .frame(width: size.width * 0.012, height: size.width * 0.012)
                        .position(x: CGFloat(pt.col) * cellP, y: CGFloat(pt.row) * rowP)
                }
                
                // GLOW LAYER (Under Stones)
                if let lastPos = boardVM.lastMovePosition,
                   (AppSettings.shared.showBoardGlow || AppSettings.shared.showEnhancedGlow) {
                    let j = boardVM.getJitterOffset(forPosition: lastPos)
                    let tx = CGFloat(lastPos.col) * cellP + (j.x * cellP)
                    let ty = CGFloat(lastPos.row) * rowP + (j.y * rowP)
                    
                    let s = AppSettings.shared.showEnhancedGlow ? cellP * 1.8 : cellP * 1.5
                    Circle().fill(RadialGradient(gradient: Gradient(colors: [Color.red.opacity(0.6), Color.clear]), center: .center, startRadius: 0, endRadius: s/2))
                        .frame(width: s, height: s)
                        .position(x: tx, y: ty)
                }

                ForEach(boardVM.stonesToRender) { rs in
                    let sS = (rs.color == .black ? 1.015 : 0.995) * cellP
                    StoneView2D(color: rs.color, position: rs.id)
                        .frame(width: sS, height: sS)
                        .position(x: CGFloat(rs.id.col) * cellP + (rs.offset.x * cellP),
                                  y: CGFloat(rs.id.row) * rowP + (rs.offset.y * rowP))
                }
                
                if let ghostPos = boardVM.ghostPosition, let color = boardVM.ghostColor {
                    StoneView2D(color: color, position: ghostPos)
                        .frame(width: cellP, height: cellP)
                        .opacity(0.4)
                        .position(x: CGFloat(ghostPos.col) * cellP, y: CGFloat(ghostPos.row) * rowP)
                }

                // MARKER LAYER (Over Stones)
                if let lastPos = boardVM.lastMovePosition {
                    let j = boardVM.getJitterOffset(forPosition: lastPos)
                    let tx = CGFloat(lastPos.col) * cellP + (j.x * cellP)
                    let ty = CGFloat(lastPos.row) * rowP + (j.y * rowP)
                    
                    Group {
                        // DOT
                        if AppSettings.shared.showLastMoveDot {
                            Circle().fill(Color.red)
                                .frame(width: cellP * 0.25, height: cellP * 0.25)
                        }
                        
                        // CIRCLE
                        if AppSettings.shared.showLastMoveCircle {
                            let stoneColor = boardVM.stonesToRender.first(where: { $0.id == lastPos })?.color ?? .black
                            let strokeColor = stoneColor == .black ? Color.white : Color.black
                            let width = max(0.8, size.width * 0.0025) // Half previous: max(1.5, ... * 0.005)
                            
                            Circle().stroke(strokeColor, lineWidth: width)
                                .frame(width: cellP * 0.45, height: cellP * 0.45)
                        }
                        
                        // NUMBER
                        if AppSettings.shared.showMoveNumbers {
                            let stoneColor = boardVM.stonesToRender.first(where: { $0.id == lastPos })?.color ?? .black
                            let textColor = stoneColor == .black ? Color.white : Color.black
                            
                            Text("\(boardVM.currentMoveIndex)")
                                .font(.system(size: cellP * 0.5, weight: .bold))
                                .foregroundColor(textColor)
                        }
                    }
                    .position(x: tx, y: ty)
                }
            }
            .frame(width: gridW, height: gridH)
            
            // Interaction Layer (Top-most)
            Color.clear.contentShape(Rectangle())
                .frame(width: size.width, height: size.height)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        let c = Int(round((loc.x - margin) / cellP))
                        let r = Int(round((loc.y - margin) / rowP))
                        if c >= 0 && c < bSize && r >= 0 && r < bSize {
                            boardVM.updateGhostStone(at: BoardPosition(r, c))
                        } else { boardVM.clearGhostStone() }
                    case .ended: boardVM.clearGhostStone()
                    }
                }
                .onTapGesture { loc in
                    let c = Int(round((loc.x - margin) / cellP))
                    let r = Int(round((loc.y - margin) / rowP))
                    if c >= 0 && c < bSize && r >= 0 && r < bSize {
                        boardVM.placeStone(at: BoardPosition(r, c))
                    }
                }
        }
    }
    
    private func starPoints(size: Int) -> [BoardPosition] {
        if size == 19 { return [BoardPosition(3,3), BoardPosition(3,9), BoardPosition(3,15), BoardPosition(9,3), BoardPosition(9,9), BoardPosition(9,15), BoardPosition(15,3), BoardPosition(15,9), BoardPosition(15,15)] }
        return []
    }
}
