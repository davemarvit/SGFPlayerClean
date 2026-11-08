import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct StoneWobbleCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let settings = AppSettings.shared
        settings.showDropInAnimation = true
        let manager = SceneManager3D()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode; renderer.isPlaying = true
        var time = 0.0
        func frame() {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
            time += 1.0 / 240
        }
        func frames(_ count: Int) { for _ in 0..<count { frame() } }
        let point = BoardPosition(3, 4)
        for (size, color, environment) in [(19, Stone.black, PlayingEnvironment.gardenRoom),
                                           (9, .white, .gardenRoom), (19, .white, .spaceStation)] {
            manager.updateEnvironment(environment, flicker: false, motion: false)
            manager.updateBoardSize(size)
            manager.updateStones(from: [], lastMove: nil, moveIndex: 0, settings: settings, animate: false)
            let stones = [RenderStone(id: point, color: color, offset: CGPoint(x: 0.08, y: -0.06))]
            manager.updateStones(from: stones, lastMove: point, moveIndex: 1, settings: settings, settleOnLanding: true)
            let mesh = manager.scene.rootNode.childNode(withName: "board-stone", recursively: true)!
            let anchor = mesh.parent!
            let restAngles = mesh.eulerAngles, restPosition = mesh.position, geometry = mesh.geometry
            let restOrientation = mesh.simdOrientation
            let cell = CGFloat(18) / CGFloat(size - 1)
            let targetX = (CGFloat(point.col) - CGFloat(size - 1) / 2 + 0.08) * cell
            let targetZ = (CGFloat(point.row) - CGFloat(size - 1) / 2 - 0.06) * cell * 1.0773
            var sawPositive = false, sawNegative = false
            var largestTilt: CGFloat = 0
            var firstRock: Double?, lastRock: Double?
            let start = time
            for index in 0..<Int((environment.stoneDropDuration + 0.4) * 240) {
                frame()
                let pose = mesh.presentation
                let a = anchor.presentation.position
                let up = pose.simdOrientation.act(SIMD3<Float>(0, 1, 0))
                let tilt = atan2(CGFloat(hypot(up.x, up.z)), CGFloat(up.y))
                largestTilt = max(largestTilt, tilt)
                if a.y > 1.001 {
                    require(tilt < 0.0001, "Stone stays level during the fall")
                }
                if tilt > 0.0001 {
                    if firstRock == nil { firstRock = time - start }
                    lastRock = time - start
                    require(abs(a.y - 1) < 0.001 && abs(a.x - targetX) < 0.001 && abs(a.z - targetZ) < 0.001,
                            "Wobble occurs only after landing, with no anchor drift or bounce")
                    sawPositive = sawPositive || up.z > 0.0001
                    sawNegative = sawNegative || up.z < -0.0001
                }
                require(abs(pose.position.x) < 0.0001 && abs(pose.position.z) < 0.0001,
                        "Stone center never shuffles sideways")
                require(pose.position.y >= restPosition.y - 0.0001 && pose.position.y < restPosition.y + cell * 0.008,
                        "Contact correction remains minute, without a visible hop")
                let radius = (geometry as! SCNSphere).radius
                let sy = CGFloat(pose.scale.y)
                let support = radius * sqrt(max(0, 1 - (1 - sy * sy) * CGFloat(up.y * up.y)))
                require(pose.position.y + 0.0001 >= support, "Tilted stone stays above the board surface")
                require(mesh.geometry === geometry && (tilt < 0.001 || abs((pose.simdOrientation * restOrientation.inverse).axis.y) < 0.001),
                        "Wobble preserves the stone finish and shell orientation")
                // Frequent ordinary board publications must not restart the settle.
                if index % 7 == 0 {
                    manager.updateStones(from: stones, lastMove: point, moveIndex: 1, settings: settings, settleOnLanding: true)
                }
            }
            require(sawPositive && sawNegative && largestTilt > .pi / 60 && largestTilt < .pi / 30,
                    "One slight rock and weaker return reach a readable three-to-six-degree tilt")
            require(firstRock! >= environment.stoneDropDuration && lastRock! - firstRock! < 0.30,
                    "Wobble begins at contact and finishes in about 280 ms, including the slow space-station drop")
            require(mesh.action(forKey: "stone-landing-wobble") == nil &&
                    abs(mesh.eulerAngles.x) < 0.00001 && abs(mesh.eulerAngles.z) < 0.00001 && mesh.position.y == restPosition.y,
                    "Stone returns exactly to its resting pose; updates do not retrigger it")

            // Scrubbing and Reduce Motion must cancel a partially completed rock.
            for reduceMotion in [false, true] {
                manager.updateStones(from: [], lastMove: nil, moveIndex: 0, settings: settings, animate: false)
                manager.updateStones(from: stones, lastMove: point, moveIndex: 1, settings: settings, settleOnLanding: true)
                let moving = manager.scene.rootNode.childNode(withName: "board-stone", recursively: true)!
                frames(Int((environment.stoneDropDuration + 0.045) * 240))
                require(hypot(moving.presentation.eulerAngles.x, moving.presentation.eulerAngles.z) > 0.001,
                        "Cancellation fixture interrupts an actual tilt")
                manager.updateStones(from: stones, lastMove: point, moveIndex: 1, settings: settings,
                    animate: reduceMotion, settleOnLanding: !reduceMotion)
                frames(4)
                require(!moving.hasActions && abs(moving.eulerAngles.x) < 0.00001 && abs(moving.eulerAngles.z) < 0.00001 && moving.position.y == restPosition.y,
                        "Scrubbing or Reduce Motion clears any residual tilt and lift")
            }
            for animate in [false, true] {
                manager.updateStones(from: [], lastMove: nil, moveIndex: 0, settings: settings, animate: false)
                settings.showDropInAnimation = !animate
                manager.updateStones(from: stones, lastMove: point, moveIndex: 1, settings: settings, animate: animate, settleOnLanding: true)
                let instant = manager.scene.rootNode.childNode(withName: "board-stone", recursively: true)!
                require(!instant.hasActions && !instant.parent!.hasActions, "Instant placement and disabled animations never wobble")
                settings.showDropInAnimation = true
            }
        }
        print("PASS: rendered contact-only wobble, damped reversal, visible three-to-six-degree tilt, stable center/finish, no clipping or bounce, exact rest, repeated updates, 9x9/19x19, both colors, normal/slow drop, scrubbing, Reduce Motion and animation preference")
        try liveWobble()
    }

    @MainActor static func liveWobble() throws {
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.analysisEnabled = false
        AppSettings.shared.isMuted = true; AppSettings.shared.environment3D = .gardenRoom
        let app = AppModel(); app.aiAnalysisEnabled = false; app.newLocalGame(); app.viewMode = .view3D
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = NSHostingView(rootView: ContentView3D().environmentObject(app))
        window.orderFront(nil)
        func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        settle(0.5)
        let live = UnifiedInteractiveSceneView.lastActiveView as! UnifiedSCNView
        _ = live.finishCameraArrival?(); settle(0.1)
        let projected = live.projectPoint(SCNVector3(0, 1, 0))
        live.onInteraction?(.click, CGPoint(x: projected.x, y: projected.y))
        app.boardVM!.syncState()
        let mesh = live.scene!.rootNode.childNode(withName: "board-stone", recursively: true)!
        var peak: Float = 0
        let end = Date().addingTimeInterval(0.8)
        while Date() < end {
            settle(1.0 / 120)
            let up = mesh.presentation.simdOrientation.act(SIMD3<Float>(0, 1, 0))
            peak = max(peak, atan2(hypot(up.x, up.z), up.y))
        }
        require(peak > .pi / 90, "Production garden-room view actually renders a visible wobble (peak \(peak), playing \(live.isPlaying))")
        require(mesh.action(forKey: "stone-landing-wobble") == nil && abs(mesh.eulerAngles.x) < 0.0001,
                "Live view settles without forced snapshots or continuous rendering")
        print("PASS: production garden-room click visibly wobbles and settles under its real render policy; peak degrees \(peak * 180 / .pi)")
    }
}
