import SwiftUI
import Vision
@testable import SGF_Player_Offline_Review

@main struct LocalPassCheck {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.offline-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        AppSettings.shared.moveInterval = 10
        let model = AppModel()
        model.showRightPanel = false
        let sgf = "(;SZ[9]RU[Japanese]AB[ba][ab][bc]AW[bb][ca][db][cc];B[cb])"
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("local-pass-\(UUID()).sgf")
        try sgf.write(to: fixture, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let wrapper = SGFGameWrapper(url: fixture, game: SGFGame.from(tree: try SGFParser.parse(text: sgf)))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 750),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Offline Pass check"
        defer { window.orderOut(nil) }
        var failures: [String] = []
        func check(_ ok: Bool, _ message: String) { if !ok { failures.append(message) } }
        func wait(_ seconds: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func visibleText(_ host: NSView, _ name: String) throws -> String {
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-pass-\(name).png"))
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        }
        for mode in [ViewMode.view2D, .view3D] {
            model.viewMode = mode
            model.selectGame(wrapper)
            let vm = model.boardVM!
            let host = NSHostingView(rootView: Group {
                if mode == .view2D { ContentView2D() } else { ContentView3D() }
            }.environmentObject(model))
            window.contentView = host; window.orderFront(nil); wait(0.5)
            check(vm.localPassUnavailableReason != nil, "Pass must be blocked while reviewing history")
            vm.passLocally(); wait()
            check(model.player.maxIndex == 1 && model.player.currentIndex == 0, "Pass changed recorded history")
            vm.goToEnd(); wait()
            check(vm.localPassUnavailableReason == nil, "Pass must be available at the end")
            check(try visibleText(host, "\(mode)-ready").split(separator: " ").contains("pass"), "Pass button not visible in \(mode)")
            vm.startAutoPlay(); wait()
            vm.passLocally()
            check(model.player.maxIndex == 1, "Pass must be blocked during playback")
            vm.stopAutoPlay(); wait()
            let board = model.player.board
            let captures = model.player.capturesByBlack
            var clicks = 0
            vm.onPlaySound = { _ in clicks += 1 }
            vm.passLocally(); wait()
            check(model.player.turn == .black && model.player.currentIndex == 2, "White pass failed")
            check(model.player.board == board && model.player.capturesByBlack == captures, "Pass changed stones or captures")
            check(vm.koPoint == nil, "Pass did not clear the simple-ko marker")
            check(vm.localPassStatus == "White passed · Black to move", "Wrong first-pass status")
            check(clicks == 0, "Pass should not play a stone placement/capture sound")
            vm.passLocally(); wait()
            check(model.player.turn == .white && model.player.lastTwoMovesWerePasses, "Second pass failed")
            check(try visibleText(host, "\(mode)-two-passes").contains("both players passed"), "Two-pass status not visible in \(mode)")
            vm.stepBackward(); wait()
            check(!model.player.lastTwoMovesWerePasses && vm.localPassStatus == "White passed · Black to move", "Rewind left stale pass status")
            vm.stepBackward(); wait()
            check(vm.localPassStatus == nil && vm.koPoint != nil, "Rewind did not restore pre-pass ko")
            vm.goToEnd(); wait()
            check(model.player.lastTwoMovesWerePasses && model.player.board == board, "Pass replay changed board")
            vm.isOnlineContext = true
            vm.passLocally()
            check(model.player.maxIndex == 3, "Local Pass must not alter an online game")
            vm.isOnlineContext = false
        }
        if !failures.isEmpty {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
        print("PASS: Local passes in 2D/3D preserve stones/captures, change turns, clear ko, rewind/replay, show status, avoid stone sounds, and reject history/playback/online input.")
    }
}
