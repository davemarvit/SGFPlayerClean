import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private struct FinalMoveHost: View {
    @ObservedObject var app: AppModel
    var body: some View {
        if let vm = app.boardVM {
            BoardWorkspaceView(vm: vm) { ContentView3D() }.environmentObject(app)
        }
    }
}
@main struct FinalMoveStabilityCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.environment3D = .monastery
        let app = AppModel(); app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let sgf = "(;SZ[19]RE[W+0.5];B[dd];W[pp];B[];W[] )"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("final-move-\(UUID()).sgf")
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        app.viewMode = .view3D
        let vm = app.boardVM!
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: FinalMoveHost(app: app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded(); SCNTransaction.flush()
        }
        vm.seekToMove(2); settle()
        let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        _ = view.finishCameraArrival?(); settle()
        let corners = [SCNVector3(-10, 1, -10.773), SCNVector3(10, 1, 10.773)]
        func projected() -> [CGPoint] {
            corners.map { let p = view.projectPoint($0)
                return view.convert(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), to: host) }
        }
        for size in [CGSize(width: 1280, height: 900), CGSize(width: 1000, height: 650)] {
            window.setContentSize(size); vm.seekToMove(2); settle()
            let before = projected()
            for index in [3, 4, 3, 2, 4, 0] {
                vm.seekToMove(index); settle()
                if index == 3 {
                    require(vm.playbackPassStatus == "Black passed · White to move", "First pass identifies Black")
                } else if index == 4 {
                    require(vm.playbackPassStatus == "White passed · Both players have passed", "Final pass identifies White")
                } else {
                    require(vm.playbackPassStatus == nil, "Ordinary moves clear the pass status")
                }
                for (a, b) in zip(before, projected()) {
                    require(abs(a.x-b.x) < 0.25 && abs(a.y-b.y) < 0.25,
                        "Move \(index), \(size): board jumped by \(b.x-a.x), \(b.y-a.y)")
                }
            }
        }
        vm.seekToMove(3); vm.isOnlineContext = true; settle()
        require(vm.playbackPassStatus == "Black passed · White to move", "Online playback also identifies passes")
        let controls = NSHostingView(rootView: PlaybackControlsView(boardVM: vm).environmentObject(app))
        let controlsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        controlsWindow.contentView = controls; controlsWindow.orderFront(nil)
        defer { controlsWindow.orderOut(nil) }
        vm.seekToMove(2); settle()
        let controlsHeight = controls.fittingSize.height
        require(controlsHeight > 0, "Shared 2D/3D controls are laid out")
        for index in [3, 4, 2, 0] {
            vm.seekToMove(index); settle(); controls.layoutSubtreeIfNeeded()
            require(abs(controls.fittingSize.height - controlsHeight) < 0.25,
                "Shared controls keep the same height at move \(index)")
        }
        let beforeEstimate = projected()
        for estimate in [true, false] {
            vm.territoryIsEstimate = estimate; settle()
            for (a, b) in zip(beforeEstimate, projected()) {
                require(abs(a.x-b.x) < 0.25 && abs(a.y-b.y) < 0.25, "Scoring estimate notice must not move board")
            }
        }
        print("PASS: first pass, final pass, backward/forward navigation, and estimate notice keep board fixed; both players identified")
    }
}
