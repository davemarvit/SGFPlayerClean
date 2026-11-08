import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct VariationGhostsCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil
        AppSettings.shared.isMuted = true
        AppSettings.shared.moveInterval = 10
        let app = AppModel()
        app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        func settle(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        let sgf = "(;SZ[9]RU[Japanese];B[aa](;W[dd];B[bb](;W[cc])(;W[ee]))(;W[ff];B[gg])(;W[]))"
        let game = SGFGame.from(tree: try SGFParser.parse(text: sgf))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("variation-ghosts-\(UUID()).sgf")
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: game)); settle()
        let vm = app.boardVM!
        require(vm.reviewVariationChoices.isEmpty, "No branch ghosts before the fork")
        vm.seekToMove(1); settle()
        require(vm.reviewTreeCollapsed && vm.reviewVariationChoices.isEmpty, "Collapsed tree hides fork ghosts by default")
        vm.reviewTreeCollapsed = false; settle()
        let choices = vm.reviewVariationChoices
        require(choices.count == 2 && choices.map(\.label) == ["A", "B"], "Fork shows both on-board continuations, omitting pass")
        require(choices.allSatisfy { $0.color == .white }, "Ghosts use the saved move color")
        app.aiAnalysisEnabled = true; settle()
        require(vm.reviewVariationChoices.count == 2, "AI keeps every saved continuation visible, including the main line")
        app.aiAnalysisEnabled = false; settle()
        let original = vm.reviewSGFData()!
        let count = vm.reviewTree!.nodes.count
        vm.updateGhostStone(at: choices[0].position)
        require(vm.ghostPosition == nil, "A branch ghost does not get a second floating placement preview")
        vm.canPreviewAnalysis = { true }
        vm.hoverAnalysis(at: choices[0].position); settle(0.6)
        require(!vm.isPreviewingVariation && vm.variationStatus == nil, "Saved variation hover never starts an AI preview")
        let candidate = AIMoveInfo(move: "C7", visits: 50, winrate: 0.6, scoreLead: 2, pv: ["C7", "D6", "pass"])
        KataGoEngine.shared.currentAnalysisData[1] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: 1,
            moveInfos: [candidate], rootInfo: nil)
        vm.hoverAnalysis(at: BoardPosition(2, 2)); settle(0.55)
        require(vm.isPreviewingVariation && vm.reviewVariationChoices.isEmpty, "AI animation temporarily hides saved branches")
        vm.updateGhostStone(at: choices[0].position)
        vm.hoverAnalysis(at: choices[0].position); settle(0.6)
        require(!vm.isPreviewingVariation && vm.variationStatus == nil && vm.ghostPosition == nil,
                "Moving from an AI preview to a saved branch restores only the saved ghost")
        vm.canPreviewAnalysis = { false }
        vm.updateGhostStone(at: BoardPosition(7, 7))
        require(vm.ghostPosition == BoardPosition(7, 7), "New-move preview still works away from saved branches")
        vm.clearGhostStone()

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 646), styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let size = CGSize(width: 600, height: 646)
        let host = NSHostingView(rootView: BoardView2D(boardVM: vm, layoutVM: app.layoutVM, size: size).environmentObject(app))
        window.contentView = host; window.orderFront(nil); settle()
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-variation-ghosts-2d.png"))
        let grid = GoEquipmentDimensions2D.gridRect(in: size)
        let x = grid.minX + CGFloat(choices[1].position.col) * grid.width / 8
        let y = grid.minY + CGFloat(choices[1].position.row) * grid.height / 8
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: size.height - y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            NSApp.postEvent(event, atStart: false)
            if let queued = NSApp.nextEvent(matching: type == .leftMouseDown ? .leftMouseDown : .leftMouseUp, until: Date().addingTimeInterval(0.1), inMode: .default, dequeue: true) {
                NSApp.sendEvent(queued)
            }
            settle(0.05)
        }
        settle()
        require(vm.reviewTree!.selectedID == choices[1].id && vm.currentMoveIndex == 2, "Actual 2D click opens branch B")
        require(vm.reviewVariationChoices.isEmpty && app.player.board.stones[choices[1].position] == .white, "Branch choice becomes a real historical stone and ghosts disappear")
        require(vm.reviewTree!.nodes.count == count && vm.reviewSGFData() == original && !vm.reviewDraftSaved, "Navigation neither edits SGF nor writes a draft")

        vm.seekToMove(1); settle()
        app.viewMode = .view3D
        window.setContentSize(CGSize(width: 1000, height: 750))
        window.contentView = NSHostingView(rootView: ContentView3D().environmentObject(app)); settle(3.2)
        let live = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        // Input is intentionally consumed during the current 13-second arrival.
        // Exercise branch picking only after reaching the playing view.
        _ = live.finishCameraArrival?(); SCNTransaction.flush(); settle()
        func ghostNodes() -> [SCNNode] {
            var result: [SCNNode] = []
            live.scene!.rootNode.enumerateChildNodes { node, _ in
                if node.name == "review-variation-stone" { result.append(node) }
            }
            return result
        }
        require(ghostNodes().count == 2, "Production 3D view renders both saved continuations")
        vm.reviewTreeCollapsed = true; settle()
        require(vm.reviewVariationChoices.isEmpty && ghostNodes().isEmpty, "Collapsing the tree removes branch ghosts in 3D")
        vm.reviewTreeCollapsed = false; settle()
        require(ghostNodes().count == 2, "Expanding the tree restores the fork ghosts in 3D")
        require(ghostNodes().allSatisfy { abs($0.opacity - 0.45) < 0.001 && !$0.castsShadow && $0.physicsBody == nil }, "Branch previews are translucent and do not participate in physics")
        let projected = live.projectPoint(SCNVector3(-2.25, 2.05, -2.25 * 1.0773))
        let click = live.convert(CGPoint(x: projected.x, y: projected.y), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: click, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        live.mouseMoved(with: event(.mouseMoved)); settle()
        require(vm.ghostPosition == nil && live.usesBoardCursor, "Hover selects a saved ghost without a floating duplicate")
        let dot = live.scene!.rootNode.childNode(withName: "ghost-landing-marker", recursively: true)!
        require(dot.opacity == 1 && dot.position.y > 2, "Actionable branch gets a bright cursor above its ghost")
        let image = NSBitmapImageRep(data: live.snapshot().tiffRepresentation!)!
        try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-variation-ghosts-3d.png"))
        live.mouseDown(with: event(.leftMouseDown)); live.mouseUp(with: event(.leftMouseUp)); settle()
        require(vm.reviewTree!.selectedID == choices[0].id && vm.currentMoveIndex == 2, "Actual 3D click switches to branch A")
        require(ghostNodes().isEmpty && vm.reviewVariationChoices.isEmpty, "3D removes all previews on leaving the fork")
        require(vm.reviewTree!.nodes.count == count && vm.reviewSGFData() == original && !vm.reviewDraftSaved, "3D selection preserves the entire saved tree")
        vm.seekToMove(3); settle()
        require(vm.reviewVariationChoices.count == 2 && ghostNodes().count == 2, "Nested forks show their own continuations")
        vm.beginScrubbing(); settle()
        require(vm.reviewVariationChoices.isEmpty && ghostNodes().isEmpty, "Scrubbing hides branch targets")
        vm.endScrubbing(at: 3); settle()
        require(ghostNodes().count == 2, "Releasing scrub at the same fork restores previews")
        app.player.play(); settle()
        require(vm.reviewVariationChoices.isEmpty && ghostNodes().isEmpty, "Autoplay hides clickable branch ghosts")
        app.player.pause(); settle()
        require(ghostNodes().count == 2, "Pausing restores fork ghosts")
        app.copyCurrentBoard(to: .localPlay); settle()
        require(vm.reviewVariationChoices.isEmpty && ghostNodes().isEmpty, "Local Play does not display review navigation ghosts")

        let edgeSGF = "(;SZ[9](;C[note];B[cc])(;B[])(;B[tt])(;B[cc])(;AB[dd];B[ee]))"
        let edgeGame = SGFGame.from(tree: try SGFParser.parse(text: edgeSGF))
        let edgeTree = ReviewTree(game: edgeGame, analysisID: "edge", filename: "edge.sgf")
        require(edgeTree.boardVariations.count == 1 && edgeTree.boardVariations[0].position == BoardPosition(2, 2), "Comment prefixes work; pass, out-of-range, duplicates and setup edits never create misleading targets")
        print("PASS: fork-only ghosts, both renderers and real clicks, nested branches, immutable SGF, AI/placement separation, scrub/play/mode lifecycle, and SGF edge cases")
    }
}
