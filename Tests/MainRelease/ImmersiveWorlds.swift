import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

@main struct ImmersiveWorldsCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: "/private/tmp/sgf-immersive-worlds-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for name in ["retro-future-panorama.png", "laboratory-panorama.png", "tree-intimate-panorama.png", "monastery-intimate-panorama.png", "zafu-worn-cloth.png", "yugen-worn-brocade.png"] {
            guard let image = EnvironmentMaterials.image(name), let bitmap = image.representations.first else {
                fputs("FAIL: Missing bundled café texture \(name)\n", stderr); exit(1)
            }
            guard bitmap.pixelsWide >= 1200 else { fputs("FAIL: Café texture is too small\n", stderr); exit(1) }
        }
        let manager = SceneManager3D(); manager.updateDebugSettings()
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd];W[pd];B[dp];W[pp];B[cf];W[nc];B[fc];W[qn];B[cn];W[nq];B[qq];W[pq];B[qp];W[po])")))
        player.seek(to: player.maxIndex)
        manager.updateStones(from: player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) }, lastMove: nil, moveIndex: player.maxIndex, settings: AppSettings.shared, animate: false)
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        manager.updateCapturedStones(black: 3, white: 7)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        for kind in [PlayingEnvironment.retroFuture, .laboratory, .monastery] {
            manager.updateEnvironment(kind, flicker: false)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
                rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
            manager.beginCameraArrival(reduceMotion: false)
            for (index, time) in [0.0, 2.6, 4.0].enumerated() {
                manager.updateCameraArrival(elapsed: time)
                SCNTransaction.flush()
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1400, height: 1000), antialiasingMode: .multisampling4X)
                let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                try data.write(to: output.appendingPathComponent("\(kind.rawValue)-\(index).png"))
            }
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1400, height: 1000))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        let point = view.projectPoint(SCNVector3(0, 1, 0))
        let hit = manager.hitTest(point: CGPoint(x: point.x, y: point.y), in: view)
        guard hit?.x == 9 && hit?.y == 9 else {
            fputs("FAIL: Table furniture blocks board interaction\n", stderr); exit(1)
        }
        }
        for kind in [PlayingEnvironment.tree, .coffeeShop, .laboratory, .retroFuture] {
            manager.updateEnvironment(kind, flicker: false, motion: false)
            for size in [9,13,19] {
                manager.updateBoardSize(size)
                let board = manager.scene.rootNode.childNode(withName: kind.usesTableBoard ? "kaya-table-board" : "kaya-floor-board", recursively: true)!
                let bounds = board.geometry!.boundingBox
                for distance: CGFloat in [28,10,1,0] { for tilt: Float in [-0.55,0,0.44,1.8] {
                    for yaw: Float in [-3,0,3] { for pan: CGFloat in [-18,0,18] {
                        manager.updateCameraPosition(distance: distance, rotationX: tilt, rotationY: yaw, panX: pan, panY: -pan)
                        let p = manager.cameraNode.position
                        precondition(p.y >= bounds.max.y + 1.19 || abs(p.x) >= bounds.max.x + 1.19 || abs(p.z) >= bounds.max.z + 1.19, "Camera entered wood")
                    }}
                }}
            }
        }
        print("PASS: packaged artwork, new environments, board interaction, opening views and camera collision")
    }
}
