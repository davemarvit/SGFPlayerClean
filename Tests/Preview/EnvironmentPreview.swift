import AppKit
import SceneKit
@testable import SGFPlayerNetworking

@main struct ShojiPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let images = try FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }.compactMap { url -> NSImage? in
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
        if CommandLine.arguments.contains("--benchmark") {
            var timings: [Double] = []
            for frame in 0..<100 {
                manager.updateCameraPosition(distance: 48, rotationX: 0.05, rotationY: Float(frame) * 0.009 - 0.45, panX: 0, panY: 0)
                SCNTransaction.flush()
                let start = CFAbsoluteTimeGetCurrent()
                _ = renderer.snapshot(atTime: Double(frame) / 60, with: CGSize(width: 960, height: 640), antialiasingMode: .multisampling4X)
                if frame >= 20 { timings.append((CFAbsoluteTimeGetCurrent() - start) * 1000) }
            }
            timings.sort()
            print("Offscreen 960x640 camera sweep: median", timings[timings.count/2], "ms; p95", timings[Int(Double(timings.count) * 0.95)], "ms")
            return
        }
        for kind in PlayingEnvironment.allCases {
            manager.updateEnvironment(kind, flicker: false)
            if kind == .cave {
                manager.cameraNode.position=SCNVector3(29,7,0)
                manager.cameraNode.look(at:SCNVector3(24,4,-18))
                SCNTransaction.flush()
                let image=renderer.snapshot(atTime:0,with:CGSize(width:1000,height:1000),antialiasingMode:.multisampling4X)
                try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("lamp-detail.png"))
            }
            let views: [(String, CGFloat, Float, Float)] = [
                ("setting", 46, -0.12, -0.25), ("default", 25, 0.45, 0),
                ("close", 29, 0.1, 0), ("wide", 72, -0.12, -0.25), ("low", 55, -0.40, -0.25), ("reverse", 60, 0.12, 2.8)]
            for (name, distance, x, y) in views {
                manager.updateCameraPosition(distance: distance, rotationX: x, rotationY: y, panX: 0, panY: 0)
                SCNTransaction.flush()
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1400, height: 1000), antialiasingMode: .multisampling4X)
                let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                try data.write(to: output.appendingPathComponent(kind.rawValue + "-" + name + ".png"))
            }
        }
        withExtendedLifetime(images) {}
    }
}
