import AppKit
import SceneKit
@testable import SGFPlayerNetworking

@main struct GoEquipmentPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let images = try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil).compactMap { url -> NSImage? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            image.setName(url.lastPathComponent == TatamiTexture.assetName ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
            return image
        }
        let manager = SceneManager3D()
        manager.updateDebugSettings()
        let game = SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd];W[pd];B[dp];W[pp];B[cf];W[nc];B[fc];W[qn];B[cn];W[nq];B[qq];W[pq];B[qp];W[po])"))
        let player = SGFPlayer(); player.load(game: game); player.seek(to: player.maxIndex)
        manager.updateStones(from: player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) },
            lastMove: nil, moveIndex: player.maxIndex, settings: AppSettings.shared, animate: false)
        manager.updateCapturedStones(black: 7, white: 4, seed: 17)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.fieldOfView = 48
        camera.camera?.zFar = 1000
        manager.scene.rootNode.addChildNode(camera); renderer.pointOfView = camera
        camera.position = SCNVector3(25, 29, 37); camera.look(at: SCNVector3(0, 0, 0))
        var time = 0.0
        for _ in 0..<240 {
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 96, height: 96), antialiasingMode: .none)
            time += 1.0 / 60
        }
        func save(_ name: String, position: SCNVector3, target: SCNVector3, size: CGSize) throws {
            camera.position = position
            camera.look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            SCNTransaction.flush()
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                .write(to: destination.appendingPathComponent(name + ".png"))
        }
        try save("whole-setting", position: SCNVector3(25, 29, 37), target: SCNVector3(0, 0, 0), size: CGSize(width: 1400, height: 950))
        try save("black-bowl", position: SCNVector3(-23, 10, 16), target: SCNVector3(-14, 1, 5), size: CGSize(width: 900, height: 750))
        try save("white-bowl", position: SCNVector3(-24, 10, -1), target: SCNVector3(-14, 1, -5), size: CGSize(width: 900, height: 750))
        try save("lid", position: SCNVector3(22, 7, 14), target: SCNVector3(14, 0, 5), size: CGSize(width: 900, height: 750))
        let models = SCNScene()
        for name in ["white-stone-bowl", "black-stone-bowl", "white-player-lid", "black-player-lid"] {
            let node = manager.scene.rootNode.childNode(withName: name, recursively: true)!.clone()
            node.physicsBody = nil
            node.enumerateChildNodes { child, _ in child.physicsBody = nil }
            if name.hasSuffix("-lid") {
                // Export reusable empty lids, without this preview game's captures/counts.
                node.childNodes.forEach { $0.removeFromParentNode() }
            }
            models.rootNode.addChildNode(node)
        }
        guard models.write(to: destination.appendingPathComponent("GoEquipment.scn"), options: nil, delegate: nil, progressHandler: nil) else {
            fatalError("Could not export equipment")
        }
        let points = (0..<220).map { index in
            "[" + String(UnicodeScalar(97 + index % 19)!) + String(UnicodeScalar(97 + index / 19)!) + "]"
        }
        let depleted = "(;SZ[19]AB" + points.prefix(110).joined() + "AW" + points.suffix(110).joined() + ")"
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: depleted)))
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        try save("bowls-depleted", position: SCNVector3(-23, 16, 16), target: SCNVector3(-14, 1, 1), size: CGSize(width: 900, height: 750))
        withExtendedLifetime(images) {}
    }
}
