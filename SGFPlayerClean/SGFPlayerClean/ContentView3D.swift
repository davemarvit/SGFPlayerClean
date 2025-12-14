//
//  ContentView3D.swift
//  SGFPlayerClean
//
//  Updated (v3.41):
//  - Fixes Build Error: Corrects BoardSnapshot init signature.
//  - Ensures 3D view reflects Online State.
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
            // LAYER 1: 3D SCENE
            sceneView
                .edgesIgnoringSafeArea(.all)

            // LAYER 2: LAYOUT
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: geometry.size.width * 0.7)
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                    
                    RightPanelView(app: app, boardVM: boardVM)
                        .frame(width: geometry.size.width * 0.3)
                }
            }
            
            // LAYER 3: FLOATING CONTROLS
            GeometryReader { geometry in
                VStack {
                    SharedOverlays(
                        showSettings: $showSettings,
                        buttonsVisible: $buttonsVisible,
                        app: app
                    )
                    Spacer()
                }
                
                VStack {
                    Spacer()
                    PlaybackControls(boardVM: boardVM)
                        .padding(.bottom, 40)
                }
                .frame(width: geometry.size.width * 0.7)
                .allowsHitTesting(true)
            }
        }
        // LIFECYCLE
        .onAppear {
            setupScene()
            resetFadeTimer()
            if let game = app.selection {
                if boardVM.currentGame?.id != game.id {
                    boardVM.loadGame(game)
                }
            }
            updateScene()
        }
        .onDisappear {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
        .onContinuousHover { phase in handleMouseMove(phase) }
        .keyboardShortcuts(boardVM: boardVM)
        .onChange(of: geometrySizeWrapper) { _, newSize in adjustCameraForSize(newSize) }
        
        // OBSERVING STONES (Fix for Invisible Stones)
        .onChange(of: boardVM.stones) { _, _ in updateScene() }
        
        .onChange(of: boardVM.currentMoveIndex) { _, _ in updateScene() }
        .onChange(of: settings.showBoardGlow) { _, _ in updateScene() }
        .onChange(of: currentRotationX) { _, _ in updateCamera() }
        .onChange(of: currentRotationY) { _, _ in updateCamera() }
        .onChange(of: cameraDistance) { _, _ in updateCamera() }
        
        .onChange(of: boardVM.ghostPosition) { _, pos in
            if let pos = pos {
                sceneManager.updateGhost(at: pos.col, row: pos.row, color: boardVM.ghostColor)
            } else {
                sceneManager.hideGhost()
            }
        }
    }
    
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

    // CRITICAL FIX: Convert Dictionary to Snapshot using correct signature
    private func updateScene() {
        let lastMove = boardVM.lastMovePosition.map { (x: $0.col, y: $0.row) }
        
        // 1. Create a blank grid
        var grid = [[Stone?]](repeating: [Stone?](repeating: nil, count: boardVM.boardSize), count: boardVM.boardSize)
        
        // 2. Populate from boardVM.stones (Source of Truth)
        for (pos, stone) in boardVM.stones {
            if pos.row < boardVM.boardSize && pos.col < boardVM.boardSize {
                grid[pos.row][pos.col] = stone
            }
        }
        
        // 3. Create Snapshot (Fixed init signature)
        let snapshot = BoardSnapshot(size: boardVM.boardSize, grid: grid)
        
        // 4. Pass to Manager
        sceneManager.updateStones(from: snapshot, lastMove: lastMove)
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

// MARK: - Interactive Scene View
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
        
        view.onClick = { point in
            if let (col, row) = sceneManager.hitTest(point: point, in: view) {
                boardVM.placeStone(at: BoardPosition(row, col))
            }
        }
        
        view.onHover = { point in
            if let (col, row) = sceneManager.hitTest(point: point, in: view) {
                DispatchQueue.main.async { boardVM.updateGhostStone(at: BoardPosition(row, col)) }
            } else {
                DispatchQueue.main.async { boardVM.clearGhostStone() }
            }
        }
        
        view.onDrag = { deltaX, deltaY in
            let sensitivity: Float = 0.005
            DispatchQueue.main.async {
                rotationY -= Float(deltaX) * sensitivity
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
                if hypot(p1.x - p2.x, p1.y - p2.y) < 10.0 {
                    onClick?(self.convert(event.locationInWindow, from: nil))
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
            onHover?(self.convert(event.locationInWindow, from: nil))
            super.mouseMoved(with: event)
        }
    }
} 
