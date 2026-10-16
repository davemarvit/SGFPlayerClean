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
        
        let mistakeMoves = Set(MistakeFilter(players: vm.mistakePlayers, minimumLoss: vm.mistakeMinimumLoss)
            .moveNumbers(in: Array(evals.values)))

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
                            if let root = aiEngine.currentAnalysisData[turn]?.rootInfo,
                               let summary = AIPositionSummary(root: root, playerToMove: vm.engine.playerToMove(at: turn)) {
                                let blackWinrate = summary.blackWinrate
                                let blackScoreLead = summary.blackScoreLead
                                
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
                                
                                
                                if mistakeMoves.contains(turn), let ev = evals[turn - 1] {
                                    PointMark(
                                        x: .value("Turn", turn),
                                        y: .value("Value", blackWinrate * 100)
                                    )
                                    .foregroundStyle(ev.quality.color)
                                    .symbolSize(40)
                                }
                                
                            }
                        }
                        
                        RuleMark(x: .value("Current", vm.currentMoveIndex))
                            .foregroundStyle(.red)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        RuleMark(y: .value("Center", 50))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    .chartYScale(domain: 0...100)
                    .chartXScale(domain: 0...max(1, vm.totalMoves))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5))
                    }
                    .chartPlotStyle { plot in
                        plot.background(LinearGradient(colors: [
                            .black.opacity(0.65), .gray.opacity(0.35), .white.opacity(0.6)
                        ], startPoint: .top, endPoint: .bottom))
                    }
                    // Clicking on the graph to jump to a turn
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            let origin = geometry[proxy.plotAreaFrame]
                            let summary = aiEngine.currentAnalysisData[vm.currentMoveIndex]?.rootInfo.flatMap {
                                AIPositionSummary(root: $0, playerToMove: vm.engine.playerToMove(at: vm.currentMoveIndex))
                            }
                            let labelWidth = min(CGFloat(190), origin.width)
                            let markerX = origin.minX + (proxy.position(forX: vm.currentMoveIndex) ?? 0)
                            let labelX = max(origin.minX + labelWidth / 2, min(origin.maxX - labelWidth / 2, markerX))
                            Text(summary?.label ?? "Move \(vm.currentMoveIndex) · Pending")
                                .font(.caption2.monospacedDigit()).foregroundStyle(.white)
                                .frame(width: labelWidth, height: 22)
                                .background(.black.opacity(0.8), in: Capsule())
                                .position(x: labelX, y: origin.minY - 15)
                                .accessibilityLabel(summary?.accessibilityDescription ?? "Analysis pending for move \(vm.currentMoveIndex)")
                                .accessibilityIdentifier("ai-position-readout")
                                .allowsHitTesting(false)
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onTapGesture { location in
                                    let origin = geometry[proxy.plotAreaFrame]
                                    let x = location.x - origin.minX
                                    if origin.contains(location), let turn: Int = proxy.value(atX: x) {
                                        vm.seekToMove(max(0, min(vm.totalMoves, turn)))
                                    }
                                }
                        }
                    }
                    .padding(.top, 30)
                    .frame(height: 155)
                    .padding(.horizontal, 12)
                    HStack(spacing: 10) {
                        Text("Win %").foregroundStyle(.blue)
                        Text("Points · dashed").foregroundStyle(.green)
                        Spacer(minLength: 0)
                    }
                    .font(.caption2).padding(.horizontal, 12).padding(.bottom, 5)
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
    var analyses: [Int: AIAnalysis] = [:]
    
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
            GridRow { Text("Average loss"); statistic(.black, accuracy: false); statistic(.white, accuracy: false) }
            GridRow { Text("Accuracy"); statistic(.black, accuracy: true); statistic(.white, accuracy: true) }
        }
        .font(.caption2)
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
    private func statistic(_ player: Stone, accuracy: Bool) -> some View {
        let stats = AIPlayerPerformance(player: player, evaluations: evals, analyses: analyses)
        let value = accuracy ? stats.accuracy : stats.meanPointLoss
        return Text(value.map { String(format: accuracy ? "%.1f / 100" : "%.2f pt", $0) } ?? "—")
            .help(accuracy ? "KaTrain-style difficulty-weighted accuracy. Requires candidate priors; older cached analysis may not include them. Based on analysed moves, independent of the mistake filter." : "Average points lost per analysed move, independent of the mistake filter.")
    }

}

struct MistakeFilterView: View {
    @ObservedObject var vm: BoardViewModel
    let analyzedCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mistakes by", selection: $vm.mistakePlayers) {
                ForEach(MistakeFilter.Players.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Text("Minimum loss")
                TextField("Points", value: $vm.mistakeMinimumLoss,
                          format: .number.precision(.fractionLength(1)))
                    .frame(width: 50).textFieldStyle(.roundedBorder)
                    .onChange(of: vm.mistakeMinimumLoss) { value in
                        let clamped = value.isFinite ? min(100, max(0, value)) : 2
                        if value != clamped { vm.mistakeMinimumLoss = clamped }
                    }
                Text("points")
            }
            Slider(value: $vm.mistakeMinimumLoss, in: 0...max(10, vm.mistakeMinimumLoss), step: 0.5)
                .accessibilityLabel("Minimum points lost")
            Text("\(vm.matchingMistakeMoves.count) matching mistakes")
                .accessibilityIdentifier("matching-mistake-count")
            Text("\(analyzedCount) of \(vm.totalMoves) moves analysed on this line")
                .foregroundStyle(.secondary)
        }.font(.caption)
    }
}
