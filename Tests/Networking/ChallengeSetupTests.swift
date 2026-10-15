import XCTest
@testable import SGFPlayerNetworking

final class ChallengeSetupTests: XCTestCase {
    func testZeroMainTimeAllowedButNonpositivePeriodRejected() {
        var setup = ChallengeSetup()
        XCTAssertNil(setup.validationError)
        setup.mainTime = 0
        XCTAssertNil(setup.validationError)
        setup.periodTime = 0
        XCTAssertNotNil(setup.validationError)
        setup.periodTime = 30; setup.mainTime = -1
        XCTAssertNotNil(setup.validationError)
    }

    func testFischerAndSimpleConstraints() {
        var setup = ChallengeSetup(); setup.timeControl = "fischer"
        XCTAssertNil(setup.validationError)
        setup.maxTime = setup.initialTime - 1
        XCTAssertNotNil(setup.validationError)
        setup.maxTime = setup.initialTime; setup.increment = -1
        XCTAssertNotNil(setup.validationError)
        setup.increment = 0
        XCTAssertNil(setup.validationError)
        setup.timeControl = "simple"; setup.perMove = 0
        XCTAssertNotNil(setup.validationError)
        setup.perMove = 1
        XCTAssertNil(setup.validationError)
    }

    func testCorruptSavedRankRangeAndOtherUnsupportedValuesFailSafely() {
        var setup = ChallengeSetup(); setup.minRank = Int.max
        XCTAssertNotNil(setup.validationError)
        setup.minRank = 30; setup.maxRank = 20
        XCTAssertNotNil(setup.validationError)
        setup = ChallengeSetup(); setup.handicap = 1
        XCTAssertNotNil(setup.validationError)
        setup.handicap = -1
        XCTAssertNil(setup.validationError)
        setup.name = "  "
        XCTAssertNotNil(setup.validationError)
    }
}
