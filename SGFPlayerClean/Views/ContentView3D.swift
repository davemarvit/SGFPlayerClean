// MARK: - File: ContentView3D.swift (v3.360)
import SwiftUI
import SceneKit

struct ContentView3D: View {
    @EnvironmentObject var app: AppModel
    @StateObject private var sceneManager = SceneManager3D()
    @ObservedObject private var settings = AppSettings.shared

    @State private var cameraPanX: CGFloat = 4.0
    @State private var cameraPanY: CGFloat = -4.48
    @State private var cameraDistance: CGFloat = 25.0
    @State private var currentRotationX: Float = -0.7
    @State private var currentRotationY: Float = 0.0
    
    var body: some View {
        ZStack {
            if let boardVM = app.boardVM {
                InteractiveSceneView(
                    scene: sceneManager.scene,
                    cameraNode: sceneManager.cameraNode,
                    sceneManager: sceneManager,
                    boardVM: boardVM,
                    rotationX: $currentRotationX,
                    rotationY: $currentRotationY
                ).edgesIgnoringSafeArea(.all)

                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Color.clear.frame(width: geometry.size.width * 0.7).allowsHitTesting(false)
                        RightPanelView().frame(width: geometry.size.width * 0.3)
                    }
                }
            }
        }
        .onAppear { setupScene() }
        .onChange(of: app.boardVM?.stones) { _, _ in updateScene() }
    }

    private func setupScene() {
        if let vm = app.boardVM {
            sceneManager.boardVM = vm
            updateCamera()
            updateScene()
        }
    }
    
    private func updateCamera() {
        sceneManager.updateCameraPosition(distance: cameraDistance, rotationX: currentRotationX, rotationY: currentRotationY, panX: cameraPanX, panY: cameraPanY)
    }

    private func updateScene() {
        guard let boardVM = app.boardVM else { return }
        let lastMove = boardVM.lastMovePosition.map { (x: $0.col, y: $0.row) }
        var grid = [[Stone?]](repeating: [Stone?](repeating: nil, count: boardVM.boardSize), count: boardVM.boardSize)
        for (pos, stone) in boardVM.stones { if pos.row < boardVM.boardSize && pos.col < boardVM.boardSize { grid[pos.row][pos.col] = stone } }
        sceneManager.updateStones(from: BoardSnapshot(size: boardVM.boardSize, grid: grid), lastMove: lastMove)
    }
}

// InteractiveSceneView must be in scope
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
        view.backgroundColor = .black
        view.onClick = { point in
            if let (col, row) = sceneManager.hitTest(point: point, in: view) {
                boardVM.placeStone(at: BoardPosition(row, col))
            }
        }
        view.onHover = { point in
            if let (col, row) = sceneManager.hitTest(point: point, in: view) {
                boardVM.updateGhostStone(at: BoardPosition(row, col))
            } else {
                boardVM.clearGhostStone()
            }
        }
        view.onDrag = { deltaX, deltaY in
            let sensitivity: Float = 0.005
            rotationY -= Float(deltaX) * sensitivity
            let newX = rotationX - Float(deltaY) * sensitivity
            rotationX = max(-1.4, min(-0.1, newX))
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
            let trackingArea = NSTrackingArea(rect: self.bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .activeAlways], owner: self, userInfo: nil)
            self.addTrackingArea(trackingArea)
        }
        override func mouseDown(with event: NSEvent) { self.mouseDownEvent = event; super.mouseDown(with: event) }
        override func mouseUp(with event: NSEvent) {
            if let down = mouseDownEvent {
                let p1 = down.locationInWindow, p2 = event.locationInWindow
                if hypot(p1.x - p2.x, p1.y - p2.y) < 10.0 { onClick?(self.convert(event.locationInWindow, from: nil)) }
            }
            self.mouseDownEvent = nil; super.mouseUp(with: event)
        }
        override func mouseDragged(with event: NSEvent) { onDrag?(event.deltaX, event.deltaY); super.mouseDragged(with: event) }
        override func mouseMoved(with event: NSEvent) { onHover?(self.convert(event.locationInWindow, from: nil)); super.mouseMoved(with: event) }
    }
}
