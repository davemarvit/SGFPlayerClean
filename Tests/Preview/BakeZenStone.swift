import AppKit
import SceneKit

/// Convert the unmodified CC0 boulder scan, preserving its natural crown.
/// Normalize to a 20-unit width with its lowest point at ground level.
@main struct BakeZenStone {
    static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: input.appendingPathComponent("stone.gltf"))) as! [String: Any]
        let data = try Data(contentsOf: input.appendingPathComponent("stone.bin"))
        let accessors = document["accessors"] as! [[String: Any]]
        let views = document["bufferViews"] as! [[String: Any]]
        func buffer(_ index: Int) -> (Data, Int) {
            let accessor = accessors[index], view = views[accessor["bufferView"] as! Int]
            let offset = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
            return (data.subdata(in: offset..<(offset + (view["byteLength"] as! Int))), accessor["count"] as! Int)
        }
        func source(_ index: Int, _ semantic: SCNGeometrySource.Semantic, _ components: Int) -> SCNGeometrySource {
            let (bytes, count) = buffer(index)
            if semantic == .vertex {
                let values = bytes.withUnsafeBytes { raw in
                    (0..<count).map { i in SIMD3<Float>(
                        raw.loadUnaligned(fromByteOffset:i*12,as:Float.self),
                        raw.loadUnaligned(fromByteOffset:i*12+4,as:Float.self),
                        raw.loadUnaligned(fromByteOffset:i*12+8,as:Float.self)) }
                }
                let minX=values.map(\.x).min()!, maxX=values.map(\.x).max()!
                let minY=values.map(\.y).min()!, minZ=values.map(\.z).min()!, maxZ=values.map(\.z).max()!
                let scale: Float = 20/(maxX-minX)
                return SCNGeometrySource(vertices:values.map { SCNVector3(($0.x-(minX+maxX)/2)*scale,($0.y-minY)*scale,($0.z-(minZ+maxZ)/2)*scale) })
            }
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
            let node = SCNNode(geometry: geometry); node.name = "zen-stone-\(index)"
            scene.rootNode.addChildNode(node)
        }
        guard scene.write(to: output, options: nil, delegate: nil, progressHandler: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        print("Saved natural garden stone to \(output.path)")
    }
}
