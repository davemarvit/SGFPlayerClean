import SwiftUI
@testable import SGF_Player_Offline_Review

/// Read an optional user's SGF without copying it into the repo or changing it.
@main struct StoneJitterCheck {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.offline-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        AppSettings.shared.jitterMultiplier = 1
        let external = ProcessInfo.processInfo.environment["SGF_JITTER_TEST_FILE"]
        let url = URL(fileURLWithPath: external ?? "/private/tmp/anonymous-jitter.sgf")
        let game: SGFGame
        if external != nil {
            game = SGFGame.from(tree: try SGFParser.parse(text: String(contentsOf: url, encoding: .utf8)))
        } else {
            var fixture = SGFGame()
            fixture.moves = (0..<100).map { ($0.isMultiple(of: 2) ? .black : .white, ($0 % 19, $0 / 19)) }
            game = fixture
        }
        precondition(game.moves.count >= 93)
        let model = AppModel()
        let wrapper = SGFGameWrapper(url: url, game: game)
        model.selectGame(wrapper)
        let vm = model.boardVM!
        func currentOffsets() -> [BoardPosition: CGPoint] {
            Dictionary(uniqueKeysWithValues: vm.stonesToRender.map { ($0.id, $0.offset) })
        }
        func frame(_ index: Int) -> [BoardPosition: CGPoint] {
            vm.seekToMove(index); vm.syncState()
            return currentOffsets()
        }
        // Scrubbing can reach 93 before it ever displays 92, then revisit both.
        let jumped93 = frame(93)
        let jumped92 = frame(92)
        vm.stepForward(); vm.syncState() // Ordinary Right Arrow after revisiting 92.
        let replay93 = currentOffsets()
        let position = model.player.lastMove!
        let moved = jumped92.keys.filter { jumped93[$0] != nil && jumped92[$0] != jumped93[$0] }
        let distant = moved.filter { max(abs($0.row - position.y), abs($0.col - position.x)) > 6 }
        print("Move 93 at (\(position.x),\(position.y)): \(moved.count) of \(jumped92.count) existing stones moved; \(distant.count) beyond local influence.")
        model.selectGame(wrapper)
        let started = Date()
        // This is exactly the VM method bound to Right Arrow, without slider seeks.
        for _ in 0..<92 { vm.stepForward(); vm.syncState() }
        let sequential92 = currentOffsets()
        vm.stepForward(); vm.syncState()
        let sequential93 = currentOffsets()
        let arrowMoved = sequential92.keys.filter { sequential93[$0] != nil && sequential92[$0] != sequential93[$0] }
        let arrowDistant = arrowMoved.filter { max(abs($0.row - position.y), abs($0.col - position.x)) > 6 }
        print("Fresh arrow-only 92–93: \(arrowMoved.count) existing stones moved; \(arrowDistant.count) distant.")
        // Left/Right Arrow after earlier navigation must restore the same exact layouts.
        vm.stepBackward(); vm.syncState()
        let arrowBack = currentOffsets()
        vm.stepForward(); vm.syncState()
        let arrowForward = currentOffsets()
        guard jumped92 == sequential92, jumped93 == sequential93, replay93 == sequential93, distant.isEmpty, arrowDistant.isEmpty, arrowBack == sequential92, arrowForward == sequential93 else {
            fputs("FAIL: Skipped/rewound frames changed jiggle layout or moved distant stones\n", stderr)
            exit(1)
        }
        print("PASS: Exact game 92–93 offsets agree across sequential play, skipped previews and rewind; distant stones stay fixed. Sequential 93-frame check: \(Date().timeIntervalSince(started)) seconds.")
    }
}
