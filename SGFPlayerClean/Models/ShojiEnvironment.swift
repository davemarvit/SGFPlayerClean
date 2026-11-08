#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SceneKit

/// Static scenery, built once. Each wall is flattened into a few material batches.
/// Paper is opaque with a soft glow, avoiding transparency sorting and extra lights.
final class ShojiEnvironment {
    let node = SCNNode()
    private var walls: [SCNNode] = []

    init() {
        node.name = "shoji-environment"
        addWall(name: "shoji-back", panels: 4, panelWidth: 24, position: SCNVector3(0, -1.015, -34), angle: 0)
        addWall(name: "shoji-left", panels: 2, panelWidth: 20, position: SCNVector3(-48, -1.015, -14), angle: .pi / 2)
        addWall(name: "shoji-right", panels: 2, panelWidth: 20, position: SCNVector3(48, -1.015, -14), angle: -.pi / 2)

        node.addChildNode(GardenScenery.makeIndoorPlant())
    }

    private func addWall(name: String, panels: Int, panelWidth: CGFloat, position: SCNVector3, angle: CGFloat) {
        let wall = SCNNode()
        let height: CGFloat = 80
        func timber(width: CGFloat, height: CGFloat, depth: CGFloat, x: CGFloat, y: CGFloat, z: CGFloat = 0) {
            let box = SCNBox(width: width, height: height, length: depth, chamferRadius: min(width, height, depth) * 0.06)
            let seed = abs(sin(x * 19.17 + y * 7.31 + width * 3.21))
            let vertices = Self.positions(of: box).map { SCNVector3(CGFloat($0.x) * width, CGFloat($0.y) * height, CGFloat($0.z) * depth) }
            let uv = vertices.map { p in
                // Physical grain scale along each member instead of stretching
                // the entire photograph across a fraction-of-an-inch lattice.
                CGPoint(x: (height > width ? CGFloat(p.x) + CGFloat(p.z) : CGFloat(p.y) + CGFloat(p.z)) / 8 + seed * 5,
                        y: (height > width ? CGFloat(p.y) : CGFloat(p.x)) / 38 + seed * 3)
            }
            let geometry = SCNGeometry(sources: box.sources.filter { $0.semantic != .texcoord && $0.semantic != .vertex } + [.init(vertices: vertices), .init(textureCoordinates: uv)], elements: box.elements)
            geometry.materials = [Self.woods[min(3, Int(seed * 4))]]
            let part = SCNNode(geometry: geometry)
            part.position = SCNVector3(x, y, z)
            wall.addChildNode(part)
        }
        for panel in 0..<panels {
            let x = (CGFloat(panel) - CGFloat(panels - 1) / 2) * panelWidth
            let isWindow = name == "shoji-back" && (panel == 1 || panel == 2)
            let paperBottom: CGFloat = isWindow ? 42 : 4
            let paper = SCNPlane(width: panelWidth - 1, height: height - 0.8 - paperBottom)
            let wallPhase: CGFloat = name == "shoji-back" ? 0 : name == "shoji-left" ? 7.3 : 13.1
            let paperVertices = Self.positions(of: paper).map { SCNVector3(CGFloat($0.x) * (panelWidth - 1), CGFloat($0.y) * (height - 0.8 - paperBottom), CGFloat($0.z)) }
            let paperUV = paperVertices.map { p in
                CGPoint(x: (CGFloat(p.x) + x) / 24 + wallPhase, y: (CGFloat(p.y) + (height - 0.8 + paperBottom) / 2) / 24)
            }
            let paperGeometry = SCNGeometry(sources: paper.sources.filter { $0.semantic != .texcoord && $0.semantic != .vertex } + [.init(vertices: paperVertices), .init(textureCoordinates: paperUV)], elements: paper.elements)
            paperGeometry.materials = [Self.paper]
            let pane = SCNNode(geometry: paperGeometry)
            pane.position = SCNVector3(x, (height - 0.8 + paperBottom) / 2, -0.18)
            wall.addChildNode(pane)
            // Substantial perimeter, delicate lattice, and a low wooden kickboard.
            for side: CGFloat in [-1, 1] {
                timber(width: 0.65, height: height, depth: 0.9, x: x + side * (panelWidth - 0.65) / 2, y: height / 2)
            }
            timber(width: panelWidth, height: 4, depth: 0.8, x: x, y: 2)
            timber(width: panelWidth, height: 0.8, depth: 1, x: x, y: height - 0.4)
            for column in 1..<4 {
                timber(width: 0.20, height: height - 0.8 - paperBottom, depth: 0.42,
                    x: x - panelWidth / 2 + CGFloat(column) * panelWidth / 4, y: (height - 0.8 + paperBottom) / 2)
            }
            for row in 0..<10 {
                let y = 4 + CGFloat(row) * (height - 4.8) / 10
                if isWindow && y < paperBottom { continue }
                timber(width: panelWidth - 1.2, height: 0.22, depth: 0.46,
                    x: x, y: y)
            }
            if isWindow {
                // An actual opening, with no glass sorting or reflection pass.
                timber(width: panelWidth, height: 0.9, depth: 2.4, x: x, y: 4.2, z: 0.25)
                timber(width: panelWidth, height: 1.1, depth: 1.2, x: x, y: paperBottom)
                timber(width: 0.28, height: paperBottom - 4, depth: 0.5, x: x, y: (paperBottom + 4) / 2)
            }
        }
        // Posts and a header give the light screens an architectural frame.
        for side: CGFloat in [-1, 1] {
            timber(width: 1.2, height: height, depth: 1.4,
                x: side * CGFloat(panels) * panelWidth / 2, y: height / 2)
        }
        timber(width: CGFloat(panels) * panelWidth + 1.2, height: 1.4, depth: 1.6,
            x: 0, y: height - 0.2)
        // A shared sill anchors the panels to the tatami.
        timber(width: CGFloat(panels) * panelWidth + 0.8, height: 0.5, depth: 1.8,
            x: 0, y: 0.25)
        let batch = wall.flattenedClone()
        batch.name = name
        batch.position = position
        batch.eulerAngles.y = .init(angle)
        batch.categoryBitMask = 2
        batch.castsShadow = false
        batch.enumerateChildNodes { part, _ in
            part.categoryBitMask = 2
            part.castsShadow = false
        }
        node.addChildNode(batch)
        walls.append(batch)
    }

    /// A cutaway room: the near wall disappears when the camera crosses outside
    /// it, so orbiting or panning never traps the view behind a paper panel.
    func updateVisibility(cameraPosition: SCNVector3) {
        for wall in walls {
            let distance = wall.convertPosition(cameraPosition, from: nil).z
            let opacity = CGFloat(max(0, min(1, distance / 4)))
            if wall.opacity != opacity { wall.opacity = opacity }
            let hidden = opacity == 0
            if wall.isHidden != hidden { wall.isHidden = hidden }
        }
    }

    private static func positions(of geometry: SCNGeometry) -> [SCNVector3] {
        guard let source = geometry.sources(for: .vertex).first else { return [] }
        return source.data.withUnsafeBytes { bytes in
            (0..<source.vectorCount).map { i in
                func value(_ axis: Int) -> CGFloat {
                    let offset = source.dataOffset + i * source.dataStride + axis * source.bytesPerComponent
                    return source.bytesPerComponent == 8 ? CGFloat(bytes.loadUnaligned(fromByteOffset: offset, as: Double.self))
                        : CGFloat(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self))
                }
                return SCNVector3(value(0), value(1), value(2))
            }
        }
    }

    private static let woods: [SCNMaterial] = (0..<4).map { index in
        let material = EnvironmentMaterials.scanned("fine_grained_wood")
        material.name = "shoji-cedar-\(index)"
        let tone = CGFloat(index) * 0.045
        material.multiply.contents = NSColor(srgbRed:0.80+tone,green:0.63+tone,blue:0.44+tone,alpha:1)
        material.normal.intensity = 0.28
        material.emission.contents = material.diffuse.contents
        material.emission.intensity = 0.20
        material.shaderModifiers = [.surface: """
        #pragma body
        float2 p = _surface.diffuseTexcoord;
        float patina = 0.86 + 0.10 * sin(p.y * 4.3 + sin(p.x * 13.0)) + 0.04 * sin(p.y * 19.0);
        _surface.diffuse.rgb *= patina;
        _surface.roughness = clamp(0.50 + _surface.roughness * 0.25, 0.50, 0.85);
        """]
        return material
    }

    private static let paper: SCNMaterial = {
        let size = 128
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        let pixels = bitmap.bitmapData!
        for y in 0..<size {
            for x in 0..<size {
                let noise = Double((x * 73 + y * 151 + x * y * 13) % 29) / 29
                let value = 0.90 + noise * 0.035
                let i = (y * size + x) * 4
                pixels[i] = UInt8(value * 255)
                pixels[i + 1] = UInt8(value * 0.975 * 255)
                pixels[i + 2] = UInt8(value * 0.88 * 255)
                pixels[i + 3] = 255
            }
        }
        let image = NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: size, height: size))
        let material = SCNMaterial()
        material.name = "shoji-washi"
        material.lightingModel = .lambert
        material.diffuse.contents = image
        material.emission.contents = image
        material.emission.intensity = 0.42
        material.isDoubleSided = true
        for property in [material.diffuse, material.emission] {
            property.wrapS = .repeat; property.wrapT = .repeat
            property.contentsTransform = SCNMatrix4Identity
            property.minificationFilter = .linear; property.magnificationFilter = .linear
            property.mipFilter = .linear
        }
        material.shaderModifiers = [.surface: """
        #pragma body
        float2 p = _surface.diffuseTexcoord;
        // Broad transmitted daylight varies continuously across the screens;
        // smaller mottling suggests uneven handmade paper and outdoor foliage.
        float broad = 0.83 + 0.22 * sin(p.x * 1.37 + p.y * 0.63)
                           + 0.10 * cos(p.x * 2.9 - p.y * 1.4);
        float mottling = 0.035 * sin(p.x * 7.7 + sin(p.y * 4.1)) * cos(p.y * 6.3);
        float shade = clamp(broad + mottling - 0.10 * smoothstep(2.5, 3.4, p.y), 0.56, 1.04);
        float3 tint = mix(float3(0.91, 0.92, 0.93), float3(1.0, 0.97, 0.90), shade);
        _surface.diffuse.rgb *= shade * tint;
        _surface.emission.rgb *= shade * tint;
        """]
        return material
    }()
}
