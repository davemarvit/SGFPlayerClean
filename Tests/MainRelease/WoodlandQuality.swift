import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

/// Check the shipped assets and actual GPU output, including the alpha-channel
/// conversion that prevents opaque fern cards or inverted leaf silhouettes.
@main struct WoodlandQualityCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for name in ["woodland-ground-color.jpg", "woodland-ground-normal.jpg"] {
            let image = EnvironmentMaterials.image(name)!
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            require(bitmap.pixelsWide == 4096 && bitmap.pixelsHigh == 4096, "Full-resolution ground scan is bundled")
        }
        let variants = EnvironmentMaterials.woodlandFerns
        require(variants.count == 4, "All scanned fern growth habits load from the app bundle")
        let opacity = variants[0].firstMaterial!.transparent.contents as! NSImage
        let mask = NSBitmapImageRep(data: opacity.tiffRepresentation!)!
        var empty = 0, leaves = 0
        for y in stride(from: 0, to: mask.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: mask.pixelsWide, by: 8) {
                let alpha = mask.colorAt(x: x, y: y)!.alphaComponent
                if alpha < 0.01 { empty += 1 }
                if alpha > 0.99 { leaves += 1 }
            }
        }
        require(empty > leaves && leaves > 1000, "Fern alpha preserves thin leaves and clear spaces between them")
        let manager = SceneManager3D(); manager.updateDebugSettings()
        manager.updateEnvironment(.tree, flicker: false, motion: false)
        manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
            rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        let floor = manager.scene.rootNode.childNode(withName: "photographic-ground", recursively: true)!
        let geometry = floor.geometry!, detailed = geometry.firstMaterial!
        let transform = floor.simdWorldTransform
        let panorama = detailed.copy() as! SCNMaterial
        panorama.shaderModifiers = nil; panorama.multiply.contents = NSColor.white; panorama.normal.contents = nil
        var frames: [NSBitmapImageRep] = []
        for material in [panorama, detailed] {
            geometry.firstMaterial = material; SCNTransaction.flush()
            _ = renderer.snapshot(atTime: 0, with: CGSize(width: 1200, height: 900), antialiasingMode: .multisampling4X)
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1200, height: 900), antialiasingMode: .multisampling4X)
            frames.append(NSBitmapImageRep(data: image.tiffRepresentation!)!)
        }
        var changed = 0
        for y in stride(from: 0, to: 900, by: 6) {
            for x in stride(from: 0, to: 1200, by: 6) {
                let a = frames[0].colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                let b = frames[1].colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                let delta = abs(a.redComponent-b.redComponent) + abs(a.greenComponent-b.greenComponent) + abs(a.blueComponent-b.blueComponent)
                if delta > 0.05 { changed += 1 }
            }
        }
        require(changed > 1000, "The compiled ground shader visibly replaces the stretched panorama at the seat")
        manager.beginCameraArrival(reduceMotion: false)
        for time in [0.0, 6.0, 13.0] {
            manager.updateCameraArrival(elapsed: time)
            require(floor.simdWorldTransform == transform, "Scanned ground stays fixed throughout arrival")
        }
        print("PASS: bundled 4K ground, four fern variants, cutout alpha and seated GPU shader (\(changed) changed samples)")
    }
}
