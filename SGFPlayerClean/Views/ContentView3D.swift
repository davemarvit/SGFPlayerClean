// MARK: - File: ContentView3D.swift (v4.974)
import SwiftUI
import SceneKit
import Combine

struct ContentView3D: View {
    @EnvironmentObject var app: AppModel
    @StateObject private var sceneManager = SceneManager3D()
    @FocusState private var isBoardFocused: Bool
    
    // Initialize @State from persisted AppSettings
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
                // 3D Scene Layer
                InteractiveSceneView(scene: sceneManager.scene, cameraNode: sceneManager.cameraNode, sceneManager: sceneManager, boardVM: bVM, rotationX: $rotX, rotationY: $rotY)
                    .edgesIgnoringSafeArea(.all)
                
                // Gesture Overlay with Capture Logic
                CameraControlHandler(
                    rotationX: $rotX,
                    rotationY: $rotY,
                    distance: $distance,
                    panX: $panX,
                    panY: $panY,
                    sceneManager: sceneManager,
                    onInteractionEnded: { saveViewportDefault() }
                )
                
                // UI Overlay Layer
                VStack(spacing: 0) {
                    HStack(spacing: 0) { Color.clear.allowsHitTesting(false); RightPanelView().frame(width: 320) }
                    Spacer(); PlaybackControlsView(boardVM: bVM).padding(.bottom, 25)
                }
            }
        }
        .focused($isBoardFocused)
        .keyboardShortcuts(boardVM: app.boardVM!)
        .onAppear {
            isBoardFocused = true
            updateScene()
        }
        .onReceive(app.boardVM?.onRequestUpdate3D ?? PassthroughSubject<Void, Never>()) { _ in
            updateScene()
        }
    }
    
    private func updateScene() {
        guard let bVM = app.boardVM else { return }
        sceneManager.updateStones(from: bVM.stonesToRender, lastMove: bVM.lastMovePosition, moveIndex: bVM.currentMoveIndex, settings: AppSettings.shared)
        sceneManager.updateCapturedStones(black: bVM.blackCapturedCount, white: bVM.whiteCapturedCount)
        sceneManager.updateCameraPosition(distance: distance, rotationX: rotX, rotationY: rotY, panX: panX, panY: panY)
    }

    private func saveViewportDefault() {
        // Sync the current interactive state back to the persisted Defaults
        let settings = AppSettings.shared
        settings.camera3DRotationX = Double(rotX)
        settings.camera3DRotationY = Double(rotY)
        settings.camera3DDistance = Double(distance)
        settings.camera3DPanX = Double(panX)
        settings.camera3DPanY = Double(panY)
    }
}

struct InteractiveSceneView: NSViewRepresentable {
    let scene: SCNScene; let cameraNode: SCNNode; let sceneManager: SceneManager3D; let boardVM: BoardViewModel
    @Binding var rotationX: Float; @Binding var rotationY: Float
    func makeNSView(context: Context) -> ClickableSCNView {
        let v = ClickableSCNView(); v.scene = scene; v.pointOfView = cameraNode; v.backgroundColor = .black; v.antialiasingMode = .multisampling4X
        v.onClick = { p in if let (c, r) = sceneManager.hitTest(point: p, in: v) { boardVM.placeStone(at: BoardPosition(r, c)) } }
        return v
    }
    func updateNSView(_ v: ClickableSCNView, context: Context) { v.scene = scene; v.pointOfView = cameraNode }
}

class ClickableSCNView: SCNView {
    var onClick: ((CGPoint) -> Void)?
    private var downEvent: NSEvent?
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); for t in self.trackingAreas { self.removeTrackingArea(t) }
        self.addTrackingArea(NSTrackingArea(rect: self.bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .activeAlways], owner: self, userInfo: nil))
    }
    override func mouseDown(with e: NSEvent) { self.downEvent = e; super.mouseDown(with: e) }
    override func mouseUp(with e: NSEvent) { if let d = downEvent { if hypot(d.locationInWindow.x - e.locationInWindow.x, d.locationInWindow.y - e.locationInWindow.y) < 10 { onClick?(self.convert(e.locationInWindow, from: nil)) } }; self.downEvent = nil; super.mouseUp(with: e) }
}
