// MARK: - File: RightPanelView.swift (v8.102)
import SwiftUI

/// Activity, analysis, and account controls have independent responsibilities.
struct AppModeControls: View {
    @EnvironmentObject var app: AppModel
    @State private var showGames = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                AppModeSelector(selection: app.mode) { mode in
                    if mode == .review {
                        // Capture the board before changing modes, which otherwise
                        // restores a different, previously reviewed game.
                        if app.mode != .review, app.selection != nil || app.boardVM?.isOnlineContext == true || app.player.maxIndex > 0 {
                            app.copyCurrentBoard(to: .review)
                        } else {
                            app.mode = .review
                            if app.selection == nil && app.player.maxIndex == 0 { app.showRightPanel = true }
                        }
                    } else {
                        app.mode = mode
                    }
                    if mode == .observe { showGames = true }
                }.frame(width: 400)
                Toggle("AI analysis", isOn: Binding(get: { app.isAIAvailable }, set: { app.aiAnalysisEnabled = $0 }))
                    .disabled(app.aiUnavailableReason != nil)
                    .help(app.aiUnavailableReason ?? "Show KataGo analysis for this board")
                if app.mode == .review {
                    Button("Choose game…") {
                        app.closePostGameChat()
                        app.showRightPanel = true
                    }
                    .help("Choose a game from your collection or load an SGF game or folder")
                }
                Spacer(minLength: 0)
                ToolbarSoundControl()
                #if !SGF_OFFLINE_REVIEW
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.ogsClient.username ?? "Not signed in").interfaceFont(.caption).bold()
                    if app.ogsClient.isAuthenticated && !app.ogsClient.isSocketAuthenticated {
                        Button("Reconnect") { app.ogsClient.disconnect(); app.ogsClient.connect() }
                            .interfaceFont(.caption2)
                            .help(app.ogsClient.connectionStatus)
                            .accessibilityIdentifier("account-reconnect")
                    } else {
                        Text(app.ogsClient.isSocketAuthenticated ? "Connected" : app.ogsClient.connectionStatus)
                            .interfaceFont(.caption2).foregroundColor(.secondary)
                    }
                }
                if app.ogsClient.isAuthenticated {
                    Button("Log Out") { app.ogsClient.logout() }
                }
                #endif
            }
            if app.mode == .review, let status = app.backgroundReviewStatus {
                Text(status).interfaceFont(.caption).foregroundColor(.secondary)
            }
            if app.aiAnalysisEnabled, let reason = app.aiUnavailableReason {
                Text(reason).interfaceFont(.caption).foregroundColor(.secondary)
            }
        }.padding(8)
        .sheet(isPresented: $showGames) {
            OGSObservationBrowserView(didObserve: { showGames = false }, onCancel: { showGames = false })
                .environmentObject(app).frame(width: 560, height: 620)
        }
    }
}

/// Keep native segments, but also deliver clicks on the already-selected mode.
/// A Picker only reports selection changes, so it cannot reopen Observe's browser.
private struct AppModeSelector: NSViewRepresentable {
    let selection: AppMode
    let onSelect: (AppMode) -> Void

    private var modes: [AppMode] {
        #if SGF_OFFLINE_REVIEW
        AppMode.allCases.filter { !$0.usesOGS }
        #else
        AppMode.allCases
        #endif
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, modes: modes) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: modes.map(\.rawValue), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.selectMode(_:)))
        control.segmentStyle = .rounded
        control.setAccessibilityLabel("Mode")
        for index in modes.indices { control.setWidth(96, forSegment: index) }
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onSelect = onSelect
        control.selectedSegment = modes.firstIndex(of: selection) ?? -1
    }

    final class Coordinator: NSObject {
        var onSelect: (AppMode) -> Void
        let modes: [AppMode]
        init(onSelect: @escaping (AppMode) -> Void, modes: [AppMode]) {
            self.onSelect = onSelect
            self.modes = modes
        }
        @objc func selectMode(_ control: NSSegmentedControl) {
            guard modes.indices.contains(control.selectedSegment) else { return }
            onSelect(modes[control.selectedSegment])
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
                Text(app.mode == .observe && app.ogsClient.activeGameID == nil ? "Select a Game" : app.mode.rawValue)
                    .interfaceFont(.headline)
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
            VStack(alignment: .leading, spacing: 8) {
                Button(action: { app.promptForSGFs() }) {
                    Image(systemName: "folder.badge.plus")
                    Text("Load SGFs")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open a single SGF game or an entire folder")

                Picker("Sort by", selection: $app.gameSortMethod) {
                    ForEach(AppModel.GameSortMethod.allCases, id: \.self) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .accessibilityIdentifier("game-library-sort")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().background(Color.white.opacity(0.1))
            
            // Metadata for current selection
            if let game = app.selection, let bvm = app.boardVM {
                ScrollView { LocalGameMetadataView(game: game, boardVM: bvm) }
                    .frame(maxHeight: 360)
                Divider().background(Color.white.opacity(0.1))
            } 
            
            // The Scrollable Library List
            if !app.sortedGames.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(app.sortedGames) { wrapper in
                            Button(action: {
                                app.selectGame(wrapper)
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
                    .interfaceFont(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    @State private var confirmNewGame = false
    private var localPlayContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Play both sides on this board.").interfaceFont(.caption)
                if let game = app.selection, let vm = app.boardVM {
                    LocalGameMetadataView(game: game, boardVM: vm)
                }
                Button("New Game") {
                    if app.hasLocalGameToReplace { confirmNewGame = true }
                    else { app.newLocalGame() }
                }
                Button("Review this game") { app.copyCurrentBoard(to: .review) }
                Text("Pass and playback controls are along the bottom of the board.")
                    .interfaceFont(.caption).foregroundColor(.secondary)
                Spacer()
            }.padding()
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    OGSObservationBrowserView(showsTitle: false)
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
        Group {
            if isOverlay { compactMetadata }
            else { sidebarMetadata }
        }
    }

    private var compactMetadata: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text("B").bold(); Text(game.game.info.playerBlack ?? "Black") }.interfaceFont(.headline)
                    Text("\(boardVM.blackCapturedCount) prisoners").interfaceFont(.caption).foregroundColor(.white.opacity(0.7))
                }
                VStack(alignment: .trailing, spacing: 2) {
                    HStack { Text(game.game.info.playerWhite ?? "White"); Text("W").bold() }.interfaceFont(.headline)
                    Text("\(boardVM.whiteCapturedCount) prisoners").interfaceFont(.caption).foregroundColor(.white.opacity(0.7))
                }
            }

            Divider().background(Color.white.opacity(0.1))
            
            HStack(alignment: .top, spacing: 16) {
                HStack(spacing: 6) {
                    Text("Date:").interfaceFont(.caption).foregroundColor(.white.opacity(0.5))
                    Text(game.game.info.date ?? "-").interfaceFont(.callout)
                }
                HStack(spacing: 6) {
                    Text("Result:").interfaceFont(.caption).foregroundColor(.white.opacity(0.5))
                    Text(game.game.info.result ?? "-").interfaceFont(.callout).bold().foregroundColor(.yellow)
                }
            }
            
            if boardVM.isAIAllowed?() == true && boardVM.usesAdaptiveAnalysis?() != true && boardVM.aiAnalysisProgress > 0.0 && boardVM.aiAnalysisProgress < 1.0 {
                ProgressView(value: boardVM.aiAnalysisProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        }.padding(12).background(isOverlay ? Color.black.opacity(0.4) : Color.black.opacity(0.1)).cornerRadius(isOverlay ? 8 : 0)
    }

    private var sidebarMetadata: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Game information").interfaceFont(.headline)
            playerRow(color: .black, name: game.game.info.playerBlack, rank: game.game.info.blackRank,
                      captures: boardVM.blackCapturedCount)
            playerRow(color: .white, name: game.game.info.playerWhite, rank: game.game.info.whiteRank,
                      captures: boardVM.whiteCapturedCount)
            Divider()
            VStack(spacing: 8) {
                detail("Move", "\(boardVM.currentMoveIndex) of \(boardVM.totalMoves)")
                detail("To play", boardVM.engine.turn == .black ? "Black" : "White")
                detail("Board", "\(boardVM.boardSize) × \(boardVM.boardSize)")
                detail("Rules", game.game.info.rules)
                detail("Komi", game.game.info.komi)
                if game.game.handicap > 0 { detail("Handicap", String(game.game.handicap)) }
                detail("Event", game.game.info.event)
                detail("Date", game.game.info.date)
                detail("Result", game.game.info.result)
                // Preserve useful imported SGF metadata without exposing file
                // paths or internal property codes to the player.
                if let props = game.game.sourceTree?.mainLineNodes.first?.props {
                    detail("Game", props["GN"]?.first)
                    detail("Place", props["PC"]?.first)
                    detail("Round", props["RO"]?.first)
                    if let seconds = props["TM"]?.first, let duration = Double(seconds), duration > 0 {
                        detail("Main time", "\(String(format: "%g", duration / 60)) min")
                    }
                    detail("Overtime", props["OT"]?.first)
                }
            }
            if boardVM.isAIAllowed?() == true && boardVM.usesAdaptiveAnalysis?() != true
                && boardVM.aiAnalysisProgress > 0 && boardVM.aiAnalysisProgress < 1 {
                ProgressView(value: boardVM.aiAnalysisProgress).tint(.blue)
                    .accessibilityLabel("Game analysis progress")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("sidebar-game-information")
    }

    private func playerRow(color: Stone, name: String?, rank: String?, captures: Int) -> some View {
        let side = color == .black ? "Black" : "White"
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(color == .black ? Color.black : Color.white)
                .overlay(Circle().stroke(.gray, lineWidth: 1))
                .frame(width: 16, height: 16).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name.flatMap { $0.isEmpty ? nil : $0 } ?? side).interfaceFont(.subheadline, weight: .bold)
                    .fixedSize(horizontal: false, vertical: true)
                if let rank, !rank.isEmpty { Text(rank).interfaceFont(.caption).foregroundStyle(.secondary) }
                Text("Captured: \(captures)").interfaceFont(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sidebar-\(side.lowercased())-captures")
                    .accessibilityLabel("\(side) captured \(captures) stones")
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(value).multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }.interfaceFont(.caption)
        }
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
                        Text("Sound").interfaceFont(.headline)
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
