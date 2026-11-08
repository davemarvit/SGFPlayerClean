import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

@main struct CafeMugsPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = Bundle.main.resourceURL!
        let output = URL(fileURLWithPath: "/private/tmp/sgf-cafe-mugs-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let images = FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }.compactMap { url -> NSImage? in
            guard !url.path.contains("/Bowls2D/"), let image = NSImage(contentsOf: url) else { return nil }
            image.setName(url.path.contains("/Environments/") || url.lastPathComponent == TatamiTexture.assetName ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
            return image
        }
        precondition(EnvironmentMaterials.image("marvit-but-first-coffee-monster.jpg") != nil, "Original mug artwork must be bundled")
        let manager = SceneManager3D(); manager.updateDebugSettings()
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd];W[pd];B[dp];W[pp];B[cf];W[nc];B[fc];W[qn];B[cn];W[nq];B[qq];W[pq];B[qp];W[po])")))
        player.seek(to: player.maxIndex)
        manager.updateStones(from: player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) }, lastMove: nil, moveIndex: player.maxIndex, settings: AppSettings.shared, animate: false)
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        manager.updateCapturedStones(black: 3, white: 7)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        func save(_ name: String, time: Double = 3, size: CGSize = CGSize(width: 1400, height: 1000)) throws {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        for kind in [PlayingEnvironment.coffeeShop, .monastery] {
            manager.updateEnvironment(kind, flicker: false, motion: false)
            manager.updateCameraPosition(distance: 28, rotationX: 0.44, rotationY: 0, panX: 0, panY: 0)
            try save(kind.rawValue + "-seated", size: CGSize(width: 1280, height: 960))
            manager.updateCameraPosition(distance: 43, rotationX: 0.55, rotationY: 0, panX: 0, panY: 0)
            try save(kind.rawValue + "-equipment")
        }
        manager.updateEnvironment(.coffeeShop, flicker: false, motion: true)
        manager.cameraNode.position = SCNVector3(21.5, 7, -4)
        manager.cameraNode.look(at: SCNVector3(21.5, 1.4, -17.5))
        manager.cameraNode.camera!.fieldOfView = 38
        for i in 0...360 { _ = renderer.snapshot(atTime: 4 + Double(i)/60, with: CGSize(width: 64, height: 64), antialiasingMode: .none) }
        try save("mug-steam-10", time: 10)
        for i in 1...120 { _ = renderer.snapshot(atTime: 10 + Double(i)/60, with: CGSize(width: 64, height: 64), antialiasingMode: .none) }
        try save("mug-steam-12", time: 12)
        manager.updateEnvironment(.coffeeShop, flicker: false, motion: false)
        try save("mug-no-steam", time: 12)
        manager.cameraNode.camera!.fieldOfView = 38
        let bowl = manager.scene.rootNode.childNode(withName: "white-stone-bowl", recursively: true)!
        manager.cameraNode.position = SCNVector3(bowl.position.x, 10, bowl.position.z + 12)
        manager.cameraNode.look(at: SCNVector3(bowl.position.x, 0.5, bowl.position.z))
        try save("bowl-shadow-on", time: 12)
        bowl.childNodes.forEach { if $0.name == "supply-stone" { $0.castsShadow = false } }
        try save("bowl-shadow-off", time: 12)
        let on = NSBitmapImageRep(data: try Data(contentsOf: output.appendingPathComponent("bowl-shadow-on.png")))!
        let off = NSBitmapImageRep(data: try Data(contentsOf: output.appendingPathComponent("bowl-shadow-off.png")))!
        var wallSamples = 0, wallShadowSamples = 0
        var largest: CGFloat = 0
        for y in stride(from: 100, to: 700, by: 8) { for x in stride(from: 250, to: 1150, by: 8) {
            let hits = renderer.hitTest(CGPoint(x: x, y: 999-y), options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true])
            guard let hit = hits.first, hit.node === bowl,
                  hit.localCoordinates.x * hit.localNormal.x + hit.localCoordinates.z * hit.localNormal.z < -0.5 else { continue }
            wallSamples += 1
            let a = on.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!, b = off.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            let delta = (b.redComponent-a.redComponent)*0.2126 + (b.greenComponent-a.greenComponent)*0.7152 + (b.blueComponent-a.blueComponent)*0.0722
            if delta > 0.005 { wallShadowSamples += 1 }
            largest = max(largest, delta)
        }}
        precondition(wallSamples > 100 && wallShadowSamples > 10 && largest > 0.03, "Supply stones must visibly shade the inner wooden wall")
        print("Inner bowl wall samples", wallSamples, "visibly shaded by stones", wallShadowSamples, "largest change", largest)
        withExtendedLifetime(images) {}
    }
}
