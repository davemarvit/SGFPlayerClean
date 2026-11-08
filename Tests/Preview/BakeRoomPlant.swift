import AppKit
import SceneKit
import CoreImage

/// Offline conversion of Poly Haven's CC0 potted plant. Material textures
/// stay external and retain the source model's pot and foliage atlases.
@main struct BakeRoomPlant {
    static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: input.appendingPathComponent("plant.gltf"))) as! [String: Any]
        let data = try Data(contentsOf: input.appendingPathComponent("plant.bin"))
        let accessors = document["accessors"] as! [[String: Any]]
        let views = document["bufferViews"] as! [[String: Any]]
        func buffer(_ index: Int) -> (Data, Int) {
            let accessor = accessors[index], view = views[accessor["bufferView"] as! Int]
            let offset = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
            return (data.subdata(in: offset..<(offset + (view["byteLength"] as! Int))), accessor["count"] as! Int)
        }
        func source(_ index: Int, _ semantic: SCNGeometrySource.Semantic, _ components: Int) -> SCNGeometrySource {
            let (bytes, count) = buffer(index)
            if semantic == .texcoord {
                let coordinates = bytes.withUnsafeBytes { raw in
                    (0..<count).map { i in CGPoint(x: CGFloat(raw.loadUnaligned(fromByteOffset: i*8, as: Float.self)),
                        y: CGFloat(1 - raw.loadUnaligned(fromByteOffset: i*8+4, as: Float.self))) }
                }
                return SCNGeometrySource(textureCoordinates: coordinates)
            }
            return SCNGeometrySource(data: bytes, semantic: semantic, vectorCount: count,
                usesFloatComponents: true, componentsPerVector: components, bytesPerComponent: 4,
                dataOffset: 0, dataStride: components*4)
        }
        let scene = SCNScene()
        let nodes = document["nodes"] as! [[String: Any]]
        for (index, mesh) in (document["meshes"] as! [[String: Any]]).enumerated() {
            let primitive = (mesh["primitives"] as! [[String: Any]])[0]
            let attributes = primitive["attributes"] as! [String: Int]
            let (indices, count) = buffer(primitive["indices"] as! Int)
            let geometry = SCNGeometry(sources: [source(attributes["POSITION"]!, .vertex, 3),
                source(attributes["NORMAL"]!, .normal, 3), source(attributes["TEXCOORD_0"]!, .texcoord, 2)],
                elements: [SCNGeometryElement(data: indices, primitiveType: .triangles,
                    primitiveCount: count/3, bytesPerIndex: 2)])
            let node = SCNNode(geometry: geometry); node.name = ["room-plant-pot", "room-plant-leaves", "room-plant-soil"][index]
            let transform = nodes.first { $0["mesh"] as? Int == index }!
            let translation = transform["translation"] as? [Double] ?? [0, 0, 0]
            node.position = SCNVector3(translation[0], translation[1], translation[2])
            scene.rootNode.addChildNode(node)
        }
        // Normalize all meshes together, preserving the original leaf/pot alignment.
        let bounds = scene.rootNode.boundingBox
        let scale = CGFloat(23.5) / CGFloat(bounds.max.y - bounds.min.y)
        let centerX = CGFloat(bounds.min.x + bounds.max.x) / 2
        let centerZ = CGFloat(bounds.min.z + bounds.max.z) / 2
        for node in scene.rootNode.childNodes {
            node.position = SCNVector3((CGFloat(node.position.x) - centerX) * scale,
                (CGFloat(node.position.y) - CGFloat(bounds.min.y)) * scale,
                (CGFloat(node.position.z) - centerZ) * scale)
            node.scale = SCNVector3(scale, scale, scale)
        }
        guard scene.write(to: output, options: nil, delegate: nil, progressHandler: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // SceneKit's aOne mode needs opacity in alpha, whereas the source is
        // a grayscale mask (rgbZero would invert it and show the empty cards).
        let mask = CIImage(contentsOf: input.appendingPathComponent("room-plant-leaf-alpha.png"))!
        let opacity = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
        ])
        try CIContext(options: [.workingColorSpace: NSNull()]).writePNGRepresentation(of: opacity,
            to: output.deletingLastPathComponent().appendingPathComponent("room-plant-opacity.png"),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        print("Saved room plant to \(output.path)")
    }
}
