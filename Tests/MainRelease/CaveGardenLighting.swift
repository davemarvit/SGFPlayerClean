import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct CaveGardenLightingCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let manager = SceneManager3D(); manager.updateDebugSettings()
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text:
            "(;SZ[19]AB[dd][jd][pd][gj][mj][dp][jp][pp]AW[gd][md][dj][jj][pj][gp][mp])")))
        manager.updateStones(from: player.board.stones.map {
            RenderStone(id: $0.key, color: $0.value, offset: .zero)
        }, lastMove: nil, moveIndex: 0, settings: AppSettings.shared, animate: false)
        manager.updateEnvironment(.cave, flicker: true, motion: false)
        manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
            rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
        let root = manager.scene.rootNode
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        renderer.isPlaying = true
        func snapshot(_ time: Double = 0) -> NSBitmapImageRep {
            SCNTransaction.flush()
            let size = CGSize(width: 1200, height: 900)
            _ = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            return NSBitmapImageRep(data: renderer.snapshot(atTime: time, with: size,
                antialiasingMode: .multisampling4X).tiffRepresentation!)!
        }
        func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, threshold: CGFloat = 0.025) -> Int {
            var count = 0
            for y in stride(from: 0, to: 900, by: 2) {
                for x in stride(from: 0, to: 1200, by: 2) {
                    let c = a.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
                    let d = b.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
                    if abs(c.redComponent-d.redComponent)+abs(c.greenComponent-d.greenComponent)
                        + abs(c.blueComponent-d.blueComponent) > threshold { count += 1 }
                }
            }
            return count
        }
        let lamp = root.childNode(withName: "oil-lamp-light", recursively: true)!
        let flame = root.childNode(withName: "oil-lamp-flame", recursively: true)!
        require(lamp.worldPosition.y > 1 && lamp.worldPosition.y < 16, "Low light above the board produces long shadows independently of the visible lamp")
        require(abs(flame.position.x-19)<0.001 && abs(flame.position.y-11.45)<0.001 && abs(flame.position.z+16)<0.001, "Visible flame retains its seated framing")
        // Isolate the flame shader from the light's tiny intensity fluctuations.
        lamp.removeAction(forKey: "lamp-flicker")
        flame.removeAction(forKey:"flame-motion")
        let flameMaterial = flame.childNodes.first!.geometry!.firstMaterial!
        flameMaterial.setValue(Float(0),forKey:"flameTime")
        let firstFlame = snapshot(0)
        flameMaterial.setValue(Float(0.23),forKey:"flameTime")
        let moving = difference(firstFlame, snapshot(0.23))
        print("Flame changed samples:", moving)
        require(moving > 20, "Flame silhouette visibly moves in rendered pixels")
        manager.updateEnvironment(.cave, flicker: false, motion: false)
        let still = difference(snapshot(0.4), snapshot(0.63))
        require(still == 0, "Disabling flicker also freezes the flame silhouette")
        print("PASS: visible flame motion \(moving) samples; disabled motion \(still)")
        var stones: [SCNNode] = []
        root.enumerateChildNodes { node, _ in if node.name == "board-stone" { stones.append(node) } }
        require(stones.count == 15, "Distributed board fixture loaded")
        let baseline = snapshot(0.7)
        for sx in [-1,1] { for sz in [-1,1] {
            let quarter = stones.filter { $0.worldPosition.x * CGFloat(sx) > 0 && $0.worldPosition.z * CGFloat(sz) > 0 }
            require(!quarter.isEmpty, "Each quarter contains stones")
            quarter.forEach { $0.castsShadow = false }
            let changes = difference(baseline, snapshot(0.7), threshold:0.012)
            quarter.forEach { $0.castsShadow = true }
            require(changes > 5, "Stones cast visible shadows in quarter \(sx),\(sz)")
            print("PASS: cave quarter \(sx),\(sz) shadows: \(changes) samples")
        }}
        manager.updateEnvironment(.japaneseGarden, flicker: false, motion: false)
        let floor = root.childNode(withName: "photographic-ground", recursively: true)!
        require(floor.castsShadow && floor.boundingBox.max.y-floor.boundingBox.min.y > 0.25,
                "Rake lines have actual relief and participate in shadow rendering")
        let sun = root.childNode(withName: "SUN", recursively: true)!
        let forward = snapshot(1)
        sun.position = SCNVector3(20,31.4,20); sun.look(at: SCNVector3Zero)
        let reverse = snapshot(1)
        require(difference(forward,reverse) > 10000, "Gravel relief responds to the scene light direction")
        require(root.childNode(withName:"nearby-zen-maple-leaves",recursively:true) != nil,
                "Cutout maple leaves are bundled and visible")
        print("PASS: raised gravel relief responds to light; maple cutouts loaded")
    }
}
