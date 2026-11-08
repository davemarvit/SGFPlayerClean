import XCTest
@testable import SGFPlayerNetworking

final class PassPresentationTests: XCTestCase {
    func testRecordedResults() {
        for (raw, expected) in [
            ("B+3.5", "Black +3.5"), ("W+0.5", "White +0.5"),
            (" B+3.6\n", "Black +3.6"), ("W+R", "White wins by resignation"),
            ("B+Resign", "Black wins by resignation"), ("W+Time", "White wins on time"),
            ("B+F", "Black wins by forfeit"), ("0", "Draw"), ("Jigo", "Draw"),
            ("Void", "Void game"), ("?", "Result not recorded"), ("", "Result not recorded"),
            ("W+", "White wins"), ("B+nan", "Recorded result: B+nan")
        ] {
            var info = SGFGame.Info(); info.result = raw
            XCTAssertEqual(info.resultDescription, expected)
        }
        XCTAssertEqual(SGFGame.Info().resultDescription, "Result not recorded")
    }
    func testPassFadeAndReplacementIdentity() {
        let pass = PassAnnouncement(color: .white, startedAt: 10)
        XCTAssertEqual(pass.text, "White passes")
        XCTAssertEqual(pass.opacity(at: 10), 0)
        XCTAssertEqual(pass.opacity(at: 10.075), 0.5, accuracy: 0.001)
        XCTAssertEqual(pass.opacity(at: 10.4), 1)
        XCTAssertEqual(pass.opacity(at: 11.4), 0.5, accuracy: 0.001)
        XCTAssertEqual(pass.opacity(at: 12), 0)
        XCTAssertEqual(pass.opacity(at: 9), 0)
        let next = PassAnnouncement(color: .black, startedAt: 11)
        XCTAssertEqual(next.text, "Black passes")
        XCTAssertNotEqual(next.id, pass.id)
    }
    func testAutomaticPlaybackHoldsPassButManualStepsRemainImmediate() {
        let old = AppSettings.shared.moveInterval
        defer { AppSettings.shared.moveInterval = old }
        AppSettings.shared.moveInterval = 0.1
        var game = SGFGame(); game.moves = [(.black, nil), (.white, (1, 1))]
        let player = SGFPlayer(); player.load(game: game); player.play()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertEqual(player.currentIndex, 1)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        XCTAssertEqual(player.currentIndex, 1, "Pass must remain readable even at maximum speed")
        RunLoop.main.run(until: Date().addingTimeInterval(1.15))
        XCTAssertEqual(player.currentIndex, 2)
        player.pause(); player.seek(to: 0); player.stepForward(); player.stepForward()
        XCTAssertEqual(player.currentIndex, 2)
    }
}
