// MARK: - File: RightPanelView.swift (v8.102)
import SwiftUI

struct RightPanelView: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Mode", selection: $app.rightPanelTab) {
                    Text("Local").tag(AppModel.PanelTab.local)
                    Text("Online").tag(AppModel.PanelTab.online)
                    Text("AI").tag(AppModel.PanelTab.ai)
                }.pickerStyle(.segmented)
                
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
                if app.rightPanelTab == .local {
                    localTabContent
                } else if app.rightPanelTab == .online {
                    onlineTabContent
                } else if app.rightPanelTab == .ai {
                    aiTabContent
                }
            }
        }.frostedGlassStyle()
    }
    
    @ViewBuilder
    private var localTabContent: some View {
        VStack(spacing: 0) {
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
                                // Delayed Auto-Play
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    app.boardVM?.startAutoPlay()
                                }
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
    
    @ViewBuilder
    private var aiTabContent: some View {
        VStack(spacing: 20) {
            Text("AI Analysis")
                .font(.headline)
            
            if app.isAIAvailable {
                Text("KataGo engine is active for this game.")
                    .font(.caption)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
            } else {
                Text("AI is disabled during live online matches.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    private var onlineTabContent: some View {
        VStack {
            if (app.ogsClient.activeGameID != nil && app.ogsClient.isConnected) || app.ogsClient.activeGameID == 999999 {
                ActiveGamePanel().transition(.opacity)
            } else if app.isCreatingChallenge {
                OGSCreateChallengeView(isPresented: $app.isCreatingChallenge).transition(.opacity)
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

