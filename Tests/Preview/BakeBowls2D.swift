import AppKit
import SceneKit
import simd
@testable import SGFPlayerNetworking

/// Offline sprites from the same meshes, wood and settled poses as the 3D view.
@main struct BakeBowls2D {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output=URL(fileURLWithPath:CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        struct Layout: Decodable { let capacity:Int; let states:[[[Float]]]; let whiteStates:[[[Float]]] }
        let layout=try JSONDecoder().decode(Layout.self,from:Data(contentsOf:URL(fileURLWithPath:"SGFPlayerClean/Models/BowlLayouts.json")))
        let scene=SCNScene(); scene.background.contents=NSColor.clear
        let camera=SCNNode(); camera.camera=SCNCamera()
        camera.camera!.usesOrthographicProjection=true
        camera.camera!.orthographicScale=Double(GoEquipmentDimensions2D.bowlImageSpan / GoEquipmentDimensions2D.millimetresPerModelUnit / 2)
        camera.camera!.wantsHDR=true; camera.camera!.wantsExposureAdaptation=false
        camera.position=SCNVector3(0,20,5.5); camera.look(at:SCNVector3(0,1.8,0))
        scene.rootNode.addChildNode(camera)
        let sun=SCNNode(); sun.light=SCNLight(); sun.light!.type = .directional
        sun.light!.intensity=760; sun.light!.castsShadow=true
        sun.light!.shadowMapSize=CGSize(width:1024,height:1024)
        sun.light!.shadowRadius=2; sun.light!.shadowSampleCount=16
        sun.light!.shadowColor=NSColor(white:0,alpha:0.65)
        sun.light!.shadowBias=0.01; sun.light!.orthographicScale=8
        sun.position=SCNVector3(-6,12,-7); sun.look(at:SCNVector3Zero)
        scene.rootNode.addChildNode(sun)
        let ambient=SCNNode(); ambient.light=SCNLight(); ambient.light!.type = .ambient
        ambient.light!.intensity=50; scene.rootNode.addChildNode(ambient)
        scene.lightingEnvironment.contents=NSImage(size:NSSize(width:256,height:256),flipped:false) { rect in
            NSGradient(colors:[NSColor(white:0.65,alpha:1),NSColor(white:0.35,alpha:1),NSColor(white:0.95,alpha:1)])!.draw(in:rect,angle:90)
            return true
        }
        scene.lightingEnvironment.intensity=1.1
        let renderer=SCNRenderer(device:nil,options:nil)
        renderer.scene=scene; renderer.pointOfView=camera
        for white in (CommandLine.arguments.contains("--white-only") ? [true] : [false,true]) {
            // White stones need a broader, lighter penumbra at 2D display sizes.
            // Keep the black bowl's established lighting and all 3D materials intact.
            sun.light!.shadowRadius = white ? 6 : 2
            sun.light!.shadowSampleCount = white ? 32 : 16
            sun.light!.shadowColor = NSColor(white: 0, alpha: white ? 0.35 : 0.65)
            ambient.light!.intensity = white ? 100 : 50
            let material=SCNMaterial(); material.lightingModel = .physicallyBased
            material.diffuse.contents=NSColor(white:white ? 0.95 : 0.018,alpha:1)
            material.roughness.contents=white ? 0.57 : 0.41
            material.clearCoat.contents=white ? 0.86 : 0.1
            material.emission.contents=NSColor(white:white ? 0.11 : 0.025,alpha:1)
            let bowl=GoEquipment3D.makeBowl(isWhite:white,stoneMaterial:material)
            scene.rootNode.addChildNode(bowl)
            let stones=bowl.childNodes.filter { $0.name == "supply-stone" }
            let states = white ? layout.whiteStates : layout.states
            let turn=simd_quatf(angle:white ? 1.1 : 0,axis:SIMD3<Float>(0,1,0))
            let calibration = CommandLine.arguments.contains("--calibration")
            if calibration { bowl.geometry = nil }
            for count in (calibration ? [1] : CommandLine.arguments.contains("--sample") ? [0,40,90,stones.count] : Array(0...stones.count)) {
                try autoreleasepool {
                    for (i,stone) in stones.enumerated() {
                        stone.isHidden=i>=count
                        guard i<count else { continue }
                        let p=states[count][i]
                        stone.opacity=1
                        stone.simdPosition=turn.act(SIMD3(p[0],p[1],p[2]))
                        stone.simdOrientation=turn*simd_quatf(ix:p[3],iy:p[4],iz:p[5],r:p[6])
                        if calibration {
                            stone.position = SCNVector3(0, 1.8, 0)
                            stone.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0,1,0))
                        }
                    }
                    SCNTransaction.flush()
                    let image=renderer.snapshot(atTime:0,with:CGSize(width:512,height:512),antialiasingMode:.multisampling4X)
                    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
                    try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(white ? "white" : "black")-\(count).png"))
                }
            }
            bowl.removeFromParentNode()
            print("Baked \(stones.count+1) \(white ? "white" : "black") bowl states")
        }
    }
}
