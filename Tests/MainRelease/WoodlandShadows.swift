import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct WoodlandShadowCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: "/private/tmp/sgf-woodland-shadow-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let manager = SceneManager3D(); manager.updateDebugSettings()
        manager.updateEnvironment(.tree, flicker:false, motion:false)
        let grove = manager.scene.rootNode.childNode(withName:"nearby-ferns-and-moss",recursively:true)!
        var casters = [grove]
        grove.enumerateChildNodes { child, _ in casters.append(child) }
        let meshes = casters.filter { $0.geometry != nil }
        require(!meshes.isEmpty && meshes.allSatisfy { $0.castsShadow }, "Every batched woodland mesh casts shadows")
        let view = SCNView(frame:NSRect(x:0,y:0,width:1200,height:900))
        view.scene=manager.scene; view.pointOfView=manager.cameraNode
        let renderer = SCNRenderer(device:view.device,options:nil)
        renderer.scene=manager.scene; renderer.pointOfView=manager.cameraNode
        func snapshot() -> NSBitmapImageRep {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime:0,with:view.bounds.size,antialiasingMode:.multisampling4X)
            return NSBitmapImageRep(data:renderer.snapshot(atTime:0,with:view.bounds.size,antialiasingMode:.multisampling4X).tiffRepresentation!)!
        }
        manager.updateCameraPosition(distance:SceneManager3D.seatedCameraDistance(boardSize:19),
            rotationX:SceneManager3D.seatedCameraRotationX,rotationY:0,panX:0,panY:0)
        manager.beginCameraArrival(reduceMotion:false)
        for (name,time) in [("opening",0.0),("survey",6.0),("seated",13.0)] {
            manager.updateCameraArrival(elapsed:time)
            casters.forEach { $0.castsShadow=true }
            let shadowed = snapshot()
            casters.forEach { $0.castsShadow=false }
            let unshadowed = snapshot()
            var groundChanges=0
            for y in stride(from:0,to:shadowed.pixelsHigh,by:3) {
                for x in stride(from:0,to:shadowed.pixelsWide,by:3) {
                    let a=shadowed.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
                    let b=unshadowed.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
                    let change=(b.redComponent-a.redComponent)*0.2126+(b.greenComponent-a.greenComponent)*0.7152+(b.blueComponent-a.blueComponent)*0.0722
                    if change>0.012 {
                        let hits=view.hitTest(CGPoint(x:x,y:shadowed.pixelsHigh-1-y),options:[.ignoreHiddenNodes:true])
                        if hits.first(where: { $0.node.name != "canopy-shadow-caster" })?.node.name == "photographic-ground" { groundChanges += 1 }
                    }
                }
            }
            print("\(name): \(groundChanges) sampled ground pixels darkened by woodland shadows")
            require(groundChanges>30,"Plants cast visible shadows on the actual ground in \(name)")
            for (suffix,bitmap) in [("shadows",shadowed),("no-shadows",unshadowed)] {
                try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
        casters.forEach { $0.castsShadow=true }
        print("PASS: woodland shadow casting verified on ground throughout arrival and at the seated view")
    }
}
