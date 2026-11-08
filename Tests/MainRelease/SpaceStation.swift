import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

@main struct SpaceStationCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard let image = EnvironmentMaterials.panorama(.spaceStation),
              image.representations.contains(where: { $0.pixelsWide >= 1700 }) else {
            fatalError("Missing packaged station panorama")
        }
        for asset in ["station-worn-graphite.png", "station-worn-ivory.png"] {
            guard let texture = EnvironmentMaterials.image(asset),
                  texture.representations.contains(where: { $0.pixelsWide >= 1000 }) else {
                fatalError("Missing packaged wear texture: \(asset)")
            }
        }
        let manager = SceneManager3D(); manager.updateDebugSettings()
        manager.updateEnvironment(.spaceStation, flicker: false)
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1280, height: 960))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        let output = URL(fileURLWithPath: "/private/tmp/sgf-space-station-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: size),
                rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
            SCNTransaction.flush()
            let p = view.projectPoint(SCNVector3(0, 1, 0))
            let hit = manager.hitTest(point: CGPoint(x: p.x, y: p.y), in: view)
            precondition(hit?.x == size / 2 && hit?.y == size / 2, "Controls must not intercept board picking")
            let image = renderer.snapshot(atTime: 0, with: view.bounds.size, antialiasingMode: .multisampling4X)
            try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                .write(to: output.appendingPathComponent("station-\(size).png"))
        }
        let display = manager.scene.rootNode.childNode(withName: "station-display", recursively: true)!.geometry!.firstMaterial!
        let clock = manager.scene.rootNode.childNode(withName: "station-display-clock", recursively: true)!
        renderer.isPlaying = true
        func tick(_ time: Double) {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 32,height: 32), antialiasingMode: .none)
        }
        func phase() -> Float { (display.value(forKey: "stationDisplayPhase") as! NSNumber).floatValue }
        tick(0.1); let start = phase(); tick(1.1)
        precondition(phase() > start && phase()-start < 0.06, "Display movement must be slow")
        manager.setEnvironmentActive(false)
        let frozen = phase(); tick(10)
        precondition(clock.isPaused && phase() == frozen, "Inactive display must stay still")
        manager.setEnvironmentActive(true)
        let settings = AppSettings.shared; settings.showDropInAnimation = true
        manager.updateStones(from: [RenderStone(id: BoardPosition(9, 9), color: .black, offset: .zero)],
                             lastMove: nil, moveIndex: 1, settings: settings)
        let anchor = manager.scene.rootNode.childNode(withName: "board-stone", recursively: true)!.parent!
        precondition(anchor.action(forKey: "stone-placement-drop")?.duration == 2)
        precondition(abs(manager.scene.physicsWorld.gravity.y + 0.1962) < 0.001)
        manager.updateEnvironment(.gardenRoom, flicker: false)
        precondition(abs(manager.scene.physicsWorld.gravity.y + 19.62) < 0.001)
        print("PASS: bundled station artwork, 9/13/19 board picking, textured tabletop renders, slow display motion and pausing, two-second drops and gravity reset")
    }
}
