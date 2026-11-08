import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private struct FramingHost: View {
    @ObservedObject var app: AppModel
    var body: some View {
        BoardWorkspaceView(vm: app.boardVM!) { ContentView3D() }
            .environmentObject(app)
    }
}
@main struct AnalysisReframingCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.analysisEnabled = true
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let game = SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd];W[pp])"))
        app.selectGame(SGFGameWrapper(url: FileManager.default.temporaryDirectory.appendingPathComponent("framing-\(UUID()).sgf"), game: game))
        app.viewMode = .view3D
        app.aiAnalysisEnabled = false; app.showRightPanel = false
        app.boardVM!.reviewTreeCollapsed = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: FramingHost(app: app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)); host.layoutSubtreeIfNeeded(); SCNTransaction.flush() }
        settle(1.0)
        let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        _ = view.finishCameraArrival?(); settle(0.05)
        let pose = view.pointOfView!.simdTransform
        func sample() -> (x: CGFloat, lens: CGFloat) {
            let p = view.projectPoint(SCNVector3(0, 1, 0))
            return (view.convert(CGPoint(x: p.x, y: p.y), to: host).x, view.pointOfView!.camera!.fieldOfView)
        }
        let original = sample()
        func transition(_ enabled: Bool) -> (x: CGFloat, lens: CGFloat) {
            let before = sample()
            app.aiAnalysisEnabled = enabled
            var frames = [before]
            let deadline = Date().addingTimeInterval(1.0)
            while Date() < deadline { settle(0.02); frames.append(sample()) }
            let final = frames.last!
            let travel = abs(final.x - before.x)
            let steps = zip(frames, frames.dropFirst()).map { abs($1.x - $0.x) }
            require(travel > 70, "AI toggle changes the usable board center: \(before) -> \(final), available=\(app.isAIAvailable), reason=\(app.aiUnavailableReason ?? "none"), mode=\(app.mode), collapsed=\(app.boardVM!.reviewTreeCollapsed)")
            require(steps.max()! < travel * 0.3, "Camera framing glides without a sudden positional jump: \(steps.max()!) / \(travel)")
            require(frames.filter { abs($0.x - before.x) > 4 && abs($0.x - final.x) > 4 }.count > 8, "Several intermediate camera centers are rendered")
            require(frames.filter { abs($0.lens - before.lens) > 0.2 && abs($0.lens - final.lens) > 0.2 }.count > 8, "Camera lens eases with the pan")
            require(UnifiedInteractiveSceneView.lastActiveView === view && view.pointOfView!.simdTransform == pose,
                    "Reframing preserves the scene and user's orbit/pan position")
            print("AI \(enabled): \(frames.count) frames, travel \(travel), largest step \(steps.max()!), lens \(before.lens) → \(final.lens)")
            return final
        }
        _ = transition(true)
        let disabled = transition(false)
        require(abs(disabled.x - original.x) < 1 && abs(disabled.lens - original.lens) < 0.01, "Closing returns to exact original framing")
        app.aiAnalysisEnabled = true; settle(0.2)
        let reversal = sample()
        app.aiAnalysisEnabled = false; settle(0.02)
        require(abs(sample().x - reversal.x) < 15, "Rapid reversal starts from the current framing")
        settle(0.9)
        require(abs(sample().x - original.x) < 1, "Rapid reversal settles correctly")
        print("PASS: AI on/off smoothly pans and adjusts the lens together, keeps scene/orbit intact, reverses continuously")
    }
}
