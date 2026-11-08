import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class BowlSupplyTests: XCTestCase {
    private func supply(_ manager: SceneManager3D, white: Bool) -> [SCNNode] {
        manager.scene.rootNode.childNode(withName: white ? "white-stone-bowl" : "black-stone-bowl", recursively: true)!
            .childNodes.filter { $0.name == "supply-stone" && !$0.isHidden }
    }

    func testFullBowlsPackDenselyWithoutRuntimePhysics() throws {
        // Guard against reintroducing the tall, friction-locked pile. Height is
        // measured in bowl coordinates, independent of scene placement.
        for white in [false, true] {
            let bowl = GoEquipment3D.makeBowl(isWhite: white, stoneMaterial: SCNMaterial())
            let stones = bowl.childNodes.filter { $0.name == "supply-stone" }
            XCTAssertEqual(stones.count, white ? 180 : 181)
            let meanHeight = stones.reduce(0.0) { $0 + Double($1.position.y) } / Double(stones.count)
            XCTAssertLessThan(meanHeight, 2.38, "Stones should settle into gaps rather than form a loose tall pile")
            XCTAssertTrue(stones.allSatisfy { $0.physicsBody == nil && hypot($0.position.x, $0.position.z) < 3.1 })
            let geometry = try XCTUnwrap(stones.first?.geometry as? SCNSphere)
            XCTAssertEqual(geometry.radius * 2 * GoEquipmentDimensions2D.millimetresPerModelUnit,
                           GoEquipmentDimensions2D.stoneDiameter(white ? .white : .black), accuracy: 0.0001)
        }
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd])")))
        player.seek(to: 1)
        let manager = SceneManager3D()
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        let blackHeights = supply(manager, white: false).map { $0.position.y }
        let whiteHeights = supply(manager, white: true).map { $0.position.y }
        XCTAssertEqual(blackHeights.count, whiteHeights.count)
        XCTAssertNotEqual(blackHeights, whiteHeights, "White stones need their own simulation at their actual size")
    }

    func testSupplyAndPlayedFinishesStaySharedAcrossScenesResizesAndSettings() throws {
        let manager = SceneManager3D()
        let black = manager.stoneMaterial(isWhite:false)
        let white = manager.stoneMaterial(isWhite:true)
        for kind in PlayingEnvironment.allCases {
            manager.updateEnvironment(kind,flicker:false,motion:false)
            for size in [9,13,19] {
                manager.updateBoardSize(size)
                XCTAssertTrue(manager.stoneMaterial(isWhite:false) === black)
                XCTAssertTrue(manager.stoneMaterial(isWhite:true) === white)
                XCTAssertTrue(supply(manager,white:false).first!.geometry!.firstMaterial === black)
                XCTAssertTrue(supply(manager,white:true).first!.geometry!.firstMaterial === white)
            }
        }
        manager.blackRoughness = 0.52
        manager.whiteRoughness = 0.63
        manager.stoneAmbientIntensity = 0.8
        XCTAssertEqual(black.roughness.contents as? Double,0.52)
        XCTAssertEqual(white.roughness.contents as? Double,0.63)
        let emission = try XCTUnwrap((black.emission.contents as? NSColor)?.usingColorSpace(.sRGB))
        XCTAssertEqual(emission.redComponent,0,accuracy:0.0001,"Black stones reflect light without a gray self-lit veil")
    }

    func testMovesPassesHandicapAndRewindUseBakedStates() throws {
        let game = SGFGame.from(tree: try SGFParser.parse(text:
            "(;SZ[19]AB[dd][pp]AW[pd];B[dp];W[];B[cf];W[nc])"))
        let player = SGFPlayer(); player.load(game: game)
        let manager = SceneManager3D()
        func sync() { GoEquipment3D.updateSupplies(in: manager, player: player, animate: false) }
        sync()
        XCTAssertEqual(supply(manager, white: false).count, 179)
        XCTAssertEqual(supply(manager, white: true).count, 179)
        let initial = supply(manager, white: false).map(\.simdTransform)
        player.seek(to: 1); sync()
        XCTAssertEqual(supply(manager, white: false).count, 178)
        player.seek(to: 2); sync()
        XCTAssertEqual(supply(manager, white: true).count, 179, "Passes do not remove supply stones")
        player.seek(to: 4); sync()
        XCTAssertEqual(supply(manager, white: false).count, 177)
        XCTAssertEqual(supply(manager, white: true).count, 178)
        let end = supply(manager, white: false).map(\.simdTransform)
        player.seek(to: 0); sync()
        XCTAssertEqual(supply(manager, white: false).map(\.simdTransform), initial, "Rewind restores the complete settled layout")
        player.seek(to: 4); sync()
        XCTAssertEqual(supply(manager, white: false).map(\.simdTransform), end)
        sync()
        XCTAssertEqual(supply(manager, white: false).map(\.simdTransform), end, "Unchanged UI updates do no layout work")
        XCTAssertTrue((supply(manager, white: false) + supply(manager, white: true)).allSatisfy { $0.physicsBody == nil })
    }

    func testCapturedStoneDoesNotReturnToSupplyAndNewGameRefills() throws {
        let game = SGFGame.from(tree: try SGFParser.parse(text:
            "(;SZ[9]AB[ba][ab][bc]AW[bb][ca][db][cc];B[cb])"))
        let player = SGFPlayer(); player.load(game: game)
        let manager = SceneManager3D()
        player.seek(to: 1)
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        XCTAssertEqual(player.capturesByBlack, 1)
        XCTAssertEqual(supply(manager, white: true).count, 176, "Prisoners belong to the capture lid")
        XCTAssertEqual(supply(manager, white: false).count, 177)
        player.load(game: SGFGame())
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        XCTAssertEqual(supply(manager, white: false).count, 181)
        XCTAssertEqual(supply(manager, white: true).count, 180)
    }

    func testAnimatedMoveImmediatelyUndoneRestoresVisibility() throws {
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd])")))
        let manager = SceneManager3D()
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        player.seek(to: 1)
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: true)
        player.seek(to: 0)
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene
        for frame in 0..<60 { renderer.update(atTime: Double(frame) / 60) }
        XCTAssertEqual(supply(manager, white: false).count, 181)
        XCTAssertTrue(supply(manager, white: false).allSatisfy { $0.opacity == 1 })
    }
}
