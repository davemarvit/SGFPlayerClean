import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class ShojiEnvironmentTests: XCTestCase {
    func testCameraCanLeaveRoomWithoutLookingThroughNearWall() throws {
        let room = ShojiEnvironment()
        let scene = SCNScene(); scene.rootNode.addChildNode(room.node)
        let back = try XCTUnwrap(room.node.childNode(withName: "shoji-back", recursively: false))
        let left = try XCTUnwrap(room.node.childNode(withName: "shoji-left", recursively: false))
        let right = try XCTUnwrap(room.node.childNode(withName: "shoji-right", recursively: false))
        room.updateVisibility(cameraPosition: SCNVector3(0, 25, 20))
        XCTAssertTrue([back, left, right].allSatisfy { !$0.isHidden && $0.opacity == 1 })
        room.updateVisibility(cameraPosition: SCNVector3(0, 25, -40))
        XCTAssertTrue(back.isHidden)
        room.updateVisibility(cameraPosition: SCNVector3(-55, 25, 0))
        XCTAssertTrue(left.isHidden); XCTAssertFalse(back.isHidden)
        room.updateVisibility(cameraPosition: SCNVector3(55, 25, 0))
        XCTAssertTrue(right.isHidden); XCTAssertFalse(left.isHidden)
        room.updateVisibility(cameraPosition: SCNVector3(46, 25, 0))
        XCTAssertEqual(right.opacity, 0.5, accuracy: 0.001)
        room.updateVisibility(cameraPosition: SCNVector3(0, 25, 20))
        XCTAssertTrue([back, left, right].allSatisfy { !$0.isHidden && $0.opacity == 1 })
    }

    func testOrbitAndResizeReuseLightweightStationaryScenery() throws {
        let manager = SceneManager3D()
        let room = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "shoji-environment", recursively: true))
        let initial = room.simdWorldTransform
        var meshes: [SCNGeometry] = []
        room.enumerateChildNodes { node, _ in
            if let geometry = node.geometry { meshes.append(geometry) }
            XCTAssertNil(node.physicsBody)
            XCTAssertNil(node.light)
            if node.name?.hasPrefix("shoji-") == true { XCTAssertFalse(node.castsShadow) }
        }
        XCTAssertLessThanOrEqual(meshes.count, 6, "Lattice is batched rather than hundreds of draw nodes")
        XCTAssertLessThanOrEqual(meshes.reduce(0) { $0 + $1.materials.count }, 24,
            "Garden foliage shares material batches")
        XCTAssertNil(room.childNode(withName: "window-garden", recursively: false), "The garden uses a distant photographic view")
        XCTAssertNotNil(room.childNode(withName: "indoor-plant", recursively: false))
        let identities = meshes.map(ObjectIdentifier.init)
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            for angle in stride(from: Float(0), to: 6.3, by: 0.1) {
                manager.updateCameraPosition(distance: 70, rotationX: 0.1, rotationY: angle, panX: 0, panY: 0)
            }
            XCTAssertEqual(room.simdWorldTransform, initial)
            var after: [ObjectIdentifier] = []
            room.enumerateChildNodes { node, _ in
                if let geometry = node.geometry { after.append(ObjectIdentifier(geometry)) }
            }
            XCTAssertEqual(after, identities, "Camera and board-size changes must not regenerate room geometry")
            XCTAssertTrue(manager.scene.rootNode.childNode(withName: "shoji-environment", recursively: true) === room)
        }
    }
}
