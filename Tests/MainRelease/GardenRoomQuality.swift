import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct GardenRoomQuality {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let manager = SceneManager3D(); manager.updateDebugSettings()
        manager.updateEnvironment(.gardenRoom, flicker: false)
        manager.beginCameraArrival(reduceMotion: false)
        manager.updateCameraArrival(elapsed: 0)
        let root = manager.scene.rootNode
        require(root.childNode(withName: "garden-room-exterior", recursively: true) == nil,
            "No flat photographic panel can obstruct the garden opening")
        let image = manager.scene.background.contents as! NSImage
        let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        require(pixels.width == 8192 && pixels.height == 4096, "Complete 8K garden panorama is bundled at full resolution")
        let plant = root.childNode(withName: "indoor-plant", recursively: true)!
        require(plant.childNodes.count == 3, "Complete plant, pot, and soil meshes are bundled")
        let bounds = plant.boundingBox
        require(abs(bounds.max.y - bounds.min.y - 23.5) < 0.01, "Plant retains its calibrated physical scale")
        for node in plant.childNodes {
            let material = node.geometry!.firstMaterial!
            for channel in [material.diffuse, material.normal, material.roughness] {
                require(channel.contents is NSImage, "Plant texture channels are available in the installed bundle")
            }
        }
        let leaf = plant.childNode(withName: "room-plant-leaves", recursively: false)!
        require(leaf.geometry!.firstMaterial!.transparent.contents is NSImage, "Leaf cutout mask is bundled")
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        func snapshot() -> NSBitmapImageRep {
            SCNTransaction.flush()
            let size = CGSize(width: 960, height: 720)
            _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
            return NSBitmapImageRep(data: renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X).tiffRepresentation!)!
        }
        func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, rows: Range<Int>) -> Int {
            var changed = 0
            for y in rows { for x in 0..<960 {
                let c = a.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                let d = b.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if abs(c.redComponent-d.redComponent) + abs(c.greenComponent-d.greenComponent) + abs(c.blueComponent-d.blueComponent) > 0.025 { changed += 1 }
            }}
            return changed
        }
        let baseline = snapshot()
        manager.scene.background.contents = PlayingEnvironment.gardenRoom.background
        let withoutPhoto = snapshot()
        manager.scene.background.contents = image
        require(difference(baseline, withoutPhoto, rows: 0..<500) > 20000, "Full-resolution exterior is visible through the opening")
        let sun = root.childNode(withName: "SUN", recursively: true)!.light!
        sun.castsShadow = false
        let withoutShadows = snapshot()
        sun.castsShadow = true
        let shadowPixels = difference(baseline, withoutShadows, rows: 480..<720)
        require(shadowPixels > 500, "Soft shadows still visibly ground the equipment and plant on the tatami")
        sun.shadowRadius = 1.5
        let hardShadows = snapshot()
        require(difference(baseline, hardShadows, rows: 480..<720) > 500, "Shadow softness changes the rendered floor")
        manager.finishCameraArrival()
        for angle: Float in [0, 0.9, 2.8, 4.5] {
            manager.updateCameraPosition(distance: 150, rotationX: 0.12, rotationY: angle, panX: 0, panY: 0)
            let complete = snapshot()
            manager.scene.background.contents = PlayingEnvironment.gardenRoom.background
            let missing = snapshot()
            manager.scene.background.contents = image
            require(difference(complete, missing, rows: 0..<720) > 20000,
                "Panorama covers the wide/orbit view instead of exposing a gray void at angle \(angle)")
        }
        manager.updateEnvironment(.cave, flicker: false)
        require(sun.intensity == 0 && manager.scene.lightingEnvironment.intensity == 0, "Garden daylight does not leak into the cave")
        manager.updateEnvironment(.gardenRoom, flicker: false)
        require(sun.shadowRadius == 7, "Returning to the room restores its soft daylight")
        print("PASS: bundled photographic exterior, complete textured plant, visible soft floor shadows (\(shadowPixels) pixels), environment switching")
    }
}
