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
                ToolbarSoundControl()
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
    @State private var confirmReplaceLocalGame = false
    @State private var replacementSourceID: UUID?
    
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
        .onChange(of: app.mode) { _ in confirmReplaceLocalGame = false; confirmNewGame = false }
        .onChange(of: app.selection?.id) { _ in confirmReplaceLocalGame = false; confirmNewGame = false }
        .confirmationDialog("Replace the current local game?", isPresented: $confirmReplaceLocalGame, titleVisibility: .visible) {
            Button("Replace local game", role: .destructive) {
                guard app.mode == .review, app.selection?.id == replacementSourceID else { return }
                app.copyCurrentBoard(to: .localPlay)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The moves in your current local game will be replaced with this position.")
        }
    }
    
    @ViewBuilder
    private var localTabContent: some View {
        VStack(spacing: 0) {
            Button("Continue this position in Local Play") {
                app.boardVM?.stopAutoPlay()
                if app.hasLocalGameToReplace {
                    replacementSourceID = app.selection?.id
                    confirmReplaceLocalGame = true
                }
                else { app.copyCurrentBoard(to: .localPlay) }
            }
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
                if app.hasLocalGameToReplace { confirmNewGame = true }
                else { app.newLocalGame() }
            }
            Button("Review this game") { app.copyCurrentBoard(to: .review) }
            Text("Pass and playback controls are along the bottom of the board.")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }.padding()
        .confirmationDialog("Start a new local game?", isPresented: $confirmNewGame) {
            Button("New Game", role: .destructive) { if app.mode == .localPlay { app.newLocalGame() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var onlineTabContent: some View {
        VStack {
            if app.ogsClient.activeGameID != nil {
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


/// Global audio belongs beside the account controls, not among board gestures.
struct ToolbarSoundControl: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showVolume = false

    var body: some View {
        SoundButton(isSilent: settings.soundIsSilent, volume: settings.masterVolume,
                    onClick: { settings.toggleSound() }, onHold: { showVolume = true })
            .frame(width: 28, height: 28)
            .popover(isPresented: $showVolume, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sound").font(.headline)
                        Spacer()
                        Text(settings.isMuted ? "Muted" : "\(Int((settings.masterVolume * 100).rounded()))%")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: Binding(get: { settings.masterVolume }, set: {
                            settings.masterVolume = $0
                            if $0 > 0 { settings.isMuted = false }
                        }), in: 0...1)
                        .accessibilityLabel("Master volume")
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    Button(settings.soundIsSilent ? "Unmute" : "Mute") { settings.toggleSound() }
                }.padding(16).frame(width: 240)
            }
    }
}

/// Keep native button accessibility/keyboard behavior. A hold opens the popover
/// and suppresses the click on release, so adjusting volume never toggles mute.
struct SoundButton: NSViewRepresentable {
    let isSilent: Bool
    let volume: Double
    var onClick: () -> Void
    var onHold: () -> Void

    final class Coordinator: NSObject {
        var onClick: () -> Void = {}
        @objc func click() { onClick() }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SoundHoldButton {
        let button = SoundHoldButton()
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.click)
        button.setAccessibilityIdentifier("sound-control")
        return button
    }
    func updateNSView(_ button: SoundHoldButton, context: Context) {
        context.coordinator.onClick = onClick
        button.onHold = onHold
        let symbol = isSilent ? "speaker.slash.fill" : (volume < 0.4 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
        let label = isSilent ? "Unmute sound" : "Mute sound"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.setAccessibilityLabel(label)
        button.toolTip = "\(label). Hold or right-click to adjust volume."
    }
    static func dismantleNSView(_ button: SoundHoldButton, coordinator: Coordinator) {
        button.onHold = nil
        button.target = nil
    }
}

final class SoundHoldButton: NSButton {
    var onHold: (() -> Void)?
    private var held = false

    override func mouseDown(with event: NSEvent) {
        held = false
        let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.held = true
            self.highlight(false)
            self.onHold?()
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate(); held = false }
        super.mouseDown(with: event)
    }
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        guard !held else { return false }
        return super.sendAction(action, to: target)
    }
    override func rightMouseDown(with event: NSEvent) { onHold?() }
}
