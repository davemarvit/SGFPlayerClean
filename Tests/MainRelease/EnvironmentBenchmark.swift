import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

@main struct ShojiPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = URL(fileURLWithPath: "/Users/Dave/SGFPlayerClean/SGFPlayerClean/Assets")
        let output = URL(fileURLWithPath: "/private/tmp/sgf-environment-benchmark")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let manager = SceneManager3D(); manager.updateDebugSettings()
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd];W[pd];B[dp];W[pp];B[cf];W[nc];B[fc];W[qn];B[cn];W[nq];B[qq];W[pq];B[qp];W[po])")))
        player.seek(to: player.maxIndex)
        manager.updateStones(from: player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) }, lastMove: nil, moveIndex: player.maxIndex, settings: AppSettings.shared, animate: false)
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        renderer.isPlaying = true
        var time = 0.0
        for kind in PlayingEnvironment.allCases {
            let start = CFAbsoluteTimeGetCurrent()
            manager.updateEnvironment(kind, flicker: true)
            let buildMS = (CFAbsoluteTimeGetCurrent()-start)*1000
            var timings: [Double] = []
            for frame in 0..<100 {
                manager.updateCameraPosition(distance: 48, rotationX: 0.05, rotationY: Float(frame) * 0.009 - 0.45, panX: 0, panY: 0)
                SCNTransaction.flush()
                let start = CFAbsoluteTimeGetCurrent()
                _ = renderer.snapshot(atTime: time, with: CGSize(width: 960, height: 640), antialiasingMode: .multisampling4X)
                time += 1.0/60
                if frame >= 20 { timings.append((CFAbsoluteTimeGetCurrent()-start)*1000) }
            }
            timings.sort()
            print(kind.rawValue, "first scene construction", buildMS, "ms; warm median", timings[40], "ms; p95", timings[76], "ms")
        }

        // Paired sweeps isolate the incremental cost, alternating order to
        // reduce warmup/thermal bias. Snapshot time includes readback overhead.
        for kind in [PlayingEnvironment.tree,.cave] {
            var results: [Bool:[Double]] = [false:[],true:[]]
            for enabled in [false,true,true,false] {
                manager.updateEnvironment(kind,flicker:enabled)
                if kind == .tree {
                    manager.scene.rootNode.childNode(withName:"canopy-shadow-caster",recursively:true)?.isHidden = !enabled
                }
                for frame in 0..<80 {
                    manager.updateCameraPosition(distance:48,rotationX:0.05,rotationY:Float(frame)*0.009-0.45,panX:0,panY:0)
                    SCNTransaction.flush()
                    let start=CFAbsoluteTimeGetCurrent()
                    _ = renderer.snapshot(atTime:time,with:CGSize(width:960,height:640),antialiasingMode:.multisampling4X)
                    time += 1.0/60
                    if frame >= 20 { results[enabled]!.append((CFAbsoluteTimeGetCurrent()-start)*1000) }
                }
            }
            for enabled in [false,true] {
                let values=results[enabled]!.sorted()
                print("PAIRED",kind.rawValue,enabled ? "effect on" : "effect off",
                      "median",values[values.count/2],"ms; p95",values[Int(Double(values.count)*0.95)],"ms")
            }
        }

    }
}
