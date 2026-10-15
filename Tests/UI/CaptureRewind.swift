import SwiftUI
import SceneKit
@testable import SGF_Player_Offline_Review

/// Exercise the real view/model subscription path, not just manually updated SceneKit nodes.
@main struct CaptureRewindCheck {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.offline-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        UserDefaults.standard.set(0, forKey: "stoneVolume")
        let sgf = "(;SZ[9]RU[Chinese-OGS]KM[0.5]HA[2]PL[W]AB[cg][gc];W[cc];B[gg];W[ee])"
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("capture-rewind-\(UUID()).sgf")
        try sgf.write(to: fixture, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let model = AppModel()
        model.viewMode = .view3D
        model.showRightPanel = false
        model.selectGame(SGFGameWrapper(url: fixture, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        #if SGF_OGS_REVIEW
        model.copyCurrentBoard(to: .localPlay)
        #endif
        let host = NSHostingView(rootView: ContentView3D().environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 650),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Offline capture check"
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        func wait(_ duration: Double) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
        func findSceneView(_ view: NSView) -> UnifiedSCNView? {
            if let found = view as? UnifiedSCNView { return found }
            for child in view.subviews { if let found = findSceneView(child) { return found } }
            return nil
        }
        wait(0.5)
        let view = findSceneView(host)!
        model.boardVM!.goToEnd(); wait(0.2)
        for (x, y) in [(0,0), (2,0), (1,0), (0,1), (-1,-1), (1,1)] {
            let index = model.player.currentIndex
            if x < 0 { precondition(model.player.tryPlayMove(color: model.player.turn, x: x, y: y) == nil) }
            else { model.boardVM!.placeStone(at: BoardPosition(y, x)) }
            precondition(model.player.currentIndex == index + 1)
            wait(0.15)
        }
        func check3D(_ label: String, captures: Int) {
            let lid = view.scene!.rootNode.childNode(withName: "white-player-lid", recursively: true)!
            let count = lid.childNodes.filter { $0.name == "captured-black" }.count
            let shown = lid.presentation.childNodes.filter { $0.name == "captured-black" }.count
            precondition(model.player.capturesByWhite == captures)
            precondition(model.boardVM!.whiteCapturedCount == captures)
            precondition(count == captures && shown == captures, "3D lid failed: \(label)")
            let text = lid.childNode(withName: "capture-count", recursively: false)!.geometry as! SCNText
            precondition(text.string as? String == String(captures))
            print("3D \(label): engine, view model, visible stones, and label all = \(captures)")
        }
        check3D("captured", captures: 2)
        // The UI probe can run while the display is asleep, when SCNView's
        // display link does not advance. Step the actual hosted scene explicitly
        // to verify physics without depending on window visibility or wall time.
        let renderer = SCNRenderer(device: view.device, options: nil)
        renderer.scene = view.scene; renderer.pointOfView = view.pointOfView
        for frame in 0..<120 {
            _ = renderer.snapshot(atTime: Double(frame) / 60, with: CGSize(width: 96, height: 96), antialiasingMode: .none)
        }
        let lid = view.scene!.rootNode.childNode(withName: "white-player-lid", recursively: true)!
        let centered = lid.childNodes.filter { $0.name == "captured-black" }.allSatisfy {
            let position = $0.presentation.position
            return hypot(Double(position.x), Double(position.z)) < 1.3 && position.y < 0.5
        }
        model.boardVM!.stepBackward(); wait(0.3); check3D("rewound past capture", captures: 0)
        model.boardVM!.goToStart(); wait(0.3); check3D("rewound to start", captures: 0)
        precondition(model.player.board.stones.count == 2)
        model.boardVM!.goToEnd(); wait(0.3); check3D("replayed", captures: 2)

        // Keep the actual 2D view mounted across the rewind. A fresh root would conceal
        // the old missing-observer bug by supplying the correct count only on creation.
        let host2D = NSHostingView(rootView: ContentView2D().environmentObject(model))
        window.contentView = host2D; wait(0.5)
        func snapshot(_ view: NSView, _ name: String) throws -> CGImage {
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])!
            try data.write(to: URL(fileURLWithPath: "/private/tmp/sgf-ui-\(name).png"))
            return bitmap.cgImage!
        }
        let captured = try snapshot(host2D, "captured")
        model.boardVM!.goToStart(); wait(0.5)
        let rewound = try snapshot(host2D, "rewound")
        let freshHost = NSHostingView(rootView: ContentView2D().environmentObject(model))
        window.contentView = freshHost; wait(0.5)
        let fresh = try snapshot(freshHost, "fresh-start")
        // Interior of the lowered upper lid in this fixed 800x650 fixture; excludes
        // the board, player metadata, controls, and other independently changing UI.
        func lidPixels(_ image: CGImage) -> Data {
            let scale = CGFloat(image.width) / 800
            let crop = image.cropping(to: CGRect(x: 560 * scale, y: 75 * scale, width: 120 * scale, height: 75 * scale))!
            return NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:])!
        }
        precondition(lidPixels(captured) != lidPixels(fresh), "Fixture did not show the two captured stones")
        guard lidPixels(rewound) == lidPixels(fresh) else {
            fputs("FAIL: 2D lid retained captured stones after rewind\n", stderr); exit(1)
        }
        guard centered else {
            fputs("FAIL: Small 3D captures remained near the lip\n", stderr); exit(1)
        }
        print("PASS: 2D lid clears without remounting; 3D captures settle near center and rewind/replay correctly.")
    }
}
