import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class CoffeeShopTests: XCTestCase {
    func testCompactEquipmentClearsBoardAndFitsNormalWindows() throws {
        let manager = SceneManager3D()
        manager.updateEnvironment(.coffeeShop, flicker: false, motion: false)
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1280, height: 960))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: size), rotationX: 0.44, rotationY: 0, panX: 0, panY: 0)
            SCNTransaction.flush()
            let board = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "kaya-table-board", recursively: true))
            for name in ["white-player-lid", "black-player-lid", "white-stone-bowl", "black-stone-bowl"] {
                let item = try XCTUnwrap(manager.scene.rootNode.childNode(withName: name, recursively: true))
                let bounds = item.boundingBox
                XCTAssertGreaterThan(abs(item.position.x) - max(abs(bounds.min.x), abs(bounds.max.x)), board.boundingBox.max.x + 0.2)
                // Project the actual round surfaces: empty corners of a bowl's
                // bounding box extend well beyond its visible silhouette.
                var surfaces = [item]
                item.enumerateChildNodes { node, _ in surfaces.append(node) }
                for surface in surfaces {
                    for source in surface.geometry?.sources(for: .vertex) ?? [] {
                        XCTAssertTrue(source.usesFloatComponents)
                        source.data.withUnsafeBytes { bytes in
                            for i in 0..<source.vectorCount {
                                func component(_ j: Int) -> CGFloat {
                                    let offset = source.dataOffset + i * source.dataStride + j * source.bytesPerComponent
                                    return source.bytesPerComponent == 4
                                        ? CGFloat(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self))
                                        : CGFloat(bytes.loadUnaligned(fromByteOffset: offset, as: Double.self))
                                }
                                let point = view.projectPoint(surface.convertPosition(SCNVector3(component(0), component(1), component(2)), to: nil))
                                XCTAssertGreaterThanOrEqual(point.x, 1, "\(name) stays in view on \(size)×\(size)")
                                XCTAssertLessThanOrEqual(point.x, 1279, "\(name) stays in view on \(size)×\(size)")
                                XCTAssertGreaterThanOrEqual(point.y, 1); XCTAssertLessThanOrEqual(point.y, 959)
                            }
                        }
                    }
                }
            }
        }
        manager.updateEnvironment(.monastery, flicker: false)
        XCTAssertEqual(manager.equipmentOffsetX, 20, "Floor-board layout is preserved")
    }

    func testSteamStopsForReducedMotionAndInactiveOrDifferentEnvironments() throws {
        let manager = SceneManager3D()
        manager.updateEnvironment(.coffeeShop, flicker: false, motion: false)
        var emitters: [SCNNode] = []
        manager.scene.rootNode.enumerateChildNodes { n, _ in if n.name == "coffee-steam" { emitters.append(n) } }
        XCTAssertEqual(emitters.count, 2)
        func expect(_ running: Bool) {
            for emitter in emitters {
                XCTAssertEqual(emitter.isHidden, !running)
                XCTAssertEqual(emitter.particleSystems!.first!.birthRate, running ? 2 : 0)
                XCTAssertEqual(emitter.particleSystems!.first!.speedFactor, running ? 1 : 0)
                XCTAssertFalse(emitter.castsShadow)
            }
        }
        expect(false)
        manager.updateEnvironment(.coffeeShop, flicker: false, motion: true); expect(true)
        manager.setEnvironmentActive(false); expect(false)
        manager.setEnvironmentActive(true); expect(true)
        manager.updateEnvironment(.tree, flicker: false); expect(false)
        manager.updateEnvironment(.coffeeShop, flicker: false, motion: false); expect(false)
        manager.setEnvironmentActive(false); manager.setEnvironmentActive(true); expect(false)
    }

    func testTableBoardAndEquipmentShareTheTableSurfaceAtEveryBoardSize() throws {
        let manager = SceneManager3D()
        manager.updateEnvironment(.coffeeShop, flicker: false)
        let root = manager.scene.rootNode
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            let board = try XCTUnwrap(root.childNode(withName: "kaya-table-board", recursively: true))
            XCTAssertNil(board.childNode(withName: "kaya-carved-foot", recursively: true))
            XCTAssertEqual(board.geometry!.boundingBox.max.y, 1, accuracy: 0.001)
            XCTAssertEqual(board.geometry!.boundingBox.min.y, -1.4, accuracy: 0.001)
            let table = try XCTUnwrap(root.childNode(withName: "coffee-tabletop", recursively: true))
            let top = table.convertPosition(SCNVector3(0, table.boundingBox.max.y, 0), to: root)
            XCTAssertEqual(top.y, CGFloat(PlayingEnvironment.coffeeShop.equipmentSurfaceY), accuracy: 0.001)
            XCTAssertEqual(table.physicsBody?.type, .static)
            for name in ["white-player-lid", "black-player-lid", "white-stone-bowl", "black-stone-bowl"] {
                let piece = try XCTUnwrap(root.childNode(withName: name, recursively: true))
                XCTAssertEqual(piece.position.y, PlayingEnvironment.coffeeShop.equipmentSurfaceY + 0.165, accuracy: 0.001)
            }
            XCTAssertLessThan(board.boundingBox.max.x, table.boundingBox.max.x - 10)
            XCTAssertLessThan(board.boundingBox.max.z, table.boundingBox.max.z - 10)
        }
        manager.updateEnvironment(.tree, flicker: false)
        let floorBoard = try XCTUnwrap(root.childNode(withName: "kaya-floor-board", recursively: true))
        XCTAssertEqual(floorBoard.childNodes.filter { $0.name == "kaya-carved-foot" }.count, 4)
        XCTAssertNil(root.childNode(withName: "coffee-tabletop", recursively: true))
        XCTAssertEqual(root.childNode(withName: "white-player-lid", recursively: true)!.position.y,
                       KayaFloorBoard.floorY + 0.165, accuracy: 0.001)
    }

    func testChangingSupportHeightPreservesSettledCapturesAndBoardStones() throws {
        let manager = SceneManager3D()
        manager.updateCapturedStones(black: 4, white: 4, seed: 123)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        func frame(_ time: Double) {
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
        }
        for i in 0...180 { frame(Double(i) / 60) }
        var captures: [SCNNode] = []
        manager.scene.rootNode.enumerateChildNodes { n, _ in
            if n.name == "captured-white" || n.name == "captured-black" { captures.append(n) }
        }
        XCTAssertEqual(captures.count, 8)
        var time = 3.0
        for kind in [PlayingEnvironment.coffeeShop, .moon, .coffeeShop, .gardenRoom] {
            let local = captures.map { $0.presentation.simdTransform }
            manager.updateEnvironment(kind, flicker: false)
            for (n, pose) in zip(captures, local) {
                XCTAssertNotNil(n.parent)
                XCTAssertEqual(n.simdTransform, pose, "Switching supports must keep each settled pile intact")
            }
            for i in 1...60 { frame(time + Double(i) / 60) }
            time += 1
            for n in captures {
                XCTAssertGreaterThan(n.presentation.worldPosition.y, kind.equipmentSurfaceY,
                                     "Captured stones remain supported after switching environments")
                XCTAssertLessThan(abs(n.presentation.position.x), 4)
                XCTAssertLessThan(abs(n.presentation.position.z), 4)
            }
        }
    }

    func testAnOverflowingStoneLandsOnThePhysicalTable() throws {
        let manager = SceneManager3D()
        manager.updateEnvironment(.coffeeShop, flicker: false)
        let stone = SCNNode(geometry: SCNSphere(radius: 0.5))
        stone.position = SCNVector3(10, 5, 23)
        stone.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: stone.geometry!, options: [.collisionMargin: 0.005]))
        stone.physicsBody!.categoryBitMask = 1; stone.physicsBody!.collisionBitMask = 2
        stone.physicsBody!.restitution = 0
        manager.scene.rootNode.addChildNode(stone)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        for i in 0...240 {
            _ = renderer.snapshot(atTime: Double(i) / 60, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
        }
        XCTAssertEqual(stone.presentation.worldPosition.y - 0.5, PlayingEnvironment.coffeeShop.equipmentSurfaceY, accuracy: 0.08)
    }
}
