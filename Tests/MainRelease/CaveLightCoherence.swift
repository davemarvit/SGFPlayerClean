import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n",stderr); exit(1) }
}

@main struct CaveLightCoherence {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        // Exercise real startup: updateDebugSettings removes the legacy fill
        // lights and previously concealed the production-only washed-out cave.
        let manager = SceneManager3D()
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text:
            "(;SZ[19]AB[dd][jd][pd][gj][mj][dp][jp][pp]AW[gd][md][dj][jj][pj][gp][mp])")))
        manager.updateStones(from: player.board.stones.map {
            RenderStone(id:$0.key,color:$0.value,offset:.zero)
        },lastMove:nil,moveIndex:0,settings:AppSettings.shared,animate:false)
        manager.updateEnvironment(.cave,flicker:false,motion:false)
        manager.updateCameraPosition(distance:SceneManager3D.seatedCameraDistance(boardSize:19),
            rotationX:SceneManager3D.seatedCameraRotationX,rotationY:0,panX:0,panY:0)
        let root = manager.scene.rootNode
        let lamp = root.childNode(withName:"oil-lamp-light",recursively:true)!
        let sun = root.childNode(withName:"SUN",recursively:true)!
        for name in ["AMB_BOARD", "AMB_STONE"] {
            let fill = root.childNode(withName: name, recursively: true)!.light!
            let color = (fill.color as! NSColor).usingColorSpace(.sRGB)!
            require(color.redComponent <= 0.019, "Startup \(name) cannot wash out cave shadows")
        }
        require(sun.light!.intensity == 0 && manager.scene.lightingEnvironment.intensity == 0,
            "Cave has no competing overhead or sky-reflection illumination")
        let emission = manager.stoneMaterial(isWhite:true).emission.contents as! NSColor
        require(emission.usingColorSpace(.sRGB)!.redComponent == 0,"White stones do not glow through their shadows")
        var stones: [SCNNode] = []
        root.enumerateChildNodes { n,_ in if n.name == "board-stone" { stones.append(n) } }
        require(stones.count == 15,"Distributed stone fixture loaded")
        let renderer = SCNRenderer(device:nil,options:nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        let width = 1200, height = 900
        func snapshot() -> NSBitmapImageRep {
            SCNTransaction.flush()
            let size = CGSize(width:width,height:height)
            _ = renderer.snapshot(atTime:0,with:size,antialiasingMode:.multisampling4X)
            return NSBitmapImageRep(data:renderer.snapshot(atTime:0,with:size,antialiasingMode:.multisampling4X).tiffRepresentation!)!
        }
        func pixel(_ world: SCNVector3) -> SIMD2<Double> {
            let p = renderer.projectPoint(world)
            return SIMD2(Double(p.x),Double(height)-1-Double(p.y))
        }
        func luminance(_ image: NSBitmapImageRep,_ x: Int,_ y: Int) -> Double {
            let c = image.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
            return Double(c.redComponent*0.2126+c.greenComponent*0.7152+c.blueComponent*0.0722)
        }
        let baseline = snapshot()
        for (index,stone) in stones.enumerated() {
            let center = stone.worldPosition
            let surface = SCNVector3(center.x,1,center.z)
            let base = pixel(surface)
            let radius = CGFloat((stone.geometry as! SCNSphere).radius)
            let screenRadius = simd_length(pixel(SCNVector3(center.x+radius,1,center.z))-base)
            let away = simd_normalize(SIMD3<Float>(Float(center.x-lamp.worldPosition.x),0,Float(center.z-lamp.worldPosition.z)))
            let direction = simd_normalize(pixel(SCNVector3(surface.x+CGFloat(away.x),1,surface.z+CGFloat(away.z)))-base)
            stone.castsShadow = false
            let unshadowed = snapshot()
            stone.castsShadow = true
            var weight = 0.0, centroid = SIMD2<Double>.zero, farthest = 0.0
            let reach = screenRadius*7
            for y in max(0,Int(base.y-reach))...min(height-1,Int(base.y+reach)) {
                for x in max(0,Int(base.x-reach))...min(width-1,Int(base.x+reach)) {
                    let delta = SIMD2(Double(x),Double(y))-base
                    // Ignore the stone itself and measure the cast shadow on the slab.
                    if simd_length(delta)<screenRadius*1.15 { continue }
                    let change = luminance(unshadowed,x,y)-luminance(baseline,x,y)
                    if change > 0.018 {
                        weight += change; centroid += delta*change
                        farthest = max(farthest,simd_dot(delta,direction))
                    }
                }
            }
            require(weight>0.5,"Stone \(index) has a visible cast shadow")
            let alignment = simd_dot(simd_normalize(centroid),direction)
            let length = farthest/(screenRadius*2)
            require(alignment>0.90,"Stone \(index) shadow points away from the common lamp")
            require(length>0.85,"Stone \(index) shadow extends beyond a short contact patch")
            print("PASS stone",index,"shadow direction",alignment,"length in stone diameters",length)
        }
        // With the source off, no substitute highlight source may remain.
        lamp.light!.intensity = 0
        let dark = snapshot()
        for stone in stones {
            let p = pixel(stone.worldPosition), r = 10
            var peak = 0.0
            for y in Int(p.y)-r...Int(p.y)+r { for x in Int(p.x)-r...Int(p.x)+r {
                if hypot(Double(x)-p.x,Double(y)-p.y)<Double(r) {
                    peak = max(peak,luminance(dark,x,y))
                }
            }}
            let white = stone.geometry!.firstMaterial === manager.stoneMaterial(isWhite:true)
            require(peak < (white ? 0.10 : 0.035),
                "Both stone colors remain dark when the lamp is off, including normal startup ambient")
        }
        lamp.light!.intensity = PlayingEnvironmentScene.caveLampIntensity
        for size in [9,13,19] {
            manager.updateBoardSize(size)
            manager.updateDebugSettings()
            let resizedEmission = manager.stoneMaterial(isWhite:true).emission.contents as! NSColor
            require(resizedEmission.usingColorSpace(.sRGB)!.redComponent == 0,
                "Board resizing and settings updates preserve unlit white stones")
            require(sun.light!.intensity == 0 && manager.scene.lightingEnvironment.intensity == 0,
                "Board resizing and settings updates preserve the single cave light")
        }
        manager.updateEnvironment(.japaneseGarden,flicker:false,motion:false)
        require(sun.light!.intensity>0 && manager.scene.lightingEnvironment.intensity>0,
            "Leaving the cave restores daylight and environment reflections")
        let restored = manager.stoneMaterial(isWhite:true).emission.contents as! NSColor
        require(restored.usingColorSpace(.sRGB)!.redComponent>0,"Normal stone fill is restored outside the cave")
        print("PASS: one cave source, long coherent shadows on every stone, other environments restored")
    }
}
