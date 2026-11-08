import AppKit
import SceneKit
@testable import SGFPlayerNetworking

@main struct GroundDetailPreview {
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
        for kind in PlayingEnvironment.allCases {
            manager.updateEnvironment(kind, flicker: false)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
                rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
            guard let floor = manager.scene.rootNode.childNode(withName: "photographic-ground", recursively: true),
                  let geometry = floor.geometry, let detailed = geometry.firstMaterial else { continue }
            let original = detailed.copy() as! SCNMaterial
            original.shaderModifiers = nil; original.multiply.contents = NSColor.white
            original.normal.contents = nil
            for (label, material) in [("before", original), ("after", detailed)] {
                geometry.firstMaterial = material
                for (pose, time) in [("seated", 4.0), ("opening", 0.0)] {
                    manager.beginCameraArrival(reduceMotion: false)
                    manager.updateCameraArrival(elapsed: time)
                    SCNTransaction.flush()
                    let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1600, height: 1200), antialiasingMode: .multisampling4X)
                    let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                    try data.write(to: output.appendingPathComponent("\(kind.rawValue)-\(pose)-\(label).png"))
                    manager.finishCameraArrival()
                }
            }
            geometry.firstMaterial = detailed
        }
        withExtendedLifetime(images) {}
    }
}
