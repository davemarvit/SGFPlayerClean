import AppKit
import SceneKit
@testable import SGFPlayerNetworking

@main struct SpaceStationPreview {
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
        manager.updateEnvironment(.spaceStation, flicker: false, motion: false)
        manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19), rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
        let div = manager.scene.rootNode.childNode(withName: "viewport-scuffed-mullion", recursively: true)!
        print("DIVIDER", div.boundingBox, div.geometry?.sources(for: .vertex).first?.vectorCount ?? -1)
        try save("station-playing")
        manager.beginCameraArrival(reduceMotion: false)
        manager.updateCameraArrival(elapsed: 0)
        try save("station-opening")
        manager.finishCameraArrival()
        manager.updateCameraPosition(distance: 45, rotationX: 0.53, rotationY: 0.12, panX: 0, panY: 0)
        try save("station-workstation")
        manager.cameraNode.position = SCNVector3(18, 18, 27)
        manager.cameraNode.look(at: SCNVector3(25, 0, -7))
        manager.cameraNode.camera!.fieldOfView = 58
        try save("station-controls")
        manager.updateEnvironment(.spaceStation, flicker: false, motion: true)
        renderer.isPlaying = true
        try save("station-controls-t0", time: 10)
        try save("station-controls-t10", time: 20)
        manager.updateEnvironment(.spaceStation, flicker: false, motion: false)
        manager.cameraNode.eulerAngles = SCNVector3Zero
        manager.updateCameraPosition(distance: 45, rotationX: -0.55, rotationY: 0, panX: -12, panY: 0)
        try save("station-window-left", time: 20)
        manager.cameraNode.eulerAngles = SCNVector3Zero
        manager.updateCameraPosition(distance: 45, rotationX: -0.55, rotationY: 0, panX: 12, panY: 0)
        try save("station-window-right", time: 20)
        manager.updateCameraPosition(distance: 100, rotationX: -0.55, rotationY: 0, panX: 60, panY: 60)
        try save("station-window-limit", time: 20)
        withExtendedLifetime(images) {}
    }
}
