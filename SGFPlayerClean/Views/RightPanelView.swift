// MARK: - File: RightPanelView.swift (v8.102)
import SwiftUI

struct RightPanelView: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $app.rightPanelTab) {
                Text("Local").tag(AppModel.PanelTab.local)
                Text("Online").tag(AppModel.PanelTab.online)
            }.pickerStyle(.segmented).padding(10)
            
            Divider().background(Color.white.opacity(0.1))
            
            ZStack {
                if app.rightPanelTab == .local {
                    VStack(spacing: 0) {
                        if let game = app.selection, let bvm = app.boardVM {
                            LocalGameMetadataView(game: game, boardVM: bvm)
                            // Divider().background(Color.white.opacity(0.1)) // No longer needed
                        } else {
                            Text("No Game Selected")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                                .padding()
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top) // Align to top
                } else {
                    onlineTabContent
                }
            }
        }.frostedGlassStyle()
    }
    
    @ViewBuilder
    private var onlineTabContent: some View {
        VStack {
            if app.ogsClient.activeGameID != nil && app.ogsClient.isConnected {
                ActiveGamePanel().transition(.opacity)
            } else {
                OGSBrowserView(isPresentingCreate: $app.isCreatingChallenge) { id in
                    app.joinOnlineGame(id: id)
                }.transition(.opacity)
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
                    HStack { Text("B").bold(); Text(game.game.info.playerBlack ?? "Black") }.font(.headline)
                    Text("\(boardVM.blackCapturedCount) prisoners").font(.caption).foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack { Text(game.game.info.playerWhite ?? "White"); Text("W").bold() }.font(.headline)
                    Text("\(boardVM.whiteCapturedCount) prisoners").font(.caption).foregroundColor(.white.opacity(0.7))
                }
            }

            Divider().background(Color.white.opacity(0.1))
            
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Date").font(.caption).foregroundColor(.white.opacity(0.5))
                    Text(game.game.info.date ?? "-").font(.callout)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Result").font(.caption).foregroundColor(.white.opacity(0.5))
                    Text(game.game.info.result ?? "-").font(.callout).bold().foregroundColor(.yellow)
                }
            }
        }.padding().background(Color.black.opacity(0.1))
    }
}

// LocalPlaylistView and LocalGameRow Removed

