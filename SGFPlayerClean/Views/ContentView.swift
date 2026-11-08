// MARK: - File: ContentView.swift (v7.201)
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var showSettings: Bool = false
    @State private var buttonsVisible: Bool = true

    var body: some View {
        GeometryReader { window in
        let textScale = CGFloat(settings.interfaceTextScale) * InterfaceTypography.windowScale(width: window.size.width)
        VStack(spacing: 0) {
        AppModeControls()
        CompletedGameResultBanner()
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
        .environment(\.interfaceTextScale, textScale)
        .font(.system(size: 16 * textScale))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appModel.showDebugDashboard) { DebugDashboard(appModel: appModel).frame(minWidth: 700, minHeight: 500) }
        .onAppear {
            appModel.handleStartup()
        }
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

/// Keep the final result visible while the player explores the finished game.
struct CompletedGameResultBanner: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        if app.mode == .review, let result = app.completedGameResult {
            HStack(spacing: 14) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Game finished")
                        .interfaceFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(result)
                        .interfaceFont(.title2, weight: .semibold)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = app.completedGameSaveError {
                        Text(error).interfaceFont(.caption).foregroundStyle(.orange)
                        Button("Retry saving game") { app.retryCompletedGameSave() }
                    } else if let url = app.completedGameSaveURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Saved: " + url.lastPathComponent, systemImage: "folder")
                                .interfaceFont(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Show saved game in Finder")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.13)))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("completed-game-result")
        }
    }
}

/// AI always stays beside the board. On narrower windows the dismissible game
/// panel may cover the AI column, rather than moving analysis below the board.
struct BoardWorkspaceView<Board: View>: View {
    @AppStorage("analysisPanelWidth") private var preferredAnalysisWidth = 0.0
    @State private var resizeHovered = false
    @Environment(\.interfaceTextScale) private var textScale
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    var analysisEngine: KataGoEngine = .shared
    @ViewBuilder var board: () -> Board

    var body: some View {
        GeometryReader { geo in
            // A collapsed tree is only a header. Its transparent column must not
            // consume playing space when AI and post-game chat are absent.
            let reservesAnalysis = app.isAIAvailable || app.postGameChatID != nil
                || (app.mode == .review && vm.reviewTree != nil && !vm.reviewTreeCollapsed)
            let layout = BoardWorkspaceGeometry(size: geo.size, aiEnabled: reservesAnalysis,
                sidebarVisible: app.showRightPanel || vm.localScoringVisible,
                preferredAnalysisWidth: preferredAnalysisWidth > 0 ? CGFloat(preferredAnalysisWidth) : nil)
            ZStack(alignment: .leading) {
                board()
                    .environment(\.boardControlsWidth, layout.aiOrigin)
                    .frame(width: layout.boardWidth, height: geo.size.height)
                    // The oversized 3D scene extends behind the surrounding UI.
                    // Clipping pixels alone does not constrain SwiftUI hit testing.
                    .contentShape(Rectangle())
                    .clipped()
                BoardEventOverlay(boardVM: vm, showsResult: app.mode == .review && app.completedGameResult == nil)
                    .frame(width: layout.aiOrigin, height: geo.size.height)
                if app.showsAnalysisWorkspace {
                    let panelWidth = reservesAnalysis ? layout.aiWidth : min(400, layout.aiOrigin)
                    AIWorkspacePanel(vm: vm, ai: analysisEngine)
                        .frame(width: panelWidth, height: reservesAnalysis ? geo.size.height : 44 * textScale)
                        .frame(height: geo.size.height, alignment: .top)
                        .offset(x: reservesAnalysis ? layout.aiOrigin : layout.aiOrigin - panelWidth)
                }
                if reservesAnalysis && app.showsAnalysisWorkspace {
                    resizeHandle(layout: layout, height: geo.size.height)
                        .offset(x: layout.aiOrigin - 5)
                }
                if layout.hasSidebar { RightSidebarOverlay(vm: vm) }
            }
            .coordinateSpace(name: "board-workspace")
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .background {
                if app.viewMode == .view3D {
                    Color(nsColor: SceneManager3D.backgroundColor)
                } else {
                    TatamiBackground(boardHeight: ContentView2D.getLayout(
                        area: CGSize(width: layout.boardWidth, height: geo.size.height)).bH)
                }
            }
        }
    }

    private func resizeHandle(layout: BoardWorkspaceGeometry, height: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(.white.opacity(resizeHovered ? 0.35 : 0.12)).frame(width: 1)
            Capsule().fill(.white.opacity(resizeHovered ? 0.85 : 0.45)).frame(width: 3, height: 36)
        }
        .frame(width: 10, height: height)
        .contentShape(Rectangle())
        .overlay(AnalysisPanelResizeSurface(width: layout.aiWidth,
            onResize: { preferredAnalysisWidth = Double(layout.clampedAnalysisWidth($0)) },
            onReset: { preferredAnalysisWidth = 0 }))
        .onHover { resizeHovered = $0 }
        .help("Drag to resize the analysis panel. Double-click to restore automatic width.")
        .accessibilityElement()
        .accessibilityLabel("Resize analysis panel")
        .accessibilityIdentifier("analysis-panel-resizer")
        .accessibilityValue("\(Int(layout.aiWidth)) points wide")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: preferredAnalysisWidth = Double(layout.clampedAnalysisWidth(layout.aiWidth + 40))
            case .decrement: preferredAnalysisWidth = Double(layout.clampedAnalysisWidth(layout.aiWidth - 40))
            @unknown default: break
            }
        }
    }
}

/// Use window coordinates so moving the divider during a drag cannot move the
/// gesture's origin. Native mouse tracking also supports double-click reset.
struct AnalysisPanelResizeSurface: NSViewRepresentable {
    let width: CGFloat
    let onResize: (CGFloat) -> Void
    let onReset: () -> Void

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) {
        view.panelWidth = width; view.onResize = onResize; view.onReset = onReset
    }
    final class Surface: NSView {
        var panelWidth: CGFloat = 0
        var onResize: ((CGFloat) -> Void)?
        var onReset: (() -> Void)?
        private var dragStart: (x: CGFloat, width: CGFloat)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { dragStart = nil; onReset?() }
            else { dragStart = (event.locationInWindow.x, panelWidth) }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStart else { return }
            onResize?(start.width + start.x - event.locationInWindow.x)
        }
        override func mouseUp(with event: NSEvent) { dragStart = nil }
    }
}

struct BoardWorkspaceGeometry {
    let hasSidebar: Bool
    let reservesSidebar: Bool
    let boardWidth: CGFloat
    let aiWidth: CGFloat
    let aiOrigin: CGFloat
    let analysisWidthRange: ClosedRange<CGFloat>

    func clampedAnalysisWidth(_ width: CGFloat) -> CGFloat {
        min(analysisWidthRange.upperBound, max(analysisWidthRange.lowerBound, width))
    }

    init(size: CGSize, aiEnabled: Bool, sidebarVisible: Bool, preferredAnalysisWidth: CGFloat? = nil) {
        hasSidebar = sidebarVisible
        reservesSidebar = sidebarVisible && (!aiEnabled || size.width >= 1500)
        let available = max(1, size.width - (reservesSidebar ? 320 : 0))
        // Give width beyond the board's height limit to analysis, not the left margin.
        let boardAspect: CGFloat = 1.0773
        let groupFactor: CGFloat = 1 + 1 / 19.0 + boardAspect / 3
        let fittedBoardWidth = size.height * 0.85 / boardAspect * groupFactor / 0.92
        let preferredAI = max(280, min(400, available * 0.27))
        let maximum = available * 0.5
        let minimum = min(280, maximum)
        analysisWidthRange = minimum...maximum
        let automaticWidth = max(preferredAI, available - fittedBoardWidth)
        let requestedWidth = preferredAnalysisWidth.flatMap { $0.isFinite ? $0 : nil } ?? automaticWidth
        aiWidth = aiEnabled ? min(maximum, max(minimum, requestedWidth)) : 0
        aiOrigin = available - aiWidth
        // Analysis may cover the outer lid area. Preserve the playable board and
        // use the recovered width to enlarge it, rather than reserving every lid pixel.
        let overlap = aiEnabled ? min(aiWidth * 0.95, aiOrigin * 0.36) : 0
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

/// AI tools and the persistent game tree have independent scroll areas.
struct AIWorkspacePanel: View {
    @Environment(\.interfaceTextScale) private var textScale
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    @ObservedObject var ai = KataGoEngine.shared

    var body: some View {
        GeometryReader { geo in
            let treeVisible = app.mode == .review && vm.reviewTree != nil
            let chatHeight: CGFloat = app.postGameChatID != nil ? min(240, max(180, geo.size.height * 0.35)) : 0
            VStack(spacing: 0) {
                if treeVisible {
                    VariationTreeView(vm: vm, isCollapsed: $vm.reviewTreeCollapsed)
                        // Reserve the same viewport with AI on or off. Enabling AI
                        // must not move the selected node or reset the user's scroll.
                        .frame(height: vm.reviewTreeCollapsed ? 44 * textScale : max(140, (geo.size.height - chatHeight) * 0.55))
                    if app.isAIAvailable { Divider() }
                }
                if app.isAIAvailable {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("AI analysis").interfaceFont(.headline)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 7) {
                                    Circle().stroke(Color.blue, lineWidth: 3).frame(width: 14, height: 14)
                                    Text("Best suggestion")
                                }
                                HStack(spacing: 7) {
                                    Circle().stroke(.primary, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                                        .frame(width: 14, height: 14)
                                    Text("Played move")
                                }
                            }
                            .interfaceFont(.caption2)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Blue ring: best suggestion. Dashed ring: played move. Fill color indicates move quality.")
                            MoveLossLegend()
                            if app.mode == .review {
                                Button("Analyze full game") { app.analyzeFullGame() }
                                    .buttonStyle(.bordered)
                                    .disabled(vm.totalMoves == 0)
                                    .help("Analyze every position from the opening, then deepen the whole game. Keeps your place and reuses saved results.")
                                    .accessibilityIdentifier("analyze-full-game")
                                let covered = (0...vm.totalMoves).filter {
                                    (ai.currentAnalysisData[$0]?.rootInfo?.visits ?? 0) > 0
                                }.count
                                Text("Game coverage · \(covered) of \(vm.totalMoves + 1) positions")
                                    .interfaceFont(.caption).foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .accessibilityIdentifier("full-game-coverage")
                                Toggle("Ownership & dead stones", isOn: $vm.showLikelyDeadStones)
                                    .toggleStyle(.switch)
                                    .help("Black and white shading shows expected ownership. Faded stones and stronger crosses indicate groups expected to be lost. Estimates, not scoring decisions.")
                                    .accessibilityIdentifier("likely-dead-stones-toggle")
                                Toggle("Keep analyzing", isOn: Binding(
                                    get: { app.keepAnalyzing }, set: { app.setKeepAnalyzing($0) }))
                                    .toggleStyle(.switch)
                                    .help("Continuously deepen the selected position. Follows the selected move and pauses during playback.")
                                    .accessibilityIdentifier("keep-analyzing-toggle")
                                if app.keepAnalyzing {
                                    Text(vm.isAutoPlaying || vm.isScrubbing ? "Paused during playback" :
                                        (ai.engineStartupError ?? ai.analysisError ??
                                         "Selected position \(vm.currentMoveIndex) · \(ai.currentAnalysisData[vm.currentMoveIndex]?.rootInfo?.visits ?? 0) visits"))
                                        .interfaceFont(.caption).foregroundStyle(.secondary)
                                        .monospacedDigit()
                                        .accessibilityIdentifier("keep-analyzing-status")
                                }
                            }
                            WinRateGraphView(aiEngine: ai, vm: vm).frame(maxWidth: .infinity)
                            if app.viewMode != .view3D, let game = app.selection {
                                LocalGameMetadataView(game: game, boardVM: vm, isOverlay: true)
                            }
                            let evals = Array(ai.evaluateGameQuality(upTo: vm.totalMoves, engine: vm.engine).values)
                            MistakeFilterView(vm: vm, analyzedCount: evals.count)
                            ScrollView(.horizontal) {
                                MoveQualitySummaryView(evals: evals, analyses: ai.currentAnalysisData)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                } else { Spacer(minLength: 0) }
                if app.postGameChatID != nil, let game = app.ogsGame {
                    Divider()
                    OGSChatView(gameVM: game)
                        .frame(height: chatHeight)
                        .background(Color(white: 0.10))
                }
            }
        }
        .background(.black.opacity(app.isAIAvailable ||
            (app.mode == .review && vm.reviewTree != nil && !vm.reviewTreeCollapsed) ? 0.22 : 0))
        .accessibilityIdentifier("ai-workspace-panel")
        .onReceive(app.$selection) { _ in vm.reviewTreeCollapsed = true }
    }
}

/// A vertical focus lens: integrate the magnification so rows never overlap.
/// Horizontal lanes stay fixed as focus moves, keeping forks easy to follow.
struct VariationTreeLens {
    let focusRow: Int
    static let columnPitch: CGFloat = 38
    private func integral(_ row: CGFloat) -> CGFloat {
        let distance = row - CGFloat(focusRow) - 0.5
        return 18 * row + 60 * atan(distance / 2.5)
    }
    func top(of row: Int) -> CGFloat { integral(CGFloat(row)) - integral(0) }
    func height(of row: Int) -> CGFloat { top(of: row + 1) - top(of: row) }
    func diameter(at row: Int) -> CGFloat {
        let distance = CGFloat(row - focusRow) / 2.5
        return 12 + 16 / (1 + distance * distance)
    }
    func row(at y: CGFloat, count: Int) -> Int? {
        guard y >= 0, y < top(of: count) else { return nil }
        var lower = 0, upper = count
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if top(of: middle) <= y { lower = middle } else { upper = middle }
        }
        return lower
    }
}

/// Persistent SGF nodes only. Hovered AI continuations never enter this view.
struct VariationTreeView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    @Binding var isCollapsed: Bool
    @StateObject private var treeScroll = VariationTreeScrollSupport.Coordinator()
    private let pitch: CGFloat = VariationTreeLens.columnPitch
    private let nodeOrigin: CGFloat = 38

    init(vm: BoardViewModel, isCollapsed: Binding<Bool> = .constant(false)) {
        self.vm = vm
        self._isCollapsed = isCollapsed
    }

    var body: some View {
        if let tree = vm.reviewTree {
            let highlightedNodes = ancestry(of: tree)
            let lens = VariationTreeLens(focusRow: tree.nodes[tree.selectedID].depth)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button { isCollapsed.toggle() } label: {
                        Label("Variations", systemImage: isCollapsed ? "chevron.right" : "chevron.down")
                            .interfaceFont(.headline)
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Expand variation tree" : "Collapse variation tree")
                    .accessibilityLabel(isCollapsed ? "Expand variation tree" : "Collapse variation tree")
                    .accessibilityIdentifier("variation-tree-disclosure")
                    Spacer()
                    Button { app.saveReviewSGF() } label: {
                        Label("Save SGF…", systemImage: "square.and.arrow.down")
                    }
                    .help("Save SGF with all variations")
                    .accessibilityLabel("Save SGF with all variations")
                }
                .padding(.horizontal, 16).padding(.top, 12)
                if !isCollapsed {
                    HStack(spacing: 12) {
                        navigationButton("arrow.up", "Previous node", disabled: tree.neighbor(direction: -1) == nil) { vm.navigateReviewTree(vertical: -1) }
                        navigationButton("arrow.down", "Next node", disabled: tree.neighbor(direction: 1) == nil) { vm.navigateReviewTree(vertical: 1) }
                        Divider().frame(height: 14)
                        navigationButton("arrow.left", "Previous variation (Control–Left)", disabled: tree.sibling(direction: -1) == nil) { vm.navigateReviewTree(horizontal: -1) }
                        navigationButton("arrow.right", "Next variation (Control–Right)", disabled: tree.sibling(direction: 1) == nil) { vm.navigateReviewTree(horizontal: 1) }
                        navigationButton("arrow.uturn.backward.circle", "Return to main-line branch point (Command–Left)", disabled: tree.mainLineBranchOrigin == nil) { vm.returnToMainLineBranchOrigin() }
                        Button { vm.deleteSelectedReviewNode() } label: { Image(systemName: "trash") }
                            .disabled(!vm.canDeleteReviewNode)
                            .help("Delete selected node and its continuation")
                            .accessibilityLabel("Delete node and continuation")
                        Button { vm.undoReviewDeletion() } label: { Image(systemName: "arrow.uturn.backward") }
                            .disabled(!vm.canUndoReviewDeletion)
                            .help("Undo Delete")
                            .accessibilityLabel("Undo Delete")
                        Spacer()
                        Text("Move \(tree.nodes[tree.selectedID].moveNumber)").interfaceFont(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    Text(vm.reviewDraftSaved ? "Draft saved · Export with Save SGF" : "Play on the board to add a variation")
                        .interfaceFont(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                    if let error = vm.reviewTreeError {
                        Text(error).interfaceFont(.caption).foregroundStyle(.orange).padding(.horizontal, 16)
                    }
                    GeometryReader { geo in
                        // Enough space above and below the tree to center even
                        // the starting position and the final move.
                        let treePadding = max(12, (geo.size.height - 16 - lens.height(of: lens.focusRow)) / 2)
                        ScrollView([.horizontal, .vertical]) {
                            // Explicit row positions avoid LazyVStack's estimated
                            // heights when jumping far through a variable-size tree.
                            // Render only the viewport plus a small scrolling margin.
                            let width = max(geo.size.width, nodeOrigin + CGFloat(tree.columnCount) * pitch)
                            ZStack(alignment: .topLeading) {
                                ForEach(visibleRows(tree, lens: lens, padding: treePadding, viewportHeight: geo.size.height), id: \.self) { row in
                                    treeRow(tree, row: row, lens: lens, highlightedNodes: highlightedNodes)
                                        .frame(width: width, height: lens.height(of: row))
                                        .position(x: width / 2, y: treePadding + lens.top(of: row) + lens.height(of: row) / 2)
                                }
                            }
                            .frame(width: width, height: max(geo.size.height + 1, 2 * treePadding + lens.top(of: tree.rows.count)), alignment: .topLeading)
                            .background(VariationTreeScrollSupport(
                                controller: treeScroll, selection: tree.selectedID,
                                target: CGRect(x: nodeOrigin + CGFloat(tree.columns[tree.selectedID]) * pitch - pitch / 2,
                                               y: treePadding + lens.top(of: lens.focusRow),
                                               width: pitch, height: lens.height(of: lens.focusRow))))
                        }
                        .scrollIndicators(.visible)
                        .overlay(alignment: .topLeading) {
                            VariationTreeMouseSurface(controller: treeScroll,
                                playback: { direction, tenMoves, variation in vm.navigatePlayback(direction: direction, tenMoves: tenMoves, variation: variation) },
                                returnToOrigin: { vm.returnToMainLineBranchOrigin() },
                                navigate: { vertical, horizontal in vm.navigateReviewTree(vertical: vertical, horizontal: horizontal) },
                                select: { point in
                                    if let id = node(at: point, tree: tree, lens: lens, topPadding: treePadding) { vm.selectReviewNode(id) }
                                },
                                describe: { point in
                                    guard let id = node(at: point, tree: tree, lens: lens, topPadding: treePadding) else { return nil }
                                    return nodeDescription(tree.nodes[id]) + (tree.nodes[id].comment.map { "\n" + $0 } ?? "")
                                },
                                contextActions: { point in
                                    guard let id = node(at: point, tree: tree, lens: lens, topPadding: treePadding) else { return [] }
                                    return nodeContextActions(tree, id: id)
                                })
                                .frame(width: max(0, geo.size.width - 16), height: max(0, geo.size.height - 16))
                        }
                        .onDisappear { treeScroll.endDrag() }
                    }
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12).padding(.bottom, 12)
                    if let comment = tree.nodes[tree.selectedID].comment, !comment.isEmpty {
                        ScrollView { Text(comment).interfaceFont(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 80).padding(.horizontal, 16).padding(.bottom, 12)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("variation-tree")
        }
    }

    private func visibleRows(_ tree: ReviewTree, lens: VariationTreeLens, padding: CGFloat, viewportHeight: CGFloat) -> ClosedRange<Int> {
        let viewport = treeScroll.visibleRect
        let center = padding + lens.top(of: lens.focusRow) + lens.height(of: lens.focusRow) / 2
        let top = viewport.isEmpty ? center - viewportHeight / 2 : viewport.minY
        let bottom = viewport.isEmpty ? center + viewportHeight / 2 : viewport.maxY
        let last = tree.rows.count - 1
        let startY = max(0, top - padding - 100)
        let endY = max(0, bottom - padding + 100)
        let first = lens.row(at: startY, count: tree.rows.count) ?? last
        let end = lens.row(at: endY, count: tree.rows.count) ?? last
        return first...max(first, end)
    }

    private func node(at point: CGPoint, tree: ReviewTree, lens: VariationTreeLens, topPadding: CGFloat) -> Int? {
        guard let row = lens.row(at: point.y - topPadding, count: tree.rows.count) else { return nil }
        return tree.rows[row].first { abs(point.x - (nodeOrigin + CGFloat(tree.columns[$0]) * pitch)) <= pitch / 2 }
    }

    private func navigationButton(_ icon: String, _ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.plain).disabled(disabled).help(label).accessibilityLabel(label)
    }

    private func ancestry(of tree: ReviewTree) -> Set<Int> {
        var result = Set<Int>()
        var current: Int? = tree.selectedID
        while let id = current {
            result.insert(id)
            current = tree.nodes[id].parent
        }
        return result
    }

    private func treeRow(_ tree: ReviewTree, row: Int, lens: VariationTreeLens, highlightedNodes: Set<Int>) -> some View {
        let height = lens.height(of: row)
        let diameter = lens.diameter(at: row)
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var branches = Path()
                var highlighted = Path()
                for id in tree.rows[row] {
                    let node = tree.nodes[id]
                    let x = nodeOrigin + CGFloat(tree.columns[id]) * pitch
                    if let parent = node.parent {
                        let start = CGPoint(x: nodeOrigin + CGFloat(tree.columns[parent]) * pitch, y: 0)
                        let end = CGPoint(x: x, y: height / 2)
                        branches.move(to: start); branches.addLine(to: end)
                        if highlightedNodes.contains(id) {
                            highlighted.move(to: start); highlighted.addLine(to: end)
                        }
                    }
                    if !node.children.isEmpty {
                        let start = CGPoint(x: x, y: height / 2)
                        let end = CGPoint(x: x, y: height)
                        branches.move(to: start); branches.addLine(to: end)
                        // Stop the yellow path at the selected node, even when
                        // the selected line has further moves below it.
                        if highlightedNodes.contains(id), id != tree.selectedID {
                            highlighted.move(to: start); highlighted.addLine(to: end)
                        }
                    }
                }
                context.stroke(branches, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
                context.stroke(highlighted, with: .color(.yellow), lineWidth: 2)
            }
            if let rulerNode = tree.rows[row].first.map({ tree.nodes[$0] }),
               rulerNode.color != nil, rulerNode.moveNumber > 0, rulerNode.moveNumber.isMultiple(of: 5) {
                Text(String(rulerNode.moveNumber))
                    .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 25, alignment: .trailing)
                    .position(x: 13, y: height / 2)
                    .accessibilityLabel("Move \(rulerNode.moveNumber)")
            }
            ForEach(tree.rows[row], id: \.self) { id in
                let node = tree.nodes[id]
                Button {
                    vm.selectReviewNode(id)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Circle().fill(node.color == .white ? Color(white: 0.91) : node.color == .black ? Color(white: 0.08) : Color(white: 0.3))
                        if node.comment != nil { Circle().fill(.orange).frame(width: 3, height: 3) }
                    }
                    .frame(width: diameter, height: diameter)
                     .overlay {
                        if id == tree.selectedID {
                            Circle().strokeBorder(Color.cyan, lineWidth: 5)
                                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 0.75))
                                .frame(width: diameter + 4, height: diameter + 4)
                        } else {
                            Circle().stroke(Color.white.opacity(node.color == .black ? 0.85 : 0.35),
                                            lineWidth: node.color == .black ? 2 : 1)
                        }
                    }
                    .frame(width: pitch, height: height).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(nodeDescription(node))
                .help(nodeDescription(node) + (node.comment.map { "\n" + $0 } ?? ""))
                .contextMenu {
                    ForEach(Array(nodeContextActions(tree, id: id).enumerated()), id: \.offset) { index, action in
                        if index == 1 { Divider() }
                        Button(action.title, action: action.perform).disabled(!action.enabled)
                    }
                }
                .id("tree-node-\(id)")
                .position(x: nodeOrigin + CGFloat(tree.columns[id]) * pitch, y: height / 2)
            }
        }
    }

    private func nodeContextActions(_ tree: ReviewTree, id: Int) -> [VariationTreeMouseSurface.MenuAction] {
        [
            .init(title: "Add pass here", enabled: vm.canCreateReviewVariation) {
                vm.selectReviewNode(id)
                if vm.reviewTree?.selectedID == id { vm.addReviewMove(at: nil) }
            },
            .init(title: tree.nodes[id].children.isEmpty ? "Delete Node" : "Delete Node and Continuation",
                  enabled: vm.canDeleteReviewNode(id)) { vm.deleteReviewNode(id) },
            .init(title: "Undo Delete", enabled: vm.canCreateReviewVariation && vm.canUndoReviewDeletion) {
                vm.undoReviewDeletion()
            }
        ]
    }

    private func nodeDescription(_ node: ReviewTree.Node) -> String {
        guard let color = node.color else { return node.parent == nil ? "Starting position" : "Comment or setup node" }
        return "Move \(node.moveNumber), \(color == .black ? "Black" : "White")" + (node.isPass ? " passes" : "")
    }
}

/// Keeps native wheel/scrollbar behavior and publishes the visible tree area, adding
/// mouse panning and a steady vertical midpoint for the active move.
struct VariationTreeScrollSupport: NSViewRepresentable {
    let controller: Coordinator
    let selection: Int
    let target: CGRect

    final class Anchor: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func makeCoordinator() -> Coordinator { controller }
    func updateNSView(_ view: Anchor, context: Context) {
        context.coordinator.update(view: view, selection: selection, target: target)
    }
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator: ObservableObject {
        weak var scroll: NSScrollView?
        weak var anchor: Anchor?
        @Published private(set) var visibleRect = CGRect.zero
        private var boundsObserver: NSObjectProtocol?

        deinit { if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) } }
        private func publishVisibleRect() {
            guard let scroll, let anchor else { return }
            let rect = anchor.convert(scroll.contentView.bounds, from: scroll.contentView)
            if visibleRect != rect { visibleRect = rect }
        }
        private var origin: CGPoint?
        private var lastSelection: Int?
        private var generation = 0

        func detach() {
            generation += 1
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            boundsObserver = nil
            scroll = nil; anchor = nil; endDrag()
        }
        func update(view: Anchor, selection: Int, target: CGRect) {
            generation += 1
            let ticket = generation
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, ticket == self.generation,
                      let scroll = view.enclosingScrollView else { return }
                let attaching = self.scroll !== scroll
                self.scroll = scroll
                self.anchor = view
                scroll.scrollerStyle = .legacy
                scroll.hasVerticalScroller = true
                scroll.hasHorizontalScroller = true
                scroll.autohidesScrollers = false
                if attaching {
                    if let boundsObserver = self.boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
                    scroll.contentView.postsBoundsChangedNotifications = true
                    self.boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                        object: scroll.contentView, queue: .main) { [weak self] _ in self?.publishVisibleRect() }
                }
                defer { self.publishVisibleRect() }
                guard attaching || self.lastSelection != selection else { return }
                self.lastSelection = selection
                guard let document = scroll.documentView else { return }
                // Follow selection, not redraws: manual scrolling stays untouched
                // until navigation selects another move. Reveal branches horizontally
                // only when needed; vertical centering follows the lens geometry.
                let rect = view.convert(target, to: document)
                let clip = scroll.contentView
                var proposed = clip.bounds
                proposed.origin.y = rect.midY - proposed.height / 2
                if rect.minX < proposed.minX { proposed.origin.x = rect.minX }
                else if rect.maxX > proposed.maxX { proposed.origin.x = rect.maxX - proposed.width }
                clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
                scroll.reflectScrolledClipView(clip)
            }
        }
        // The input surface recognizes either a drag or a mouse-up click.
        // Its coordinates stay fixed while the native content scrolls.
        func drag(_ translation: CGSize) {
            guard let scroll else { return }
            let clip = scroll.contentView
            if origin == nil { origin = clip.bounds.origin }
            guard let origin else { return }
            let proposed = CGRect(origin: CGPoint(x: origin.x - translation.width,
                y: origin.y - translation.height * (clip.isFlipped ? 1 : -1)), size: clip.bounds.size)
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
            scroll.reflectScrolledClipView(clip)
        }
        func endDrag() { origin = nil }
    }
}

/// A mouse surface over the viewport only (never the scrollbars). Mouse-down
/// records intent; mouse-up selects, unless movement has committed to panning.
/// Keeping this explicit avoids SwiftUI's different hit behavior over empty rows.
struct VariationTreeMouseSurface: NSViewRepresentable {
    struct MenuAction {
        let title: String
        let enabled: Bool
        let perform: () -> Void
    }
    let controller: VariationTreeScrollSupport.Coordinator
    let playback: (Int, Bool, Bool) -> Void
    let returnToOrigin: () -> Void
    let navigate: (Int, Int) -> Void
    let select: (CGPoint) -> Void
    let describe: (CGPoint) -> String?
    let contextActions: (CGPoint) -> [MenuAction]

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) { view.actions = self }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.actions?.controller.endDrag() }

    final class Surface: NSView {
        var actions: VariationTreeMouseSurface?
        private var start: CGPoint?
        private var dragging = false
        private var tracking: NSTrackingArea?
        private var menuActions: [MenuAction] = []
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func keyDown(with event: NSEvent) {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == 123, modifiers == .command {
                actions?.returnToOrigin()
                return
            }
            guard !modifiers.contains(.command), !modifiers.contains(.option) else {
                super.keyDown(with: event)
                return
            }
            switch event.keyCode {
            case 123, 124:
                actions?.playback(event.keyCode == 123 ? -1 : 1,
                                  event.modifierFlags.contains(.shift),
                                  event.modifierFlags.contains(.control))
            case 125: actions?.navigate(1, 0)
            case 126: actions?.navigate(-1, 0)
            default: super.keyDown(with: event)
            }
        }
        override func isAccessibilityElement() -> Bool { false }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
                return
            }
            start = convert(event.locationInWindow, from: nil)
            dragging = false
            actions?.controller.endDrag()
            window?.makeFirstResponder(self)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            let point = convert(event.locationInWindow, from: nil)
            let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
            if hypot(delta.width, delta.height) >= 5 { dragging = true }
            if dragging { toolTip = nil; actions?.controller.drag(delta) }
        }
        override func mouseUp(with event: NSEvent) {
            defer { start = nil; dragging = false; actions?.controller.endDrag() }
            guard start != nil, !dragging, bounds.contains(convert(event.locationInWindow, from: nil)),
                  let point = contentPoint(event) else { return }
            actions?.select(point)
        }
        override func scrollWheel(with event: NSEvent) { actions?.controller.scroll?.scrollWheel(with: event) }
        private func contentPoint(_ event: NSEvent) -> CGPoint? {
            actions?.controller.anchor?.convert(event.locationInWindow, from: nil)
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
            addTrackingArea(area); tracking = area
        }
        override func mouseMoved(with event: NSEvent) {
            toolTip = contentPoint(event).flatMap { actions?.describe($0) }
                ?? "Click a move to select it; drag to scroll the tree."
        }
        override func mouseExited(with event: NSEvent) { toolTip = nil }
        override func menu(for event: NSEvent) -> NSMenu? {
            guard let point = contentPoint(event) else { return nil }
            // Resolve the node now. Lens/selection changes while the menu is open
            // must not make an action operate on a different row at this coordinate.
            menuActions = actions?.contextActions(point) ?? []
            guard !menuActions.isEmpty else { return nil }
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (index, command) in menuActions.enumerated() {
                if index == 1 { menu.addItem(.separator()) }
                let item = NSMenuItem(title: command.title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
                item.tag = index; item.isEnabled = command.enabled
                item.target = self; menu.addItem(item)
            }
            return menu
        }
        @objc private func performMenuAction(_ sender: NSMenuItem) {
            guard menuActions.indices.contains(sender.tag), menuActions[sender.tag].enabled else { return }
            menuActions[sender.tag].perform()
        }
    }
}

// macOS does not scale fixed caption fonts with a window's available space.
// Keep a common hierarchy for app text, with a separate prominent AI readout.
enum InterfaceTypography {
    static func windowScale(width: CGFloat) -> CGFloat {
        1 + min(0.4, max(0, (width - 1440) / 2400))
    }
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 23
        case .title3: return 20
        case .headline: return 18
        case .body: return 16
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 14
        case .caption: return 14
        case .caption2: return 13
        @unknown default: return 16
        }
    }
}
private struct InterfaceTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}
extension EnvironmentValues {
    var interfaceTextScale: CGFloat {
        get { self[InterfaceTextScaleKey.self] }
        set { self[InterfaceTextScaleKey.self] = newValue }
    }
}
private struct InterfaceFont: ViewModifier {
    @Environment(\.interfaceTextScale) private var scale
    let style: Font.TextStyle
    let weight: Font.Weight?
    func body(content: Content) -> some View {
        content.font(.system(size: InterfaceTypography.size(style) * scale,
                             weight: weight ?? (style == .headline ? .semibold : .regular)))
    }
}
extension View {
    func interfaceFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(InterfaceFont(style: style, weight: weight))
    }
}
