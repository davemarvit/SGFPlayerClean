import AppKit
import SceneKit
@testable import SGFPlayerNetworking

@main
struct CapturePreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        let images = try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil).compactMap { url -> NSImage? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            image.setName(url.deletingPathExtension().lastPathComponent)
            return image
        }
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        let manager = SceneManager3D()
        manager.updateCapturedStones(black: 40, white: 3)
        manager.updateBoardSize(9)
        manager.updateCapturedStones(black: 40, white: 3)
        SCNTransaction.commit()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene
        renderer.pointOfView = manager.cameraNode
        SCNTransaction.flush()
        _ = renderer.prepare(manager.scene, shouldAbortBlock: nil)
        // This checks the rebuilt scene and initial pile layout, not real-time physics settling.
        let output = renderer.snapshot(atTime: CACurrentMediaTime(), with: CGSize(width: 1400, height: 1000), antialiasingMode: .multisampling4X)
        guard let tiff = output.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { fatalError("Capture preview failed") }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        withExtendedLifetime(images) {}
    }
}
