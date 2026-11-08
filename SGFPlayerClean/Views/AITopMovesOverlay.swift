import SwiftUI

/// Draws candidate move dots with winrate % based on KataGo analysis
struct AITopMovesOverlay: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    
    // Board geometry parameters used by BoardView
    let availableSize: CGSize
    let padding: CGSize
    
    var body: some View {
        let size = vm.boardSize
        if size <= 0 { return AnyView(EmptyView()) }
        
        let gridW = availableSize.width - (padding.width * 2)
        let gridH = availableSize.height - (padding.height * 2)
        let cellWidth = gridW / CGFloat(max(1, size - 1))
        let rowHeight = gridH / CGFloat(max(1, size - 1))
        let stoneRadius = cellWidth / 2.0
        
        // Ensure AI is allowed (security feature)
        let isAIAvailable = app.isAIAvailable && !vm.isPreviewingVariation && !vm.localScoringVisible
        guard isAIAvailable else { return AnyView(EmptyView()) }
        
        // Fetch current analysis
        let turn = vm.currentMoveIndex
        guard let analysis = KataGoEngine.shared.currentAnalysisData[turn] else {
            return AnyView(EmptyView())
        }
        
        let moves = analysis.moveInfos ?? []
        let bestMove = AIMovePresentation.ranked(moves).first
        // Find Root Data or fallback to best
        let rootWinrate = analysis.rootInfo?.winrate ?? bestMove?.winrate ?? 0
        let rootScore = analysis.rootInfo?.scoreLead ?? bestMove?.scoreLead ?? 0
        let nextMove = vm.engine.nextHistoricalMovePosition
        
        let topMoves = vm.reviewCandidateMoves

        return AnyView(
            ZStack {
                ForEach(topMoves, id: \.move) { info in
                    let isBestMove = info.move == bestMove?.move
                    moveDot(info: info, size: size, stoneRadius: stoneRadius, cellWidth: cellWidth, rowHeight: rowHeight, rootWinrate: rootWinrate, rootScore: rootScore, nextMove: nextMove, isBestMove: isBestMove)
                }
            }
        )
    }
    
    @ViewBuilder
    private func moveDot(info: AIMoveInfo, size: Int, stoneRadius: CGFloat, cellWidth: CGFloat, rowHeight: CGFloat, rootWinrate: Double, rootScore: Double, nextMove: BoardPosition?, isBestMove: Bool) -> some View {
        if let pos = parseSGFCoord(info.move, size: size),
           !vm.reviewVariationChoices.contains(where: { $0.position == pos }) {
            let dotSize = stoneRadius * 1.5
            
            // Match BoardView2D: Grid intersections are exactly at (col * cellWidth, row * rowHeight).
            let cx = CGFloat(pos.col) * cellWidth
            let cy = CGFloat(pos.row) * rowHeight
            
            let isNextPlayed = (pos == nextMove)
            let lossColor = MoveLossPalette.sample(pointsLost: rootScore - info.scoreLead)
            let color = lossColor.color
            
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .shadow(radius: 2)

                if isNextPlayed {
                    Circle().stroke(color, lineWidth: dotSize * 0.025)
                        .brightness(-0.18)
                        .frame(width: dotSize * 0.97, height: dotSize * 0.97)
                }
                
                if isBestMove {
                    Circle().stroke(Color.blue, lineWidth: dotSize * 0.12)
                        .frame(width: dotSize * 0.88, height: dotSize * 0.88)
                }
                if isNextPlayed {
                    let dashPeriod = .pi * dotSize * 1.14 / 12
                    let playedColor: Color = vm.engine.moveColor(at: vm.currentMoveIndex) == .white ? .white : .black
                    Circle().stroke(playedColor, style: StrokeStyle(lineWidth: max(2, dotSize * 0.055),
                        dash: [dashPeriod * 0.62, dashPeriod * 0.38]))
                        .frame(width: dotSize * 1.14, height: dotSize * 1.14)
                }

                let deltaWin = (info.winrate - rootWinrate) * 100
                let deltaPt = info.scoreLead - rootScore
                
                let winStr = deltaWin > 0 ? String(format: "+%.1f%%", deltaWin) : String(format: "%.1f%%", deltaWin)
                let ptStr = deltaPt > 0 ? String(format: "+%.1f", deltaPt) : String(format: "%.1f", deltaPt)
                
                VStack(spacing: 0) {
                    Text(winStr)
                        .font(.system(size: dotSize * 0.38, weight: .bold))
                        .foregroundColor(lossColor.labelColor)
                    Text(ptStr)
                        .font(.system(size: dotSize * 0.38, weight: .bold))
                        .foregroundColor(lossColor.labelColor)
                }
                .lineLimit(1)
                .minimumScaleFactor(isNextPlayed ? 0.5 : 1)
                .frame(width: isNextPlayed ? dotSize * 0.88 : nil)
            }
            .position(x: cx, y: cy)
        }
    }
    
    // KataGo coords: A1 to T19
    private func parseSGFCoord(_ s: String, size: Int) -> BoardPosition? {
        if s.lowercased() == "pass" { return nil }
        guard s.count >= 2 else { return nil }
        
        let letters = "ABCDEFGHJKLMNOPQRST" // Standard GTP skip I
        let uppercased = s.uppercased()
        let char = uppercased[uppercased.startIndex]
        
        guard let xIndex = letters.firstIndex(of: char) else { return nil }
        let x = letters.distance(from: letters.startIndex, to: xIndex)
        
        let numRange = uppercased.index(after: uppercased.startIndex)..<uppercased.endIndex
        let numStr = String(uppercased[numRange])
        guard let yMath = Int(numStr) else { return nil }
        
        // GTP Y is 1 at bottom, size at top. UI array has 0 at top.
        let y = size - yMath
        
        if x >= 0, x < size, y >= 0, y < size {
            return BoardPosition(y, x)
        }
        return nil
    }
    
    // Reverse lookup helper
    private func toGTPCoord(_ pos: BoardPosition, size: Int) -> String {
        let letters = "ABCDEFGHJKLMNOPQRST" // Standard GTP skip I
        guard pos.col >= 0, pos.col < letters.count else { return "" }
        let xIndex = letters.index(letters.startIndex, offsetBy: pos.col)
        let xChar = letters[xIndex]
        let yMath = size - pos.row
        return "\(xChar)\(yMath)"
    }
}
