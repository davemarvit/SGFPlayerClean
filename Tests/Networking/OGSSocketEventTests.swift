import XCTest
@testable import SGFPlayerNetworking

final class OGSSocketEventTests: XCTestCase {
    func testLobbyBatchRetainsArrayPayload() throws {
        let event = try XCTUnwrap(OGSSocketEvent(json: #"["seek_graph", [{"id": 1}, {"id": 2}]]"#))
        XCTAssertEqual(event.name, "seek_graph")
        XCTAssertEqual((event.payload as? [[String: Int]])?.map { $0["id"]! }, [1, 2])
        let decoded = try JSONDecoder().decode([[String: Int]].self, from: XCTUnwrap(event.containerData))
        XCTAssertEqual(decoded, [["id": 1], ["id": 2]])
        XCTAssertTrue(event.object.isEmpty)
    }

    func testIncrementalAndGamePayloadsRemainObjects() throws {
        for name in ["seekgraph/global", "game/123/move"] {
            let event = try XCTUnwrap(OGSSocketEvent(json: "[\"\(name)\", {\"id\": 123}]"))
            XCTAssertEqual(event.object["id"] as? Int, 123)
            XCTAssertNotNil(event.containerData)
        }
    }

    func testMissingLobbyPayloadIsSafe() throws {
        let event = try XCTUnwrap(OGSSocketEvent(json: #"["seekgraph/global"]"#))
        XCTAssertNil(event.payload)
        XCTAssertNil(event.containerData)
        XCTAssertTrue(event.object.isEmpty)
    }

    func testScalarPayloadIsNotSerializedAsContainer() throws {
        for value in ["null", "true", "3", #""message""#] {
            let event = try XCTUnwrap(OGSSocketEvent(json: "[\"seek_graph\", \(value)]"))
            XCTAssertNil(event.containerData)
            XCTAssertTrue(event.object.isEmpty)
        }
    }

    func testMalformedEnvelopeIsIgnored() {
        for json in ["", "[", "[]", "{}", "null", "[42, {}]", #"["", {}]"#] {
            XCTAssertNil(OGSSocketEvent(json: json), json)
        }
    }
}
