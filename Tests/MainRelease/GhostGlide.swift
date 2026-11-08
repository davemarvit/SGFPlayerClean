import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private func near(_ a: SCNVector3, _ b: SCNVector3, tolerance: CGFloat = 0.001) -> Bool {
    abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
}

@main struct GhostGlideCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        AppSettings.shared.showDropInAnimation = true
        let manager = SceneManager3D()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode; renderer.isPlaying = true
        var time = 0.0
        func frame() {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
            time += 1.0 / 240
        }
        func frames(_ count: Int) { for _ in 0..<count { frame() } }
        for size in [19, 9] {
            manager.updateBoardSize(size)
            let cell = CGFloat(18) / CGFloat(size - 1)
            for color in [Stone.white, .black] {
                manager.updateStones(from: [], lastMove: nil, moveIndex: 0, settings: AppSettings.shared, animate: false)
                manager.clearGhostStone()
                let startPoint = BoardPosition(3, 3), target = BoardPosition(3, 4)
                manager.updateGhostStone(at: startPoint, color: color, animate: true)
                let ghost = manager.scene.rootNode.childNode(withName: "ghost-stone", recursively: true)!
                let dot = manager.scene.rootNode.childNode(withName: "ghost-landing-marker", recursively: true)!
                let start = ghost.position, geometry = ghost.geometry, yaw = ghost.eulerAngles.y
                require(!ghost.hasActions, "First appearance does not fly in from an old position")
                frames(2)
                manager.updateGhostStone(at: target, color: color, animate: true)
                manager.updateBoardCursor(at: target)
                require(near(ghost.position, start), "Glide starts without a jump")
                require(abs(dot.position.x - start.x - cell) < 0.001 && !dot.hasActions,
                        "Red dot snaps immediately while the stone remains behind")
                frames(7)
                let middle = ghost.presentation.position
                require(middle.x > start.x && middle.x < dot.position.x, "Rendered stone is between intersections during the glide")
                require(ghost.geometry === geometry && ghost.eulerAngles.y == yaw, "Shell pattern and rotation stay fixed")

                // Reverse before arrival, then bombard the same target with refreshes.
                manager.updateGhostStone(at: startPoint, color: color, animate: true)
                require(near(ghost.position, middle), "Rapid reversal starts at the last rendered position")
                for _ in 0..<26 { manager.updateGhostStone(at: startPoint, color: color, animate: true); frame() }
                require(near(ghost.presentation.position, start) && !ghost.hasActions,
                        "Duplicate hover publications do not postpone arrival or queue movement")

                manager.updateGhostStone(at: target, color: color, animate: true)
                frames(7)
                let clickPosition = ghost.presentation.position
                manager.prepareGhostPlacement(at: target, color: color)
                manager.clearGhostStone() // Online play clears the hover before the board publishes.
                let stones = [RenderStone(id: target, color: color, offset: CGPoint(x: 0.08, y: -0.06))]
                manager.updateStones(from: stones, lastMove: target, moveIndex: 1, settings: AppSettings.shared)
                let placed = manager.scene.rootNode.childNode(withName: "board-stone", recursively: true)!
                let anchor = placed.parent!
                require(near(placed.position + anchor.position, clickPosition), "Drop begins exactly at the visible in-flight ghost")
                require(placed.geometry === geometry && placed.eulerAngles.y == yaw && anchor.opacity == 1,
                        "Click solidifies the same stone with no texture or orientation pop")
                frames(65)
                let expected = SCNVector3((CGFloat(target.col) - CGFloat(size - 1) / 2 + 0.08) * cell,
                    1, (CGFloat(target.row) - CGFloat(size - 1) / 2 - 0.06) * cell * 1.0773)
                require(near(anchor.presentation.position, expected), "Moving click lands at the chosen intersection plus natural jitter")
                manager.updateStones(from: stones, lastMove: target, moveIndex: 1, settings: AppSettings.shared)
                require(placed.geometry === geometry && placed.eulerAngles.y == yaw, "Later board refresh preserves landed appearance")

                manager.updateGhostStone(at: startPoint, color: color, animate: true)
                manager.updateGhostStone(at: target, color: color, animate: true)
                frames(3)
                manager.updateGhostStone(at: target, color: color, animate: false)
                require(!ghost.hasActions && abs(ghost.position.x - dot.position.x) < 0.001,
                        "Reduce Motion finishes an active glide immediately")
                manager.updateGhostStone(at: startPoint, color: color, animate: true)
                manager.clearGhostStone(); frames(25)
                require(ghost.opacity == 0 && !ghost.hasActions, "Leaving an intersection cancels hidden motion")
                manager.updateGhostStone(at: target, color: color, animate: true)
                require(!ghost.hasActions, "Re-entry appears directly over its target")

                // Rejected clicks and non-click updates must never reuse an old pose.
                manager.prepareGhostPlacement(at: target, color: color)
                manager.cancelGhostPlacement()
                manager.clearGhostStone()
                manager.updateStones(from: [], lastMove: nil, moveIndex: 0, settings: AppSettings.shared, animate: false)
                manager.updateStones(from: stones, lastMove: target, moveIndex: 1, settings: AppSettings.shared)
                let normal = manager.scene.rootNode.childNode(withName: "board-stone", recursively: true)!.parent!
                require(abs(normal.position.x - (CGFloat(target.col) - CGFloat(size - 1) / 2) * cell) < 0.001,
                        "Playback after cancellation starts over its own target")
                frames(65)
            }
        }
        print("PASS: rendered 80ms glide, snapping dot, stable appearance, reversal, duplicate updates, click-to-drop continuity, landing, cancellation and Reduce Motion on 9x9/19x19 in both colors")
        try liveClicks()
    }

    @MainActor static func liveClicks() throws {
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ghost-glide-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        AppSettings.shared.folderURL = nil; AppSettings.shared.savedGamesFolderURL = temp
        AppSettings.shared.isMuted = true; AppSettings.shared.analysisEnabled = false
        AppSettings.shared.environment3D = .spaceStation // Longer drop makes the handoff easy to sample.
        let app = AppModel(); app.aiAnalysisEnabled = false; app.newLocalGame(); app.viewMode = .view3D
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let vm = app.boardVM!
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = NSHostingView(rootView: ContentView3D().environmentObject(app))
        window.orderFront(nil)
        func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        settle(0.4)
        let live = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        live.onInteraction?(.click, .zero) // Skip the arrival survey.
        settle(0.1)
        let ghost = live.scene!.rootNode.childNode(withName: "ghost-stone", recursively: true)!
        let dot = live.scene!.rootNode.childNode(withName: "ghost-landing-marker", recursively: true)!
        let cell = CGFloat(18) / CGFloat(vm.boardSize - 1)
        func location(_ point: BoardPosition) -> CGPoint {
            let projected = live.projectPoint(SCNVector3((CGFloat(point.col) - CGFloat(vm.boardSize - 1) / 2) * cell,
                1, (CGFloat(point.row) - CGFloat(vm.boardSize - 1) / 2) * cell * 1.0773))
            return CGPoint(x: projected.x, y: projected.y)
        }
        func event(_ type: NSEvent.EventType, at point: BoardPosition) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: live.convert(location(point), to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: type == .mouseMoved ? 0 : 1, pressure: 0)!
        }
        func click(_ point: BoardPosition) {
            live.mouseDown(with: event(.leftMouseDown, at: point))
            live.mouseUp(with: event(.leftMouseUp, at: point))
        }
        for row in [7, 9] {
            let before = BoardPosition(row, 7), target = BoardPosition(row, 8)
            let color = vm.engine.turn, index = vm.engine.currentIndex
            live.mouseMoved(with: event(.mouseMoved, at: before)); settle(0.12)
            // Freeze the render clock for native-event assertions: the 80 ms
            // action must not finish on the render thread while this test reads
            // its pose. The offscreen checks above sample the motion itself.
            live.scene!.isPaused = true
            live.mouseMoved(with: event(.mouseMoved, at: target))
            // No run-loop wait: the click reaches the real production handler while gliding.
            require(ghost.hasActions && vm.ghostPosition == target, "Production hover starts a glide to the clicked point")
            let visible = ghost.presentation.position, geometry = ghost.geometry, yaw = ghost.eulerAngles.y
            require(abs(visible.x - dot.position.x) > cell * 0.5, "Click occurs while the stone visibly trails the snapping dot")
            click(target)
            require(vm.engine.currentIndex == index + 1 && vm.engine.board.stones[target] == color && vm.engine.board.stones[before] == nil,
                    "Real click places exactly one move at the pointer, not at the moving ghost")
            vm.syncState()
            var placed: SCNNode?
            live.scene!.rootNode.enumerateChildNodes { node, _ in
                if node.name == "board-stone", node.parent?.action(forKey: "stone-placement-drop") != nil,
                   node.geometry === geometry, node.eulerAngles.y == yaw { placed = node }
            }
            require(placed != nil && near(placed!.position + placed!.parent!.position, visible, tolerance: 0.05),
                    "Production view carries the click snapshot into the new stone's drop")
            require(ghost.opacity == 0, "Accepted click hides the floating duplicate immediately")
            live.scene!.isPaused = false
            settle(2.1)
            require(abs(placed!.parent!.presentation.position.y - 1) < 0.001, "Live drop finishes on the board")
            click(target)
            require(vm.engine.currentIndex == index + 1, "Clicking an occupied point cannot add another move")
        }
        print("PASS: real 3D hover/click callbacks place Black and White at the pointer during motion, retain the visible drop origin and appearance, and reject occupied clicks")
    }
}

private func + (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
}
