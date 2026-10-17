import XCTest
@testable import SGFPlayerNetworking

final class LobbySpeedTests: XCTestCase {
    private func challenge(_ fields: [String: Any]) throws -> OGSChallenge {
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(OGSChallenge.self, from: data)
    }

    func testRankRestrictionIncludesEndpointsAndExplainsIneligibleRows() throws {
        let game = try challenge(["min_rank": 20, "max_rank": 25])
        XCTAssertEqual(game.rankRestriction(for: 19), "Requires at least 10k")
        XCTAssertNil(game.rankRestriction(for: 20))
        XCTAssertNil(game.rankRestriction(for: 25))
        XCTAssertEqual(game.rankRestriction(for: 26), "Requires at most 5k")
        XCTAssertNil(game.rankRestriction(for: nil))
    }

    func testOGSSpeedBoundaries() throws {
        // OGS classifyGameSpeed: untimed or >1 hour = correspondence;
        // <10 seconds = blitz; 10 seconds through 1 hour = live.
        let cases: [(Int, String)] = [
            (0, "correspondence"), (1, "blitz"), (9, "blitz"),
            (10, "live"), (13, "live"), (29, "live"), (30, "live"),
            (3599, "live"), (3600, "live"), (3601, "correspondence"),
            (86400, "correspondence")
        ]
        for (seconds, expected) in cases {
            XCTAssertEqual(try challenge(["time_per_move": seconds]).speedCategory,
                           expected, "\(seconds) seconds per move")
        }
    }

    func testBothServerSpeedLocationsOverrideFallback() throws {
        for speed in ["live", "blitz", "correspondence"] {
            XCTAssertEqual(try challenge(["speed": speed, "time_per_move": 60]).speedCategory, speed)
            XCTAssertEqual(try challenge([
                "time_control_parameters": ["speed": speed], "time_per_move": 60
            ]).speedCategory, speed)
        }
        XCTAssertEqual(try challenge([
            "speed": "blitz", "time_control_parameters": ["speed": "live"]
        ]).speedCategory, "live", "Preserve the nested tag's existing priority")
    }

    func testUnknownSpeedTagsFallBackWithoutHidingGames() throws {
        XCTAssertEqual(try challenge([
            "time_control_parameters": ["speed": ""], "speed": "correspondence"
        ]).speedCategory, "correspondence")
        XCTAssertEqual(try challenge([
            "time_control_parameters": ["speed": "unknown"],
            "speed": "unknown", "time_per_move": 13
        ]).speedCategory, "live")
        XCTAssertEqual(try challenge([:]).speedCategory, "live")
    }

    func testCHJTimeControlRemainsLiveWithoutSpeedTag() throws {
        // Reconstructed from the reported 19x19, 6m + 2x10s challenge.
        // OGS's board-size-aware average rounds to 13 seconds per move.
        let game = try challenge([
            "id": 101, "username": "CHJ-8888", "width": 19, "height": 19,
            "ranked": true, "time_per_move": 13, "time_control": "byoyomi",
            "time_control_parameters": ["main_time": 360, "periods": 2, "period_time": 10]
        ])
        XCTAssertEqual(game.speedCategory, "live")
        XCTAssertEqual(game.formattedTimeControl, "6m + 2x10s")
    }
}
