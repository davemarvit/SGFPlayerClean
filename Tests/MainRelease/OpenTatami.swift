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
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            require(floor.parent != nil && floor.simdWorldTransform == initialFloor, "Resize preserves environment")
        }

        // Exercise the real SwiftUI gesture bindings and persisted viewport.
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        app.aiAnalysisEnabled = false; app.showRightPanel = false; app.viewMode = .view3D
        let url = URL(fileURLWithPath: "/private/tmp/sgf-tatami-fixture.sgf")
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
        print("PASS: bundled texture, orbit/pan/zoom, camera clearance, board hit testing, resize, real gesture bindings, drag direction, saved viewport and tall windows")
    }
}
