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
        if CommandLine.arguments.dropFirst(3).contains("ko") {
            var game = SGFGame()
            game.boardSize = 9; game.info.rules = "japanese"
            game.setup = [(.black,1,0),(.black,0,1),(.black,1,2),
                          (.white,1,1),(.white,2,0),(.white,3,1),(.white,2,2)]
            let player = SGFPlayer(); player.load(game: game)
            precondition(player.tryPlayMove(color: .black, x: 2, y: 1) == nil)
            let stones = player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) }
            manager.updateStones(from: stones, lastMove: BoardPosition(1,2), moveIndex: 1, settings: AppSettings.shared, animate: false)
            manager.updateKoMarker(at: player.koPoint)
            manager.updateCapturedStones(black: player.capturesByBlack, white: player.capturesByWhite)
        }
        // Freeze the layout and omit invisible collision meshes in this static preview.
        manager.scene.physicsWorld.speed = 0
        manager.scene.rootNode.enumerateChildNodes { node, _ in node.physicsBody = nil }
        var invisibleNodes: [SCNNode] = []
        manager.scene.rootNode.enumerateChildNodes { node, _ in
            if node.opacity == 0 { invisibleNodes.append(node) }
        }
        invisibleNodes.forEach { $0.removeFromParentNode() }
        SCNTransaction.commit()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene
        renderer.pointOfView = manager.cameraNode
        SCNTransaction.flush()
        _ = renderer.prepare(manager.scene, shouldAbortBlock: nil)
        // This checks the rebuilt scene and initial pile layout, not real-time physics settling.
        let size = CGSize(width: 1400, height: 1000)
        let time = CACurrentMediaTime()
        // Warm up offscreen Metal resources before capturing the final frame.
        _ = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
        let output = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
        guard let tiff = output.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { fatalError("Capture preview failed") }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        withExtendedLifetime(images) {}
    }
}
