import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct AnalysisPlacementCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.showDropInAnimation = true
        AppSettings.shared.environment3D = .monastery
        let app = AppModel(); app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("placement-\(UUID()).sgf")
        let sgf = "(;SZ[19];B[dd];W[pd];B[dp];W[pp])"
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        app.aiAnalysisEnabled = true; app.viewMode = .view3D
        let vm = app.boardVM!
        vm.goToStart() // Exercise forward placement from the beginning.
        let candidate = AIMoveInfo(move: "K10", visits: 100, winrate: 0.6, scoreLead: 2, pv: nil)
        for turn in 0...4 {
            KataGoEngine.shared.currentAnalysisData[turn] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: turn,
                moveInfos: [candidate], rootInfo: AIRootInfo(winrate: 0.6, scoreLead: Double(turn), visits: 100))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ContentView3D().environmentObject(app))
        window.orderFront(nil); defer { window.orderOut(nil) }
        func settle(_ duration: Double) { RunLoop.main.run(until: Date().addingTimeInterval(duration)); SCNTransaction.flush() }
        settle(0.4)
        let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        _ = view.finishCameraArrival?(); settle(0.05)
        func nodes(_ name: String) -> [SCNNode] {
            var result: [SCNNode] = []
            view.scene!.rootNode.enumerateChildNodes { node, _ in if node.name == name { result.append(node) } }
            return result
        }
        func placing() -> Bool { nodes("board-stone").contains { $0.parent?.action(forKey: "stone-placement-drop") != nil } }
        func requireQuietFlight() {
            require(placing(), "Fixture must catch a stone in flight")
            let hints = nodes("AI_HINT")
            require(!hints.isEmpty && hints.allSatisfy { $0.isHidden }, "Values stay hidden throughout placement")
        }
        func waitForLanding(_ timeout: Double) {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                settle(0.025)
                if placing() { requireQuietFlight() }
            } while placing() && Date() < deadline
            settle(0.04)
            require(!placing(), "Placement completes")
            require(!nodes("AI_HINT").isEmpty && nodes("AI_HINT").allSatisfy { !$0.isHidden }, "Current values return automatically after landing")
        }
        require(!nodes("AI_HINT").isEmpty && nodes("AI_HINT").allSatisfy { !$0.isHidden }, "Initial position displays values")
        vm.stepForward()
        let flightDeadline = Date().addingTimeInterval(0.5)
        while !placing() && Date() < flightDeadline { settle(0.002) }
        requireQuietFlight()
        // A fresh report during the flight cannot bring the numbers back early.
        var refreshed = KataGoEngine.shared.currentAnalysisData[1]!
        refreshed.ownership = Array(repeating: 0, count: 361)
        KataGoEngine.shared.currentAnalysisData[1] = refreshed
        settle(0.025); requireQuietFlight(); waitForLanding(1)
        vm.stepForward(); settle(0.025)
        vm.stepForward(); settle(0.025); requireQuietFlight()
        vm.stepBackward(); settle(0.025); waitForLanding(1)
        require(vm.currentMoveIndex == 2, "Rapid forward/back navigation keeps the requested position")
        AppSettings.shared.environment3D = .spaceStation; settle(0.2)
        _ = view.finishCameraArrival?(); settle(0.05)
        vm.stepForward(); settle(0.05); requireQuietFlight()
        settle(0.4); requireQuietFlight(); waitForLanding(3)
        vm.stepForward(); settle(0.05); requireQuietFlight()
        app.aiAnalysisEnabled = false; settle(2.3)
        require(nodes("AI_HINT").isEmpty, "Late landing callback must not restore disabled AI")
        print("PASS: analysis annotations stay hidden during normal/slow placement, restore after landing, survive live reports and rapid rewind, and respect AI off")
    }
}
