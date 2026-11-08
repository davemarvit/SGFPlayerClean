import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private struct CenteringHost: View {
    @ObservedObject var app: AppModel
    var body: some View {
        if let vm = app.boardVM {
            BoardWorkspaceView(vm: vm) { ContentView3D() }.environmentObject(app)
        }
    }
}
@main struct BoardCenteringCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.environment3D = .monastery
        let app = AppModel(); app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let sgf = "(;SZ[19];B[dd];W[pd];B[dp];W[pp])"
        let url = URL(fileURLWithPath: "/private/tmp/board-centering-fixture.sgf")
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        app.copyCurrentBoard(to: .localPlay); app.viewMode = .view3D
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: CenteringHost(app: app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle(_ time: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(time)); host.layoutSubtreeIfNeeded() }
        let output = URL(fileURLWithPath: "/private/tmp/sgf-board-centering-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        settle(0.4)
        var count = 0
        for kind in [PlayingEnvironment.monastery, .coffeeShop] {
            AppSettings.shared.environment3D = kind; settle()
            for analysis in [false, true] {
                app.copyCurrentBoard(to: analysis ? .review : .localPlay); settle()
                app.boardVM!.reviewTreeCollapsed = !analysis; settle()
                require(app.showsAnalysisWorkspace == analysis, "Exercise the actual expanded analysis/tree layout")
                for size in [CGSize(width: 1280, height: 900), CGSize(width: 2055, height: 1200), CGSize(width: 800, height: 1000)] {
                    window.setContentSize(size)
                    for sidebar in [false, true] {
                        app.showRightPanel = sidebar; settle()
                        let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
                        _ = view.finishCameraArrival?(); SCNTransaction.flush()
                        let layout = BoardWorkspaceGeometry(size: size, aiEnabled: analysis, sidebarVisible: sidebar)
                        let corners = [SCNVector3(-10,1,-10.773), SCNVector3(10,1,-10.773), SCNVector3(-10,1,10.773), SCNVector3(10,1,10.773)]
                        let points = corners.map { p -> CGPoint in
                            let q = view.projectPoint(p)
                            return view.convert(CGPoint(x:q.x,y:q.y),to:host)
                        }
                        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
                        require(abs((minX + maxX) / 2 - layout.aiOrigin / 2) < 2,
                            "Board centered in usable width: \(kind), \(size), analysis=\(analysis), sidebar=\(sidebar): \((minX+maxX)/2) vs \(layout.aiOrigin/2)")
                        require(minX > 0 && maxX < layout.aiOrigin, "Grid remains clear of panels")
                        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
                        let visibleScene = view.convert(view.bounds,to:host)
                        require(abs((minY+maxY)/2-visibleScene.midY)<2,
                            "Board vertically centered: \(kind), \(size): \((minY+maxY)/2) vs \(visibleScene.midY)")
                        require(visibleScene.midY < size.height/2-15, "Reserve the actual playback controls below the board")
                        require(minY > 0 && maxY < size.height, "Entire wooden surface remains visible")
                        let pick = view.projectPoint(SCNVector3(0,1,0))
                        view.onInteraction?(.hover,CGPoint(x:pick.x,y:pick.y))
                        require(view.usesBoardCursor, "Pointer picking follows the shifted viewport")
                        if size.width == 1280 && sidebar {
                            let image = NSImage(size:CGSize(width:layout.aiOrigin,height:size.height))
                            let sceneFrame = view.convert(view.bounds,to:host)
                            image.lockFocus()
                            view.snapshot().draw(in:CGRect(x:sceneFrame.minX,y:0,width:view.bounds.width,height:view.bounds.height))
                            image.unlockFocus()
                            let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
                            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(kind.rawValue)-analysis-\(analysis).png"))
                        }
                        count += 1
                    }
                }
            }
        }
        let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        let seated = view.pointOfView!.simdTransform
        view.onInteraction?(.drag(delta:CGPoint(x:20,y:10),modifiers:.shift),.zero); settle()
        let panned = view.pointOfView!.simdTransform
        require(panned != seated, "Manual pan remains available")
        app.showRightPanel.toggle(); settle()
        require(view.pointOfView!.simdTransform == panned, "Panel resizing does not erase manual camera positioning")
        app.recenter3DRequested.send(); settle(SceneManager3D.cameraRecenterDuration + 0.1)
        require(view.pointOfView!.simdTransform == seated, "Recenter returns to the centered seat")
        print("PASS: \(count) real layouts centered with open/closed sidebar, analysis, wide and portrait windows, floor/table boards, picking, manual pan and recenter")
    }
}
