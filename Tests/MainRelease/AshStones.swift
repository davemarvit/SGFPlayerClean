import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

@main struct AshStonesPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = Bundle.main.resourceURL!
        let output = URL(fileURLWithPath: "/private/tmp/sgf-ash-stones-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let images = FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }.compactMap { url -> NSImage? in
            guard !url.path.contains("/Bowls2D/"), let image = NSImage(contentsOf: url) else { return nil }
            image.setName(url.path.contains("/Environments/") || url.lastPathComponent == TatamiTexture.assetName ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
            return image
        }
        let manager = SceneManager3D(); manager.updateDebugSettings()
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd];W[pd];B[dp];W[pp];B[cf];W[nc];B[fc];W[qn];B[cn];W[nq];B[qq];W[pq];B[qp];W[po])")))
        player.seek(to: player.maxIndex)
        manager.updateStones(from: player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) }, lastMove: nil, moveIndex: player.maxIndex, settings: AppSettings.shared, animate: false)
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        manager.updateCapturedStones(black: 3, white: 7)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        func save(_ name: String, time: Double = 3, size: CGSize = CGSize(width: 1400, height: 1000)) throws {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        for kind in PlayingEnvironment.allCases {
            manager.updateEnvironment(kind,flicker:false,motion:false)
            manager.updateCameraPosition(distance:28,rotationX:0.44,rotationY:0,panX:0,panY:0)
            try save(kind.rawValue+"-seated")
            manager.cameraNode.position = SCNVector3(18,11,21)
            manager.cameraNode.look(at:SCNVector3(10,0.5,3),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
            manager.cameraNode.camera!.fieldOfView = 51
            try save(kind.rawValue+"-black-stones")
        }
        manager.updateEnvironment(.monastery,flicker:false,motion:true)
        manager.cameraNode.position = SCNVector3(25,1,4)
        manager.cameraNode.look(at:SCNVector3(17,-4.1,-13),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
        manager.cameraNode.camera!.fieldOfView = 40
        for i in 0...480 { _ = renderer.snapshot(atTime: Double(i)/60, with: CGSize(width:64,height:64), antialiasingMode:.none) }
        try save("gray-ash",time:8)
        // The center of the vessel must expose ash, not the bronze shell.
        let ash = manager.scene.rootNode.childNode(withName:"nearby-incense-ash",recursively:true)!
        let target = ash.convertPosition(SCNVector3(0,6.59,0.8),to:nil)
        let p = renderer.projectPoint(target)
        let hits = renderer.hitTest(CGPoint(x:p.x,y:p.y),options:[.searchMode:SCNHitTestSearchMode.closest.rawValue,.ignoreHiddenNodes:true])
        precondition(hits.first?.node === ash,"Bronze must not cover the ash")
        for distance: CGFloat in [28,25.2,22.4] {
            manager.updateCameraPosition(distance:distance,rotationX:0.44,rotationY:0,panX:0,panY:0)
            manager.cameraNode.camera!.fieldOfView = 60
            try save("incense-framing-\(distance)",size:CGSize(width:1280,height:900))
            let smokeTop = ash.convertPosition(SCNVector3(0,15,0),to:nil)
            let tip = renderer.projectPoint(smokeTop)
            print("Incense smoke framing",distance,tip)
            precondition(tip.x > 20 && tip.x < 1260 && tip.y > 20 && tip.y < 880,"Modest zoom must leave room for smoke")
        }
        for kind in [PlayingEnvironment.coffeeShop,.laboratory,.monastery,.retroFuture] {
            manager.updateEnvironment(kind,flicker:false,motion:false)
            manager.updateCameraPosition(distance:28,rotationX:0.44,rotationY:0,panX:0,panY:0)
            manager.beginCameraArrival(reduceMotion:false)
            for elapsed in [0.0,2.5,4.0,6.5,9.0] {
                manager.updateCameraArrival(elapsed:elapsed)
                try save(kind.rawValue+"-arrival-\(elapsed)")
            }
        }
        manager.updateEnvironment(.coffeeShop,flicker:false,motion:false)
        manager.cameraNode.position = SCNVector3(-10,7,8)
        manager.cameraNode.look(at:SCNVector3(-21.5,1,17.5),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
        manager.cameraNode.camera!.fieldOfView = 38
        try save("asteroid-mug")
        var designs = Set<String>()
        manager.scene.rootNode.enumerateChildNodes { n, _ in
            for material in n.geometry?.materials ?? [] {
                if let name=material.name, name.hasPrefix("Lawrence Marvit") { designs.insert(name) }
            }
        }
        precondition(designs.count == 2,"Each mug must have its own Marvit design")
        print("PASS: exposed gray ash, incense framing, both mug designs, extended arrival and stone finishes in all environments")
        withExtendedLifetime(images) {}
    }
}
