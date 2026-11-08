import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private struct EntryHost: View {
    @ObservedObject var app: AppModel
    var body: some View {
        Group {
            if app.viewMode == .view3D { ContentView3D().environmentObject(app) }
            else { Color.gray }
        }
    }
}

@main struct SettledEntryCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        let settings = AppSettings.shared
        settings.folderURL = nil; settings.analysisEnabled = false; settings.isMuted = true
        settings.showDropInAnimation = true
        let app = AppModel(); app.aiAnalysisEnabled = false; app.showRightPanel = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let coordinates = (0..<260).map { i in
            "[\(Character(UnicodeScalar(97 + i % 19)!))\(Character(UnicodeScalar(97 + i / 19)!))]"
        }
        let black = coordinates.enumerated().filter { $0.offset % 2 == 0 }.map(\.element).joined()
        let white = coordinates.enumerated().filter { $0.offset % 2 == 1 }.map(\.element).joined()
        let sgf = "(;SZ[19]AB\(black)AW\(white))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settled-entry-\(UUID()).sgf")
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        require(app.boardVM!.displayedStones.count == 260, "Fixture restores 260 existing stones")
        app.viewMode = .view2D
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: EntryHost(app: app))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        for environment in [PlayingEnvironment.gardenRoom, .spaceStation] {
            app.viewMode = .view2D; settle(0.1)
            settings.environment3D = environment
            app.viewMode = .view3D; settle(0.1)
            let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
            let opening = view.pointOfView!.simdTransform
            var count = 0
            view.scene!.rootNode.enumerateChildNodes { node, _ in
                guard node.name == "board-stone", let anchor = node.parent else { return }
                count += 1
                require(!anchor.hasActions && !node.hasActions, "Initial position never schedules a drop or wobble in \(environment)")
                require(abs(anchor.position.y - 1) < 0.001, "Every existing stone starts on the board")
            }
            require(count == 260, "Production view includes every restored stone")
            settings.showMoveNumbers.toggle(); settle(0.2)
            require(view.pointOfView!.simdTransform == opening, "Routine updates retain the minimum opening hold")
            let observedAt = CACurrentMediaTime()
            while view.pointOfView!.simdTransform == opening && CACurrentMediaTime() - observedAt < 1.7 {
                settle(0.02)
            }
            require(view.pointOfView!.simdTransform != opening, "Camera departs promptly in \(environment)")
            require(view.finishCameraArrival?() == true, "Tour remains skippable after departure")
            print("PASS: \(environment) production 2D-to-3D entry starts with 260 resting stones and a short opening")
        }
    }
}
