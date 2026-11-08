import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

final class FrameCounter: NSObject, SCNSceneRendererDelegate {
    private let lock = NSLock()
    private var count = 0
    var frames: Int { lock.lock(); defer { lock.unlock() }; return count }
    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock(); count += 1; lock.unlock()
    }
}

@main struct StationParallaxCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let manager = SceneManager3D()
        manager.updateEnvironment(.spaceStation, flicker: false, motion: true)
        let root = manager.scene.rootNode
        let outside = root.childNode(withName: "orbital-exterior", recursively: true)!
        let room = root.childNode(withName: "photographic-surroundings", recursively: true)!
        precondition(outside.boundingBox.max.x > room.boundingBox.max.x * 5)
        precondition(manager.cameraNode.camera!.zFar == 2000)
        precondition(room.geometry!.firstMaterial!.transparent.contents is NSImage)
        let environment = root.childNode(withName: "environment-spaceStation", recursively: true)!
        let dividers = environment.childNodes.filter { $0.name == "viewport-scuffed-mullion" }
        precondition(dividers.count == 2)
        precondition(dividers[0].eulerAngles.y * dividers[1].eulerAngles.y < 0)

        // Render the actual production material face-on and compare ten seconds
        // of content movement; checking the uniform alone misses invisible shaders.
        let material = root.childNode(withName: "station-display", recursively: true)!.geometry!.firstMaterial!
        let screenScene = SCNScene()
        let panel = SCNNode(geometry: SCNPlane(width: 3, height: 2))
        panel.geometry!.firstMaterial = material
        screenScene.rootNode.addChildNode(panel)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position.z = 3
        screenScene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = screenScene; renderer.pointOfView = camera
        func pixels(_ phase: Float) -> Data {
            material.setValue(phase, forKey: "stationDisplayPhase")
            SCNTransaction.flush()
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 768, height: 512), antialiasingMode: .none)
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        let first = pixels(0), later = pixels(2 * .pi / 18)
        let changed = zip(first, later).filter { abs(Int($0)-Int($1)) > 12 }.count
        precondition(changed > 1500, "Display content must visibly move: \(changed)")

        // A native view must animate while idle, without input or snapshot calls.
        let view = UnifiedSCNView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        let counter = FrameCounter(); view.delegate = counter
        let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 320, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view; window.orderFrontRegardless()
        view.updateEnvironmentPlayback()
        precondition(view.isPlaying && view.rendersContinuously)
        material.setValue(Float(0), forKey: "stationDisplayPhase")
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        let phase = (material.value(forKey: "stationDisplayPhase") as! NSNumber).floatValue
        precondition(counter.frames > 2 && phase > 0 && phase < 0.15,
                     "Idle native view should advance slowly: frames=\(counter.frames), phase=\(phase)")
        manager.updateEnvironment(.spaceStation, flicker: false, motion: false)
        view.updateEnvironmentPlayback()
        precondition(!view.isPlaying && !view.rendersContinuously)
        window.orderOut(nil)
        manager.updateEnvironment(.coffeeShop, flicker: false)
        precondition(manager.cameraNode.camera!.zFar == 1000)
        print("PASS: separate enclosing exterior, two solid mullions, \(changed) changed display samples, \(counter.frames) idle native frames, slow motion and Reduce Motion pause")
    }
}
