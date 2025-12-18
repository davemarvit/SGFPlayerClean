//
//  OGSBrowserView.swift
//  SGFPlayerClean
//
//  v3.123: Revert to Sheet.
//  - Restored .sheet presentation (Stable).
//  - Preserves Green/Yellow button logic.
//  - Preserves Persistence.
//

import SwiftUI

enum BoardSizeCategory: String, CaseIterable, Identifiable {
    case size19 = "19", size13 = "13", size9 = "9", other = "Other"
    var id: String { rawValue }
}

enum GameSpeedFilter: String, CaseIterable, Identifiable {
    case all = "All Speeds", live = "Live", blitz = "Blitz", correspondence = "Correspondence"
    var id: String { rawValue }
}

struct OGSBrowserView: View {
    @ObservedObject var client: OGSClient
    @Binding var isPresentingCreate: Bool
    
    // Persistence via AppStorage
    @AppStorage("ogs_filter_speed") private var selectedSpeed: GameSpeedFilter = .all
    @AppStorage("ogs_filter_ranked") private var showRankedOnly: Bool = false
    @AppStorage("ogs_filter_sizes") private var sizeFiltersRaw: String = "19,13,9,Other"
    
    // Helper to read filters
    private var sizeFilters: Set<BoardSizeCategory> {
        Set(sizeFiltersRaw.split(separator: ",").compactMap { BoardSizeCategory(rawValue: String($0)) })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("Lobby").font(.headline).foregroundColor(.white)
                    Button(action: { isPresentingCreate = true }) {
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered).tint(.blue).disabled(!client.isConnected)
                    Spacer()
                    if client.isConnected { Label("Connected", systemImage: "circle.fill").font(.caption).foregroundColor(.green) }
                    else { Button("Retry") { client.connect() }.font(.caption).buttonStyle(.borderedProminent).tint(.orange) }
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                // Filters
                HStack(spacing: 12) {
                    Text("Size:").font(.caption).foregroundColor(.white.opacity(0.7))
                    ForEach(BoardSizeCategory.allCases) { size in
                        Toggle(size.rawValue, isOn: Binding(
                            get: { sizeFilters.contains(size) },
                            set: { isActive in
                                var current = sizeFilters
                                if isActive { current.insert(size) } else { current.remove(size) }
                                sizeFiltersRaw = current.map { $0.rawValue }.sorted().joined(separator: ",")
                            }
                        )).toggleStyle(.checkbox).font(.caption)
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
            .padding()
            .background(Color.black.opacity(0.1))
            
            Divider().background(Color.white.opacity(0.1))
            
            // List
            if client.availableGames.isEmpty {
                VStack { Spacer(); Text(client.isConnected ? "No challenges found." : "Connecting...").foregroundColor(.white.opacity(0.5)); Spacer() }
            } else {
                ScrollViewReader { proxy in
                    List(filteredChallenges) { challenge in
                        let isMine = (client.playerID != nil && challenge.challenger.id == client.playerID!)
                        ChallengeRow(challenge: challenge, isMine: isMine, onAction: {
                            if isMine { client.cancelChallenge(challengeID: challenge.id) }
                            else { client.joinGame(gameID: challenge.id) }
                        })
                        .id(challenge.id)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.top, 8, for: .scrollContent)
                }
            }
            
            // Footer
            HStack {
                Text("\(filteredChallenges.count) / \(client.availableGames.count)").font(.caption).foregroundColor(.white.opacity(0.3))
                Spacer()
            }.padding(6).background(Color.black.opacity(0.1))
        }
        .onAppear { if !client.isSubscribedToSeekgraph { client.subscribeToSeekgraph() } }
        // Reverted to .sheet for stability
        .sheet(isPresented: $isPresentingCreate) {
            OGSCreateChallengeView(client: client, isPresented: $isPresentingCreate)
        }
    }
    
    var filteredChallenges: [OGSChallenge] {
        client.availableGames.filter { game in
            if showRankedOnly && !game.game.ranked { return false }
            let w = game.game.width, h = game.game.height
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
        }.sorted { ($0.challenger.username == client.username) != ($1.challenger.username == client.username) ? ($0.challenger.username == client.username) : ($0.id > $1.id) }
    }
}

struct ChallengeRow: View {
    let challenge: OGSChallenge
    let isMine: Bool
    let onAction: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onAction) {
                Text(isMine ? "CANCEL" : "ACCEPT")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 2)
                    .foregroundColor(isMine ? .black : .white)
            }
            .buttonStyle(.borderedProminent)
            .tint(isMine ? .yellow : .green)
            .controlSize(.small)
            
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
                    Text("RATED").font(.system(size: 10, weight: .heavy)).foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3), lineWidth: 1))
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
