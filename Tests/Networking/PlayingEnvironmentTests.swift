import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class PlayingEnvironmentTests: XCTestCase {
    func testImaginativeTablePropsHaveVisibleGeometryAndLeaveBoardClear() throws {
        let manager = SceneManager3D()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        for kind in [PlayingEnvironment.retroFuture, .laboratory] {
            manager.updateEnvironment(kind, flicker: false)
            _ = renderer.snapshot(atTime: 0, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
            var vertices = 0
            manager.scene.rootNode.enumerateChildNodes { node, _ in
                guard node.name?.contains("-foreground-") == true else { return }
                XCTAssertNotNil(node.geometry, "Batched props must survive SceneKit flattening")
                for source in node.geometry?.sources(for: .vertex) ?? [] {
                    vertices += source.vectorCount
                    source.data.withUnsafeBytes { bytes in
                        for i in 0..<source.vectorCount {
                            func component(_ j: Int) -> CGFloat {
                                let offset = source.dataOffset + i * source.dataStride + j * source.bytesPerComponent
                                return source.bytesPerComponent == 4
                                    ? CGFloat(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self))
                                    : CGFloat(bytes.loadUnaligned(fromByteOffset: offset, as: Double.self))
                            }
                            let point = node.convertPosition(SCNVector3(component(0),component(1),component(2)), to: nil)
                            XCTAssertTrue(abs(point.x) > 15 || abs(point.z) > 16, "Scenery cannot overlap the playing surface")
                            XCTAssertGreaterThan(point.y, CGFloat(kind.equipmentSurfaceY) - 0.05)
                        }
                    }
                }
            }
            XCTAssertGreaterThan(vertices, 1000)
        }
    }

    func testIncenseSmokeRespectsMotionAndSceneLifetime() throws {
        let manager = SceneManager3D()
        manager.updateEnvironment(.monastery,flicker:false,motion:false)
        var emitters: [SCNNode] = []
        manager.scene.rootNode.enumerateChildNodes { n, _ in if n.name == "incense-smoke" { emitters.append(n) } }
        XCTAssertEqual(emitters.count,2)
        func expect(_ running: Bool) {
            for emitter in emitters {
                XCTAssertEqual(emitter.isHidden,!running)
                XCTAssertFalse(emitter.castsShadow)
                let smoke = emitter.particleSystems!.first!
                XCTAssertEqual(smoke.birthRate,running ? 4 : 0)
                XCTAssertEqual(smoke.speedFactor,running ? 1 : 0)
            }
        }
        expect(false)
        manager.updateEnvironment(.monastery,flicker:false,motion:true); expect(true)
        manager.setEnvironmentActive(false); expect(false)
        manager.setEnvironmentActive(true); expect(true)
        manager.updateEnvironment(.coffeeShop,flicker:false,motion:true); expect(false)
        manager.updateEnvironment(.monastery,flicker:false,motion:false); expect(false)
    }

    func testLampVariationIsGentleContinuousAndIrregular() {
        var values: [Double] = []
        for tick in 0...4800 {
            let t = Double(tick) * 0.125
            let value = PlayingEnvironmentScene.lampVariation(at: t)
            XCTAssertLessThanOrEqual(abs(value.brightness), 0.025)
            XCTAssertLessThanOrEqual(abs(value.offset.x), 0.065)
            XCTAssertLessThanOrEqual(abs(value.offset.y), 0.035)
            XCTAssertLessThanOrEqual(abs(value.offset.z), 0.055)
            let next = PlayingEnvironmentScene.lampVariation(at: t + 0.001)
            XCTAssertLessThan(abs(next.brightness - value.brightness), 0.0002)
            values.append(value.brightness)
        }
        XCTAssertGreaterThan(values.max()! - values.min()!, 0.025)
        let differences = (0..<400).map { abs(values[$0] - values[$0 + 400]) }
        XCTAssertGreaterThan(differences.reduce(0,+) / 400, 0.005, "No repeated 50-second cycle")
    }

    func testYugenHasTwoGroundedSeatsWithClearBoardAndBowlSpace() throws {
        let manager = SceneManager3D(); manager.updateEnvironment(.yugenRoom, flicker: false)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        _ = renderer.snapshot(atTime: 0, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
        for side in ["player", "opponent"] {
            let seat = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "yugen-furniture-\(side)", recursively: true))
            XCTAssertEqual(seat.worldPosition.y, KayaFloorBoard.floorY, accuracy: 0.001)
            XCTAssertTrue(seat.castsShadow); XCTAssertNil(seat.physicsBody)
            // Includes the runner, seat, back and separate armrest, all outside
            // the slab and the bowls' z extent (about +/- 14 world units).
            XCTAssertGreaterThan(abs(seat.position.z) - max(abs(seat.boundingBox.min.z), abs(seat.boundingBox.max.z)), 14)
            XCTAssertGreaterThan(seat.boundingBox.max.y, 14)
        }
        manager.updateEnvironment(.moon, flicker: false)
        XCTAssertNil(manager.scene.rootNode.childNode(withName: "yugen-furniture-player", recursively: true))
    }

    func testMonasteryHasHorizontalTimberAndTwoGroundedSeats() throws {
        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("SGFPlayerClean/Assets/Environments")
        let panorama = try XCTUnwrap(NSImage(contentsOf: assets.appendingPathComponent("monastery-intimate-panorama.png")))
        panorama.setName("monastery-intimate-panorama.png")
        defer { withExtendedLifetime(panorama) {} }
        let manager = SceneManager3D()
        manager.updateEnvironment(.monastery, flicker: false)
        let root = manager.scene.rootNode
        let floor = try XCTUnwrap(root.childNode(withName: "photographic-ground", recursively: true))
        XCTAssertEqual(floor.geometry?.firstMaterial?.name, "monastery-worn-floorboards")
        XCTAssertEqual(floor.geometry?.firstMaterial?.lightingModel, .physicallyBased)
        let positions = try XCTUnwrap(floor.geometry?.sources(for: .vertex).first)
        func point(_ i: Int) -> SIMD3<Float> {
            positions.data.withUnsafeBytes { bytes in
                let offset = positions.dataOffset + i * positions.dataStride
                func component(_ axis: Int) -> Float {
                    let start = offset + axis * positions.bytesPerComponent
                    return positions.bytesPerComponent == 8 ? Float(bytes.loadUnaligned(fromByteOffset: start, as: Double.self))
                        : bytes.loadUnaligned(fromByteOffset: start, as: Float.self)
                }
                return SIMD3(component(0), component(1), component(2))
            }
        }
        var widths = Set<Int>()
        // Boards are subdivided along their grain so the worn edges can chip.
        for i in stride(from: 0, to: positions.vectorCount, by: 2) {
            let across = point(i + 1) - point(i)
            XCTAssertEqual(across.x, 0); XCTAssertGreaterThan(across.z, 0)
            XCTAssertEqual(point(i).y, -1.015, accuracy: 0.001)
            widths.insert(Int(across.z * 100))
        }
        XCTAssertGreaterThan(widths.count, 10, "Plank widths vary naturally")
        let seats = try ["player", "opponent"].map { side in
            try XCTUnwrap(root.childNode(withName: "zabuton-\(side)", recursively: true))
        }
        XCTAssertEqual(seats[0].position.z, -seats[1].position.z)
        for seat in seats {
            XCTAssertEqual(seat.worldPosition.y, KayaFloorBoard.floorY, accuracy: 0.001)
            XCTAssertNil(seat.physicsBody)
            let body = try XCTUnwrap(seat.childNodes.first { $0.name?.hasPrefix("zabuton-body") == true })
            XCTAssertTrue(body.castsShadow)
            XCTAssertGreaterThan(body.boundingBox.min.z + abs(seat.position.z), 14, "Seat clears even the larger nine-line slab")
        }
        manager.updateEnvironment(.moon, flicker: false)
        XCTAssertNil(root.childNode(withName: "zabuton-player", recursively: true))
        manager.updateEnvironment(.monastery, flicker: false)
        XCTAssertTrue(root.childNode(withName: "zabuton-player", recursively: true) === seats[0])
    }

    func testGrainFollowsTheSlabAndDappleOnlyAppearsUnderTree() throws {
        let body = KayaFloorBoard.body(width:20,length:22)
        let uv = try XCTUnwrap(body.sources(for:.texcoord).first)
        func u(_ index: Int) -> Double {
            uv.data.withUnsafeBytes { bytes in
                let offset=uv.dataOffset+index*uv.dataStride
                return uv.bytesPerComponent == 8 ? bytes.loadUnaligned(fromByteOffset:offset,as:Double.self)
                    : Double(bytes.loadUnaligned(fromByteOffset:offset,as:Float.self))
            }
        }
        for start in [16,20] { // Long sides: grain stays constant along z.
            XCTAssertEqual(u(start),u(start+1)); XCTAssertNotEqual(u(start+1),u(start+2))
        }
        for start in [8,12] { // Player-facing ends: grain follows height.
            XCTAssertNotEqual(u(start),u(start+1)); XCTAssertEqual(u(start+1),u(start+2))
        }
        XCTAssertEqual(PlayingEnvironment(rawValue:"tatami"),.monastery)
        let manager=SceneManager3D()
        for kind in [PlayingEnvironment.tree,.monastery,.cave,.yugenRoom,.tree] {
            manager.updateEnvironment(kind,flicker:false)
            manager.updateBoardSize(13)
            XCTAssertNil(manager.scene.rootNode.childNode(withName:"canopy-dapple",recursively:true))
            let canopy=manager.scene.rootNode.childNode(withName:"canopy-shadow-caster",recursively:true)
            XCTAssertEqual(canopy != nil,kind == .tree)
            if let canopy {
                XCTAssertTrue(canopy.castsShadow); XCTAssertNil(canopy.physicsBody)
                XCTAssertTrue(canopy.actionKeys.isEmpty)
            }
            XCTAssertEqual(manager.cameraNode.camera?.wantsHDR,kind == .cave)
        }
    }
    func testSwitchingPreservesGameAndReusesScenery() throws {
        let manager = SceneManager3D()
        let root = manager.scene.rootNode
        let bowl = try XCTUnwrap(root.childNode(withName: "black-stone-bowl", recursively: true))
        let room = try XCTUnwrap(root.childNode(withName: "shoji-environment", recursively: true))
        let floor = try XCTUnwrap(root.childNode(withName: "tatami-environment", recursively: true))
        let support = try XCTUnwrap(floor.childNode(withName: "tatami-collision-surface", recursively: false))
        let camera = manager.cameraNode.simdTransform
        var cached: [PlayingEnvironment: SCNNode] = [:]
        for _ in 0..<2 {
            for kind in PlayingEnvironment.allCases {
                manager.updateEnvironment(kind, flicker: true)
                let scene = try XCTUnwrap(root.childNode(withName: "environment-\(kind.rawValue)", recursively: true))
                if let previous = cached[kind] { XCTAssertTrue(previous === scene) }
                cached[kind] = scene
                XCTAssertEqual(manager.currentEnvironment, kind)
                XCTAssertEqual(manager.cameraNode.simdTransform, camera)
                XCTAssertTrue(root.childNode(withName: "black-stone-bowl", recursively: true) === bowl)
                XCTAssertEqual(room.isHidden, kind != .gardenRoom)
                XCTAssertTrue(floor.childNodes.filter { $0.physicsBody == nil }.allSatisfy {
                    $0.isHidden == ($0.name == "room-tatami" ? kind != .gardenRoom : true)
                })
                XCTAssertNotNil(support.physicsBody); XCTAssertFalse(support.isHidden)
                var lights = 0, meshes = 0
                scene.enumerateChildNodes { node, _ in
                    if node.name?.hasSuffix("-tabletop") == true { XCTAssertEqual(node.physicsBody?.type, .static) }
                    else { XCTAssertNil(node.physicsBody) }
                    if let light = node.light { lights += 1; XCTAssertTrue(light.castsShadow) }
                    if node.geometry != nil { meshes += 1 }
                }
                XCTAssertEqual(lights, kind == .cave ? 1 : 0)
                XCTAssertLessThanOrEqual(meshes, kind == .laboratory ? 24 : 14)
                for (other, node) in cached where other != kind {
                    XCTAssertNil(node.parent)
                    XCTAssertNil(node.childNode(withName: "oil-lamp-light", recursively: true)?.action(forKey: "lamp-flicker"))
                }
            }
        }
    }

    func testEquipmentLayoutLabelsAndShadowLighting() throws {
        let manager=SceneManager3D(); let root=manager.scene.rootNode
        let blackLid=try XCTUnwrap(root.childNode(withName:"black-player-lid",recursively:true))
        let whiteLid=try XCTUnwrap(root.childNode(withName:"white-player-lid",recursively:true))
        XCTAssertLessThan(blackLid.position.x,-18); XCTAssertGreaterThan(whiteLid.position.x,18)
        XCTAssertGreaterThan(blackLid.position.z,0); XCTAssertLessThan(whiteLid.position.z,0)
        XCTAssertGreaterThan(try XCTUnwrap(root.childNode(withName:"black-stone-bowl",recursively:true)).position.x,18)
        XCTAssertLessThan(try XCTUnwrap(root.childNode(withName:"white-stone-bowl",recursively:true)).position.x,-18)
        for lid in [blackLid,whiteLid] {
            XCTAssertNil(lid.childNode(withName:"capture-count",recursively:false))
        }
        let plant=try XCTUnwrap(root.childNode(withName:"indoor-plant",recursively:true))
        XCTAssertTrue(plant.castsShadow)
        manager.updateEnvironment(.cave,flicker:false)
        let lamp=try XCTUnwrap(root.childNode(withName:"oil-lamp-light",recursively:true))
        XCTAssertGreaterThan(lamp.worldPosition.y,1)
        XCTAssertEqual(lamp.light?.castsShadow,true)
        XCTAssertEqual(root.childNode(withName:"SUN",recursively:true)?.light?.castsShadow,true)
        manager.updateEnvironment(.moon,flicker:false)
        XCTAssertEqual(root.childNode(withName:"SUN",recursively:true)?.light?.castsShadow,true)
    }

    func testCanopyFillExcludesHighCanopyAndResetsWhenSwitching() throws {
        let manager = SceneManager3D()
        let root = manager.scene.rootNode
        let sun = try XCTUnwrap(root.childNode(withName: "SUN", recursively: true))
        var cachedCanopyLight: SCNNode?
        for kind in [PlayingEnvironment.tree, .cave, .moon, .tree, .gardenRoom] {
            manager.updateEnvironment(kind, flicker: false)
            let foliage = root.childNode(withName: "SUN_CANOPY", recursively: true)
            XCTAssertEqual(foliage != nil, kind == .tree)
            if let foliage {
                if let cachedCanopyLight { XCTAssertTrue(foliage === cachedCanopyLight) }
                cachedCanopyLight = foliage
                XCTAssertEqual(sun.light!.intensity + foliage.light!.intensity, 1000)
                let canopy = try XCTUnwrap(root.childNode(withName: "canopy-shadow-caster", recursively: true))
                XCTAssertGreaterThan(canopy.worldPosition.y + canopy.boundingBox.min.y, sun.worldPosition.y)
                XCTAssertFalse(sun.light!.automaticallyAdjustsShadowProjection)
            }
            if kind == .moon || kind == .gardenRoom {
                XCTAssertEqual(sun.light!.intensity, kind == .gardenRoom ? 650 : 1000)
                XCTAssertEqual(sun.position.y, 31.4, accuracy: 0.001)
                XCTAssertTrue(sun.light!.automaticallyAdjustsShadowProjection)
            }
        }
    }

    func testLampStopsWhenDisabledOrViewLeaves() throws {
        let manager = SceneManager3D()
        manager.updateEnvironment(.cave, flicker: true)
        let lamp = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "oil-lamp-light", recursively: true))
        XCTAssertNotNil(lamp.action(forKey: "lamp-flicker"))
        manager.setEnvironmentActive(false)
        XCTAssertNil(lamp.action(forKey: "lamp-flicker"))
        manager.updateEnvironment(.cave, flicker: true)
        XCTAssertNil(lamp.action(forKey: "lamp-flicker"), "Settings updates cannot restart a hidden view")
        manager.setEnvironmentActive(true)
        XCTAssertNotNil(lamp.action(forKey: "lamp-flicker"))
        manager.updateEnvironment(.cave, flicker: false)
        XCTAssertNil(lamp.action(forKey: "lamp-flicker"))
        XCTAssertEqual(lamp.light?.intensity, PlayingEnvironmentScene.caveLampIntensity)
    }

    func testFloorBoardSurfaceAndEquipmentAgreeOnFloorHeight() throws {
        let manager=SceneManager3D()
        for size in [9,13,19] {
            manager.updateBoardSize(size)
            let root=manager.scene.rootNode
            let board=try XCTUnwrap(root.childNode(withName:"kaya-floor-board",recursively:true))
            let body=try XCTUnwrap(board.geometry)
            XCTAssertEqual(body.boundingBox.max.y,1,accuracy:0.001)
            XCTAssertEqual(body.boundingBox.min.y,1-KayaFloorBoard.slabThickness,accuracy:0.001)
            let feet=board.childNodes.filter { $0.name == "kaya-carved-foot" }
            XCTAssertEqual(feet.count,4)
            for foot in feet {
                XCTAssertEqual(foot.worldPosition.y,KayaFloorBoard.floorY+0.015,accuracy:0.001)
            }
            for name in ["black-stone-bowl","white-stone-bowl","black-player-lid","white-player-lid"] {
                let item=try XCTUnwrap(root.childNode(withName:name,recursively:true))
                XCTAssertEqual(item.worldPosition.y,KayaFloorBoard.floorY+0.165,accuracy:0.001)
            }
            let support=try XCTUnwrap(root.childNode(withName:"tatami-collision-surface",recursively:true))
            XCTAssertEqual(support.worldPosition.y+0.1,KayaFloorBoard.floorY,accuracy:0.001)
        }
    }
}
