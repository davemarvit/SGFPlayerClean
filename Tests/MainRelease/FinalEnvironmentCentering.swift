import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private struct FinalSeatHost: View {
    @ObservedObject var app: AppModel
    var body: some View {
        VStack(spacing: 0) {
            AppModeControls()
            if let vm = app.boardVM {
                BoardWorkspaceView(vm: vm) { ContentView3D() }
            }
        }.environmentObject(app)
    }
}

@main struct FinalEnvironmentCenteringCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        let kind = PlayingEnvironment(rawValue: ProcessInfo.processInfo.environment["SGF_PROBE_ENV"] ?? "cave")!
        AppSettings.shared.environment3D = kind
        let app = AppModel(); app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let url = URL(fileURLWithPath: "/private/tmp/final-seat-fixture.sgf")
        try "(;SZ[19];B[dd];W[pd];B[dp];W[pp])".write(to: url, atomically: true, encoding: .utf8)
        let game = SGFGame.from(tree: try SGFParser.parse(text: String(contentsOf: url)))
        app.selectGame(SGFGameWrapper(url: url, game: game)); app.copyCurrentBoard(to: .review)
        app.viewMode = .view3D; app.showRightPanel = false
        let vm = app.boardVM!; vm.reviewTreeCollapsed = true
        let size = CGSize(width: 2056, height: 1258)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: FinalSeatHost(app: app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle(_ duration: Double) {
            let until = Date().addingTimeInterval(duration)
            while Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            host.layoutSubtreeIfNeeded(); SCNTransaction.flush()
        }
        // Let the production arrival timer reach its actual final position.
        settle(SceneManager3D.cameraArrivalTotalDuration + 0.8)
        let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        precondition(view.finishCameraArrival?() == false, "Arrival must finish naturally before measuring")
        precondition(app.mode == .review && !app.isAIAvailable && vm.reviewTreeCollapsed)
        let corners = [SCNVector3(-10,1,-10.773), SCNVector3(10,1,-10.773), SCNVector3(-10,1,10.773), SCNVector3(10,1,10.773)]
        func center() -> CGPoint {
            let points = corners.map { p -> CGPoint in
                let q = view.projectPoint(p)
                return view.convert(CGPoint(x:q.x,y:q.y),to:host)
            }
            return CGPoint(x:(points.map(\.x).min()!+points.map(\.x).max()!)/2,
                           y:(points.map(\.y).min()!+points.map(\.y).max()!)/2)
        }
        let finalCenter = center()
        precondition(abs(finalCenter.x-size.width/2)<2,
                     "\(kind): collapsed review should center in full visible width: \(finalCenter.x) vs \(size.width/2)")
        let frame = view.convert(view.bounds,to:host)
        precondition(abs(finalCenter.y-frame.midY)<2, "Final vertical position should center above controls")
        let output = URL(fileURLWithPath: "/private/tmp/sgf-final-environment-centering")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let image = NSImage(size:size)
        image.lockFocus()
        view.snapshot().draw(in:CGRect(x:frame.minX,y:size.height-frame.maxY,width:frame.width,height:frame.height))
        image.unlockFocus()
        try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
            .write(to:output.appendingPathComponent(kind.rawValue+".png"))

        // Expanding and collapsing must actually resize the viewport; a newly
        // created panel must not silently collapse itself on publisher delivery.
        vm.reviewTreeCollapsed = false; settle(0.25)
        precondition(!vm.reviewTreeCollapsed)
        precondition(center().x < finalCenter.x-100, "An expanded tree reserves its visible column")
        vm.reviewTreeCollapsed = true; settle(0.25)
        precondition(abs(center().x-size.width/2)<2, "Collapsing gives the empty column back")
        app.showRightPanel = true; settle(0.25)
        precondition(abs(center().x-(size.width-320)/2)<2, "Open library is excluded from visible playing width")
        app.showRightPanel = false; settle(0.25)
        precondition(abs(center().x-size.width/2)<2)
        print("PASS \(kind.rawValue): natural final center x=\(finalCenter.x), expected=\(size.width/2); expanded/collapsed tree and library correctly reclaim visible space")
    }
}
