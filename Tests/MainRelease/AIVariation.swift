import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class PreviewHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct PreviewCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.stoneVolume = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PreviewHTTP.self]; config.httpCookieStorage = nil
        let app = AppModel(ogsClient: OGSClient(session: URLSession(configuration: config)))
        let game = SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9]RU[Japanese];B[aa];W[bb];B[cc])"))
        let gameURL = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID()).sgf")
        try "(;SZ[9];B[aa];W[bb];B[cc])".write(to: gameURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: gameURL) }
        app.selectGame(SGFGameWrapper(url: gameURL, game: game))
        app.aiAnalysisEnabled = true
        let vm = app.boardVM!
        func settle(_ time: Double = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(time)) }
        settle(); vm.seekToMove(1); settle()
        let ai = KataGoEngine.shared
        let candidate = AIMoveInfo(move: "C7", visits: 50, winrate: 0.6, scoreLead: 2, pv: ["C7", "D6", "pass"])
        ai.currentAnalysisData[1] = AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: 1,
            moveInfos: [candidate], rootInfo: AIRootInfo(winrate: 0.6, scoreLead: 2, visits: 50))
        let original = app.player.board
        var sounds = 0; vm.onPlaySound = { _ in sounds += 1 }
        vm.hoverAnalysis(at: BoardPosition(2,2)); settle(0.2)
        require(!vm.isPreviewingVariation, "Dwell prevents flickering previews")
        vm.hoverAnalysis(at: nil); settle(0.4)
        require(!vm.isPreviewingVariation, "Leaving before dwell cancels late preview")
        vm.hoverAnalysis(at: BoardPosition(2,2)); settle(0.55)
        require(vm.variationFrame?.numbers[BoardPosition(2,2)] == 1, "First preview move appears")
        require(vm.displayedStones.count == 2, "2D display includes hypothetical stone")
        require(app.player.board == original && app.player.currentIndex == 1 && app.player.maxIndex == 3,
            "Preview cannot edit actual position or history")
        require(vm.blackCapturedCount == 0 && vm.whiteCapturedCount == 0 && sounds == 0,
            "Preview cannot animate captures in lids or play move sounds")
        let scene = SceneManager3D()
        scene.updateBoardSize(9)
        scene.updateStones(from: vm.displayedStones, lastMove: nil, moveIndex: 1, settings: AppSettings.shared, animate: false)
        scene.updateVariationNumbers(frame: vm.variationFrame)
        require(scene.scene.rootNode.childNode(withName: "ai-variation-number", recursively: true) != nil, "3D preview numbered")
        let boardView = NSHostingView(rootView: BoardView2D(boardVM: vm, layoutVM: app.layoutVM, size: CGSize(width: 500, height: 539)).environmentObject(app))
        boardView.frame = CGRect(x: 0, y: 0, width: 500, height: 539)
        boardView.layoutSubtreeIfNeeded()
        require(boardView.fittingSize.width > 0, "2D preview view renders")
        if let bitmap = boardView.bitmapImageRepForCachingDisplay(in: boardView.bounds) {
            boardView.cacheDisplay(in: boardView.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/sgf-ai-preview-2d.png"))
        }
        scene.updateCameraPosition(distance: 34, rotationX: 0.75, rotationY: 0, panX: 0, panY: 0)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene.scene; renderer.pointOfView = scene.cameraNode
        let snapshot = renderer.snapshot(atTime: 0, with: CGSize(width: 700, height: 650), antialiasingMode: .multisampling4X)
        if let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/sgf-ai-preview-3d.png"))
        }
        settle(0.65)
        require(vm.variationFrame?.numbers[BoardPosition(3,3)] == 2, "Continuation animates")
        vm.hoverAnalysis(at: nil)
        require(!vm.isPreviewingVariation && vm.displayedStones.count == 1, "Leaving restores board immediately")
        scene.updateStones(from: vm.displayedStones, lastMove: vm.lastMovePosition, moveIndex: 1, settings: AppSettings.shared, animate: false)
        scene.updateVariationNumbers(frame: nil)
        require(scene.scene.rootNode.childNode(withName: "ai-variation-number", recursively: true) == nil, "3D preview numbers cleared")
        vm.hoverAnalysis(at: BoardPosition(2,2)); settle(0.55)
        app.aiAnalysisEnabled = false
        require(!vm.isPreviewingVariation && ai.currentAnalysisData[1] != nil, "AI off cancels preview but keeps analysis")
        app.aiAnalysisEnabled = true
        vm.hoverAnalysis(at: BoardPosition(2,2)); vm.seekToMove(2); settle(0.6)
        require(!vm.isPreviewingVariation, "Navigation cancels pending preview")
        app.mode = .localPlay; settle()
        require(vm.canPreviewAnalysis?() == false, "Hover preview restricted to Review")
        app.mode = .playOnline; settle()
        require(!app.isAIAvailable && vm.canPreviewAnalysis?() == false, "No online-play analysis")
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApplication.shared)
        require(!ai.isEngineRunning, "Termination hook stops engine synchronously")
        print("PASS: preview dwell, animation, restoration, 2D/3D display, history/capture/audio isolation, AI toggle and mode restrictions")
    }
}
