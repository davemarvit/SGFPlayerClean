import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private struct InformationHost: View {
    @ObservedObject var app: AppModel
    @State private var settings = false
    @State private var buttons = true
    var body: some View {
        if let vm = app.boardVM {
            BoardWorkspaceView(vm: vm) { ContentView3D() }
                .overlay { SharedOverlays(showSettings: $settings, buttonsVisible: $buttons, app: app, boardVM: vm) }
                .environmentObject(app)
        }
    }
}

@main struct CafeWindowCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.environment3D = .coffeeShop
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        app.aiAnalysisEnabled = false
        let sgf = "(;SZ[19];B[dd];W[pd];B[dp];W[pp])"
        let url = URL(fileURLWithPath: "/private/tmp/game-information-fixture.sgf")
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        app.copyCurrentBoard(to: .localPlay)
        app.viewMode = .view3D; app.showRightPanel = true
        let vm = app.boardVM!
        vm.goToEnd()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: InformationHost(app: app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.35)) }
        settle()
        let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        _ = view.finishCameraArrival?()
        for width: CGFloat in [1280, 1440] {
            window.setContentSize(NSSize(width: width, height: 900))
            settle(); host.layoutSubtreeIfNeeded()
            // Check actual mesh vertices inside the board workspace (right panel excluded).
            for name in ["white-stone-bowl", "black-stone-bowl", "white-player-lid", "black-player-lid"] {
                let item = view.scene!.rootNode.childNode(withName: name, recursively: true)!
                var minX: CGFloat = 99999, maxX: CGFloat = -99999
                for source in item.geometry!.sources(for: .vertex) {
                    source.data.withUnsafeBytes { bytes in
                        for i in 0..<source.vectorCount {
                            func component(_ j: Int) -> CGFloat {
                                let offset = source.dataOffset + i * source.dataStride + j * source.bytesPerComponent
                                return source.bytesPerComponent == 4 ? CGFloat(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self)) : CGFloat(bytes.loadUnaligned(fromByteOffset: offset, as: Double.self))
                            }
                            let p = view.projectPoint(item.convertPosition(SCNVector3(component(0),component(1),component(2)), to: nil))
                            let inHost = view.convert(NSPoint(x: p.x, y: p.y), to: host)
                            minX = min(minX, inHost.x); maxX = max(maxX, inHost.x)
                        }
                    }
                }
                print(name, width, "horizontal extent", minX, maxX)
                require(minX > 0 && maxX < width - 320, "\(name) fits beside sidebar")
            }
        }
        print("PASS: café equipment fits in the real app with an open sidebar at 1280 and 1440 pixels")
    }
}
