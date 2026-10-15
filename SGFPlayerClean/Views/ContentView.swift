// MARK: - File: ContentView.swift (v7.201)
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showSettings: Bool = false
    @State private var buttonsVisible: Bool = true

    var body: some View {
        VStack(spacing: 0) {
        AppModeControls()
        ZStack {
            mainInterface // .disabled(appModel.isCreatingChallenge) removed
            if let vm = appModel.boardVM {
                SharedOverlays(showSettings: $showSettings, buttonsVisible: $buttonsVisible, app: appModel, boardVM: vm)
            }
            VStack {
                HStack {
                    Spacer()
                    // Debug Icon Removed
                }
                Spacer()
            }
            VStack {
                HStack {
                    Spacer()
                    // Debug Icon Removed
                }
                Spacer()
            }
            // Challenge View Removed (Moved to Right Panel)
        }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appModel.showDebugDashboard) { DebugDashboard(appModel: appModel).frame(minWidth: 700, minHeight: 500) }
        .onAppear {
            appModel.handleStartup()
        }
    }

    @ViewBuilder
    private var mainInterface: some View {
        if let vm = appModel.boardVM {
            BoardWorkspaceView(vm: vm) {
                if appModel.viewMode == .view3D { ContentView3D() }
                else { ContentView2D() }
            }
        }
    }
}

/// AI always stays beside the board. On narrower windows the dismissible game
/// panel may cover the AI column, rather than moving analysis below the board.
struct BoardWorkspaceView<Board: View>: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    var analysisEngine: KataGoEngine = .shared
    @ViewBuilder var board: () -> Board

    var body: some View {
        GeometryReader { geo in
            let layout = BoardWorkspaceGeometry(size: geo.size, aiEnabled: app.isAIAvailable,
                sidebarVisible: app.showRightPanel || vm.localScoringVisible)
            ZStack(alignment: .leading) {
                board()
                    .environment(\.boardControlsWidth, layout.aiOrigin)
                    .frame(width: layout.boardWidth, height: geo.size.height)
                    .clipped()
                if app.isAIAvailable {
                    AIWorkspacePanel(vm: vm, ai: analysisEngine)
                        .frame(width: layout.aiWidth, height: geo.size.height)
                        .offset(x: layout.aiOrigin)
                }
                if layout.hasSidebar { RightSidebarOverlay(vm: vm) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .background {
                if app.viewMode == .view3D {
                    Color(nsColor: SceneManager3D.backgroundColor)
                } else {
                    TatamiBackground(boardHeight: geo.size.height * 0.85)
                }
            }
        }
    }
}

struct BoardWorkspaceGeometry {
    let hasSidebar: Bool
    let reservesSidebar: Bool
    let boardWidth: CGFloat
    let aiWidth: CGFloat
    let aiOrigin: CGFloat

    init(size: CGSize, aiEnabled: Bool, sidebarVisible: Bool) {
        hasSidebar = sidebarVisible
        reservesSidebar = sidebarVisible && (!aiEnabled || size.width >= 1500)
        let available = max(1, size.width - (reservesSidebar ? 320 : 0))
        // Give width beyond the board's height limit to analysis, not the left margin.
        let boardAspect: CGFloat = 1.0773
        let groupFactor: CGFloat = 1 + 1 / 19.0 + boardAspect / 3
        let fittedBoardWidth = size.height * 0.85 / boardAspect * groupFactor / 0.92
        let preferredAI = max(280, min(400, available * 0.27))
        aiWidth = aiEnabled ? min(available * 0.5, max(preferredAI, available - fittedBoardWidth)) : 0
        aiOrigin = available - aiWidth
        // Analysis may cover the outer lid area. Preserve the playable board and
        // use the recovered width to enlarge it, rather than reserving every lid pixel.
        let overlap = aiEnabled ? min(aiWidth * 0.65, aiOrigin * 0.25) : 0
        boardWidth = aiOrigin + overlap
    }
}

private struct BoardControlsWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var boardControlsWidth: CGFloat? {
        get { self[BoardControlsWidthKey.self] }
        set { self[BoardControlsWidthKey.self] = newValue }
    }
}

/// The scrollable column leaves room beneath the graph for analysis tools.
struct AIWorkspacePanel: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    @ObservedObject var ai = KataGoEngine.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI analysis").font(.headline)
                WinRateGraphView(aiEngine: ai, vm: vm).frame(maxWidth: .infinity)
                if let game = app.selection {
                    LocalGameMetadataView(game: game, boardVM: vm, isOverlay: true)
                }
                if ai.currentAnalysisData.count >= vm.totalMoves && vm.totalMoves > 5 {
                    MoveQualitySummaryView(evals: Array(ai.evaluateGameQuality(upTo: vm.totalMoves, engine: vm.engine).values))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.black.opacity(0.22))
        .accessibilityIdentifier("ai-workspace-panel")
    }
}
