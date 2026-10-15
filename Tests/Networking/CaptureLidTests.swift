import XCTest
import SceneKit
import simd
@testable import SGFPlayerNetworking

final class CaptureLidTests: XCTestCase {
    func testPhysicsKeepsLargeCapturePileInsideLidsAcrossSizesAndCameraTilt() throws {
        let manager = SceneManager3D()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene
        renderer.pointOfView = manager.cameraNode
        var time = 0.0
        for size in [19, 9, 13] {
            manager.updateBoardSize(size)
            manager.updateCameraPosition(distance: 30, rotationX: size == 9 ? 0.35 : 0.85,
                                        rotationY: 0.4, panX: 0, panY: 0)
            manager.updateCapturedStones(black: 80, white: 3)
            SCNTransaction.flush()
            for _ in 0..<180 {
                _ = renderer.snapshot(atTime: time, with: CGSize(width: 96, height: 96), antialiasingMode: .none)
                time += 1.0 / 60.0
            }
            let lid = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "black-player-lid", recursively: true))
            let stones = lid.childNodes.filter { $0.name == "captured-white" }
            XCTAssertEqual(stones.count, 80)
            for stone in stones {
                let position = stone.presentation.position
                XCTAssertTrue(position.x.isFinite && position.y.isFinite && position.z.isFinite)
                XCTAssertLessThan(hypot(Double(position.x), Double(position.z)), 3.5, "Escaped lid on \(size)x\(size)")
                XCTAssertGreaterThan(position.y, -0.1, "Fell through floor")
                XCTAssertLessThan(position.y, 4.5, "Pile did not settle")
                XCTAssertEqual(stone.scale.x, 1)
                XCTAssertEqual(stone.scale.y, 1)
            }
        }
        // Moving the parent of an already simulated pile must preserve its local position.
        manager.updateCameraPosition(distance: 25, rotationX: 1.1, rotationY: -0.6, panX: 2, panY: -1)
        manager.updateCapturedStones(black: 100, white: 4)
        for _ in 0..<180 {
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 96, height: 96), antialiasingMode: .none)
            time += 1.0 / 60.0
        }
        let movedLid = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "black-player-lid", recursively: true))
        for stone in movedLid.childNodes where stone.name == "captured-white" {
            let position = stone.presentation.position
            XCTAssertLessThan(hypot(Double(position.x), Double(position.z)), 3.5)
            XCTAssertGreaterThan(position.y, -0.1)
        }
        manager.updateCapturedStones(black: 1, white: 0)
        let lid = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "black-player-lid", recursively: true))
        XCTAssertEqual(lid.childNodes.filter { $0.name == "captured-white" }.count, 1)
    }

    func testCameraTransformPreservesOriginalViewWithoutMovingPhysicsWorld() {
        let manager = SceneManager3D()
        for (x, y, pan, distance): (CGFloat, CGFloat, CGFloat, CGFloat) in [(0.75,0,0,25), (1.1,-0.6,2,30), (0.3,0.8,-3,20)] {
            let oldWorld = SCNNode()
            oldWorld.position = SCNVector3(pan, 0, -pan)
            oldWorld.eulerAngles = SCNVector3(x, y, 0)
            let oldCamera = SCNNode()
            oldCamera.position = SCNVector3(0, 15 * distance / 25, 20 * distance / 25)
            oldCamera.look(at: SCNVector3Zero)
            let expected = simd_inverse(oldCamera.simdTransform) * oldWorld.simdTransform
            manager.updateCameraPosition(distance: distance, rotationX: Float(x), rotationY: Float(y), panX: pan, panY: -pan)
            let actual = simd_inverse(manager.cameraNode.simdWorldTransform)
            for column in 0..<4 {
                for row in 0..<4 { XCTAssertEqual(actual[column][row], expected[column][row], accuracy: 0.0001) }
            }
            XCTAssertEqual(manager.scene.physicsWorld.gravity.x, 0)
            XCTAssertEqual(manager.scene.physicsWorld.gravity.z, 0)
        }
    }

    func testKoMarkerCanBeShownAndCleared() {
        let manager = SceneManager3D()
        manager.updateKoMarker(at: BoardPosition(1, 2))
        let marker = manager.scene.rootNode.childNode(withName: "ko-marker", recursively: true)
        XCTAssertEqual((marker?.geometry as? SCNText)?.string as? String, "Ko")
        manager.updateKoMarker(at: nil)
        XCTAssertNil(manager.scene.rootNode.childNode(withName: "ko-marker", recursively: true))
    }

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
            let visual = try XCTUnwrap(stone.childNode(withName: "capture-visual", recursively: false))
            let sphere = try XCTUnwrap(visual.geometry as? SCNSphere)
            // White stones retain their existing 98% optical size adjustment.
            XCTAssertEqual(sphere.radius * CGFloat(visual.scale.x), 0.48 * 0.98, accuracy: 0.001)
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
