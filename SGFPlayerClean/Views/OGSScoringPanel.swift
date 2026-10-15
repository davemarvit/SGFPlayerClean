import SwiftUI

/// Self-contained so the production scoring UI can be rendered with offline fixtures.
struct OGSScoringPanel: View {
    let finished: Bool
    let connected: Bool
    let participant: Bool
    let atLivePosition: Bool
    let canEdit: Bool
    let acceptance: OGSScoreAcceptance
    let strictSeki: Bool
    let summary: OGSScoreSummary?
    var scoringSettings = GameAnalysisSettings()
    var winnerDescription: String? = nil
    var serverTerritory = false
    let error: String?
    let accept: () -> Void
    let resume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(finished ? "Final Score" : "Review scoring", systemImage: "flag.checkered")
                    .font(.headline).fixedSize()
                if finished, let winnerDescription {
                    Text(winnerDescription).font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let summary {
                scoreGrid(summary)
                Text("Score supplied by OGS, including komi and other adjustments.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(serverTerritory ? "Board markers supplied by OGS." : "Board markers are a local estimate.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(finished
                     ? "No numeric score supplied by OGS. Games ending by resignation or timeout may not have one."
                     : "Click a stone group to mark it dead or alive. Faded stones are marked dead.")
                    .font(.callout)
                Text("Territory markers are a local estimate, not a final score.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if finished && !atLivePosition {
                Text("This is the final score; the board is showing an earlier position.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !finished {
                Text("Strict seki scoring: \(strictSeki ? "on" : "off")")
                    .font(.caption).foregroundStyle(.secondary)
                if !connected {
                    status("Reconnect to review and submit scoring.", icon: "wifi.slash")
                } else if !participant {
                    status("Spectating — scoring is controlled by the players.", icon: "eye")
                } else if !atLivePosition {
                    status("Return to the latest move to edit or accept scoring.", icon: "clock.arrow.circlepath")
                } else {
                    switch acceptance {
                    case .none: EmptyView()
                    case .updating: status("Updating marks. Waiting for OGS…", icon: "clock")
                    case .submitting: status("Acceptance sent. Waiting for OGS confirmation…", icon: "clock")
                    case .confirmed: status("OGS confirmed your acceptance. Waiting for the other player.", icon: "checkmark.circle")
                    case .resuming: status("Resume requested. Waiting for OGS…", icon: "clock")
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("Accept scoring", action: accept)
                        .buttonStyle(ScoringButtonStyle(prominent: true))
                        .disabled(!canEdit || !atLivePosition || acceptance != .none)
                    Button("Resume play", action: resume)
                        .buttonStyle(ScoringButtonStyle(prominent: false))
                        .disabled(!canEdit || !atLivePosition)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func status(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.callout).fixedSize(horizontal: false, vertical: true)
    }

    private func scoreGrid(_ score: OGSScoreSummary) -> some View {
        let rows = ScoringRows(settings: scoringSettings)
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow { Text(""); Text("Black").bold(); Text("White").bold() }
            row("Total", score.black.total, score.white.total).bold()
            Divider().gridCellColumns(3)
            if rows.territory { row("Territory", score.black.territory, score.white.territory) }
            if rows.stones { row("Stones", score.black.stones, score.white.stones) }
            if rows.prisoners { row("Prisoners", score.black.prisoners, score.white.prisoners) }
            row("Komi", score.black.komi, score.white.komi)
            if rows.handicap && ((score.black.handicap ?? 0) != 0 || (score.white.handicap ?? 0) != 0) {
                row("Handicap compensation", score.black.handicap, score.white.handicap)
            }
        }
        .font(.callout).monospacedDigit()
    }

    private func row(_ title: String, _ black: Double?, _ white: Double?) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(black.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "—")
            Text(white.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "—")
        }
    }
}

/// Presentation only: server totals remain authoritative. Unknown rules retain rows
/// rather than assuming the analysis engine's default Chinese rules.
private struct ScoringRows {
    let territory, stones, prisoners, handicap: Bool

    init(settings: GameAnalysisSettings) {
        let rules = settings.rules == nil ? nil : (settings.kataRules ?? settings.rules?.lowercased())
        let territoryRules = ["japanese", "korean"].contains(rules ?? "")
        let areaRules = ["chinese", "chinese-ogs", "chinese-kgs", "aga", "bga",
                         "aga-button", "new-zealand", "tromp-taylor", "ing"].contains(rules ?? "")
        let stoneRules = rules == "stone-scoring"
        territory = settings.ruleOverrides?.scoreTerritory ?? !stoneRules
        stones = settings.ruleOverrides?.scoreStones ?? !territoryRules
        prisoners = settings.ruleOverrides?.scorePrisoners ?? !(areaRules || stoneRules)
        if let bonus = settings.whiteHandicapBonus {
            handicap = bonus != "0"
        } else {
            handicap = !(territoryRules || ["new-zealand", "tromp-taylor", "stone-scoring"].contains(rules ?? ""))
        }
    }
}

#if SGF_OFFLINE_REVIEW
/// Display fixtures only: no AppModel, OGSClient, networking, or game mutations.
enum OfflineScoringExample: String, CaseIterable, Identifiable {
    case whiteWin = "White wins by 6.5 points"
    case blackWin = "Black wins by 1 point"
    case draw = "Draw"
    case fractional = "White wins by 6.25 points"
    case missingScore = "No numeric score (resignation or timeout)"
    var id: String { rawValue }

    var summary: OGSScoreSummary? {
        let blackTotal: Double
        let whiteKomi: Double
        switch self {
        case .whiteWin: blackTotal = 29; whiteKomi = 6.5
        case .blackWin: blackTotal = 36; whiteKomi = 6
        case .draw: blackTotal = 29; whiteKomi = 0
        case .fractional: blackTotal = 29; whiteKomi = 6.25
        case .missingScore: return nil
        }
        return OGSScoreSummary.parse([
            "black": ["total": blackTotal, "territory": blackTotal - 4, "stones": 0, "prisoners": 4, "komi": 0],
            "white": ["total": 29 + whiteKomi, "territory": 25, "stones": 0, "prisoners": 4, "komi": whiteKomi]
        ])
    }
}

struct OfflineScoringReview: View {
    @Environment(\.dismiss) private var dismiss
    @State var example: OfflineScoringExample = .whiteWin
    @State private var blackName = "Dave"
    @State private var whiteName = "Alice"
    @State private var earlierPosition = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Offline scoring review").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Illustrative scores, unrelated to the board behind this window. No OGS connection.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Example", selection: $example) {
                ForEach(OfflineScoringExample.allCases) { Text($0.rawValue).tag($0) }
            }
            HStack {
                TextField("Black player", text: $blackName).accessibilityLabel("Black player name")
                TextField("White player", text: $whiteName).accessibilityLabel("White player name")
            }.textFieldStyle(.roundedBorder)
            Toggle("Show the earlier-position notice", isOn: $earlierPosition)
            ScrollView {
                OGSScoringPanel(finished: true, connected: false, participant: false,
                    atLivePosition: !earlierPosition, canEdit: false, acceptance: .none,
                    strictSeki: false, summary: example.summary,
                    winnerDescription: example.summary?.winnerDescription(blackName: blackName, whiteName: whiteName),
                    error: nil, accept: {}, resume: {})
                    .frame(width: 330)
                    .frame(maxWidth: .infinity)
            }
            Text("These examples are independent of your game. To score your board, pass twice, then review dead groups and territory in the sidebar.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 560, height: 610)
    }
}
#endif

private struct ScoringButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.blue : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
