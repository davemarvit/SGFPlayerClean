import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

/// Exercise the shipped maps and compiled shaders, including actual flame pixels
/// at the end of arrival. A light node alone does not prove the flame is visible.
@main struct EnvironmentQualityCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for asset in ["garden-gravel", "moon-regolith", "cave-riverbed", "weathered_brown_planks", "yugen-carpet", "summit-rock"] {
            for suffix in ["color", "normal"] {
                guard let image = EnvironmentMaterials.image("\(asset)-\(suffix).jpg"),
                      let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!) else {
                    require(false, "Missing shipped map: \(asset)-\(suffix)"); return
                }
                require(bitmap.pixelsWide == 4096 && bitmap.pixelsHigh == 4096, "Full 4K \(asset) \(suffix)")
            }
        }
        let manager = SceneManager3D(); manager.updateDebugSettings()
        let root = manager.scene.rootNode
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        func snapshot() -> NSBitmapImageRep {
            SCNTransaction.flush()
            let size = CGSize(width: 1200, height: 900)
            _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
            let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
            return NSBitmapImageRep(data: image.tiffRepresentation!)!
        }
        func changed(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, step: Int) -> Int {
            var result = 0
            for y in stride(from: 0, to: 900, by: step) {
                for x in stride(from: 0, to: 1200, by: step) {
                    let ca = a.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    let cb = b.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    if abs(ca.redComponent-cb.redComponent) + abs(ca.greenComponent-cb.greenComponent)
                        + abs(ca.blueComponent-cb.blueComponent) > 0.06 { result += 1 }
                }
            }
            return result
        }
        for kind in [PlayingEnvironment.japaneseGarden, .moon, .yugenRoom, .mountainSummit] {
            manager.updateEnvironment(kind, flicker: false, motion: false)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
                rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
            let floor = root.childNode(withName: "photographic-ground", recursively: true)!
            let geometry = floor.geometry!, detailed = geometry.firstMaterial!
            let baseline = detailed.copy() as! SCNMaterial
            baseline.shaderModifiers = nil; baseline.multiply.contents = NSColor.white; baseline.normal.contents = nil
            geometry.firstMaterial = baseline
            let plain = snapshot()
            geometry.firstMaterial = detailed
            let scan = snapshot()
            let samples = changed(plain, scan, step: 6)
            require(samples > 300, "The \(kind.rawValue) floor shader visibly renders its detail")
            let transform = floor.simdWorldTransform
            manager.beginCameraArrival(reduceMotion: false)
            for time in [0.0, 6.0, 13.0] {
                manager.updateCameraArrival(elapsed: time)
                require(floor.simdWorldTransform == transform, "Floor remains fixed during arrival")
            }
            if kind == .yugenRoom {
                require(geometry.sources(for: .vertex).first?.vectorCount == 4,
                        "Rug is a flat rectangle, not radial panorama geometry")
                require(root.childNode(withName: "yugen-floor-mats", recursively: true) != nil, "Tatami surrounds the rug")
                require(abs(floor.worldPosition.y + geometry.boundingBox.max.y - KayaFloorBoard.floorY) < 0.001,
                        "Rug meets the furniture and board feet")
            }
            print("PASS: \(kind.rawValue) shipped shader, \(samples) changed samples, fixed floor")
        }
        manager.updateEnvironment(.cave, flicker: false, motion: false)
        let flame = root.childNode(withName: "oil-lamp-flame", recursively: true)!
        let rock = root.childNode(withName: "oil-lamp-rock", recursively: true)!
        require(abs(rock.boundingBox.max.y + rock.position.y - PlayingEnvironmentScene.caveLampBaseHeight) < 0.025,
                "Lowered lamp still meets its stone support")
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: size),
                rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
            manager.beginCameraArrival(reduceMotion: false); manager.updateCameraArrival(elapsed: 13)
            flame.isHidden = false
            let lit = snapshot()
            let projected = renderer.projectPoint(flame.childNodes[0].worldPosition)
            require(projected.x > 20 && projected.x < 1180 && projected.y > 20 && projected.y < 880
                    && projected.z > 0 && projected.z < 1, "Flame is inside the final \(size)×\(size) frame")
            flame.isHidden = true
            let unlit = snapshot()
            let samples = changed(lit, unlit, step: 2)
            flame.isHidden = false
            require(samples > 15, "Flame actually renders without being occluded for \(size)×\(size)")
            print("PASS: seated \(size)×\(size) flame visible in \(samples) samples")
        }
        print("PASS: 4K environment assets, GPU detail, rectangular Yugen rug and lowered cave flame")
    }
}
