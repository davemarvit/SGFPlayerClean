import XCTest
import SceneKit
@testable import QuietGo_iPad

@MainActor final class TabletCameraTests: XCTestCase {
    func testBoardFitsPortraitLandscapeAndNarrowWindowsWithoutClipping() throws {
        let manager = SceneManager3D()
        defer { manager.setEnvironmentActive(false) }
        manager.cameraNode.camera?.projectionDirection = .vertical
        for count in [9, 13, 19] {
            manager.updateBoardSize(count)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: count), rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
            let board = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "kaya-floor-board", recursively: true))
            let bounds = board.boundingBox
            let corners = [bounds.min.x, bounds.max.x].flatMap { x in
                [bounds.min.z, bounds.max.z].map { z in board.convertPosition(SCNVector3(x, bounds.max.y, z), to: nil) }
            }
            for size in [CGSize(width: 834, height: 970), CGSize(width: 914, height: 650), CGSize(width: 390, height: 700)] {
                let view = SCNView(frame: CGRect(origin: .zero, size: size))
                view.scene = manager.scene; view.pointOfView = manager.cameraNode
                let angle = TabletCameraFraming.fieldOfView(board: board, seatedTransform: manager.cameraNode.simdTransform, viewport: size)
                func projectedBounds() -> CGRect {
                    SCNTransaction.flush()
                    _ = view.snapshot() // Establish the renderer's actual viewport before projecting.
                    let points = corners.map { view.projectPoint($0) }
                    let x = points.map { CGFloat($0.x) }, y = points.map { CGFloat($0.y) }
                    return CGRect(x: x.min()!, y: y.min()!, width: x.max()! - x.min()!, height: y.max()! - y.min()!)
                }
                let ratio = size.width / size.height
                manager.updateCameraFieldOfView(ratio < 1 ? min(95, 60 / max(0.6, ratio)) : 60)
                let previous = projectedBounds()
                manager.updateCameraFieldOfView(angle)
                let fitted = projectedBounds()
                XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.03, dy: size.height * 0.03).contains(fitted), "All board edges must remain visible")
                XCTAssertGreaterThan(max(fitted.width / size.width, fitted.height / size.height), 0.82)
                if size.width > 800 {
                    XCTAssertGreaterThan(fitted.width * fitted.height, previous.width * previous.height * 1.25)
                    print("Tablet \(count) / \(size): board area increased \(Int((fitted.width * fitted.height / (previous.width * previous.height) - 1) * 100)) percent")
                }
            }
        }
    }

    func testViewportFittingPreservesTourAndUserCameraPose() {
        let c = TabletBoard3D.Coordinator(game: TabletGame(restore: false))
        defer { c.manager.setEnvironmentActive(false) }
        c.configureCamera(environment: .gardenRoom, active: true, recenter: 0, reduceMotion: false)
        c.manager.updateCameraArrival(elapsed: 4)
        let touring = c.manager.cameraNode.simdTransform
        c.updateViewport(CGSize(width: 834, height: 970))
        XCTAssertEqual(c.manager.cameraNode.simdTransform, touring)
        XCTAssertTrue(c.manager.isCameraArriving)
        c.manager.finishCameraArrival()
        c.distance = 38; c.ry = 0.4; c.px = 2; c.camera()
        let custom = c.manager.cameraNode.simdTransform
        c.updateViewport(CGSize(width: 914, height: 650))
        XCTAssertEqual(c.manager.cameraNode.simdTransform, custom)
        XCTAssertEqual(c.distance, 38); XCTAssertEqual(c.ry, 0.4); XCTAssertEqual(c.px, 2)
    }

    func testArrivalSurvivesRefreshAndRecenterGlidesFromActualPose() {
        let c = TabletBoard3D.Coordinator(game: TabletGame(restore: false))
        defer { c.manager.setEnvironmentActive(false) }
        c.configureCamera(environment: .gardenRoom, active: true, recenter: 0, reduceMotion: false)
        XCTAssertTrue(c.manager.isCameraArriving)
        let opening = c.manager.cameraNode.simdTransform
        c.manager.updateCameraArrival(elapsed: 3)
        let touring = c.manager.cameraNode.simdTransform
        XCTAssertNotEqual(touring, opening)
        c.configureCamera(environment: .gardenRoom, active: true, recenter: 0, reduceMotion: false)
        XCTAssertEqual(c.manager.cameraNode.simdTransform, touring, "Board updates must not restart or interrupt the tour")
        c.manager.updateCameraFieldOfView(85)
        XCTAssertTrue(c.manager.finishCameraArrival())
        let seated = c.manager.cameraNode.simdTransform
        XCTAssertEqual(c.manager.cameraNode.camera!.fieldOfView, 85, accuracy: 0.01)
        c.ry = 1; c.px = 3; c.distance = 45; c.camera()
        let start = c.manager.cameraNode.simdTransform
        c.configureCamera(environment: .gardenRoom, active: true, recenter: 1, reduceMotion: false)
        XCTAssertTrue(c.manager.isCameraArriving)
        XCTAssertEqual(c.manager.cameraNode.simdTransform, start, "Recenter must not jump at its start")
        c.manager.updateCameraArrival(elapsed: 0.5)
        XCTAssertNotEqual(c.manager.cameraNode.simdTransform, start)
        XCTAssertNotEqual(c.manager.cameraNode.simdTransform, seated)
        c.configureCamera(environment: .gardenRoom, active: true, recenter: 1, reduceMotion: false)
        c.manager.updateCameraArrival(elapsed: SceneManager3D.cameraRecenterDuration)
        XCTAssertFalse(c.manager.isCameraArriving)
        XCTAssertEqual(c.manager.cameraNode.simdTransform, seated)
        XCTAssertEqual(c.ry, 0); XCTAssertEqual(c.px, 0)
    }

    func testEnvironmentChangesReducedMotionAndLifecycle() {
        let c = TabletBoard3D.Coordinator(game: TabletGame(restore: false))
        defer { c.manager.setEnvironmentActive(false) }
        c.configureCamera(environment: .gardenRoom, active: false, recenter: 0, reduceMotion: false)
        XCTAssertFalse(c.manager.isCameraArriving)
        c.configureCamera(environment: .gardenRoom, active: true, recenter: 0, reduceMotion: false)
        XCTAssertTrue(c.manager.isCameraArriving, "Initial activation plays the tour")
        c.configureCamera(environment: .gardenRoom, active: false, recenter: 0, reduceMotion: false)
        XCTAssertFalse(c.manager.isCameraArriving)
        let seated = c.manager.cameraNode.simdTransform
        c.configureCamera(environment: .gardenRoom, active: true, recenter: 0, reduceMotion: false)
        XCTAssertFalse(c.manager.isCameraArriving, "Returning from background must not replay a cancelled tour")
        for environment in PlayingEnvironment.allCases where environment != .gardenRoom {
            c.configureCamera(environment: environment, active: true, recenter: 0, reduceMotion: false)
            XCTAssertTrue(c.manager.isCameraArriving, "Environment changes should showcase \(environment)")
            c.manager.updateCameraArrival(elapsed: SceneManager3D.cameraArrivalTotalDuration)
            XCTAssertFalse(c.manager.isCameraArriving)
            XCTAssertEqual(c.manager.cameraNode.simdTransform, seated)
        }
        c.configureCamera(environment: .gardenRoom, active: true, recenter: 0, reduceMotion: false)
        XCTAssertTrue(c.manager.isCameraArriving)
        c.configureCamera(environment: .gardenRoom, active: true, recenter: 0, reduceMotion: true)
        XCTAssertFalse(c.manager.isCameraArriving)
        XCTAssertEqual(c.manager.cameraNode.simdTransform, seated)
        c.configureCamera(environment: .moon, active: true, recenter: 0, reduceMotion: true)
        XCTAssertFalse(c.manager.isCameraArriving)
        c.ry = 1; c.camera()
        c.configureCamera(environment: .moon, active: true, recenter: 1, reduceMotion: true)
        XCTAssertFalse(c.manager.isCameraArriving)
        XCTAssertEqual(c.manager.cameraNode.simdTransform, seated)
    }
}
