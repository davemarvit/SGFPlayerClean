import SwiftUI
import SceneKit
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class ResultsHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        require(request.httpMethod == "GET", "No game mutations in offline tests")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct SelectedMoveFeedbackCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.isMuted = true; AppSettings.shared.folderURL = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ResultsHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        let app = AppModel(ogsClient: client)
        defer { client.disconnect(); KataGoEngine.shared.stop() }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let text = "(;SZ[19]PB[Alice]PW[Bob]RU[Japanese];B[dd];W[jk];B[pp])"
        let url = temporary.appendingPathComponent("review.sgf")
        try text.write(to: url, atomically: true, encoding: .utf8)
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: text))))
        let vm = app.boardVM!, ai = KataGoEngine.shared
        app.aiAnalysisEnabled = true
        func settle(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        settle()
        for (turn, score, win) in [(0, 4.0, 0.7), (1, -2.0, 0.35), (2, 5.2, 0.8), (3, -4.0, 0.3)] {
            ai.currentAnalysisData[turn] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: turn, moveInfos: nil,
                rootInfo: AIRootInfo(winrate: win, scoreLead: score, visits: 100))
        }
        AppSettings.shared.showLastMoveDot = false
        AppSettings.shared.showMoveNumbers = true
        vm.mistakePlayers = .white; vm.mistakeMinimumLoss = 3
        vm.goToStart(); settle(); vm.seekNextMistake(); settle()
        require(vm.currentMoveIndex == 2 && vm.lastMovePosition == BoardPosition(10,9), "Red arrow selects the played White stone")
        require(vm.emphasizesReviewedMove && vm.selectedMoveFeedback?.title == "Move 2 · White · K9", "Selected-move feedback matches the board")
        require(vm.selectedMoveFeedback?.lossText == "3.2 points lost", "Selected-move loss")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua); window.orderFront(nil)
        defer { window.orderOut(nil) }
        func capture<V: View>(_ view: V, size: CGSize, name: String) throws -> String {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            window.setContentSize(size); window.contentView = host; settle(0.35)
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-selected-\(name).png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }
        let words = try capture(SelectedMoveStoneLabels(vm: vm, cellWidth: 130).background(.white),
            size: CGSize(width: 180, height: 180), name: "readout")
        require(words.contains("3.2") && words.contains("15.0"), "On-stone labels show points and probability change: \(words)")
        _ = try capture(BoardView2D(boardVM: vm, layoutVM: app.layoutVM, size: CGSize(width: 700, height: 754)).environmentObject(app),
                        size: CGSize(width: 760, height: 810), name: "2d")
        let scene = SceneManager3D()
        func updateScene() {
            scene.updateStones(from: vm.displayedStones, lastMove: vm.lastMovePosition, moveIndex: vm.currentMoveIndex,
                settings: AppSettings.shared, animate: false, emphasizeLastMove: vm.emphasizesReviewedMove)
            scene.updateSelectedMoveFeedback(vm.selectedMoveFeedback, at: vm.lastMovePosition)
        }
        updateScene()
        func nodes(_ name: String) -> [SCNNode] {
            var result: [SCNNode] = []
            scene.scene.rootNode.enumerateChildNodes { node, _ in if node.name == name { result.append(node) } }
            return result
        }
        require(nodes("MARKER_DOT").count == 1 && nodes("MARKER_NUMBER").isEmpty, "3D review forces a clear dot without a number over it")
        require(nodes("ai-selected-feedback").count == 1, "Exactly one on-stone label pair")
        let stone = vm.displayedStones.first { $0.id == BoardPosition(10,9) }!
        let anchor = nodes("MARKER_DOT")[0].parent!
        require(abs(Double(anchor.position.x) - Double(stone.offset.x)) < 0.001 &&
                abs(Double(anchor.position.z) - Double((1 + stone.offset.y) * 1.0773)) < 0.001, "3D dot is on K9, the actual mistaken move")
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene.scene; renderer.pointOfView = scene.cameraNode
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 900, height: 700), antialiasingMode: .multisampling4X)
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-selected-3d.png"))
        app.aiAnalysisEnabled = false; settle(); updateScene()
        require(vm.selectedMoveFeedback == nil && !vm.emphasizesReviewedMove, "AI off hides move feedback")
        require(nodes("ai-selected-feedback").isEmpty, "AI off removes on-stone labels")
        require(nodes("MARKER_DOT").isEmpty && nodes("MARKER_NUMBER").count == 1, "AI off restores the existing marker preference")
        require(!AppSettings.shared.showLastMoveDot && AppSettings.shared.showMoveNumbers, "Saved marker preferences unchanged")
        app.aiAnalysisEnabled = true; settle()
        ai.currentAnalysisData[2] = nil
        updateScene()
        require(nodes("ai-selected-feedback").isEmpty, "Missing analysis removes old on-stone labels")
        require(vm.selectedMoveFeedback?.pointsLost == nil, "Missing analysis shows pending, never a stale loss")
        ai.currentAnalysisData[2] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: 2, moveInfos: nil,
            rootInfo: AIRootInfo(winrate: 0.8, scoreLead: 5.2, visits: 100))
        vm.goToStart(); settle()
        require(vm.selectedMoveFeedback == nil, "Initial position has no previous move")
        app.mode = .playOnline; settle()
        require(vm.selectedMoveFeedback == nil && !vm.emphasizesReviewedMove, "No AI feedback in online play")
        print("PASS: selected move number/color/coordinate, correct point and probability loss, 2D/3D current red dot, marker preference restoration, missing analysis and mode gates")
    }
}
