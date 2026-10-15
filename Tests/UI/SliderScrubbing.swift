import SwiftUI
import Combine
import SceneKit
@testable import SGF_Player_Offline_Review

@main struct SliderScrubbingCheck {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.offline-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        let model = AppModel()
        let game = SGFGame.from(tree: try SGFParser.parse(text:
            "(;SZ[9]RU[Japanese]KM[6.5]AB[aa][ba]PL[W];W[ab];B[ii];W[bb];B[hi];W[ca])"))
        let wrapper = SGFGameWrapper(url: URL(fileURLWithPath: "/private/tmp/scrub-capture.sgf"), game: game)
        model.selectGame(wrapper)
        let vm = model.boardVM!
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        // AppKit tracks sliders in this mode, not the default mode used by Combine's
        // RunLoop scheduler. Keep this mode alive without returning to default mode.
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString))
        let keepAlive = Timer(timeInterval: 0.01, repeats: true) { _ in }
        RunLoop.main.add(keepAlive, forMode: .eventTracking)
        defer { keepAlive.invalidate() }
        func track(_ seconds: Double) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { RunLoop.main.run(mode: .eventTracking, before: end) }
        }
        model.player.seek(to: 5)
        track(0.2)
        guard model.player.blackStonesCaptured == 2,
              vm.currentMoveIndex == 5, vm.whiteCapturedCount == 2,
              vm.stonesToRender.count == model.player.board.stones.count else {
            fputs("FAIL: Tracking mode left board at \(vm.currentMoveIndex) while engine/lids reached \(model.player.currentIndex)\n", stderr)
            exit(1)
        }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 750),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Offline slider tracking check"
        defer { window.orderOut(nil) }
        func findScene(_ view: NSView) -> SCNView? {
            if let scene = view as? SCNView { return scene }
            return view.subviews.compactMap { findScene($0) }.first
        }
        var failures: [String] = []
        func check(_ ok: Bool, _ message: String) { if !ok { failures.append(message) } }
        for mode in [ViewMode.view2D, .view3D] {
            model.viewMode = mode
            model.selectGame(wrapper)
            let host = NSHostingView(rootView: ContentView().environmentObject(model))
            window.contentView = host; window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            var moves = 0
            let subscription = model.player.moveProcessed.sink { moves += 1 }
            var sounds = 0
            vm.onPlaySound = { _ in sounds += 1 }
            vm.beginScrubbing()
            for i in 0..<200 { vm.scrub(to: i % 6) }
            vm.scrub(to: 5)
            check(moves == 0, "Raw drag events performed unbounded seeks")
            track(0.08)
            check(moves == 1 && vm.currentMoveIndex == 5, "Latest drag target was not coalesced into one preview")
            check(vm.whiteCapturedCount == 2 && vm.stonesToRender.count == 5, "Board/lids disagree during tracking")
            if let scene = findScene(host)?.scene {
                var boardStones = 0
                scene.rootNode.enumerateChildNodes { node, _ in
                    if node.name == "board-stone" {
                        boardStones += 1
                        check(node.parent?.opacity == 1, "Scrub preview is hidden by a drop animation")
                    }
                }
                check(boardStones == 5, "3D board did not update during tracking")
                let lid = scene.rootNode.childNode(withName: "white-player-lid", recursively: true)!
                check(lid.childNodes.filter { $0.name == "captured-black" }.count == 2, "3D lid did not update during tracking")
            } else {
                check(mode == .view2D, "Missing 3D scene")
            }
            for _ in 0..<100 { vm.scrub(to: 5) }
            track(0.12)
            check(moves == 1, "Duplicate positions caused repeated work")
            let started = Date()
            var requests = 0
            while Date().timeIntervalSince(started) < 0.3 {
                vm.scrub(to: requests % 6); requests += 1
                track(0.001)
            }
            check(moves <= 8, "Preview rate exceeded its 20/s cap")
            vm.endScrubbing(at: 1)
            check(!vm.isScrubbing && vm.currentMoveIndex == 1 && model.player.currentIndex == 1,
                  "Release did not immediately apply the exact final position")
            check(vm.whiteCapturedCount == 0, "Final captures did not match released position")
            let releasedMoves = moves
            track(0.12)
            check(moves == releasedMoves, "Stale preview ran after release")
            check(sounds == 0, "Scrubbing generated playback sounds")
            vm.beginScrubbing(); vm.scrub(to: 5)
            model.selectGame(wrapper)
            track(0.12)
            check(vm.currentMoveIndex == 0 && !vm.isScrubbing, "Pending drag leaked into a new game")
            subscription.cancel()

        }
        if !failures.isEmpty { failures.forEach { fputs("FAIL: \($0)\n", stderr) }; exit(1) }
        print("PASS: Tracking-mode board/lid updates in 2D/3D, coalescing and rate cap, silent previews, exact release, and cancellation on game change.")
    }
}
