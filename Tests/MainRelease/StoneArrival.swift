import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
@main struct StoneArrivalCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        AppSettings.shared.showDropInAnimation = true
        let manager = SceneManager3D()
        manager.updateEnvironment(.spaceStation, flicker: false, motion: false)
        manager.updateCameraPosition(distance: 32, rotationX: 0.44, rotationY: 0, panX: 0, panY: 0)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        func frame(_ time: Double) {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 320, height: 240), antialiasingMode: .none)
        }
        frame(0)
        // Match the enclosing SwiftUI scene transaction, with a deliberately long
        // duration so any inherited movement is easy to distinguish from the drop.
        SCNTransaction.begin(); SCNTransaction.animationDuration = 1
        manager.updateStones(from: [RenderStone(id: BoardPosition(3, 15), color: .white, offset: .zero)],
                             lastMove: nil, moveIndex: 1, settings: AppSettings.shared, animate: true)
        SCNTransaction.commit()
        var anchor: SCNNode?
        manager.scene.rootNode.enumerateChildNodes { node, _ in if node.name == "board-stone" { anchor = node.parent } }
        let stone = anchor!
        let expected = stone.position
        var previousY = CGFloat.greatestFiniteMagnitude
        for index in 1...130 {
            let time = Double(index) / 60
            frame(time)
            let actual = stone.presentation.position
            require(abs(actual.x - expected.x) < 0.001 && abs(actual.z - expected.z) < 0.001,
                    "Stone starts over its intersection and never sweeps across other points: frame \(index), \(actual) vs \(expected)")
            require(actual.y <= previousY + 0.001 && actual.y >= 0.999, "Stone only drops toward the board")
            if index == 1 { require(actual.y > 2, "First frame is above the destination, not on another intersection") }
            previousY = actual.y
        }
        require(abs(stone.presentation.position.y - 1) < 0.001, "Stone lands on the board")
        print("PASS: first rendered frame starts directly above destination; every frame stays on vertical drop path despite enclosing animation transaction")
    }
}
