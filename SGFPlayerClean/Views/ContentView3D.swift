// ========================================================
// FILE: ./Views/ContentView3D.swift
// VERSION: v5.100 (Click Debugging)
// ========================================================
import SwiftUI
import SceneKit
import Combine

struct ContentView3D: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.boardControlsWidth) private var controlsWidth
    @StateObject private var sceneManager = SceneManager3D()
    @FocusState private var isBoardFocused: Bool
    
    // Camera State
    @State private var rotX: Float
    @State private var rotY: Float
    @State private var distance: CGFloat
    @State private var panX: CGFloat
    @State private var panY: CGFloat
    
    private let boardAspectRatio: CGFloat = 1.0773
    private func getLayout(area: CGSize) -> (bW: CGFloat, bH: CGFloat, lidD: CGFloat, gap: CGFloat) {
        let totalWFactor: CGFloat = 1.30 
        let bH = min((area.width * 0.92 / totalWFactor) * boardAspectRatio, area.height * 0.85)
        let bW = bH / boardAspectRatio
        return (bW, bH, bH / 3.0, bW / 19.0)
    }
    
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
                    let sceneHeight = min(geo.size.height, geo.size.width / 1.3)
                    UnifiedInteractiveSceneView(
                        scene: sceneManager.scene,
                    cameraNode: sceneManager.cameraNode,
                    rotationX: $rotX,
                    rotationY: $rotY,
                    distance: $distance,
                    panX: $panX,
                    panY: $panY,
                    onHover: { point in
                        if let v = UnifiedInteractiveSceneView.lastActiveView,
                           let (c, r) = sceneManager.hitTest(point: point, in: v) {
                            bVM.updateGhostStone(at: BoardPosition(r, c))
                            bVM.hoverAnalysis(at: BoardPosition(r, c))
                        } else {
                            bVM.clearGhostStone(); bVM.hoverAnalysis(at: nil)
                        }
                    },
                    onClick: { point in
                        print("🖱 [3D View] Click at \(point)")
                        if let v = UnifiedInteractiveSceneView.lastActiveView,
                           let (c, r) = sceneManager.hitTest(point: point, in: v) {
                            print("🎯 [3D View] Hit Board: \(c),\(r)")
                            bVM.placeStone(at: BoardPosition(r, c))
                        } else {
                            print("❌ [3D View] Missed Board")
                        }
                    },
                    onCameraChange: {
                        bVM.cancelVariationPreview()
                        sceneManager.updateCameraPosition(distance: distance, rotationX: rotX, rotationY: rotY, panX: panX, panY: panY)
                        saveViewport()
                    },
                    onExit: { bVM.clearGhostStone(); bVM.hoverAnalysis(at: nil) }
                )
                .frame(width: geo.size.width * 1.4, height: sceneHeight)
                // With analysis over the lids, use more of the left margin to keep
                // the enlarged board clear of the overlay, including portrait windows.
                .offset(x: -(geo.size.width * (app.showsAnalysisWorkspace ? 0.32 : 0.29)), y: (geo.size.height - sceneHeight) / 2)
                }
                .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    Spacer()
                    PlaybackControlsView(boardVM: bVM).padding(.bottom, 25)
                        .frame(width: controlsWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: bVM.ghostPosition) { _, _ in updateScene() }
                .onChange(of: bVM.ghostColor) { _, _ in updateScene() }
                
                // Floating Metadata + AI Table (Aligned identically to 2D)
                if !app.showsAnalysisWorkspace, let game = app.selection {
                    GeometryReader { geo in
                        let L = getLayout(area: geo.size)
                        let margin = L.bW * 0.065
                        
                        VStack(spacing: 0) {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(alignment: .top, spacing: L.gap) {
                                    Color.clear.frame(width: L.bW, height: L.bH) // Fake Board
                                VStack(spacing: 0) {
                                    Color.clear.frame(width: L.lidD, height: L.lidD).padding(.top, margin - (L.lidD / 2))
                                    
                                    HStack(alignment: .center, spacing: 12) {
                                        LocalGameMetadataView(game: game, boardVM: bVM, isOverlay: true)
                                            .scaleEffect(0.9)
                                            .fixedSize()
                                        

                                    }
                                    .frame(width: L.lidD, alignment: .leading)
                                    .offset(y: -45)
                                    .frame(height: 80)
                                    
                                    Spacer()
                                    Color.clear.frame(width: L.lidD, height: L.lidD).padding(.bottom, margin - (L.lidD / 2))
                                }
                                .frame(height: L.bH)
                                }
                                .frame(width: L.bW + L.gap + L.lidD)
                                .padding(.trailing, 100) // Nudge
                                
                                Spacer()
                            }
                            Spacer()
                            
                            // Emulate 2D bottom constraint exactly so Spacers share identical math
                            PlaybackControlsView(boardVM: bVM)
                                .padding(EdgeInsets(top: 0, leading: 0, bottom: 25, trailing: 0))
                                .opacity(0)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                }

            }
        }
        .background(Color(nsColor: SceneManager3D.backgroundColor))
        .onDisappear { app.boardVM?.cancelVariationPreview() }
        .focused($isBoardFocused)
        .keyboardShortcuts(boardVM: app.boardVM!, appModel: app)
        .onAppear {
            isBoardFocused = true
            updateScene()
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
    
    private func updateScene() {
        guard let bVM = app.boardVM else { return }
        
        // Dynamic Resize Check
        sceneManager.updateBoardSize(bVM.boardSize) // Ensure 3D matches 2D physics
        
        sceneManager.updateStones(from: bVM.displayedStones, lastMove: bVM.isPreviewingVariation ? nil : bVM.lastMovePosition, moveIndex: bVM.currentMoveIndex, settings: AppSettings.shared, animate: !bVM.isScrubbing && !bVM.isPreviewingVariation && !bVM.restoringVariation)
        sceneManager.updateVariationNumbers(frame: bVM.variationFrame)
        sceneManager.updateCapturedStones(black: bVM.blackCapturedCount, white: bVM.whiteCapturedCount)
        sceneManager.updateTerritory(points: bVM.isPreviewingVariation ? [:] : bVM.territoryPoints)
        sceneManager.updateKoMarker(at: bVM.isPreviewingVariation ? nil : bVM.koPoint)
        sceneManager.updateCameraPosition(distance: distance, rotationX: rotX, rotationY: rotY, panX: panX, panY: panY)
        sceneManager.updateGhostStone(at: bVM.isPreviewingVariation ? nil : bVM.ghostPosition, color: bVM.ghostColor)
        
        // AI Hints
        let isAIAvailable = app.isAIAvailable && !bVM.localScoringVisible && !bVM.isPreviewingVariation
        let turn = bVM.currentMoveIndex
        let analysis = KataGoEngine.shared.currentAnalysisData[turn]
        let moves = analysis?.moveInfos ?? []
        let root = analysis?.rootInfo
        let nextMove = bVM.engine.nextHistoricalMovePosition
        sceneManager.updateAIHints(moves: moves, isAvailable: isAIAvailable, root: root, nextMove: nextMove)
    }
    
    private func saveViewport() {
        let settings = AppSettings.shared
        settings.camera3DRotationX = Double(rotX); settings.camera3DRotationY = Double(rotY)
        settings.camera3DDistance = Double(distance); settings.camera3DPanX = Double(panX); settings.camera3DPanY = Double(panY)
    }
}

// MARK: - Native Event Handling Implementation

struct UnifiedInteractiveSceneView: NSViewRepresentable {
    let scene: SCNScene; let cameraNode: SCNNode
    @Binding var rotationX: Float; @Binding var rotationY: Float; @Binding var distance: CGFloat; @Binding var panX: CGFloat; @Binding var panY: CGFloat
    var onHover: (CGPoint) -> Void; var onClick: (CGPoint) -> Void; var onCameraChange: () -> Void
    var onExit: () -> Void = {}
    static weak var lastActiveView: SCNView?
    
    func makeNSView(context: Context) -> UnifiedSCNView {
        let v = UnifiedSCNView()
        v.scene = scene; v.pointOfView = cameraNode; v.backgroundColor = SceneManager3D.backgroundColor; v.antialiasingMode = .multisampling4X; v.allowsCameraControl = false
        // v5.100: Explicitly request best resolution for Retina hit-testing accuracy
        v.wantsBestResolutionOpenGLSurface = true
        v.onInteraction = { event, point in handleInteraction(event: event, point: point, context: context) }
        UnifiedInteractiveSceneView.lastActiveView = v
        return v
    }
    
    func updateNSView(_ v: UnifiedSCNView, context: Context) {
        v.scene = scene; v.pointOfView = cameraNode
        v.onInteraction = { event, point in handleInteraction(event: event, point: point, context: context) }
        UnifiedInteractiveSceneView.lastActiveView = v
    }

    static func dismantleNSView(_ v: UnifiedSCNView, coordinator: ()) {
        v.isPlaying = false
        v.onInteraction = nil
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
            } else {
                // Controls Fixed (v5.600):
                // Left/Right: Restored to standard Drag (Left = Rotate Left/CCW) (+= delta)
                // Up/Down: Drag UP tilts board UP (Skimming View). Range expanded (-0.2 to 1.8).
                rotationX = max(-0.2, min(1.8, rotationX - Float(delta.y) * 0.005))
                rotationY += Float(delta.x) * 0.005
            }
            onCameraChange()
        case .zoom(let amount):
            distance = max(10.0, min(100.0, distance * (1.0 - amount * 0.1))); onCameraChange()
        }
    }
}

class UnifiedSCNView: SCNView {
    enum EventType { case click, hover, exit, drag(delta: CGPoint, modifiers: NSEvent.ModifierFlags), zoom(amount: CGFloat) }
    var onInteraction: ((EventType, CGPoint) -> Void)?
    private var lastDragPos: CGPoint = .zero; private var isDragging = false; private var downPos: CGPoint = .zero
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil); lastDragPos = loc; downPos = loc; isDragging = false; super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if !isDragging && hypot(loc.x - downPos.x, loc.y - downPos.y) > 3 { isDragging = true }
        if isDragging {
            let delta = CGPoint(x: loc.x - lastDragPos.x, y: loc.y - lastDragPos.y)
            onInteraction?(.drag(delta: delta, modifiers: event.modifierFlags), loc)
            lastDragPos = loc
        }
        super.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            let loc = convert(event.locationInWindow, from: nil)
            onInteraction?(.click, loc)
        }
        isDragging = false; super.mouseUp(with: event)
    }
    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        onInteraction?(.hover, loc)
        super.mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) { onInteraction?(.exit, .zero); super.mouseExited(with: event) }
    override func scrollWheel(with event: NSEvent) { onInteraction?(.zoom(amount: event.deltaY), .zero); super.scrollWheel(with: event) }
}

// MaterialDebugView Removed (v5.500)
