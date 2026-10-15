import SwiftUI
import Vision
@testable import SGF_Player_Offline_Review

/// Optional external file is read only. By default use an anonymous nested 132-move game.
@main struct SGFPlaybackCheck {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.offline-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        let environment = ProcessInfo.processInfo.environment
        let externalFile = environment["SGF_PLAYBACK_TEST_FILE"]
        let expected = Int(environment["SGF_PLAYBACK_EXPECTED_MOVES"] ?? "132")!
        let url = URL(fileURLWithPath: externalFile ?? "/private/tmp/anonymous-nested-playback.sgf")
        let text: String
        if externalFile != nil {
            text = try String(contentsOf: url, encoding: .utf8)
        } else {
            let moves = (0..<132).map { i in
                ";\(i.isMultiple(of: 2) ? "B" : "W")[\(String(UnicodeScalar(97 + i % 19)!))\(String(UnicodeScalar(97 + i / 19)!))]"
            }
            text = "(;SZ[19]RU[AGA]KM[7.5]" + moves.joined(separator: "(") + String(repeating: ")", count: 132)
        }
        let wrapper = SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: text)))
        let model = AppModel()
        model.showRightPanel = false
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 850),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Offline SGF playback check"
        defer { window.orderOut(nil) }
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        func wait() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
        func visibleText(_ host: NSView) throws -> String {
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-playback-\(model.viewMode)-\(model.player.currentIndex).png"))
            // OCR only the controls, so tiny numeric text is not overwhelmed by the board.
            let image = bitmap.cgImage!
            let footer = image.cropping(to: CGRect(x: 0, y: image.height - image.height / 8,
                                                   width: image.width, height: image.height / 8))!
            let enlarged = CGContext(data: nil, width: footer.width * 3, height: footer.height * 3,
                                     bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            enlarged.interpolationQuality = .high
            enlarged.draw(footer, in: CGRect(x: 0, y: 0, width: footer.width * 3, height: footer.height * 3))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: enlarged.makeImage()!).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined().filter { !$0.isWhitespace }.lowercased()
        }
        for mode in [ViewMode.view2D, .view3D] {
            model.viewMode = mode
            model.selectGame(wrapper)
            let vm = model.boardVM!
            let host = NSHostingView(rootView: ContentView().environmentObject(model))
            window.contentView = host; window.orderFront(nil); wait()
            check(vm.totalMoves == expected, "\(mode): incorrect playback length")
            check(model.selection?.game.sourceTree != nil, "Imported variation tree lost in app selection")
            vm.stepForward(); wait()
            check(vm.currentMoveIndex == 1, "First move did not advance")
            vm.stepForward(); wait()
            check(vm.currentMoveIndex == 2, "Playback still stops after one move")
            vm.goToEnd(); wait()
            check(vm.currentMoveIndex == expected, "End control cannot reach final move")
            let endText = try visibleText(host)
            check(endText.contains("\(expected)/\(expected)"), "\(mode): final counter missing: \(endText)")
            let endBoard = model.player.board
            vm.seekToMove(expected / 2); wait()
            check(vm.currentMoveIndex == expected / 2, "Seeking failed")
            vm.goToStart(); wait()
            check(vm.currentMoveIndex == 0 && vm.totalMoves == expected, "Rewind lost remaining history")
            for _ in 0..<expected { vm.stepForward() }
            wait()
            check(model.player.board == endBoard, "Sequential replay differs from seek-to-end")
        }
        if !failures.isEmpty { failures.forEach { fputs("FAIL: \($0)\n", stderr) }; exit(1) }
        print("PASS: Full \(expected)-move SGF in 2D/3D; visible counters, forward steps, end, seek, rewind/replay, and retained source tree.")
    }
}
