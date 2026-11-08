#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SceneKit
import simd

/// Millimetres for the 2D equipment, independent of window and game board size.
/// Japanese board/stone dimensions: Nihon Ki-in's equipment guide. The existing
/// bowl mesh represents a ~16 cm bowl for thick stones (~10.8 mm black).
enum GoEquipmentDimensions2D {
    static let boardWidth: CGFloat = 424.2
    static let boardHeight: CGFloat = 454.5
    static let columnPitch: CGFloat = 22
    static let rowPitch: CGFloat = 23.7
    static let blackStoneDiameter: CGFloat = 22.2
    static let whiteStoneDiameter: CGFloat = 21.9
    static let bowlStoneModelDiameter: CGFloat = 0.96
    static let millimetresPerModelUnit = blackStoneDiameter / bowlStoneModelDiameter
    // BakeBowls2D uses an orthographic half-span of four model units.
    static let bowlImageSpan = 8 * millimetresPerModelUnit
    static let bowlDiameter = 6.9 * millimetresPerModelUnit
    static let lidDiameter = 6 * millimetresPerModelUnit

    static func stoneDiameter(_ color: Stone) -> CGFloat {
        color == .black ? blackStoneDiameter : whiteStoneDiameter
    }

    static func gridRect(in size: CGSize) -> CGRect {
        let width = size.width * (18 * columnPitch / boardWidth)
        let height = size.height * (18 * rowPitch / boardHeight)
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                      width: width, height: height)
    }
}

/// Solid turned-wood equipment. Materials contain grain only; SceneKit supplies
/// the highlights, shading and shadows for the current camera and lights.
enum GoEquipment3D {
    // Matching finish, but distinct pieces of wood. Keep the patterns stable
    // across board rebuilds and launches instead of randomizing each frame.
    private static let whitePlayerLidWood = lidMaterial(variant: 1)
    private static let blackPlayerLidWood = lidMaterial(variant: 0)

    private final class SupplyState {
        var remaining: Int?
        var game: UInt64?
    }
    private static let supplyStates = NSMapTable<SCNNode, SupplyState>.weakToStrongObjects()

    private static func state(for bowl: SCNNode) -> SupplyState {
        if let existing = supplyStates.object(forKey: bowl) { return existing }
        let state = SupplyState()
        supplyStates.setObject(state, forKey: bowl)
        return state
    }

    static func update(in manager: SceneManager3D) {
        guard let upperLid = manager.scene.rootNode.childNode(withName: "white-player-lid", recursively: true),
              let lowerLid = manager.scene.rootNode.childNode(withName: "black-player-lid", recursively: true),
              let world = upperLid.parent else { return }
        upperLid.geometry?.materials = [whitePlayerLidWood]
        lowerLid.geometry?.materials = [blackPlayerLidWood]
        for isWhite in [true, false] {
            let name = isWhite ? "white-stone-bowl" : "black-stone-bowl"
            let position = SCNVector3(isWhite ? -manager.equipmentOffsetX : manager.equipmentOffsetX,
                                      manager.currentEnvironment.equipmentSurfaceY + 0.165, isWhite ? -9 : manager.currentEnvironment.blackBowlZ)
            if let existing = world.childNode(withName: name, recursively: false) {
                existing.position = position
                continue
            }
            let stone = manager.stoneMaterial(isWhite: isWhite)
            let bowl = makeBowl(isWhite: isWhite, stoneMaterial: stone)
            bowl.position = position
            world.addChildNode(bowl)
        }
    }

    static func woodMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "walnut-wood"
        material.lightingModel = .physicallyBased
        material.diffuse.contents = woodTexture
        material.roughness.contents = 0.57
        // A small diffuse bounce keeps the shaded wood readable under the
        // board's deliberately simple lighting, without painted highlights.
        material.emission.contents = woodTexture
        material.emission.intensity = 0.16
        material.metalness.contents = 0
        material.clearCoat.contents = 0.10
        material.clearCoatRoughness.contents = 0.48
        return material
    }

    private static func lidMaterial(variant: Int = 0) -> SCNMaterial {
        let maps = lidGrainMaps(variant: variant)
        let material = woodMaterial()
        material.name = "textured-lid-walnut-\(variant)"
        material.diffuse.contents = maps.color
        material.emission.contents = maps.color
        material.emission.intensity = 0.045
        material.normal.contents = maps.normal
        material.normal.intensity = 0.7
        material.roughness.contents = maps.roughness
        material.clearCoat.contents = 0.02
        material.clearCoatRoughness.contents = 0.65
        for property in [material.diffuse, material.normal, material.roughness, material.emission] {
            property.minificationFilter = .linear
            property.magnificationFilter = .linear
            property.mipFilter = .linear
            property.maxAnisotropy = 16
        }
        return material
    }

    /// The 2D lid references have uneven growth rings and short, fine pores.
    /// Generate unlit color and surface maps so their relief follows the 3D light.
    private static func lidGrainMaps(variant: Int) -> (color: NSImage, normal: NSImage, roughness: NSImage) {
        let size = 1024
        func bitmap() -> NSBitmapImageRep {
            NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        }
        let color = bitmap(), normal = bitmap(), roughness = bitmap()
        let colors = color.bitmapData!, normals = normal.bitmapData!, rough = roughness.bitmapData!
        var height = [Double](repeating: 0, count: size * size)
        func hash(_ x: Int, _ y: Int) -> Double {
            var n = UInt64(bitPattern: Int64(x)) &* 374761393 &+ UInt64(bitPattern: Int64(y)) &* 668265263
            n = n &+ UInt64(variant) &* 2246822519
            n = (n ^ (n >> 13)) &* 1274126177
            return Double((n ^ (n >> 16)) & 0xffff) / 65535
        }
        func noise(_ x: Double, _ y: Double) -> Double {
            let ix = Int(floor(x)), iy = Int(floor(y))
            let fx = x - Double(ix), fy = y - Double(iy)
            let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
            let a = hash(ix, iy) * (1 - u) + hash(ix + 1, iy) * u
            let b = hash(ix, iy + 1) * (1 - u) + hash(ix + 1, iy + 1) * u
            return a * (1 - v) + b * v
        }
        func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value * 255))) }
        for row in 0..<size {
            for column in 0..<size {
                let x = Double(column) / Double(size), y = Double(row) / Double(size)
                let dx = (x - (variant == 0 ? 0.48 : 0.535)) * (variant == 0 ? 1.06 : 0.97)
                let dy = y - (variant == 0 ? 0.51 : 0.475)
                let radius = hypot(dx, dy)
                let warp = radius + 0.025 * (noise(x * 6, y * 6) - 0.5)
                    + 0.006 * sin(x * 16 + y * 9)
                let growth = warp * (variant == 0 ? 23 : 21.7)
                    + 0.14 * sin(x * 7 + y * 5) + Double(variant) * 0.27
                let latewood = pow(0.5 + 0.5 * sin(growth * 2 * .pi), 7)
                let fiber = sin(warp * 1650 + 4 * noise(x * 80, y * 80))
                let pore = pow(max(0, fiber), 9) * noise(x * 190, y * 190)
                let fleck = noise(x * 430, y * 430) - 0.5
                let variation = 0.09 * sin(growth * 2 * .pi - 0.8) - 0.155 * latewood
                    + 0.06 * (noise(x * 12, y * 12) - 0.5) + 0.025 * fiber - 0.105 * pore + 0.035 * fleck
                let pixel = row * size + column, index = pixel * 4
                colors[index] = byte(0.405 + variation)
                colors[index + 1] = byte(0.215 + variation * 0.76)
                colors[index + 2] = byte(0.095 + variation * 0.46)
                colors[index + 3] = 255
                height[pixel] = 0.025 * sin(growth * 2 * .pi) + 0.045 * fiber - 0.19 * pore + 0.02 * fleck
                let grainRoughness = byte(0.62 + 0.2 * pore + 0.08 * latewood + 0.035 * fleck)
                rough[index] = grainRoughness; rough[index + 1] = grainRoughness
                rough[index + 2] = grainRoughness; rough[index + 3] = 255
            }
        }
        for row in 0..<size {
            for column in 0..<size {
                let left = height[row * size + max(0, column - 1)]
                let right = height[row * size + min(size - 1, column + 1)]
                let above = height[max(0, row - 1) * size + column]
                let below = height[min(size - 1, row + 1) * size + column]
                let nx = (left - right) * 2.2, ny = (below - above) * 2.2
                let length = sqrt(nx * nx + ny * ny + 1)
                let index = (row * size + column) * 4
                normals[index] = byte(0.5 + nx / length * 0.5)
                normals[index + 1] = byte(0.5 + ny / length * 0.5)
                normals[index + 2] = byte(0.5 + 0.5 / length)
                normals[index + 3] = 255
            }
        }
        func image(_ bitmap: NSBitmapImageRep) -> NSImage {
            let image = NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: size, height: size))
            return image
        }
        return (image(color), image(normal), image(roughness))
    }

    // Shared by the visible mesh and the offline collision mesh.
    static let supplyStoneScaleY: CGFloat = 0.486
    static func supplyStoneRadius(isWhite: Bool) -> CGFloat {
        GoEquipmentDimensions2D.stoneDiameter(isWhite ? .white : .black)
            / GoEquipmentDimensions2D.millimetresPerModelUnit / 2
    }

    static func makeBowl(isWhite: Bool, stoneMaterial: SCNMaterial, includeStones: Bool = true) -> SCNNode {
        // Interior floor -> inner wall -> rounded lip -> outer wall -> underside.
        // The opening accepts the matching lid's approximately 3-unit radius.
        let profile: [CGPoint] = [
            .init(x: 0, y: 0.45), .init(x: 0.9, y: 0.46), .init(x: 1.6, y: 0.55),
            .init(x: 2.1, y: 0.78), .init(x: 2.5, y: 1.16), .init(x: 2.76, y: 1.65),
            .init(x: 2.88, y: 2.2), .init(x: 2.91, y: 2.8), .init(x: 2.88, y: 3.34),
            .init(x: 2.89, y: 3.55), .init(x: 2.94, y: 3.65), .init(x: 3.03, y: 3.69),
            .init(x: 3.12, y: 3.65), .init(x: 3.18, y: 3.54), .init(x: 3.23, y: 3.34),
            .init(x: 3.36, y: 2.9), .init(x: 3.45, y: 2.4), .init(x: 3.44, y: 1.9),
            .init(x: 3.32, y: 1.38), .init(x: 3.08, y: 0.87), .init(x: 2.73, y: 0.44),
            .init(x: 2.32, y: 0.12), .init(x: 2.13, y: 0.02), .init(x: 2.1, y: -0.15),
            .init(x: 1.87, y: -0.15), .init(x: 1.83, y: -0.04), .init(x: 0, y: -0.04)
        ]
        let shell = lathe(profile: profile)
        shell.materials = [isWhite ? whitePlayerLidWood : blackPlayerLidWood]
        let bowl = SCNNode(geometry: shell)
        bowl.name = isWhite ? "white-stone-bowl" : "black-stone-bowl"
        bowl.categoryBitMask = 2
        guard includeStones else { return bowl }
        let stoneGeometry = SCNSphere(radius: supplyStoneRadius(isWhite: isWhite))
        stoneGeometry.segmentCount = 24
        stoneGeometry.materials = [stoneMaterial]

        let capacity = isWhite ? min(180, bakedLayout.capacity) : bakedLayout.capacity
        for _ in 0..<capacity {
            let stone = SCNNode(geometry: stoneGeometry)
            stone.name = "supply-stone"
            stone.categoryBitMask = 4
            stone.scale = SCNVector3(1, supplyStoneScaleY, 1)
            bowl.addChildNode(stone)
        }
        applySupply(remaining: capacity, to: bowl, isWhite: isWhite, animate: false)
        return bowl
    }

    private struct BakedLayout: Decodable {
        let version: Int
        let capacity: Int
        let whiteStates: [[[Float]]]
        // One frame for each stone count, including zero; each pose is xyz + xyzw quaternion.
        let states: [[[Float]]]
    }

    private static let bakedLayout: BakedLayout = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "BowlLayouts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let layout = try? JSONDecoder().decode(BakedLayout.self, from: data),
              layout.version == 2, layout.capacity == 181,
              layout.whiteStates.count == 181,
              layout.whiteStates.enumerated().allSatisfy({ index, poses in
                  poses.count == index && poses.allSatisfy { $0.count == 7 && $0.allSatisfy(\.isFinite) }
              }),
              layout.states.count == layout.capacity + 1,
              layout.states.enumerated().allSatisfy({ index, poses in
                  poses.count == index && poses.allSatisfy { $0.count == 7 && $0.allSatisfy(\.isFinite) }
              }) else { fatalError("Missing or invalid baked bowl layouts") }
        return layout
    }()

    /// Shared by both presentations. A prisoner stays spent; a pass spends nothing.
    static func supplyCounts(for player: SGFPlayer) -> (black: Int, white: Int) {
        let history = player.getCurrentAIPayload()
        var black = 0, white = 0
        // Count played stones, not stones still on the board: prisoners stay in lids.
        for move in history.initial + history.moves where move.x >= 0 && move.y >= 0 {
            if move.color == "B" { black += 1 } else { white += 1 }
        }
        return (max(0, 181 - black), max(0, 180 - white))
    }

    static func updateSupplies(in manager: SceneManager3D, player: SGFPlayer, animate: Bool) {
        let remaining = supplyCounts(for: player)
        for (isWhite, count) in [(false, remaining.black), (true, remaining.white)] {
            let name = isWhite ? "white-stone-bowl" : "black-stone-bowl"
            guard let bowl = manager.scene.rootNode.childNode(withName: name, recursively: true) else { continue }
            let capacity = isWhite ? min(180, bakedLayout.capacity) : bakedLayout.capacity
            let sameGame = state(for: bowl).game == player.captureSeed
            applySupply(remaining: min(capacity, count), to: bowl, isWhite: isWhite, animate: animate && sameGame)
            state(for: bowl).game = player.captureSeed
        }
    }

    private static func applySupply(remaining: Int, to bowl: SCNNode, isWhite: Bool, animate: Bool) {
        let state = Self.state(for: bowl)
        let previous = state.remaining
        guard previous != remaining else { return }
        let stones = bowl.childNodes.filter { $0.name == "supply-stone" }
        let poses = isWhite ? bakedLayout.whiteStates[remaining] : bakedLayout.states[remaining]
        let transition = animate && previous.map { abs($0 - remaining) == 1 } == true
        state.remaining = remaining
        let turn = simd_quatf(angle: isWhite ? 1.1 : 0, axis: SIMD3<Float>(0, 1, 0))
        SCNTransaction.begin()
        SCNTransaction.disableActions = !transition
        SCNTransaction.animationDuration = transition ? 0.24 : 0
        for (index, stone) in stones.enumerated() {
            if index < remaining {
                let p = poses[index]
                stone.isHidden = false
                stone.opacity = 1
                stone.simdPosition = turn.act(SIMD3(p[0], p[1], p[2]))
                stone.simdOrientation = turn * simd_quatf(ix: p[3], iy: p[4], iz: p[5], r: p[6])
            } else if transition && previous == remaining + 1 && index == remaining {
                stone.position.y += 0.6
                stone.opacity = 0
                SCNTransaction.completionBlock = { [weak state, weak stone] in
                    DispatchQueue.main.async {
                        guard let current = state?.remaining, current <= index else { return }
                        stone?.isHidden = true
                    }
                }
            } else {
                stone.opacity = 0
                stone.isHidden = true
            }
        }
        SCNTransaction.commit()
    }

    static func lathe(profile: [CGPoint], segments: Int = 96) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
        var coordinates: [CGPoint] = []
        var indices: [Int32] = []
        for (ring, point) in profile.enumerated() {
            let before = profile[max(0, ring - 1)], after = profile[min(profile.count - 1, ring + 1)]
            let dr = after.x - before.x, dy = after.y - before.y
            let length = max(0.001, hypot(dr, dy))
            for segment in 0...segments {
                let angle = CGFloat(segment) * 2 * .pi / CGFloat(segments)
                let c = cos(angle), s = sin(angle)
                vertices.append(SCNVector3(point.x * c, point.y, point.x * s))
                normals.append(SCNVector3(-dy / length * c, dr / length, -dy / length * s))
                coordinates.append(CGPoint(x: 0.5 + point.x * c / 8,
                    y: 0.5 + (point.x * s + point.y * 0.35) / 10))
                if ring < profile.count - 1 && segment < segments {
                    let a = Int32(ring * (segments + 1) + segment)
                    let b = a + 1, d = a + Int32(segments + 1), e = d + 1
                    if point.x > 0 { indices += [a, b, d] }
                    if profile[ring + 1].x > 0 { indices += [b, e, d] }
                }
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: coordinates)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    private static let woodTexture: NSImage = {
        let size = 768
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        let pixels = bitmap.bitmapData!
        for row in 0..<size {
            for column in 0..<size {
                let x = Double(column) / Double(size), y = Double(row) / Double(size)
                let warp = y * 65 + 2.6 * sin(x * 5) + 0.7 * sin(x * 13 + y * 4)
                let fine = sin(warp * 2 * .pi)
                let pores = pow(max(0, sin(warp * 2 * .pi + 0.8)), 14)
                let variation = 0.028 * fine - 0.045 * pores + 0.025 * sin(y * 19 + x * 3)
                let channels = [0.48 + variation, 0.275 + variation * 0.7, 0.145 + variation * 0.45]
                let index = (row * size + column) * 4
                for channel in 0..<3 { pixels[index + channel] = UInt8(max(0, min(255, channels[channel] * 255))) }
                pixels[index + 3] = 255
            }
        }
        let image = NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: size, height: size))
        return image
    }()
}
