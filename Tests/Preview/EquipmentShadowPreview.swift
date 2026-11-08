import AppKit
import SceneKit
@testable import SGFPlayerNetworking

@main struct EquipmentShadowPreview {
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
        defer { withExtendedLifetime(images) {} }
        let manager = SceneManager3D(); manager.updateDebugSettings()
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19]AB[dd][jj][pq]AW[dp][pd][qq])")))
        manager.updateStones(from: player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) }, lastMove: nil, moveIndex: 0, settings: AppSettings.shared, animate: false)
        manager.updateCapturedStones(black: 4, white: 4, seed: 123)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        for frame in 0..<180 {
            _ = renderer.snapshot(atTime: Double(frame) / 60, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
        }
        let names = ["kaya-floor-board", "white-stone-bowl", "black-stone-bowl", "white-player-lid", "black-player-lid", "board-stone", "supply-stone", "captured-white", "captured-black"]
        func snapshot() -> NSBitmapImageRep {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: 3, with: CGSize(width: 1400, height: 1000), antialiasingMode: .multisampling4X)
            return NSBitmapImageRep(data: renderer.snapshot(atTime: 3, with: CGSize(width: 1400, height: 1000), antialiasingMode: .multisampling4X).tiffRepresentation!)!
        }
        func changes(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
            var count = 0
            for y in stride(from: 0, to: a.pixelsHigh, by: 3) { for x in stride(from: 0, to: a.pixelsWide, by: 3) {
                let c = a.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!, d = b.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
                let delta = (d.redComponent-c.redComponent)*0.2126 + (d.greenComponent-c.greenComponent)*0.7152 + (d.blueComponent-c.blueComponent)*0.0722
                if delta > 0.012 { count += 1 }
            }}
            return count
        }
        for kind in PlayingEnvironment.allCases where CommandLine.arguments.count < 4 || kind.rawValue == CommandLine.arguments[3] {
            manager.updateEnvironment(kind, flicker: false)
            manager.updateCameraPosition(distance: 43, rotationX: 0.55, rotationY: 0, panX: 0, panY: 0)
            let base = snapshot()
            try base.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(kind.rawValue + ".png"))
            var reports: [String] = []
            for originalName in names {
                let name = originalName == "kaya-floor-board" && kind.usesTableBoard ? "kaya-table-board" : originalName
                var nodes: [SCNNode] = []
                manager.scene.rootNode.enumerateChildNodes { n, _ in
                    if n.name == name {
                        nodes.append(n)
                        n.enumerateChildNodes { child, _ in nodes.append(child) }
                    }
                }
                let states = nodes.map { $0.castsShadow }
                nodes.forEach { $0.castsShadow = false }
                let unshadowed = snapshot()
                reports.append("\(name):\(changes(base,unshadowed))")
                for (n, shadow) in zip(nodes, states) { n.castsShadow = shadow }
            }
            let contact = manager.scene.rootNode.childNode(withName: "equipment-contact-shadows", recursively: true)!
            contact.isHidden = true
            reports.append("contact:\(changes(base,snapshot()))")
            contact.isHidden = false
            print(kind.rawValue, reports.joined(separator: " "))
        }
    }
}
