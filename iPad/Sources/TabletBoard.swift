import SwiftUI
import SceneKit

struct TabletBoard2D: View {
    @ObservedObject var game: TabletGame
    let portrait: Bool
    var body: some View {
        GeometryReader { proxy in
            let layout = TabletTableLayout(size: proxy.size, portrait: portrait)
            let board = layout.board
            let spacing = board.width * 0.87 / CGFloat(game.player.board.size - 1)
            let rowSpacing = board.height * 0.87 / CGFloat(game.player.board.size - 1)
            let origin = CGPoint(x: board.minX + board.width * 0.065, y: board.minY + board.height * 0.065)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    // Use the shared tatami artwork and physical scale; the iPad owns only its drawing adapter.
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.54, green: 0.55, blue: 0.36)))
                    let tile = TatamiTexture.tileSide(boardHeight: board.height)
                    if let tatami = UIImage(named: TatamiTexture.assetName), tile > 0 {
                        for row in 0..<Int(ceil(size.height / tile)) {
                            for col in 0..<Int(ceil(size.width / tile)) {
                                var floor = context
                                let mirrorX = col % 2 == 1, mirrorY = row % 2 == 1
                                floor.translateBy(x: CGFloat(col + (mirrorX ? 1 : 0)) * tile, y: CGFloat(row + (mirrorY ? 1 : 0)) * tile)
                                floor.scaleBy(x: mirrorX ? -1 : 1, y: mirrorY ? -1 : 1)
                                floor.draw(Image(uiImage: tatami), in: CGRect(x: 0, y: 0, width: tile, height: tile))
                            }
                        }
                    }
                    context.fill(Path(roundedRect: board, cornerRadius: 8), with: .color(Color(red: 0.78, green: 0.58, blue: 0.31)))
                    if let wood = UIImage(named: "board_kaya.jpg") { context.draw(Image(uiImage: wood), in: board) }
                    var lines = Path()
                    let count = game.player.board.size
                    for i in 0..<count {
                        let dx = CGFloat(i) * spacing, dy = CGFloat(i) * rowSpacing
                        lines.move(to: CGPoint(x: origin.x+dx, y: origin.y)); lines.addLine(to: CGPoint(x: origin.x+dx, y: origin.y+CGFloat(count-1)*rowSpacing))
                        lines.move(to: CGPoint(x: origin.x, y: origin.y+dy)); lines.addLine(to: CGPoint(x: origin.x+CGFloat(count-1)*spacing, y: origin.y+dy))
                    }
                    context.stroke(lines, with: .color(.black.opacity(0.8)), lineWidth: 0.8)
                    let stars = count == 19 ? [3,9,15] : count == 13 ? [3,6,9] : count == 9 ? [2,4,6] : []
                    for row in stars { for col in stars {
                        context.fill(Path(ellipseIn: CGRect(x: origin.x+CGFloat(col)*spacing-2, y: origin.y+CGFloat(row)*rowSpacing-2, width: 4,height:4)),with:.color(.black))
                    }}
                    for (point, stone) in game.player.board.stones {
                        let center = CGPoint(x: origin.x+CGFloat(point.col)*spacing, y: origin.y+CGFloat(point.row)*rowSpacing)
                        let rect = CGRect(x: center.x-spacing*0.47, y: center.y-spacing*0.47, width: spacing*0.94,height:spacing*0.94)
                        var c = context
                        if game.deadStones.contains(point) { c.opacity = 0.35 }
                        c.addFilter(.shadow(color: .black.opacity(0.5),radius:2,x:1,y:2))
                        let texture = stone == .black ? "stone_black.png" : String(format:"clam_%02d.png", (point.row*31+point.col)%5+1)
                        if let image=UIImage(named:texture) { c.draw(Image(uiImage:image),in:rect) }
                        else {
                        c.fill(Path(ellipseIn:rect),with:.radialGradient(Gradient(colors:stone == .black ? [.gray,.black] : [.white,Color(white:0.7)]),center:CGPoint(x:center.x-spacing*0.15,y:center.y-spacing*0.2),startRadius:0,endRadius:spacing*0.7))
                        }
                        if game.player.lastMove.map({ $0.x == point.col && $0.y == point.row }) == true {
                            context.stroke(Path(ellipseIn:rect.insetBy(dx:spacing*0.32,dy:spacing*0.32)),with:.color(.red),lineWidth:2)
                        }
                    }
                    if game.mode == .review, game.scoring == nil {
                        for choice in game.tree.boardVariations where game.player.board.stones[choice.position] == nil {
                            let center = CGPoint(x: origin.x + CGFloat(choice.position.col) * spacing, y: origin.y + CGFloat(choice.position.row) * rowSpacing)
                            let rect = CGRect(x: center.x - spacing * 0.47, y: center.y - spacing * 0.47, width: spacing * 0.94, height: spacing * 0.94)
                            context.fill(Path(ellipseIn: rect), with: .color((choice.color == .black ? Color.black : .white).opacity(0.48)))
                        }
                    }
                    for (point, owner) in game.territory {
                        let rect=CGRect(x:origin.x+CGFloat(point.col)*spacing-spacing*0.14,y:origin.y+CGFloat(point.row)*rowSpacing-spacing*0.14,width:spacing*0.28,height:spacing*0.28)
                        context.fill(Path(rect),with:.color(owner == .black ? .black : .white))
                    }
                    if let point = game.selectedPoint {
                        let rect=CGRect(x:origin.x+CGFloat(point.col)*spacing-spacing*0.48,y:origin.y+CGFloat(point.row)*rowSpacing-spacing*0.48,width:spacing*0.96,height:spacing*0.96)
                        context.fill(Path(ellipseIn:rect),with:.color((game.player.turn == .black ? Color.black : .white).opacity(0.5)))
                        context.stroke(Path(ellipseIn:rect),with:.color(.cyan),lineWidth:2)
                    }
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                Color.clear
                    .frame(width: board.width, height: board.height)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { event in
                        let point = CGPoint(x: event.location.x + layout.board.minX, y: event.location.y + layout.board.minY)
                        if let intersection = layout.intersection(at: point, boardSize: game.player.board.size) {
                            game.tap(at: intersection)
                        }
                    })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Go board, \(game.player.board.size) by \(game.player.board.size)")
                    .accessibilityIdentifier("board2D")
                    .position(x: layout.board.midX, y: layout.board.midY)
                TabletEquipment(player: game.player, layout: layout)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct TabletBoard3D: UIViewRepresentable {
    @ObservedObject var game: TabletGame
    let environment: PlayingEnvironment
    let active: Bool
    let recenter: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeCoordinator() -> Coordinator { Coordinator(game: game) }
    func makeUIView(context: Context) -> SCNView {
        let view = TabletSceneView(); let c=context.coordinator
        c.manager.cameraNode.camera?.zNear = 1
        c.manager.cameraNode.camera?.projectionDirection = .vertical
        view.scene=c.manager.scene; view.pointOfView=c.manager.cameraNode
        view.antialiasingMode = .multisampling4X; view.preferredFramesPerSecond=30
        view.isAccessibilityElement=true; view.accessibilityIdentifier="board3D"; view.accessibilityLabel="3D Go board"
        view.backgroundColor = .black; view.isPlaying=true
        view.isMultipleTouchEnabled = true
        c.view = view
        view.viewportChanged = { [weak c] size in c?.updateViewport(size) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            view.cameraValue = { [weak c] in
                guard let c else { return nil }
                let p = c.manager.cameraNode.simdPosition
                return String(format: "%@ %.3f,%.3f,%.3f", c.manager.isCameraArriving ? "moving" : "seated", p.x, p.y, p.z)
            }
        }
        #endif
        let skip = TabletCameraSkipGesture { [weak c] in c?.manager.finishCameraArrival() ?? false }
        view.addGestureRecognizer(skip)
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        let orbit = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.orbit(_:)))
        orbit.minimumNumberOfTouches = 2; orbit.maximumNumberOfTouches = 2
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 3; pan.maximumNumberOfTouches = 3
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: c, action: #selector(Coordinator.rotate(_:)))
        for gesture in [tap, orbit, pan, pinch, rotation] {
            gesture.delegate = c
            gesture.require(toFail: skip)
            view.addGestureRecognizer(gesture)
        }
        // Camera gestures cooperate. Waiting for a three-finger pan to fail holds
        // the two-finger orbit until touch-up, so it must have no such dependency.
        for cameraGesture in [orbit, pan, pinch, rotation] { tap.require(toFail: cameraGesture) }
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let c=context.coordinator; c.game=game
        c.configureCamera(environment: environment, active: active, recenter: recenter, reduceMotion: reduceMotion)
        view.isPlaying = active
        c.updateViewport(view.bounds.size)
        let stones=game.player.board.stones.map { RenderStone(id:$0.key,color:$0.value,offset:.zero,isDead:game.deadStones.contains($0.key)) }
        c.manager.updateStones(from:stones,lastMove:game.player.lastMove.map{BoardPosition($0.y,$0.x)},moveIndex:game.player.currentIndex,settings:AppSettings.shared,animate:false)
        c.manager.updateCapturedStones(black:game.player.blackStonesCaptured,white:game.player.whiteStonesCaptured,seed:game.player.captureSeed)
        c.manager.updateGhostStone(at:game.selectedPoint,color:game.selectedPoint == nil ? nil : game.player.turn)
        c.manager.updateReviewVariations(game.mode == .review && game.scoring == nil ? game.tree.boardVariations : [])
        c.manager.updateTerritory(points:game.territory)
    }
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) { coordinator.manager.setEnvironmentActive(false); view.isPlaying=false; view.scene=nil }
    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: SCNView?
        let manager=SceneManager3D()
        var game:TabletGame
        var distance:CGFloat=SceneManager3D.seatedCameraDistance(boardSize:19)
        var rx=SceneManager3D.seatedCameraRotationX, ry:Float=0
        var px:CGFloat=0, py:CGFloat=0, recenter=0
        private var environment: PlayingEnvironment?
        private var boardSize: Int?
        private var pendingArrival = false
        private var seatedTransform: simd_float4x4?
        private weak var framingBoard: SCNNode?
        init(game:TabletGame) { self.game=game; super.init() }
        func camera() {
            manager.updateCameraPosition(distance:distance,rotationX:rx,rotationY:ry,panX:px,panY:py)
        }
        func updateViewport(_ size: CGSize) {
            guard size.width > 0, size.height > 0, let seatedTransform, let framingBoard else { return }
            manager.updateCameraFieldOfView(TabletCameraFraming.fieldOfView(board: framingBoard, seatedTransform: seatedTransform, viewport: size))
        }
        private func resetPose() {
            distance = SceneManager3D.seatedCameraDistance(boardSize: game.player.board.size)
            rx = SceneManager3D.seatedCameraRotationX; ry = 0; px = 0; py = 0
        }
        func configureCamera(environment: PlayingEnvironment, active: Bool, recenter: Int, reduceMotion: Bool) {
            let changed = self.environment != environment || boardSize != game.player.board.size
            let requestedRecenter = self.recenter != recenter
            self.environment = environment; boardSize = game.player.board.size; self.recenter = recenter
            manager.updateBoardSize(game.player.board.size)
            manager.updateEnvironment(environment, flicker: false, motion: !reduceMotion)
            manager.setEnvironmentActive(active)
            if reduceMotion { manager.finishCameraArrival() }
            if changed {
                manager.finishCameraArrival()
                resetPose(); camera()
                seatedTransform = manager.cameraNode.simdTransform
                framingBoard = manager.scene.rootNode.childNode(withName: environment.usesTableBoard ? "kaya-table-board" : "kaya-floor-board", recursively: true)
                updateViewport(view?.bounds.size ?? .zero)
                pendingArrival = true
            }
            if pendingArrival && active {
                pendingArrival = false
                manager.beginCameraArrival(reduceMotion: reduceMotion)
            } else if requestedRecenter {
                resetPose()
                manager.beginCameraRecenter(distance: distance, rotationX: rx, reduceMotion: reduceMotion)
            } else {
                // The shared renderer protects an in-progress flight from routine updates.
                camera()
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer.view === other.view, !(other is TabletCameraSkipGesture) else { return false }
            return !(gestureRecognizer is UITapGestureRecognizer) && !(other is UITapGestureRecognizer)
        }
        @objc func tap(_ g:UITapGestureRecognizer) { guard !manager.finishCameraArrival() else { return }; guard let v=g.view as? SCNView, let p=manager.hitTest(point:g.location(in:v),in:v) else{return}; game.tap(at: BoardPosition(p.y,p.x)) }
        @objc func orbit(_ g: UIPanGestureRecognizer) {
            let d = g.translation(in: g.view); g.setTranslation(.zero, in: g.view)
            guard g.numberOfTouches == 2, g.state == .began || g.state == .changed else { return }
            ry += Float(d.x) * 0.006; rx = min(1.3, max(-0.15, rx + Float(d.y) * 0.006)); camera()
        }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            let d = g.translation(in: g.view); g.setTranslation(.zero, in: g.view)
            guard g.numberOfTouches == 3, g.state == .began || g.state == .changed else { return }
            px += d.x * 0.025; py -= d.y * 0.025; camera()
        }
        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            let scale = g.scale; g.scale = 1
            guard g.numberOfTouches == 2, g.state == .began || g.state == .changed, scale.isFinite, scale > 0 else { return }
            distance = min(95, max(17, distance / scale)); camera()
        }
        @objc func rotate(_ g: UIRotationGestureRecognizer) {
            let angle = g.rotation; g.rotation = 0
            guard g.numberOfTouches == 2, g.state == .began || g.state == .changed else { return }
            ry -= Float(angle); camera()
        }
    }
}

/// Read the live pose for UI tests; no polling timer or diagnostics in the interface.
final class TabletSceneView: SCNView {
    var viewportChanged: ((CGSize) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        viewportChanged?(bounds.size)
    }
    var cameraValue: (() -> String?)?
    override var accessibilityValue: String? {
        get { cameraValue?() ?? super.accessibilityValue }
        set { super.accessibilityValue = newValue }
    }
}

/// Decide on touch-down, then consume the entire contact sequence. A long press,
/// drag, second finger or Pencil lift must never turn a skipped flight into a move.
final class TabletCameraSkipGesture: UIGestureRecognizer {
    private let finish: () -> Bool
    private var contacts: Set<UITouch> = []
    init(finish: @escaping () -> Bool) {
        self.finish = finish
        super.init(target: nil, action: nil)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        contacts.formUnion(touches)
        if state == .possible { state = finish() ? .began : .failed }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed { state = .changed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        contacts.subtract(touches)
        if contacts.isEmpty && (state == .began || state == .changed) { state = .ended }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }
    override func reset() { super.reset(); contacts.removeAll() }
}

/// Fit the rendered board's top to the playing viewport, independently of the
/// user's current orbit/zoom or the animated tour. SceneKit uses a vertical lens.
enum TabletCameraFraming {
    static func fieldOfView(board: SCNNode, seatedTransform: simd_float4x4, viewport: CGSize) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0 else { return 60 }
        let bounds = board.boundingBox
        let worldToCamera = simd_inverse(seatedTransform)
        let aspect = Float(viewport.width / viewport.height)
        var tangent: Float = 0
        for x in [bounds.min.x, bounds.max.x] {
            for z in [bounds.min.z, bounds.max.z] {
                let point = worldToCamera * board.simdWorldTransform * SIMD4<Float>(x, bounds.max.y, z, 1)
                guard point.z < 0 else { return 60 }
                tangent = max(tangent, abs(point.x / point.z) / aspect, abs(point.y / point.z))
            }
        }
        // Four percent of the viewport at each edge leaves room for stones and
        // the wooden rim, while making the grid much easier to use with fingers.
        return CGFloat(2 * atan(tangent / 0.92) * 180 / .pi)
    }
}
