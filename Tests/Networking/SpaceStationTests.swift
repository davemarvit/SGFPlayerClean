import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class SpaceStationTests: XCTestCase {
    func testDisplayMotionIsSlowAndPausesWithSceneAndReduceMotion() throws {
        let manager = SceneManager3D()
        manager.updateEnvironment(.spaceStation, flicker: false, motion: true)
        let root = manager.scene.rootNode
        let clock = try XCTUnwrap(root.childNode(withName: "station-display-clock", recursively: true))
        var material: SCNMaterial?
        root.enumerateChildNodes { child, _ in
            if let display = child.geometry?.materials.first(where: { $0.name == "station-worn-display-glass" }) { material = display }
        }
        let display = try XCTUnwrap(material)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode; renderer.isPlaying = true
        func render(_ time: Double) {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 32,height: 32), antialiasingMode: .none)
        }
        func phase() -> Float { (display.value(forKey: "stationDisplayPhase") as? NSNumber)?.floatValue ?? -1 }
        render(0); render(0.1)
        let start = phase()
        render(1.1)
        XCTAssertGreaterThan(phase(), start)
        XCTAssertLessThan(phase()-start, 0.06, "Less than 3.5 degrees of orbital motion per second")
        manager.setEnvironmentActive(false)
        XCTAssertTrue(clock.isPaused)
        let frozen = phase(); render(10)
        XCTAssertEqual(phase(), frozen, accuracy: 0.00001)
        manager.setEnvironmentActive(true); XCTAssertFalse(clock.isPaused)
        manager.updateEnvironment(.spaceStation, flicker: false, motion: false)
        XCTAssertTrue(clock.isPaused)
        manager.updateEnvironment(.coffeeShop, flicker: false)
        XCTAssertTrue(clock.isPaused)
        manager.updateEnvironment(.spaceStation, flicker: false, motion: true)
        XCTAssertTrue(root.childNode(withName: "station-display-clock", recursively: true) === clock)
        XCTAssertFalse(clock.isPaused)
    }

    func testCapturedStoneDriftsThenLandsOnItsLid() throws {
        let manager = SceneManager3D()
        manager.updateEnvironment(.spaceStation, flicker: false)
        manager.updateCapturedStones(black: 1, white: 0)
        let stone = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "captured-white", recursively: true))
        let startY = stone.position.y
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        renderer.isPlaying = true
        SCNTransaction.flush()
        for frame in 0...30 {
            _ = renderer.snapshot(atTime: Double(frame) / 60, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
        }
        XCTAssertLessThan(stone.presentation.position.y, startY - 0.005)
        XCTAssertGreaterThan(stone.presentation.position.y, startY - 0.10, "Capture should still be drifting after half a second")
        for frame in 31...1800 {
            _ = renderer.snapshot(atTime: Double(frame) / 60, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
            if frame > 300 && stone.physicsBody!.isResting { break }
        }
        XCTAssertLessThan(stone.presentation.position.y, startY - 0.30, "Low gravity must still let the stone reach its lid")
        XCTAssertGreaterThan(stone.presentation.position.y, -0.1, "The physical lid catches the stone")
        XCTAssertTrue(stone.physicsBody!.isResting)
    }

    func testSlowDropSurvivesRefreshAndHistoryJumpSettlesImmediately() throws {
        let settings = AppSettings.shared
        let previous = settings.showDropInAnimation
        settings.showDropInAnimation = true
        defer { settings.showDropInAnimation = previous }
        let manager = SceneManager3D()
        let stones = [RenderStone(id: BoardPosition(9, 9), color: .black, offset: .zero)]
        for kind in [PlayingEnvironment.spaceStation, .coffeeShop, .spaceStation, .moon] {
            manager.updateStones(from: [], lastMove: nil, moveIndex: 0, settings: settings, animate: false)
            manager.updateEnvironment(kind, flicker: false)
            manager.updateStones(from: stones, lastMove: nil, moveIndex: 1, settings: settings)
            let visual = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "board-stone", recursively: true))
            let anchor = try XCTUnwrap(visual.parent)
            let action = try XCTUnwrap(anchor.action(forKey: "stone-placement-drop"))
            XCTAssertEqual(action.duration, kind == .spaceStation ? 2 : 0.2, accuracy: 0.001)
            manager.updateStones(from: stones, lastMove: nil, moveIndex: 1, settings: settings)
            XCTAssertTrue(anchor.action(forKey: "stone-placement-drop") === action)
            manager.updateStones(from: stones, lastMove: nil, moveIndex: 1, settings: settings, animate: false)
            XCTAssertFalse(anchor.hasActions)
            XCTAssertEqual(anchor.position.y, 1, accuracy: 0.001)
            XCTAssertEqual(manager.scene.physicsWorld.gravity.y, kind == .spaceStation ? -0.1962 : -19.62, accuracy: 0.0001)
        }
    }

    func testTableSupportsEveryBoardSizeAndInsetControlsLeaveEquipmentClear() throws {
        let manager = SceneManager3D()
        manager.updateEnvironment(.spaceStation, flicker: false)
        let root = manager.scene.rootNode
        let table = try XCTUnwrap(root.childNode(withName: "station-tabletop", recursively: true))
        XCTAssertEqual(table.physicsBody?.type, .static)
        XCTAssertEqual(table.boundingBox.max.x - table.boundingBox.min.x, 72, accuracy: 0.001)
        XCTAssertEqual(table.boundingBox.max.z - table.boundingBox.min.z, 56, accuracy: 0.001)
        XCTAssertEqual(table.worldPosition.y + table.boundingBox.max.y, PlayingEnvironment.spaceStation.equipmentSurfaceY, accuracy: 0.001)
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            let board = try XCTUnwrap(root.childNode(withName: "kaya-table-board", recursively: true))
            XCTAssertTrue(board.childNodes.allSatisfy { $0.name != "kaya-carved-foot" })
            XCTAssertEqual(board.geometry!.boundingBox.min.y, 1 - 2.4, accuracy: 0.001)
            for name in ["black-stone-bowl", "white-stone-bowl", "black-player-lid", "white-player-lid"] {
                let equipment = try XCTUnwrap(root.childNode(withName: name, recursively: true))
                XCTAssertEqual(equipment.position.y, PlayingEnvironment.spaceStation.equipmentSurfaceY + 0.165, accuracy: 0.001)
                XCTAssertLessThan(abs(equipment.position.x) + 4.5, 20)
            }
        }
        let consoles = root.childNode(withName: "environment-spaceStation", recursively: true)!.childNodes.filter {
            $0.name?.hasPrefix("station-switch-banks") == true
        }
        XCTAssertFalse(consoles.isEmpty)
        for console in consoles {
            XCTAssertTrue(console.castsShadow)
            XCTAssertGreaterThan(console.geometry?.sources(for: .vertex).first?.vectorCount ?? 0, 100)
        }
        manager.updateCapturedStones(black: 3, white: 2)
        let lid = try XCTUnwrap(root.childNode(withName: "black-player-lid", recursively: true))
        let captures = lid.childNodes.filter { $0.physicsBody?.type == .dynamic }
        XCTAssertFalse(captures.isEmpty)
        manager.updateEnvironment(.coffeeShop, flicker: false)
        XCTAssertTrue(root.childNode(withName: "black-player-lid", recursively: true) === lid)
        XCTAssertTrue(captures.allSatisfy { $0.parent === lid })
        XCTAssertNil(table.parent?.parent)
        manager.updateEnvironment(.spaceStation, flicker: false)
        XCTAssertTrue(root.childNode(withName: "station-tabletop", recursively: true) === table)
    }
}
