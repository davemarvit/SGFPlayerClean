import SwiftUI
import Charts

/// A visual representation of the AI's win rate and score lead over the course of the game
struct WinRateGraphView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var aiEngine = KataGoEngine.shared
    @ObservedObject var vm: BoardViewModel
    
    var body: some View {
        let isAIAvailable = app.isAIAvailable
        let evals = isAIAvailable ? aiEngine.evaluateGameQuality(upTo: vm.totalMoves, engine: vm.engine) : [:]
        
        // Find the top 10 worst moves to highlight, ignoring mediocre ones to reduce clutter
        let worstMoves = evals.filter { (key: Int, value: MoveEvaluation) in 
            value.quality == .disastrous || value.quality == .poor 
        }
        .sorted { (lhs: (key: Int, value: MoveEvaluation), rhs: (key: Int, value: MoveEvaluation)) in 
            lhs.value.winDelta < rhs.value.winDelta // Sort ascending (worst negative drops first)
        }
        .prefix(10)
        
        let worstTurns = Set(worstMoves.map { $0.key })
        
        VStack(spacing: 4) {
            if isAIAvailable, let notice = aiEngine.analysisNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isAIAvailable, let warning = aiEngine.analysisWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isAIAvailable, aiEngine.isEngineRunning, let error = aiEngine.analysisError {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry analysis") {
                    aiEngine.retryFailedAnalysis()
                    vm.syncState()
                }.font(.caption).buttonStyle(.bordered)
            }
            if !isAIAvailable {
                Text("AI Analysis Hidden (Live Game)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else if !aiEngine.isEngineRunning {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(aiEngine.engineStartupError ?? "KataGo Engine Offline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") { aiEngine.start() }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                }
                .padding()
            } else {
                if aiEngine.currentAnalysisData.isEmpty {
                    Text("No Analysis Data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(height: 70)
                } else {
                    Chart {
                        ForEach(Array(aiEngine.currentAnalysisData.keys.sorted()), id: \.self) { turn in
                            if let data = aiEngine.currentAnalysisData[turn], let root = data.rootInfo {
                                let playerToMove = vm.engine.playerToMove(at: turn)
                                let blackWinrate = playerToMove == .black ? root.winrate : (1.0 - root.winrate)
                                let blackScoreLead = playerToMove == .black ? root.scoreLead : -root.scoreLead
                                
                                // Map Score Lead tightly to the 0...100 graph layout
                                // Assume 1 point = 1% threshold, centering at 50%
                                let mappedScore = max(0, min(100, 50.0 + blackScoreLead))
                                
                                LineMark(
                                    x: .value("Turn", turn),
                                    y: .value("Value", blackWinrate * 100),
                                    series: .value("Metric", "Win %")
                                )
                                .foregroundStyle(.blue)
                                .interpolationMethod(.monotone)
                                
                                LineMark(
                                    x: .value("Turn", turn),
                                    y: .value("Value", mappedScore),
                                    series: .value("Metric", "Score Lead")
                                )
                                .foregroundStyle(.green)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3]))
                                .interpolationMethod(.monotone)
                                
                                
                                if worstTurns.contains(turn), let ev = evals[turn] {
                                    PointMark(
                                        x: .value("Turn", turn),
                                        y: .value("Value", blackWinrate * 100)
                                    )
                                    .foregroundStyle(ev.quality.color)
                                    .symbolSize(40)
                                }
                                
                                if turn == vm.currentMoveIndex {
                                    RuleMark(x: .value("Current", turn))
                                        .foregroundStyle(.red)
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                                }
                            }
                        }
                        
                        RuleMark(y: .value("Center", 50))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    .chartYScale(domain: 0...102)
                    .chartXScale(domain: 0...max(1, vm.totalMoves))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5))
                    }
                    .padding(.top, 15)
                    .frame(height: 120) // Give dual lines more vertical room
                    .padding(.horizontal)
                    // Clicking on the graph to jump to a turn
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onTapGesture { location in
                                    let origin = geometry[proxy.plotAreaFrame]
                                    let x = location.x - origin.minX
                                    if let turn: Int = proxy.value(atX: x) {
                                        vm.seekToMove(turn)
                                    }
                                }
                        }
                    }
                }
                
                // Show Progress Bar if analyzing
                let isFullyAnalyzed = aiEngine.currentAnalysisData.count >= vm.totalMoves && vm.totalMoves > 5
                
                if !isFullyAnalyzed && aiEngine.isEngineRunning {
                    let currentVisits = aiEngine.currentAnalysisData[vm.currentMoveIndex]?.rootInfo?.visits ?? 0
                    if currentVisits > 0 && currentVisits < 50 {
                        HStack {
                            Text("Analyzing:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            ProgressView(value: Double(currentVisits), total: 50.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                                .frame(height: 4)
                            Text("\(currentVisits)/50")
                                .font(.caption2).monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 2)
                    } else if aiEngine.currentAnalysisData[vm.currentMoveIndex] == nil {
                        HStack {
                            ProgressView().controlSize(.mini)
                            Text("Queuing Analysis for Move \(vm.currentMoveIndex)...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Summary Table
struct MoveQualitySummaryView: View {
    let evals: [MoveEvaluation]
    
    var body: some View {
        let bCount = MoveQuality.allCases.map { q in evals.filter { $0.player == .black && $0.quality == q }.count }
        let wCount = MoveQuality.allCases.map { q in evals.filter { $0.player == .white && $0.quality == q }.count }
        
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("") // Corner
                Text("Black").bold()
                Text("White").bold()
            }
            ForEach(0..<MoveQuality.allCases.count, id: \.self) { i in
                let q = MoveQuality.allCases[i]
                GridRow {
                    HStack {
                        Circle().fill(q.color).frame(width: 8, height: 8)
                        Text(q.rawValue)
                    }
                    Text("\(bCount[i])")
                    Text("\(wCount[i])")
                }
            }
        }
        .font(.caption2)
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}
