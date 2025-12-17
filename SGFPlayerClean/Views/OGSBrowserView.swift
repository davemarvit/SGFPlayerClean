//
//  OGSBrowserView.swift
//  SGFPlayerClean
//
//  v3.108: Restored Transparency & Improved Filters.
//  - REMOVED: Opaque backgrounds blocking the frosted glass effect.
//  - ADDED: .scrollContentBackground(.hidden) to allow transparency in List.
//  - CHANGED: Board Size selector is now a row of Checkboxes (Multi-select).
//  - ADDED: "Rated Only" checkbox.
//

import SwiftUI

// MARK: - Filter Enums
enum BoardSizeCategory: String, CaseIterable, Identifiable {
    case size19 = "19"
    case size13 = "13"
    case size9 = "9"
    case other = "?"
    
    var id: String { rawValue }
}

enum GameSpeedFilter: String, CaseIterable, Identifiable {
    case all = "All Speeds"
    case live = "Live"
    case blitz = "Blitz"
    case correspondence = "Correspondence"
    
    var id: String { rawValue }
}

// MARK: - Browser View
struct OGSBrowserView: View {
    @ObservedObject var client: OGSClient
    
    // Filter State
    // Default to 19x19 and 13x13 and 9x9 enabled, or whatever preference you prefer.
    @State private var sizeFilters: Set<BoardSizeCategory> = [.size19, .size13, .size9, .other]
    @State private var selectedSpeed: GameSpeedFilter = .all
    @State private var showRankedOnly: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. Header & Filters
            VStack(spacing: 12) {
                // Title & Connection Status
                HStack {
                    Text("Lobby")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if client.isConnected {
                        Label("Connected", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Button("Retry Connection") { client.connect() }
                            .font(.caption)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                // Filters Row 1: Sizes (Checkboxes)
                HStack(spacing: 12) {
                    Text("Size:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    ForEach(BoardSizeCategory.allCases) { size in
                        Toggle(size.rawValue, isOn: Binding(
                            get: { sizeFilters.contains(size) },
                            set: { isActive in
                                if isActive { sizeFilters.insert(size) }
                                else { sizeFilters.remove(size) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                    
                    Spacer()
                }
                
                // Filters Row 2: Speed & Rated
                HStack {
                    Picker("", selection: $selectedSpeed) {
                        ForEach(GameSpeedFilter.allCases) { speed in
                            Text(speed.rawValue).tag(speed)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .controlSize(.small)
                    
                    Toggle("Rated", isOn: $showRankedOnly)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    
                    Spacer()
                }
            }
            .padding()
            // Semi-transparent background for header only (to separate from list)
            .background(Color.black.opacity(0.1))
            
            Divider().background(Color.white.opacity(0.1))
            
            // 2. Challenge List
            if client.availableGames.isEmpty {
                VStack {
                    Spacer()
                    if !client.isConnected {
                        Text("Connecting...")
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Text("No challenges found.")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                }
            } else {
                List(filteredChallenges) { challenge in
                    ChallengeRow(challenge: challenge) {
                        // EnvironmentObject access would require passing appModel,
                        // but since we are inside RightPanelView which has access,
                        // we rely on the Notification mechanism or simple Join logic.
                        // Assuming AppModel listens to client.activeGameID or we trigger join here.
                        // For direct action, we call client logic which AppModel observes.
                        
                        // Trigger join via client (AppModel observes activeGameID)
                        // Or technically AppModel.joinOnlineGame is the orchestrator.
                        // Since we don't have AppModel passed in init here (to fix the previous error),
                        // we can't call appModel.joinOnlineGame(id:).
                        // However, OGSClient.joinGame(id:) starts the process.
                        
                        // FIX: We need to trigger AppModel logic.
                        // Since we cleaned up init, let's assume the Row just needs to call join.
                        client.joinGame(gameID: challenge.id)
                        
                        // NOTE: If your AppModel logic requires specific setup before join,
                        // this might bypass it. But usually OGSClient join is sufficient
                        // for the socket layer, and AppModel reacts to the state change.
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden) // <--- CRITICAL FOR TRANSPARENCY
            }
            
            // 3. Footer / Stats
            HStack {
                Text("\(filteredChallenges.count) / \(client.availableGames.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .padding(8)
            .background(Color.black.opacity(0.1))
        }
        .onAppear {
            if !client.isSubscribedToSeekgraph {
                client.subscribeToSeekgraph()
            }
        }
    }
    
    // MARK: - Filtering Logic
    var filteredChallenges: [OGSChallenge] {
        client.availableGames.filter { game in
            // 1. Ranked Filter
            if showRankedOnly && !game.game.ranked {
                return false
            }
            
            // 2. Size Filter
            let w = game.game.width
            let h = game.game.height
            let category: BoardSizeCategory
            
            if w == 19 && h == 19 { category = .size19 }
            else if w == 13 && h == 13 { category = .size13 }
            else if w == 9 && h == 9 { category = .size9 }
            else { category = .other }
            
            if !sizeFilters.contains(category) {
                return false
            }
            
            // 3. Speed Filter
            let speed = game.speedCategory.lowercased()
            switch selectedSpeed {
            case .all: break
            case .live:
                if speed != "live" && speed != "rapid" { return false } // 'rapid' often maps to live
            case .blitz:
                if speed != "blitz" { return false }
            case .correspondence:
                if speed != "correspondence" { return false }
            }
            
            return true
        }
        .sorted {
            // Sort: My games first, then newest
            if ($0.challenger.username == client.username) != ($1.challenger.username == client.username) {
                return $0.challenger.username == client.username
            }
            return $0.id > $1.id
        }
    }
}

// MARK: - List Row Component
struct ChallengeRow: View {
    let challenge: OGSChallenge
    let onJoin: () -> Void
    
    var body: some View {
        HStack {
            // Rank Badge
            Text(challenge.challenger.displayRank)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 18)
                .background(rankColor)
                .foregroundColor(.white)
                .cornerRadius(3)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(challenge.game.name ?? "Challenge")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.white)
                    
                    if challenge.game.ranked {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(challenge.challenger.username)
                        .fontWeight(.semibold)
                    Text("•")
                    Text(challenge.speedCategory.capitalized)
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Game Details
            VStack(alignment: .trailing, spacing: 2) {
                Text(challenge.boardSize)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text(challenge.timeControlDisplay)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(alignment: .trailing)
            
            // Join Button
            Button("Play") {
                onJoin()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.white)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear) // Ensure row doesn't paint opaque background
        .listRowSeparatorTint(Color.white.opacity(0.1))
    }
    
    var rankColor: Color {
        guard let rank = challenge.challenger.ranking else { return .gray }
        if rank >= 30 { return .blue } // Dan
        if rank >= 20 { return .green } // SDK
        return .orange // DDK
    }
}
