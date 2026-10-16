import SwiftUI
import SceneKit
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class LayoutHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct TreeGraphLayoutCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        AppSettings.shared.folderURL = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LayoutHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        let model = AppModel(ogsClient: client)
        let game = SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19]PB[Alice]PW[Bob]RU[Japanese];B[pd];W[dd];B[qp];W[dp];B[cd];W[cc])"))
        model.selectGame(SGFGameWrapper(url: URL(fileURLWithPath: "/private/tmp/layout-fixture.sgf"), game: game))
        model.aiAnalysisEnabled = true
        let vm = model.boardVM!
        vm.goToEnd()
        // A temporary process keeps the graph in its running state. All data is
        // injected locally; no real engine, user cache or OGS connection is used.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let executable = temp.appendingPathComponent("engine")
        try "#!/bin/sh\nwhile IFS= read -r line; do :; done\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let weights = temp.appendingPathComponent("weights")
        try Data().write(to: weights)
        let ai = KataGoEngine(executableURL: executable, modelURL: weights, cacheDirectory: temp)
        ai.start()
        require(ai.isEngineRunning, "Fixture engine starts")
        for turn in 0...6 {
            ai.currentAnalysisData[turn] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: turn,
                moveInfos: [], rootInfo: AIRootInfo(winrate: turn.isMultiple(of: 2) ? 0.72 : 0.28, scoreLead: turn.isMultiple(of: 2) ? 7.5 : -7.5, visits: 100))
        }
        defer { ai.stop(); client.disconnect(); try? FileManager.default.removeItem(at: temp) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1714, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.orderOut(nil) }
        model.viewMode = .view2D; model.showRightPanel = false
        vm.seekToMove(3)
        model.aiAnalysisEnabled = false
        let host = NSHostingView(rootView: AIWorkspacePanel(vm: vm, ai: ai).environmentObject(model)
            .frame(width: 400, height: 850).background(Color(nsColor: .windowBackgroundColor)))
        window.setContentSize(CGSize(width: 400, height: 850)); window.contentView = host; window.orderFront(nil)
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.25)) }
        func capture(_ name: String) throws -> NSBitmapImageRep {
            settle(); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-tree-graph-\(name).png"))
            return bitmap
        }
        func labels(_ bitmap: NSBitmapImageRep) throws -> [VNRecognizedTextObservation] {
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return request.results ?? []
        }
        func ringCenter(_ bitmap: NSBitmapImageRep) -> CGPoint? {
            var total = CGPoint.zero; var count: CGFloat = 0
            // Only the upper tree viewport, excluding the blue graph below it.
            for y in 70..<Int(CGFloat(bitmap.pixelsHigh) * 0.55) {
                for x in 0..<bitmap.pixelsWide {
                    let c = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    if c.blueComponent > c.redComponent + 0.25 && c.greenComponent > c.redComponent + 0.2 {
                        total.x += CGFloat(x); total.y += CGFloat(y); count += 1
                    }
                }
            }
            return count > 20 ? CGPoint(x: total.x/count, y: total.y/count) : nil
        }
        let before = try capture("ai-off")
        guard let beforeCenter = ringCenter(before) else { require(false, "Selected tree node visible before AI"); return }
        model.aiAnalysisEnabled = true
        let after = try capture("ai-on")
        guard let afterCenter = ringCenter(after) else { require(false, "Selected tree node visible after AI"); return }
        require(abs(beforeCenter.x - afterCenter.x) < 1 && abs(beforeCenter.y - afterCenter.y) < 1,
                "Toggling AI must not move the selected tree node")
        let text = try labels(after)
        let strings = text.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        require(strings.contains("B+7.5") && strings.contains("72%"), "Current-move estimates visible: \(strings)")
        let aiHeader = text.first { $0.topCandidates(1).first?.string.hasSuffix(" analysis") == true }!
        require(aiHeader.boundingBox.midY < 0.46, "AI information sits below the tree")
        require(vm.currentMoveIndex == 3 && vm.reviewTree?.selectedID == 3, "Toggle preserves game position")
        // The chevron is part of the production view; exercise its actual click target.
        func click(_ point: CGPoint) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            }
            settle()
        }
        click(CGPoint(x: 24, y: 850 - 22))
        let collapsed = try capture("collapsed")
        let collapsedLabels = try labels(collapsed)
        let collapsedHeader = collapsedLabels.first { $0.topCandidates(1).first?.string.hasSuffix(" analysis") == true }!
        require(collapsedHeader.boundingBox.midY > 0.85, "Collapsing tree gives AI the space below its header")
        require(vm.currentMoveIndex == 3 && vm.reviewTree?.selectedID == 3, "Collapse must not navigate")
        click(CGPoint(x: 24, y: 850 - 22))
        let expanded = try capture("expanded")
        require(ringCenter(expanded) != nil && vm.reviewTree?.selectedID == 3, "Expanding restores selected node")
        // Pending positions retain the red cursor and never borrow another move's values.
        ai.currentAnalysisData[3] = nil
        let pending = try capture("pending")
        let pendingText = try labels(pending).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        require(pendingText.contains("Pending") && !pendingText.contains("B+7.5"), "Missing current analysis is explicit")
        // Capture graph alone for edge labels, white lead and gradient inspection.
        ai.currentAnalysisData[0] = AIAnalysis(id: "white", isDuringSearch: false, turnNumber: 0, moveInfos: [],
            rootInfo: AIRootInfo(winrate: 0.2, scoreLead: -2.5, visits: 100))
        vm.seekToMove(0); settle()
        let graphHost = NSHostingView(rootView: WinRateGraphView(aiEngine: ai, vm: vm).environmentObject(model)
            .frame(width: 320, height: 210).background(Color(nsColor: .windowBackgroundColor)))
        window.setContentSize(CGSize(width: 320, height: 210)); window.contentView = graphHost; settle()
        graphHost.layoutSubtreeIfNeeded()
        let graph = graphHost.bitmapImageRepForCachingDisplay(in: graphHost.bounds)!
        graphHost.cacheDisplay(in: graphHost.bounds, to: graph)
        try graph.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-tree-graph-white.png"))
        let whiteText = try labels(graph).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        require(whiteText.contains("W+2.5") && whiteText.contains("80%"), "Left-edge White label is readable: \(whiteText)")
        // Shared bottom controller must not offer game actions during Review.
        for mode in [AppMode.review, .localPlay, .observe] {
            model.mode = mode; settle()
            let controls = NSHostingView(rootView: PlaybackControlsView(boardVM: vm).environmentObject(model)
                .frame(width: 700, height: 100).background(Color(nsColor: .windowBackgroundColor)))
            window.setContentSize(CGSize(width: 700, height: 100)); window.contentView = controls; settle()
            controls.layoutSubtreeIfNeeded()
            let bitmap = controls.bitmapImageRepForCachingDisplay(in: controls.bounds)!
            controls.cacheDisplay(in: controls.bounds, to: bitmap)
            let words = try labels(bitmap).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased().split(separator: " ")
            require(words.contains("pass") == (mode == .localPlay), "Bottom Pass visibility follows actual play mode: \(mode)")
        }
        print("PASS: stable tree viewport with AI toggles, analysis below tree, real collapse/expand clicks, retained selection, Black/White numerical labels and explicit pending positions")
    }
}
