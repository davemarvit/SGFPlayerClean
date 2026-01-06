// MARK: - File: OGSBrowserView.swift (v4.202)
import SwiftUI

struct OGSBrowserView: View {
    @EnvironmentObject var app: AppModel
    @Binding var isPresentingCreate: Bool
    var onJoin: (Int) -> Void

    @AppStorage("ogs_filter_speed") private var selectedSpeed: GameSpeedFilter = .all
    @AppStorage("ogs_filter_ranked") private var showRankedOnly: Bool = false
    @AppStorage("ogs_filter_sizes") private var sizeFiltersRaw: String = "19,13,9,Other"

    private var sizeFilters: Set<BoardSizeCategory> {
        Set(sizeFiltersRaw.split(separator: ",").compactMap { BoardSizeCategory(rawValue: String($0)) })
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().background(Color.white.opacity(0.1))
            if filteredChallenges.isEmpty {
                emptyState
            } else {
                challengeList
            }
        }
        .onAppear {
            if !app.ogsClient.isSubscribedToSeekgraph { app.ogsClient.subscribeToSeekgraph() }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Lobby").font(.headline).foregroundColor(.white)
                Button(action: { isPresentingCreate = true }) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).frame(width: 24, height: 24)
                }.buttonStyle(.bordered).tint(.blue).disabled(!app.ogsClient.isConnected)
                Spacer()
                if app.ogsClient.isConnected { Label("Connected", systemImage: "circle.fill").font(.caption).foregroundColor(.green) }
                else { Button("Retry") { app.ogsClient.connect() }.font(.caption).buttonStyle(.borderedProminent).tint(.orange) }
            }
            HStack(spacing: 12) {
                Text("Size:").font(.caption).foregroundColor(.white.opacity(0.7))
                ForEach(BoardSizeCategory.allCases) { size in
                    Toggle(size.rawValue, isOn: sizeBinding(for: size)).toggleStyle(.checkbox).font(.caption)
                }
                Spacer()
            }
            HStack {
                Picker("", selection: $selectedSpeed) {
                    ForEach(GameSpeedFilter.allCases) { speed in Text(speed.rawValue).tag(speed) }
                }.labelsHidden().frame(width: 120).controlSize(.small)
                Toggle("Rated Only", isOn: $showRankedOnly).toggleStyle(.checkbox).font(.caption)
                Spacer()
            }
        }.padding().background(Color.black.opacity(0.1))
    }

    private var emptyState: some View {
        VStack { Spacer(); Text(app.ogsClient.isConnected ? "No challenges found." : "Connecting...").foregroundColor(.white.opacity(0.5)); Spacer() }
    }

    private var challengeList: some View {
        List {
            ForEach(filteredChallenges) { challenge in
                ChallengeRow(challenge: challenge, isMine: isChallengeMine(challenge)) {
                    if isChallengeMine(challenge) { app.ogsClient.cancelChallenge(challengeID: challenge.id) }
                    else { onJoin(challenge.id) }
                }
            }
        }
        .listStyle(.inset).scrollContentBackground(.hidden)
    }

    // FIX: Broken down into sub-expressions to prevent compiler timeout
    private var filteredChallenges: [OGSChallenge] {
        let all = app.ogsClient.availableGames
        let filtered = all.filter { game in
            if showRankedOnly && !(game.game?.ranked ?? false) { return false }
            
            let w = game.game?.width ?? 19
            let h = game.game?.height ?? 19
            let cat: BoardSizeCategory = (w == 19 && h == 19) ? .size19 : (w == 13 && h == 13) ? .size13 : (w == 9 && h == 9) ? .size9 : .other
            if !sizeFilters.contains(cat) { return false }
            
            if selectedSpeed != .all {
                let speed = game.speedCategory
                if selectedSpeed == .live && speed != "live" { return false }
                if selectedSpeed == .blitz && speed != "blitz" { return false }
                if selectedSpeed == .correspondence && speed != "correspondence" { return false }
            }
            return true
        }
        return filtered.sorted { $0.id > $1.id }
    }

    private func isChallengeMine(_ challenge: OGSChallenge) -> Bool {
        guard let pid = app.ogsClient.playerID else { return false }
        return challenge.challenger?.id == pid
    }

    private func sizeBinding(for size: BoardSizeCategory) -> Binding<Bool> {
        Binding(
            get: { sizeFilters.contains(size) },
            set: { isActive in
                var current = sizeFilters
                if isActive { current.insert(size) } else { current.remove(size) }
                sizeFiltersRaw = current.map { $0.rawValue }.sorted().joined(separator: ",")
            }
        )
    }
}

struct ChallengeRow: View {
    let challenge: OGSChallenge; let isMine: Bool; let onAction: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onAction) {
                Text(isMine ? "CANCEL" : "ACCEPT").font(.system(size: 10, weight: .bold)).padding(.horizontal, 2).foregroundColor(isMine ? .black : .white)
            }.buttonStyle(.borderedProminent).tint(isMine ? .yellow : .green).controlSize(.small)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(challenge.challenger?.displayRank ?? "?").font(.system(size: 13, weight: .bold)).foregroundColor(rankColor)
                    Text(challenge.challenger?.username ?? "Unknown").font(.system(size: 13, weight: .medium)).lineLimit(1)
                }
                Text(challenge.timeControlDisplay).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            }.frame(minWidth: 100, alignment: .leading)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.boardSize).font(.system(size: 13, weight: .bold))
                Text(challenge.game?.rules?.capitalized ?? "Japanese").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            }.frame(width: 60, alignment: .leading)
            
            if challenge.game?.ranked ?? false {
                Text("RATED").font(.system(size: 10, weight: .heavy)).foregroundColor(.white.opacity(0.8)).padding(.horizontal, 6).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
        }.padding(.vertical, 6).listRowBackground(Color.clear)
    }

    var rankColor: Color {
        guard let rank = challenge.challenger?.ranking else { return .gray }
        if rank >= 30 { return .cyan }
        if rank >= 20 { return .green }
        return .orange
    }
}
