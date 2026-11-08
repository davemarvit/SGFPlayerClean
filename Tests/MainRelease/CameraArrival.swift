import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private struct ArrivalHost: View {
    @ObservedObject var app: AppModel
    @State private var showSettings = false
    @State private var buttonsVisible = true
    var body: some View {
        Group {
            if app.viewMode == .view3D { ContentView3D() }
            else { Color.gray }
        }
        .environmentObject(app)
        .overlay {
            if let vm = app.boardVM {
                SharedOverlays(showSettings: $showSettings, buttonsVisible: $buttonsVisible, app: app, boardVM: vm)
            }
        }
    }
}

private final class ArrivalButtonTarget: NSObject {
    var clicks = 0
    @objc func click(_ sender: Any?) { clicks += 1 }
}

@main struct CameraArrivalCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.camera3DRotationX = 1.4; AppSettings.shared.camera3DPanX = 40
        AppSettings.shared.environment3D = .moon
        let app = AppModel(); app.aiAnalysisEnabled = false; app.showRightPanel = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let game = SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd];W[pp])"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("arrival-\(UUID()).sgf")
        try "(;SZ[19];B[dd];W[pp])".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: game))
        let vm = app.boardVM!
        let model = SceneManager3D()
        model.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
            rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
        let seated = model.cameraNode.simdTransform
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: ArrivalHost(app: app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle(_ seconds: Double = 0.12) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func enter() -> UnifiedSCNView {
            app.viewMode = .view2D; settle()
            app.viewMode = .view3D; settle()
            return UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        }
        func event(_ type: NSEvent.EventType, at point: CGPoint, in target: NSWindow? = nil) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: (target ?? window).windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let live = enter()
        require(live.pointOfView!.position.y > CGFloat(seated.columns.3.y), "Entry begins above the seat despite old preferences")
        let before = live.pointOfView!.simdTransform
        settle(0.3)
        require(live.pointOfView!.simdTransform == before, "Opening stays still during the establishing pause")
        vm.goToEnd(); AppSettings.shared.showMoveNumbers.toggle(); settle(1.35)
        require(live.pointOfView!.simdTransform != before && live.pointOfView!.simdTransform != seated,
            "Camera advances while ordinary game/settings updates run")
        let originalMove = vm.currentMoveIndex
        // Direct event delivery must also consume the release, even if the
        // flight would have naturally finished between press and release.
        live.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 350, y: 350)))
        require(live.pointOfView!.simdTransform == seated, "Mouse-down jumps immediately to the seat")
        settle(0.15)
        live.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 350, y: 350)))
        require(vm.currentMoveIndex == originalMove, "Skipping never places or navigates a move")
        require(live.finishCameraArrival?() == false, "A completed arrival cannot consume another click")

        let again = enter()
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        require(again.filterCameraArrivalEvent(event(.leftMouseDown, at: .zero, in: other)) != nil,
            "Clicks in a different window are unaffected")
        require(again.pointOfView!.simdTransform != seated, "Other windows cannot skip arrival")
        // A window point outside the scene still skips, including overlay controls.
        require(again.filterCameraArrivalEvent(event(.leftMouseDown, at: CGPoint(x: 1190, y: 790))) == nil,
            "Window-wide click is consumed")
        require(again.pointOfView!.simdTransform == seated, "Window-wide skip reaches the exact destination")
        require(again.filterCameraArrivalEvent(event(.leftMouseDragged, at: .zero)) == nil, "Skip drag is consumed")
        require(again.filterCameraArrivalEvent(event(.leftMouseUp, at: .zero)) == nil, "Skip release is consumed")
        require(again.filterCameraArrivalEvent(event(.leftMouseDown, at: .zero)) != nil, "Subsequent input is restored")

        let monitored = enter()
        let target = ArrivalButtonTarget()
        let button = NSButton(title: "Probe", target: target, action: #selector(ArrivalButtonTarget.click(_:)))
        button.frame = NSRect(x: 1050, y: 700, width: 120, height: 40)
        host.addSubview(button)
        let buttonPoint = button.convert(CGPoint(x: 60, y: 20), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApp.postEvent(event(type, at: buttonPoint), atStart: false)
        }
        while let queued = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) {
            NSApp.sendEvent(queued)
        }
        require(monitored.pointOfView!.simdTransform == seated && target.clicks == 0,
            "Installed native event monitor skips through an overlay without activating its button")
        button.removeFromSuperview()

        let natural = enter()
        settle(SceneManager3D.cameraArrivalTotalDuration + 0.1)
        require(natural.pointOfView!.simdTransform == seated, "Clock completes the entire descent")
        require(natural.finishCameraArrival?() == false, "Natural completion clears arrival state")
        for corner in [SCNVector3(-9, 1, -9.696), SCNVector3(9, 1, -9.696), SCNVector3(-9, 1, 9.696), SCNVector3(9, 1, 9.696)] {
            let projected = natural.projectPoint(corner)
            let point = host.convert(natural.convert(CGPoint(x: projected.x, y: projected.y), to: nil), from: nil)
            require(host.bounds.insetBy(dx: 15, dy: 15).contains(point), "Seated view keeps every grid corner in the visible viewport")
        }
        let center = natural.projectPoint(SCNVector3(0, 1, 0))
        natural.onInteraction?(.hover, CGPoint(x: center.x, y: center.y))
        require(natural.usesBoardCursor, "Board picking resumes after arrival")
        natural.onInteraction?(.drag(delta: CGPoint(x: 20, y: 10), modifiers: []), .zero); settle()
        require(natural.pointOfView!.simdTransform != seated, "Manual camera starts from the seated pose")
        natural.onInteraction?(.drag(delta: CGPoint(x: 40, y: 20), modifiers: .shift), .zero)
        natural.onInteraction?(.zoom(amount: 2), .zero); settle()
        let moveBeforeRecenter = vm.currentMoveIndex
        let recenterPoint = host.convert(CGPoint(x: 168, y: host.isFlipped ? 36 : host.bounds.height - 36), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApp.postEvent(event(type, at: recenterPoint), atStart: false)
        }
        while let queued = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) {
            NSApp.sendEvent(queued)
        }
        settle()
        require(natural.pointOfView!.simdTransform != seated, "Toolbar recenter glides rather than jumping")
        settle(SceneManager3D.cameraRecenterDuration)
        require(natural.pointOfView!.simdTransform == seated, "Actual fourth toolbar button resets orbit, pan and zoom")
        require(natural.finishCameraArrival?() == false, "Recenter does not replay arrival")
        require(vm.currentMoveIndex == moveBeforeRecenter, "Recenter leaves the game position unchanged")
        require(AppSettings.shared.camera3DPanX == 0 && AppSettings.shared.camera3DPanY == 0
            && AppSettings.shared.camera3DDistance == Double(SceneManager3D.seatedCameraDistance(boardSize: 19)), "Recenter saves the restored viewport")
        require(NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil) != nil, "Recenter symbol is available")
        func captureToolbar(_ name: String) throws {
            let region = NSRect(x: 0, y: host.isFlipped ? 0 : host.bounds.height - 90, width: 260, height: 90)
            let bitmap = host.bitmapImageRepForCachingDisplay(in: region)!
            host.cacheDisplay(in: region, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-toolbar-\(name).png"))
        }
        try captureToolbar("3d")
        natural.onInteraction?(.drag(delta: CGPoint(x: 10, y: 0), modifiers: .shift), .zero); settle()
        require(abs(AppSettings.shared.camera3DPanX - Double(SceneManager3D.seatedCameraDistance(boardSize: 19)) * 0.02) < 0.001,
            "The next gesture continues from reset state rather than the previous pan")
        AppSettings.shared.environment3D = .tree; settle(0.2)
        require(natural.pointOfView!.position.y > CGFloat(seated.columns.3.y), "Changing scenery starts its fly-in")
        let treeOpening = natural.pointOfView!.simdTransform
        AppSettings.shared.showMoveNumbers.toggle(); settle(1.3)
        require(natural.pointOfView!.simdTransform != treeOpening && natural.pointOfView!.simdTransform != seated,
            "Other settings let the environment fly-in continue")
        AppSettings.shared.environment3D = .cave; settle(0.2)
        require(natural.pointOfView!.position.x < 0 && natural.pointOfView!.position.y > CGFloat(seated.columns.3.y),
            "Rapid scene changes replace the old path with the cave opening")
        require(natural.finishCameraArrival?() == true, "The new environment fly-in remains skippable")
        require(natural.pointOfView!.simdTransform == seated && vm.currentMoveIndex == moveBeforeRecenter,
            "Environment changes land at the same playing view without altering the game")
        let departing = enter()
        let departingCamera = departing.pointOfView!
        app.viewMode = .view2D; settle(0.2)
        let stopped = departingCamera.simdTransform
        settle(0.2)
        require(departingCamera.simdTransform == stopped, "Leaving 3D cancels the old timer")
        try captureToolbar("2d")
        app.viewMode = .view3D; settle()
        let reduced = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        _ = reduced.finishCameraArrival?()
        window.setContentSize(CGSize(width: 750, height: 1000)); settle()
        require(reduced.pointOfView!.camera!.fieldOfView > 60, "Portrait layout preserves framing")
        print("PASS: entry/reentry, updates, skip, natural completion, closer board framing, animated toolbar recenter, saved reset, gesture continuity, environment fly-ins, rapid scene switching, exit cleanup and portrait framing")
    }
}
