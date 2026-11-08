#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SceneKit
import simd

/// Six-sun slab and traditional carved feet, scaled to a 42 cm wide goban.
/// The playing surface stays at y=1 so all game coordinates remain unchanged.
enum KayaFloorBoard {
    static let slabThickness: CGFloat = 8.6
    static let footHeight: CGFloat = 5.1
    static let floorY: CGFloat = 1 - slabThickness - footHeight - 0.015
    static let sceneryOffset: CGFloat = floorY + 1.015

    static func body(width: CGFloat, length: CGFloat, thickness: CGFloat = slabThickness) -> SCNGeometry {
        let x = width/2, z = length/2, top: CGFloat = 1, bottom = top-thickness
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uv: [CGPoint] = []
        var indices: [Int32] = []
        func face(_ points: [SCNVector3], normal: SCNVector3, horizontalGrain: Bool = false) {
            let start = Int32(vertices.count)
            vertices += points; normals += Array(repeating:normal,count:4)
            let coordinates = [CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:1,y:1),CGPoint(x:0,y:1)]
            // Long sides follow the trunk along the board's length. Mapping
            // the mesh itself keeps diffuse and bounced-light grain identical.
            uv += horizontalGrain ? coordinates.map { CGPoint(x:$0.y,y:$0.x) } : coordinates
            indices += [start,start+1,start+2,start,start+2,start+3]
        }
        face([SCNVector3(-x,top,z),SCNVector3(x,top,z),SCNVector3(x,top,-z),SCNVector3(-x,top,-z)],normal:SCNVector3(0,1,0))
        face([SCNVector3(-x,bottom,-z),SCNVector3(x,bottom,-z),SCNVector3(x,bottom,z),SCNVector3(-x,bottom,z)],normal:SCNVector3(0,-1,0))
        face([SCNVector3(-x,bottom,z),SCNVector3(x,bottom,z),SCNVector3(x,top,z),SCNVector3(-x,top,z)],normal:SCNVector3(0,0,1))
        face([SCNVector3(x,bottom,-z),SCNVector3(-x,bottom,-z),SCNVector3(-x,top,-z),SCNVector3(x,top,-z)],normal:SCNVector3(0,0,-1))
        face([SCNVector3(x,bottom,z),SCNVector3(x,bottom,-z),SCNVector3(x,top,-z),SCNVector3(x,top,z)],normal:SCNVector3(1,0,0),horizontalGrain:true)
        face([SCNVector3(-x,bottom,-z),SCNVector3(-x,bottom,z),SCNVector3(-x,top,z),SCNVector3(-x,top,-z)],normal:SCNVector3(-1,0,0),horizontalGrain:true)
        return SCNGeometry(sources:[.init(vertices:vertices),.init(normals:normals),.init(textureCoordinates:uv)],
            elements:stride(from:0,to:indices.count,by:6).map {
                SCNGeometryElement(indices:Array(indices[$0..<$0+6]),primitiveType:.triangles)
            })
    }

    static func addFeet(to board: SCNNode, width: CGFloat, length: CGFloat, material: SCNMaterial, stone: Bool = false) {
        // Maekawa ga60030 side and Yoshida 495 leg photographs: broad upper
        // body, narrow waist, compact lower fruit. About 10.7 × 7.6 cm on a
        // 42 cm goban, instead of the previous oversized teardrop silhouette.
        let profile: [(CGFloat,CGFloat)] = [(0,0.62),(0.18,0.86),(0.5,1.22),
            (0.9,1.55),(1.3,1.70),(1.55,1.66),(1.75,1.38),(1.93,0.95),
            (2.08,0.72),(2.22,0.76),(2.38,0.98),(2.65,1.24),(3.0,1.51),
            (3.4,1.69),(3.9,1.79),(4.4,1.80),(4.8,1.80),(5.1,1.80)]
        var vertices:[SCNVector3]=[], normals:[SCNVector3]=[], uv:[CGPoint]=[], indices:[Int32]=[]
        let segments = 96
        for (ring,p) in profile.enumerated() {
            let before=profile[max(0,ring-1)], after=profile[min(profile.count-1,ring+1)]
            let slope=(after.1-before.1)/max(0.01,after.0-before.0)
            for j in 0...segments {
                let a=CGFloat(j)*2 * .pi/CGFloat(segments)
                let depth: CGFloat = p.0 < 1.9 ? 0.075 : 0.035
                let facet: CGFloat = 1 - depth + depth*cos(a*8)
                let angularSlope = -8*depth*sin(a*8)/facet
                vertices.append(SCNVector3(cos(a)*p.1*facet,p.0,sin(a)*p.1*facet))
                let normal = simd_normalize(SIMD3<Float>(Float(cos(a)+angularSlope*sin(a)),Float(-slope),Float(sin(a)-angularSlope*cos(a))))
                normals.append(SCNVector3(normal))
                uv.append(CGPoint(x:CGFloat(j)/CGFloat(segments),y:p.0/footHeight))
                if ring<profile.count-1 && j<segments {
                    let k=Int32(ring*(segments+1)+j), n=k+Int32(segments+1)
                    indices += [k,n,k+1,k+1,n,n+1]
                }
            }
        }
        let geometry=SCNGeometry(sources:[.init(vertices:vertices),.init(normals:normals),.init(textureCoordinates:uv)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        let carved = material.copy() as! SCNMaterial
        carved.name = stone ? "limestone-carved-foot" : "kaya-carved-foot-wood"
        carved.emission.contents = carved.diffuse.contents; carved.emission.intensity = stone ? 0.015 : 0.09
        carved.shaderModifiers = [.surface: """
        #pragma body
        float angle = _surface.diffuseTexcoord.x * 6.2831853;
        float height = _surface.diffuseTexcoord.y;
        float ribs = 0.85 + 0.15*cos(angle*8.0);
        float shoulder = 1.0 - 0.25*exp(-pow((height-0.42)*18.0,2.0));
        float occlusion = ribs * shoulder;
        _surface.emission.rgb *= occlusion;
        _surface.diffuse.rgb *= mix(0.72,1.0,occlusion);
        """]
        carved.diffuse.intensity = 0.88
        carved.roughness.contents = stone ? 0.94 : 0.72
        geometry.materials=[carved]
        for x in [-width/2+2.9,width/2-2.9] { for z in [-length/2+3.1,length/2-3.1] {
            let foot=SCNNode(geometry:geometry); foot.name="kaya-carved-foot"
            foot.position=SCNVector3(x,floorY+0.015,z); foot.categoryBitMask=2
            board.addChildNode(foot)
        }}
    }
    /// A small baked contact-shadow map grounds the equipment without another
    /// shadow-map pass, including on photographically lit floor materials.
    static func contactShadow(width: CGFloat, length: CGFloat, surfaceY: CGFloat = floorY, equipmentX: CGFloat = 20, blackBowlZ: CGFloat = 7, blackLidZ: CGFloat = 4, hasFeet: Bool = true, hasMugs: Bool = false) -> SCNNode {
        let size=256
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
        let pixels=bitmap.bitmapData!
        for row in 0..<size { for col in 0..<size {
            let x=(CGFloat(col)/CGFloat(size)-0.5)*64, z=(CGFloat(row)/CGFloat(size)-0.5)*44
            var alpha: CGFloat=0.35*exp(-pow(abs(x)/(width*0.54),6)-pow(abs(z)/(length*0.54),6))
            if hasFeet { for fx in [-width/2+2.9,width/2-2.9] { for fz in [-length/2+3.1,length/2-3.1] {
                let a=0.55*exp(-((x-fx)*(x-fx)+(z-fz)*(z-fz))/1.9)
                alpha=1-(1-alpha)*(1-a)
            }}}
            for (bx,bz): (CGFloat,CGFloat) in [(-equipmentX,-9),(equipmentX,blackBowlZ),(-equipmentX,blackLidZ),(equipmentX,-6)] {
                let a=0.55*exp(-((x-bx)*(x-bx)+(z-bz)*(z-bz))/7)
                alpha=1-(1-alpha)*(1-a)
            }
            if hasMugs { for side: CGFloat in [-1,1] {
                let dx=x-side*21.5, dz=z+side*17.5
                let a=0.42*exp(-(dx*dx+dz*dz)/2.0)
                alpha=1-(1-alpha)*(1-a)
            }}
            let i=(row*size+col)*4
            let shade=UInt8((1-min(1,alpha))*255)
            pixels[i]=shade; pixels[i+1]=shade; pixels[i+2]=shade; pixels[i+3]=255
        }}
        let image = NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: size, height: size))
        let material=SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents=image; material.writesToDepthBuffer=false
        material.blendMode = .multiply
        let plane=SCNPlane(width:64,height:44); plane.materials=[material]
        let node=SCNNode(geometry:plane); node.eulerAngles.x = -.pi/2
        node.position.y = .init(surfaceY+0.025); node.castsShadow=false; node.categoryBitMask=2
        node.name="equipment-contact-shadows"
        node.renderingOrder=10
        return node
    }

}
