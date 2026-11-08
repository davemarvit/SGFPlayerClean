import SwiftUI
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct TreeContextMenuCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("tree-menu-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        AppSettings.shared.folderURL = nil; AppSettings.shared.savedGamesFolderURL = temp
        AppSettings.shared.analysisEnabled = false; AppSettings.shared.isMuted = true
        let app = AppModel(); app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let sgf = "(;SZ[9]RU[Japanese];B[aa](;W[bb];B[cc])(;W[dd]C[Delete this branch];B[]))"
        let url = temp.appendingPathComponent("original.sgf")
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        let vm = app.boardVM!
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        vm.selectReviewNode(0); settle()
        let original = vm.reviewSGFData()!
        let target = vm.reviewTree!.nodes.first { $0.comment == "Delete this branch" }!.id
        let mainLeaf = vm.reviewTree!.nodes.first { $0.properties["B"] == ["cc"] }!.id
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let host = NSHostingView(rootView: VariationTreeView(vm: vm).environmentObject(app))
        window.contentView = host; window.orderFront(nil); settle()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let surface = descendants(host).compactMap { $0 as? VariationTreeMouseSurface.Surface }.first!
        func menu(_ id: Int, controlClick: Bool = false) -> NSMenu {
            let tree = vm.reviewTree!
            let lens = VariationTreeLens(focusRow: tree.nodes[tree.selectedID].depth)
            let padding = max(12, (surface.bounds.height - lens.height(of: lens.focusRow)) / 2)
            let row = tree.nodes[id].depth
            let point = CGPoint(x: 38 + CGFloat(tree.columns[id]) * VariationTreeLens.columnPitch,
                y: padding + lens.top(of: row) + lens.height(of: row) / 2)
            let location = surface.actions!.controller.anchor!.convert(point, to: nil)
            let event = NSEvent.mouseEvent(with: controlClick ? .leftMouseDown : .rightMouseDown,
                location: location, modifierFlags: controlClick ? [.control] : [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            guard let result = surface.menu(for: event) else { fatalError("Missing native node menu") }
            return result
        }
        func invoke(_ item: NSMenuItem) {
            require(item.isEnabled, "Menu action is enabled: \(item.title)")
            require(NSApp.sendAction(item.action!, to: item.target, from: item), "Native menu action reaches its target")
            settle()
        }
        let branchMenu = menu(target)
        require(vm.reviewTree!.selectedID == 0, "Opening or dismissing a context menu does not move selection")
        let deletion = branchMenu.item(withTitle: "Delete Node and Continuation")!
        require(deletion.isEnabled && branchMenu.item(withTitle: "Add pass here") != nil,
                "Right-click offers deletion with clear continuation scope and retains Add pass")
        vm.selectReviewNode(mainLeaf); settle() // Move the focus lens while the menu is open.
        invoke(deletion)
        require(vm.reviewTree!.nodes.count == 4 && vm.reviewTree!.selectedID == 1,
                "Menu deletes the clicked branch and its pass, not the later selection")
        require(vm.reviewTree!.nodes.contains { $0.properties["B"] == ["cc"] }, "Sibling main line survives")
        require(vm.canUndoReviewDeletion && vm.reviewDraftSaved, "Deletion is persisted and undoable")
        let savedOriginal = try String(contentsOf: url, encoding: .utf8)
        require(savedOriginal == sgf, "Original SGF is untouched")
        let rootMenu = menu(0, controlClick: true)
        require(rootMenu.items.first { $0.title.hasPrefix("Delete Node") }?.isEnabled == false,
                "Root deletion is disabled in the Control-click menu")
        invoke(rootMenu.item(withTitle: "Undo Delete")!)
        require(vm.reviewSGFData() == original && vm.reviewTree!.selectedID == target,
                "Undo restores the complete branch and selects the restored node")
        let leafMenu = menu(mainLeaf)
        require(leafMenu.item(withTitle: "Delete Node")?.isEnabled == true, "Leaf deletion has the shorter label")
        invoke(leafMenu.item(withTitle: "Delete Node")!)
        require(vm.reviewTree!.nodes.count == 5 && vm.reviewTree!.nodes.contains { $0.comment == "Delete this branch" },
                "Leaf deletion removes only that leaf and preserves the alternative")
        invoke(menu(0).item(withTitle: "Undo Delete")!)
        require(vm.reviewSGFData() == original, "Leaf deletion also restores exactly")
        invoke(menu(mainLeaf).item(withTitle: "Add pass here")!)
        require(vm.reviewTree!.nodes.count == 7 && vm.reviewTree!.nodes[vm.reviewTree!.selectedID].isPass,
                "Existing Add pass menu action still operates on its clicked node")
        let before = vm.reviewSGFData()
        vm.deleteReviewNode(-1); vm.deleteReviewNode(999); vm.deleteReviewNode(0)
        require(vm.reviewSGFData() == before, "Invalid IDs and root cannot delete anything")
        vm.isOnlineContext = true
        require(!vm.canDeleteReviewNode(target), "Online context cannot edit review nodes")
        vm.deleteReviewNode(target)
        require(vm.reviewSGFData() == before, "Online guard applies to the targeted action too")
        print("PASS: native right-click/Control-click menus, captured node identity across lens changes, branch/leaf deletion, parent selection, sibling preservation, root/online protection, Undo Delete, persistence, original SGF preservation and Add pass")
    }
}
