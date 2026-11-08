import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private struct HoverStabilityHost: View {
    @ObservedObject var app: AppModel
    var body: some View {
        if let vm = app.boardVM {
            BoardWorkspaceView(vm: vm) { ContentView3D() }.environmentObject(app)
        }
    }
}

@main struct HoverBoardStabilityCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil
        AppSettings.shared.isMuted = true
        AppSettings.shared.environment3D = .monastery
        let app = AppModel(); app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let sgf = "(;SZ[19];B[dd];W[pd];B[dp];W[pp])"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hover-stability-\(UUID()).sgf")
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        app.viewMode = .view3D
        let vm = app.boardVM!
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: HoverStabilityHost(app: app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle(_ duration: Double = 0.15) {
            RunLoop.main.run(until: Date().addingTimeInterval(duration))
            host.layoutSubtreeIfNeeded(); SCNTransaction.flush()
        }
        settle(0.4); vm.seekToMove(1); settle()
        vm.canPreviewAnalysis = { true }
        let candidate = AIMoveInfo(move: "C17", visits: 50, winrate: 0.6, scoreLead: 2,
                                   pv: ["C17", "E15", "pass"])
        KataGoEngine.shared.currentAnalysisData[1] = AIAnalysis(id: "fixture", isDuringSearch: false,
            turnNumber: 1, moveInfos: [candidate], rootInfo: nil)
        let original = app.player.board
        let corners = [SCNVector3(-10, 1, -10.773), SCNVector3(10, 1, -10.773),
                       SCNVector3(-10, 1, 10.773), SCNVector3(10, 1, 10.773)]
        for size in [CGSize(width: 1280, height: 900), CGSize(width: 1000, height: 650)] {
            window.setContentSize(size)
            for expanded in [false, true] {
                vm.reviewTreeCollapsed = !expanded
                app.showRightPanel = expanded
                settle()
                let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
                _ = view.finishCameraArrival?(); settle()
                func projectedCorners() -> [CGPoint] {
                    corners.map {
                        let p = view.projectPoint($0)
                        return view.convert(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), to: host)
                    }
                }
                let before = projectedCorners()
                let camera = view.pointOfView!.simdTransform
                let fieldOfView = view.pointOfView!.camera!.fieldOfView
                func check(_ stage: String) {
                    for (a, b) in zip(before, projectedCorners()) {
                        require(abs(a.x - b.x) < 0.25 && abs(a.y - b.y) < 0.25,
                            "\(stage), \(size), panels=\(expanded): board shifted by (\(b.x-a.x), \(b.y-a.y)) points")
                    }
                    require(view.pointOfView!.simdTransform == camera, "\(stage): camera stays fixed")
                    require(abs(view.pointOfView!.camera!.fieldOfView - fieldOfView) < 0.001,
                            "\(stage): lens stays fixed")
                    require(app.player.board == original && app.player.currentIndex == 1,
                            "\(stage): actual position is preserved")
                }
                let p = view.projectPoint(SCNVector3(-7, 1, -7 * 1.0773))
                view.onInteraction?(.hover, CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)))
                settle(0.2)
                require(vm.ghostPosition == BoardPosition(2, 2) && !vm.isPreviewingVariation,
                        "Actual board hover shows a ghost during dwell")
                check("ghost dwell")
                settle(0.4)
                require(vm.variationFrame?.numbers[BoardPosition(2, 2)] == 1, "First hypothetical stone lands")
                var firstLabel: SCNNode?
                view.scene!.rootNode.enumerateChildNodes { node, _ in
                    if node.name == "ai-variation-number" { firstLabel = node }
                }
                require(firstLabel != nil && firstLabel?.parent?.childNode(withName: "board-stone", recursively: false) != nil,
                        "First stone already carries its number")
                _ = view.snapshot()
                require(abs(Double(firstLabel!.presentation.position.y - firstLabel!.position.y)) < 0.001,
                        "The first rendered number is already at the stone surface, without a delayed rise")
                check("first preview move")
                settle(0.7)
                require(vm.variationFrame?.numbers[BoardPosition(4, 4)] == 2, "Continuation still plays")
                require(firstLabel?.parent != nil, "Earlier numbers stay attached as the next move lands")
                check("continuation")
                settle(0.7); check("completed preview")
                view.onInteraction?(.exit, .zero); settle()
                require(!vm.isPreviewingVariation, "Leaving restores the game")
                check("restoration")
                vm.hoverAnalysis(at: BoardPosition(5, 5)); settle(0.6)
                require(vm.variationStatus != nil, "Uncached hover reports unavailable offline analysis")
                check("analysis status")
                vm.hoverAnalysis(at: nil); settle(); check("status cleared")
            }
        }
        print("PASS: rendered board corners and camera remain fixed through hover dwell, landing, continuation, completion, restoration and status changes, at two sizes with panels open/closed")
    }
}
