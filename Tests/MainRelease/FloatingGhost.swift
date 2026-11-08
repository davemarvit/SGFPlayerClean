import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct FloatingGhostCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        AppSettings.shared.showDropInAnimation = true
        let scene = SceneManager3D()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene.scene; renderer.pointOfView = scene.cameraNode; renderer.isPlaying = true
        var time = 0.0
        func frame() {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
            time += 1.0 / 60
        }
        for (size, color) in [(19, Stone.black), (9, Stone.white)] {
            scene.updateBoardSize(size)
            scene.updateStones(from: [], lastMove: nil, moveIndex: 0, settings: AppSettings.shared, animate: false)
            scene.updateCameraPosition(distance: 30, rotationX: 0.5, rotationY: 0.25, panX: 0, panY: 0)
            scene.updateDebugSettings()
            let point = BoardPosition(size / 2, size / 2)
            scene.updateGhostStone(at: point, color: color)
            let ghost = scene.scene.rootNode.childNode(withName: "ghost-stone", recursively: true)!
            let dot = scene.scene.rootNode.childNode(withName: "ghost-landing-marker", recursively: true)!
            let origin = ghost.worldPosition
            require(ghost.scale.y < 0.5 && ghost.opacity > 0 && ghost.opacity < 1, "Preview is a translucent flattened stone")
            require(dot.opacity == 1 && dot.position.y < ghost.position.y, "Red landing dot sits below the hovering stone")
            require(!ghost.castsShadow && !dot.castsShadow && ghost.physicsBody == nil && dot.physicsBody == nil,
                    "Preview does not add shadows or physics")
            require(dot.geometry!.firstMaterial!.lightingModel == .constant && !dot.geometry!.firstMaterial!.writesToDepthBuffer,
                    "Landing glow is self-lit without obscuring the board")
            frame()
            let image = renderer.snapshot(atTime: time, with: CGSize(width: 1100, height: 850), antialiasingMode: .multisampling4X)
            let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try data.write(to: URL(fileURLWithPath: "/private/tmp/sgf-floating-ghost-\(size).png"))
            scene.clearGhostStone()
            require(ghost.opacity == 0 && dot.opacity == 0, "Placement clears both preview elements")
            scene.updateStones(from: [RenderStone(id: point, color: color, offset: CGPoint(x: 0.08, y: -0.06))],
                lastMove: nil, moveIndex: 1, settings: AppSettings.shared)
            let placed = scene.scene.rootNode.childNode(withName: "board-stone", recursively: true)!
            let anchor = placed.parent!
            let start = placed.worldPosition
            require(abs(start.x - origin.x) < 0.0001 && abs(start.y - origin.y) < 0.0001 && abs(start.z - origin.z) < 0.0001,
                    "Drop begins at the exact ghost center, before final stone jitter")
            require(placed.geometry === ghost.geometry && placed.scale.x == ghost.scale.x &&
                    placed.scale.y == ghost.scale.y && placed.scale.z == ghost.scale.z,
                    "Placed stone retains the ghost shape and color")
            require(anchor.hasActions && anchor.opacity == 1, "Click makes the stone solid before its drop starts")
            for _ in 0..<7 { frame() }
            require(anchor.presentation.position.y > 1 && anchor.presentation.position.y < origin.y,
                    "Stone visibly travels toward the board")
            require(anchor.presentation.opacity == 1, "Stone remains fully solid throughout the drop")
            for _ in 0..<20 { frame() }
            let cell = CGFloat(18) / CGFloat(size - 1)
            require(abs(anchor.presentation.position.y - 1) < 0.001 && abs(anchor.presentation.opacity - 1) < 0.001,
                    "Stone finishes solid on the board")
            require(abs(anchor.presentation.position.x - 0.08 * cell) < 0.001 &&
                    abs(anchor.presentation.position.z + 0.06 * cell * 1.0773) < 0.001,
                    "Landing preserves the natural stone offset")
            scene.updateStones(from: [], lastMove: nil, moveIndex: 0, settings: AppSettings.shared, animate: false)
            AppSettings.shared.showDropInAnimation = false
            scene.updateStones(from: [RenderStone(id: point, color: color, offset: .zero)],
                lastMove: nil, moveIndex: 1, settings: AppSettings.shared)
            let instant = scene.scene.rootNode.childNode(withName: "board-stone", recursively: true)!.parent!
            require(!instant.hasActions && instant.position.y == 1 && instant.opacity == 1, "Animation preference still permits instant placement")
            AppSettings.shared.showDropInAnimation = true
        }
        print("PASS: floating preview, aligned glow, both stone colors, exact drop origin, animation progression/landing, jitter and animation preference")
    }
}
