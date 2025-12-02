//
//  ContentView2D.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Main container for 2D board view
//
//  ARCHITECTURE:
//  - Uses BoardViewModel and LayoutViewModel (dependency injection)
//  - 70% left panel (board) / 30% right panel (metadata + chat)
//  - GeometryReader stays here (not extracted to subcomponent)
//  - Pure UI (no business logic)
//

import SwiftUI

struct ContentView2D: View {

    // MARK: - Dependencies

    /// App-wide state (from old AppModel)
    // REMOVED TO TEST: @EnvironmentObject var app: AppModel
    @StateObject var app: AppModel

    /// Board state management
    @StateObject var boardVM: BoardViewModel

    /// Layout calculations
    @StateObject var layoutVM = LayoutViewModel()

    // MARK: - UI State

    /// Settings panel open/closed
    @State private var showSettings = false

    /// Buttons visible (fade out after inactivity)
    @State private var buttonsVisible = true

    /// Button fade timer
    @State private var fadeTimer: Timer?

    /// Window size (local copy to avoid reading layoutVM in body)
    @State private var windowSize: CGSize = .zero

    // MARK: - Initialization

    init() {
        // Create AppModel and BoardViewModel locally - NO EnvironmentObject!
        let model = AppModel()
        _app = StateObject(wrappedValue: model)
        _boardVM = StateObject(wrappedValue: BoardViewModel(player: model.player))
        print("✅ ContentView2D init: Created AppModel and BoardVM locally")
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                // Main content
                mainContent
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .onChange(of: geometry.size) { newSize in
                // Update layout when window size changes
                // Using .onChange prevents infinite loop
                handleWindowResize(newSize)
            }
            .onAppear {
                // Initial layout calculation
                handleWindowResize(geometry.size)
                onViewAppear()

                // DEBUG: Auto-load a test file if available
                if let testFile = URL(string: "file:///Users/Dave/Personal/Old%20personal/Go/KGS/motida-Heraclitus.sgf") {
                    print("🧪 Auto-loading test file for debugging")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.loadSGFFile(from: testFile)
                    }
                }
            }
            .onDisappear {
                onViewDisappear()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LoadSGFFile"))) { notification in
                print("🔔 Received LoadSGFFile notification")
                if let url = notification.object as? URL {
                    print("🔔 URL from notification: \(url.path)")
                    loadSGFFile(from: url)
                } else {
                    print("⚠️ Notification object is not a URL: \(String(describing: notification.object))")
                }
            }
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            boardVM.previousMove()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            boardVM.nextMove()
            return .handled
        }
        .onKeyPress(.upArrow) {
            boardVM.goToStart()
            return .handled
        }
        .onKeyPress(.downArrow) {
            boardVM.goToEnd()
            return .handled
        }
        .onKeyPress(.space) {
            boardVM.toggleAutoPlay()
            return .handled
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        HStack(spacing: 0) {
            // Left panel (70% - board area)
            leftPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: windowSize.width * 0.7)

            // Right panel (30% - metadata + chat)
            rightPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: windowSize.width * 0.3)
        }
        .overlay(debugOverlay)
        .overlay(settingsOverlay)
        .overlay(topButtonsOverlay)
        .onHover { phase in
            handleMouseMove(phase)
        }
    }

    // DEBUG: Show what's loaded - CENTERED AND HUGE
    private var debugOverlay: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("DEBUG v1.3.3")
                    .font(.title).bold()
                Text("Stones: \(boardVM.stones.count)")
                    .font(.title2)
                Text("Move: \(boardVM.currentMoveIndex)")
                    .font(.title2)
                Text("Game: \(boardVM.currentGame?.title ?? "NONE")")
                    .font(.title2)
                Text("Board size: \(boardVM.boardSize)")
                    .font(.title2)
                Text("Window: \(Int(windowSize.width))x\(Int(windowSize.height))")
                    .font(.title2)
            }
            .padding(30)
            .background(Color.yellow)
            .foregroundColor(.black)
            .cornerRadius(12)
            .shadow(radius: 20)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Left Panel (Board Area)

    private var leftPanel: some View {
        ZStack {
            // Tatami background
            TatamiBackground()

            // Board (grid + stones)
            BoardView2D(
                boardVM: boardVM,
                layoutVM: layoutVM
            )

            // Bowls (captured stones)
            BowlsView(
                boardVM: boardVM,
                layoutVM: layoutVM
            )

            // Playback controls (bottom center, aligned with board)
            VStack {
                Spacer()

                PlaybackControls(
                    boardVM: boardVM
                )
                // FIXED: Don't use layoutVM.windowSize in body - causes infinite loop!
                // .offset(x: layoutVM.boardCenterX - (layoutVM.windowSize.width * 0.7 / 2))
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Right Panel (Metadata + Chat)

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // DEBUG INFO - v1.3.4
            VStack(alignment: .leading, spacing: 5) {
                Text("DEBUG v1.3.4").font(.title).bold()
                Text("Stones: \(boardVM.stones.count)")
                Text("Move: \(boardVM.currentMoveIndex)")
                Text("Game: \(boardVM.currentGame?.title ?? "NONE")")
                Text("Size: \(boardVM.boardSize)")
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color.yellow)
            .foregroundColor(.black)

            // Game info card
            GameInfoCard(
                boardVM: boardVM,
                ogsVM: app.ogsGame // From AppModel
            )
            .padding(.top, 20)
            .padding(.horizontal, 10)

            // Chat panel (Phase 4)
            // ChatPanel(ogsVM: app.ogsGame)
            //     .padding(.horizontal, 10)

            Spacer()

            // OGS controls (Pass/Undo/Resign) - Phase 3
            // OGSControlsPanel(ogsVM: app.ogsGame)
            //     .padding(.bottom, 20)
        }
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Overlays

    /// Settings panel overlay (slides from left)
    private var settingsOverlay: some View {
        Group {
            if showSettings {
                HStack(spacing: 0) {
                    // Settings panel
                    SettingsPanel(isOpen: $showSettings)
                        .frame(width: 400)
                        .background(Color(NSColor.windowBackgroundColor))
                        .transition(.move(edge: .leading))

                    Spacer()
                }
                .zIndex(100)
            }
        }
    }

    /// Top buttons overlay (settings gear)
    private var topButtonsOverlay: some View {
        VStack {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .imageScale(.large)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)
                .padding(.top, 20)
                .opacity(buttonsVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.3), value: buttonsVisible)

                Spacer()

                // Fullscreen button
                Button {
                    toggleFullscreen()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .imageScale(.medium)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.top, 20)
                .opacity(buttonsVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.3), value: buttonsVisible)
            }

            Spacer()
        }
        .zIndex(50)
    }

    // MARK: - Event Handlers

    private func onViewAppear() {
        // Load first game if available
        if let firstGame = app.games.first {
            boardVM.loadGame(firstGame)
        }

        // Initial layout calculation
        // (GeometryReader will trigger proper calculation)

        // Start button fade timer
        resetFadeTimer()
    }

    private func onViewDisappear() {
        // Stop auto-play
        boardVM.stopAutoPlay()

        // Clean up timer
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    private func handleWindowResize(_ newSize: CGSize) {
        // Only update if size actually changed (prevent infinite loop)
        guard newSize != windowSize else { return }

        // Update local state (used in body to avoid reading layoutVM)
        windowSize = newSize

        // LayoutViewModel handles layout calculations
        layoutVM.handleResize(
            newSize: newSize,
            boardSize: boardVM.boardSize,
            leftPanelWidth: newSize.width * 0.7
        )
    }

    private func handleMouseMove(_ phase: HoverPhase) {
        switch phase {
        case .active:
            // Show buttons on mouse move
            if !buttonsVisible {
                withAnimation(.easeIn(duration: 0.2)) {
                    buttonsVisible = true
                }
            }
            resetFadeTimer()
        case .ended:
            break
        }
    }

    private func resetFadeTimer() {
        fadeTimer?.invalidate()

        fadeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.5)) {
                buttonsVisible = false
            }
        }
    }

    private func toggleFullscreen() {
        NSApplication.shared.keyWindow?.toggleFullScreen(nil)
    }

    private func loadSGFFile(from url: URL) {
        print("🔵 loadSGFFile called with: \(url.path)")

        do {
            let data = try Data(contentsOf: url)
            print("🔵 Data loaded: \(data.count) bytes")

            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            print("🔵 Text decoded: \(text.prefix(100))...")

            let tree = try SGFParser.parse(text: text)
            print("🔵 SGF parsed successfully")

            let game = SGFGame.from(tree: tree)
            print("🔵 Game created: \(game.moves.count) moves")

            let wrapper = SGFGameWrapper(url: url, game: game)
            print("🔵 Wrapper created")

            // Load into BoardViewModel
            boardVM.loadGame(wrapper)
            print("✅ Game loaded into BoardViewModel - \(boardVM.stones.count) stones on board")

            // Store in app model
            if !app.games.contains(where: { $0.url == url }) {
                app.games.append(wrapper)
            }
            app.selection = wrapper
            print("✅ App model updated - total games: \(app.games.count)")

        } catch {
            print("❌ Failed to load SGF: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView2D()
        .frame(width: 1400, height: 900)
}

// MARK: - Placeholder Types for Phase 1
// These will be replaced with real AppModel in Phase 2

/// Minimal AppModel for Phase 1 testing
class AppModel: ObservableObject {
    @Published var games: [SGFGameWrapper] = []
    @Published var player: SGFPlayer = SGFPlayer()
    @Published var ogsGame: OGSGameViewModel? = nil
    @Published var selection: SGFGameWrapper?

    init() {
        print("🚀 APP: AppModel init completed")
    }

    func loadSampleGames(from folderURL: URL) {
        // Load games in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var sgfURLs: [URL] = []

            if let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "sgf" {
                        sgfURLs.append(fileURL)
                    }
                }
            }

            sgfURLs.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            // Limit to 100 games to avoid long loading times
            let limitedURLs = Array(sgfURLs.prefix(100))

            var parsed: [SGFGameWrapper] = []
            for fileURL in limitedURLs {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    let tree = try SGFParser.parse(text: text)
                    let game = SGFGame.from(tree: tree)
                    parsed.append(SGFGameWrapper(url: fileURL, game: game))
                    print("✅ Loaded: \(fileURL.lastPathComponent)")
                } catch {
                    print("❌ Failed to parse \(fileURL.lastPathComponent): \(error)")
                }
            }

            // Update UI on main thread
            DispatchQueue.main.async {
                self.games = parsed
                self.selection = parsed.first
                print("📚 Loaded \(parsed.count) games")
            }
        }
    }
}

/// Placeholder for OGS (Phase 3)
class OGSGameViewModel: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var currentGameID: Int?
    @Published var gamePhase: String = "none"
}
