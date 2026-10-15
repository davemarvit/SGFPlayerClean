import XCTest
@testable import SGFPlayerNetworking

final class OGSObservedGameTests: XCTestCase {
    private func game(_ json: String) throws -> OGSObservedGame {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        return try XCTUnwrap(OGSObservedGame(json: object))
    }

    func testSnapshotIncludesPassesRanksAndByoyomi() throws {
        let row = try game(#"{"id":1,"black":{"username":"Alice","ranking":29},"white":{"username":"Bob","ranking":32.5},"width":19,"height":19,"json":{"moves":[[0,0],[-1,-1],[2,2]],"time_control":{"system":"byoyomi","main_time":1200,"periods":5,"period_time":30}}}"#)
        XCTAssertEqual(row.blackRank, "1k")
        XCTAssertEqual(row.whiteRank, "3d")
        XCTAssertEqual(row.strongestRank, 32.5)
        XCTAssertEqual(row.moveCount, 3)
        XCTAssertEqual(row.timeControl, "20m + 5×30s")
    }

    func testSortUsesStrongerPlayerNotAverageAndKeepsTiesStable() throws {
        let rows = try [
            #"{"id":1,"black":{"ranking":33},"white":{"ranking":33}}"#,
            #"{"id":2,"black":{"ranking":10},"white":{"ranking":35}}"#,
            #"{"id":3}"#,
            #"{"id":4,"black":{"ranking":35}}"#
        ].map(game)
        XCTAssertEqual(OGSObservedGame.strongestFirst(rows).map(\.id), [2, 4, 1, 3])
    }

    func testOverallRatingsProfessionalsAndMissingMetadata() throws {
        let snapshot = try game(#"{"id":4,"black":{"username":"Alice"},"json":{"players":{"black":{"ranking":34}}}}"#)
        XCTAssertEqual(snapshot.blackName, "Alice")
        XCTAssertEqual(snapshot.blackRank, "5d")
        let rated = try game(#"{"id":1,"black":{"ranking":0,"ratings":{"overall":{"rating":2000,"deviation":70}}},"white":{"ratings":{"overall":{"rating":1800,"deviation":200}}}}"#)
        XCTAssertEqual(rated.blackRank, "1d")
        XCTAssertEqual(rated.whiteRank, "?")
        XCTAssertGreaterThan(try XCTUnwrap(rated.strongestRank), 30)
        let pro = try game(#"{"id":2,"black":{"ranking":1039,"professional":true}}"#)
        XCTAssertEqual(pro.blackRank, "3p")
        XCTAssertEqual(OGSObservedGame.strongestFirst([rated, pro]).first?.id, 2)
        let unknown = try game(#"{"id":3}"#)
        XCTAssertNil(unknown.strongestRank)
        XCTAssertNil(unknown.moveCount)
        XCTAssertNil(unknown.timeControl)
        XCTAssertEqual(unknown.blackRank, "?")
    }

    func testTimeControlSystemsAndIncompleteData() throws {
        let cases: [(String, String?)] = [
            (#"{"system":"fischer","initial_time":300,"time_increment":10}"#, "5m + 10s/move"),
            (#"{"system":"canadian","main_time":600,"period_time":300,"stones_per_period":25}"#, "10m + 5m/25 stones"),
            (#"{"system":"absolute","total_time":900}"#, "15m total"),
            (#"{"system":"simple","per_move":30}"#, "30s/move"),
            (#"{"system":"none"}"#, "No time limit"),
            (#"{"system":"byoyomi"}"#, "Byo-yomi"),
            (#"{"system":"unknown"}"#, nil)
        ]
        for (params, expected) in cases {
            XCTAssertEqual(try game("{\"id\":1,\"json\":{\"time_control\":\(params)}}").timeControl, expected)
        }
    }
}
