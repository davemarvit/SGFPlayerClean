import XCTest
import SceneKit
import simd
@testable import SGFPlayerNetworking

final class CameraCollisionTests: XCTestCase {
    func testZoomPanAndTiltStayOutsideAllBoardSizesAndStyles() throws {
        let manager=SceneManager3D()
        for kind in [PlayingEnvironment.tree,.coffeeShop,.laboratory,.retroFuture] {
            manager.updateEnvironment(kind,flicker:false,motion:false)
            for size in [9,13,19] {
                manager.updateBoardSize(size)
                let board=try XCTUnwrap(manager.scene.rootNode.childNode(withName:kind.usesTableBoard ? "kaya-table-board" : "kaya-floor-board",recursively:true))
                let bounds=board.geometry!.boundingBox
                for distance:CGFloat in [28,10,1,0] {
                    for tilt:Float in [-0.55,0,0.44,1.8] {
                        for yaw:Float in [-3,0,3] {
                            for pan:CGFloat in [-18,0,18] {
                                manager.updateCameraPosition(distance:distance,rotationX:tilt,rotationY:yaw,panX:pan,panY:-pan)
                                let p=manager.cameraNode.position
                                let within = p.x > bounds.min.x-1.19 && p.x < bounds.max.x+1.19
                                    && p.z > bounds.min.z-1.19 && p.z < bounds.max.z+1.19
                                    && p.y > bounds.min.y-1.19 && p.y < bounds.max.y+1.19
                                XCTAssertFalse(within,"Camera cannot enter padded slab: \(kind), \(size), \(p)")
                            }
                        }
                    }
                }
                manager.beginCameraRecenter(distance:SceneManager3D.seatedCameraDistance(boardSize:size),rotationX:0.44,reduceMotion:false)
                for frame in 0...66 {
                    manager.updateCameraArrival(elapsed:Double(frame)/60)
                    let p=manager.cameraNode.position
                    XCTAssertTrue(p.y>=2.19 || abs(p.x)>=bounds.max.x+1.19 || abs(p.z)>=bounds.max.z+1.19)
                }
                manager.finishCameraArrival()
            }
        }
    }

    func testSweptMovementStopsAtWoodAndAllowsMovingAway() {
        let low=SIMD3<Float>(-10,-7.6,-10.8), high=SIMD3<Float>(10,1,10.8)
        let from=SIMD3<Float>(-20,0.5,0), to=SIMD3<Float>(20,0.5,0)
        let stopped=SceneManager3D.safeCameraPosition(to,from:from,minimum:low,maximum:high)
        XCTAssertLessThanOrEqual(stopped.x,-11.2)
        XCTAssertGreaterThan(stopped.x,-11.3)
        XCTAssertEqual(SceneManager3D.safeCameraPosition(from,from:stopped,minimum:low,maximum:high),from)
        let overhead=SIMD3<Float>(0,25,0)
        XCTAssertEqual(SceneManager3D.safeCameraPosition(overhead,from:nil,minimum:low,maximum:high),overhead)
        let recovered=SceneManager3D.safeCameraPosition(.zero,from:nil,minimum:low,maximum:high)
        XCTAssertEqual(recovered.y,2.2,accuracy:0.0001)
    }
}
