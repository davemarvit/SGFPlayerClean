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
            let layout = BoardWorkspaceGeometry(size: geo.size, aiEnabled: app.showsAnalysisWorkspace,
                sidebarVisible: app.showRightPanel || vm.localScoringVisible)
            ZStack(alignment: .leading) {
                board()
                    .environment(\.boardControlsWidth, layout.aiOrigin)
                    .frame(width: layout.boardWidth, height: geo.size.height)
                    .clipped()
                if app.showsAnalysisWorkspace {
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
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    @ObservedObject var ai = KataGoEngine.shared
    @State private var treeCollapsed = false

    var body: some View {
        GeometryReader { geo in
            let treeVisible = app.mode == .review && vm.reviewTree != nil
            VStack(spacing: 0) {
                if treeVisible {
                    VariationTreeView(vm: vm, isCollapsed: $treeCollapsed)
                        // Reserve the same viewport with AI on or off. Enabling AI
                        // must not move the selected node or reset the user's scroll.
                        .frame(height: treeCollapsed ? 44 : max(180, geo.size.height * 0.55))
                    if app.isAIAvailable { Divider() }
                }
                if app.isAIAvailable {
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
                    .frame(maxHeight: .infinity)
                } else { Spacer(minLength: 0) }
            }
        }
        .background(.black.opacity(0.22))
        .accessibilityIdentifier("ai-workspace-panel")
    }
}

/// Persistent SGF nodes only. Hovered AI continuations never enter this view.
struct VariationTreeView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var vm: BoardViewModel
    @Binding var isCollapsed: Bool
    @FocusState private var hasFocus: Bool
    private let pitch: CGFloat = 22
    private let nodeOrigin: CGFloat = 38

    init(vm: BoardViewModel, isCollapsed: Binding<Bool> = .constant(false)) {
        self.vm = vm
        self._isCollapsed = isCollapsed
    }

    var body: some View {
        if let tree = vm.reviewTree {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button { isCollapsed.toggle() } label: {
                        Label("Variations", systemImage: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.headline)
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
                        navigationButton("arrow.left", "Previous branch", disabled: tree.sibling(direction: -1) == nil) { vm.navigateReviewTree(horizontal: -1) }
                        navigationButton("arrow.right", "Next branch", disabled: tree.sibling(direction: 1) == nil) { vm.navigateReviewTree(horizontal: 1) }
                        Spacer()
                        Text("Move \(tree.nodes[tree.selectedID].moveNumber)").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    Text(vm.reviewDraftSaved ? "Draft saved · Export with Save SGF" : "Play on the board to add a variation")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                    if let error = vm.reviewTreeError {
                        Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 16)
                    }
                    GeometryReader { geo in
                        ScrollViewReader { proxy in
                            ScrollView([.horizontal, .vertical]) {
                                LazyVStack(spacing: 0) {
                                    ForEach(tree.rows.indices, id: \.self) { row in
                                        treeRow(tree, row: row)
                                            .frame(width: max(geo.size.width, nodeOrigin + CGFloat(tree.columnCount) * pitch), height: pitch)
                                            .id("tree-row-\(row)")
                                    }
                                }
                                .padding(.vertical, 12)
                                .frame(minHeight: geo.size.height, alignment: .topLeading)
                            }
                            .onAppear { reveal(tree, in: proxy) }
                            .onChange(of: tree.selectedID) { _, _ in reveal(tree, in: proxy) }
                        }
                    }
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12).padding(.bottom, 12)
                    .focusable().focused($hasFocus)
                    .onKeyPress(.upArrow) { vm.navigateReviewTree(vertical: -1); return .handled }
                    .onKeyPress(.downArrow) { vm.navigateReviewTree(vertical: 1); return .handled }
                    .onKeyPress(.leftArrow) { vm.navigateReviewTree(horizontal: -1); return .handled }
                    .onKeyPress(.rightArrow) { vm.navigateReviewTree(horizontal: 1); return .handled }
                    if let comment = tree.nodes[tree.selectedID].comment, !comment.isEmpty {
                        ScrollView { Text(comment).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 80).padding(.horizontal, 16).padding(.bottom, 12)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("variation-tree")
        }
    }

    private func reveal(_ tree: ReviewTree, in proxy: ScrollViewProxy) {
        // Materialize a distant lazy row before scrolling to its horizontal branch.
        proxy.scrollTo("tree-row-\(tree.nodes[tree.selectedID].depth)", anchor: .center)
        DispatchQueue.main.async { proxy.scrollTo("tree-node-\(tree.selectedID)", anchor: .center) }
    }

    private func navigationButton(_ icon: String, _ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.plain).disabled(disabled).help(label).accessibilityLabel(label)
    }

    private func treeRow(_ tree: ReviewTree, row: Int) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for id in tree.rows[row] {
                    let node = tree.nodes[id]
                    let x = nodeOrigin + CGFloat(tree.columns[id]) * pitch
                    var path = Path()
                    if let parent = node.parent {
                        path.move(to: CGPoint(x: nodeOrigin + CGFloat(tree.columns[parent]) * pitch, y: 0))
                        path.addLine(to: CGPoint(x: x, y: pitch / 2))
                    }
                    if !node.children.isEmpty {
                        path.move(to: CGPoint(x: x, y: pitch / 2))
                        path.addLine(to: CGPoint(x: x, y: pitch))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
                }
            }
            if let rulerNode = tree.rows[row].first.map({ tree.nodes[$0] }),
               rulerNode.color != nil, rulerNode.moveNumber > 0, rulerNode.moveNumber.isMultiple(of: 5) {
                Text(String(rulerNode.moveNumber))
                    .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 25, alignment: .trailing)
                    .position(x: 13, y: pitch / 2)
                    .accessibilityLabel("Move \(rulerNode.moveNumber)")
            }
            ForEach(tree.rows[row], id: \.self) { id in
                let node = tree.nodes[id]
                Button {
                    hasFocus = true
                    vm.selectReviewNode(id)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Circle().fill(node.color == .white ? Color(white: 0.91) : node.color == .black ? Color(white: 0.08) : Color(white: 0.3))
                        if node.comment != nil { Circle().fill(.orange).frame(width: 3, height: 3) }
                    }
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(id == tree.selectedID ? Color.cyan : Color.white.opacity(0.35), lineWidth: id == tree.selectedID ? 2 : 1))
                    .frame(width: pitch, height: pitch).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(nodeDescription(node))
                .help(nodeDescription(node) + (node.comment.map { "\n" + $0 } ?? ""))
                .contextMenu {
                    Button("Add pass here") {
                        vm.selectReviewNode(id)
                        if vm.reviewTree?.selectedID == id { vm.addReviewMove(at: nil) }
                    }
                }
                .id("tree-node-\(id)")
                .position(x: nodeOrigin + CGFloat(tree.columns[id]) * pitch, y: pitch / 2)
            }
        }
    }

    private func nodeDescription(_ node: ReviewTree.Node) -> String {
        guard let color = node.color else { return node.parent == nil ? "Starting position" : "Comment or setup node" }
        return "Move \(node.moveNumber), \(color == .black ? "Black" : "White")" + (node.isPass ? " passes" : "")
    }
}
