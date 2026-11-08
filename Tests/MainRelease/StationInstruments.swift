import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

@main struct StationInstrumentsCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let manager = SceneManager3D()
        manager.updateEnvironment(.spaceStation, flicker: false, motion: false)
        var panels: [SCNNode] = []
        manager.scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "station-display" { panels.append(node) }
        }
        precondition(panels.count == 5)
        let output = URL(fileURLWithPath: "/private/tmp/sgf-station-instruments")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var kinds = Set<Int>()
        var fingerprints = Set<Data>()
        for panel in panels {
            let material = panel.geometry!.firstMaterial!
            let kind = (material.value(forKey: "stationInstrument") as! NSNumber).intValue
            let aspect = (material.value(forKey: "stationAspect") as! NSNumber).doubleValue
            let image = material.diffuse.contents as! NSImage
            precondition(abs(image.size.width / image.size.height - aspect) < 0.002)
            let bounds = panel.geometry!.boundingBox
            precondition(abs(Double((bounds.max.x-bounds.min.x)/(bounds.max.y-bounds.min.y)) - aspect) < 0.002)
            kinds.insert(kind)
            let scene = SCNScene()
            let display = SCNNode(geometry: SCNPlane(width: aspect*2, height: 2))
            display.geometry!.firstMaterial = material
            scene.rootNode.addChildNode(display)
            let camera = SCNNode(); camera.camera = SCNCamera()
            camera.camera!.usesOrthographicProjection = true
            camera.camera!.orthographicScale = 1.08
            camera.position.z = 5; scene.rootNode.addChildNode(camera)
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = scene; renderer.pointOfView = camera
            func render(_ phase: Float, suffix: String) throws -> Data {
                material.setValue(phase, forKey: "stationDisplayPhase"); SCNTransaction.flush()
                let size = CGSize(width: min(1800,aspect*600), height: min(600,1800/aspect))
                let snapshot = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
                let bitmap = NSBitmapImageRep(data: snapshot.tiffRepresentation!)!
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("instrument-\(kind)-\(suffix).png"))
                return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow*bitmap.pixelsHigh)
            }
            let first = try render(0,suffix: "start")
            let later = try render(2 * .pi / 18,suffix: "10-seconds")
            fingerprints.insert(first)
            let changed = zip(first,later).filter { abs(Int($0)-Int($1)) > 12 }.count
            precondition(changed > 200, "Instrument \(kind) must visibly evolve over ten seconds: \(changed)")
            print("Instrument \(kind): aspect \(aspect), \(changed) moving samples")
        }
        precondition(kinds == Set(0..<5) && fingerprints.count == 5)
        precondition(PlayingEnvironmentScene.stationDisplayCycleDuration == 180)
        print("PASS: five distinct instruments, native panel proportions, visible slow motion, three-minute wireframe rotation")
    }
}
