import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private final class CursorOverlayFixture: ObservableObject {
    @Published var point: CGPoint?
}

private struct CursorTestScene: View {
    @ObservedObject var overlay: CursorOverlayFixture
    var body: some View {
        ZStack {
            ContentView3D()
            if let point = overlay.point {
                Button("Control") {}.frame(width: 80, height: 80).background(.red).position(point)
            }
        }
    }
}

@main struct GhostStoneCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil
        AppSettings.shared.isMuted = true
        AppSettings.shared.moveInterval = 10
        let app = AppModel()
        app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ghost-\(UUID()).sgf")
        let sgf = "(;SZ[9]RU[Japanese]KM[6.5];B[aa];W[bb])"
        try sgf.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        app.selectGame(SGFGameWrapper(url: temp, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        let vm = app.boardVM!
        func settle(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        let point = BoardPosition(4, 4)
        settle()
        vm.updateGhostStone(at: point)
        require(vm.ghostPosition == point && vm.ghostColor == .black, "Review shows a black ghost before the first move with AI off")
        vm.seekToMove(1); settle(); vm.updateGhostStone(at: point)
        require(vm.ghostPosition == point && vm.ghostColor == .white, "Review history shows the next player's ghost")
        vm.updateGhostStone(at: BoardPosition(0, 0))
        require(vm.ghostPosition == nil, "Occupied points hide the ghost")
        vm.updateGhostStone(at: BoardPosition(9, 9))
        require(vm.ghostPosition == nil, "Out-of-bounds points hide the ghost")

        app.copyCurrentBoard(to: .localPlay); settle()
        vm.updateGhostStone(at: point)
        require(vm.ghostPosition == nil, "Local history cannot offer an unplayable move")
        vm.goToEnd(); settle(); vm.updateGhostStone(at: point)
        require(vm.ghostPosition == point && vm.ghostColor == .black, "Local play restores the ghost at the latest position")
        let original = app.player.board
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let host = NSHostingView(rootView: BoardView2D(boardVM: vm, layoutVM: app.layoutVM, size: CGSize(width: 500, height: 539)).environmentObject(app))
        window.setContentSize(CGSize(width: 500, height: 539))
        window.contentView = host; window.orderFront(nil); settle()
        func snapshot2D() -> Data {
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])!
        }
        vm.clearGhostStone(); settle()
        let empty = snapshot2D()
        vm.updateGhostStone(at: point); settle()
        let ghost = snapshot2D()
        require(empty != ghost, "2D rendering visibly changes when the ghost appears")
        try ghost.write(to: URL(fileURLWithPath: "/private/tmp/sgf-ghost-2d.png"))
        vm.clearGhostStone(); settle()
        require(empty == snapshot2D(), "2D ghost disappears cleanly")

        app.viewMode = .view3D
        window.setContentSize(CGSize(width: 1000, height: 750))
        let overlay = CursorOverlayFixture()
        window.contentView = NSHostingView(rootView: CursorTestScene(overlay: overlay).environmentObject(app)); settle(0.4)
        let live = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        let center = live.projectPoint(SCNVector3(0, 1, 0))
        let location = CGPoint(x: center.x, y: center.y)
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: live.convert(location, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
        live.mouseMoved(with: event); settle()
        require(live.usesBoardCursor, "Legal board hover replaces the system cursor")
        func cursorHasVisiblePixels() -> Bool {
            guard let data = NSCursor.current.image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data) else { return false }
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { return true }
                }
            }
            return false
        }
        require(!cursorHasVisiblePixels(), "Native arrow is actually transparent above the board")
        require(vm.ghostPosition == point && vm.ghostColor == .black, "Actual 3D mouse hover reaches the shared ghost model")
        var sphere: SCNNode?
        live.scene!.rootNode.enumerateChildNodes { node, _ in
            if node.name == "ghost-stone", node.opacity > 0, node.position.x == 0, node.position.z == 0 { sphere = node }
        }
        require(sphere != nil, "3D ghost node is visible at the hovered intersection")
        let landing = live.scene!.rootNode.childNode(withName: "ghost-landing-marker", recursively: true)!
        require(landing.opacity == 1 && landing.position.x == sphere!.position.x && landing.position.z == sphere!.position.z,
                "Landing glow marks the intersection directly below the floating stone")
        require(sphere!.position.y > landing.position.y + 1, "Ghost floats above the board")
        if let tiff = live.snapshot().tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-ghost-3d.png"))
        }
        live.onInteraction?(.exit, .zero); settle()
        require(vm.ghostPosition == nil && sphere?.opacity == 0 && landing.opacity == 0, "Leaving the 3D board hides the ghost and landing glow")
        require(!live.usesBoardCursor, "Leaving the board restores the normal cursor")
        require(cursorHasVisiblePixels(), "Restored native cursor has a visible image")
        let occupied = live.projectPoint(SCNVector3(-6.75, 1, -6.75 * 1.0773))
        func mouseEvent(at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: live.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 2, clickCount: 0, pressure: 0)!
        }
        live.mouseMoved(with: mouseEvent(at: CGPoint(x: occupied.x, y: occupied.y))); settle()
        require(live.usesBoardCursor && vm.ghostPosition == nil && sphere?.opacity == 0,
                "Occupied intersection keeps the dot cursor without a playable ghost")
        require(landing.opacity > 0.3 && landing.opacity < 0.6 && landing.position.y > 2,
                "Dim pointer stays visible above the existing stone")
        if let tiff = live.snapshot().tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-board-cursor-occupied.png"))
        }
        for notification in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
            live.mouseMoved(with: event)
            NotificationCenter.default.post(name: notification,
                object: notification == NSWindow.didResignKeyNotification ? window : NSApplication.shared)
            require(!live.usesBoardCursor && landing.opacity == 0, "Losing window/application focus restores cursor and clears indicator")
        }
        live.mouseMoved(with: event)
        let container = window.contentView!
        let overlayPoint = live.convert(location, to: container)
        overlay.point = CGPoint(x: overlayPoint.x, y: container.isFlipped ? overlayPoint.y : container.bounds.height - overlayPoint.y)
        settle()
        NSApplication.shared.postEvent(event, atStart: false)
        if let queued = NSApplication.shared.nextEvent(matching: .mouseMoved, until: Date().addingTimeInterval(0.2), inMode: .default, dequeue: true) {
            NSApplication.shared.sendEvent(queued)
        }
        live.mouseMoved(with: event)
        settle()
        require(!live.usesBoardCursor, "Moving onto an overlaid control restores the normal cursor")
        live.cursorUpdate(with: event)
        require(!live.usesBoardCursor && cursorHasVisiblePixels(), "Board tracking cannot reclaim the cursor from an overlaid control")
        overlay.point = nil; settle()
        live.mouseMoved(with: event)
        live.mouseMoved(with: mouseEvent(at: CGPoint(x: 5, y: 5))); settle()
        require(!live.usesBoardCursor && landing.opacity == 0, "Board surroundings retain the normal cursor")
        require(app.player.board == original && app.player.maxIndex == 2, "Hover never changes the board or move history")
        vm.updateGhostStone(at: point); vm.placeStone(at: point); settle()
        require(vm.ghostPosition == nil, "Placing a move clears the now-occupied ghost")
        vm.updateGhostStone(at: BoardPosition(5, 5))
        require(vm.ghostColor == .white, "Next hover uses the new player's color")
        vm.passLocally(); vm.passLocally(); settle()
        vm.updateGhostStone(at: point)
        require(vm.localScoringVisible && vm.ghostPosition == nil, "Scoring suppresses placement ghosts")
        vm.resumeLocalPlay(); settle(); vm.updateGhostStone(at: BoardPosition(5, 5))
        require(vm.ghostPosition != nil, "Resuming play restores the ghost")
        vm.isOnlineContext = true; vm.updateGhostStone(at: point)
        require(vm.ghostPosition == nil, "Disconnected online contexts cannot offer moves")
        vm.isOnlineContext = false
        let ko = "(;SZ[9]RU[Japanese]AB[ba][ab][bc]AW[bb][ca][db][cc];B[cb])"
        app.selectGame(SGFGameWrapper(url: temp, game: SGFGame.from(tree: try SGFParser.parse(text: ko))))
        vm.goToEnd(); settle()
        vm.updateGhostStone(at: BoardPosition(1, 1))
        require(vm.ghostPosition == nil, "Illegal ko recapture has no playable ghost")
        vm.updateGhostStone(at: point)
        require(vm.ghostPosition == point, "Legal move beside a ko still has a ghost")
        vm.goToStart(); settle(); vm.updateGhostStone(at: point)
        vm.startAutoPlay(); settle()
        require(vm.ghostPosition == nil, "Playback clears an existing ghost")
        vm.updateGhostStone(at: point)
        require(vm.ghostPosition == nil, "Playback suppresses new ghosts")
        vm.stopAutoPlay()
        let resized = SceneManager3D()
        for size in [19, 9, 13, 19, 9] {
            resized.updateBoardSize(size)
            resized.updateGhostStone(at: BoardPosition(size / 2, size / 2), color: .white)
            var ghosts: [SCNNode] = []
            resized.scene.rootNode.enumerateChildNodes { node, _ in
                if node.name == "ghost-stone" { ghosts.append(node) }
            }
            require(ghosts.count == 1 && ghosts[0].opacity > 0, "Exactly one visible ghost survives resize to \(size)")
            require(abs(ghosts[0].position.x) < 0.001 && abs(ghosts[0].position.z) < 0.001, "Resized ghost matches the center intersection")
            resized.clearGhostStone()
            require(ghosts[0].opacity == 0, "Resized ghost clears")
        }
        live.mouseMoved(with: event)
        window.contentView = nil; settle()
        require(!live.usesBoardCursor, "Removing the 3D view restores the normal cursor")
        print("PASS: Review and Local Play ghosts, both colors, 2D rendering, actual 3D hover/exit, occupied/outside/history/scoring guards, placement cleanup and board isolation")
    }
}
