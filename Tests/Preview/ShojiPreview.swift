import AppKit
import SceneKit
@testable import SGFPlayerNetworking

@main struct ShojiPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let images = try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil).compactMap { url -> NSImage? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            image.setName(url.lastPathComponent == TatamiTexture.assetName ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
            return image
        }
        let manager = SceneManager3D(); manager.updateDebugSettings()
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd];W[pd];B[dp];W[pp];B[cf];W[nc];B[fc];W[qn];B[cn];W[nq];B[qq];W[pq];B[qp];W[po])")))
        player.seek(to: player.maxIndex)
        manager.updateStones(from: player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) }, lastMove: nil, moveIndex: player.maxIndex, settings: AppSettings.shared, animate: false)
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        let views: [(String, CGFloat, Float, Float, CGFloat, CGFloat)] = [
            ("shoji-setting", 38, 0.05, -0.38, 0, 0),
            ("default-view", 25, 0.45, 0, 0, 0),
            ("wide-view", 70, 0.05, -0.4, 0, 0),
            ("reverse-view", 65, 0.05, 2.8, 0, 0),
            ("translated-view", 35, 0.25, -0.4, 35, 0)]
        for (name, distance, x, y, panX, panY) in views {
            manager.updateCameraPosition(distance: distance, rotationX: x, rotationY: y, panX: panX, panY: panY)
            SCNTransaction.flush()
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1400, height: 1000), antialiasingMode: .multisampling4X)
            let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try data.write(to: output.appendingPathComponent(name + ".png"))
        }
        withExtendedLifetime(images) {}
    }
}
