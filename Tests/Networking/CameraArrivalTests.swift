import XCTest
import SceneKit
import simd
@testable import SGFPlayerNetworking

final class CameraArrivalTests: XCTestCase {
    func testSeatedWoodenSurfaceIsCenteredForEveryEnvironmentAndBoardSize() {
        let manager = SceneManager3D()
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            let x = CGFloat(size+1)*18/CGFloat(size-1)/2, z = x*1.0773
            let corners = [SCNVector3(-x,1,-z), SCNVector3(x,1,-z), SCNVector3(-x,1,z), SCNVector3(x,1,z)]
            for kind in PlayingEnvironment.allCases {
                manager.updateEnvironment(kind, flicker: false, motion: false)
                manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: size),
                    rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
                SCNTransaction.flush()
                let points = corners.map { view.projectPoint($0) }
                let xs = points.map(\.x), ys = points.map(\.y)
                XCTAssertEqual((xs.min()!+xs.max()!)/2,600,accuracy:0.5,"\(kind), \(size)")
                XCTAssertEqual((ys.min()!+ys.max()!)/2,400,accuracy:0.5,"\(kind), \(size)")
            }
        }
    }

    func testOpeningHoldsForOneSecondThenStartsWithoutADiscontinuity() {
        let manager = SceneManager3D()
        for kind in PlayingEnvironment.allCases {
            manager.updateEnvironment(kind, flicker: false)
            manager.beginCameraArrival(reduceMotion: false)
            let opening = manager.cameraNode.simdTransform
            let lens = manager.cameraNode.camera!.fieldOfView
            for elapsed in [0.0, 0.5, 0.999, 1.0] {
                manager.updateCameraArrival(elapsed: elapsed)
                XCTAssertTrue(manager.isCameraArriving)
                XCTAssertEqual(manager.cameraNode.simdTransform, opening)
                XCTAssertEqual(manager.cameraNode.camera!.fieldOfView, lens)
            }
            manager.updateCameraArrival(elapsed: 1.001)
            for column in 0..<4 {
                XCTAssertLessThan(simd_length(manager.cameraNode.simdTransform[column] - opening[column]), 0.0001)
            }
            manager.updateCameraArrival(elapsed: 1.5)
            XCTAssertNotEqual(manager.cameraNode.simdTransform, opening)
            manager.finishCameraArrival()
        }
    }

    func testSurveyPreservesWideLensAndJoinsDescentSmoothly() {
        let manager = SceneManager3D()
        let join = SceneManager3D.cameraArrivalHoldDuration + SceneManager3D.cameraArrivalSurveyDuration
        for kind in PlayingEnvironment.allCases {
            manager.updateEnvironment(kind, flicker: false)
            manager.beginCameraArrival(reduceMotion: false)
            let opening = manager.cameraNode.simdPosition
            let openingForward = manager.cameraNode.simdWorldFront
            let lens = manager.cameraNode.camera!.fieldOfView
            manager.updateCameraArrival(elapsed: join - 0.001)
            let before = manager.cameraNode.simdTransform
            XCTAssertGreaterThan(simd_distance(manager.cameraNode.simdPosition, opening), 25,
                "The survey must travel enough to reveal another part of the environment")
            let forward = manager.cameraNode.simdWorldFront
            let headingChange = acos(min(1, simd_dot(simd_normalize(SIMD2(openingForward.x, openingForward.z)),
                simd_normalize(SIMD2(forward.x, forward.z)))))
            XCTAssertGreaterThan(headingChange, .pi / 6, "Look around by at least thirty degrees")
            XCTAssertLessThan(headingChange / Float(SceneManager3D.cameraArrivalSurveyDuration), 0.15,
                "Extra coverage should retain a leisurely pace")
            XCTAssertEqual(manager.cameraNode.simdPosition.y, opening.y, accuracy: 0.001)
            XCTAssertEqual(manager.cameraNode.camera!.fieldOfView, lens, accuracy: 0.001)
            manager.updateCameraArrival(elapsed: join + 0.001)
            for column in 0..<4 {
                XCTAssertLessThan(simd_length(manager.cameraNode.simdTransform[column] - before[column]), 0.0001)
            }
            manager.finishCameraArrival()
        }
    }

    func testArrivalConvergesToTheEntirePlayingPoseBeforeCompletion() {
        let manager = SceneManager3D()
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        let corners = [SCNVector3(-9, 1, -9.696), SCNVector3(9, 1, -9.696),
                       SCNVector3(-9, 1, 9.696), SCNVector3(9, 1, 9.696)]
        var worstPixelJump: CGFloat = 0
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            for kind in PlayingEnvironment.allCases {
                manager.updateEnvironment(kind, flicker: false)
                manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: size),
                    rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
                manager.beginCameraArrival(reduceMotion: false)
                for frame in 0..<Int(SceneManager3D.cameraArrivalTotalDuration * 60) { manager.updateCameraArrival(elapsed: Double(frame) / 60) }
                SCNTransaction.flush()
                let before = corners.map { view.projectPoint($0) }
                manager.updateCameraArrival(elapsed: SceneManager3D.cameraArrivalTotalDuration)
                SCNTransaction.flush()
                let after = corners.map { view.projectPoint($0) }
                let jump = zip(before, after).map { hypot($0.x - $1.x, $0.y - $1.y) }.max()!
                worstPixelJump = max(worstPixelJump, jump)
                XCTAssertLessThan(jump, 0.1, "No visible completion snap in \(kind), \(size)×\(size)")
            }
        }
        print("Largest final-frame board displacement: \(worstPixelJump) pixels")
    }

    func testArrivalIsIndependentOfFrameHistoryAndStartsWithALevelHorizon() {
        let manager = SceneManager3D()
        for kind in PlayingEnvironment.allCases {
            manager.updateEnvironment(kind, flicker: false)
            // Also cover a destination with yaw and pan: these must be reached
            // during animation rather than corrected only by finishCameraArrival.
            manager.updateCameraPosition(distance: 34, rotationX: 0.7, rotationY: 0.6, panX: 3, panY: -2)
            let destination = manager.cameraNode.simdTransform
            manager.beginCameraArrival(reduceMotion: false)
            // SceneKit's float quaternion conversion can introduce thousandths
            // of a degree; this tolerance is still less than 0.006 degrees.
            XCTAssertEqual(manager.cameraNode.simdWorldRight.y, 0, accuracy: 0.0001)
            let forward = simd_normalize(kind.arrivalView.gaze - kind.arrivalView.eye)
            XCTAssertGreaterThan(simd_dot(manager.cameraNode.simdWorldFront, forward), 0.99999)
            manager.updateCameraArrival(elapsed: 1.5)
            let direct = manager.cameraNode.simdTransform
            manager.finishCameraArrival()
            manager.beginCameraArrival(reduceMotion: false)
            for frame in 0...180 { manager.updateCameraArrival(elapsed: Double(frame) / 120) }
            let stepped = manager.cameraNode.simdTransform
            for column in 0..<4 {
                XCTAssertLessThan(simd_length(direct[column] - stepped[column]), 0.00001,
                    "Dropped frames do not change camera orientation")
            }
            manager.updateCameraArrival(elapsed: SceneManager3D.cameraArrivalTotalDuration - 0.001)
            for column in 0..<4 {
                XCTAssertLessThan(simd_length(manager.cameraNode.simdTransform[column] - destination[column]), 0.0001,
                    "Yaw, tilt, roll and pan already match before handoff")
            }
            manager.finishCameraArrival()
        }
    }

    func testEveryEnvironmentDescendsWithoutMovingEquipmentOrLosingDestination() throws {
        let manager = SceneManager3D()
        let floor = try XCTUnwrap(manager.scene.rootNode.childNode(withName: "tatami-environment", recursively: true))
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            for kind in PlayingEnvironment.allCases {
                manager.updateEnvironment(kind, flicker: false)
                manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: size),
                    rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
                let destination = manager.cameraNode.simdTransform
                let floorTransform = floor.simdWorldTransform
                manager.beginCameraArrival(reduceMotion: false)
                XCTAssertTrue(manager.isCameraArriving)
                XCTAssertEqual(manager.cameraNode.camera!.fieldOfView, kind.arrivalFieldOfView, accuracy: 0.001)
                XCTAssertGreaterThan(manager.cameraNode.simdPosition.y, destination.columns.3.y)
                var height = manager.cameraNode.simdPosition.y
                for frame in 0..<Int(SceneManager3D.cameraArrivalTotalDuration * 60) {
                    manager.updateCameraArrival(elapsed: Double(frame) / 60)
                    let pose = manager.cameraNode.simdTransform
                    XCTAssertLessThanOrEqual(manager.cameraNode.simdPosition.y, height + 0.0001)
                    XCTAssertGreaterThan(manager.cameraNode.simdPosition.y, 1)
                    XCTAssertGreaterThan(manager.cameraNode.simdPosition.z, 10.8)
                    height = manager.cameraNode.simdPosition.y
                    // A routine scene update cannot snap the camera away from its path.
                    manager.updateCameraPosition(distance: 10, rotationX: 1, rotationY: 2, panX: 20, panY: 30)
                    XCTAssertEqual(manager.cameraNode.simdTransform, pose)
                    XCTAssertEqual(floor.simdWorldTransform, floorTransform)
                }
                manager.updateCameraArrival(elapsed: SceneManager3D.cameraArrivalTotalDuration)
                XCTAssertFalse(manager.isCameraArriving)
                XCTAssertEqual(manager.cameraNode.camera!.fieldOfView, 60, accuracy: 0.001)
                XCTAssertEqual(manager.cameraNode.simdTransform, destination)
                XCTAssertFalse(manager.finishCameraArrival())
            }
        }
    }

    func testSkippingReducedMotionAndLeavingCannotRestartAnOldFlight() {
        let manager = SceneManager3D()
        manager.updateCameraPosition(distance: 32, rotationX: 0.08, rotationY: 0, panX: 0, panY: 0)
        let destination = manager.cameraNode.simdTransform
        manager.beginCameraArrival(reduceMotion: true)
        XCTAssertFalse(manager.isCameraArriving)
        XCTAssertEqual(manager.cameraNode.simdTransform, destination)
        for fraction in [0.0, 0.3, 0.99] {
            manager.beginCameraArrival(reduceMotion: false)
            manager.updateCameraArrival(elapsed: fraction * SceneManager3D.cameraArrivalTotalDuration)
            XCTAssertTrue(manager.finishCameraArrival())
            XCTAssertEqual(manager.cameraNode.simdTransform, destination)
            manager.updateCameraArrival(elapsed: 1.5)
            XCTAssertEqual(manager.cameraNode.simdTransform, destination)
        }
        manager.beginCameraArrival(reduceMotion: false)
        manager.setEnvironmentActive(false)
        XCTAssertFalse(manager.isCameraArriving)
        XCTAssertEqual(manager.cameraNode.simdTransform, destination)
        manager.beginCameraArrival(reduceMotion: false)
        XCTAssertFalse(manager.isCameraArriving, "Late settings callbacks cannot animate a hidden view")
        manager.setEnvironmentActive(true)
        manager.beginCameraArrival(reduceMotion: false)
        manager.updateEnvironment(.moon, flicker: false)
        XCTAssertFalse(manager.isCameraArriving)
        XCTAssertEqual(manager.cameraNode.simdTransform, destination)
    }

    func testViewportChangesDuringFlightPreserveTheLensAndFinalFit() {
        let manager = SceneManager3D()
        manager.beginCameraArrival(reduceMotion: false)
        manager.updateCameraArrival(elapsed: 1)
        let pose = manager.cameraNode.simdTransform
        manager.updateCameraFieldOfView(85)
        XCTAssertGreaterThan(manager.cameraNode.camera!.fieldOfView, 85)
        XCTAssertEqual(manager.cameraNode.simdTransform, pose)
        manager.finishCameraArrival()
        XCTAssertEqual(manager.cameraNode.camera!.fieldOfView, 85, accuracy: 0.001)
    }

    func testRecenterGlidesFromPannedAndReversedViewsAndCanBeInterrupted() {
        let manager = SceneManager3D()
        let distance = SceneManager3D.seatedCameraDistance(boardSize: 19)
        let tilt = SceneManager3D.seatedCameraRotationX
        manager.updateCameraPosition(distance: distance, rotationX: tilt, rotationY: 0, panX: 0, panY: 0)
        let destination = manager.cameraNode.simdTransform
        for yaw: Float in [0.8, .pi, -.pi, 7 * .pi] {
            manager.updateCameraPosition(distance: 48, rotationX: -0.2, rotationY: yaw, panX: 12, panY: -6)
            let start = manager.cameraNode.simdTransform
            manager.beginCameraRecenter(distance: distance, rotationX: tilt, reduceMotion: false)
            XCTAssertEqual(manager.cameraNode.simdTransform, start, "No initial jump")
            XCTAssertTrue(manager.isCameraArriving)
            for frame in 1..<66 {
                manager.updateCameraArrival(elapsed: Double(frame) / 60)
                let position = manager.cameraNode.simdPosition
                XCTAssertTrue(position.x.isFinite && position.y.isFinite && position.z.isFinite)
                XCTAssertGreaterThan(position.y, 1, "Path clears the board even from the opposite side")
                XCTAssertGreaterThanOrEqual(simd_length(position), Float(distance) - 0.01)
                XCTAssertEqual(manager.cameraNode.camera!.fieldOfView, 60, accuracy: 0.001)
                if frame == 30 {
                    XCTAssertNotEqual(manager.cameraNode.simdTransform, start)
                    XCTAssertNotEqual(manager.cameraNode.simdTransform, destination)
                }
            }
            manager.updateCameraArrival(elapsed: SceneManager3D.cameraRecenterDuration)
            XCTAssertEqual(manager.cameraNode.simdTransform, destination)
            XCTAssertFalse(manager.isCameraArriving)
        }
        manager.updateCameraPosition(distance: 50, rotationX: 0.1, rotationY: 1, panX: 10, panY: 5)
        manager.beginCameraRecenter(distance: distance, rotationX: tilt, reduceMotion: true)
        XCTAssertEqual(manager.cameraNode.simdTransform, destination)
        XCTAssertFalse(manager.isCameraArriving)
        manager.updateCameraPosition(distance: 45, rotationX: 0.1, rotationY: 2, panX: 0, panY: 0)
        manager.beginCameraRecenter(distance: distance, rotationX: tilt, reduceMotion: false)
        manager.updateCameraArrival(elapsed: 0.4)
        XCTAssertTrue(manager.finishCameraArrival())
        manager.updateCameraArrival(elapsed: 0.5)
        XCTAssertEqual(manager.cameraNode.simdTransform, destination)
    }

    func testNewSeatEnlargesTheBoardAndReducesNearFarDistortion() {
        let manager = SceneManager3D()
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        func measurements() -> (ratio: CGFloat, area: CGFloat) {
            SCNTransaction.flush()
            let nearLeft = view.projectPoint(SCNVector3(-9, 1, 9.696))
            let nearRight = view.projectPoint(SCNVector3(9, 1, 9.696))
            let farLeft = view.projectPoint(SCNVector3(-9, 1, -9.696))
            let farRight = view.projectPoint(SCNVector3(9, 1, -9.696))
            let nearWidth = nearRight.x - nearLeft.x, farWidth = farRight.x - farLeft.x
            return (farWidth / nearWidth, (nearWidth + farWidth) / 2 * abs(farLeft.y - nearLeft.y))
        }
        manager.updateCameraPosition(distance: 32, rotationX: 0.08, rotationY: 0, panX: 0, panY: 0)
        let previous = measurements()
        manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
            rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
        let current = measurements()
        XCTAssertGreaterThan(current.ratio, previous.ratio + 0.06)
        XCTAssertGreaterThan(current.area, previous.area * 1.1)
    }
}
