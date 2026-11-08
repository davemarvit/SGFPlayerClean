import XCTest
import SceneKit
import simd
@testable import SGFPlayerNetworking

final class CaptureLidTests: XCTestCase {
    func testSettledCapturePileSleepsAndNewCapturesResumeSimulation() throws {
        let manager = SceneManager3D()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        renderer.isPlaying = true
        var time = 0.0
        func stones() -> [SCNNode] {
            var result: [SCNNode] = []
            manager.scene.rootNode.enumerateChildNodes { node, _ in
                if node.name == "captured-white" || node.name == "captured-black" { result.append(node) }
            }
            return result
        }
        func settle() {
            SCNTransaction.flush()
            for frame in 0..<1200 {
                _ = renderer.snapshot(atTime: time, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
                time += 1.0 / 60
                RunLoop.main.run(until: Date().addingTimeInterval(0.0001))
                if frame > 90 && stones().allSatisfy({ $0.physicsBody!.isResting }) { return }
            }
            XCTFail("A settled capture pile should stop collision work")
        }
        manager.updateCapturedStones(black: 80, white: 3, seed: 123)
        settle()
        let poses = stones().map { $0.presentation.simdTransform }
        manager.updateCameraPosition(distance: 30, rotationX: 0.6, rotationY: 0.8, panX: 2, panY: 1)
        XCTAssertTrue(stones().allSatisfy { $0.physicsBody!.isResting }, "Camera movement must not wake capture physics")
        XCTAssertEqual(stones().map { $0.presentation.simdTransform }, poses)
        manager.updateCapturedStones(black: 82, white: 3, seed: 123)
        XCTAssertTrue(stones().contains { !$0.physicsBody!.isResting }, "New captures still fall and settle")
        settle()
        manager.updateCapturedStones(black: 40, white: 3, seed: 123)
        settle()
        XCTAssertEqual(stones().count, 43)
    }

    func testRewindAfterAddedHandicapGameMovesRemovesCapturedBlackStones() throws {
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text:
            "(;SZ[9]RU[Chinese-OGS]KM[0.5]HA[2]PL[W]AB[cg][gc];W[cc];B[gg];W[ee])")))
        player.seek(to: player.maxIndex)
        for (x, y) in [(0,0), (2,0), (1,0), (0,1), (-1,-1), (1,1)] {
            XCTAssertNil(player.tryPlayMove(color: player.turn, x: x, y: y))
        }
        let end = player.maxIndex
        XCTAssertEqual(player.capturesByWhite, 2)
        let scene = SceneManager3D(); scene.updateBoardSize(9)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene.scene; renderer.pointOfView = scene.cameraNode
        var time = 0.0
        for (index, expected) in [(end, 2), (end - 1, 0), (end, 2), (0, 0), (end, 2), (0, 0)] {
            player.seek(to: index)
            scene.updateCapturedStones(black: player.capturesByBlack, white: player.capturesByWhite)
            SCNTransaction.flush()
            for _ in 0..<10 {
                _ = renderer.snapshot(atTime: time, with: CGSize(width: 96, height: 96), antialiasingMode: .none)
                time += 1.0 / 60
            }
            let lid = try XCTUnwrap(scene.scene.rootNode.childNode(withName: "white-player-lid", recursively: true))
            XCTAssertEqual(lid.childNodes.filter { $0.name == "captured-black" }.count, expected)
            XCTAssertEqual(lid.presentation.childNodes.filter { $0.name == "captured-black" }.count, expected)
            XCTAssertNil(lid.childNode(withName: "capture-count", recursively: false))
        }
        XCTAssertEqual(player.board.stones.count, 2, "Rewind restores the original handicap stones")
    }

    func testLargeCapturePilesSettleOnLidsOrTatamiAcrossSizesAndCameraTilt() throws {
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
                XCTAssertLessThan(hypot(Double(position.x), Double(position.z)), 8, "Spilled stone did not stop near its lid on \(size)x\(size)")
                XCTAssertGreaterThan(position.y, 0, "Fell through the visible tatami")
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
            XCTAssertLessThan(hypot(Double(position.x), Double(position.z)), 8)
            XCTAssertGreaterThan(position.y, 0)
        }
        manager.updateCapturedStones(black: 1, white: 0)
        let lid = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "black-player-lid", recursively: true))
        XCTAssertEqual(lid.childNodes.filter { $0.name == "captured-white" }.count, 1)
    }

    func testStoneSettlesDownCurvedSideAndRestsOnVisibleSurface() throws {
        let manager = SceneManager3D()
        manager.updateCapturedStones(black: 1, white: 0, seed: 123)
        let lid = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "black-player-lid", recursively: true))
        XCTAssertNil(lid.childNode(withName: "capture-walls", recursively: false))
        let stone = try XCTUnwrap(lid.childNodes.first { $0.name == "captured-white" })
        stone.position = SCNVector3(2.45, 1.6, 0)
        stone.eulerAngles = SCNVector3Zero
        stone.physicsBody?.resetTransform()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        SCNTransaction.flush()
        for frame in 0..<360 {
            _ = renderer.snapshot(atTime: Double(frame) / 60, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
        }
        let position = stone.presentation.position
        XCTAssertLessThan(hypot(Double(position.x), Double(position.z)), 2.2,
            "The inner slope must guide the stone into the dish")
        XCTAssertGreaterThan(position.y, 0.3)
        XCTAssertLessThan(position.y, 0.8)
        // Sample the actual visible ellipsoid after rotation. It should meet the
        // wooden surface without sinking into it or hovering above it.
        let transform = stone.presentation.simdTransform
        let radius: Float = 0.48 * 0.98
        var minimumGap = Float.greatestFiniteMagnitude
        for latitude in 0...24 {
            let theta = Float(latitude) * .pi / 24
            for longitude in 0..<48 {
                let phi = Float(longitude) * 2 * .pi / 48
                let local = SIMD4<Float>(radius * sin(theta) * cos(phi),
                    radius * 0.486 * cos(theta), radius * sin(theta) * sin(phi), 1)
                let point = transform * local
                let r = CGFloat(hypot(point.x, point.z))
                if r < CaptureLidSurface.innerRadius {
                    minimumGap = min(minimumGap, point.y - Float(CaptureLidSurface.interiorHeight(at: r)))
                }
            }
        }
        XCTAssertGreaterThan(minimumGap, -0.045, "Visible stone penetrates the dish")
        XCTAssertLessThan(minimumGap, 0.06, "Visible stone floats above its collision surface")
    }

    func testSpilledStoneLandsOnTatamiAndBoardCatchesStonesAboveIt() throws {
        let manager = SceneManager3D()
        manager.updateCapturedStones(black: 1, white: 0)
        let lid = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "black-player-lid", recursively: true))
        // Keep the established collision fixture independent of the display layout.
        lid.position.x = 14; lid.position.z = 5
        let stone = try XCTUnwrap(lid.childNodes.first { $0.name == "captured-white" })
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        var time = 0.0
        // Fixed world-space drops keep this collision regression independent of equipment layout.
        for (x, expectedWorldY): (CGFloat, CGFloat) in [(18.1 - lid.worldPosition.x, KayaFloorBoard.floorY + 0.48 * 0.98 * 0.486),
                                                       (8 - lid.worldPosition.x, 1 + 0.48 * 0.98 * 0.486)] {
            stone.position = SCNVector3(x, 2.15 - lid.worldPosition.y, 5 - lid.worldPosition.z)
            stone.eulerAngles = SCNVector3Zero
            stone.physicsBody?.clearAllForces()
            stone.physicsBody?.velocity = SCNVector3Zero
            stone.physicsBody?.angularVelocity = SCNVector4(0, 0, 0, 0)
            stone.physicsBody?.resetTransform()
            SCNTransaction.flush()
            for _ in 0..<240 {
                _ = renderer.snapshot(atTime: time, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
                time += 1.0 / 60
            }
            XCTAssertEqual(CGFloat(stone.presentation.worldPosition.y), expectedWorldY, accuracy: 0.04)
            XCTAssertEqual(CGFloat(stone.presentation.position.x), x, accuracy: 0.15)
        }
        manager.updateCapturedStones(black: 0, white: 0)
        XCTAssertFalse(lid.childNodes.contains { $0.name == "captured-white" },
            "Rewind must remove spilled captures too")
    }

    func testCameraCentersRaisedBoardAndPreservesPanWithoutMovingPhysicsWorld() throws {
        let manager = SceneManager3D()
        for size in [19, 9, 13] {
            manager.updateBoardSize(size)
            manager.updateCapturedStones(black: 3, white: 2)
            let board = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "kaya-floor-board", recursively: true))
            let bounds = try XCTUnwrap(board.geometry).boundingBox
            let corners = [SCNVector3(bounds.min.x, bounds.max.y, bounds.min.z),
                           SCNVector3(bounds.max.x, bounds.max.y, bounds.min.z),
                           SCNVector3(bounds.min.x, bounds.max.y, bounds.max.z),
                           SCNVector3(bounds.max.x, bounds.max.y, bounds.max.z)]
            var bodies: [SCNNode] = []
            manager.scene.rootNode.enumerateChildNodes { node, _ in
                if node.physicsBody != nil { bodies.append(node) }
            }
            let poses = bodies.map { $0.simdWorldTransform }
            let gravity = manager.scene.physicsWorld.gravity
            func projectedMidpoint() -> Float {
                // Perspective-divided surface bounds measure the visible result,
                // independently of the camera's centering calculation.
                let points = corners.map { manager.cameraNode.convertPosition($0, from: board) }
                XCTAssertTrue(points.allSatisfy { $0.z < 0 }, "Board stays in front of the camera")
                let heights = points.map { Float($0.y / -$0.z) }
                return (heights.min()! + heights.max()!) / 2
            }
            for (x, y, distance): (Float, Float, CGFloat) in [(0.75, 0, 25), (1.1, -0.6, 30), (0.3, 0.8, 20)] {
                manager.updateCameraPosition(distance: distance, rotationX: x, rotationY: y, panX: 0, panY: 0)
                XCTAssertEqual(projectedMidpoint(), 0, accuracy: 0.0001, "Raised board is vertically centered on \(size)x\(size)")
                let centered = manager.cameraNode.simdWorldTransform
                manager.updateCameraPosition(distance: distance, rotationX: x, rotationY: y, panX: 2, panY: -2)
                XCTAssertNotEqual(manager.cameraNode.simdWorldTransform, centered)
                XCTAssertGreaterThan(abs(projectedMidpoint()), 0.001, "Deliberate pan must remain visible")
                let panned = manager.cameraNode.simdWorldTransform
                manager.updateCameraPosition(distance: distance, rotationX: x, rotationY: y, panX: 2, panY: -2)
                XCTAssertEqual(manager.cameraNode.simdWorldTransform, panned, "Repeated scene updates must not drift")
                XCTAssertEqual(bodies.map { $0.simdWorldTransform }, poses, "Camera movement must leave physics bodies in place")
                XCTAssertEqual(manager.scene.physicsWorld.gravity.x, gravity.x)
                XCTAssertEqual(manager.scene.physicsWorld.gravity.y, gravity.y)
                XCTAssertEqual(manager.scene.physicsWorld.gravity.z, gravity.z)
            }
        }
    }

    func testKoMarkerCanBeShownAndCleared() {
        let manager = SceneManager3D()
        manager.updateKoMarker(at: BoardPosition(1, 2))
        let marker = manager.scene.rootNode.childNode(withName: "ko-marker", recursively: true)
        XCTAssertNotNil(marker?.geometry as? SCNPlane)
        XCTAssertNotNil(marker?.geometry?.firstMaterial?.diffuse.contents as? NSImage)
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
        XCTAssertNil(scene.scene.rootNode.childNode(withName: "capture-count", recursively: true))
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
