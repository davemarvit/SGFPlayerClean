import SwiftUI
import SceneKit
import Vision
@testable import SGF_Player_Offline_Review

@main struct LocalScoringCheck {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.offline-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        let model = AppModel()
        model.showRightPanel = false
        let sgf = "(;SZ[9]RU[Japanese]KM[6.5]PB[Dave]PW[Alice]AB[da][db][dc][dd][de][df][dg][dh][di][ba][bb][bc][cc][ad]AW[fa][fb][fc][fd][fe][ff][fg][fh][fi][aa][ab])"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("local-scoring-\(UUID()).sgf")
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let wrapper = SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf)))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 850),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Offline local scoring check"
        defer { window.orderOut(nil) }
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        func wait(_ seconds: Double = 0.25) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func sceneView(_ view: NSView) -> SCNView? {
            if let found = view as? SCNView { return found }
            return view.subviews.compactMap { sceneView($0) }.first
        }
        func snapshot(_ host: NSView, _ name: String) throws -> String {
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-local-score-\(name).png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined().filter { !$0.isWhitespace }.lowercased()
        }
        for mode in [ViewMode.view2D, .view3D] {
            model.viewMode = mode; model.selectGame(wrapper)
            model.showRightPanel = mode == .view2D
            let vm = model.boardVM!
            let host = NSHostingView(rootView: ContentView().environmentObject(model))
            window.contentView = host; window.orderFront(nil); wait(0.5)
            let initial = model.player.board
            vm.passLocally(); wait(); vm.passLocally(); wait()
            check(vm.localScoringVisible, "Two passes did not start scoring")
            check(!model.player.isPlaying, "Scoring must pause playback")
            check(try snapshot(host, "\(mode)-review").contains("reviewscore"), "Scoring sidebar did not open while sidebar was closed")
            vm.placeStone(at: BoardPosition(0,0)); wait()
            check(vm.localScoring?.deadStones.count == 2, "Click did not mark the entire group")
            check(vm.stonesToRender.filter(\.isDead).count == 2, "Dead stones are not faded")
            check(vm.localScoring?.result?.black.total == 24, "Incorrect territory plus dead-prisoner total")
            check(vm.localScoring?.result?.white.total == 33.5, "Incorrect white komi total")
            check(vm.territoryPoints.values.filter { $0 == .black }.count == 22, "Black territory is wrong")
            check(vm.territoryPoints.values.filter { $0 == .white }.count == 27, "White territory is wrong")
            check(model.player.board == initial && model.player.currentIndex == 2, "Marking changed the game history")
            check(vm.blackCapturedCount == 0 && vm.whiteCapturedCount == 0, "Scoring mutated capture lids")
            if let scene = sceneView(host) {
                var colors: [String: Int] = [:]
                scene.scene!.rootNode.enumerateChildNodes { node, _ in
                    if let name = node.name, name.hasPrefix("territory-") { colors[name, default: 0] += 1 }
                }
                check(colors["territory-black"] == 22 && colors["territory-white"] == 27, "3D markers do not match the score")
                let bitmap = NSBitmapImageRep(data: scene.snapshot().tiffRepresentation!)!
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-local-score-3D-board.png"))
            }
            vm.editLocalScoring { $0.tool = .neutralAreas }
            vm.placeStone(at: BoardPosition(2,0)); wait()
            check(vm.localScoring?.result?.black.territory == 19, "Neutral area was not excluded")
            vm.placeStone(at: BoardPosition(2,0)); wait()
            check(vm.localScoring?.result?.black.territory == 22, "Neutral area toggle was not reversible")
            vm.confirmLocalScore(); wait()
            let text = try snapshot(host, "\(mode)-final")
            check(text.contains("finalscore") && text.contains("alice[white]winsby9.5points"), "Final winner text missing/clipped")
            vm.placeStone(at: BoardPosition(0,0)); wait()
            check(vm.localScoring?.deadStones.count == 2, "Confirmed score was editable")
            vm.stepBackward(); wait()
            check(!vm.localScoringVisible && vm.territoryPoints.isEmpty && vm.stonesToRender.allSatisfy { !$0.isDead }, "Rewind retained scoring marks")
            vm.goToEnd(); wait()
            check(vm.localScoringVisible && vm.localScoring?.isFinal == true && vm.localScoring?.deadStones.count == 2, "Review result was lost on rewind/replay")
            vm.reviewLocalScore(); vm.editLocalScoring { $0.tool = .deadGroups }
            vm.placeStone(at: BoardPosition(0,0)); wait()
            check(vm.localScoring?.deadStones.isEmpty == true, "Edit scoring did not restore live stones")
            vm.resumeLocalPlay(); wait()
            check(!vm.localScoringVisible && vm.territoryPoints.isEmpty, "Resume left scoring mode active")
            vm.passLocally(); wait()
            check(!vm.localScoringVisible, "One new pass after resumption reused a pass from the previous round")
            vm.passLocally(); wait()
            check(vm.localScoringVisible, "Two fresh passes after resumption did not restart scoring")
            vm.resumeLocalPlay(); wait()
            vm.placeStone(at: BoardPosition(4,7)); wait()
            check(model.player.currentIndex == 5, "Cannot play after resuming")
            vm.passLocally(); wait(); vm.passLocally(); wait()
            check(vm.localScoringVisible && vm.localScoring?.deadStones.isEmpty == true, "New scoring round inherited stale marks")
            model.selectGame(wrapper); wait()
            check(vm.localScoring == nil && vm.territoryPoints.isEmpty, "Loading another game retained scoring")
        }
        if !failures.isEmpty { failures.forEach { fputs("FAIL: \($0)\n", stderr) }; exit(1) }
        print("PASS: Real 2D/3D scoring flow, sidebar opening, group marking, both territory colors, neutral edits, totals, final winner text, frozen result, rewind/replay, resume, and new-game reset.")
    }
}
