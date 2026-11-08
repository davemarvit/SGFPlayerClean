import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

@main struct CoffeeShopCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: "/private/tmp/sgf-coffee-shop-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for name in ["coffee-shop-panorama.png", "coffee-table-wood.png"] {
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
        for kind in [PlayingEnvironment.coffeeShop] {
            manager.updateEnvironment(kind, flicker: false)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
                rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
            manager.beginCameraArrival(reduceMotion: false)
            for (index, time) in [0.0, 1.8, 2.6, 3.4, 4.0].enumerated() {
                manager.updateCameraArrival(elapsed: time)
                SCNTransaction.flush()
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1400, height: 1000), antialiasingMode: .multisampling4X)
                let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                try data.write(to: output.appendingPathComponent("\(kind.rawValue)-\(index).png"))
            }
        }
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1400, height: 1000))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        let point = view.projectPoint(SCNVector3(0, 1, 0))
        let hit = manager.hitTest(point: CGPoint(x: point.x, y: point.y), in: view)
        guard hit?.x == 9 && hit?.y == 9 else {
            fputs("FAIL: Table furniture blocks board interaction\n", stderr); exit(1)
        }
        manager.updateCameraPosition(distance: 48, rotationX: 0.7, rotationY: 0.45, panX: 0, panY: 0)
        let wide = renderer.snapshot(atTime: 0, with: CGSize(width: 1400, height: 1000), antialiasingMode: .multisampling4X)
        try NSBitmapImageRep(data: wide.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("coffeeShop-furniture.png"))
        var timings: [Double] = []
        for _ in 0..<12 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = renderer.snapshot(atTime: 0, with: CGSize(width: 1400, height: 1000), antialiasingMode: .multisampling4X)
            timings.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        print("Café render/readback median ms:", timings.sorted()[6])
        print("PASS: packaged café textures, tabletop board interaction, opening and seated views")
    }
}
