import XCTest
import Combine
@testable import SGFPlayerNetworking

final class PlaybackTimingTests: XCTestCase {
    func testDelayChangesWhilePlayingAndStaysPausedWhenStopped() throws {
        let settings = AppSettings.shared
        let originalInterval = settings.moveInterval
        defer { settings.moveInterval = originalInterval }
        settings.moveInterval = 2
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text:
            "(;SZ[9];B[aa];W[ba];B[ca];W[da];B[ea];W[fa];B[ga];W[ha];B[ia])")))
        var playingStates: [Bool] = []
        let subscription = player.$isPlaying.sink { playingStates.append($0) }
        defer { player.pause(); subscription.cancel() }
        func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

        player.play()
        wait(0.3)
        XCTAssertEqual(player.currentIndex, 0, "Start must honor the saved delay")
        settings.moveInterval = 0.1
        wait(0.36)
        XCTAssertTrue((2...4).contains(player.currentIndex), "A running game must adopt the faster delay")
        XCTAssertEqual(playingStates, [false, true], "Speed changes must not trigger pause/auto-advance")

        settings.moveInterval = 2
        let slowedIndex = player.currentIndex
        wait(0.3)
        XCTAssertEqual(player.currentIndex, slowedIndex, "The earlier fast timer must be cancelled")
        player.pause()
        settings.moveInterval = 0.1
        wait(0.25)
        XCTAssertEqual(player.currentIndex, slowedIndex, "Moving the slider while paused must not start playback")
        player.play()
        player.play()
        wait(0.25)
        XCTAssertTrue((1...3).contains(player.currentIndex - slowedIndex), "Resume must use the new setting without duplicate timers")
        player.pause()
        let pausedIndex = player.currentIndex
        wait(0.25)
        XCTAssertEqual(player.currentIndex, pausedIndex)
    }

    func testPlaybackStopsAtEndWithConfiguredDelay() throws {
        let settings = AppSettings.shared
        let originalInterval = settings.moveInterval
        defer { settings.moveInterval = originalInterval }
        settings.moveInterval = 0.1
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9];B[aa])")))
        player.play()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertFalse(player.isPlaying)
    }
}
