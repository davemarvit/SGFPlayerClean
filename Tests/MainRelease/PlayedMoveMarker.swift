import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class MarkerHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct PlayedMoveMarkerCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.isMuted = true; AppSettings.shared.folderURL = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MarkerHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        let app = AppModel(ogsClient: client)
        defer { client.disconnect(); KataGoEngine.shared.stop() }
        let output = URL(fileURLWithPath: "/private/tmp/sgf-played-marker")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let text = "(;SZ[9]AB[dc][ec][cf]AW[fd][dd][df];B[ee])"
        let url = output.appendingPathComponent("fixture.sgf")
        try text.write(to: url, atomically: true, encoding: .utf8)
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: text))))
        app.mode = .review; app.aiAnalysisEnabled = true
        let vm = app.boardVM!, ai = KataGoEngine.shared
        vm.goToStart()
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.25)) }
        settle()
        let root = AIRootInfo(winrate: 0.6, scoreLead: 0, visits: 100)
        let candidate = AIMoveInfo(move: "E4", visits: 100, winrate: 0.6, scoreLead: 0, pv: nil)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.orderFront(nil); defer { window.orderOut(nil) }
        let scene = SceneManager3D()
        scene.updateBoardSize(9)
        scene.updateStones(from: vm.displayedStones, lastMove: nil, moveIndex: 0, settings: AppSettings.shared, animate: false)
        scene.updateCameraPosition(distance: 25, rotationX: 0.45, rotationY: 0, panX: 0, panY: 0)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene.scene; renderer.pointOfView = scene.cameraNode
        for loss in [0.0, 0.25, 1.5, 3, 6, 12, 20] {
            ai.currentAnalysisData[0] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: 0, moveInfos: [candidate], rootInfo: root)
            ai.currentAnalysisData[1] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: 1, moveInfos: [],
                rootInfo: AIRootInfo(winrate: 0.4, scoreLead: loss, visits: 100))
            settle()
            require(abs(vm.historicalMoveEvaluation!.scoreDelta + loss) < 0.001, "Fixture exercises measured point loss")
            scene.updateAIHints(moves: vm.reviewCandidateMoves, isAvailable: true, root: root,
                nextMove: vm.engine.nextHistoricalMovePosition)
            SCNTransaction.flush(); settle()
            let ring = scene.scene.rootNode.childNode(withName: "historical-move-inner-ring", recursively: true)!
            let badge = ring.parent!
            let material = badge.geometry!.firstMaterial!
            let fill = (material.diffuse.contents as! NSColor).usingColorSpace(.deviceRGB)!
            let expected = NSColor(MoveLossPalette.color(pointsLost: loss)).usingColorSpace(.deviceRGB)!
            let bestRings = scene.scene.rootNode.childNodes(passingTest: { node, _ in node.name == "ai-best-move-ring" })
            require(bestRings.count == 1 && (bestRings[0].geometry?.firstMaterial?.diffuse.contents as? NSColor) == NSColor.blue,
                    "Exactly one blue outline identifies the best suggestion, independently of point-loss color")
            require(fill.alphaComponent == 1 && material.lightingModel == .constant, "Recorded move is opaque and unlit")
            require(abs(fill.redComponent - expected.redComponent) < 0.001 && abs(fill.greenComponent - expected.greenComponent) < 0.001 && abs(fill.blueComponent - expected.blueComponent) < 0.001,
                "Fill uses the continuous color for \(loss) points lost")
            let dashes = badge.childNodes.filter { $0.name == "historical-move-dash" }
            require(dashes.count == 12 && dashes.allSatisfy { ($0.geometry?.firstMaterial?.diffuse.contents as? NSColor) == NSColor.black }, "Distinct black dashed outline")
            let values = badge.childNodes.compactMap { $0.geometry as? SCNText }.map { String(describing: $0.string ?? "") }
            require(values.count == 2 && !values.contains { $0.localizedCaseInsensitiveContains("played") }, "Only the two values appear inside")
            if loss >= 6 {
                require(badge.childNodes.filter { $0.geometry is SCNText }.allSatisfy {
                    guard let ink = ($0.geometry?.firstMaterial?.diffuse.contents as? NSColor)?.usingColorSpace(.deviceRGB) else { return false }
                    return ink.redComponent > 0.99 && ink.greenComponent > 0.99 && ink.blueComponent > 0.99
                }, "Dark red and purple badges use white text")
            }
            let others = scene.scene.rootNode.childNodes(passingTest: { node, _ in node.name == "AI_HINT" && node !== badge })
            require(others.allSatisfy { ($0.geometry!.firstMaterial!.diffuse.contents as! NSColor).alphaComponent == 1 && $0.geometry!.firstMaterial!.lightingModel == .constant }, "Candidate colors stay opaque and independent of wood and lighting")
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1000, height: 850), antialiasingMode: .multisampling4X)
            try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("3d-loss-\(loss).png"))
            let host = NSHostingView(rootView: BoardView2D(boardVM: vm, layoutVM: app.layoutVM, size: CGSize(width: 820, height: 870)).environmentObject(app).frame(width: 900, height: 900))
            window.contentView = host; settle(); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("2d-loss-\(loss).png"))
        }
        for (sgfColor, expected) in [("B", NSColor.black), ("W", NSColor.white)] {
            let fixture = "(;SZ[9];\(sgfColor)[ee])"
            let game = SGFGame.from(tree: try SGFParser.parse(text: fixture))
            app.selectGame(SGFGameWrapper(url: url, game: game)); settle()
            vm.goToStart(); settle() // Newly opened games now start at the end of their main line.
            ai.currentAnalysisData[0] = AIAnalysis(id: "color-fixture", isDuringSearch: false, turnNumber: 0,
                moveInfos: [AIMoveInfo(move: "E5", visits: 100, winrate: 0.6, scoreLead: 0, pv: nil)], rootInfo: root)
            scene.updateAIHints(moves: vm.reviewCandidateMoves, isAvailable: true, root: root,
                nextMove: vm.engine.nextHistoricalMovePosition, playedColor: vm.engine.moveColor(at: vm.currentMoveIndex))
            var dashes: [SCNNode] = []
            scene.scene.rootNode.enumerateChildNodes { node, _ in
                if node.name == "historical-move-dash" { dashes.append(node) }
            }
            require(dashes.count == 12 && dashes.allSatisfy {
                ($0.geometry?.firstMaterial?.diffuse.contents as? NSColor) == expected
            }, "Dotted ring follows the actual SGF stone color, including a white first move")
        }
        // A one-visit winrate outlier must not be highlighted as the best move.
        // Its fill still reflects its estimated point loss, independent of visits.
        let recommended = AIMoveInfo(move: "G7", visits: 231, winrate: 0.99, scoreLead: 71.78, pv: nil, order: 0)
        let outlier = AIMoveInfo(move: "H7", visits: 1, winrate: 0.999, scoreLead: 28.02, pv: nil, order: 4)
        let suggestionRoot = AIRootInfo(winrate: 0.99, scoreLead: 71.35, visits: 500)
        ai.currentAnalysisData = [0: AIAnalysis(id: "suggestions", isDuringSearch: false, turnNumber: 0,
            moveInfos: [outlier, recommended], rootInfo: suggestionRoot)]
        settle()
        require(vm.reviewCandidateMoves.map(\.move) == ["G7", "H7"], "Suggestions follow KataGo order")
        scene.updateAIHints(moves: vm.reviewCandidateMoves, isAvailable: true, root: suggestionRoot, nextMove: nil)
        let hints = scene.scene.rootNode.childNodes(passingTest: { node, _ in node.name == "AI_HINT" })
        require(hints.count == 2, "Both suggestions stay visible")
        let bestRing = scene.scene.rootNode.childNode(withName: "ai-best-move-ring", recursively: true)!
        let tentative = hints.first { $0 !== bestRing.parent }!
        let fill = (tentative.geometry!.firstMaterial!.diffuse.contents as! NSColor).usingColorSpace(.sRGB)!
        require(abs(fill.redComponent - 0.447) < 0.001 && abs(fill.greenComponent - 0.129) < 0.001 && abs(fill.blueComponent - 0.42) < 0.001,
            "One-visit suggestion still uses its purple point-loss color")
        require(bestRing.parent!.position.x < tentative.position.x, "Blue ring marks G7, not the higher-winrate H7 outlier")
        let suggestionHost = NSHostingView(rootView: BoardView2D(boardVM: vm, layoutVM: app.layoutVM, size: CGSize(width: 820, height: 870)).environmentObject(app).frame(width: 900, height: 900))
        window.contentView = suggestionHost; settle(); suggestionHost.layoutSubtreeIfNeeded()
        let suggestionBitmap = suggestionHost.bitmapImageRepForCachingDisplay(in: suggestionHost.bounds)!
        suggestionHost.cacheDisplay(in: suggestionHost.bounds, to: suggestionBitmap)
        try suggestionBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("2d-tentative-suggestions.png"))
        let suggestionImage = renderer.snapshot(atTime: 0, with: CGSize(width: 1000, height: 850), antialiasingMode: .multisampling4X)
        try NSBitmapImageRep(data: suggestionImage.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("3d-tentative-suggestions.png"))
        scene.updateAIHints(moves: [], isAvailable: false, root: nil, nextMove: nil)
        require(scene.scene.rootNode.childNode(withName: "historical-move-inner-ring", recursively: true) == nil, "Disabling analysis clears the complete badge")
        print("PASS: continuous loss fills including intermediate and purple endpoints, a single blue best outline, white text on dark badges, stone-colored dashes, two values, lighting-independent candidates and removal; rendered 2D and 3D")
    }
}
