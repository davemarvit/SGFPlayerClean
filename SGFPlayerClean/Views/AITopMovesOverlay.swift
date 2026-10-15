import SwiftUI

/// Draws candidate move dots with winrate % based on KataGo analysis
struct AITopMovesOverlay: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    
    // Board geometry parameters used by BoardView
    let availableSize: CGSize
    let padding: CGFloat
    
    var body: some View {
        let size = vm.boardSize
        if size <= 0 { return AnyView(EmptyView()) }
        
        let gridW = availableSize.width - (padding * 2)
        let gridH = availableSize.height - (padding * 2)
        let cellWidth = gridW / CGFloat(max(1, size - 1))
        let rowHeight = gridH / CGFloat(max(1, size - 1))
        let stoneRadius = cellWidth / 2.0
        
        // Ensure AI is allowed (security feature)
        let isAIAvailable = app.isAIAvailable
        guard isAIAvailable else { return AnyView(EmptyView()) }
        
        // Fetch current analysis
        let turn = vm.currentMoveIndex
        guard let analysis = KataGoEngine.shared.currentAnalysisData[turn],
              let moves = analysis.moveInfos else {
            return AnyView(EmptyView())
        }
        
        // Find Root Data or fallback to best
        let rootWinrate = analysis.rootInfo?.winrate ?? (moves.map { $0.winrate }.max() ?? 0)
        let rootScore = analysis.rootInfo?.scoreLead ?? (moves.map { $0.scoreLead }.max() ?? 0)
        let nextMove = vm.engine.nextHistoricalMovePosition
        
        var topMoves = Array(moves.sorted { $0.winrate > $1.winrate }.prefix(10))
        
        // Force include historical nextMove if not in top 10 but evaluated by KataGo
        if let next = nextMove, !topMoves.contains(where: { parseSGFCoord($0.move, size: size) == next }) {
            if let missingMove = moves.first(where: { parseSGFCoord($0.move, size: size) == next }) {
                topMoves.append(missingMove)
            } else {
                let fallback = AIMoveInfo(move: toGTPCoord(next, size: size), visits: 0, winrate: rootWinrate, scoreLead: rootScore, pv: nil)
                topMoves.append(fallback)
            }
        }
        
        return AnyView(
            ZStack {
                ForEach(topMoves, id: \.move) { info in
                    let isBestMove = info.move == topMoves.first?.move
                    moveDot(info: info, size: size, stoneRadius: stoneRadius, cellWidth: cellWidth, rowHeight: rowHeight, rootWinrate: rootWinrate, rootScore: rootScore, nextMove: nextMove, isBestMove: isBestMove)
                }
            }
        )
    }
    
    @ViewBuilder
    private func moveDot(info: AIMoveInfo, size: Int, stoneRadius: CGFloat, cellWidth: CGFloat, rowHeight: CGFloat, rootWinrate: Double, rootScore: Double, nextMove: BoardPosition?, isBestMove: Bool) -> some View {
        if let pos = parseSGFCoord(info.move, size: size) {
            let dotSize = stoneRadius * 1.5
            
            // Match BoardView2D: Grid intersections are exactly at (col * cellWidth, row * rowHeight).
            let cx = CGFloat(pos.col) * cellWidth
            let cy = CGFloat(pos.row) * rowHeight
            
            let diff = rootWinrate - info.winrate
            let color = getColor(diff: diff)
            
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(0.6) // More transparent in 2D
                    .shadow(radius: 2)
                
                let isNextPlayed = (pos == nextMove)
                
                if isBestMove && isNextPlayed {
                    Circle()
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: dotSize * 0.1, dash: [5]))
                        .frame(width: dotSize * 1.05, height: dotSize * 1.05)
                    Circle()
                        .stroke(Color.black, style: StrokeStyle(lineWidth: dotSize * 0.1, dash: [5, 5], dashPhase: 5))
                        .frame(width: dotSize * 1.05, height: dotSize * 1.05)
                } else if isBestMove {
                    Circle()
                        .stroke(Color.blue, lineWidth: dotSize * 0.1)
                        .frame(width: dotSize * 1.05, height: dotSize * 1.05)
                } else if isNextPlayed {
                    Circle()
                        .stroke(Color.black.opacity(0.8), lineWidth: dotSize * 0.1)
                        .frame(width: dotSize * 1.05, height: dotSize * 1.05)
                }
                
                let deltaWin = (info.winrate - rootWinrate) * 100
                let deltaPt = info.scoreLead - rootScore
                
                let winStr = deltaWin > 0 ? String(format: "+%.1f%%", deltaWin) : String(format: "%.1f%%", deltaWin)
                let ptStr = deltaPt > 0 ? String(format: "+%.1f", deltaPt) : String(format: "%.1f", deltaPt)
                
                VStack(spacing: 0) {
                    Text(winStr)
                        .font(.system(size: dotSize * 0.38, weight: .bold))
                        .foregroundColor(.black)
                    Text(ptStr)
                        .font(.system(size: dotSize * 0.38, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .position(x: cx, y: cy)
        }
    }
    
    private func getColor(diff: Double) -> Color {
        if diff < 0.05 {
            return .green
        } else if diff < 0.15 {
            return .yellow
        } else {
            return .red.opacity(0.6)
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
