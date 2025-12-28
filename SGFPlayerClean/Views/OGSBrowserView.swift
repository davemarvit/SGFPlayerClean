// MARK: - File: OGSBrowserView.swift (v4.200)
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
            
            footerSection
        }
        .onAppear {
            if !app.ogsClient.isSubscribedToSeekgraph { app.ogsClient.subscribeToSeekgraph() }
        }
    }
    
    private var emptyState: some View {
        VStack {
            Spacer()
            Text(app.ogsClient.isConnected ? "No challenges found." : "Connecting...")
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
    }

    private var challengeList: some View {
        List {
            ForEach(filteredChallenges, id: \.id) { challenge in
                ChallengeRow(
                    challenge: challenge,
                    isMine: isChallengeMine(challenge),
                    onAction: { handleRowAction(challenge) }
                )
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Lobby").font(.headline).foregroundColor(.white)
                Button(action: { isPresentingCreate = true }) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered).tint(.blue).disabled(!app.ogsClient.isConnected)
                Spacer()
                if app.ogsClient.isConnected { Label("Connected", systemImage: "circle.fill").font(.caption).foregroundColor(.green) }
                else { Button("Retry") { app.ogsClient.connect() }.font(.caption).buttonStyle(.borderedProminent).tint(.orange) }
            }
            HStack(spacing: 12) {
                Text("Size:").font(.caption).foregroundColor(.white.opacity(0.7))
                ForEach(BoardSizeCategory.allCases) { size in
                    Toggle(size.rawValue, isOn: sizeBinding(for: size))
                        .toggleStyle(.checkbox).font(.caption)
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
        }
        .padding().background(Color.black.opacity(0.1))
    }
    
    private var footerSection: some View {
        HStack {
            Text("\(filteredChallenges.count) / \(app.ogsClient.availableGames.count) challenges").font(.caption).foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .padding(6).background(Color.black.opacity(0.1))
    }
    
    // MARK: - Logic Helpers
    
    private var filteredChallenges: [OGSChallenge] {
        let all = app.ogsClient.availableGames
        return all.filter { game in
            if showRankedOnly && !game.game.ranked { return false }
            
            let w = game.game.width
            let h = game.game.height
            let cat: BoardSizeCategory = (w==19 && h==19) ? .size19 : (w==13 && h==13) ? .size13 : (w==9 && h==9) ? .size9 : .other
            if !sizeFilters.contains(cat) { return false }
            
            let speed = game.speedCategory.lowercased()
            switch selectedSpeed {
            case .all: break
            case .live: if speed != "live" && speed != "rapid" { return false }
            case .blitz: if speed != "blitz" { return false }
            case .correspondence: if speed != "correspondence" { return false }
            }
            return true
        }.sorted { ($0.challenger.username == app.ogsClient.username) != ($1.challenger.username == app.ogsClient.username) ? ($0.challenger.username == app.ogsClient.username) : ($0.id > $1.id) }
    }
    
    private func isChallengeMine(_ challenge: OGSChallenge) -> Bool {
        guard let pid = app.ogsClient.playerID else { return false }
        return challenge.challenger.id == pid
    }
    
    private func handleRowAction(_ challenge: OGSChallenge) {
        if isChallengeMine(challenge) {
            app.ogsClient.cancelChallenge(challengeID: challenge.id)
        } else {
            onJoin(challenge.id)
        }
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

// MARK: - ChallengeRow Helper
struct ChallengeRow: View {
    let challenge: OGSChallenge; let isMine: Bool; let onAction: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onAction) {
                Text(isMine ? "CANCEL" : "ACCEPT")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 2)
                    .foregroundColor(isMine ? .black : .white)
            }.buttonStyle(.borderedProminent).tint(isMine ? .yellow : .green).controlSize(.small)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(challenge.challenger.displayRank).font(.system(size: 13, weight: .bold)).foregroundColor(rankColor)
                    Text(challenge.challenger.username).font(.system(size: 13, weight: .medium)).lineLimit(1)
                }
                Text(challenge.timeControlDisplay).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            }.frame(minWidth: 100, alignment: .leading)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.boardSize).font(.system(size: 13, weight: .bold))
                Text(challenge.game.rules.capitalized).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            }.frame(width: 60, alignment: .leading)
            
            Group {
                if challenge.game.ranked {
                    Text("RATED").font(.system(size: 10, weight: .heavy)).foregroundColor(.white.opacity(0.8)).padding(.horizontal, 6).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3), lineWidth: 1))
                } else {
                    Text("UNRATED").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.3)).opacity(0)
                }
            }.frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.white.opacity(0.1))
    }
    
    var rankColor: Color {
        guard let rank = challenge.challenger.ranking else { return .gray }
        if rank >= 30 { return .cyan }
        if rank >= 20 { return .green }
        return .orange
    }
}
