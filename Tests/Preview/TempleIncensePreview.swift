import AppKit
import SceneKit
@testable import SGFPlayerNetworking

@main struct TempleIncensePreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let images = FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }.compactMap { url -> NSImage? in
            guard !url.path.contains("/Bowls2D/"), let image = NSImage(contentsOf: url) else { return nil }
            image.setName(url.path.contains("/Environments/") || url.lastPathComponent == TatamiTexture.assetName ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
            return image
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
        func save(_ name: String, time: Double = 3, size: CGSize = CGSize(width: 1400, height: 1000)) throws {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        manager.updateEnvironment(.monastery, flicker: false, motion: true)
        manager.updateCameraPosition(distance: 28, rotationX: 0.44, rotationY: 0, panX: 0, panY: 0)
        for i in 0...480 { _ = renderer.snapshot(atTime: Double(i)/60, with: CGSize(width:64,height:64), antialiasingMode:.none) }
        try save("temple-seated",time:8)
        manager.updateCameraPosition(distance:43,rotationX:0.55,rotationY:0,panX:0,panY:0)
        try save("temple-wide",time:8)
        manager.cameraNode.position = SCNVector3(-18,1,-8)
        manager.cameraNode.look(at:SCNVector3(-27,-4.5,-25),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
        manager.cameraNode.camera!.fieldOfView = 40
        try save("incense-smoke-8",time:8)
        for i in 1...180 { _ = renderer.snapshot(atTime: 8+Double(i)/60, with: CGSize(width:64,height:64), antialiasingMode:.none) }
        try save("incense-smoke-11",time:11)
        manager.updateEnvironment(.monastery,flicker:false,motion:false)
        try save("incense-no-smoke",time:11)
        manager.cameraNode.position = SCNVector3(22,-4,25)
        manager.cameraNode.look(at:SCNVector3(0,-7,0),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
        manager.cameraNode.camera!.fieldOfView = 62
        try save("goban-legs",time:11)
        withExtendedLifetime(images) {}
    }
}
