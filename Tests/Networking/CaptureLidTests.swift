import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class CaptureLidTests: XCTestCase {
    func testLidsContainCorrectColorsAndCountsAfterResizeUndoAndReset() throws {
        let scene = SceneManager3D()
        func count(_ color: String, in lid: String) throws -> Int {
            let node = try XCTUnwrap(scene.scene.rootNode.childNode(withName: lid, recursively: true))
            return node.childNodes.filter { $0.name == "captured-\(color)" }.count
        }
        scene.updateCapturedStones(black: 40, white: 3)
        XCTAssertEqual(try count("white", in: "black-player-lid"), 40)
        XCTAssertEqual(try count("black", in: "white-player-lid"), 3)
        let label = scene.scene.rootNode.childNode(withName: "black-player-lid", recursively: true)?
            .childNode(withName: "capture-count", recursively: false)?.geometry as? SCNText
        XCTAssertEqual(label?.string as? String, "40")
        // Previously, rebuilding detached all nodes but retained counts, leaving empty lids.
        scene.updateBoardSize(9)
        scene.updateCapturedStones(black: 40, white: 3)
        XCTAssertEqual(try count("white", in: "black-player-lid"), 40)
        XCTAssertEqual(try count("black", in: "white-player-lid"), 3)
        let captured = scene.scene.rootNode.childNode(withName: "black-player-lid", recursively: true)!
            .childNodes.filter { $0.name == "captured-white" }
        for stone in captured {
            let sphere = try XCTUnwrap(stone.geometry as? SCNSphere)
            // White stones retain their existing 98% optical size adjustment.
            XCTAssertEqual(sphere.radius * CGFloat(stone.scale.x), 0.48 * 0.98, accuracy: 0.001)
            XCTAssertLessThan(hypot(Double(stone.position.x), Double(stone.position.z)), 2.5)
        }
        for i in captured.indices {
            for j in captured.indices where j > i && captured[i].position.y == captured[j].position.y {
                let dx = Double(captured[i].position.x - captured[j].position.x)
                let dz = Double(captured[i].position.z - captured[j].position.z)
                XCTAssertGreaterThanOrEqual(hypot(dx, dz), 0.96)
            }
        }
        scene.updateCapturedStones(black: 1, white: 0)
        XCTAssertEqual(try count("white", in: "black-player-lid"), 1)
        XCTAssertEqual(try count("black", in: "white-player-lid"), 0)
        scene.createLids()
        XCTAssertEqual(try count("white", in: "black-player-lid"), 1)
        scene.updateCapturedStones(black: -1, white: -1)
        XCTAssertEqual(try count("white", in: "black-player-lid"), 0)
        XCTAssertEqual(try count("black", in: "white-player-lid"), 0)
    }
}
