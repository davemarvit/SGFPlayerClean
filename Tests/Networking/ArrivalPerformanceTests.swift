import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class ArrivalPerformanceTests: XCTestCase {
    private final class DeferredPreparationView: SCNView {
        override func prepare(_ objects: [Any], completionHandler: ((Bool) -> Void)? = nil) {}
    }
    private func sun(_ manager: SceneManager3D) -> SCNLight {
        manager.scene.rootNode.childNode(withName: "SUN", recursively: true)!.light!
    }

    func testCrowdedBoardAndUnsettledCapturesDoNotExtendOpening() {
        let manager = SceneManager3D(optimizesCameraArrival: true)
        let settings = AppSettings.shared
        let original = settings.showDropInAnimation
        defer { settings.showDropInAnimation = original; manager.finishCameraArrival() }
        settings.showDropInAnimation = true
        let stones = (0..<240).map { i in
            RenderStone(id: BoardPosition(i / 19, i % 19), color: i % 2 == 0 ? .black : .white, offset: .zero)
        }
        manager.updateStones(from: stones, lastMove: nil, moveIndex: 240, settings: settings, animate: false)
        manager.updateCapturedStones(black: 12, white: 12, seed: 42)
        let capture = manager.scene.rootNode.childNode(withName: "captured-black", recursively: true)!
        XCTAssertFalse(capture.physicsBody!.isResting)
        manager.beginCameraArrival(reduceMotion: false)
        let opening = manager.cameraNode.simdTransform
        manager.updateCameraArrival(elapsed: 0.99)
        XCTAssertEqual(manager.cameraNode.simdTransform, opening)
        manager.updateCameraArrival(elapsed: 1)
        XCTAssertEqual(manager.cameraNode.simdTransform, opening)
        manager.updateCameraArrival(elapsed: 1.1)
        XCTAssertNotEqual(manager.cameraNode.simdTransform, opening, "Captures must not extend the one-second opening")
        manager.updateCameraArrival(elapsed: SceneManager3D.cameraArrivalTotalDuration)
        XCTAssertFalse(manager.isCameraArriving)
    }

    func testGraphicsPreparationHasOnlyHalfASecondOfExtraGrace() {
        let manager = SceneManager3D(optimizesCameraArrival: true)
        let view = DeferredPreparationView()
        manager.beginCameraArrival(reduceMotion: false, renderer: view)
        let opening = manager.cameraNode.simdTransform
        manager.updateCameraArrival(elapsed: 1)
        manager.updateCameraArrival(elapsed: 1.49)
        XCTAssertEqual(manager.cameraNode.simdTransform, opening)
        manager.updateCameraArrival(elapsed: SceneManager3D.cameraArrivalMaximumHold)
        XCTAssertEqual(manager.cameraNode.simdTransform, opening)
        manager.updateCameraArrival(elapsed: 1.6)
        XCTAssertNotEqual(manager.cameraNode.simdTransform, opening, "An unresponsive renderer cannot stall the tour indefinitely")
        manager.updateCameraArrival(elapsed: SceneManager3D.cameraArrivalMaximumHold + SceneManager3D.cameraArrivalDuration)
        XCTAssertFalse(manager.isCameraArriving)
    }

    func testEmptyBoardStartsAfterNormalHoldAndShadowsReturnBeforeCloseApproach() {
        let manager = SceneManager3D(optimizesCameraArrival: true)
        let light = sun(manager), samples = sun(manager).shadowSampleCount
        let map = light.shadowMapSize
        manager.beginCameraArrival(reduceMotion: false)
        let opening = manager.cameraNode.simdTransform
        XCTAssertEqual(light.shadowSampleCount, 4)
        XCTAssertEqual(light.shadowMapSize, map)
        manager.updateCameraArrival(elapsed: 1)
        XCTAssertEqual(manager.cameraNode.simdTransform, opening)
        manager.updateCameraArrival(elapsed: 2)
        XCTAssertNotEqual(manager.cameraNode.simdTransform, opening)
        manager.updateCameraArrival(elapsed: 8)
        XCTAssertEqual(light.shadowSampleCount, 4)
        manager.updateCameraArrival(elapsed: 9.1)
        XCTAssertTrue(manager.isCameraArriving)
        XCTAssertEqual(light.shadowSampleCount, samples)
        manager.finishCameraArrival()
    }

    func testCancellationReducedMotionAndEnvironmentSwitchRestoreQuality() {
        let manager = SceneManager3D(optimizesCameraArrival: true)
        let light = sun(manager), samples = sun(manager).shadowSampleCount
        for cancel in [0, 1, 2] {
            manager.setEnvironmentActive(true)
            manager.beginCameraArrival(reduceMotion: false)
            if cancel == 0 { manager.finishCameraArrival() }
            if cancel == 1 { manager.setEnvironmentActive(false) }
            if cancel == 2 { manager.beginCameraArrival(reduceMotion: true) }
            XCTAssertEqual(light.shadowSampleCount, samples)
            XCTAssertFalse(manager.cameraNode.isPreparingOrArriving)
            let pose = manager.cameraNode.simdTransform
            manager.updateCameraArrival(elapsed: 5)
            XCTAssertEqual(manager.cameraNode.simdTransform, pose)
        }
        manager.beginCameraArrival(reduceMotion: false)
        manager.updateEnvironment(.moon, flicker: false)
        XCTAssertFalse(manager.isCameraArriving)
        XCTAssertEqual(light.shadowSampleCount, 16, "A new environment keeps its own full-quality settings")
    }

    func testDistantMeshesKeepColorAndSizeAndRollbackOmitsThem() {
        for enabled in [false, true] {
            let manager = SceneManager3D(optimizesCameraArrival: enabled)
            for size in [19, 9] {
                manager.updateBoardSize(size)
                manager.updateStones(from: [
                    RenderStone(id: BoardPosition(1, 1), color: .black, offset: .zero),
                    RenderStone(id: BoardPosition(2, 2), color: .white, offset: .zero)
                ], lastMove: nil, moveIndex: 2, settings: AppSettings.shared, animate: false)
                var count = 0
                manager.scene.rootNode.enumerateChildNodes { node, _ in
                    guard node.name == "board-stone", let mesh = node.geometry as? SCNSphere else { return }
                    count += 1
                    XCTAssertEqual(mesh.levelsOfDetail?.count ?? 0, enabled ? 2 : 0)
                    for level in mesh.levelsOfDetail ?? [] {
                        let simpler = level.geometry as! SCNSphere
                        XCTAssertEqual(simpler.radius, mesh.radius)
                        XCTAssertTrue(simpler.firstMaterial === mesh.firstMaterial)
                        XCTAssertLessThan(simpler.segmentCount, mesh.segmentCount)
                    }
                }
                XCTAssertEqual(count, 2)
            }
        }
    }
}
