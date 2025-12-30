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

    // MARK: - Layout Configuration

    /// UI element spacing configuration (in cells or pixels)
    private struct Spacing {
        // Lid positioning
        static let lidVerticalSpacing: CGFloat = 30          // Space between upper and lower lids (pixels)
        static let lidToBoard: CGFloat = 1.5                 // Distance from board right edge to lid center (cells)
        static let lowerLidVerticalOffset: CGFloat = 0.2    // Lower lid drops below board edge (fraction of board height)
        static let lowerLidHorizontalOffset: CGFloat = 0.5  // Lower lid shifts right (cells)

        // Metadata positioning
        static let metadataToBoard: CGFloat = 1.5            // Distance from board right edge to metadata left edge (cells)
        static let metadataVerticalOffset: CGFloat = 100    // Distance from board top (pixels)
    }

    // MARK: - Dependencies

    /// App-wide state - FIXED: Use @StateObject instead of @EnvironmentObject
    @StateObject var app: AppModel

    /// Board state management
    @StateObject var boardVM: BoardViewModel

    /// Layout calculations - RE-ENABLED (needed for responsive layout)
    @StateObject var layoutVM = LayoutViewModel()

    // MARK: - UI State

    /// Settings panel open/closed
    @State private var showSettings = false

    /// Buttons visible (fade out after inactivity)
    @State private var buttonsVisible = true

    /// Button fade timer
    @State private var fadeTimer: Timer?

    // MARK: - Initialization

    init() {
        // FIXED: Create AppModel locally to avoid EnvironmentObject init() issue
        let model = AppModel()
        _app = StateObject(wrappedValue: model)
        _boardVM = StateObject(wrappedValue: BoardViewModel(player: model.player))
        print("✅ ContentView2D: Initialized with local AppModel (no EnvironmentObject)")
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - Tatami texture over entire window
                TatamiBackground()

                // Main content (70/30 split)
                mainContent(geometry: geometry)

                // Overlays
                settingsOverlay
                topButtonsOverlay
            }
            .onAppear {
                // Calculate layout with 70% width (leaves space for future 30% right panel)
                layoutVM.calculateLayout(
                    containerSize: geometry.size,
                    boardSize: boardVM.boardSize,
                    leftPanelWidth: geometry.size.width * 0.7
                )
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                handleWindowResize(newSize)
            }
        }
        .onAppear {
            onViewAppear()
        }
        .onDisappear {
            onViewDisappear()
        }
        // Mouse tracking for button fade
        .onContinuousHover { phase in
            handleMouseMove(phase)
        }
        // Listen for file open notifications
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LoadSGFFile"))) { notification in
            print("🔔 Received LoadSGFFile notification")
            if let url = notification.object as? URL {
                print("🔔 URL: \(url.path)")
                loadSGFFile(from: url)
            } else {
                print("⚠️ Notification object is not a URL")
            }
        }
        // Keyboard shortcuts
        .focusable()
        .onKeyPress(.leftArrow, action: {
            print("⌨️ Left arrow pressed")
            boardVM.previousMove()
            return .handled
        })
        .onKeyPress(.rightArrow, action: {
            print("⌨️ Right arrow pressed")
            boardVM.nextMove()
            return .handled
        })
        .onKeyPress(.upArrow, action: {
            print("⌨️ Up arrow pressed")
            boardVM.goToStart()
            return .handled
        })
        .onKeyPress(.downArrow, action: {
            print("⌨️ Down arrow pressed")
            boardVM.goToEnd()
            return .handled
        })
        .onKeyPress(.space, action: {
            print("⌨️ Space pressed")
            boardVM.toggleAutoPlay()
            return .handled
        })
        .onKeyPress(.escape, action: {
            print("⌨️ Escape pressed")
            if NSApplication.shared.keyWindow?.styleMask.contains(.fullScreen) == true {
                NSApplication.shared.keyWindow?.toggleFullScreen(nil)
            }
            return .handled
        })
        .onKeyPress(phases: .down) { press in
            // Handle Shift+Arrow for 10-move jumps
            if press.modifiers.contains(.shift) {
                switch press.key {
                case .leftArrow:
                    print("⌨️ Shift+Left arrow pressed (10 moves)")
                    for _ in 0..<10 {
                        guard boardVM.currentMoveIndex > 0 else { break }
                        boardVM.previousMove()
                    }
                    return .handled
                case .rightArrow:
                    print("⌨️ Shift+Right arrow pressed (10 moves)")
                    for _ in 0..<10 {
                        guard boardVM.currentMoveIndex < boardVM.totalMoves else { break }
                        boardVM.nextMove()
                    }
                    return .handled
                default:
                    return .ignored
                }
            }
            return .ignored
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            // Board (grid + stones) - sized for full window
            BoardView2D(
                boardVM: boardVM,
                layoutVM: layoutVM
            )

            // Captured stones lids (positioned relative to board)
            lidsOverlay

            // Game metadata overlay (translucent, above lids)
            metadataOverlay

            // Playback controls (centered below board)
            PlaybackControls(boardVM: boardVM)
                .position(
                    x: layoutVM.boardCenter.x,
                    y: layoutVM.boardFrame.maxY + ((layoutVM.windowSize.height - layoutVM.boardFrame.maxY) / 2) + 25
                )

            // Version number (bottom right corner for verification)
            Text("v1.0.34")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .position(
                    x: layoutVM.windowSize.width - 30,
                    y: layoutVM.windowSize.height - 15
                )
        }
    }

    // MARK: - Lids Overlay

    private var lidsOverlay: some View {
        let lidDiameter = layoutVM.getLidDiameter(boardSize: boardVM.boardSize)
        let lidRadius = lidDiameter / 2
        let cellWidth = layoutVM.getCellWidth(boardSize: boardVM.boardSize)
        let cellHeight = layoutVM.getCellHeight(boardSize: boardVM.boardSize)
        let boardMaxX = layoutVM.boardFrame.maxX
        let boardMinY = layoutVM.boardFrame.minY
        let boardHeight = layoutVM.boardFrame.height

        // Upper lid: positioned to the right of the board, shifted 0.5 cells left
        // Position center at: board right edge + lid radius + spacing - 0.5 cells
        let upperLidX = boardMaxX + lidRadius + (Spacing.lidToBoard * cellWidth) - (0.5 * cellWidth)
        let upperLidY = boardMinY + lidRadius

        // Lower lid: offset down and to the right relative to upper lid
        let lowerLidX = upperLidX + (Spacing.lowerLidHorizontalOffset * cellWidth)
        // Lower lid is positioned below upper lid + spacing + 1/5 board height offset + 3 cells
        let lowerLidY = upperLidY + lidDiameter + Spacing.lidVerticalSpacing + (boardHeight * Spacing.lowerLidVerticalOffset) + (3 * cellHeight)

        return ZStack {
            // Upper lid (Black's captures - white stones)
            SimpleLidView(
                stoneColor: .white,
                stoneCount: boardVM.blackCapturedCount,
                stoneSize: layoutVM.getWhiteStoneSize(boardSize: boardVM.boardSize),
                lidNumber: 1,
                lidSize: lidDiameter
            )
            .position(x: upperLidX, y: upperLidY)

            // Lower lid (White's captures - black stones)
            SimpleLidView(
                stoneColor: .black,
                stoneCount: boardVM.whiteCapturedCount,
                stoneSize: layoutVM.getBlackStoneSize(boardSize: boardVM.boardSize),
                lidNumber: 2,
                lidSize: lidDiameter
            )
            .position(x: lowerLidX, y: lowerLidY)
        }
    }

    // MARK: - Metadata Overlay

    private var metadataOverlay: some View {
        let cellWidth = layoutVM.getCellWidth(boardSize: boardVM.boardSize)
        let boardMaxX = layoutVM.boardFrame.maxX
        let boardMinY = layoutVM.boardFrame.minY

        // Position metadata to the right of board with 1.5 cell spacing
        let metadataX = boardMaxX + (Spacing.metadataToBoard * cellWidth)

        return GameInfoCard(
            boardVM: boardVM,
            ogsVM: app.ogsGame
        )
        .frame(width: 280) // Fixed narrower width
        .position(
            x: metadataX + 140, // Center it (half of 280)
            y: boardMinY + Spacing.metadataVerticalOffset
        )
    }

    // MARK: - Overlays

    /// Settings panel overlay (slides from left)
    private var settingsOverlay: some View {
        Group {
            if showSettings {
                ZStack(alignment: .leading) {
                    // Transparent background (click to close)
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showSettings = false
                            }
                        }

                    // Settings panel
                    SettingsPanel(isOpen: $showSettings, app: app)
                        .transition(.move(edge: .leading))
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
        // Start button fade timer
        resetFadeTimer()
    }

    /// Load SGF file from file picker
    private func loadSGFFile(from url: URL) {
        print("🔵 loadSGFFile called with: \(url.path)")
        do {
            print("🔵 Reading file data...")
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)

            print("🔵 Parsing SGF text (\(text.count) chars)...")
            let tree = try SGFParser.parse(text: text)
            let game = SGFGame.from(tree: tree)
            let wrapper = SGFGameWrapper(url: url, game: game)

            print("✅ Parsed successfully. Loading into BoardViewModel...")
            print("   Title: \(wrapper.title ?? "Untitled")")
            print("   Board size: \(game.boardSize)")
            print("   Total moves: \(game.moves.count)")

            boardVM.loadGame(wrapper)
            print("✅ Game loaded into BoardViewModel")
        } catch {
            print("❌ Failed to load SGF: \(error)")
        }
    }

    private func loadHardcodedTestGame() {
        // Load first SGF from Cho Chikun folder
        let folderPath = "/Users/Dave/Go/Pro games/Cho_Chikun"
        let folderURL = URL(fileURLWithPath: folderPath)

        guard let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            print("❌ Could not access folder: \(folderPath)")
            return
        }

        // Find first SGF file
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "sgf" {
                print("📂 Loading SGF file: \(fileURL.lastPathComponent)")
                do {
                    let data = try Data(contentsOf: fileURL)
                    let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    let tree = try SGFParser.parse(text: text)
                    let game = SGFGame.from(tree: tree)
                    let wrapper = SGFGameWrapper(url: fileURL, game: game)

                    print("✅ Loaded game: \(wrapper.title ?? "Untitled")")
                    print("   Board size: \(game.boardSize)")
                    print("   Handicap stones: \(game.setup.count)")
                    print("   Total moves: \(game.moves.count)")

                    boardVM.loadGame(wrapper)
                    return
                } catch {
                    print("❌ Failed to parse \(fileURL.lastPathComponent): \(error)")
                }
            }
        }

        print("⚠️ No SGF files found in \(folderPath)")
    }

    private func onViewDisappear() {
        // Stop auto-play
        boardVM.stopAutoPlay()

        // Clean up timer
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    private func handleWindowResize(_ newSize: CGSize) {
        // LayoutViewModel handles this (70% width for future 30% right panel)
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
        // TODO: Reference old UIStateViewModel.toggleFullscreen()
        NSApplication.shared.keyWindow?.toggleFullScreen(nil)
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
    @Published var folderURL: URL? = nil
    @Published var isLoadingGames: Bool = false

    /// Open folder picker dialog
    func promptForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose a folder containing .sgf files"
        panel.message = "Select a folder with SGF game files"

        print("🔍 FOLDER PICKER: Showing panel...")
        let result = panel.runModal()

        if result == .OK, let url = panel.url {
            print("🔍 FOLDER PICKER: Selected \(url.path)")
            folderURL = url
            loadSampleGames(from: url)
        } else {
            print("🔍 FOLDER PICKER: Cancelled")
        }
    }

    func loadSampleGames(from folderURL: URL) {
        // Set loading state
        DispatchQueue.main.async {
            self.isLoadingGames = true
        }

        // Save folder URL to settings
        AppSettings.shared.folderURL = folderURL

        // Load in background to avoid blocking UI
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

            // Sort by path
            sgfURLs.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            // Shuffle if requested
            if AppSettings.shared.shuffleGameOrder {
                sgfURLs.shuffle()
                print("🔀 Shuffled game order")
            }

            print("📂 Found \(sgfURLs.count) games, loading all...")

            var parsed: [SGFGameWrapper] = []
            for fileURL in sgfURLs {
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

            // Update on main thread
            DispatchQueue.main.async {
                self.games = parsed

                // Auto-select and load first game if enabled
                if AppSettings.shared.startGameOnLaunch, let firstGame = parsed.first {
                    self.selection = firstGame
                    // Post notification to load the game
                    NotificationCenter.default.post(
                        name: NSNotification.Name("LoadSGFFile"),
                        object: firstGame.url
                    )
                    print("🎮 Auto-launching first game: \(firstGame.title ?? "Untitled")")
                } else {
                    self.selection = parsed.first
                }

                self.isLoadingGames = false
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
