import SwiftUI
import SceneKit
import simd
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct OpenTatamiCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.isMuted = true
        AppSettings.shared.folderURL = nil
        require(NSImage(named: TatamiTexture.assetName) != nil, "Bundled weave is available")
        let manager = SceneManager3D()
        let player = SGFPlayer()
        let sgf = "(;SZ[19];B[dd];W[pd];B[dp];W[pp];B[cf];W[nc];B[fc];W[qn];B[cn];W[nq];B[qq];W[pq];B[qp];W[po];B[qo];W[qm];B[dn];W[nf];B[fd];W[nd])"
        let game = SGFGame.from(tree: try SGFParser.parse(text: sgf))
        player.load(game: game); player.seek(to: player.maxIndex)
        manager.updateStones(from: player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) },
            lastMove: nil, moveIndex: player.maxIndex, settings: AppSettings.shared, animate: false)
        manager.updateDebugSettings()
        let floor = manager.scene.rootNode.childNode(withName: "tatami-environment", recursively: true)!
        let initialFloor = floor.simdWorldTransform
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1200, height: 850))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        let renderer = SCNRenderer(device: view.device, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        let poses: [(String, CGFloat, Float, Float, CGFloat, CGFloat)] = [
            ("default", 32, 0.45, 0, 0, 0), ("rotated", 32, 0.1, 0.8, 0, 0),
            ("translated", 35, 0.5, -0.6, 3, -2), ("wide", 100, -0.2, 1.7, 0, 0),
            ("close", 10, 1.8, 0, 0, 0), ("floor-limit", 10, 0.45, 1, 60, 60)]
        for (name, distance, x, y, panX, panY) in poses {
            manager.updateCameraPosition(distance: distance, rotationX: x, rotationY: y, panX: panX, panY: panY)
            SCNTransaction.flush()
            require(floor.simdWorldTransform == initialFloor, "Floor remains fixed relative to board: \(name)")
            require(manager.cameraNode.position.y >= 0.5, "Camera stays above floor: \(name)")
            let image = renderer.snapshot(atTime: 0, with: view.bounds.size, antialiasingMode: .multisampling4X)
            let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try data.write(to: URL(fileURLWithPath: "/private/tmp/sgf-tatami-\(name).png"))
            if ["default", "rotated", "translated"].contains(name) {
                let projected = view.projectPoint(SCNVector3(0, 1, 0))
                let hit = manager.hitTest(point: CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y)), in: view)
                require(hit?.x == 9 && hit?.y == 9, "Board remains clickable through floor scene: \(name)")
            }
        }
        // Test actual visible face hits: a side click must not see the hidden top behind it.
        manager.updateCameraPosition(distance:38,rotationX:-0.25,rotationY:0,panX:0,panY:0)
        SCNTransaction.flush()
        for (point, blocked) in [(SCNVector3(0,1,0),true),(SCNVector3(0,-3,10.773),false)] {
            let projected=view.projectPoint(point)
            require(manager.isPointOnBoard(CGPoint(x:projected.x,y:projected.y),in:view)==blocked,
                    "Only the upward surface blocks camera dragging")
        }
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            require(floor.parent != nil && floor.simdWorldTransform == initialFloor, "Resize preserves environment")
        }

        // Exercise the real SwiftUI gesture bindings and persisted viewport.
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        app.aiAnalysisEnabled = false; app.showRightPanel = false; app.viewMode = .view3D
        let url = URL(fileURLWithPath: "/private/tmp/sgf-camera-\(UUID()).sgf")
        defer { try? FileManager.default.removeItem(at: url) }
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        app.selectGame(SGFGameWrapper(url: url, game: game))
        app.boardVM?.goToEnd()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: ContentView3D().environmentObject(app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.25)) }
        settle()
        let live = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        func supplyCount(_ name: String) -> Int {
            live.scene!.rootNode.childNode(withName: name, recursively: true)!.childNodes
                .filter { $0.name == "supply-stone" && !$0.isHidden }.count
        }
        require(supplyCount("black-stone-bowl") == 171 && supplyCount("white-stone-bowl") == 170,
            "Actual 3D view consumes a supply stone for each played move")
        app.boardVM?.goToStart(); settle()
        require(supplyCount("black-stone-bowl") == 181 && supplyCount("white-stone-bowl") == 180,
            "Rewinding the actual view refills both bowls")
        app.boardVM?.goToEnd(); settle()
        require(supplyCount("black-stone-bowl") == 171 && supplyCount("white-stone-bowl") == 170,
            "Replay restores the depleted supply")
        AppSettings.shared.showMoveNumbers = true; settle()
        func marker() -> SCNNode? { live.scene!.rootNode.childNode(withName: "MARKER_NUMBER", recursively: true) }
        var previousMarker = marker()
        var rebuilds = 0
        let benchmarkStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<40 {
            live.onInteraction?(.drag(delta: CGPoint(x: 3, y: 0), modifiers: []), .zero)
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            let next = marker()
            if next !== previousMarker { rebuilds += 1 }
            previousMarker = next
        }
        print("CAMERA BENCHMARK: 40 drags, seconds=", CFAbsoluteTimeGetCurrent() - benchmarkStart, "marker rebuilds=", rebuilds)
        require(rebuilds == 0, "Camera gestures must not rebuild move labels")
        let forward = live.onInteraction
        var clicks = 0
        func observeClicks() {
            // SwiftUI refreshes the event closure during hover/state changes.
            // Reattach the probe immediately before each native event sequence.
            live.onInteraction = { event, point in
                if case .click = event { clicks += 1 } else { forward?(event, point) }
            }
        }
        let projectedBoard = live.projectPoint(SCNVector3(0, 1, 0))
        let boardPoint = CGPoint(x: projectedBoard.x, y: projectedBoard.y)
        let projectedBorder = live.projectPoint(SCNVector3(9.8, 1, 0))
        let borderPoint = CGPoint(x: projectedBorder.x, y: projectedBorder.y)
        let outside = CGPoint(x: 10, y: 10)
        require(live.canStartCameraDrag?(boardPoint, live) == false, "Board blocks gesture starts")
        require(live.canStartCameraDrag?(borderPoint, live) == false, "Wooden border blocks gesture starts too")
        require(live.canStartCameraDrag?(outside, live) == true, "Surroundings allow gesture starts")
        func event(_ type: NSEvent.EventType, _ point: CGPoint, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: live.convert(point, to: nil), modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func drag(from: CGPoint, to: CGPoint, flags: NSEvent.ModifierFlags) {
            observeClicks()
            live.mouseDown(with: event(.leftMouseDown, from, flags))
            live.mouseDragged(with: event(.leftMouseDragged, to, flags))
            live.mouseUp(with: event(.leftMouseUp, to, flags))
            settle()
        }
        for flags: NSEvent.ModifierFlags in [[], .shift] {
            let before = live.pointOfView!.simdTransform
            drag(from: boardPoint, to: outside, flags: flags)
            require(live.pointOfView!.simdTransform == before, "A drag starting on the board never moves the camera")
        }
        require(clicks == 0, "Rejected drags do not accidentally place stones")
        observeClicks()
        live.mouseDown(with: event(.leftMouseDown, boardPoint, []))
        live.mouseUp(with: event(.leftMouseUp, boardPoint, []))
        require(clicks == 1, "Ordinary board clicks still work")
        for flags: NSEvent.ModifierFlags in [[], .shift] {
            let before = live.pointOfView!.simdTransform
            drag(from: outside, to: CGPoint(x: outside.x + 20, y: outside.y + 10), flags: flags)
            require(live.pointOfView!.simdTransform != before, "Outside drag still rotates or translates")
        }
        live.onInteraction = forward
        let start = live.pointOfView!.simdTransform
        let initialCenter = live.projectPoint(SCNVector3(0, 1, 0))
        live.onInteraction?(.drag(delta: CGPoint(x: 30, y: 12), modifiers: .shift), .zero)
        settle()
        require(live.pointOfView!.simdTransform != start, "Shift drag translates the actual view")
        require(AppSettings.shared.camera3DPanX != 0, "Translation persists")
        let movedCenter = live.projectPoint(SCNVector3(0, 1, 0))
        require(movedCenter.x > initialCenter.x && movedCenter.y > initialCenter.y, "Panning follows the drag direction")
        let translated = live.pointOfView!.simdTransform
        live.onInteraction?(.drag(delta: CGPoint(x: 60, y: 20), modifiers: []), .zero)
        settle()
        require(live.pointOfView!.simdTransform != translated, "Drag rotates the actual view")
        let distance = AppSettings.shared.camera3DDistance
        live.onInteraction?(.zoom(amount: 1), .zero); settle()
        require(AppSettings.shared.camera3DDistance < distance, "Zoom uses existing controls")
        window.setContentSize(CGSize(width: 800, height: 1000)); settle()
        host.layoutSubtreeIfNeeded()
        require(abs(live.bounds.height - 1000) < 1, "Floor fills tall viewports")
        require(live.pointOfView!.camera!.fieldOfView > 60, "Tall viewport retains board framing")
        live.onInteraction?(.drag(delta:CGPoint(x:0,y:1000),modifiers:[]),.zero); settle()
        require(abs(AppSettings.shared.camera3DRotationX + 0.55) < 0.001,"Mouse orbit reaches the new low horizon view")
        require(live.pointOfView!.position.y >= 0.5,"Low orbit preserves camera clearance")
        print("PASS: bundled texture, orbit/pan/zoom, camera clearance, board hit testing, resize, real gesture bindings, drag direction, saved viewport and tall windows")
    }
}
