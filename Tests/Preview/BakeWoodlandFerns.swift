import AppKit
import SceneKit
import CoreImage

/// Offline conversion of Poly Haven's four CC0 fern meshes. Material textures
/// stay external so the application shares one atlas across all instances.
@main struct BakeWoodlandFerns {
    static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: input.appendingPathComponent("fern.gltf"))) as! [String: Any]
        let data = try Data(contentsOf: input.appendingPathComponent("fern.bin"))
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
        for (index, mesh) in (document["meshes"] as! [[String: Any]]).enumerated() {
            let primitive = (mesh["primitives"] as! [[String: Any]])[0]
            let attributes = primitive["attributes"] as! [String: Int]
            let (indices, count) = buffer(primitive["indices"] as! Int)
            let geometry = SCNGeometry(sources: [source(attributes["POSITION"]!, .vertex, 3),
                source(attributes["NORMAL"]!, .normal, 3), source(attributes["TEXCOORD_0"]!, .texcoord, 2)],
                elements: [SCNGeometryElement(data: indices, primitiveType: .triangles,
                    primitiveCount: count/3, bytesPerIndex: 2)])
            let node = SCNNode(geometry: geometry); node.name = "woodland-fern-\(index)"
            scene.rootNode.addChildNode(node)
        }
        guard scene.write(to: output, options: nil, delegate: nil, progressHandler: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // SceneKit's aOne mode needs opacity in alpha, whereas the source is
        // a grayscale mask (rgbZero would invert it and show the empty cards).
        let mask = CIImage(contentsOf: input.appendingPathComponent("fern-alpha.png"))!
        let opacity = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
        ])
        try CIContext(options: [.workingColorSpace: NSNull()]).writePNGRepresentation(of: opacity,
            to: output.deletingLastPathComponent().appendingPathComponent("woodland-fern-opacity.png"),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        print("Saved four fern variants to \(output.path)")
    }
}
