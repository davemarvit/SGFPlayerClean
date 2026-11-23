import SwiftUI
import Charts

struct PhysicalGameReviewView:View {
    @ObservedObject var review:PhysicalGameReview
    @State private var selectedTurn:Int?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Game review").font(.title2.bold())
                Spacer()
                if review.busy {ProgressView().controlSize(.small)}
                Text(review.coverage).font(.callout).foregroundStyle(.secondary)
            }
            if let reason=review.unavailableReason {
                Text(reason).foregroundStyle(.secondary)
            } else if review.totalMoves==0 {
                Text("Player assessments appear after moves have been played.").foregroundStyle(.secondary)
            } else {
                if review.busy {
                    ProgressView(value:Double(review.evaluations.count),total:Double(max(1,review.totalMoves)))
                    Text("Analyzing the game · assessments update as moves are analyzed.").font(.caption).foregroundStyle(.secondary)
                }
                if let error=review.error {
                    HStack {Text(error).foregroundStyle(.orange);Button("Retry game analysis") {review.start()}}
                }
                HStack(alignment:.top,spacing:24) {
                    graph.frame(width:520)
                    summary.frame(width:330)
                }
                Text("Accuracy uses the same difficulty-weighted assessment as SGFPlayer Clean. Statistics cover analyzed moves; missing analysis is never counted as a perfect move.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical,8)
    }
    private var graph:some View {
        let points=review.points
        let scale=AIReviewGraphScale(scores:points.map { $0.summary.blackScoreLead })
        let evals=Dictionary(uniqueKeysWithValues:review.evaluations.map {($0.turn+1,$0)})
        let focused=points.first {$0.turn==selectedTurn} ?? points.last
        return VStack(alignment:.leading,spacing:10) {
            Text("Game graph").font(.headline)
            if points.isEmpty {
                Text("Waiting for position analysis…").foregroundStyle(.secondary).frame(height:205)
            } else {
                Chart {
                    ForEach(points) {point in
                        LineMark(x:.value("Move",point.turn),y:.value("Value",point.summary.blackScoreLead),
                                 series:.value("Series","score-\(point.segment)"))
                            .foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth:1.5,dash:[3]))
                            .interpolationMethod(.monotone)
                        LineMark(x:.value("Move",point.turn),y:.value("Value",scale.winratePosition(point.summary.blackWinrate)),
                                 series:.value("Series","win-\(point.segment)"))
                            .foregroundStyle(.blue).interpolationMethod(.monotone)
                        PointMark(x:.value("Move",point.turn),y:.value("Value",point.summary.blackScoreLead))
                            .foregroundStyle(.green).symbolSize(8)
                        if let move=evals[point.turn],-move.scoreDelta>=2 {
                            PointMark(x:.value("Move",point.turn),y:.value("Value",scale.winratePosition(point.summary.blackWinrate)))
                                .foregroundStyle(MoveLossPalette.color(pointsLost:-move.scoreDelta)).symbolSize(35)
                        }
                    }
                    RuleMark(y:.value("Even",0)).foregroundStyle(.secondary.opacity(0.3))
                    if let selectedTurn {
                        RuleMark(x:.value("Selected move",selectedTurn)).foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth:1,dash:[4]))
                    }
                }
                .chartXScale(domain:0...max(1,review.totalMoves))
                .chartYScale(domain: -scale.limit...scale.limit)
                .chartXAxis {AxisMarks(values:.automatic(desiredCount:6))}
                .chartYAxis {
                    AxisMarks(position:.leading,values:[-scale.limit,0,scale.limit]) {value in
                        AxisGridLine();AxisTick();AxisValueLabel {
                            if let score=value.as(Double.self) {Text(score==0 ? "0":String(format:"%+.2g",score))}
                        }
                    }
                    AxisMarks(position:.trailing,values:[-scale.limit,0,scale.limit]) {value in
                        AxisTick();AxisValueLabel {
                            if let score=value.as(Double.self) {Text(String(format:"%.0f%%",(score/scale.limit+1)*50))}
                        }
                    }
                }
                .chartPlotStyle {plot in plot.background(LinearGradient(colors:[.black.opacity(0.4),.gray.opacity(0.2),.white.opacity(0.35)],startPoint:.top,endPoint:.bottom))}
                .chartOverlay {proxy in
                    GeometryReader {geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover {phase in
                                switch phase {
                                case .active(let location):select(location,proxy:proxy,geometry:geometry,points:points)
                                case .ended:selectedTurn=nil
                                }
                            }
                            .onTapGesture {location in select(location,proxy:proxy,geometry:geometry,points:points)}
                    }
                }.frame(height:205)
                .accessibilityLabel("Game graph. Positive score and win probability above fifty percent favor Black; negative score favors White. Missing analysis leaves gaps.")
            }
            HStack {
                Text("Win probability").foregroundStyle(.blue)
                Text("Score · dashed").foregroundStyle(.green)
                Spacer()
                Text("Move →").foregroundStyle(.secondary)
            }.font(.caption)
            Text("Black’s point lead (left) and win probability (right). Colored dots mark losses of 2+ points.")
                .font(.caption).foregroundStyle(.secondary)
            if let focused {
                Text("Move \(focused.turn) · \(focused.summary.label)")
                    .font(.callout).monospacedDigit().accessibilityIdentifier("game-graph-readout")
            }
        }
    }
    private func select(_ location:CGPoint,proxy:ChartProxy,geometry:GeometryProxy,points:[PhysicalGameReview.Point]) {
        let plot=geometry[proxy.plotAreaFrame]
        guard plot.contains(location),let turn:Double=proxy.value(atX:location.x-plot.minX) else {selectedTurn=nil;return}
        let rounded=Int(turn.rounded())
        selectedTurn=points.contains {$0.turn==rounded} ? rounded:nil
    }
    private var summary:some View {
        let evals=review.evaluations
        let black=review.performance(.black),white=review.performance(.white)
        return VStack(alignment:.leading,spacing:10) {
            Text("Player accuracy & move quality").font(.headline)
            distribution(.black,evaluations:evals)
            distribution(.white,evaluations:evals)
            Grid(alignment:.leading,horizontalSpacing:12,verticalSpacing:7) {
                GridRow {Text("");Text("Black").bold();Text("White").bold()}
                GridRow {Text("Accuracy");statistic(black.accuracy,format:"%.1f / 100");statistic(white.accuracy,format:"%.1f / 100")}
                GridRow {Text("Average loss");statistic(black.meanPointLoss,format:"%.2f pt");statistic(white.meanPointLoss,format:"%.2f pt")}
                GridRow {Text("Analyzed");Text("\(black.analyzedMoves)/\(review.moveCount(.black))");Text("\(white.analyzedMoves)/\(review.moveCount(.white))")}
                ForEach(MoveQuality.allCases) {quality in
                    GridRow {
                        HStack(spacing:5) {Circle().fill(Self.color(quality)).frame(width:8,height:8);Text(quality.rawValue)}
                        count(quality,player:.black,evaluations:evals)
                        count(quality,player:.white,evaluations:evals)
                    }
                }
            }.font(.callout).monospacedDigit()
            if (black.analyzedMoves>0 && black.accuracy==nil) || (white.analyzedMoves>0 && white.accuracy==nil) {
                Text("Accuracy unavailable: this cached analysis lacks candidate probabilities.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func statistic(_ value:Double?,format:String)->some View {
        Text(value.map {String(format:format,$0)} ?? "—")
    }
    private func count(_ quality:MoveQuality,player:Stone,evaluations:[MoveEvaluation])->some View {
        let moves=evaluations.filter {$0.player==player},count=moves.filter {$0.quality==quality}.count
        return Text(moves.isEmpty ? "—":"\(count) (\(Int((100*Double(count)/Double(moves.count)).rounded()))%)")
    }
    private func distribution(_ player:Stone,evaluations:[MoveEvaluation])->some View {
        let moves=evaluations.filter {$0.player==player}
        return HStack(spacing:8) {
            Text(player == .black ? "Black":"White").font(.caption).frame(width:36,alignment:.leading)
            GeometryReader {geometry in
                HStack(spacing:0) {
                    ForEach(MoveQuality.allCases) {quality in
                        let count=moves.filter {$0.quality==quality}.count
                        if count>0 {
                            Rectangle().fill(Self.color(quality)).frame(width:geometry.size.width*Double(count)/Double(max(1,moves.count)))
                        }
                    }
                }
            }.frame(height:10).background(Color.secondary.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius:3))
                .accessibilityLabel("\(player.rawValue) move-quality distribution; counts and percentages in the table")
        }
    }
    private static func color(_ quality:MoveQuality)->Color {
        switch quality {
        case .excellent:return MoveLossPalette.color(pointsLost:0)
        case .good:return MoveLossPalette.color(pointsLost:0.5)
        case .mediocre:return MoveLossPalette.color(pointsLost:3)
        case .poor:return MoveLossPalette.color(pointsLost:6)
        case .disastrous:return MoveLossPalette.color(pointsLost:12)
        }
    }
}
