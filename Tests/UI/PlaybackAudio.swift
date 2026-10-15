import SwiftUI
import AVFoundation
@testable import SGF_Player_Offline_Review

/// Run the actual playback -> BoardViewModel -> AppModel -> AVAudioPlayer path.
/// Volume is zero so this check does not interrupt the user; hardware audibility remains manual.
@main struct PlaybackAudioCheck {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.offline-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        let settings = AppSettings.shared
        settings.stoneVolume = 0
        settings.moveInterval = 0.1
        let model = AppModel()
        var failures: [String] = []
        func check(_ success: Bool, _ message: String) {
            if !success { failures.append(message) }
        }
        func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        // Inspect real audio players without adding test-only accessors to production code.
        func audio(_ name: String) -> AVAudioPlayer {
            let value = Mirror(reflecting: model).children.first { $0.label == name }!.value
            return (value as? AVAudioPlayer)!
        }
        let click = audio("clickPlayer")
        let single = audio("captureSinglePlayer")
        let multiple = audio("captureMultiPlayer")
        let fixtures = [
            ("single", "(;SZ[9]AB[ba][ab][bc]AW[bb][ca][db][cc];B[cb])", 1),
            ("multiple", "(;SZ[9]PL[W]AB[aa][ba]AW[ca][ab];W[bb])", 2)
        ]
        for mode in [ViewMode.view3D, .view2D] {
            model.viewMode = mode
            for (name, sgf, count) in fixtures {
                let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("audio-\(UUID()).sgf")
                try sgf.write(to: fixture, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(at: fixture) }
                model.selectGame(SGFGameWrapper(url: fixture, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
                wait(0.6)
                for player in [click, single, multiple] { player.stop(); player.currentTime = 0 }
                let expected = count == 1 ? single : multiple
                let unexpected = count == 1 ? multiple : single
                var heardClick = false
                var heardCapture = false
                var heardWrongCapture = false
                model.player.play()
                let deadline = Date().addingTimeInterval(1.4)
                while Date() < deadline {
                    wait(0.01)
                    heardClick = heardClick || (click.isPlaying && click.currentTime > 0)
                    heardCapture = heardCapture || (expected.isPlaying && expected.currentTime > 0)
                    heardWrongCapture = heardWrongCapture || unexpected.isPlaying
                }
                check(model.player.capturesByBlack + model.player.capturesByWhite == count, "\(mode) \(name): capture fixture failed")
                check(heardCapture, "\(mode) \(name): capture audio did not run")
                check(!heardWrongCapture, "\(mode) \(name): wrong capture clip ran")
                if mode == .view3D { check(heardClick, "3D \(name): placement click missing") }
                check(expected.volume == 0, "Stone Volume not applied")
                // Rewinding must not generate another capture sound.
                for player in [click, single, multiple] { player.stop(); player.currentTime = 0 }
                model.player.seek(to: 0)
                var rewindSound = false
                let rewindDeadline = Date().addingTimeInterval(0.6)
                while Date() < rewindDeadline {
                    wait(0.01)
                    rewindSound = rewindSound || single.isPlaying || multiple.isPlaying
                }
                check(!rewindSound, "\(mode) \(name): capture audio ran on rewind")
            }
        }
        if !failures.isEmpty {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
        print("PASS: Automatic playback runs single/multiple capture audio in 2D and 3D, retains 3D placement clicks, and stays silent on rewind.")
    }
}
