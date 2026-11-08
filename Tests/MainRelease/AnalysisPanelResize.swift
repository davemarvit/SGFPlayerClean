import SwiftUI
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private struct BoardAreaProbe: NSViewRepresentable {
    @Environment(\.boardControlsWidth) var width
    static var usableWidth: CGFloat = 0
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { Self.usableWidth = width ?? 0 }
}
@main struct AnalysisPanelResizeCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        UserDefaults.standard.removeObject(forKey: "analysisPanelWidth")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("resize-\(UUID()).sgf")
        let sgf = "(;SZ[9];B[aa];W[bb];B[cc])"
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        app.aiAnalysisEnabled = true; app.showRightPanel = false
        let vm = app.boardVM!
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        func makeHost() -> NSHostingView<some View> {
            NSHostingView(rootView: BoardWorkspaceView(vm: vm) { BoardAreaProbe() }.environmentObject(app))
        }
        var host = makeHost()
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded() }
        settle()
        let originalGame = vm.reviewSGFData()
        let originalNode = vm.reviewTree?.selectedID
        func layout() -> BoardWorkspaceGeometry {
            let stored = UserDefaults.standard.double(forKey: "analysisPanelWidth")
            return BoardWorkspaceGeometry(size: host.bounds.size, aiEnabled: true, sidebarVisible: false,
                preferredAnalysisWidth: stored > 0 ? stored : nil)
        }
        func event(_ type: NSEvent.EventType, x: CGFloat, count: Int = 1) {
            let point = host.convert(NSPoint(x: x, y: host.bounds.midY), to: nil)
            window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1)!)
        }
        func drag(_ delta: CGFloat) {
            let start = layout().aiOrigin
            event(.leftMouseDown, x: start); settle()
            for step in 1...8 { event(.leftMouseDragged, x: start + delta * CGFloat(step) / 8); settle() }
            event(.leftMouseUp, x: start + delta); settle()
        }
        let initial = layout().aiWidth
        drag(100)
        require(abs(layout().aiWidth - max(280, initial - 100)) < 2, "Drag right narrows the panel: initial \(initial), actual \(layout().aiWidth), stored \(UserDefaults.standard.double(forKey: "analysisPanelWidth")), workspace \(host.bounds.size), available \(app.isAIAvailable)")
        require(abs(BoardAreaProbe.usableWidth - layout().aiOrigin) < 2, "Board receives the resized usable area")
        let narrowed = layout().aiWidth
        drag(-160)
        require(abs(layout().aiWidth - (narrowed + 160)) < 2, "Drag left widens the panel")
        let saved = layout().aiWidth
        window.contentView = NSView(); host = makeHost(); window.contentView = host; settle()
        require(abs(layout().aiWidth - saved) < 2 && abs(BoardAreaProbe.usableWidth - (1400 - saved)) < 2,
                "Width persists when the view is recreated")
        drag(900)
        require(abs(layout().aiWidth - 280) < 2, "Narrow width limit")
        drag(-900)
        require(abs(layout().aiWidth - 700) < 2, "Board keeps at least half the available width")
        let origin = layout().aiOrigin
        event(.leftMouseDown, x: origin); event(.leftMouseUp, x: origin)
        event(.leftMouseDown, x: origin, count: 2); event(.leftMouseUp, x: origin, count: 2); settle()
        require(UserDefaults.standard.double(forKey: "analysisPanelWidth") == 0, "Double-click restores automatic sizing")
        require(vm.reviewSGFData() == originalGame && vm.reviewTree?.selectedID == originalNode,
                "Dragging the divider never plays or selects a move")
        let large = BoardWorkspaceGeometry(size: CGSize(width: 3840, height: 2100), aiEnabled: true, sidebarVisible: true, preferredAnalysisWidth: 340)
        require(large.aiWidth == 340 && large.aiOrigin == 3180, "Manual width works in a full 4K workspace with the game sidebar")
        let small = BoardWorkspaceGeometry(size: CGSize(width: 1000, height: 700), aiEnabled: true, sidebarVisible: false, preferredAnalysisWidth: 1600)
        require(small.aiWidth == 500, "Saved wide panels fit smaller windows")
        require(NSImage(systemSymbolName: "target", accessibilityDescription: nil) != nil, "Bullseye symbol is available")
        print("PASS: actual left-edge drags resize the panel and board, persist width, respect limits, reset on double-click, and preserve the game; 4K and smaller-window layouts fit.")
    }
}
