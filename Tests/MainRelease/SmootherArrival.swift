import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct SmootherArrivalCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let settings = AppSettings.shared
        settings.showDropInAnimation = true
        let stones = (0..<260).map { i in
            RenderStone(id: BoardPosition(i / 19, i % 19), color: i % 2 == 0 ? .black : .white, offset: .zero)
        }
        if ProcessInfo.processInfo.environment["SGF_ARRIVAL_BENCHMARK"] == "1" {
            try benchmark(stones: stones)
            return
        }
        let manager = SceneManager3D(optimizesCameraArrival: true)
        manager.updateEnvironment(.moon, flicker: false, motion: false)
        manager.updateStones(from: stones, lastMove: nil, moveIndex: stones.count, settings: settings, animate: false)
        manager.updateCapturedStones(black: 12, white: 12, seed: 42)
        let view = UnifiedSCNView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        view.scene = manager.scene; view.pointOfView = manager.cameraNode
        view.antialiasingMode = .multisampling4X
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view; window.orderFront(nil)
        view.updateEnvironmentPlayback()
        require(!view.isPlaying && !view.rendersContinuously, "Fixture begins without environmental animation")
        let seated = manager.cameraNode.simdTransform
        let start = CACurrentMediaTime()
        manager.beginCameraArrival(reduceMotion: false, renderer: view)
        let opening = manager.cameraNode.simdTransform
        view.updateEnvironmentPlayback()
        require(view.isPlaying && view.rendersContinuously, "Settling survives routine view updates")
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        require(manager.cameraNode.simdTransform == opening, "Opening stays still while preparing")
        while manager.cameraNode.simdTransform == opening && CACurrentMediaTime() - start < 2 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        require(manager.cameraNode.simdTransform != opening, "Crowded scene starts within the bounded hold")
        require(CACurrentMediaTime() - start >= 1, "Departure retains a full one-second minimum")
        var meshes = 0
        manager.scene.rootNode.enumerateChildNodes { node, _ in
            guard node.name == "board-stone", let anchor = node.parent else { return }
            meshes += 1
            require(anchor.action(forKey: "stone-placement-drop") == nil && !node.hasActions,
                    "Existing board stones are already at rest")
            require(abs(anchor.presentation.position.y - 1) < 0.001, "Restored stones sit on the board")
        }
        require(meshes == stones.count, "All crowded-board stones remain visible")
        print("Crowded board departure after \(CACurrentMediaTime() - start) seconds; \(meshes) stones settled")
        manager.finishCameraArrival()
        require(manager.cameraNode.simdTransform == seated, "Skipping reaches the exact playing pose")
        require(!view.isPlaying && !view.rendersContinuously, "Skipping restores on-demand rendering")
        require(view.antialiasingMode == .multisampling4X, "Edge smoothing stays intact")
        // Cancel before the asynchronous prepare callback can arrive.
        manager.beginCameraArrival(reduceMotion: false, renderer: view)
        manager.setEnvironmentActive(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        require(!manager.isCameraArriving && manager.cameraNode.simdTransform == seated,
                "Late preparation cannot restart a canceled arrival")
        require(!view.isPlaying && !view.rendersContinuously, "Leaving restores playback flags")
        manager.setEnvironmentActive(true)
        manager.beginCameraArrival(reduceMotion: false, renderer: view)
        let displayClock = SCNNode(); displayClock.name = "station-display-clock"
        manager.scene.rootNode.addChildNode(displayClock)
        manager.finishCameraArrival()
        require(view.isPlaying && view.rendersContinuously, "Motion enabled during the tour remains enabled afterward")
        displayClock.removeFromParentNode(); view.updateEnvironmentPlayback()
        window.orderOut(nil)
        print("PASS: preparation, crowded-board settlement, bounded departure, skip, cancellation and rendering restoration")
    }

    @MainActor static func benchmark(stones: [RenderStone]) throws {
        let output = URL(fileURLWithPath: "/private/tmp/sgf-smoother-arrival")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for count in [0, stones.count] {
            for enabled in [false, true, true, false] {
                let manager = SceneManager3D(optimizesCameraArrival: enabled)
                manager.updateEnvironment(.gardenRoom, flicker: false, motion: false)
                manager.updateStones(from: Array(stones.prefix(count)), lastMove: nil, moveIndex: count,
                    settings: AppSettings.shared, animate: false)
                manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
                    rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
                let renderer = SCNRenderer(device: nil, options: nil)
                renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode; renderer.isPlaying = true
                manager.beginCameraArrival(reduceMotion: false)
                manager.updateCameraArrival(elapsed: 1)
                var renderTime = 0.0
                for (phase, from, span) in [("wide", 2.0, 5.0), ("near", 11.0, 1.9)] {
                    var timings: [Double] = []
                    for frame in 0..<24 {
                        manager.updateCameraArrival(elapsed: from + Double(frame) / 23 * span)
                        SCNTransaction.flush()
                        let start = CACurrentMediaTime()
                        let snapshot = renderer.snapshot(atTime: renderTime, with: CGSize(width: 960, height: 640),
                            antialiasingMode: .multisampling4X)
                        renderTime += 1.0 / 60
                        if frame >= 6 { timings.append((CACurrentMediaTime() - start) * 1000) }
                        if frame == 23 && count > 0, let tiff = snapshot.tiffRepresentation,
                           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                            try png.write(to: output.appendingPathComponent("\(phase)-\(enabled ? "optimized" : "original").png"))
                        }
                    }
                    timings.sort()
                    print("BENCH stones=\(count) optimized=\(enabled) phase=\(phase) median_ms=\(timings[timings.count/2]) p95_ms=\(timings[Int(Double(timings.count-1)*0.95)])")
                }
                manager.finishCameraArrival()
            }
        }
    }
}
