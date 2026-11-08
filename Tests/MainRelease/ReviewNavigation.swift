import SwiftUI
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private struct KeyboardFixture: View {
    let app: AppModel
    @FocusState private var focused: Bool
    var body: some View {
        Color.gray.focused($focused)
            .keyboardShortcuts(boardVM: app.boardVM!, appModel: app)
            .onAppear { focused = true }
    }
}
@main struct ReviewNavigationCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.analysisEnabled = false; AppSettings.shared.isMuted = true
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let sgf = "(;SZ[9];B[aa](;W[gg];B[hh])(;W[fg];B[fh];W[ff]))"
        let wrapper = SGFGameWrapper(url: FileManager.default.temporaryDirectory.appendingPathComponent("navigation-\(UUID()).sgf"),
            game: SGFGame.from(tree: try SGFParser.parse(text: sgf)))
        let vm = app.boardVM!
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func key(_ direction: Int, flags: NSEvent.ModifierFlags = []) {
            let characters = direction < 0 ? "\u{F702}" : "\u{F703}"
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                window.sendEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: direction < 0 ? 123 : 124)!)
            }
            settle()
        }
        for treeFocused in [false, true] {
            app.selectGame(wrapper)
            if treeFocused {
                let host = NSHostingView(rootView: VariationTreeView(vm: vm).environmentObject(app))
                window.contentView = host; settle(); host.layoutSubtreeIfNeeded()
                guard let surface = descendants(host).compactMap({ $0 as? VariationTreeMouseSurface.Surface }).first else {
                    fatalError("Missing native variation tree")
                }
                require(window.makeFirstResponder(surface), "Tree accepts keyboard focus")
            } else {
                window.contentView = NSHostingView(rootView: KeyboardFixture(app: app)); settle()
            }
            key(-1); key(-1); key(1)
            require(vm.currentMoveIndex == 2 && app.player.board.stones[BoardPosition(6, 6)] == .white,
                    "Plain arrows return through the main line, tree focus: \(treeFocused)")
            key(1, flags: .control)
            require(vm.currentMoveIndex == 2 && app.player.board.stones[BoardPosition(6, 5)] == .white,
                    "Control–Right selects alternative, tree focus: \(treeFocused)")
            if treeFocused, let host = window.contentView {
                host.layoutSubtreeIfNeeded()
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-current-branch-yellow.png"))
            }
            key(-1); key(-1); key(1); key(1)
            require(vm.currentMoveIndex == 2 && app.player.board.stones[BoardPosition(6, 6)] == .white,
                    "Back past fork and forward returns to main line")
            key(1, flags: .control)
            key(1); key(1)
            require(vm.currentMoveIndex == 4 && app.player.board.stones[BoardPosition(5, 5)] == .white,
                    "Forward continues to alternative endpoint")
            let savedTree = vm.reviewSGFData()
            key(-1, flags: .command)
            require(vm.currentMoveIndex == 1 && vm.reviewTree?.isMainLine == true,
                    "Command–Left returns to the main-line branch point, tree focus: \(treeFocused)")
            require(vm.reviewSGFData() == savedTree, "Returning keeps every variation")
            key(-1, flags: .command)
            require(vm.currentMoveIndex == 1, "Command–Left on main line stays put")
            key(1)
            require(app.player.board.stones[BoardPosition(6, 6)] == .white, "Forward after return follows main line")
            key(1, flags: .control); key(1); key(1)
            key(1, flags: .control)
            require(vm.currentMoveIndex == 4, "No next variation leaves position unchanged")
            key(-1, flags: .control)
            require(vm.currentMoveIndex == 2 && app.player.board.stones[BoardPosition(6, 6)] == .white,
                    "Control–Left returns to main line from inside alternative")
            key(-1, flags: .shift); require(vm.currentMoveIndex == 0, "Shift–Left still jumps ten moves")
            key(1, flags: .shift)
            require(vm.currentMoveIndex == 3 && app.player.board.stones[BoardPosition(7, 7)] == .black,
                    "Shift–Right follows current main line to its end")
            let nestedSGF = "(;SZ[9];B[aa](;W[bb])(;W[cc];B[dd](;W[ee])(;C[nested];W[])))"
            app.selectGame(SGFGameWrapper(url: wrapper.url.deletingLastPathComponent().appendingPathComponent("nested-\(UUID()).sgf"),
                game: SGFGame.from(tree: try SGFParser.parse(text: nestedSGF))))
            vm.selectReviewNode(vm.reviewTree!.nodes.last!.id); settle()
            key(-1, flags: .command)
            require(vm.currentMoveIndex == 1 && vm.reviewTree?.selectedID == 1 && vm.reviewTree?.isMainLine == true,
                    "Real Command–Left skips nested forks and comments, tree focus: \(treeFocused)")
        }
        print("PASS: real board and focused-tree keys restore main line after leaving variations; Control arrows switch variations; boundaries and Shift navigation")
    }
}
