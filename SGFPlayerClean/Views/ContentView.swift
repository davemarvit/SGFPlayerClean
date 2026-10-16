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
                            let evals = Array(ai.evaluateGameQuality(upTo: vm.totalMoves, engine: vm.engine).values)
                            MistakeFilterView(vm: vm, analyzedCount: evals.count)
                            MoveQualitySummaryView(evals: evals, analyses: ai.currentAnalysisData)
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
    @StateObject private var treeScroll = VariationTreeScrollSupport.Coordinator()
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
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(spacing: 0) {
                                ForEach(tree.rows.indices, id: \.self) { row in
                                    treeRow(tree, row: row)
                                        .frame(width: max(geo.size.width - 16, nodeOrigin + CGFloat(tree.columnCount) * pitch), height: pitch)
                                        .id("tree-row-\(row)")
                                }
                            }
                            .padding(.vertical, 12)
                            .frame(minHeight: max(0, geo.size.height - 16), alignment: .topLeading)
                            .background(VariationTreeScrollSupport(
                                controller: treeScroll, selection: tree.selectedID,
                                target: CGRect(x: nodeOrigin + CGFloat(tree.columns[tree.selectedID]) * pitch - pitch / 2,
                                               y: 12 + CGFloat(tree.nodes[tree.selectedID].depth) * pitch,
                                               width: pitch, height: pitch)))
                        }
                        .scrollIndicators(.visible)
                        .overlay(alignment: .topLeading) {
                            VariationTreeMouseSurface(controller: treeScroll,
                                navigate: { vertical, horizontal in vm.navigateReviewTree(vertical: vertical, horizontal: horizontal) },
                                select: { point in
                                    if let id = node(at: point, tree: tree) { vm.selectReviewNode(id) }
                                },
                                describe: { point in
                                    guard let id = node(at: point, tree: tree) else { return nil }
                                    return nodeDescription(tree.nodes[id]) + (tree.nodes[id].comment.map { "\n" + $0 } ?? "")
                                },
                                addPass: { point in
                                    if let id = node(at: point, tree: tree) {
                                        vm.selectReviewNode(id)
                                        if vm.reviewTree?.selectedID == id { vm.addReviewMove(at: nil) }
                                    }
                                })
                                .frame(width: max(0, geo.size.width - 16), height: max(0, geo.size.height - 16))
                        }
                        .onDisappear { treeScroll.endDrag() }
                    }
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12).padding(.bottom, 12)
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

    private func node(at point: CGPoint, tree: ReviewTree) -> Int? {
        let row = Int(floor((point.y - 12) / pitch))
        guard tree.rows.indices.contains(row) else { return nil }
        return tree.rows[row].first { abs(point.x - (nodeOrigin + CGFloat(tree.columns[$0]) * pitch)) <= pitch / 2 }
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
                    vm.selectReviewNode(id)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Circle().fill(node.color == .white ? Color(white: 0.91) : node.color == .black ? Color(white: 0.08) : Color(white: 0.3))
                        if node.comment != nil { Circle().fill(.orange).frame(width: 3, height: 3) }
                    }
                    .frame(width: 14, height: 14)
                     .overlay {
                        if id == tree.selectedID {
                            Circle().strokeBorder(Color.cyan, lineWidth: 5)
                                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 0.75))
                                .frame(width: 18, height: 18)
                        } else {
                            Circle().stroke(Color.white.opacity(0.35), lineWidth: 1)
                        }
                    }
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

/// Keeps SwiftUI's lazy tree and native wheel/scrollbar behavior, while adding
/// mouse panning and minimal reveal instead of recentering every selection.
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
        private var origin: CGPoint?
        private var lastSelection: Int?
        private var generation = 0

        func detach() {
            generation += 1
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
                guard attaching || self.lastSelection != selection else { return }
                self.lastSelection = selection
                guard let document = scroll.documentView else { return }
                // Coordinates belong to the full content background, including
                // unmaterialized lazy rows. AppKit reveals only the clipped edges.
                let rect = view.convert(target, to: document)
                document.scrollToVisible(rect)
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
    let controller: VariationTreeScrollSupport.Coordinator
    let navigate: (Int, Int) -> Void
    let select: (CGPoint) -> Void
    let describe: (CGPoint) -> String?
    let addPass: (CGPoint) -> Void

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) { view.actions = self }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.actions?.controller.endDrag() }

    final class Surface: NSView {
        var actions: VariationTreeMouseSurface?
        private var start: CGPoint?
        private var dragging = false
        private var tracking: NSTrackingArea?
        private var menuPoint: CGPoint?
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 123: actions?.navigate(0, -1)
            case 124: actions?.navigate(0, 1)
            case 125: actions?.navigate(1, 0)
            case 126: actions?.navigate(-1, 0)
            default: super.keyDown(with: event)
            }
        }
        override func isAccessibilityElement() -> Bool { false }
        override func mouseDown(with event: NSEvent) {
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
            guard let point = contentPoint(event), actions?.describe(point) != nil else { return nil }
            menuPoint = point
            let menu = NSMenu()
            let item = NSMenuItem(title: "Add pass here", action: #selector(addPassHere), keyEquivalent: "")
            item.target = self; menu.addItem(item)
            return menu
        }
        @objc private func addPassHere() { if let menuPoint { actions?.addPass(menuPoint) } }
    }
}
