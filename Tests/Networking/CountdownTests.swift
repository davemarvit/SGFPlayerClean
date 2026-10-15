import XCTest
@testable import SGFPlayerNetworking

final class CountdownTests: XCTestCase {
    func testCountdownUsesRemainingSecondRatherThanDiscardingFraction() {
        for second in 1...10 {
            let boundary = Double(second)
            XCTAssertEqual(SoundManager.countdownSecond(remaining: boundary), second)
            XCTAssertEqual(SoundManager.countdownSecond(remaining: boundary - 0.1), second)
            XCTAssertEqual(SoundManager.countdownSecond(remaining: boundary + 0.1), second == 10 ? nil : second + 1)
        }
        XCTAssertEqual(SoundManager.countdownSecond(remaining: 3.9), 4)
        XCTAssertEqual(SoundManager.countdownSecond(remaining: 1.9), 2)
        XCTAssertEqual(SoundManager.countdownSecond(remaining: 0.01), 1)
    }

    func testNoAnnouncementAfterExpiryOrForInvalidTime() {
        for time: Double in [0, -1, 10.01, 60, .nan, .infinity, -.infinity] {
            XCTAssertNil(SoundManager.countdownSecond(remaining: time))
        }
    }
}
