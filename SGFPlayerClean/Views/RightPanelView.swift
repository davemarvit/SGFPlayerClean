// MARK: - File: RightPanelView.swift (v8.102)
import SwiftUI

/// Activity, analysis, and account controls have independent responsibilities.
struct AppModeControls: View {
    @EnvironmentObject var app: AppModel
    @State private var showGames = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Picker("Mode", selection: $app.mode) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        #if SGF_OFFLINE_REVIEW
                        if !mode.usesOGS { Text(mode.rawValue).tag(mode) }
                        #else
                        Text(mode.rawValue).tag(mode)
                        #endif
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 400)
                Toggle("AI analysis", isOn: Binding(get: { app.isAIAvailable }, set: { app.aiAnalysisEnabled = $0 }))
                    .disabled(app.aiUnavailableReason != nil)
                    .help(app.aiUnavailableReason ?? "Show KataGo analysis for this board")
                if app.mode == .observe {
                    Button("Browse games…") { showGames = true }
                }
                Spacer(minLength: 0)
                #if !SGF_OFFLINE_REVIEW
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.ogsClient.username ?? "Not signed in").font(.caption).bold()
                    Text(app.ogsClient.isSocketAuthenticated ? "Connected" : app.ogsClient.connectionStatus)
                        .font(.caption2).foregroundColor(.secondary)
                }
                if app.ogsClient.isAuthenticated {
                    Button("Log Out") { app.ogsClient.logout() }
                }
                #endif
            }
            if app.aiAnalysisEnabled, let reason = app.aiUnavailableReason {
                Text(reason).font(.caption).foregroundColor(.secondary)
            }
        }.padding(8)
        .sheet(isPresented: $showGames) {
            OGSObservationBrowserView(didObserve: { showGames = false }, onCancel: { showGames = false })
                .environmentObject(app).frame(width: 560, height: 620)
        }
    }
}

struct RightPanelView: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(app.mode.rawValue).font(.headline)
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        app.showRightPanel = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
            .padding(10)
            
            Divider().background(Color.white.opacity(0.1))
            
            ZStack {
                switch app.mode {
                case .review: localTabContent
                case .localPlay: localPlayContent
                case .playOnline, .observe: onlineTabContent
                }
            }
        }.frostedGlassStyle()
    }
    
    @ViewBuilder
    private var localTabContent: some View {
        VStack(spacing: 0) {
            Button("Continue this position in Local Play") { app.copyCurrentBoard(to: .localPlay) }
                .padding(8)
            // Folder Selection & Sorting Header
            HStack {
                Button(action: { app.promptForFolder() }) {
                    Image(systemName: "folder.badge.plus")
                    Text("Load SGFs")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Picker("Sort", selection: $app.gameSortMethod) {
                    ForEach(AppModel.GameSortMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Metadata for current selection
            if let game = app.selection, let bvm = app.boardVM {
                LocalGameMetadataView(game: game, boardVM: bvm)
                Divider().background(Color.white.opacity(0.1))
            } 
            
            // The Scrollable Library List
            if !app.sortedGames.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(app.sortedGames) { wrapper in
                            Button(action: {
                                app.selectGame(wrapper)
                                #if !SGF_OFFLINE_REVIEW
                                // Delayed Auto-Play
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    guard app.mode == .review, app.selection?.id == wrapper.id else { return }
                                    app.boardVM?.startAutoPlay()
                                }
                                #endif
                            }) {
                                GameListRow(wrapper: wrapper, isSelected: app.selection?.id == wrapper.id)
                            }
                            .buttonStyle(.plain)
                            Divider().background(Color.white.opacity(0.1))
                        }
                    }
                }
            } else {
                Spacer()
                Text("No games loaded")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    @State private var confirmNewGame = false
    private var localPlayContent: some View {
        VStack(spacing: 14) {
            Text("Play both sides on this board.").font(.caption)
            if let game = app.selection, let vm = app.boardVM {
                LocalGameMetadataView(game: game, boardVM: vm)
            }
            Button("New Game") {
                if app.player.maxIndex > 0 { confirmNewGame = true }
                else { app.newLocalGame() }
            }
            Button("Review this game") { app.copyCurrentBoard(to: .review) }
            Text("Pass and playback controls are along the bottom of the board.")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }.padding()
        .confirmationDialog("Start a new local game?", isPresented: $confirmNewGame) {
            Button("New Game", role: .destructive) { app.newLocalGame() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var onlineTabContent: some View {
        VStack {
            if (app.ogsClient.activeGameID != nil && app.ogsClient.isConnected) || app.ogsClient.activeGameID == 999999 {
                ActiveGamePanel().transition(.opacity)
            } else if app.isCreatingChallenge {
                OGSCreateChallengeView(isPresented: $app.isCreatingChallenge).transition(.opacity)
            } else {
                if app.mode == .observe {
                    OGSObservationBrowserView()
                } else {
                OGSBrowserView(isPresentingCreate: $app.isCreatingChallenge) { id in
                    app.joinOnlineGame(id: id)
                }.transition(.opacity)
                }
            }
        }
    }
}

struct LocalGameMetadataView: View {
    let game: SGFGameWrapper; @ObservedObject var boardVM: BoardViewModel
    var isOverlay: Bool = false
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text("B").bold(); Text(game.game.info.playerBlack ?? "Black") }.font(.headline)
                    Text("\(boardVM.blackCapturedCount) prisoners").font(.caption).foregroundColor(.white.opacity(0.7))
                }
                VStack(alignment: .trailing, spacing: 2) {
                    HStack { Text(game.game.info.playerWhite ?? "White"); Text("W").bold() }.font(.headline)
                    Text("\(boardVM.whiteCapturedCount) prisoners").font(.caption).foregroundColor(.white.opacity(0.7))
                }
            }

            Divider().background(Color.white.opacity(0.1))
            
            HStack(alignment: .top, spacing: 16) {
                HStack(spacing: 6) {
                    Text("Date:").font(.caption).foregroundColor(.white.opacity(0.5))
                    Text(game.game.info.date ?? "-").font(.callout)
                }
                HStack(spacing: 6) {
                    Text("Result:").font(.caption).foregroundColor(.white.opacity(0.5))
                    Text(game.game.info.result ?? "-").font(.callout).bold().foregroundColor(.yellow)
                }
            }
            
            if boardVM.aiAnalysisProgress > 0.0 && boardVM.aiAnalysisProgress < 1.0 {
                ProgressView(value: boardVM.aiAnalysisProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        }.padding(12).background(isOverlay ? Color.black.opacity(0.4) : Color.black.opacity(0.1)).cornerRadius(isOverlay ? 8 : 0)
    }
}

// LocalPlaylistView and LocalGameRow Removed

