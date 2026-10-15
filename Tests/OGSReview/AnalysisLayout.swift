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

@main struct AnalysisLayoutCheck {
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
                moveInfos: [], rootInfo: AIRootInfo(winrate: 0.4 + Double(turn) * 0.03, scoreLead: Double(turn) - 3, visits: 100))
        }
        defer { ai.stop(); client.disconnect(); try? FileManager.default.removeItem(at: temp) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1714, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.orderOut(nil) }
        func findScene(_ view: NSView) -> SCNView? {
            (view as? SCNView) ?? view.subviews.lazy.compactMap(findScene).first
        }
        for mode in [ViewMode.view2D, .view3D] {
            for (width, height, sidebar) in [(1714, 900, true), (1280, 800, false), (1280, 800, true), (900, 1000, false)] {
                model.viewMode = mode; model.showRightPanel = sidebar
                let size = CGSize(width: width, height: height)
                let geometry = BoardWorkspaceGeometry(size: size, aiEnabled: true, sidebarVisible: sidebar)
                require(geometry.aiWidth >= 280 && geometry.boardWidth > 0, "AI remains a usable right-hand column")
                require(geometry.boardWidth > geometry.aiOrigin, "AI can overlap lids to recover board space")
                // A width-limited 2D board should gain at least 30% versus the previous separate-column layout.
                if width == 900 { require(geometry.boardWidth / geometry.aiOrigin > 1.30, "Recover meaningful board size") }
                require(geometry.reservesSidebar == (sidebar && width >= 1500), "Game panel overlays only in tighter windows")
                let host = NSHostingView(rootView: BoardWorkspaceView(vm: vm, analysisEngine: ai) {
                    if mode == .view2D { ContentView2D() } else { ContentView3D() }
                }.environmentObject(model).frame(width: size.width, height: size.height))
                window.setContentSize(size); window.contentView = host; window.orderFront(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                host.layoutSubtreeIfNeeded()
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let name = "\(mode == .view2D ? "2d" : "3d")-\(width)-\(sidebar ? "sidebar" : "open")"
                let scaleX = CGFloat(bitmap.pixelsWide) / size.width
                let scaleY = CGFloat(bitmap.pixelsHigh) / size.height
                func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor {
                    bitmap.colorAt(x: Int(x * scaleX), y: Int(y * scaleY))!.usingColorSpace(.sRGB)!
                }
                let margin = pixel(5, 5)
                if mode == .view3D {
                    require(margin.redComponent < 0.08 && margin.greenComponent < 0.08 && margin.blueComponent < 0.12,
                            "3D viewport margins must not expose tatami in \(name)")
                    if !sidebar || geometry.reservesSidebar {
                        let analysisBackground = pixel(geometry.aiOrigin + geometry.aiWidth / 2, size.height - 30)
                        require(analysisBackground.redComponent < 0.08 && analysisBackground.greenComponent < 0.08,
                                "3D analysis column must share the dark workspace in \(name)")
                    }
                } else {
                    require(margin.greenComponent > 0.2 && margin.greenComponent > margin.blueComponent,
                            "2D retains its tatami background in \(name)")
                }
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-analysis-\(name).png"))
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
                if !sidebar || geometry.reservesSidebar {
                    guard let label = request.results?.first(where: { $0.topCandidates(1).first?.string.lowercased().hasSuffix(" analysis") == true }) else {
                        require(false, "AI header is visible in \(name)"); return
                    }
                    let x = label.boundingBox.minX * size.width
                    require(x >= geometry.aiOrigin && x < geometry.aiOrigin + geometry.aiWidth, "AI stays to the right, never below the board")
                    let labels = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
                    require(labels.contains("Alice") && labels.contains("Bob"), "Metadata fits beneath graph: \(labels)")
                }
                if mode == .view3D {
                    guard let sceneView = findScene(host) else { require(false, "3D scene missing"); return }
                    let renderer = SCNRenderer(device: sceneView.device, options: nil)
                    renderer.scene = sceneView.scene; renderer.pointOfView = sceneView.pointOfView
                    let rendered = renderer.snapshot(atTime: 0, with: sceneView.bounds.size, antialiasingMode: .multisampling4X)
                    let image = NSBitmapImageRep(data: rendered.tiffRepresentation!)!
                    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-scene-\(name).png"))
                    let extent = sceneView.convert(sceneView.bounds, to: host)
                    let sceneBackground = image.colorAt(x: 5, y: 5)!.usingColorSpace(.sRGB)!
                    require(abs(sceneBackground.redComponent - margin.redComponent) < 0.02 &&
                            abs(sceneBackground.greenComponent - margin.greenComponent) < 0.02 &&
                            abs(sceneBackground.blueComponent - margin.blueComponent) < 0.02,
                            "Scene and surrounding 3D workspace must have matching backgrounds")
                    // AppKit's background-window capture may omit the Metal layer.
                    // Composite the actual renderer snapshot for visual inspection.
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                    let context = NSGraphicsContext.current!.cgContext
                    context.clip(to: CGRect(x: 0, y: 0, width: geometry.aiOrigin, height: size.height))
                    let y = host.isFlipped ? size.height - extent.maxY : extent.minY
                    rendered.draw(in: NSRect(x: extent.minX, y: y,
                        width: extent.width, height: extent.height))
                    NSGraphicsContext.restoreGraphicsState()
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-analysis-composite-\(name).png"))
                    var objects: [SCNNode] = []
                    sceneView.scene!.rootNode.enumerateChildNodes { node, _ in
                        if let box = node.geometry as? SCNBox, box.height == 2 { objects.append(node) }
                        if node.name == "white-player-lid" || node.name == "black-player-lid" { objects.append(node) }
                    }
                    require(objects.count == 3, "Board and two lids present")
                    for node in objects {
                        let bounds = node.boundingBox
                        for x in [bounds.min.x, bounds.max.x] {
                            for y in [bounds.min.y, bounds.max.y] {
                                for z in [bounds.min.z, bounds.max.z] {
                                    let point = renderer.projectPoint(node.convertPosition(SCNVector3(x, y, z), to: nil))
                                    let screenX = CGFloat(point.x) + extent.minX
                                    let rightEdge = node.geometry is SCNBox ? geometry.aiOrigin : geometry.boardWidth
                                    require(screenX >= 0 && screenX <= rightEdge,
                                        "3D board/lid cropped in \(name): \(node.name ?? "board") at \(screenX), width \(geometry.boardWidth)")
                                }
                            }
                        }
                    }
                }
                require(vm.currentMoveIndex == 6 && vm.stonesToRender.count == 6, "Layout changes preserve game position")
            }
        }
        print("PASS: 2D/3D AI remains right of board at wide, narrow and portrait sizes; wide sidebar reserves space, narrow sidebar overlays; graph and metadata visible after collapse; position preserved; 3D scene, margins and AI column share a dark background while 2D keeps tatami. Network denied.")
    }
}
