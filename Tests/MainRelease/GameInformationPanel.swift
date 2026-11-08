import SwiftUI
import SceneKit
import Vision
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

@main struct GameInformationPanelCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.environment3D = .monastery
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        app.aiAnalysisEnabled = false
        let sgf = "(;SZ[9]PB[Alice]PW[Bob]BR[3d]WR[2d]RU[Japanese]KM[6.5]EV[Evening game]DT[2026-10-18]PC[Kyoto]GN[Friendly match]TM[1800]OT[5x30 byo-yomi]PL[W]AB[aa][hi]AW[ba][ii];W[ab];B[ih])"
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
        func capture(_ name: String) throws -> [VNRecognizedTextObservation] {
            settle(); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-game-information-\(name).png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            let results = request.results ?? []
            print(name, results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " | "))
            return results
        }
        func text(_ item: VNRecognizedTextObservation) -> String { item.topCandidates(1).first?.string ?? "" }
        settle()
        let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        _ = view.finishCameraArrival?()
        let captured = try capture("captured")
        require(captured.contains { text($0).contains("Game information") }, "Sidebar has game information")
        for name in ["Alice", "Bob"] {
            let matches = captured.filter { text($0).contains(name) }
            require(matches.count == 1 && matches[0].boundingBox.minX > 0.75, "\(name) appears only in the right sidebar")
        }
        require(captured.filter { text($0).contains("Captured:") && text($0).contains("1") }.count == 2, "Both players' capture totals are visible")
        for value in ["Japanese", "6.5", "Kyoto", "Evening game", "3d", "2d"] {
            require(captured.contains { text($0).contains(value) }, "Sidebar includes \(value)")
        }
        require(vm.blackCapturedCount == 1 && vm.whiteCapturedCount == 1, "Capture fixture has one prisoner per player")
        require(view.scene!.rootNode.childNode(withName: "capture-count", recursively: true) == nil, "No capture numbers in physical space")
        for (lid, color) in [("black-player-lid", "white"), ("white-player-lid", "black")] {
            require(view.scene!.rootNode.childNode(withName: lid, recursively: true)!.childNodes.filter { $0.name == "captured-\(color)" }.count == 1, "Real captured stones remain in \(lid)")
        }
        vm.goToStart()
        let rewound = try capture("rewound")
        require(rewound.filter { text($0).contains("Captured:") && text($0).contains("0") }.count == 2, "Mounted sidebar updates capture counts after rewind")
        app.showRightPanel = false
        let closed = try capture("closed")
        require(!closed.contains { text($0).contains("Alice") || text($0).contains("Bob") || text($0).contains("Captured:") }, "Closing sidebar does not restore floating metadata")
        app.showRightPanel = true
        app.copyCurrentBoard(to: .review)
        let review = try capture("review")
        require(review.contains { text($0).contains("Game information") }, "Review retains the same sidebar details")
        print("PASS: metadata confined to sidebar, complete game details, live capture counts, rewind, panel close/reopen and review mode")
    }
}
