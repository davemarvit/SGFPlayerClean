// MARK: - File: RightPanelView.swift (v8.100)
import SwiftUI

struct RightPanelView: View {
    @EnvironmentObject var app: AppModel
    @State private var selectedTab: RightPanelTab = .local
    enum RightPanelTab: String { case local = "Local", online = "Online" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedTab) {
                Text("Local").tag(RightPanelTab.local)
                Text("Online").tag(RightPanelTab.online)
            }.pickerStyle(.segmented).padding(10)
            Divider().background(Color.white.opacity(0.1))
            ZStack {
                if selectedTab == .local {
                    VStack(spacing: 0) {
                        if let game = app.selection, let bvm = app.boardVM {
                            LocalGameMetadataView(game: game, boardVM: bvm)
                            Divider().background(Color.white.opacity(0.1))
                        }
                        LocalPlaylistView()
                    }
                } else { onlineTabContent }
            }
        }.frostedGlassStyle()
    }
    private var onlineTabContent: some View {
        Group {
            if app.ogsClient.activeGameID != nil && app.ogsClient.isConnected {
                ActiveGamePanel().transition(.opacity)
            } else {
                OGSBrowserView(isPresentingCreate: $app.isCreatingChallenge) { id in app.joinOnlineGame(id: id) }.transition(.opacity)
            }
        }
    }
}

struct LocalGameMetadataView: View {
    let game: SGFGameWrapper; @ObservedObject var boardVM: BoardViewModel
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(game.game.info.playerBlack ?? "Black", systemImage: "circle.fill").font(.headline)
                    Text("\(boardVM.blackCapturedCount) prisoners").font(.caption).foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label(game.game.info.playerWhite ?? "White", systemImage: "circle").font(.headline)
                    Text("\(boardVM.whiteCapturedCount) prisoners").font(.caption).foregroundColor(.white.opacity(0.7))
                }
            }
        }.padding().background(Color.black.opacity(0.1))
    }
}

struct LocalPlaylistView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        VStack(spacing: 0) {
            if app.games.isEmpty {
                Spacer(); Text("No SGF files loaded").foregroundColor(.secondary); Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(app.games) { game in
                            Button(action: { app.selectGame(game) }) { LocalGameRow(game: game, isSelected: app.selection?.id == game.id) }.buttonStyle(.plain)
                            Divider().background(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        }
    }
}

struct LocalGameRow: View {
    let game: SGFGameWrapper; let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if isSelected { Image(systemName: "play.fill").font(.caption2).foregroundColor(.cyan) }
                Text(game.game.info.playerBlack ?? "?").fontWeight(.bold) + Text(" vs ") + Text(game.game.info.playerWhite ?? "?").fontWeight(.bold)
                Spacer()
            }.font(.caption).foregroundColor(isSelected ? .cyan : .white)
            HStack {
                Text(game.game.info.date ?? "Unknown Date").font(.caption2).foregroundColor(.gray)
                Spacer()
                if let result = game.game.info.result { Text(result).font(.caption).bold().foregroundColor(.yellow) }
            }
        }.padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle()).background(isSelected ? Color.white.opacity(0.15) : Color.clear)
    }
}
