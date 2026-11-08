// MARK: - File: BoardView2D.swift (v8.103)
import SwiftUI

struct BoardView2D: View {
    @ObservedObject var boardVM: BoardViewModel
    @ObservedObject var layoutVM: LayoutViewModel
    @ObservedObject private var settings = AppSettings.shared
    let size: CGSize
    
    var body: some View {
        let grid = Self.gridRect(in: size, boardSize: boardVM.boardSize, showsCoordinates: settings.showBoardCoordinates)
        let gridW = grid.width
        let gridH = grid.height
        let bSize = boardVM.boardSize
        let cellP = gridW / CGFloat(max(1, bSize - 1))
        let rowP = gridH / CGFloat(max(1, bSize - 1))
        let displayedStones = boardVM.displayedStones
        let ownership = boardVM.ownershipEstimates
        
        ZStack {
            ZStack {
                Color(red: 0.82, green: 0.65, blue: 0.4)
                SafeImage(name: "board_kaya.jpg", resizingMode: .stretch)
            }
            .frame(width: size.width, height: size.height)
            .cornerRadius(2)
            .shadow(color: .black.opacity(0.5), radius: 12, x: 20, y: 20)
            
            if settings.showBoardCoordinates {
                Canvas { context, _ in
                    let fontSize = min(cellP, rowP) * 0.40
                    for index in 0..<bSize {
                        let letter = Text(GoBoardCoordinates.column(index))
                            .font(.system(size: fontSize, weight: .bold)).foregroundColor(.black)
                        let number = Text(GoBoardCoordinates.row(index, boardSize: bSize))
                            .font(.system(size: fontSize, weight: .bold)).foregroundColor(.black)
                        let x = grid.minX + CGFloat(index) * cellP
                        let y = grid.minY + CGFloat(index) * rowP
                        context.draw(letter, at: CGPoint(x: x, y: grid.minY - rowP * 0.82))
                        context.draw(letter, at: CGPoint(x: x, y: grid.maxY + rowP * 0.82))
                        context.draw(number, at: CGPoint(x: grid.minX - cellP * 0.82, y: y))
                        context.draw(number, at: CGPoint(x: grid.maxX + cellP * 0.82, y: y))
                    }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    if let texture = AIOwnershipTexture.image(estimates: ownership, size: bSize) {
                        context.draw(Image(decorative: texture, scale: 1),
                            in: CGRect(x: -cellP / 2, y: -rowP / 2,
                                       width: CGFloat(bSize) * cellP, height: CGFloat(bSize) * rowP))
                    }
                }
                .allowsHitTesting(false)
                BoardGridShape(boardSize: bSize)
                    .stroke(Color.black.opacity(0.8), lineWidth: 1.0)
                
                ForEach(starPoints(size: bSize), id: \.self) { pt in
                    Circle().fill(Color.black)
                        .frame(width: size.width * 4 / GoEquipmentDimensions2D.boardWidth,
                               height: size.width * 4 / GoEquipmentDimensions2D.boardWidth)
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

                ForEach(displayedStones) { rs in
                    let sS = GoEquipmentDimensions2D.stoneDiameter(rs.color) / GoEquipmentDimensions2D.columnPitch * cellP
                    StoneView2D(color: rs.color, position: rs.id)
                        .frame(width: sS, height: sS)
                        .opacity(rs.isDead ? 0.4 : 1 - 0.65 * rs.predictedDeathStrength)
                        .grayscale(rs.isDead ? 1.0 : 0.0)
                        .overlay {
                            if !rs.isDead, rs.predictedDeathStrength > 0 {
                                Image(systemName: "xmark")
                                    .font(.system(size: sS * (0.25 + 0.3 * rs.predictedDeathStrength), weight: .bold))
                                    .foregroundStyle(rs.color == .black ? Color.white : Color.black)
                                    .opacity(0.3 + 0.7 * rs.predictedDeathStrength)
                                    .accessibilityLabel("AI estimate: likely dead")
                                    .allowsHitTesting(false)
                            }
                        }
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
                
                ForEach(displayedStones) { stone in
                    if let number = boardVM.variationFrame?.numbers[stone.id] {
                        Text("\(number)")
                            .font(.system(size: cellP * 0.48, weight: .bold))
                            .foregroundColor(stone.color == .black ? .white : .black)
                            .position(x: CGFloat(stone.id.col) * cellP, y: CGFloat(stone.id.row) * rowP)
                    }
                }

                // AI Top Moves Layer
                AITopMovesOverlay(vm: boardVM, availableSize: size, padding: CGSize(width: grid.minX, height: grid.minY))

                
                if !boardVM.isPreviewingVariation, let ghostPos = boardVM.ghostPosition, let color = boardVM.ghostColor {
                    let diameter = GoEquipmentDimensions2D.stoneDiameter(color) / GoEquipmentDimensions2D.columnPitch * cellP
                    StoneView2D(color: color, position: ghostPos)
                        .frame(width: diameter, height: diameter)
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
                    SelectedMoveStoneLabels(vm: boardVM, cellWidth: cellP)
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
                        let c = Int(round((loc.x - grid.minX) / cellP))
                        let r = Int(round((loc.y - grid.minY) / rowP))
                        if c >= 0 && c < bSize && r >= 0 && r < bSize {
                            boardVM.updateGhostStone(at: BoardPosition(r, c))
                            boardVM.hoverAnalysis(at: BoardPosition(r, c))
                        } else { boardVM.clearGhostStone(); boardVM.hoverAnalysis(at: nil) }
                    case .ended: boardVM.clearGhostStone(); boardVM.hoverAnalysis(at: nil)
                    }
                }
                .onTapGesture { loc in
                    let c = Int(round((loc.x - grid.minX) / cellP))
                    let r = Int(round((loc.y - grid.minY) / rowP))
                    if c >= 0 && c < bSize && r >= 0 && r < bSize {
                        boardVM.placeStone(at: BoardPosition(r, c))
                    }
                }

            // Explicit targets above the placement layer also expose branch
            // navigation to keyboard and accessibility users.
            ForEach(boardVM.reviewVariationChoices) { choice in
                Button {
                    boardVM.placeStone(at: choice.position)
                } label: {
                    StoneView2D(color: choice.color, position: choice.position, showsShadow: false)
                        .opacity(0.45)
                        .frame(width: cellP * 0.96, height: cellP * 0.96)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open variation")
                .accessibilityLabel("Open variation \(choice.label)")
                .onHover { hovering in
                    if hovering { boardVM.clearGhostStone(); boardVM.hoverAnalysis(at: nil) }
                }
                .position(x: grid.minX + CGFloat(choice.position.col) * cellP,
                          y: grid.minY + CGFloat(choice.position.row) * rowP)
            }
        }
        .onDisappear { boardVM.cancelVariationPreview() }
    }
    
    /// Reserve one cell of wood for labels and edge stones. All overlays and
    /// pointer calculations use this same rectangle, including smaller boards.
    static func gridRect(in size: CGSize, boardSize: Int, showsCoordinates: Bool) -> CGRect {
        let original = GoEquipmentDimensions2D.gridRect(in: size)
        guard showsCoordinates else { return original }
        let intervals = CGFloat(max(1, boardSize - 1))
        let width = min(original.width, size.width * intervals / (intervals + 2.2))
        let height = min(original.height, size.height * intervals / (intervals + 2.2))
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                      width: width, height: height)
    }

    private func starPoints(size: Int) -> [BoardPosition] {
        if size == 19 { return [BoardPosition(3,3), BoardPosition(3,9), BoardPosition(3,15), BoardPosition(9,3), BoardPosition(9,9), BoardPosition(9,15), BoardPosition(15,3), BoardPosition(15,9), BoardPosition(15,15)] }
        return []
    }
}

/// Kept separate so arriving analysis updates the labels even when the board has
/// not moved. The center remains clear for the red last-move dot.
struct SelectedMoveStoneLabels: View {
    @ObservedObject var vm: BoardViewModel
    @ObservedObject private var ai = KataGoEngine.shared
    let cellWidth: CGFloat

    var body: some View {
        ZStack {
            if vm.emphasizesReviewedMove,
               let move = SelectedMoveFeedback(engine: vm.engine, analyses: ai.currentAnalysisData), move.hasStone,
               let loss = move.stoneLossText, let chance = move.stoneChanceText {
                label(chance, color: move.player).offset(y: -cellWidth * 0.29)
                label(loss, color: move.player).offset(y: cellWidth * 0.29)
            }
        }
        .frame(width: cellWidth, height: cellWidth)
        .allowsHitTesting(false)
        .accessibilityLabel(vm.selectedMoveFeedback.map { $0.title + ": " + $0.lossText + ". " + ($0.chanceText ?? "") } ?? "")
    }

    private func label(_ text: String, color: Stone) -> some View {
        let ink: Color = color == .black ? .white : .black
        let outline: Color = color == .black ? .black : .white
        return Text(text)
            .font(.system(size: max(8, cellWidth * 0.23), weight: .bold, design: .rounded))
            .monospacedDigit().foregroundStyle(ink).fixedSize()
            .shadow(color: outline, radius: 0.6, x: 1, y: 0)
            .shadow(color: outline, radius: 0.6, x: -1, y: 0)
            .shadow(color: outline, radius: 0.6, x: 0, y: 1)
            .shadow(color: outline, radius: 0.6, x: 0, y: -1)
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
                    .stroke(MoveLossPalette.color(pointsLost: marker.pointsLost), style: StrokeStyle(lineWidth: max(1.5, cellWidth * 0.045), lineCap: .round))
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
