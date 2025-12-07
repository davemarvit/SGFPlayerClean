//
//  ContentView3D.swift
//  SGFPlayerClean
//
//  Updated:
//  1. Mouse Drag Inverted (Grabbing the board).
//  2. Added comments for adjusting Transparency/Backgrounds.
//

import SwiftUI
import SceneKit

struct ContentView3D: View {

    // MARK: - Dependencies
    @ObservedObject var app: AppModel
    @ObservedObject var boardVM: BoardViewModel
    @StateObject private var sceneManager: SceneManager3D
    @ObservedObject private var settings = AppSettings.shared

    // MARK: - Camera State
    @State private var cameraPanX: CGFloat = 4.0
    @State private var cameraPanY: CGFloat = -4.48
    @State private var cameraDistance: CGFloat = 25.0
    @State private var currentRotationX: Float = -0.7
    @State private var currentRotationY: Float = 0.0
    
    // MARK: - UI State
    @State private var showSettings = false
    @State private var buttonsVisible = true
    @State private var fadeTimer: Timer?

    // MARK: - Initialization
    init(app: AppModel) {
        self.app = app
        self.boardVM = app.boardVM!
        
        _sceneManager = StateObject(wrappedValue: {
            let manager = SceneManager3D()
            manager.settings = AppSettings.shared
            manager.boardVM = app.boardVM!
            return manager
        }())
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            // LAYER 1: 3D SCENE (Bottom)
            sceneView
                .edgesIgnoringSafeArea(.all)

            // LAYER 2: LAYOUT STRUCTURE (Middle)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // LEFT: Invisible Touch Pass-through
                    Color.clear
                        .frame(width: geometry.size.width * 0.7)
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                    
                    // RIGHT: Panel
                    RightPanelView(app: app, boardVM: boardVM)
                        .frame(width: geometry.size.width * 0.3)
                        
                        // MARK: - TRANSPARENCY CUSTOMIZATION
                        // The panel currently uses .frostedGlassStyle() internally.
                        // To make it MORE transparent:
                        // 1. Go to RightPanelView.swift and reduce opacity in the modifiers there.
                        // 2. OR: Uncomment the line below to force a barely-visible background here:
                        // .background(Color.black.opacity(0.1))
                        
                        // To make it LESS transparent (Darker):
                        // .background(Color.black.opacity(0.5))
                }
            }
            
            // LAYER 3: FLOATING CONTROLS (Top)
            GeometryReader { geometry in
                // A. Top-Left Buttons
                VStack {
                    SharedOverlays(
                        showSettings: $showSettings,
                        buttonsVisible: $buttonsVisible,
                        app: app
                    )
                    Spacer()
                }
                
                // B. Bottom-Center Playback
                VStack {
                    Spacer()
                    PlaybackControls(boardVM: boardVM)
                        .padding(.bottom, 40)
                }
                .frame(width: geometry.size.width * 0.7)
                .allowsHitTesting(true)
                
                // C. Version Label
                VStack {
                    Spacer()
                    HStack {
                        Text("v1.0.49-CLEAN (3D)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.leading, 30)
                            .padding(.bottom, 15)
                        Spacer()
                    }
                }
                .allowsHitTesting(false)
            }
        }
        // LIFECYCLE & EVENTS
        .onAppear {
            setupScene()
            resetFadeTimer()
            if let game = app.selection {
                if boardVM.currentGame?.id != game.id {
                    boardVM.loadGame(game)
                }
                updateScene()
            }
        }
        .onDisappear {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
        .onContinuousHover { phase in handleMouseMove(phase) }
        .keyboardShortcuts(boardVM: boardVM)
        .onChange(of: geometrySizeWrapper) { _, newSize in adjustCameraForSize(newSize) }
        .onChange(of: boardVM.currentMoveIndex) { _, _ in updateScene() }
        .onChange(of: settings.showBoardGlow) { _, _ in updateScene() }
        .onChange(of: currentRotationX) { _, _ in updateCamera() }
        .onChange(of: currentRotationY) { _, _ in updateCamera() }
        .onChange(of: cameraDistance) { _, _ in updateCamera() }
        
        // SYNC GHOST
        .onChange(of: boardVM.ghostPosition) { _, pos in
            if let pos = pos {
                sceneManager.updateGhost(at: pos.col, row: pos.row, color: boardVM.ghostColor)
            } else {
                sceneManager.hideGhost()
            }
        }
    }
    
    // Geometry Helper
    @State private var viewSize: CGSize = .zero
    private var geometrySizeWrapper: CGSize { viewSize }

    // MARK: - Logic
    private func adjustCameraForSize(_ size: CGSize) {
        guard size.height > 0 else { return }
        if size != viewSize { viewSize = size }
        
        let availableWidth = size.width * 0.7
        let panelAspect = availableWidth / size.height
        let targetBoardAspect: CGFloat = 1.1
        let baseDistance: CGFloat = 25.0
        
        withAnimation(.easeOut(duration: 0.2)) {
            cameraDistance = (panelAspect < targetBoardAspect) ? baseDistance * (targetBoardAspect / panelAspect) : baseDistance
        }
    }

    private var sceneView: some View {
        InteractiveSceneView(
            scene: sceneManager.scene,
            cameraNode: sceneManager.cameraNode,
            sceneManager: sceneManager,
            boardVM: boardVM,
            rotationX: $currentRotationX,
            rotationY: $currentRotationY
        )
    }

    private func setupScene() { updateCamera(); updateScene() }
    
    private func updateCamera() {
        sceneManager.updateCameraPosition(distance: cameraDistance, rotationX: currentRotationX, rotationY: currentRotationY, panX: cameraPanX, panY: cameraPanY)
    }

    private func updateScene() {
        let lastMove = boardVM.lastMovePosition.map { (x: $0.col, y: $0.row) }
        sceneManager.updateStones(from: app.player.board, lastMove: lastMove)
        sceneManager.updateCapturedStones(blackCaptured: boardVM.blackCapturedCount, whiteCaptured: boardVM.whiteCapturedCount)
    }

    private func handleMouseMove(_ phase: HoverPhase) {
        if case .active = phase, !buttonsVisible {
            withAnimation(.easeIn(duration: 0.2)) { buttonsVisible = true }
        }
        resetFadeTimer()
    }

    private func resetFadeTimer() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.5)) { buttonsVisible = false }
        }
    }
}

// MARK: - Interactive Scene View (Handles Input)
struct InteractiveSceneView: NSViewRepresentable {
    let scene: SCNScene
    let cameraNode: SCNNode
    let sceneManager: SceneManager3D
    let boardVM: BoardViewModel
    
    @Binding var rotationX: Float
    @Binding var rotationY: Float

    func makeNSView(context: Context) -> ClickableSCNView {
        let view = ClickableSCNView()
        view.scene = scene
        view.pointOfView = cameraNode
        view.allowsCameraControl = false
        view.backgroundColor = NSColor.black
        
        // CLICK
        view.onClick = { point in
            if let (col, row) = sceneManager.hitTest(point: point, in: view) {
                boardVM.placeStone(at: BoardPosition(row, col))
            }
        }
        
        // HOVER
        view.onHover = { point in
            if let (col, row) = sceneManager.hitTest(point: point, in: view) {
                DispatchQueue.main.async { boardVM.updateGhostStone(at: BoardPosition(row, col)) }
            } else {
                DispatchQueue.main.async { boardVM.clearGhostStone() }
            }
        }
        
        // DRAG (INVERTED for "Grab Object" feel)
        view.onDrag = { deltaX, deltaY in
            let sensitivity: Float = 0.005
            DispatchQueue.main.async {
                // Inverted signs (-= instead of +=) so dragging LEFT rotates board LEFT
                rotationY -= Float(deltaX) * sensitivity
                
                // Inverted signs (- instead of +) so dragging UP tilts board UP
                let newX = rotationX - Float(deltaY) * sensitivity
                rotationX = max(-1.4, min(-0.1, newX))
            }
        }
        
        return view
    }

    func updateNSView(_ nsView: ClickableSCNView, context: Context) {
        nsView.scene = scene
        nsView.pointOfView = cameraNode
    }
    
    // Subclass to capture mouse events
    class ClickableSCNView: SCNView {
        var onClick: ((CGPoint) -> Void)?
        var onDrag: ((CGFloat, CGFloat) -> Void)?
        var onHover: ((CGPoint) -> Void)?
        
        private var mouseDownEvent: NSEvent?
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for trackingArea in self.trackingAreas { self.removeTrackingArea(trackingArea) }
            let options: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .activeAlways]
            let trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
            self.addTrackingArea(trackingArea)
        }
        
        override func mouseDown(with event: NSEvent) {
            self.mouseDownEvent = event
            super.mouseDown(with: event)
        }
        
        override func mouseUp(with event: NSEvent) {
            if let downEvent = mouseDownEvent {
                let p1 = downEvent.locationInWindow
                let p2 = event.locationInWindow
                let dist = hypot(p1.x - p2.x, p1.y - p2.y)
                if dist < 10.0 {
                    let location = self.convert(event.locationInWindow, from: nil)
                    onClick?(location)
                }
            }
            self.mouseDownEvent = nil
            super.mouseUp(with: event)
        }
        
        override func mouseDragged(with event: NSEvent) {
            onDrag?(event.deltaX, event.deltaY)
            super.mouseDragged(with: event)
        }
        
        override func mouseMoved(with event: NSEvent) {
            let location = self.convert(event.locationInWindow, from: nil)
            onHover?(location)
            super.mouseMoved(with: event)
        }
    }
}
