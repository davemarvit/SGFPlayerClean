import SwiftUI
import SceneKit
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class FeedbackHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct ReviewFeedbackCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0; AppSettings.shared.folderURL = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedbackHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        let app = AppModel(ogsClient: client)
        defer { client.disconnect(); KataGoEngine.shared.stop() }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        func load(_ text: String, _ name: String) throws {
            let url = temporary.appendingPathComponent(name + ".sgf")
            try text.write(to: url, atomically: true, encoding: .utf8)
            app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: text))))
        }
        try load("(;SZ[9]" + (0..<120).map { ";\($0.isMultiple(of: 2) ? "B" : "W")[]" }.joined() + ")", "long")
        let vm = app.boardVM!
        app.aiAnalysisEnabled = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.orderOut(nil) }
        let host = NSHostingView(rootView: VariationTreeView(vm: vm).environmentObject(app).frame(width: 360, height: 400))
        window.contentView = host; window.orderFront(nil)
        func settle(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func find<T: NSView>(_ view: NSView, _ type: T.Type) -> T? {
            if let result = view as? T { return result }
            for child in view.subviews { if let result = find(child, type) { return result } }
            return nil
        }
        settle(); vm.selectReviewNode(30); settle()
        guard let anchor = find(host, VariationTreeScrollSupport.Anchor.self), let scroll = anchor.enclosingScrollView else {
            require(false, "Native tree scrolling attached"); return
        }
        require(scroll.hasVerticalScroller && !scroll.autohidesScrollers && scroll.scrollerStyle == .legacy,
                "Tree has a persistent scrollbar")
        func nodePoint(_ row: Int) -> CGPoint { anchor.convert(CGPoint(x: 38, y: 12 + CGFloat(row) * 22 + 11), to: nil) }
        var eventNumber = 0
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) {
            eventNumber += 1
            window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber, clickCount: 1, pressure: 1)!)
            settle(0.025)
        }
        let beforeClick = scroll.contentView.bounds.origin
        mouse(.leftMouseDown, nodePoint(29))
        require(vm.reviewTree?.selectedID == 30, "Mouse-down alone must not select")
        mouse(.leftMouseUp, nodePoint(29)); settle()
        require(vm.reviewTree?.selectedID == 29, "Click selects a tree node")
        require(scroll.contentView.bounds.origin == beforeClick, "Click on visible node does not move tree")
        vm.navigateReviewTree(vertical: -1); settle()
        require(vm.reviewTree?.selectedID == 28 && scroll.contentView.bounds.origin == beforeClick,
                "Visible arrow navigation does not recenter")
        func drag(from point: CGPoint) {
            mouse(.leftMouseDown, point)
            for step in 1...8 { mouse(.leftMouseDragged, CGPoint(x: point.x, y: point.y + CGFloat(step) * 12)) }
            mouse(.leftMouseUp, CGPoint(x: point.x, y: point.y + 96)); settle()
        }
        let beforeDrag = scroll.contentView.bounds.origin
        // Start the drag on an unselected node: it must pan rather than select.
        drag(from: nodePoint(27))

        require(abs(scroll.contentView.bounds.origin.y - beforeDrag.y) > 40, "Dragging a node scrolls tree")
        require(vm.reviewTree?.selectedID == 28, "Dragging does not select node or change board")
        let blank = scroll.contentView.convert(CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY), to: nil)
        let beforeBlank = scroll.contentView.bounds.origin
        drag(from: blank)
        require(abs(scroll.contentView.bounds.origin.y - beforeBlank.y) > 40 && vm.currentMoveIndex == 28,
                "Dragging empty tree space scrolls without navigation")
        if let surface = find(host, VariationTreeMouseSurface.Surface.self) {
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: nodePoint(27), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 100, clickCount: 1, pressure: 1)!
            let menu = surface.menu(for: event)
            require(menu?.items.first?.title == "Add pass here", "Scrolled node retains pass context menu")
            menu?.performActionForItem(at: 0); settle()
            require(vm.reviewTree?.selectedID == 28 && vm.reviewTree?.nodes.count == 121,
                    "Context menu targets the node under the pointer and reuses its existing pass")
        }
        vm.selectReviewNode(110); settle()
        let target = anchor.convert(CGRect(x: 27, y: 12 + 110 * 22, width: 22, height: 22), to: scroll.documentView)
        require(scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(target), "Distant keyboard/navigation target is revealed")

        guard let surface = find(host, VariationTreeMouseSurface.Surface.self), let scroller = scroll.verticalScroller else {
            require(false, "Mouse surface and scrollbar exist"); return
        }
        let thumbPoint = surface.convert(CGPoint(x: scroller.bounds.midX, y: scroller.bounds.midY), from: scroller)
        require(!surface.bounds.contains(thumbPoint), "Mouse surface leaves scrollbar unobstructed")
        let wheel = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 80, wheel2: 0, wheel3: 0)!)!
        let beforeWheel = scroll.contentView.bounds.origin
        surface.scrollWheel(with: wheel); settle()
        require(scroll.contentView.bounds.origin != beforeWheel && vm.currentMoveIndex == 110, "Wheel scrolling stays available without navigation")
        try load("(;SZ[9]" + String(repeating: "(;B[];W[])", count: 24) + ")", "wide")
        settle(); vm.selectReviewNode(47); settle()
        require(scroll.contentView.bounds.origin.x > 100, "Wide branch is revealed horizontally")
        let beforeHorizontal = scroll.contentView.bounds.origin.x
        let horizontalStart = scroll.contentView.convert(CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY), to: nil)
        mouse(.leftMouseDown, horizontalStart)
        for step in 1...8 { mouse(.leftMouseDragged, CGPoint(x: horizontalStart.x + CGFloat(step) * 12, y: horizontalStart.y)) }
        mouse(.leftMouseUp, CGPoint(x: horizontalStart.x + 96, y: horizontalStart.y)); settle()
        require(scroll.contentView.bounds.origin.x < beforeHorizontal - 40 && vm.reviewTree?.selectedID == 47,
                "Horizontal dragging preserves the selected variation")
        host.layoutSubtreeIfNeeded()
        let treeImage = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: treeImage)
        try treeImage.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-feedback-tree.png"))

        try load("(;SZ[19]PB[Alice]BR[4k]PW[Bob]WR[6k]RU[Japanese];B[dd];W[pp];B[jj];W[jk];B[kk];W[kj])", "markers")
        app.aiAnalysisEnabled = true; vm.goToEnd(); settle()
        let ai = KataGoEngine.shared
        let blackScores: [Double] = [0,0,0,-1,4,-5,10]
        for turn in 0...6 {
            ai.currentAnalysisData[turn] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: turn, moveInfos: [],
                rootInfo: AIRootInfo(winrate: 0.5, scoreLead: blackScores[turn] * (turn.isMultiple(of: 2) ? 1 : -1), visits: 100))
        }
        settle()
        require(vm.recentMoveQualityMarkers.map(\.id) == [5,4,3], "Only preceding three stones receive rings")
        require(vm.recentMoveQualityMarkers.map(\.quality) == [.disastrous, .poor, .good], "Rings use table's exact classes")
        let scene = SceneManager3D()
        scene.updateBoardSize(19)
        scene.updateStones(from: vm.displayedStones, lastMove: vm.lastMovePosition, moveIndex: 6, settings: AppSettings.shared, animate: false)
        scene.updateRecentMoveQuality(vm.recentMoveQualityMarkers)
        var count = 0
        scene.scene.rootNode.enumerateChildNodes { node, _ in if node.name == "ai-recent-quality" { count += 1 } }
        require(count == 3, "3D contains three quality markers")
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene.scene; renderer.pointOfView = scene.cameraNode
        let sceneImage = renderer.snapshot(atTime: 0, with: CGSize(width: 1100, height: 850), antialiasingMode: .multisampling4X)
        let sceneBitmap = NSBitmapImageRep(data: sceneImage.tiffRepresentation!)!
        try sceneBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-feedback-scene.png"))
        scene.updateRecentMoveQuality([])
        count = 0
        scene.scene.rootNode.enumerateChildNodes { node, _ in if node.name == "ai-recent-quality" { count += 1 } }
        require(count == 0, "3D clears markers when unavailable")
        func capture<V: View>(_ view: V, size: CGSize, name: String) throws -> String {
            let view = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            window.setContentSize(size); window.contentView = view; settle(0.45)
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-feedback-\(name).png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }
        _ = try capture(BoardView2D(boardVM: vm, layoutVM: app.layoutVM, size: CGSize(width: 700, height: 754)).environmentObject(app),
                        size: CGSize(width: 760, height: 810), name: "2d")
        app.viewMode = .view3D
        _ = try capture(ContentView3D().environmentObject(app), size: CGSize(width: 1100, height: 850), name: "3d")
        let pill = try capture(PlaybackControlsView(boardVM: vm).environmentObject(app).background(.black),
                               size: CGSize(width: 750, height: 110), name: "players")
        require(pill.contains("Alice") && pill.contains("Bob") && pill.contains("4k") && pill.contains("6k") && !pill.contains("Japanese"),
                "Player pill shows names/ranks instead of rules: \(pill)")
        vm.moveError = "That intersection is occupied."
        let error = try capture(PlaybackControlsView(boardVM: vm).environmentObject(app).background(.black),
                                size: CGSize(width: 750, height: 110), name: "error")
        require(error.contains("occupied"), "Important transient messages still override player pill")
        vm.moveError = nil
        app.aiAnalysisEnabled = false; settle()
        require(vm.recentMoveQualityMarkers.isEmpty, "AI off removes quality markers")
        app.mode = .localPlay; app.aiAnalysisEnabled = true; settle()
        require(vm.recentMoveQualityMarkers.isEmpty, "Quality rings restricted to Review")
        print("PASS: click without recentering, arrow reveal, native scrollbars, node/blank drag without navigation, recent quality markers in 2D/3D, names/ranks and transient messages")
    }
}
