import SwiftUI

struct LocalScoringPanel: View {
    @ObservedObject var vm: BoardViewModel
    let blackName: String?
    let whiteName: String?

    var body: some View {
        ScrollView {
            if let session = vm.localScoring {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.isFinal ? "Final Score" : "Review score").font(.headline).fixedSize()
                        if session.isFinal, let result = session.result {
                            Text(result.winnerDescription(blackName: blackName, whiteName: whiteName))
                                .font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Local game · \(session.isFinal ? "Confirmed result" : "Both players passed")")
                        .font(.caption).foregroundStyle(.secondary)
                    if !session.isFinal {
                        Text("Click a stone to mark its whole group dead or alive. Faded stones are marked dead.")
                            .font(.callout)
                        Picker("Mark", selection: Binding(get: { session.tool }, set: { tool in vm.editLocalScoring { $0.tool = tool } })) {
                            ForEach(LocalScoringSession.Tool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        if session.tool == .neutralAreas {
                            Text("Click an empty area to exclude it from territory; click again to restore it. Use this for eyes in Japanese/Korean seki.")
                                .font(.caption)
                        }
                    }
                    HStack {
                        Circle().fill(Color.black).frame(width: 9, height: 9)
                        Text("Black territory")
                        Circle().fill(Color.white).frame(width: 9, height: 9)
                        Text("White territory")
                    }.font(.caption)
                    Text("Soft dots show counted territory. Unmarked empty points are neutral.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Picker("Scoring rules", selection: Binding(get: { session.rule }, set: { rule in
                        vm.editLocalScoring { $0.rule = rule; $0.handicapBonusOverride = nil; $0.invalidHandicapBonus = false }
                    })) {
                        ForEach(LocalScoringRule.allCases) { Text($0.rawValue).tag($0) }
                    }.disabled(session.isFinal)
                    HStack {
                        Text("White komi")
                        TextField("Required", text: Binding(get: { session.komiText }, set: { value in
                            vm.editLocalScoring { $0.komiText = value }
                        })).textFieldStyle(.roundedBorder).frame(width: 80).disabled(session.isFinal)
                            .accessibilityLabel("White komi")
                    }
                    if let issue = session.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
                    if let score = session.result {
                        let hasHandicapCompensation = score.black.handicap != 0 || score.white.handicap != 0
                        Text((session.rule.territoryScoring ? "Territory + prisoners + komi" : "Living stones + territory + komi")
                             + (hasHandicapCompensation ? " + handicap compensation" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow { Text(""); Text("Black").bold(); Text("White").bold() }
                            row("Total", score.black.total, score.white.total).bold()
                            row("Territory", Double(score.black.territory), Double(score.white.territory))
                            if session.rule.territoryScoring {
                                row("Captured", Double(score.black.captured), Double(score.white.captured))
                                row("Marked dead", Double(score.black.markedDead), Double(score.white.markedDead))
                            } else {
                                row("Living stones", Double(score.black.livingStones), Double(score.white.livingStones))
                            }
                            row("Komi", score.black.komi, score.white.komi)
                            if hasHandicapCompensation {
                                row("Handicap compensation", score.black.handicap, score.white.handicap)
                            }
                        }.font(.callout).monospacedDigit()
                    }
                    if !session.isFinal {
                        Text("Review dead groups and neutral areas together before confirming. Life and death are not determined automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Confirm score") { vm.confirmLocalScore() }
                            .buttonStyle(.borderedProminent).disabled(session.result == nil)
                        Button("Clear marks") { vm.editLocalScoring { $0.deadStones = []; $0.neutralPoints = [] } }
                    } else {
                        Button("Edit scoring") { vm.reviewLocalScore() }
                    }
                    Button("Resume play") { vm.resumeLocalPlay() }
                    Text("Scoring marks and this result are kept for this review session; the SGF file is unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(14)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        .accessibilityIdentifier("local-scoring-panel")
    }

    private func row(_ label: String, _ black: Double, _ white: Double) -> some View {
        GridRow {
            Text(label)
            Text(black.formatted(.number.precision(.fractionLength(0...2))))
            Text(white.formatted(.number.precision(.fractionLength(0...2))))
        }
    }
}

/// Observe scoring directly so a second pass opens the sidebar even when it was closed.
struct RightSidebarOverlay: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    var body: some View {
        if app.showRightPanel || vm.localScoringVisible {
            HStack {
                Spacer()
                Group {
                    if vm.localScoringVisible {
                        LocalScoringPanel(vm: vm, blackName: app.selection?.game.info.playerBlack,
                                          whiteName: app.selection?.game.info.playerWhite)
                            .frostedGlassStyle()
                    } else { RightPanelView() }
                }.frame(width: 320)
                    .background(Color.black.opacity(0.15))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}
