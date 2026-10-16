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
                if !boardVM.isPreviewingVariation, let lastPos = boardVM.lastMovePosition,
                   (AppSettings.shared.showBoardGlow || AppSettings.shared.showEnhancedGlow) {
                    let j = boardVM.getJitterOffset(forPosition: lastPos)
                    let tx = CGFloat(lastPos.col) * cellP + (j.x * cellP)
                    let ty = CGFloat(lastPos.row) * rowP + (j.y * rowP)
                    
                    let s = AppSettings.shared.showEnhancedGlow ? cellP * 1.8 : cellP * 1.5
                    Circle().fill(RadialGradient(gradient: Gradient(colors: [Color.red.opacity(0.6), Color.clear]), center: .center, startRadius: 0, endRadius: s/2))
                        .frame(width: s, height: s)
                        .position(x: tx, y: ty)
                }

                ForEach(boardVM.displayedStones) { rs in
                    let sS = (rs.color == .black ? 1.015 : 0.995) * cellP
                    StoneView2D(color: rs.color, position: rs.id)
                        .frame(width: sS, height: sS)
                        .opacity(rs.isDead ? 0.4 : 1.0)
                        .grayscale(rs.isDead ? 1.0 : 0.0)
                        .position(x: CGFloat(rs.id.col) * cellP + (rs.offset.x * cellP),
                                  y: CGFloat(rs.id.row) * rowP + (rs.offset.y * rowP))
                }
                
                if !boardVM.isPreviewingVariation, let point = boardVM.koPoint {
                    Circle().fill(RadialGradient(stops: [
                        .init(color: Color(red: 0.9, green: 0.08, blue: 0.06).opacity(0.96), location: 0),
                        .init(color: Color(red: 0.9, green: 0.08, blue: 0.06).opacity(0.9), location: 0.22),
                        .init(color: Color(red: 0.9, green: 0.08, blue: 0.06).opacity(0.38), location: 0.58),
                        .init(color: Color(red: 0.9, green: 0.08, blue: 0.06).opacity(0), location: 1)
                    ], center: .center, startRadius: 0, endRadius: cellP * 0.35))
                        .frame(width: cellP * 0.7, height: cellP * 0.7)
                        .position(x: CGFloat(point.col) * cellP, y: CGFloat(point.row) * rowP)
                        .help("Ko: immediate recapture is not allowed")
                        .accessibilityLabel("Ko: immediate recapture is not allowed")
                }

                // Territory Layer
                ForEach(Array((boardVM.isPreviewingVariation ? [:] : boardVM.territoryPoints).keys), id: \.self) { pos in
                    if let color = boardVM.territoryPoints[pos] {
                        Circle()
                            .fill(RadialGradient(stops: [
                                .init(color: (color == .black ? Color.black : Color.white).opacity(0.96), location: 0),
                                .init(color: (color == .black ? Color.black : Color.white).opacity(0.9), location: 0.22),
                                .init(color: (color == .black ? Color.black : Color.white).opacity(0.38), location: 0.58),
                                .init(color: .clear, location: 1)
                            ], center: .center, startRadius: 0, endRadius: cellP * 0.35))
                            .frame(width: cellP * 0.7, height: cellP * 0.7)
                            .position(x: CGFloat(pos.col) * cellP, y: CGFloat(pos.row) * rowP)
                            .accessibilityLabel(color == .black ? "Black territory" : "White territory")
                    }
                }
                
                ForEach(boardVM.displayedStones) { stone in
                    if let number = boardVM.variationFrame?.numbers[stone.id] {
                        Text("\(number)")
                            .font(.system(size: cellP * 0.48, weight: .bold))
                            .foregroundColor(stone.color == .black ? .white : .black)
                            .position(x: CGFloat(stone.id.col) * cellP, y: CGFloat(stone.id.row) * rowP)
                    }
                }

                // AI Top Moves Layer
                AITopMovesOverlay(vm: boardVM, availableSize: size, padding: margin)
                
                if !boardVM.isPreviewingVariation, let ghostPos = boardVM.ghostPosition, let color = boardVM.ghostColor {
                    StoneView2D(color: color, position: ghostPos)
                        .frame(width: cellP, height: cellP)
                        .opacity(0.4)
                        .position(x: CGFloat(ghostPos.col) * cellP, y: CGFloat(ghostPos.row) * rowP)
                }

                RecentMoveQualityOverlay(vm: boardVM, cellWidth: cellP, rowHeight: rowP)

                // MARKER LAYER (Over Stones)
                if !boardVM.isPreviewingVariation, let lastPos = boardVM.lastMovePosition,
                   boardVM.displayedStones.contains(where: { $0.id == lastPos }) {
                    let j = boardVM.getJitterOffset(forPosition: lastPos)
                    let tx = CGFloat(lastPos.col) * cellP + (j.x * cellP)
                    let ty = CGFloat(lastPos.row) * rowP + (j.y * rowP)
                    
                    Group {
                        // DOT
                        if AppSettings.shared.showLastMoveDot || boardVM.emphasizesReviewedMove {
                            Circle().fill(Color.red)
                                .frame(width: cellP * 0.25, height: cellP * 0.25)
                        }
                        
                        // CIRCLE
                        if AppSettings.shared.showLastMoveCircle {
                            let stoneColor = boardVM.displayedStones.first(where: { $0.id == lastPos })?.color ?? .black
                            let strokeColor = stoneColor == .black ? Color.white : Color.black
                            let width = max(0.8, size.width * 0.0025) // Half previous: max(1.5, ... * 0.005)
                            
                            Circle().stroke(strokeColor, lineWidth: width)
                                .frame(width: cellP * 0.45, height: cellP * 0.45)
                        }
                        
                        // NUMBER
                        if AppSettings.shared.showMoveNumbers && !boardVM.emphasizesReviewedMove {
                            let stoneColor = boardVM.displayedStones.first(where: { $0.id == lastPos })?.color ?? .black
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
                            boardVM.hoverAnalysis(at: BoardPosition(r, c))
                        } else { boardVM.clearGhostStone(); boardVM.hoverAnalysis(at: nil) }
                    case .ended: boardVM.clearGhostStone(); boardVM.hoverAnalysis(at: nil)
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
        .onDisappear { boardVM.cancelVariationPreview() }
    }
    
    private func starPoints(size: Int) -> [BoardPosition] {
        if size == 19 { return [BoardPosition(3,3), BoardPosition(3,9), BoardPosition(3,15), BoardPosition(9,3), BoardPosition(9,9), BoardPosition(9,15), BoardPosition(15,3), BoardPosition(15,9), BoardPosition(15,15)] }
        return []
    }
}

struct RecentMoveQualityOverlay: View {
    @ObservedObject var vm: BoardViewModel
    @ObservedObject private var ai = KataGoEngine.shared
    let cellWidth: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        ForEach(vm.recentMoveQualityMarkers) { marker in
            let jitter = vm.getJitterOffset(forPosition: marker.position)
            ZStack {
                Circle().trim(from: 0.125, to: 0.875)
                    .stroke(marker.stone == .black ? Color.white.opacity(0.6) : Color.black.opacity(0.65),
                            style: StrokeStyle(lineWidth: max(2.5, cellWidth * 0.075), lineCap: .round))
                    .rotationEffect(.degrees(90))
                Circle().trim(from: 0.125, to: 0.875)
                    .stroke(marker.quality.color, style: StrokeStyle(lineWidth: max(1.5, cellWidth * 0.045), lineCap: .round))
                    .rotationEffect(.degrees(90))
                Text(marker.label)
                    .font(.system(size: max(7, cellWidth * 0.22), weight: .bold, design: .rounded))
                    .foregroundStyle(marker.stone == .black ? Color.white : Color.black)
                    .fixedSize()
                    .offset(y: cellWidth * 0.25)
            }
            .frame(width: cellWidth * 0.60, height: cellWidth * 0.60)
            .position(x: (CGFloat(marker.position.col) + jitter.x) * cellWidth,
                      y: (CGFloat(marker.position.row) + jitter.y) * rowHeight)
            .accessibilityLabel("Move \(marker.id): \(marker.quality.rawValue), \(marker.pointsLost) estimated points lost")
        }
        .allowsHitTesting(false)
    }
}
