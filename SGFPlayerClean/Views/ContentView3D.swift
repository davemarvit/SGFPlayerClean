// ========================================================
// FILE: ./Views/ContentView3D.swift
// VERSION: v5.100 (Click Debugging)
// ========================================================
import SwiftUI
import SceneKit
import Combine

struct ContentView3D: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardControlsWidth) private var controlsWidth
    @StateObject private var sceneManager = SceneManager3D(
        optimizesCameraArrival: !UserDefaults.standard.bool(forKey: "disableOptimized3DArrival"))
    @FocusState private var isBoardFocused: Bool
    @State private var playbackHeight: CGFloat = 65
    @State private var hasPresentedScene = false
    
    // Camera State
    @State private var rotX: Float
    @State private var rotY: Float
    @State private var distance: CGFloat
    @State private var panX: CGFloat
    @State private var panY: CGFloat
    
    init() {
        let settings = AppSettings.shared
        _rotX = State(initialValue: Float(settings.camera3DRotationX))
        _rotY = State(initialValue: Float(settings.camera3DRotationY))
        _distance = State(initialValue: CGFloat(settings.camera3DDistance))
        _panX = State(initialValue: CGFloat(settings.camera3DPanX))
        _panY = State(initialValue: CGFloat(settings.camera3DPanY))
    }
    
    var body: some View {
        ZStack {
            if let bVM = app.boardVM {
                GeometryReader { geo in
                    // Keep board and both lids within the reserved viewport even
                    // when AI narrows it. Camera gestures/preferences stay intact.
                    let playAreaWidth = min(geo.size.width, controlsWidth ?? geo.size.width)
                    let bottomInset = min(geo.size.height * 0.25, playbackHeight + 12)
                    AnimatedBoardViewport(playAreaWidth: playAreaWidth,
                        fittedHeight: min(geo.size.height - bottomInset, playAreaWidth / 1.3),
                        size: geo.size, bottomInset: bottomInset) { fieldOfView in
                    UnifiedInteractiveSceneView(
                        scene: sceneManager.scene,
                    cameraNode: sceneManager.cameraNode,
                    rotationX: $rotX,
                    rotationY: $rotY,
                    distance: $distance,
                    panX: $panX,
                    panY: $panY,
                    verticalFieldOfView: fieldOfView,
                    onHover: { point in
                        guard !sceneManager.isCameraArriving else { return }
                        if let v = UnifiedInteractiveSceneView.lastActiveView,
                           let (c, r) = sceneManager.hitTest(point: point, in: v) {
                            bVM.updateGhostStone(at: BoardPosition(r, c))
                            bVM.hoverAnalysis(at: BoardPosition(r, c))
                            sceneManager.updateBoardCursor(at: BoardPosition(r, c))
                            (v as? UnifiedSCNView)?.setBoardCursorActive(true)
                        } else {
                            sceneManager.updateBoardCursor(at: nil)
                            (UnifiedInteractiveSceneView.lastActiveView as? UnifiedSCNView)?.setBoardCursorActive(false)
                            bVM.clearGhostStone(); bVM.hoverAnalysis(at: nil)
                        }
                    },
                    onClick: { point in
                        guard !sceneManager.finishCameraArrival() else { return }
                        print("🖱 [3D View] Click at \(point)")
                        if let v = UnifiedInteractiveSceneView.lastActiveView,
                           let (c, r) = sceneManager.hitTest(point: point, in: v) {
                            print("🎯 [3D View] Hit Board: \(c),\(r)")
                            let point = BoardPosition(r, c)
                            let color = bVM.engine.turn
                            let previousIndex = bVM.engine.currentIndex
                            sceneManager.prepareGhostPlacement(at: point, color: color)
                            bVM.placeStone(at: point)
                            if bVM.engine.currentIndex == previousIndex + 1,
                               bVM.engine.board.stones[point] == color {
                                bVM.clearGhostStone()
                            } else {
                                sceneManager.cancelGhostPlacement()
                            }
                        } else {
                            print("❌ [3D View] Missed Board")
                        }
                    },
                    onCameraChange: {
                        sceneManager.finishCameraArrival()
                        bVM.cancelVariationPreview()
                        sceneManager.updateCameraPosition(distance: distance, rotationX: rotX, rotationY: rotY, panX: panX, panY: panY)
                        saveViewport()
                    },
                    canStartCameraDrag: { point, view in
                        !sceneManager.isPointOnBoard(point, in: view)
                    },
                    onExit: {
                        sceneManager.updateBoardCursor(at: nil)
                        (UnifiedInteractiveSceneView.lastActiveView as? UnifiedSCNView)?.setBoardCursorActive(false)
                        bVM.clearGhostStone(); bVM.hoverAnalysis(at: nil)
                    },
                    finishCameraArrival: { sceneManager.finishCameraArrival() },
                    onFieldOfViewChange: { sceneManager.updateCameraFieldOfView($0) }
                )
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: AnimatedBoardViewport<EmptyView>.transitionDuration),
                               value: app.isAIAvailable)
                }
                .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    Spacer()
                    PlaybackControlsView(boardVM: bVM).padding(.bottom, 25)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: PlaybackHeightKey.self, value: proxy.size.height)
                        })
                        .frame(width: controlsWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // AppModel does not forward its nested board model's changes.
                // Observe hover directly and update only the ghost, not the board.
                .onReceive(bVM.$ghostPosition.combineLatest(bVM.$ghostColor)) { position, color in
                    sceneManager.updateGhostStone(at: bVM.isPreviewingVariation ? nil : position, color: color, animate: !reduceMotion)
                }

            }
        }
        .onPreferenceChange(PlaybackHeightKey.self) { playbackHeight = $0 }
        .background(Color(nsColor: SceneManager3D.backgroundColor))
        .onDisappear {
            hasPresentedScene = false
            sceneManager.setEnvironmentActive(false)
            (UnifiedInteractiveSceneView.lastActiveView as? UnifiedSCNView)?.updateEnvironmentPlayback()
            app.boardVM?.cancelVariationPreview()
        }
        .focused($isBoardFocused)
        .keyboardShortcuts(boardVM: app.boardVM!, appModel: app)
        .onAppear {
            isBoardFocused = true
            hasPresentedScene = false
            sceneManager.setEnvironmentActive(true)
            resetSeatedCamera()
            updateScene(animateEnvironmentChange: false)
            hasPresentedScene = true
            sceneManager.beginCameraArrival(reduceMotion: reduceMotion,
                renderer: UnifiedInteractiveSceneView.lastActiveView)
        }
        .onReceive(app.recenter3DRequested) { _ in
            resetSeatedCamera(animated: true)
            saveViewport()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { sceneManager.finishCameraArrival() }
            updateScene()
        }
        .onReceive(app.$selection) { _ in
            sceneManager.updateBoardCursor(at: nil)
            (UnifiedInteractiveSceneView.lastActiveView as? UnifiedSCNView)?.setBoardCursorActive(false)
        }
        .onReceive(app.boardVM?.onRequestUpdate3D ?? PassthroughSubject<Void, Never>()) { _ in updateScene() }
        .onReceive(AppSettings.shared.$showBoardGlow) { _ in DispatchQueue.main.async { updateScene() } }
        .onReceive(AppSettings.shared.$showEnhancedGlow) { _ in DispatchQueue.main.async { updateScene() } }
        .onReceive(KataGoEngine.shared.objectWillChange) { _ in DispatchQueue.main.async { updateScene() } }
        // Fallback for other settings
        .onReceive(AppSettings.shared.objectWillChange) { _ in DispatchQueue.main.async { updateScene() } }
        
        // Debug Overlay (Top Left)
        // Debug Overlay Removed
        // VStack {
        //     HStack {
        //         MaterialDebugView(manager: sceneManager)
        //         Spacer()
        //     }
        //     Spacer()
        // }
    }
    
    private func updateScene(animateEnvironmentChange: Bool = true) {
        guard let bVM = app.boardVM else { return }
        // Restoring an existing position is not a sequence of new placements.
        // Also cover initial publisher callbacks that run before onAppear.
        let animateStones = hasPresentedScene && !bVM.isScrubbing && !bVM.isPreviewingVariation && !bVM.restoringVariation
        let environmentChanged = sceneManager.currentEnvironment != AppSettings.shared.environment3D
        sceneManager.updateEnvironment(AppSettings.shared.environment3D,
            flicker: AppSettings.shared.lampFlicker && !reduceMotion, motion: !reduceMotion)
        (UnifiedInteractiveSceneView.lastActiveView as? UnifiedSCNView)?.updateEnvironmentPlayback()

        // Dynamic Resize Check
        sceneManager.updateBoardSize(bVM.boardSize) // Ensure 3D matches 2D physics
        sceneManager.updateBoardCoordinates(AppSettings.shared.showBoardCoordinates)
        if environmentChanged { resetSeatedCamera() }
        
        // Publish a hypothetical stone and its number in the same rendered frame.
        // Neither may inherit an implicit animation from another scene update.
        SCNTransaction.begin()
        if !hasPresentedScene || bVM.isPreviewingVariation || bVM.restoringVariation {
            SCNTransaction.disableActions = true
            SCNTransaction.animationDuration = 0
        }
        sceneManager.updateStones(from: bVM.displayedStones, lastMove: bVM.isPreviewingVariation ? nil : bVM.lastMovePosition, moveIndex: bVM.currentMoveIndex, settings: AppSettings.shared, animate: animateStones, emphasizeLastMove: bVM.emphasizesReviewedMove, settleOnLanding: !reduceMotion)
        sceneManager.updateVariationNumbers(frame: bVM.variationFrame)
        sceneManager.updateOwnershipOverlay(bVM.ownershipEstimates)
        SCNTransaction.commit()
        sceneManager.updateReviewVariations(bVM.reviewVariationChoices)
        sceneManager.updateRecentMoveQuality(bVM.recentMoveQualityMarkers)
        sceneManager.updateSelectedMoveFeedback(bVM.selectedMoveFeedback, at: bVM.lastMovePosition)
        sceneManager.updateCapturedStones(black: bVM.blackCapturedCount, white: bVM.whiteCapturedCount, seed: bVM.engine.captureSeed)
        GoEquipment3D.updateSupplies(in: sceneManager, player: bVM.engine,
            animate: animateStones)
        sceneManager.updateTerritory(points: bVM.isPreviewingVariation ? [:] : bVM.territoryPoints)
        sceneManager.updateKoMarker(at: bVM.isPreviewingVariation ? nil : bVM.koPoint)
        sceneManager.updateCameraPosition(distance: distance, rotationX: rotX, rotationY: rotY, panX: panX, panY: panY)
        sceneManager.updateGhostStone(at: bVM.isPreviewingVariation ? nil : bVM.ghostPosition, color: bVM.ghostColor, animate: !reduceMotion)
        
        // AI Hints
        let isAIAvailable = app.isAIAvailable && !bVM.localScoringVisible && !bVM.isPreviewingVariation
        let turn = bVM.currentMoveIndex
        let analysis = KataGoEngine.shared.currentAnalysisData[turn]
        let moves = bVM.reviewCandidateMoves
        let root = analysis?.rootInfo
        let nextMove = bVM.engine.nextHistoricalMovePosition
        sceneManager.updateAIHints(moves: moves, isAvailable: isAIAvailable, root: root, nextMove: nextMove,
            playedColor: bVM.engine.moveColor(at: turn))
        if environmentChanged && animateEnvironmentChange {
            sceneManager.beginCameraArrival(reduceMotion: reduceMotion,
                renderer: UnifiedInteractiveSceneView.lastActiveView)
        }
    }
    
    private func resetSeatedCamera(animated: Bool = false) {
        if !animated { sceneManager.finishCameraArrival() }
        rotX = SceneManager3D.seatedCameraRotationX; rotY = 0
        distance = SceneManager3D.seatedCameraDistance(boardSize: app.boardVM?.boardSize ?? 19)
        panX = 0; panY = 0
        // Own the camera before cancellation can publish a scene refresh.
        if animated {
            sceneManager.beginCameraRecenter(distance: distance, rotationX: rotX, reduceMotion: reduceMotion)
        } else {
            sceneManager.updateCameraPosition(distance: distance, rotationX: rotX, rotationY: rotY, panX: panX, panY: panY)
        }
        app.boardVM?.clearGhostStone()
        app.boardVM?.cancelVariationPreview()
        sceneManager.updateBoardCursor(at: nil)
        (UnifiedInteractiveSceneView.lastActiveView as? UnifiedSCNView)?.setBoardCursorActive(false)
    }

    private func saveViewport() {
        let settings = AppSettings.shared
        settings.camera3DRotationX = Double(rotX); settings.camera3DRotationY = Double(rotY)
        settings.camera3DDistance = Double(distance); settings.camera3DPanX = Double(panX); settings.camera3DPanY = Double(panY)
    }
}

// MARK: - Native Event Handling Implementation

/// Interpolate the optical center and fitted height on the same animation clock.
/// Compute the height limit before interpolation so the lens eases over the whole
/// transition, instead of waiting until the viewport crosses its aspect limit.
struct AnimatedBoardViewport<Content: View>: View, Animatable {
    static var transitionDuration: TimeInterval { 0.75 }
    var playAreaWidth: CGFloat
    var fittedHeight: CGFloat
    let size: CGSize
    let bottomInset: CGFloat
    @ViewBuilder var content: (CGFloat) -> Content

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(playAreaWidth, fittedHeight) }
        set { playAreaWidth = newValue.first; fittedHeight = newValue.second }
    }

    var body: some View {
        let renderHeight = size.height + bottomInset
        let sceneWidth = size.width * 1.4
        let fieldOfView = 2 * atan(tan(.pi / 6) * renderHeight / max(1, fittedHeight)) * 180 / .pi
        content(fieldOfView)
            .frame(width: sceneWidth, height: renderHeight)
            .offset(x: (playAreaWidth - sceneWidth) / 2, y: -bottomInset)
    }
}

struct UnifiedInteractiveSceneView: NSViewRepresentable {
    let scene: SCNScene; let cameraNode: SCNNode
    @Binding var rotationX: Float; @Binding var rotationY: Float; @Binding var distance: CGFloat; @Binding var panX: CGFloat; @Binding var panY: CGFloat
    var verticalFieldOfView: CGFloat = 60
    var onHover: (CGPoint) -> Void; var onClick: (CGPoint) -> Void; var onCameraChange: () -> Void
    var canStartCameraDrag: (CGPoint, SCNView) -> Bool = { _, _ in true }
    var onExit: () -> Void = {}
    var finishCameraArrival: () -> Bool = { false }
    var onFieldOfViewChange: ((CGFloat) -> Void)?
    static weak var lastActiveView: SCNView?
    
    func makeNSView(context: Context) -> UnifiedSCNView {
        let v = UnifiedSCNView()
        v.scene = scene; v.pointOfView = cameraNode; v.backgroundColor = scene.background.contents as? NSColor ?? SceneManager3D.backgroundColor; v.antialiasingMode = .multisampling4X; v.allowsCameraControl = false
        cameraNode.camera?.projectionDirection = .vertical
        if let onFieldOfViewChange { onFieldOfViewChange(verticalFieldOfView) }
        else { cameraNode.camera?.fieldOfView = verticalFieldOfView }
        // v5.100: Explicitly request best resolution for Retina hit-testing accuracy
        v.wantsBestResolutionOpenGLSurface = true
        v.onInteraction = { event, point in handleInteraction(event: event, point: point, context: context) }
        v.canStartCameraDrag = canStartCameraDrag
        v.finishCameraArrival = finishCameraArrival
        v.updateEnvironmentPlayback()
        UnifiedInteractiveSceneView.lastActiveView = v
        return v
    }
    
    func updateNSView(_ v: UnifiedSCNView, context: Context) {
        if v.scene !== scene { v.scene = scene }
        v.backgroundColor = scene.background.contents as? NSColor ?? SceneManager3D.backgroundColor
        if v.pointOfView !== cameraNode { v.pointOfView = cameraNode }
        cameraNode.camera?.projectionDirection = .vertical
        if let onFieldOfViewChange { onFieldOfViewChange(verticalFieldOfView) }
        else { cameraNode.camera?.fieldOfView = verticalFieldOfView }
        v.onInteraction = { event, point in handleInteraction(event: event, point: point, context: context) }
        v.canStartCameraDrag = canStartCameraDrag
        v.finishCameraArrival = finishCameraArrival
        v.updateEnvironmentPlayback()
        UnifiedInteractiveSceneView.lastActiveView = v
    }

    static func dismantleNSView(_ v: UnifiedSCNView, coordinator: ()) {
        v.stopBoardCursorTracking()
        v.isPlaying = false
        v.rendersContinuously = false
        v.onInteraction = nil
        v.canStartCameraDrag = nil
        v.finishCameraArrival = nil
        v.scene = nil
        if lastActiveView === v { lastActiveView = nil }
    }
    
    private func handleInteraction(event: UnifiedSCNView.EventType, point: CGPoint, context: Context) {
        switch event {
        case .click: onClick(point)
        case .hover: onHover(point)
        case .exit: onExit()
        case .drag(let delta, let modifiers):
            if modifiers.contains(.shift) && modifiers.contains(.control) {
                distance = max(10.0, min(100.0, distance - delta.y * 0.1))
            } else if modifiers.contains(.shift) {
                let sensitivity = distance * 0.002
                panX = max(-60, min(60, panX + delta.x * sensitivity))
                panY = max(-60, min(60, panY - delta.y * sensitivity))
            } else {
                // Controls Fixed (v5.600):
                // Left/Right: Restored to standard Drag (Left = Rotate Left/CCW) (+= delta)
                // Allow a seated, low view of the lunar horizon and room interiors.
                // SceneManager still enforces its camera floor limit.
                rotationX = max(-0.55, min(1.8, rotationX - Float(delta.y) * 0.005))
                rotationY += Float(delta.x) * 0.005
            }
            onCameraChange()
        case .zoom(let amount):
            distance = max(10.0, min(100.0, distance * (1.0 - amount * 0.1))); onCameraChange()
        }
    }
}

class UnifiedSCNView: SCNView, CameraArrivalPlayback {
    /// Scene actions must advance even when the mouse and board are idle.
    /// Respect the environment's visibility and Reduce Motion pause state.
    func updateEnvironmentPlayback() {
        let root = scene?.rootNode
        let displayRunning = root?.childNode(withName: "station-display-clock", recursively: true)?.isPaused == false
        let lampRunning = root?.childNode(withName: "oil-lamp-light", recursively: true)?.action(forKey: "lamp-flicker") != nil
        let arriving = (pointOfView as? SceneManager3D.ArrivalCameraNode)?.isPreparingOrArriving == true
        let running = displayRunning || lampRunning || arriving
        isPlaying = running
        rendersContinuously = running
    }

    enum EventType { case click, hover, exit, drag(delta: CGPoint, modifiers: NSEvent.ModifierFlags), zoom(amount: CGFloat) }
    var onInteraction: ((EventType, CGPoint) -> Void)?
    var canStartCameraDrag: ((CGPoint, SCNView) -> Bool)?
    var finishCameraArrival: (() -> Bool)?
    private var consumedArrivalButton: Int?
    private var consumedArrivalMouseDown = false
    private var cameraDragAllowed = false
    private var lastDragPos: CGPoint = .zero; private var isDragging = false; private var downPos: CGPoint = .zero
    private(set) var usesBoardCursor = false
    // A transparent cursor avoids the process-wide hide/unhide counter. Other
    // controls can replace it normally, and every exit restores the arrow.
    private static let boardCursor = NSCursor(image: NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSGraphicsContext.current?.cgContext.clear(rect)
        return true
    }, hotSpot: .zero)
    private var cursorEventMonitor: Any?
    private var cursorObservers: [NSObjectProtocol] = []

    func setBoardCursorActive(_ active: Bool) {
        if active {
            Self.boardCursor.set()
        } else if usesBoardCursor {
            NSCursor.arrow.set()
        }
        usesBoardCursor = active
    }

    private func pointerIsOverScene(_ event: NSEvent) -> Bool {
        guard event.window === window, let content = window?.contentView,
              let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)) else { return false }
        return hit === self || hit.isDescendant(of: self)
    }

    private func updateBoardHover(with event: NSEvent) {
        guard pointerIsOverScene(event) else {
            setBoardCursorActive(false); onInteraction?(.exit, .zero); return
        }
        onInteraction?(.hover, convert(event.locationInWindow, from: nil))
    }

    func stopBoardCursorTracking() {
        setBoardCursorActive(false)
        onInteraction?(.exit, .zero)
        if let cursorEventMonitor { NSEvent.removeMonitor(cursorEventMonitor) }
        cursorEventMonitor = nil
        consumedArrivalButton = nil
        consumedArrivalMouseDown = false
        cursorObservers.forEach { NotificationCenter.default.removeObserver($0) }
        cursorObservers.removeAll()
    }

    deinit {
        if usesBoardCursor { NSCursor.arrow.set() }
        if let cursorEventMonitor { NSEvent.removeMonitor(cursorEventMonitor) }
        cursorObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { stopBoardCursorTracking() }
        super.viewWillMove(toWindow: newWindow)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopBoardCursorTracking()
        trackingAreas.forEach { removeTrackingArea($0) }
        guard let window else { return }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
        for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject),
                               (NSApplication.didResignActiveNotification, NSApplication.shared as AnyObject)] {
            cursorObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                self?.setBoardCursorActive(false)
                self?.onInteraction?(.exit, .zero)
            })
        }
        cursorEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            guard let event = self.filterCameraArrivalEvent(event) else { return nil }
            guard self.usesBoardCursor else { return event }
            if !self.pointerIsOverScene(event) {
                self.setBoardCursorActive(false)
                self.onInteraction?(.exit, .zero)
            }
            return event
        }
    }

    /// Window-wide, including SwiftUI overlays and the sidebar. Consume the
    /// whole mouse sequence so skipping cannot activate the control underneath.
    func filterCameraArrivalEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if finishCameraArrival?() == true {
                consumedArrivalButton = event.buttonNumber
                setBoardCursorActive(false)
                onInteraction?(.exit, .zero)
                return nil
            }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if consumedArrivalButton == event.buttonNumber {
                consumedArrivalButton = nil
                return nil
            }
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if consumedArrivalButton == event.buttonNumber { return nil }
        default: break
        }
        return event
    }

    override func mouseDown(with event: NSEvent) {
        // Also protect direct native event delivery (without the local monitor).
        consumedArrivalMouseDown = finishCameraArrival?() == true
        if consumedArrivalMouseDown { return }
        let loc = convert(event.locationInWindow, from: nil); lastDragPos = loc; downPos = loc; isDragging = false
        cameraDragAllowed = canStartCameraDrag?(loc, self) ?? true
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard !consumedArrivalMouseDown else { return }
        let loc = convert(event.locationInWindow, from: nil)
        if !isDragging && hypot(loc.x - downPos.x, loc.y - downPos.y) > 3 { isDragging = true }
        if isDragging && cameraDragAllowed {
            setBoardCursorActive(false)
            onInteraction?(.exit, .zero)
            let delta = CGPoint(x: loc.x - lastDragPos.x, y: loc.y - lastDragPos.y)
            onInteraction?(.drag(delta: delta, modifiers: event.modifierFlags), loc)
            lastDragPos = loc
        } else if isDragging {
            updateBoardHover(with: event)
        }
        super.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        if consumedArrivalMouseDown { consumedArrivalMouseDown = false; return }
        if !isDragging {
            let loc = convert(event.locationInWindow, from: nil)
            onInteraction?(.click, loc)
            updateBoardHover(with: event)
        }
        isDragging = false; cameraDragAllowed = false; super.mouseUp(with: event)
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateBoardHover(with: event)
    }
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
        updateBoardHover(with: event)
    }
    override func mouseExited(with event: NSEvent) {
        setBoardCursorActive(false); onInteraction?(.exit, .zero); super.mouseExited(with: event)
    }
    override func scrollWheel(with event: NSEvent) {
        onInteraction?(.zoom(amount: event.deltaY), .zero)
        super.scrollWheel(with: event)
        updateBoardHover(with: event)
    }
}

// MaterialDebugView Removed (v5.500)

private struct PlaybackHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 65
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
