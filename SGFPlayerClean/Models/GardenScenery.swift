#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SceneKit
import simd

/// Small, entirely static garden meshes. Flattening groups all repeated leaves
/// by material; there are no physics bodies, extra lights, or shadow-map casters.
enum GardenScenery {
    private static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        // Simulate diffuse daylight without adding a shadow-casting light.
        m.emission.contents = m.diffuse.contents
        m.emission.intensity = 0.42
        return m
    }
    private static let moss = material(0.28, 0.36, 0.17)
    private static let grass = material(0.38, 0.43, 0.23)
    private static let gravel = material(0.56, 0.54, 0.44)
    private static let rocks = material(0.39, 0.42, 0.39)
    private static let bark = material(0.28, 0.22, 0.15)
    private static let fence = material(0.37, 0.33, 0.23)
    private static let foliage: [SCNMaterial] = (0..<3).map { _ in
        let m=SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents=EnvironmentMaterials.image("leaf-color.png") ?? NSColor.systemGreen
        m.roughness.contents=0.48; m.isDoubleSided=true
        m.emission.contents=m.diffuse.contents; m.emission.intensity=0.09
        return m
    }
    private static let pot = material(0.46, 0.53, 0.48)
    private static let soil = material(0.15, 0.12, 0.08)

    private static let rockMesh: SCNGeometry = {
        let rings = 14, segments = 24
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        for ring in 0...rings {
            let theta = CGFloat(ring) * .pi / CGFloat(rings)
            for segment in 0...segments {
                let phi = CGFloat(segment) * 2 * .pi / CGFloat(segments)
                let ripple: CGFloat = 0.10 * sin(phi * 3 + theta * 2) * sin(theta)
                let detail: CGFloat = 0.06 * cos(phi * 5 - theta * 3) * sin(theta)
                let radius: CGFloat = 1 + ripple + detail
                let direction = SCNVector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
                vertices.append(SCNVector3(CGFloat(direction.x) * radius, CGFloat(direction.y) * radius, CGFloat(direction.z) * radius))
                normals.append(direction)
                if ring < rings && segment < segments {
                    let a = Int32(ring * (segments + 1) + segment), b = a + Int32(segments + 1)
                    indices += [a,a+1,b, a+1,b+1,b]
                }
            }
        }
        return SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }()

    private struct Random {
        var value: UInt64 = 71423
        mutating func unit() -> CGFloat {
            value = value &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(value >> 11) / 9007199254740992
        }
    }

    @discardableResult private static func add(_ geometry: SCNGeometry, material: SCNMaterial,
        at position: SCNVector3, to root: SCNNode) -> SCNNode {
        geometry.materials = [material]
        let n = SCNNode(geometry: geometry); n.position = position
        root.addChildNode(n)
        return n
    }

    private static func ellipsoid(at p: SCNVector3, size: SCNVector3, material: SCNMaterial, to root: SCNNode) {
        let sphere = SCNSphere(radius: 1); sphere.segmentCount = 24
        let geometry = material === rocks ? rockMesh : sphere
        add(geometry, material: material, at: p, to: root).scale = size
    }

    private static func branch(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: CGFloat,
        material: SCNMaterial = bark, root: SCNNode) {
        let delta = b - a
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(simd_length(delta)))
        cylinder.radialSegmentCount = 7
        let n = add(cylinder, material: material, at: SCNVector3((a + b) / 2), to: root)
        n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
    }

    /// A curved, pointed leaf with a raised midrib; reused for all foliage.
    private static let leaf: SCNGeometry = {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        for row in 0...8 {
            let t = CGFloat(row) / 8
            let width = pow(sin(.pi * t), 0.75) * 0.38
            let bend = sin(.pi * t) * 0.06 - pow(t, 4) * 0.18
            vertices += [SCNVector3(-width, bend, t),
                SCNVector3(0, bend + sin(.pi * t) * 0.10, t), SCNVector3(width, bend, t)]
            if row < 8 {
                let a = Int32(row * 3)
                indices += [a,a+3,a+1, a+1,a+3,a+4, a+1,a+4,a+2, a+2,a+4,a+5]
            }
        }
        var averaged = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[i]), b = Int(indices[i+1]), c = Int(indices[i+2])
            let normal = simd_cross(SIMD3<Float>(vertices[b]) - SIMD3<Float>(vertices[a]),
                SIMD3<Float>(vertices[c]) - SIMD3<Float>(vertices[a]))
            for index in [a,b,c] { averaged[index] += normal }
        }
        let normals = averaged.map { SCNVector3(simd_normalize($0)) }
        let uv = (0...8).flatMap { row in (0...2).map { col in CGPoint(x:CGFloat(col)/2,y:CGFloat(row)/8) } }
        return SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals), .init(textureCoordinates: uv)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }()

    private static let leafMeshes: [SCNGeometry] = foliage.map { color in
        let mesh = leaf.copy() as! SCNGeometry
        color.isDoubleSided = true
        mesh.materials = [color]
        return mesh
    }

    static func makeGarden(includeGround: Bool = true) -> SCNNode {
        let garden = SCNNode()
        var random = Random()
        if includeGround {
            add(SCNBox(width: 142, height: 0.25, length: 105, chamferRadius: 0), material: moss,
                at: SCNVector3(0, -0.87, -87), to: garden)
        }
        // Low moss mounds and a quiet gravel bed underneath the stones.
        ellipsoid(at: SCNVector3(-6, -0.64, -66), size: SCNVector3(28, 0.14, 31), material: gravel, to: garden)
        for i in 0..<32 {
            let x = (random.unit() < 0.5 ? -1 : CGFloat(1)) * (26 + random.unit() * 32)
            let z = -43 - random.unit() * 85
            let radius = 3 + random.unit() * 7
            ellipsoid(at: SCNVector3(x, -0.7, z), size: SCNVector3(radius, 0.3 + random.unit() * 0.8, radius * 0.7),
                material: i % 3 == 0 ? grass : moss, to: garden)
        }
        for i in 0..<8 {
            let z = CGFloat(-41 - i * 7)
            let x = sin(CGFloat(i) * 0.52) * 10 - 5
            ellipsoid(at: SCNVector3(x, -0.25, z), size: SCNVector3(3.1, 0.65, 2.2), material: rocks, to: garden)
        }
        for (x, z, scale): (CGFloat, CGFloat, CGFloat) in [(-15,-57,4.3), (-10,-62,2.7), (23,-70,5.5), (28,-75,3.6)] {
            ellipsoid(at: SCNVector3(x, scale * 0.45 - 0.7, z), size: SCNVector3(scale, scale * 0.8, scale * 0.72), material: rocks, to: garden)
        }
        // A slatted boundary gives the garden depth without a skybox or reflections.
        for x in stride(from: CGFloat(-68), through: 68, by: 4) {
            add(SCNBox(width: 3.7, height: 21, length: 0.65, chamferRadius: 0), material: fence,
                at: SCNVector3(x, 9.5, -122), to: garden)
        }
        for y: CGFloat in [3, 16] {
            add(SCNBox(width: 140, height: 0.8, length: 0.9, chamferRadius: 0), material: bark,
                at: SCNVector3(0, y, -121.5), to: garden)
        }
        // A lightly branching tree, with layered clusters rather than a flat backdrop.
        branch(from: SIMD3(16,-0.7,-78), to: SIMD3(14,15,-77), radius: 0.8, root: garden)
        branch(from: SIMD3(14,12,-77), to: SIMD3(5,23,-78), radius: 0.46, root: garden)
        branch(from: SIMD3(14,14,-77), to: SIMD3(23,25,-81), radius: 0.42, root: garden)
        branch(from: SIMD3(14,15,-77), to: SIMD3(13,31,-78), radius: 0.38, root: garden)
        for (center, size) in [(SCNVector3(5,23,-78), SCNVector3(11,5,8)),
                               (SCNVector3(23,25,-81), SCNVector3(12,5,9)),
                               (SCNVector3(13,31,-78), SCNVector3(10,4,8)),
                               (SCNVector3(-30,7,-74), SCNVector3(13,6,10)),
                               (SCNVector3(37,7,-58), SCNVector3(13,6,10))] {
            ellipsoid(at: center, size: SCNVector3(CGFloat(size.x) * 0.65, CGFloat(size.y) * 0.65, CGFloat(size.z) * 0.65), material: foliage[0], to: garden)
            for i in 0..<160 {
                let azimuth = random.unit() * 2 * .pi
                let elevation = (random.unit() - 0.5) * .pi
                let radius = pow(random.unit(), 0.33)
                let n = SCNNode(geometry: leafMeshes[i % leafMeshes.count])
                n.position = SCNVector3(CGFloat(center.x) + CGFloat(size.x) * cos(azimuth) * cos(elevation) * radius,
                    CGFloat(center.y) + CGFloat(size.y) * sin(elevation) * radius,
                    CGFloat(center.z) + CGFloat(size.z) * sin(azimuth) * cos(elevation) * radius)
                let length = 2.5 + random.unit() * 1.8
                n.scale = SCNVector3(length * 0.8, length, length)
                n.eulerAngles = SCNVector3((random.unit() - 0.5) * 0.9, azimuth, (random.unit() - 0.5) * 0.6)
                garden.addChildNode(n)
            }
        }
        return batch(garden, name: "window-garden")
    }

    static func makeIndoorPlant() -> SCNNode {
        let plant = SCNNode()
        plant.name = "indoor-plant"
        plant.position = SCNVector3(-27, -1.015, -20)
        plant.eulerAngles.y = .pi
        plant.castsShadow = true
        guard let url = EnvironmentMaterials.assetURL("room-plant.scn"),
              let scene = try? SCNScene(url: url) else { return plant }
        for node in scene.rootNode.childNodes {
            let leaves = node.name == "room-plant-leaves"
            let prefix = leaves ? "room-plant-leaf" : "room-plant-pot"
            let material = SCNMaterial()
            material.name = prefix
            material.lightingModel = .physicallyBased
            material.isDoubleSided = true
            material.diffuse.contents = EnvironmentMaterials.image(prefix + "-color.jpg") ?? NSColor.gray
            material.normal.contents = EnvironmentMaterials.image(prefix + "-normal.jpg")
            material.normal.intensity = 0.35
            material.roughness.contents = EnvironmentMaterials.image(prefix + "-rough.jpg") ?? 0.8
            material.metalness.contents = 0
            material.emission.contents = material.diffuse.contents
            material.emission.intensity = leaves ? 0.08 : 0.025
            material.shaderModifiers = [.surface: """
            #pragma body
            _surface.roughness = max(_surface.roughness, 0.68);
            """]
            if leaves {
                material.transparent.contents = EnvironmentMaterials.image("room-plant-opacity.png")
                material.transparencyMode = .aOne
                material.writesToDepthBuffer = true
                material.shaderModifiers?[.fragment] = """
                #pragma body
                if (_output.color.a < 0.5) { discard_fragment(); }
                _output.color.a = 1.0;
                """
            }
            for property in [material.diffuse, material.normal, material.roughness, material.transparent, material.emission] {
                property.mipFilter = .linear; property.minificationFilter = .linear
                property.magnificationFilter = .linear; property.maxAnisotropy = 16
            }
            node.geometry?.materials = [material]
            node.categoryBitMask = 2
            node.castsShadow = true
            plant.addChildNode(node)
        }
        return plant
    }

    private static func batch(_ source: SCNNode, name: String) -> SCNNode {
        let result = source.flattenedClone()
        result.name = name
        result.categoryBitMask = 2
        result.castsShadow = false
        result.enumerateChildNodes { n, _ in n.categoryBitMask = 2; n.castsShadow = false }
        return result
    }
}
