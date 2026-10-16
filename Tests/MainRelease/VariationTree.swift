import SwiftUI
import SceneKit
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class TreeHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct VariationTreeCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0; AppSettings.shared.folderURL = nil
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("tree-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TreeHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        let app = AppModel(ogsClient: client)
        defer { client.disconnect(); KataGoEngine.shared.stop() }
        let text = "(;SZ[9]RU[Japanese]KM[0.5]PB[Alice]PW[Bob]AB[ba]AW[aa]PL[B];B[ii]C[Original line];W[hh];B[gg])"
        let url = temp.appendingPathComponent("branches.sgf")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let wrapper = SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: text)))
        app.selectGame(wrapper); app.aiAnalysisEnabled = false; app.showRightPanel = false
        let vm = app.boardVM!
        func settle(_ seconds: Double = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        settle()
        require(app.mode == .review && app.showsAnalysisWorkspace && !app.isAIAvailable, "Tree available with AI off")
        require(vm.reviewTree?.nodes.count == 4, "Initial tree")
        let originalData = vm.reviewSGFData()!
        let baseID = KataGoEngine.shared.currentGameId
        vm.placeStone(at: BoardPosition(1,0)); settle()
        require(vm.currentMoveIndex == 1 && vm.engine.capturesByBlack == 1 && vm.blackCapturedCount == 1 && vm.whiteCapturedCount == 0, "New branch captures exactly one white stone")
        require(vm.reviewTree?.nodes.count == 5 && vm.reviewDraftSaved, "Branch created and durable draft saved")
        let sourceAfterEdit = try String(contentsOf: url)
        require(sourceAfterEdit == text, "Source file untouched")
        require(KataGoEngine.shared.currentGameId != baseID, "Alternative uses isolated analysis cache ID")
        let branchID = vm.reviewTree!.selectedID
        let alternateKey = KataGoEngine.shared.currentGameId
        vm.passLocally(); settle()
        require(vm.reviewTree!.nodes[vm.reviewTree!.selectedID].isPass && vm.currentMoveIndex == 2, "Pass creates a persistent node")
        vm.selectReviewNode(1); settle()
        require(vm.engine.capturesByBlack == 0 && vm.blackCapturedCount == 0 && vm.engine.board.grid[0][0] == .white, "Original branch restores board and lid counts")
        require(KataGoEngine.shared.currentGameId == baseID, "Main line reuses original cache identity")
        vm.selectReviewNode(branchID); settle()
        require(vm.blackCapturedCount == 1, "Alternative capture restored")
        require(KataGoEngine.shared.currentGameId != baseID && KataGoEngine.shared.currentGameId != alternateKey, "Extended branch has updated cache fingerprint")
        vm.stepBackward(); settle()
        require(vm.reviewTree!.selectedID == 0 && vm.blackCapturedCount == 0, "Playback arrows track tree and captures")
        vm.placeStone(at: BoardPosition(1,0)); settle()
        require(vm.reviewTree?.nodes.count == 6 && vm.reviewTree?.selectedID == branchID, "Replaying an existing move reuses its branch")
        vm.placeStone(at: BoardPosition(0,1)); settle()
        require(vm.reviewTree?.nodes.count == 6 && vm.moveError != nil, "Illegal occupied move cannot change tree")
        let saved = temp.appendingPathComponent("export.sgf")
        try vm.writeReviewSGF(to: saved)
        let exported = try SGFParser.parse(text: String(contentsOf: saved))
        require(ReviewTree(game: SGFGame.from(tree: exported), analysisID: "export", filename: "export.sgf").nodes.count == 6, "Export includes all original and new nodes")
        require(SGFGame.from(tree: exported).moves.count == 3, "Original main line stays first")
        require(vm.reviewSGFData() != originalData, "Only explicit play changes saved tree")
        // Recover from disk by loading the unchanged source again, independent of in-memory saved modes.
        app.selectGame(wrapper); settle()
        require(vm.reviewTree?.nodes.count == 6 && vm.reviewDraftSaved && vm.currentMoveIndex == 1, "Reopening source recovers draft and edited position")
        app.mode = .localPlay; settle(); app.mode = .review; settle()
        require(vm.reviewTree?.nodes.count == 6 && vm.currentMoveIndex == 1, "Mode round trip preserves complete review tree")
        app.copyCurrentBoard(to: .localPlay); settle()
        require(vm.reviewTree == nil, "Local editing cannot retain a stale review document")
        vm.goToEnd(); settle(); vm.placeStone(at: BoardPosition(3,3)); settle()
        app.copyCurrentBoard(to: .review); settle()
        require(vm.reviewTree?.nodes.count == vm.totalMoves + 1 && vm.reviewTree?.nodes.count == 4, "Copy edited local board creates a fresh tree")
        app.selectGame(wrapper); settle()
        // AI hover previews remain separate from the persisted tree, even during export.
        vm.selectReviewNode(0); app.aiAnalysisEnabled = true; settle()
        let ai = KataGoEngine.shared
        let candidate = AIMoveInfo(move: "C7", visits: 50, winrate: 0.6, scoreLead: 2, pv: ["C7","D6","pass"])
        ai.currentAnalysisData[0] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: 0,
            moveInfos: [candidate], rootInfo: AIRootInfo(winrate: 0.6, scoreLead: 2, visits: 50))
        let beforeHover = vm.reviewSGFData()
        vm.hoverAnalysis(at: BoardPosition(2,2)); settle(0.55)
        require(vm.isPreviewingVariation, "Temporary preview starts")
        require(vm.reviewSGFData() == beforeHover && vm.reviewTree?.nodes.count == 6, "Hover preview excluded from SGF and tree")
        vm.selectReviewNode(branchID); settle()
        require(!vm.isPreviewingVariation && vm.blackCapturedCount == 1, "Branch navigation cancels hover preview")
        app.aiAnalysisEnabled = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.orderOut(nil) }
        for mode in [ViewMode.view2D, .view3D] {
            app.viewMode = mode
            let host = NSHostingView(rootView: BoardWorkspaceView(vm: vm) {
                if mode == .view2D { ContentView2D() } else { ContentView3D() }
            }.environmentObject(app).frame(width: 1280, height: 850))
            window.contentView = host; window.orderFront(nil); settle(0.5)
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let name = mode == .view2D ? "2d" : "3d"
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-tree-\(name).png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            let labels = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            require(labels.contains("Variations") && labels.contains("Save SGF"), "Tree and export controls visible in \(name) with AI off: \(labels)")
        }
        // Interact with the real SwiftUI tree, not only its view-model methods.
        app.viewMode = .view2D
        window.setContentSize(CGSize(width: 360, height: 320))
        let treeHost = NSHostingView(rootView: VariationTreeView(vm: vm).environmentObject(app).frame(width: 360, height: 320))
        window.contentView = treeHost; settle(0.3)
        func selectionCenter() -> CGPoint? {
            treeHost.layoutSubtreeIfNeeded()
            guard let bitmap = treeHost.bitmapImageRepForCachingDisplay(in: treeHost.bounds) else { return nil }
            treeHost.cacheDisplay(in: treeHost.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/sgf-tree-interaction.png"))
            var xs: [CGFloat] = []; var ys: [CGFloat] = []
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if c.blueComponent > c.redComponent + 0.25 && c.greenComponent > c.redComponent + 0.2 {
                        xs.append(CGFloat(x)); ys.append(CGFloat(y))
                    }
                }
            }
            guard xs.count > 20 else { return nil }
            return CGPoint(x: xs.reduce(0,+) / CGFloat(xs.count) * 360 / CGFloat(bitmap.pixelsWide),
                           y: 320 - ys.reduce(0,+) / CGFloat(ys.count) * 320 / CGFloat(bitmap.pixelsHigh))
        }
        guard let selectedCenter = selectionCenter() else { require(false, "Selected node ring visible"); return }
        let originalCenter = CGPoint(x: selectedCenter.x - 22, y: selectedCenter.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: originalCenter, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        settle()
        require(vm.reviewTree?.selectedID == 1 && vm.blackCapturedCount == 0, "Clicking original node switches branch")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false, keyCode: 125)!
        window.sendEvent(key); settle()
        require(vm.reviewTree?.selectedID == 2, "Focused tree handles down arrow")
        let longText = "(;SZ[9]RU[Japanese]" + (0..<200).map { ";\($0.isMultiple(of: 2) ? "B" : "W")[]" }.joined() + ")"
        app.selectGame(SGFGameWrapper(url: temp.appendingPathComponent("long.sgf"), game: SGFGame.from(tree: try SGFParser.parse(text: longText))))
        settle(); vm.selectReviewNode(200); settle(0.4)
        require(selectionCenter() != nil, "Distant selected node automatically scrolls into view")
        app.mode = .playOnline; settle()
        let index = vm.engine.currentIndex
        vm.selectReviewNode(1); vm.addReviewMove(at: BoardPosition(5,5))
        require(vm.engine.currentIndex == index && !vm.canCreateReviewVariation, "Online play cannot edit review tree")
        print("PASS: AI-independent tree creation/navigation, captures and lids, legal moves, passes, branch caches, atomic SGF export, draft recovery, mode snapshots, hover isolation, 2D/3D UI, online edit guard")
    }
}
