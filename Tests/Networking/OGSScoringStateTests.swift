import XCTest
@testable import SGFPlayerNetworking

final class OGSScoringStateTests: XCTestCase {
    func testCoordinateRoundTripAndCanonicalOrder() {
        let points: Set<BoardPosition> = [BoardPosition(1, 1), BoardPosition(0, 0), BoardPosition(26, 27)]
        let encoded = OGSScoring.encodePositions(points)
        XCTAssertEqual(encoded, "aabbBA")
        XCTAssertEqual(OGSScoring.decodePositions(encoded), points)
        XCTAssertEqual(OGSScoring.decodePositions(""), [])
    }

    func testMalformedOrOffBoardPositionsRejectWholePayload() {
        for text in ["a", "aabb?c", "tt"] {
            XCTAssertNil(OGSScoring.decodePositions(text, width: 19, height: 19))
        }
    }

    func testServerTotalsArePreservedIncludingRuleAdjustments() throws {
        let score = try XCTUnwrap(OGSScoreSummary.parse([
            "black": ["total": 40, "territory": 20, "stones": 20, "prisoners": 9],
            "white": ["total": "42.5", "territory": 18, "stones": 18, "komi": 6.5]
        ]))
        XCTAssertEqual(score.black.total, 40, "Prisoners must not be added again under area scoring")
        XCTAssertEqual(score.white.total, 42.5)
        XCTAssertNil(score.white.prisoners, "Missing components must not become invented zeros")
    }

    func testInvalidOrMissingTotalsDoNotCreateScoreboard() {
        for total in ["NaN", "Infinity", "not a score", true] as [Any] {
            XCTAssertNil(OGSScoreSummary.parse(["black": ["total": total], "white": ["total": 4]]))
        }
        XCTAssertNil(OGSScoreSummary.parse(["black": ["territory": 4], "white": ["total": 4]]))
    }

    func testAuthoritativePositionsIncludingEmptyOverlay() throws {
        let score = try XCTUnwrap(OGSScoreSummary.parse([
            "black": ["total": 1, "scoring_positions": "aa"],
            "white": ["total": 0, "scoring_positions": ""]
        ]))
        XCTAssertEqual(score.positions(width: 9, height: 9), [BoardPosition(0, 0): .black])
        let empty = try XCTUnwrap(OGSScoreSummary.parse([
            "black": ["total": 0, "scoring_positions": ""],
            "white": ["total": 6.5, "scoring_positions": ""]
        ]))
        XCTAssertEqual(empty.positions(width: 9, height: 9), [:])
    }

    func testConflictingOrUnavailablePositionsDoNotBecomeAuthoritative() throws {
        for white in [["total": 1], ["total": 1, "scoring_positions": "aa"], ["total": 1, "scoring_positions": "ZZ"]] as [[String: Any]] {
            let score = try XCTUnwrap(OGSScoreSummary.parse([
                "black": ["total": 1, "scoring_positions": "aa"], "white": white
            ]))
            XCTAssertNil(score.positions(width: 9, height: 9))
        }
    }
}
