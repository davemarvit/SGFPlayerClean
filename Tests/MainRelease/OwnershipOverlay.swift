import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct OwnershipOverlayCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        AppSettings.shared.environment3D = .monastery
        let app = AppModel(); app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let text = "(;SZ[9]PL[B]AB[bb][bc][bd][db][dd][gg]AW[cc][gc][gd][gf])"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ownership-\(UUID()).sgf")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: text))))
        app.aiAnalysisEnabled = true; app.viewMode = .view3D
        let vm = app.boardVM!
        require(vm.showLikelyDeadStones, "Ownership and dead stones are visible by default")
        let original = app.player.board
        let history = vm.reviewSGFData()
        let ownership = (0..<81).map { index -> Double in
            switch index % 9 { case 0...3: return 0.95; case 4: return 0.3; case 5: return -0.3; default: return -0.9 }
        }
        let candidate = AIMoveInfo(move: "E5", visits: 100, winrate: 0.6, scoreLead: 2, pv: ["E5", "F4"])
        KataGoEngine.shared.currentAnalysisData[0] = AIAnalysis(id: "ownership", isDuringSearch: false, turnNumber: 0,
            moveInfos: [candidate], rootInfo: AIRootInfo(winrate: 0.6, scoreLead: 2, visits: 100),
            ownership: ownership, ownershipStdev: Array(repeating: 0.05, count: 81))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 850),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ContentView3D().environmentObject(app))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle(_ duration: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(duration)); SCNTransaction.flush() }
        settle(0.5)
        let view = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        _ = view.finishCameraArrival?(); settle()
        func nodes(_ name: String) -> [SCNNode] {
            var result: [SCNNode] = []
            view.scene!.rootNode.enumerateChildNodes { node, _ in if node.name == name { result.append(node) } }
            return result
        }
        require(vm.likelyDeadStoneStrengths.count == 2, "Only the two opposing stones are estimated lost")
        require(nodes("ai-likely-dead-cross").count == 2, "Both colors get an X in the production 3D view")
        require(nodes("ai-ownership-region").count == 1, "One feathered surface covers both regions, including occupied points")
        require(vm.ownershipEstimates.count == 63 && vm.ownershipEstimates[BoardPosition(4, 4)] == nil,
                "Only strong regions are shaded; weak central influence stays clear")
        let region = nodes("ai-ownership-region")[0]
        require(region.geometry?.firstMaterial?.lightingModel == .lambert && !region.castsShadow,
                "Ownership receives lighting and stone shadows without casting its own shadow")
        for cross in nodes("ai-likely-dead-cross") {
            let mesh = cross.parent!.childNode(withName: "board-stone", recursively: false)!
            require(mesh.opacity < 0.6 && mesh.opacity > 0.3 && cross.opacity > 0.7,
                    "Likely-captured stone fades while its X remains clear")
        }
        require(nodes("board-stone").filter { $0.opacity == 1 }.count == original.stones.count - 2,
                "Living stones retain their ordinary appearance")
        let output = URL(fileURLWithPath: "/private/tmp/sgf-territory-contrast-20261019")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try NSBitmapImageRep(data: view.snapshot().tiffRepresentation!)!.representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("ownership-3d.png"))
        // Compare the same rendered instant with stone shadow casting on/off.
        // Restrict measurements to the white ownership region, where an unlit
        // overlay would most noticeably wash out the shadows.
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = view.scene; renderer.pointOfView = view.pointOfView
        let imageSize = CGSize(width: 1000, height: 850)
        func shadowSnapshot() -> NSBitmapImageRep {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: 4, with: imageSize, antialiasingMode: .multisampling4X)
            return NSBitmapImageRep(data: renderer.snapshot(atTime: 4, with: imageSize, antialiasingMode: .multisampling4X).tiffRepresentation!)!
        }
        let shadowed = shadowSnapshot()
        let casters = nodes("board-stone")
        let casting = casters.map { $0.castsShadow }
        casters.forEach { $0.castsShadow = false }
        let unshadowed = shadowSnapshot()
        for (node, enabled) in zip(casters, casting) { node.castsShadow = enabled }
        let plane = region.geometry as! SCNPlane
        let dx = plane.width / 9, dz = plane.height / 9
        let polygon = CGMutablePath()
        for (index, corner) in [SCNVector3(2 * dx, 1.004, -4 * dz), SCNVector3(4 * dx, 1.004, -4 * dz),
                                SCNVector3(4 * dx, 1.004, 4 * dz), SCNVector3(2 * dx, 1.004, 4 * dz)].enumerated() {
            let projected = renderer.projectPoint(corner)
            let point = CGPoint(x: CGFloat(projected.x), y: imageSize.height - CGFloat(projected.y))
            if index == 0 { polygon.move(to: point) } else { polygon.addLine(to: point) }
        }
        polygon.closeSubpath()
        var shadowPixels = 0
        for y in stride(from: 0, to: shadowed.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: shadowed.pixelsWide, by: 2) where polygon.contains(CGPoint(x: x, y: y)) {
                let dark = shadowed.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                let light = unshadowed.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                let delta = (light.redComponent - dark.redComponent) * 0.2126
                    + (light.greenComponent - dark.greenComponent) * 0.7152
                    + (light.blueComponent - dark.blueComponent) * 0.0722
                if delta > 0.012 { shadowPixels += 1 }
            }
        }
        require(shadowPixels > 10, "Stone shadows remain visible over white ownership shading: \(shadowPixels) pixels")
        print("Visible shadow samples within white region: \(shadowPixels)")
        try shadowed.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("ownership-shadows.png"))
        let boardSize = CGSize(width: 600, height: 647)
        let board2D = NSHostingView(rootView: BoardView2D(boardVM: vm, layoutVM: app.layoutVM, size: boardSize).environmentObject(app))
        board2D.frame = CGRect(origin: .zero, size: boardSize)
        let secondWindow = NSWindow(contentRect: CGRect(origin: .zero, size: boardSize), styleMask: [.titled], backing: .buffered, defer: false)
        secondWindow.contentView = board2D; secondWindow.orderFront(nil); settle()
        defer { secondWindow.orderOut(nil) }
        board2D.layoutSubtreeIfNeeded()
        let bitmap = board2D.bitmapImageRepForCachingDisplay(in: board2D.bounds)!
        board2D.cacheDisplay(in: board2D.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("ownership-2d.png"))
        let strong = KataGoEngine.shared.currentAnalysisData[0]!
        var isolated = strong; isolated.ownership = Array(repeating: 0.4, count: 81)
        isolated.ownership![40] = 1
        KataGoEngine.shared.currentAnalysisData[0] = isolated; settle()
        require(vm.ownershipEstimates.isEmpty && nodes("ai-ownership-region").isEmpty,
                "One strongly owned intersection surrounded by weak influence has no territory patch")
        var neutral = strong; neutral.ownership = Array(repeating: 0, count: 81)
        KataGoEngine.shared.currentAnalysisData[0] = neutral; settle()
        require(nodes("ai-likely-dead-cross").isEmpty && nodes("ai-ownership-region").isEmpty &&
                nodes("board-stone").allSatisfy { $0.opacity == 1 },
                "New neutral analysis immediately clears old confidence without navigation")
        KataGoEngine.shared.currentAnalysisData[0] = strong; settle()
        require(nodes("ai-likely-dead-cross").count == 2, "Streaming stronger analysis restores the marks")
        vm.showLikelyDeadStones = false; settle()
        require(nodes("ai-likely-dead-cross").isEmpty && nodes("ai-ownership-region").isEmpty,
                "Toggle removes both layers immediately")
        require(nodes("board-stone").allSatisfy { $0.opacity == 1 }, "Toggle restores full stone opacity")
        vm.showLikelyDeadStones = true; settle()
        vm.hoverAnalysis(at: BoardPosition(4, 4)); settle(0.6)
        require(vm.isPreviewingVariation, "Fixture exercises a real hover continuation")
        require(nodes("ai-likely-dead-cross").isEmpty && nodes("ai-ownership-region").isEmpty,
                "Actual-position estimates do not leak onto hypothetical positions")
        vm.hoverAnalysis(at: nil); settle()
        require(nodes("ai-likely-dead-cross").count == 2 && nodes("ai-ownership-region").count == 1,
                "Leaving the preview restores the estimates")
        vm.beginScrubbing(); settle()
        require(vm.ownershipEstimates.isEmpty && vm.likelyDeadStoneStrengths.isEmpty, "Scrubbing suppresses stale estimates")
        vm.endScrubbing(at: 0); settle()
        app.aiAnalysisEnabled = false; settle()
        require(nodes("ai-likely-dead-cross").isEmpty && nodes("ai-ownership-region").isEmpty,
                "AI off removes the overlay")
        require(app.player.board == original && vm.reviewSGFData() == history && vm.blackCapturedCount == 0 && vm.whiteCapturedCount == 0,
                "Hints never change history, stones, captures or scoring")
        print("PASS: stronger regional threshold, isolated-point suppression, feathered lit ownership regions under stones, progressively faded stones and Xs, both colors, 2D/3D rendering, toggle, preview/scrub/AI lifecycle, immutable position and scoring")
    }
}
