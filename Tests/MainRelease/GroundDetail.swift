import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

/// Exercise the shipped textures and GPU shader, including rendering each
/// material with and without detail. Model-only tests cannot catch a shader
/// compile error or a texture missing from the application bundle.
@main struct GroundDetailCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for asset in ["garden-gravel", "moon-regolith", "yugen-carpet", "weathered_brown_planks", "cave-riverbed", "woodland-ground"] {
            for map in ["color", "normal"] {
                let image = EnvironmentMaterials.image("\(asset)-\(map).jpg")!
                let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                require(bitmap.pixelsWide == 4096 && bitmap.pixelsHigh == 4096, "Full-resolution \(asset) \(map) is bundled")
            }
        }
        let manager = SceneManager3D()
        manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
            rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        for kind in [PlayingEnvironment.japaneseGarden, .moon, .tree, .cave, .yugenRoom, .monastery] {
            manager.updateEnvironment(kind, flicker: false)
            let floor = manager.scene.rootNode.childNode(withName: "photographic-ground", recursively: true)!
            let transform = floor.simdWorldTransform
            let geometry = floor.geometry!, detailed = geometry.firstMaterial!
            if kind == .monastery {
                require(detailed.diffuse.contents is NSImage && detailed.name == "monastery-worn-floorboards",
                    "Monastery uses the bundled wood scan instead of a mat")
                for side in ["player", "opponent"] {
                    let seat = manager.scene.rootNode.childNode(withName: "zabuton-\(side)", recursively: true)!
                    let cloth = seat.childNodes.first { $0.name?.hasPrefix("zabuton-body") == true }!.geometry!.firstMaterial!
                    require(cloth.diffuse.contents is NSImage && cloth.normal.contents is NSImage, "\(side) cushion has bundled cloth maps")
                    require(abs(seat.worldPosition.y - KayaFloorBoard.floorY) < 0.001, "\(side) cushion rests on the floor")
                }
            } else {
                require(detailed.multiply.contents is NSImage, "\(kind) loads its detail photograph")
            }
            require(detailed.shaderModifiers?[.surface] != nil, "\(kind) blends nearby detail")
            let plain = detailed.copy() as! SCNMaterial
            plain.shaderModifiers = nil; plain.multiply.contents = NSColor.white; plain.normal.contents = nil
            var frames: [NSBitmapImageRep] = []
            for material in [plain, detailed] {
                geometry.firstMaterial = material
                SCNTransaction.flush()
                var elapsed: [Double] = []
                var last: NSImage!
                for frame in 0..<12 {
                    let start = CFAbsoluteTimeGetCurrent()
                    last = renderer.snapshot(atTime: 0, with: CGSize(width: 960, height: 640), antialiasingMode: .multisampling4X)
                    if frame > 2 { elapsed.append((CFAbsoluteTimeGetCurrent() - start) * 1000) }
                }
                print(kind.rawValue, material === detailed ? "detail" : "original", "median render/readback ms", elapsed.sorted()[4])
                frames.append(NSBitmapImageRep(data: last.tiffRepresentation!)!)
            }
            var changed = 0
            for y in stride(from: 0, to: 640, by: 8) {
                for x in stride(from: 0, to: 960, by: 8) {
                    let before = frames[0].colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let after = frames[1].colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let delta = abs(before.redComponent - after.redComponent)
                        + abs(before.greenComponent - after.greenComponent) + abs(before.blueComponent - after.blueComponent)
                    if delta > 0.015 { changed += 1 }
                }
            }
            require(changed > 100, "\(kind) renders actual visible surface detail")
            manager.beginCameraArrival(reduceMotion: false)
            manager.updateCameraArrival(elapsed: 2.5)
            require(floor.simdWorldTransform == transform, "\(kind) floor stays fixed during the fly-in")
            manager.finishCameraArrival()
        }
        print("PASS: all six photographic floors load, render and retain fixed placement")
    }
}
