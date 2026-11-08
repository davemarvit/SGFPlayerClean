import AppKit
import SceneKit
@testable import SGFPlayerNetworking

@main struct CaveMineralsPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : Bundle.main.resourceURL!
        let output = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : FileManager.default.temporaryDirectory.appendingPathComponent("cave-minerals-release-preview")
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
        for kind in [PlayingEnvironment.cave] {
            manager.updateEnvironment(kind, flicker: false)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
                rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
            guard let floor = manager.scene.rootNode.childNode(withName: "photographic-ground", recursively: true),
                  let geometry = floor.geometry, let detailed = geometry.firstMaterial else { continue }
            let rock = manager.scene.rootNode.childNode(withName: "oil-lamp-rock", recursively: true)!
            precondition(rock.geometry!.name == "flowstone-stalagmite", "Lamp rests on the flowstone stalagmite")
            precondition(detailed.name == "cave-waterworn-bedrock")
            precondition(detailed.multiply.contents is NSImage && detailed.normal.contents is NSImage)
            precondition(abs(rock.boundingBox.max.y + rock.position.y - PlayingEnvironmentScene.caveLampBaseHeight) < 0.025, "Lamp rests on the rock")
            for (label, material) in [("current", detailed)] {
                geometry.firstMaterial = material
                for (pose, time) in [("seated", 14.0), ("opening", 0.0), ("survey", 6.0)] {
                    manager.beginCameraArrival(reduceMotion: false)
                    manager.updateCameraArrival(elapsed: time)
                    SCNTransaction.flush()
                    let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1600, height: 1200), antialiasingMode: .multisampling4X)
                    let pixels = NSBitmapImageRep(data: image.tiffRepresentation!)!
                    var magenta = 0
                    for y in stride(from: 0, to: pixels.pixelsHigh, by: 4) {
                        for x in stride(from: 0, to: pixels.pixelsWide, by: 4) {
                            let c = pixels.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                            if c.redComponent > 0.9 && c.blueComponent > 0.9 && c.greenComponent < 0.1 { magenta += 1 }
                        }
                    }
                    precondition(magenta == 0, "GPU shader must compile")
                    if pose == "opening" {
                        rock.isHidden = true; SCNTransaction.flush()
                        let absent = renderer.snapshot(atTime: 0, with: CGSize(width: 1600,height: 1200), antialiasingMode: .multisampling4X)
                        let without = NSBitmapImageRep(data: absent.tiffRepresentation!)!
                        rock.isHidden = false; SCNTransaction.flush()
                        var visible = 0
                        for y in stride(from: 0, to: 1200, by: 4) {
                            for x in stride(from: 0, to: 1600, by: 4) {
                                let a = pixels.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                                let b = without.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                                if abs(a.redComponent-b.redComponent) + abs(a.greenComponent-b.greenComponent) + abs(a.blueComponent-b.blueComponent) > 0.04 { visible += 1 }
                            }
                        }
                        precondition(visible > 300, "Rock must actually render, not just exist in the scene")
                        print("PASS: stalagmite visible in", visible, "sampled pixels; lamp supported; stone maps loaded")
                    }
                    let data = pixels.representation(using: .png, properties: [:])!
                    try data.write(to: output.appendingPathComponent("\(kind.rawValue)-\(pose)-\(label).png"))
                    manager.finishCameraArrival()
                }
            }
            geometry.firstMaterial = detailed
        }
        print("PASS: opening, survey, and seated GPU renders contain no shader error pixels")
        withExtendedLifetime(images) {}
    }
}
