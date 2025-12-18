//
//  RightPanelView.swift
//  SGFPlayerClean
//
//  v3.108: Wiring Challenge Creation.
//  - Pass $app.isCreatingChallenge to OGSBrowserView.
//

import SwiftUI

enum RightPanelTab: String, CaseIterable {
    case local = "Local"
    case online = "Online"
}

struct RightPanelView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var boardVM: BoardViewModel
    
    @State private var selectedTab: RightPanelTab = .online
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. TOP TOGGLE
            Picker("Mode", selection: $selectedTab) {
                Text("Local").tag(RightPanelTab.local)
                Text("Online").tag(RightPanelTab.online)
            }
            .pickerStyle(.segmented)
            .padding(10)
            .background(Color.black.opacity(0.1))
            
            Divider().background(Color.white.opacity(0.1))
            
            // 2. CONTENT AREA
            ZStack {
                if selectedTab == .local {
                    VStack(spacing: 0) {
                        // Fixed Metadata Panel at the top
                        if let game = app.selection {
                            LocalGameMetadataView(game: game, boardVM: boardVM)
                                .transition(.opacity)
                            
                            Divider().background(Color.white.opacity(0.1))
                        }
                        
                        // Scrollable Playlist
                        LocalPlaylistView(app: app)
                    }
                    .transition(.move(edge: .leading))
                    
                } else {
                    // ONLINE: Auto-switch between Lobby and Active Game
                    if app.ogsClient.activeGameID != nil && app.ogsClient.isConnected {
                        ActiveGamePanel(appModel: app)
                            .transition(.opacity)
                    } else {
                        // v3.108 FIX: Pass binding for creation sheet
                        OGSBrowserView(client: app.ogsClient, isPresentingCreate: $app.isCreatingChallenge)
                            .transition(.opacity)
                    }
                }
            }
        }
        .frostedGlassStyle()
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .animation(.easeInOut(duration: 0.2), value: app.ogsClient.activeGameID)
        .animation(.easeInOut(duration: 0.2), value: app.selection?.id)
    }
}

// ... [Keep LocalGameMetadataView, LocalPlaylistView, LocalGameRow unchanged] ...
// (Omitted for brevity as they are identical to v3.107)

// MARK: - Local Metadata View
struct LocalGameMetadataView: View {
    let game: SGFGameWrapper
    @ObservedObject var boardVM: BoardViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(game.game.info.playerBlack ?? "Black", systemImage: "circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .imageScale(.small)
                    Text("\(boardVM.whiteCapturedCount) prisoners")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label(game.game.info.playerWhite ?? "White", systemImage: "circle")
                        .font(.headline)
                        .foregroundColor(.white)
                        .imageScale(.small)
                    Text("\(boardVM.blackCapturedCount) prisoners")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Divider().background(Color.white.opacity(0.1))
            HStack {
                if let result = game.game.info.result, !result.isEmpty {
                    Text(result).font(.callout.bold()).foregroundColor(.yellow)
                } else {
                    Text("In Progress").font(.caption).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                if let date = game.game.info.date {
                    Text(date).font(.caption).foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.1))
    }
}

struct LocalPlaylistView: View {
    @ObservedObject var app: AppModel
    var body: some View {
        VStack(spacing: 0) {
            if app.games.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark").font(.largeTitle).foregroundColor(.white.opacity(0.3))
                    Text("No SGF files loaded").foregroundColor(.secondary)
                    Button("Open Folder...") { app.promptForFolder() }
                        .buttonStyle(.borderedProminent).tint(.white.opacity(0.1))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(app.games) { game in
                            Button(action: { app.selectGame(game) }) {
                                LocalGameRow(game: game, isSelected: app.selection?.id == game.id)
                            }
                            .buttonStyle(.plain)
                            Divider().background(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        }
    }
}

struct LocalGameRow: View {
    let game: SGFGameWrapper
    let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if isSelected { Image(systemName: "play.fill").font(.caption2).foregroundColor(.cyan) }
                Text(game.game.info.playerBlack ?? "?").fontWeight(.bold) + Text(" vs ") + Text(game.game.info.playerWhite ?? "?").fontWeight(.bold)
                Spacer()
            }
            .font(.caption).foregroundColor(isSelected ? .cyan : .white)
            HStack {
                Text(game.game.info.date ?? "Unknown Date").font(.caption2).foregroundColor(.gray)
                Spacer()
                if let result = game.game.info.result { Text(result).font(.caption).bold().foregroundColor(.yellow) }
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle())
        .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
    }
}
