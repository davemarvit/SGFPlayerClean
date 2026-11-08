import SwiftUI
import Charts

/// A visual representation of the AI's win rate and score lead over the course of the game
struct WinRateGraphView: View {
    @Environment(\.interfaceTextScale) private var textScale
    @EnvironmentObject var app: AppModel
    @ObservedObject var aiEngine = KataGoEngine.shared
    @ObservedObject var vm: BoardViewModel
    
    var body: some View {
        let isAIAvailable = app.isAIAvailable
        let evals = isAIAvailable ? aiEngine.evaluateGameQuality(upTo: vm.totalMoves, engine: vm.engine) : [:]
        let scoreScale = AIReviewGraphScale(scores: aiEngine.currentAnalysisData.compactMap { turn, analysis in
            guard let root = analysis.rootInfo,
                  let summary = AIPositionSummary(root: root, playerToMove: vm.engine.playerToMove(at: turn)) else { return nil }
            return summary.blackScoreLead
        })
        
        let mistakeMoves = Set(MistakeFilter(players: vm.mistakePlayers, minimumLoss: vm.mistakeMinimumLoss)
            .moveNumbers(in: Array(evals.values)))

        VStack(spacing: 4) {
            if isAIAvailable, let notice = aiEngine.analysisNotice {
                Text(notice).interfaceFont(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isAIAvailable, let warning = aiEngine.analysisWarning {
                Text(warning).interfaceFont(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isAIAvailable, aiEngine.isEngineRunning, let error = aiEngine.analysisError {
                Text(error).interfaceFont(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry analysis") {
                    aiEngine.retryFailedAnalysis()
                    vm.syncState()
                }.interfaceFont(.caption).buttonStyle(.bordered)
            }
            if !isAIAvailable {
                Text("AI Analysis Hidden (Live Game)")
                    .interfaceFont(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else if !aiEngine.isEngineRunning {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(aiEngine.engineStartupError ?? "KataGo Engine Offline")
                        .interfaceFont(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") { aiEngine.start() }
                        .interfaceFont(.caption2)
                        .buttonStyle(.bordered)
                }
                .padding()
            } else {
                AIPositionReadout(summary: aiEngine.currentAnalysisData[vm.currentMoveIndex]?.rootInfo.flatMap {
                    AIPositionSummary(root: $0, playerToMove: vm.engine.playerToMove(at: vm.currentMoveIndex))
                })
                if aiEngine.currentAnalysisData.isEmpty {
                    Text("No Analysis Data")
                        .interfaceFont(.caption)
                        .foregroundColor(.secondary)
                        .frame(height: 70)
                } else {
                    Chart {
                        ForEach(Array(aiEngine.currentAnalysisData.keys.sorted()), id: \.self) { turn in
                            if let root = aiEngine.currentAnalysisData[turn]?.rootInfo,
                               let summary = AIPositionSummary(root: root, playerToMove: vm.engine.playerToMove(at: turn)) {
                                let blackWinrate = summary.blackWinrate
                                let blackScoreLead = summary.blackScoreLead
                                
                                let mappedWinrate = scoreScale.winratePosition(blackWinrate)
                                
                                LineMark(
                                    x: .value("Turn", turn),
                                    y: .value("Value", mappedWinrate),
                                    series: .value("Metric", "Win %")
                                )
                                .foregroundStyle(.blue)
                                .interpolationMethod(.monotone)
                                
                                LineMark(
                                    x: .value("Turn", turn),
                                    y: .value("Value", blackScoreLead),
                                    series: .value("Metric", "Score Lead")
                                )
                                .foregroundStyle(.green)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3]))
                                .interpolationMethod(.monotone)
                                
                                
                                if mistakeMoves.contains(turn), let ev = evals[turn - 1] {
                                    PointMark(
                                        x: .value("Turn", turn),
                                        y: .value("Value", mappedWinrate)
                                    )
                                    .foregroundStyle(MoveLossPalette.color(pointsLost: -ev.scoreDelta))
                                    .symbolSize(40)
                                }
                                
                            }
                        }
                        
                        RuleMark(x: .value("Current", vm.currentMoveIndex))
                            .foregroundStyle(.red)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        RuleMark(y: .value("Center", 0))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    .chartYScale(domain: -scoreScale.limit...scoreScale.limit)
                    .chartXScale(domain: 0...max(1, vm.totalMoves))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) {
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel().font(.system(size: 13 * textScale))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: [-scoreScale.limit, 0, scoreScale.limit]) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let points = value.as(Double.self) {
                                    Text(points == 0 ? "0" : String(format: "%+.3g", points))
                                        .font(.system(size: 13 * textScale))
                                }
                            }
                        }
                    }
                    .chartPlotStyle { plot in
                        plot.background(LinearGradient(colors: [
                            .black.opacity(0.65), .gray.opacity(0.35), .white.opacity(0.6)
                        ], startPoint: .top, endPoint: .bottom))
                    }
                    // Clicking on the graph to jump to a turn
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
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
                    .padding(.top, 10)
                    .frame(height: 155 * textScale)
                    .padding(.horizontal, 12)
                    HStack(spacing: 10) {
                        Text("Win %").foregroundStyle(.blue)
                        Text("Points · dashed").foregroundStyle(.green)
                            .help("Vertical axis: estimated point lead. Positive favors Black; negative favors White. Bounds follow the largest score magnitude in this game.")
                        Spacer(minLength: 0)
                    }
                    .interfaceFont(.caption2).padding(.horizontal, 12).padding(.bottom, 5)
                }
                
                // Show Progress Bar if analyzing
                let isFullyAnalyzed = aiEngine.currentAnalysisData.count >= vm.totalMoves && vm.totalMoves > 5
                
                if !isFullyAnalyzed && aiEngine.isEngineRunning {
                    let currentVisits = aiEngine.currentAnalysisData[vm.currentMoveIndex]?.rootInfo?.visits ?? 0
                    if currentVisits > 0 && currentVisits < 50 {
                        HStack {
                            Text("Analyzing:")
                                .interfaceFont(.caption2)
                                .foregroundColor(.secondary)
                            ProgressView(value: Double(currentVisits), total: 50.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                                .frame(height: 4)
                            Text("\(currentVisits)/50")
                                .interfaceFont(.caption2).monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 2)
                    } else if aiEngine.currentAnalysisData[vm.currentMoveIndex] == nil {
                        HStack {
                            ProgressView().controlSize(.mini)
                            Text("Queuing Analysis for Move \(vm.currentMoveIndex)...")
                                .interfaceFont(.caption2)
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
struct MoveLossLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Color · estimated points lost").foregroundStyle(.secondary)
            LinearGradient(colors: MoveLossPalette.stops.map(\.color), startPoint: .leading, endPoint: .trailing)
                .frame(height: 10).clipShape(Capsule())
            HStack(spacing: 0) {
                ForEach(Array(MoveLossPalette.stops.enumerated()), id: \.offset) { index, stop in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(index == MoveLossPalette.stops.count - 1 ? "12+" : String(format: "%g", stop.loss))
                }
            }.monospacedDigit()
        }
        .interfaceFont(.caption2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continuous color by estimated points lost: green at zero, lime at half a point, yellow at one and a half, orange at three, red at six, purple at twelve or more.")
    }
}

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
                    Text(q.rawValue)
                    Text("\(bCount[i])")
                    Text("\(wCount[i])")
                }
            }
            GridRow { Text("Average loss"); statistic(.black, accuracy: false); statistic(.white, accuracy: false) }
            GridRow { Text("Accuracy"); statistic(.black, accuracy: true); statistic(.white, accuracy: true) }
        }
        .interfaceFont(.caption2)
        .padding(6)
        .background(Color(white: 0.12))
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
            if let feedback = vm.focusedMistakeFeedback {
                Text(feedback.title + " · " + feedback.lossText)
                    .accessibilityIdentifier("upcoming-mistake-feedback")
                Text(feedback.location == "Pass" ? "The played move was a pass. Compare the alternatives on the board." : "Dashed circle: the move played. Color shows its severity.")
                    .foregroundStyle(.secondary)
            }
            Text("\(analyzedCount) of \(vm.totalMoves) moves analysed on this line")
                .foregroundStyle(.secondary)
        }
        .interfaceFont(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The score and probability remain larger than all supporting analysis text.
struct AIPositionReadout: View {
    @Environment(\.interfaceTextScale) private var textScale
    let summary: AIPositionSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.map { $0.leadingColor == .black ? "Black leads" : "White leads" } ?? "Current position")
                .interfaceFont(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { points; probability }
                VStack(alignment: .leading, spacing: 12) { points; probability }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary?.accessibilityDescription ?? "Analysis pending")
        .accessibilityIdentifier("ai-position-readout")
    }
    private var points: some View {
        metric(summary.map { String(format: "%.1f", abs($0.blackScoreLead)) } ?? "—", label: "Point lead")
    }
    private var probability: some View {
        metric(summary.map { String(format: "%.1f%%", $0.leadingWinrate * 100) } ?? "—", label: "Win probability")
    }
    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 32 * textScale, weight: .bold, design: .rounded))
                .monospacedDigit().fixedSize()
            Text(label).interfaceFont(.caption).foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}
