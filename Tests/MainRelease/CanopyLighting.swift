import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n",stderr); exit(1) }
}

@main struct CanopyLightingCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let manager=SceneManager3D(); manager.updateDebugSettings()
        manager.updateEnvironment(.tree,flicker:false)
        let player=SGFPlayer()
        player.load(game:SGFGame.from(tree:try SGFParser.parse(text:"(;SZ[19]AW[dd][pq][jj]AB[fc][dn][np])")))
        manager.updateStones(from:player.board.stones.map { RenderStone(id:$0.key,color:$0.value,offset:.zero) },lastMove:nil,moveIndex:0,settings:AppSettings.shared,animate:false)
        manager.updateCameraPosition(distance:29,rotationX:0.1,rotationY:0,panX:0,panY:0)
        let canopy=manager.scene.rootNode.childNode(withName:"canopy-shadow-caster",recursively:true)!
        let view=SCNView(frame:NSRect(x:0,y:0,width:1400,height:1000))
        view.scene=manager.scene; view.pointOfView=manager.cameraNode
        let renderer=SCNRenderer(device:view.device,options:nil)
        renderer.scene=manager.scene; renderer.pointOfView=manager.cameraNode
        func snapshot() -> NSBitmapImageRep {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime:0,with:view.bounds.size,antialiasingMode:.multisampling4X)
            return NSBitmapImageRep(data:renderer.snapshot(atTime:0,with:view.bounds.size,antialiasingMode:.multisampling4X).tiffRepresentation!)!
        }
        canopy.castsShadow=false
        let clear=snapshot()
        canopy.castsShadow=true
        let shaded=snapshot()
        func luminance(_ image:NSBitmapImageRep,_ world:SCNVector3) -> CGFloat {
            let point=view.projectPoint(world)
            let x=Int(point.x),y=image.pixelsHigh-1-Int(point.y)
            var total:CGFloat=0
            for dy in -4...4 { for dx in -4...4 {
                let c=image.colorAt(x:x+dx,y:y+dy)!.usingColorSpace(.sRGB)!
                total += c.redComponent*0.2126+c.greenComponent*0.7152+c.blueComponent*0.0722
            }}
            return total/81
        }
        var whiteChanges:[CGFloat]=[]
        for point in [SCNVector3(-6,1.46,-6*1.0773),SCNVector3(6,1.46,7*1.0773)] {
            let off=luminance(clear,point),on=luminance(shaded,point)
            print("White stone luminance: clear",off,"canopy",on)
            whiteChanges.append(off-on)
        }
        require(whiteChanges.max()! > 0.02,"Canopy shades actual white stones, not just a board overlay")
        let wood=SCNVector3(-6,1,-4.5)
        var woodChanges: [CGFloat] = []
        for x in stride(from: CGFloat(-10), through: 10, by: 2) {
            for z in stride(from: CGFloat(-10), through: 10, by: 2) {
                let point = SCNVector3(x,1,z)
                woodChanges.append(luminance(clear,point)-luminance(shaded,point))
            }
        }
        require(woodChanges.max()! > 0.02, "Canopy shades the wood")
        let shadedFraction = Double(woodChanges.filter { $0 > 0.02 }.count) / Double(woodChanges.count)
        let sunlitFraction = Double(woodChanges.filter { $0 < 0.01 }.count) / Double(woodChanges.count)
        print("Board coverage: shade", shadedFraction, "sunlight", sunlitFraction)
        require(shadedFraction > 0.60, "Connected canopy shade dominates the board, as on the surrounding ground")
        require(sunlitFraction > 0.04 && sunlitFraction < 0.35, "Small openings of real sunlight remain between shaded regions")
        let center = view.projectPoint(SCNVector3(0, 1, 0))
        let hitStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<40 {
            let hit = manager.hitTest(point: CGPoint(x: center.x, y: center.y), in: view)
            require(hit?.x == 9 && hit?.y == 9, "The invisible canopy cannot block board interaction")
        }
        print("40 board hit tests, ms:", (CFAbsoluteTimeGetCurrent() - hitStart) * 1000)
        var timings: [Double] = []
        for _ in 0..<12 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = renderer.snapshot(atTime: 0, with: view.bounds.size, antialiasingMode: .multisampling4X)
            timings.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        print("Canopy render/readback median ms:", timings.sorted()[6])
        canopy.castsShadow=false; canopy.isHidden=true
        let hidden=snapshot()
        require(abs(luminance(clear,wood)-luminance(hidden,wood))<0.005,"Invisible canopy does not cover camera-view pixels")
        let out=URL(fileURLWithPath:"/private/tmp/sgf-canopy-lighting")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        for (name,bitmap) in [("clear",clear),("canopy",shaded)] {
            try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name+".png"))
        }
        print("PASS: real canopy shadows fall on wood and white stones; canopy geometry stays invisible")
    }
}
