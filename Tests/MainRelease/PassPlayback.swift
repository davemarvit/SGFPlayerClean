import SwiftUI
import AVFoundation
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private struct PassHost: View {
    @ObservedObject var app: AppModel
    var body: some View {
        if let vm = app.boardVM {
            BoardWorkspaceView(vm: vm) {
                if app.viewMode == .view2D { ContentView2D() } else { ContentView3D() }
            }.environmentObject(app)
        }
    }
}
@main struct PassPlaybackCheck {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.isMuted = true
        let app = AppModel(); app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let sgf = "(;SZ[9]RE[B+3.5];B[dd];W[];B[])"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pass-\(UUID()).sgf")
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: sgf))))
        let vm = app.boardVM!
        var passSounds = 0
        vm.onPassSound = { passSounds += 1 }
        func settle(_ seconds: Double = 0.05) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        await settle()
        require(vm.reviewEndResult == "Black +3.5", "Opening the final position shows recorded score")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: PassHost(app: app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        await settle(0.3)
        for mode in [ViewMode.view2D, .view3D] {
            app.viewMode = mode; vm.seekToMove(1); await settle(0.25)
            require(vm.reviewEndResult == nil && vm.passAnnouncement == nil, "No result spoilers before end")
            let before = passSounds
            app.player.stepForward(); await settle(0.25)
            require(vm.passAnnouncement?.text == "White passes" && passSounds == before + 1, "Forward pass shows and speaks once")
            let id = vm.passAnnouncement!.id
            vm.syncState(); vm.syncState()
            require(vm.passAnnouncement?.id == id && passSounds == before + 1, "Repeated sync does not restart visual or sound")
            app.player.stepForward(); await settle(0.25)
            require(vm.passAnnouncement?.text == "Black passes" && passSounds == before + 2, "Consecutive pass replaces prior announcement")
            require(vm.reviewEndResult == "Black +3.5", "Result appears at main-line end")
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let name = mode == .view2D ? "2d" : "3d"
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-pass-result-\(name).png"))
            app.player.stepBackward(); await settle()
            require(passSounds == before + 2 && vm.reviewEndResult == nil, "Rewind clears result and stays silent")
            vm.beginScrubbing(); vm.scrub(to: 3); vm.endScrubbing(at: 3); await settle()
            require(passSounds == before + 2 && vm.passAnnouncement == nil, "Scrub does not speak or animate passes")
        }
        vm.seekToMove(1); await settle()
        vm.addReviewMove(at: BoardPosition(2, 2)); await settle()
        require(vm.reviewEndResult == nil, "Variation cannot inherit original result")
        app.mode = .localPlay; vm.resetToEmpty(); await settle()
        vm.passLocally(); await settle()
        require(vm.passAnnouncement?.text == "Black passes", "Local player's pass announced")
        vm.passLocally(); await settle()
        require(vm.passAnnouncement?.text == "White passes" && vm.localScoringVisible, "Second local pass announces while opening scoring")
        // Run the real bundled voice clip silently and check mute/volume behavior.
        let manager = SoundManager.shared
        let players = Mirror(reflecting: manager).children.first { $0.label == "players" }!.value as! [String: AVAudioPlayer]
        let pass = players["pass"]!
        AppSettings.shared.isMuted = false; AppSettings.shared.masterVolume = 0.8; AppSettings.shared.voiceVolume = 0
        manager.play("pass"); await settle(0.03)
        require(pass.isPlaying && pass.volume == 0, "Existing spoken Pass clip plays and honors voice volume")
        AppSettings.shared.isMuted = true; manager.applyAudioSettings(); manager.play("pass")
        require(!pass.isPlaying, "Mute suppresses pass voice")
        print("PASS: 2D/3D pass overlays and results, repeat suppression, rewind/scrub, variations, local scoring, real pass audio and mute")
    }
}
