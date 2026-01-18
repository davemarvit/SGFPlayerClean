// ========================================================
// FILE: ./Views/ContentView3D.swift
// VERSION: v5.100 (Click Debugging)
// ========================================================
import SwiftUI
import SceneKit
import Combine

struct ContentView3D: View {
    @EnvironmentObject var app: AppModel
    @StateObject private var sceneManager = SceneManager3D()
    @FocusState private var isBoardFocused: Bool
    
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
                        } else {
                            bVM.clearGhostStone()
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
                        sceneManager.updateCameraPosition(distance: distance, rotationX: rotX, rotationY: rotY, panX: panX, panY: panY)
                        saveViewport()
                    }
                )
                .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Color.clear.allowsHitTesting(false)
                        RightPanelView().frame(width: 320)
                    }
                    Spacer()
                    PlaybackControlsView(boardVM: bVM).padding(.bottom, 25)
                }
                .onChange(of: bVM.ghostPosition) { _, _ in updateScene() }
                .onChange(of: bVM.ghostColor) { _, _ in updateScene() }
            }
        }
        .focused($isBoardFocused)
        .keyboardShortcuts(boardVM: app.boardVM!)
        .onAppear {
            isBoardFocused = true
            updateScene()
        }
        .onReceive(app.boardVM?.onRequestUpdate3D ?? PassthroughSubject<Void, Never>()) { _ in updateScene() }
        .onReceive(AppSettings.shared.$showBoardGlow) { _ in DispatchQueue.main.async { updateScene() } }
        .onReceive(AppSettings.shared.$showEnhancedGlow) { _ in DispatchQueue.main.async { updateScene() } }
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
        sceneManager.updateStones(from: bVM.stonesToRender, lastMove: bVM.lastMovePosition, moveIndex: bVM.currentMoveIndex, settings: AppSettings.shared)
        sceneManager.updateCapturedStones(black: bVM.blackCapturedCount, white: bVM.whiteCapturedCount)
        sceneManager.updateCameraPosition(distance: distance, rotationX: rotX, rotationY: rotY, panX: panX, panY: panY)
        sceneManager.updateGhostStone(at: bVM.ghostPosition, color: bVM.ghostColor)
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
    static weak var lastActiveView: SCNView?
    
    func makeNSView(context: Context) -> UnifiedSCNView {
        let v = UnifiedSCNView()
        v.scene = scene; v.pointOfView = cameraNode; v.backgroundColor = .black; v.antialiasingMode = .multisampling4X; v.allowsCameraControl = false
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
    
    private func handleInteraction(event: UnifiedSCNView.EventType, point: CGPoint, context: Context) {
        switch event {
        case .click: onClick(point)
        case .hover: onHover(point)
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
    enum EventType { case click, hover, drag(delta: CGPoint, modifiers: NSEvent.ModifierFlags), zoom(amount: CGFloat) }
    var onInteraction: ((EventType, CGPoint) -> Void)?
    private var lastDragPos: CGPoint = .zero; private var isDragging = false; private var downPos: CGPoint = .zero
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let options: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .activeAlways, .inVisibleRect]
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
    override func scrollWheel(with event: NSEvent) { onInteraction?(.zoom(amount: event.deltaY), .zero); super.scrollWheel(with: event) }
}

// MaterialDebugView Removed (v5.500)
