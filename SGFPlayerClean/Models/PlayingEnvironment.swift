#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SceneKit
import simd

enum PlayingEnvironment: String, CaseIterable, Identifiable {
    case gardenRoom, japaneseGarden, mountainSummit, moon, tree, cave, yugenRoom, coffeeShop, retroFuture, laboratory, spaceStation
    // Preserve the saved preference of users who selected the former Open tatami.
    case monastery = "tatami"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gardenRoom: return "Garden-view room"
        case .japaneseGarden: return "Japanese garden"
        case .mountainSummit: return "Mountain summit"
        case .moon: return "Moon"
        case .tree: return "Beneath the tree"
        case .cave: return "Lamplit cave"
        case .monastery: return "Buddhist monastery"
        case .yugenRoom: return "Yūgen-no-ma"
        case .coffeeShop: return "Neighborhood coffee shop"
        case .retroFuture: return "World of Tomorrow"
        case .laboratory: return "The Inventor’s Laboratory"
        case .spaceStation: return "Space station"
        }
    }
    var symbol: String {
        switch self {
        case .gardenRoom: return "window.vertical.closed"
        case .japaneseGarden: return "leaf"
        case .mountainSummit: return "mountain.2.fill"
        case .moon: return "moon.stars"
        case .tree: return "tree"
        case .cave: return "flame"
        case .monastery: return "building.columns"
        case .yugenRoom: return "square.grid.3x3"
        case .coffeeShop: return "cup.and.saucer"
        case .retroFuture: return "sparkles"
        case .laboratory: return "flask"
        case .spaceStation: return "sparkles.rectangle.stack"
        }
    }
    var detail: String {
        switch self {
        case .gardenRoom: return "Shoji screens, a garden window, and a leafy houseplant."
        case .japaneseGarden: return "A quiet clearing among moss, weathered stones, and a garden pond."
        case .mountainSummit: return "A weathered summit ledge, distant alpine ridges, and the last warm light of sunset."
        case .moon: return "A lunar summit overlooking crater rims beneath a distant Earth."
        case .tree: return "A spreading tree, soft earth, and scattered autumn leaves."
        case .cave: return "Sheltered stone and the gentle warmth of an oil lamp."
        case .monastery: return "A quiet, dark timber hall with an old bronze Buddha and soft shoji light."
        case .yugenRoom: return "Inspired by photographs of the Nihon Ki-in’s special match room."
        case .coffeeShop: return "A tabletop goban, worn wooden furniture, and a welcoming local café."
        case .retroFuture: return "An Art Deco skyport with brass consoles, rocket ships and an optimistic view of tomorrow."
        case .laboratory: return "A crowded old laboratory: copper coils, glass apparatus and a scarred workbench."
        case .spaceStation: return "A crowded space station, nearby controls, and orbital construction beyond the window. Stones drift in minimal gravity."
        }
    }
    var usesTableBoard: Bool { self == .coffeeShop || self == .retroFuture || self == .laboratory || self == .spaceStation }
    var usesAgedBoard: Bool { self == .monastery }
    var usesStoneBoard: Bool { self == .cave }
    var boardTopAsset: String {
        usesStoneBoard ? "cave-limestone-board-top.png" : usesAgedBoard ? "temple-aged-board-top.png" : "kaya-top-v2.png"
    }
    var boardEndgrainAsset: String {
        usesStoneBoard ? "cave-limestone-board-side.png" : usesAgedBoard ? "temple-aged-board-endgrain.png" : "kaya-endgrain-v2.png"
    }
    // One percent of the usual gravity gives ten times the fall time.
    var gravity: CGFloat { self == .spaceStation ? 0.1962 : 19.62 }
    var stoneDropDuration: TimeInterval { self == .spaceStation ? 2.0 : 0.2 }
    var equipmentSurfaceY: CGFloat { usesTableBoard ? 1 - 2.4 - 0.015 : KayaFloorBoard.floorY }
    var floorY: CGFloat { usesTableBoard ? equipmentSurfaceY - 34 : KayaFloorBoard.floorY }
    var sceneryOffset: CGFloat { floorY + 1.015 }
    func equipmentOffsetX(boardWidth: CGFloat) -> CGFloat {
        usesTableBoard ? boardWidth / 2 + 4.0 : 20
    }
    var blackLidZ: CGFloat { usesTableBoard ? -1 : 4 }
    var blackBowlZ: CGFloat { usesTableBoard ? 3 : 7 }
    var usesTatami: Bool { self == .gardenRoom || self == .yugenRoom }

    /// Composed from the player's side of the board, so arrival never circles
    /// through the room walls or reverses the board's playing orientation.
    var arrivalView: (eye: SIMD3<Float>, gaze: SIMD3<Float>) {
        switch self {
        case .gardenRoom: return (SIMD3(-8, 32, 48), SIMD3(0, 8, -27)) // Stay inside the shoji framing.
        case .japaneseGarden: return (SIMD3(15, 38, 64), SIMD3(-8, 20, -32)) // Pond and trees.
        case .mountainSummit: return (SIMD3(-8, 32, 58), SIMD3(22, 18, -50))
        case .moon: return (SIMD3(-13, 37, 65), SIMD3(6, 27, -45)) // Earth above the crater rim.
        case .tree: return (SIMD3(8, 34, 52), SIMD3(-16, 12, -29)) // Autumn trees and spreading canopy.
        case .cave: return (SIMD3(-15, 30, 58), SIMD3(12, 14, -25)) // Lamplight and sheltered rock.
        case .monastery: return (SIMD3(5, 32, 52), SIMD3(0, 72, -32)) // Begin at the Buddha, then descend to the board.
        case .retroFuture: return (SIMD3(8, 36, 54), SIMD3(8, 18, -38))
        case .laboratory: return (SIMD3(-6, 34, 48), SIMD3(9, 11, -31))
        case .spaceStation: return (SIMD3(0, 28, 48), SIMD3(0, 20, -65))
        case .coffeeShop: return (SIMD3(10, 32, 58), SIMD3(-8, 23, -45)) // Counter, books and street windows.
        case .yugenRoom: return (SIMD3(-9, 31, 60), SIMD3(-12, 26, -32)) // Alcove and calligraphy.
        }
    }

    /// A slow sideways arc surveys a second portion of each setting before descent.
    var arrivalSurveyAngle: Float {
        switch self {
        case .gardenRoom: return 0.65 // Keep the sweep inside the shoji framing.
        case .monastery, .laboratory, .cave, .yugenRoom, .spaceStation: return 0.85
        case .japaneseGarden: return 0.90
        case .tree: return -0.95
        case .retroFuture, .moon: return -1.00
        case .coffeeShop, .mountainSummit: return 1.00
        }
    }

    var arrivalFieldOfView: CGFloat {
        switch self {
        case .gardenRoom: return 64
        case .coffeeShop, .retroFuture: return 76
        case .laboratory: return 80
        case .spaceStation: return 84
        case .japaneseGarden, .yugenRoom: return 78
        case .moon: return 76
        case .mountainSummit: return 80
        case .tree: return 80
        case .cave: return 74
        case .monastery: return 90
        }
    }
    var background: NSColor {
        switch self {
        case .moon: return .black
        case .mountainSummit: return NSColor(srgbRed: 0.28, green: 0.35, blue: 0.45, alpha: 1)
        case .spaceStation: return NSColor(srgbRed: 0.025, green: 0.035, blue: 0.05, alpha: 1)
        case .cave: return NSColor(srgbRed: 0.037, green: 0.041, blue: 0.049, alpha: 1)
        case .tree: return NSColor(srgbRed: 0.40, green: 0.44, blue: 0.31, alpha: 1)
        case .japaneseGarden: return NSColor(srgbRed: 0.55, green: 0.62, blue: 0.48, alpha: 1)
        default: return SceneManager3D.backgroundColor
        }
    }
}

/// Cached surroundings with optional cave light, café steam and incense smoke.
/// Tabletop supports participate in stone physics; decorative props do not.
final class PlayingEnvironmentScene {
    let node = SCNNode()
    private var mistEmitters: [SCNNode] = []
    private var motionEnabled = false
    private var stationDisplayClock: SCNNode?
    static let stationDisplayCycleDuration: TimeInterval = 180
    private var lamp: SCNNode?
    private var flame: SCNNode?
    private var flickering = false
    private var lampRestPosition = SCNVector3Zero
    let kind: PlayingEnvironment

    init(_ kind: PlayingEnvironment) {
        self.kind = kind
        node.name = "environment-\(kind.rawValue)"
        switch kind {
        case .japaneseGarden, .mountainSummit, .moon, .tree, .monastery, .yugenRoom, .coffeeShop, .retroFuture, .laboratory, .spaceStation: makePhotographicGround()
        case .cave: makeCave()
        case .gardenRoom: break
        }
        if kind == .tree { makeCanopyShadow(); makeNearbyWoodland() }
        if kind == .japaneseGarden { makeZenGardenDetails() }
        if kind == .monastery { makeMonasteryCushions() }
        if kind == .yugenRoom { makeYugenSeats() }
        if kind == .coffeeShop { makeCoffeeShopFurniture() }
        if kind == .retroFuture || kind == .laboratory { makeImaginativeFurniture() }
        if kind == .spaceStation { makeSpaceStationFurniture() }
        if kind == .monastery { makeNearbyIncense() }
        node.enumerateChildNodes { n, _ in
            n.categoryBitMask = 2
            n.castsShadow = (kind == .japaneseGarden && n.name == "photographic-ground") || n.name == "oil-lamp-rock" || n.name == "canopy-shadow-caster"
                || (n.name?.hasPrefix("coffee-") == true && n.name != "coffee-steam")
                || n.name?.hasPrefix("nearby-") == true || n.name?.hasPrefix("inventor-") == true
                || n.name?.hasPrefix("tomorrow-") == true
                || n.name?.hasPrefix("station-") == true
                || n.name?.hasPrefix("zabuton-body") == true || n.name?.hasPrefix("yugen-furniture") == true
        }
    }

    /// A bolted workstation with flush touch displays and raised switch banks.
    /// The clear central pad accommodates every board size and its wooden bowls.
    private func makeSpaceStationFurniture() {
        let tableY = kind.equipmentSurfaceY - kind.sceneryOffset
        let graphite = Self.stationFinish("station-worn-graphite.png", tint: 0.95, metalness: 0.3)
        let trim = Self.stationFinish("station-worn-ivory.png", tint: 0.53, metalness: 0.65)
        let rubber = Self.stationFinish("station-worn-graphite.png", tint: 0.4, metalness: 0)
        let boardPad = Self.stationFinish("station-worn-graphite.png", tint: 1, metalness: 0)
        boardPad.name = "station-scratched-board-pad"
        boardPad.shaderModifiers?[.surface] = """
        #pragma body
        // Lift the pale scuffs separately from the charcoal base; simply raising
        // the tint washes out the whole pad without making its wear legible.
        float luminance = dot(_surface.diffuse.rgb, float3(0.2126,0.7152,0.0722));
        float scuff = smoothstep(0.055,0.22,luminance);
        _surface.diffuse.rgb = float3(0.025,0.029,0.033) + float3(0.34,0.34,0.32) * scuff;
        _surface.emission.rgb = _surface.diffuse.rgb * 0.045;
        _surface.roughness = 0.9 - scuff * 0.2;
        """
        let ivory = Self.stationFinish("station-worn-ivory.png", tint: 0.78, metalness: 0.12)
        let cyan = Self.stationFinish("station-worn-ivory.png", tint: 1, metalness: 0)
        cyan.multiply.contents = NSColor(srgbRed: 0.05, green: 0.52, blue: 0.61, alpha: 1)
        cyan.emission.intensity = 0.20
        let amber = Self.stationFinish("station-worn-ivory.png", tint: 1, metalness: 0)
        amber.multiply.contents = NSColor(srgbRed: 0.72, green: 0.32, blue: 0.07, alpha: 1)
        amber.emission.intensity = 0.12
        let screens = [Self.stationInstrument(0, aspect: 9.8/15.8),
                       Self.stationInstrument(1, aspect: 9.8/15.8),
                       Self.stationInstrument(2, aspect: 29/4.3),
                       Self.stationInstrument(3, aspect: 8.8/7),
                       Self.stationInstrument(4, aspect: 8.8/7)]
        let frame = SCNNode(), details = SCNNode(), controls = SCNNode()
        @discardableResult func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                                     _ x: CGFloat, _ y: CGFloat, _ z: CGFloat,
                                     _ material: SCNMaterial, to parent: SCNNode) -> SCNNode {
            let mesh = SCNBox(width: w, height: h, length: d, chamferRadius: min(0.14, min(w, min(h, d)) / 4))
            mesh.chamferSegmentCount = 1
            return add(Self.stationMappedBox(mesh, origin: SCNVector3(x,y,z)), material, SCNVector3(x, y, z), to: parent)
        }
        let tabletop = box(72, 2.2, 56, 0, tableY - 1.1, 0, graphite, to: node)
        tabletop.name = "station-tabletop"
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(
            geometry: SCNBox(width: 72, height: 2.2, length: 56, chamferRadius: 0), options: [.collisionMargin: 0.005]))
        body.friction = 0.65; body.restitution = 0.015
        body.categoryBitMask = 1 << 1; body.collisionBitMask = 1 << 0
        tabletop.physicsBody = body
        // Recessed central landing pad and panel seams are coplanar with the support.
        box(39, 0.025, 35, 0, tableY + 0.012, 0, boardPad, to: details)
        for side: CGFloat in [-1, 1] {
            box(1.0, 2.6, 56.5, side * 35.6, tableY - 0.9, 0, trim, to: frame)
            box(66, 2.6, 0.9, 0, tableY - 0.9, side * 27.7, trim, to: frame)
            box(0.10, 0.035, 29, side * 20, tableY + 0.025, 0, cyan, to: details)
            for z: CGFloat in [-19, 19] {
                box(6, 31.7, 7, side * 28, 14.85, z, graphite, to: frame)
                box(9, 1.0, 10, side * 28, -0.5, z, trim, to: frame)
            }
            // A flush rectangular display is built into each side of the desk.
            box(10.7, 0.045, 16.7, side * 27.3, tableY + 0.025, 9, trim, to: details)
            let display = add(SCNPlane(width: 9.8, height: 15.8), screens[side < 0 ? 0 : 1],
                              SCNVector3(side * 27.3, tableY + 0.055, 9), to: details)
            display.eulerAngles.x = -.pi / 2
            // Tilted console panels: the individual switches remain real geometry.
            let console = SCNNode()
            console.position = SCNVector3(side * 27, tableY + 4.5, -13)
            console.eulerAngles.x = -.pi / 3
            box(11.5, 15, 1.6, 0, 0, 0, ivory, to: console)
            box(10.5, 14, 0.15, 0, 0, 0.86, rubber, to: console)
            let monitor = add(SCNPlane(width: 8.8, height: 7), screens[side < 0 ? 3 : 4], SCNVector3(0, 2.6, 0.96), to: console)
            monitor.name = "station-console-display"
            for row in 0..<3 { for column in 0..<5 {
                let x = CGFloat(column) * 1.8 - 3.6, y = -2.1 - CGFloat(row) * 1.45
                box(1.25, 0.85, 0.3, x, y, 1.08, row == 0 ? cyan : trim, to: console)
                box(0.65, 0.08, 0.04, x, y + 0.2, 1.25, row == 2 ? amber : rubber, to: console)
            }}
            controls.addChildNode(console)
            // Guarded switches and status segments along the near edge.
            for i in 0..<7 {
                let x = side * (10 + CGFloat(i) * 2.8)
                box(1.9, 0.03, 1.1, x, tableY + 0.03, 24.7, i % 3 == 0 ? amber : cyan, to: details)
            }
            for i in 0..<6 {
                let z = CGFloat(i) * 7.9 - 20
                let bolt = SCNCylinder(radius: 0.19, height: 0.04); bolt.radialSegmentCount = 8
                add(bolt, trim, SCNVector3(side * 34, tableY + 0.03, z), to: details)
            }
            // Strapped equipment cases just beyond the playing area.
            for j in 0..<2 {
                let x = side * (23 + CGFloat(j) * 6.8)
                box(5.8, 3.2, 6, x, tableY + 1.6, -23.5, graphite, to: details)
                box(0.55, 3.3, 6.1, x - 1.5, tableY + 1.6, -23.5, rubber, to: details)
                box(2.2, 0.8, 0.04, x + 0.6, tableY + 2, -20.46, amber, to: details)
            }
            // Thick coiled service leads connect the switch banks to the desk.
            for i in 0..<14 {
                let a = Float(i) * 0.32, b = Float(i + 1) * 0.32
                limb(SIMD3(Float(side * 32) + sin(a) * 1.2, Float(tableY) + 0.25, -18 + a),
                     SIMD3(Float(side * 32) + sin(b) * 1.2, Float(tableY) + 0.25, -18 + b),
                     0.13, rubber, to: details)
            }
        }
        // A long inset engineering display sits behind the goban, below the window.
        box(30, 0.06, 5, 0, tableY + 0.03, -23, trim, to: details)
        let rear = add(SCNPlane(width: 29, height: 4.3), screens[2], SCNVector3(0, tableY + 0.07, -23), to: details)
        rear.eulerAngles.x = -.pi / 2
        flattened(frame, name: "station-table-frame")
        // Bake nested transforms before flattening; bounded batches avoid SceneKit's
        // large primitive index limit and keep the station cheap to render.
        for (source, label) in [(details, "inset-controls"), (controls, "switch-banks")] {
            var pieces: [SCNNode] = []
            source.enumerateChildNodes { child, _ in if child.geometry != nil { pieces.append(child) } }
            let poses = pieces.map { source.convertTransform($0.transform, from: $0.parent) }
            source.childNodes.forEach { $0.removeFromParentNode() }
            for (piece, pose) in zip(pieces, poses) {
                piece.removeFromParentNode(); piece.transform = pose
                if piece.geometry?.materials.contains(where: { material in screens.contains(where: { $0 === material }) }) == true {
                    // Keep the five display faces live. SceneKit lazily builds
                    // flattened materials, so their uniforms cannot be driven here.
                    piece.name = "station-display"; node.addChildNode(piece)
                } else { source.addChildNode(piece) }
            }
            var batch = 0
            while !source.childNodes.isEmpty {
                let group = SCNNode()
                for piece in Array(source.childNodes.prefix(40)) { group.addChildNode(piece) }
                flattened(group, name: "station-\(label)-\(batch)"); batch += 1
            }
        }
        let clock = SCNNode(); clock.name = "station-display-clock"
        clock.isPaused = true
        let sweep = SCNAction.customAction(duration: Self.stationDisplayCycleDuration) { _, elapsed in
            let phase = Float(elapsed / Self.stationDisplayCycleDuration) * 2 * .pi
            for screen in screens { screen.setValue(phase, forKey: "stationDisplayPhase") }
        }
        clock.runAction(.repeatForever(sweep), forKey: "station-display-drift")
        node.addChildNode(clock); stationDisplayClock = clock
    }

    /// Paint wear supplies both color variation and a conservative roughness field.
    /// Real lighting remains responsible for highlights and contact shadows.
    private static func stationFinish(_ asset: String, tint: CGFloat, metalness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial(); material.name = "station-weathered-" + asset
        material.lightingModel = .physicallyBased
        let image = EnvironmentMaterials.image(asset)
        material.diffuse.contents = image ?? NSColor(white: 0.3, alpha: 1)
        material.emission.contents = image; material.emission.intensity = 0.035
        material.multiply.contents = NSColor(white: tint, alpha: 1)
        material.roughness.contents = image ?? 0.75
        material.metalness.contents = metalness
        // Original face UVs stay in channel 1 for accumulated dirt at panel rims.
        material.transparent.contents = NSColor.white; material.transparent.mappingChannel = 1
        for property in [material.diffuse, material.emission, material.roughness] {
            property.wrapS = .repeat; property.wrapT = .repeat
            property.mipFilter = .linear; property.minificationFilter = .linear
            property.magnificationFilter = .linear; property.maxAnisotropy = 16
        }
        material.shaderModifiers = [.surface: """
        #pragma body
        float2 face = _surface.transparentTexcoord;
        float edge = min(min(face.x,1.0-face.x), min(face.y,1.0-face.y));
        float dirt = 0.68 + 0.32 * smoothstep(0.0,0.055,edge);
        _surface.diffuse.rgb *= dirt;
        _surface.emission.rgb *= dirt * _surface.multiply.rgb;
        _surface.roughness = clamp(0.48 + _surface.roughness * 0.4, 0.48, 0.9);
        """]
        return material
    }

    /// Use the same physical grain scale on a long desk rim and a small switch.
    /// Default primitive UVs stretch a whole photograph over every individual face.
    private static func stationMappedBox(_ box: SCNBox, origin: SCNVector3) -> SCNGeometry {
        guard let positions = box.sources(for: .vertex).first,
              let normals = box.sources(for: .normal).first,
              let originalUV = box.sources(for: .texcoord).first else { return box }
        func vector(_ source: SCNGeometrySource, _ index: Int) -> SIMD3<Float> {
            source.data.withUnsafeBytes { bytes in
                func component(_ axis: Int) -> Float {
                    let offset = source.dataOffset + index * source.dataStride + axis * source.bytesPerComponent
                    return source.bytesPerComponent == 8 ? Float(bytes.loadUnaligned(fromByteOffset: offset, as: Double.self))
                        : bytes.loadUnaligned(fromByteOffset: offset, as: Float.self)
                }
                return SIMD3(component(0), component(1), component(2))
            }
        }
        var uv: [CGPoint] = [], vertices: [SCNVector3] = []
        // SceneKit exposes normalized cube vertices; the primitive renderer applies
        // its dimensions separately. Bake those dimensions into our custom mesh.
        let dimensions = SIMD3(Float(box.width),Float(box.height),Float(box.length))
        for i in 0..<positions.vectorCount {
            let local = vector(positions,i) * dimensions
            vertices.append(SCNVector3(local))
            let p = local + SIMD3(Float(origin.x),Float(origin.y),Float(origin.z))
            let n = vector(normals,i)
            let pair: SIMD2<Float>
            if abs(n.y) >= max(abs(n.x),abs(n.z)) { pair = SIMD2(p.x,p.z) }
            else if abs(n.x) >= abs(n.z) { pair = SIMD2(p.z,p.y) }
            else { pair = SIMD2(p.x,p.y) }
            uv.append(CGPoint(x: CGFloat(pair.x / 28), y: CGFloat(pair.y / 28)))
        }
        return SCNGeometry(sources: box.sources.filter { $0.semantic != .texcoord && $0.semantic != .vertex }
                           + [.init(vertices: vertices), .init(textureCoordinates: uv), originalUV], elements: box.elements)
    }

    /// Each physical display has its own aspect-correct layout and instrument.
    /// Project genuine 3D line endpoints in the shader, retaining depth cues while
    /// keeping the glass, labels and grid stationary. No per-frame texture uploads.
    private static func stationInstrument(_ kind: Int, aspect: CGFloat) -> SCNMaterial {
        let screen = SCNMaterial(); screen.name = "station-worn-display-glass"
        screen.lightingModel = .physicallyBased
        screen.diffuse.contents = stationDisplay(kind, aspect: aspect)
        screen.emission.contents = screen.diffuse.contents; screen.emission.intensity = 0.55
        screen.multiply.contents = EnvironmentMaterials.image("station-worn-ivory.png")
        screen.roughness.contents = screen.multiply.contents
        screen.clearCoat.contents = 0.12; screen.clearCoatRoughness.contents = 0.4
        screen.setValue(Float(0), forKey: "stationDisplayPhase")
        screen.setValue(Float(kind), forKey: "stationInstrument")
        screen.setValue(Float(aspect), forKey: "stationAspect")
        screen.shaderModifiers = [.surface: """
        #pragma arguments
        float stationDisplayPhase;
        float stationInstrument;
        float stationAspect;
        #pragma body
        float grime = clamp(_surface.roughness,0.0,1.0);
        _surface.emission.rgb *= 0.45 + grime*0.45;
        _surface.roughness = 0.28 + (1.0-grime)*0.5;
        float2 uv = _surface.diffuseTexcoord;
        // Isotropic units: circles and wireframes retain their proportions on
        // both portrait panels and the exceptionally wide rear instrument.
        float2 p = float2((uv.x-0.5)*stationAspect,0.5-uv.y);
        float phase = stationDisplayPhase;
        int instrument = int(stationInstrument+0.5);
        float ink = 0.0;
        float amber = 0.0;
        float aa = max(0.0012, length(fwidth(p))*0.65);
        int count = instrument == 0 ? 84 : instrument == 1 ? 140 : instrument == 2 ? 80 : instrument == 3 ? 84 : 0;
        for (int i=0; i<count; i++) {
            float3 a=float3(0.0), b=float3(0.0);
            if (instrument == 0) {
                if (i < 40) {
                    float t=float(i%20)*6.2831853/20.0, u=t+6.2831853/20.0;
                    float y=i<20 ? -0.48 : 0.48;
                    a=float3(0.64*cos(t),y,0.64*sin(t)); b=float3(0.64*cos(u),y,0.64*sin(u));
                } else if (i < 48) {
                    float t=float(i-40)*6.2831853/8.0;
                    a=float3(0.64*cos(t),-0.48,0.64*sin(t)); b=float3(a.x,0.48,a.z);
                } else {
                    // Central habitat and two rectangular solar arrays.
                    int box=(i-48)/12, edge=(i-48)%12, axis=edge/4, corner=edge%4;
                    float3 extent=box==0 ? float3(0.22,0.85,0.22) : float3(0.35,0.58,0.025);
                    float3 center=box==0 ? float3(0.0) : float3(box==1 ? -0.96 : 0.96,0,0);
                    a=float3((corner&1)==0 ? -1.0:1.0,(corner&2)==0 ? -1.0:1.0,-1.0);
                    if(axis==0) { a=float3(-1,a.x,a.y); b=float3(1,a.y,a.z); }
                    else if(axis==1) { a=float3(a.x,-1,a.y); b=float3(a.x,1,a.z); }
                    else { b=float3(a.x,a.y,1); }
                    a=a*extent+center; b=b*extent+center;
                }
            } else if (instrument == 1) {
                float t=float(i%20)*6.2831853/20.0, u=t+6.2831853/20.0;
                if(i<80) {
                    float longitude=float(i/20)*3.14159265/4.0;
                    a=float3(cos(t)*cos(longitude),sin(t),cos(t)*sin(longitude));
                    b=float3(cos(u)*cos(longitude),sin(u),cos(u)*sin(longitude));
                } else {
                    float latitude=float((i-80)/20-1)*0.55;
                    a=float3(cos(t)*cos(latitude),sin(latitude),sin(t)*cos(latitude));
                    b=float3(cos(u)*cos(latitude),sin(latitude),sin(u)*cos(latitude));
                }
            } else if (instrument == 2) {
                // Longitudinal ship sections, connecting longerons and solar wings.
                if(i<28) {
                    int section=i/4; float t=float(i%4)*1.5707963, u=t+1.5707963;
                    float radius=0.24+0.28*sin(float(section)*3.14159265/6.0);
                    a=float3((float(section)-3.0)*0.82,radius*cos(t),radius*sin(t));
                    b=float3(a.x,radius*cos(u),radius*sin(u));
                } else if(i<52) {
                    int section=(i-28)/4; float t=float((i-28)%4)*1.5707963;
                    float r=0.24+0.28*sin(float(section)*3.14159265/6.0);
                    float q=0.24+0.28*sin(float(section+1)*3.14159265/6.0);
                    a=float3((float(section)-3.0)*0.82,r*cos(t),r*sin(t));
                    b=float3(a.x+0.82,q*cos(t),q*sin(t));
                } else {
                    int wing=(i-52)/7, edge=(i-52)%7;
                    float x=wing<2 ? -0.9:0.9, side=wing%2==0 ? -1.0:1.0;
                    if(edge<4) {
                        float t=float(edge)*1.5707963+0.7853982,u=t+1.5707963;
                        a=float3(x+0.55*cos(t),side*(0.8+0.5*sin(t)),0);
                        b=float3(x+0.55*cos(u),side*(0.8+0.5*sin(u)),0);
                    } else {
                        float dx=float(edge-5)*0.18;
                        a=float3(x+dx,side*0.45,0); b=float3(x+dx,side*1.15,0);
                    }
                }
            } else {
                if(i<80) {
                    float t=float(i%20)*6.2831853/20.0,u=t+6.2831853/20.0;
                    float z=float(i/20)*0.65-1.0;
                    a=float3(0.7*cos(t),0.7*sin(t),z); b=float3(0.7*cos(u),0.7*sin(u),z);
                } else {
                    float t=float(i-80)*1.5707963;
                    a=float3(0.7*cos(t),0.7*sin(t),-1); b=float3(a.x,a.y,0.95);
                }
            }
            if(instrument==2) { a.x*=2.6; b.x*=2.6; }
            float yaw=instrument==2 ? 0.2*sin(phase) : instrument==3 ? 0.17*sin(phase) : phase;
            float pitch=instrument==2 ? phase : instrument==3 ? 0.12*cos(phase) : 0.35;
            float cy=cos(yaw),sy=sin(yaw),cx=cos(pitch),sx=sin(pitch);
            a=float3(cy*a.x+sy*a.z,a.y,-sy*a.x+cy*a.z);
            b=float3(cy*b.x+sy*b.z,b.y,-sy*b.x+cy*b.z);
            a=float3(a.x,cx*a.y-sx*a.z,sx*a.y+cx*a.z);
            b=float3(b.x,cx*b.y-sx*b.z,sx*b.y+cx*b.z);
            float scale=instrument==2 ? 0.27 : instrument==0 ? 0.21 : instrument==1 ? 0.24 : 0.26;
            float2 q=a.xy*scale*(3.8/(3.8-a.z)), r=b.xy*scale*(3.8/(3.8-b.z));
            float2 line=r-q;
            float t=clamp(dot(p-q,line)/max(dot(line,line),0.000001),0.0,1.0);
            float distance=length(p-q-t*line);
            float depth=clamp(0.58+mix(a.z,b.z,t)*0.25,0.25,1.0);
            float stroke=(1.0-smoothstep(0.001,0.001+aa,distance))*depth;
            if(instrument==2 && i>=52) amber=max(amber,stroke);
            else ink=max(ink,stroke);
        }
        if(instrument==4) {
            // Three independent, gently travelling power/thermal traces.
            for(int row=0;row<3;row++) {
                float y=(float(row)-1.0)*0.19+0.025*sin(p.x*24.0-phase*2.0+float(row)*2.0)
                    +0.012*sin(p.x*53.0+phase+float(row));
                float line=1.0-smoothstep(0.001,0.001+aa,abs(p.y-y));
                if(row==1) amber=max(amber,line); else ink=max(ink,line*0.8);
            }
        }
        // A restrained lower telemetry strip complements each main visualization.
        float stripY=instrument==2 ? -0.34 : -0.37;
        float span=stationAspect*0.39;
        float wave=stripY+0.012*sin(p.x*38.0+phase*2.0+float(instrument));
        float telemetry=(1.0-smoothstep(0.001,0.001+aa,abs(p.y-wave)))*step(abs(p.x),span);
        amber=max(amber,telemetry*0.55);
        float clip=step(abs(p.y),0.42)*step(abs(p.x),stationAspect*0.46);
        _surface.emission.rgb += (float3(0.10,0.62,0.71)*ink+float3(0.85,0.40,0.08)*amber)*clip*(0.65+0.35*grime);
        """]
        screen.diffuse.mipFilter = .linear; screen.diffuse.maxAnisotropy = 16
        return screen
    }

    private static func stationDisplay(_ kind: Int, aspect: CGFloat) -> NSImage {
        let size = NSSize(width: (512*aspect).rounded(), height: 512)
        return NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor(srgbRed: 0.012, green: 0.035, blue: 0.048, alpha: 1).cgColor)
            ctx.fill(rect)
            let cyan = NSColor(srgbRed: 0.12, green: 0.65, blue: 0.74, alpha: 1)
            let amber = NSColor(srgbRed: 0.85, green: 0.44, blue: 0.10, alpha: 1)
            ctx.setStrokeColor(cyan.cgColor); ctx.setLineWidth(1)
            for x in stride(from: CGFloat(16), to: size.width, by: 32) {
                ctx.move(to: CGPoint(x:x,y:45)); ctx.addLine(to: CGPoint(x:x,y:460))
            }
            for y in stride(from: CGFloat(45), to: 462, by: 32) {
                ctx.move(to: CGPoint(x:16,y:y)); ctx.addLine(to: CGPoint(x:size.width-16,y:y))
            }
            ctx.setAlpha(0.10); ctx.strokePath(); ctx.setAlpha(1)
            ctx.setFillColor(cyan.cgColor); ctx.fill(CGRect(x:18,y:468,width:size.width*0.60,height:2))
            ctx.setFillColor(amber.cgColor); ctx.fill(CGRect(x:size.width*0.79,y:468,width:size.width*0.16,height:2))
            #if os(macOS)
            let titles = ["ORBITAL ASSEMBLY / 04", "NAVIGATION / DEEP FIELD", "DOCK 07 / STRUCTURAL SCAN", "RENDEZVOUS / APPROACH", "SYSTEMS / POWER BUS"]
            let status = ["TRUSS ALIGNMENT    99.8%", "INERTIAL FRAME     LOCKED", "KEEL + ARRAY GEOMETRY                         RANGE  2.4 KM                         RELATIVE VELOCITY  0.02 M/S", "CORRIDOR CLEAR / AUTO HOLD", "REACTOR / THERMAL / RESERVES"]
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            (titles[kind] as NSString).draw(at: CGPoint(x:18,y:483), withAttributes: [.font:font,.foregroundColor:cyan])
            (status[kind] as NSString).draw(at: CGPoint(x:18,y:19), withAttributes: [.font:font,.foregroundColor:cyan.withAlphaComponent(0.75)])
            #endif
            return true
        }
    }

    /// Foreground furniture is real geometry; only the distant café is a panorama.
    /// Keep board coordinates unchanged and lower the room floor below the table.
    private func makeCoffeeShopFurniture() {
        let tableY = kind.equipmentSurfaceY - kind.sceneryOffset
        let floorY: CGFloat = -1.015
        let wood = SCNMaterial()
        wood.name = "coffee-shop-worn-walnut"
        wood.lightingModel = .physicallyBased
        wood.diffuse.contents = EnvironmentMaterials.image("coffee-table-wood.png") ?? NSColor.brown
        wood.roughness.contents = 0.62
        wood.emission.contents = wood.diffuse.contents; wood.emission.intensity = 0.055
        wood.clearCoat.contents = 0.10; wood.clearCoatRoughness.contents = 0.55
        for property in [wood.diffuse, wood.emission] {
            property.mipFilter = .linear; property.minificationFilter = .linear
            property.magnificationFilter = .linear; property.maxAnisotropy = 16
        }
        @discardableResult func piece(_ geometry: SCNGeometry, _ material: SCNMaterial,
                                      _ position: SCNVector3, _ name: String, parent: SCNNode? = nil) -> SCNNode {
            let object = add(geometry, material, position, to: parent ?? node)
            object.name = "coffee-" + name
            return object
        }
        func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ position: SCNVector3,
                 _ name: String, material: SCNMaterial? = nil, parent: SCNNode? = nil) -> SCNNode {
            piece(SCNBox(width: w, height: h, length: d, chamferRadius: min(0.22, h / 4)),
                  material ?? wood, position, name, parent: parent)
        }
        func rail(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ radius: CGFloat, _ material: SCNMaterial,
                  _ name: String, parent: SCNNode) {
            let cylinder = SCNCylinder(radius: radius, height: CGFloat(simd_length(b-a)))
            cylinder.radialSegmentCount = 12
            let object = piece(cylinder, material, SCNVector3((a+b)/2), name, parent: parent)
            object.simdOrientation = simd_quatf(from: SIMD3(0,1,0), to: simd_normalize(b-a))
        }
        let top = box(70, 1.9, 52, SCNVector3(0, tableY - 0.95, 0), "tabletop")
        let shape = SCNPhysicsShape(geometry: SCNBox(width: 70, height: 1.9, length: 52, chamferRadius: 0), options: [.collisionMargin: 0.005])
        let support = SCNPhysicsBody(type: .static, shape: shape)
        support.friction = 0.6; support.restitution = 0.015
        support.categoryBitMask = 1 << 1; support.collisionBitMask = 1 << 0
        top.physicsBody = support
        let tableFrame = SCNNode()
        for x: CGFloat in [-28, 28] { for z: CGFloat in [-20, 20] {
            _ = box(3.4, tableY - floorY - 1.9, 3.4,
                    SCNVector3(x, (tableY + floorY - 1.9) / 2, z), "table-leg", parent: tableFrame)
        }}
        for z: CGFloat in [-20, 20] { _ = box(59, 5, 1.4, SCNVector3(0, tableY - 4.2, z), "table-apron", parent: tableFrame) }
        for x: CGFloat in [-28, 28] { _ = box(1.4, 5, 42, SCNVector3(x, tableY - 4.2, 0), "table-apron", parent: tableFrame) }

        flattened(tableFrame, name: "coffee-table-frame", to: node)

        for side: CGFloat in [-1, 1] {
            let chair = SCNNode(); chair.name = side < 0 ? "coffee-opponent-chair" : "coffee-player-chair"
            chair.position = SCNVector3(side < 0 ? -1 : 1.5, floorY, side * 35)
            chair.eulerAngles.y = side < 0 ? .pi + 0.04 : -0.07
            let finish = wood.copy() as! SCNMaterial
            finish.emission.intensity = 0.16
            finish.multiply.contents = side < 0 ? NSColor(srgbRed: 0.48, green: 0.58, blue: 0.42, alpha: 1)
                : NSColor(srgbRed: 0.72, green: 0.60, blue: 0.48, alpha: 1)
            _ = box(21, 1.6, 19, SCNVector3(0, 21.5, 0), "chair-seat", material: finish, parent: chair)
            for x: Float in [-8, 8] { for z: Float in [-7, 7] {
                rail(SIMD3(x * 1.15, 0.5, z * 1.15), SIMD3(x, 21.5, z), 0.8, finish, "chair-leg", parent: chair)
            }}
            for x: Float in [-8, 8] {
                rail(SIMD3(x, 21.5, 7), SIMD3(x, 43, 9.5), 0.8, finish, "chair-back", parent: chair)
                rail(SIMD3(x, 11, -7), SIMD3(x, 11, 7), 0.55, finish, "chair-stretcher", parent: chair)
            }
            for x: Float in [-4, 0, 4] {
                rail(SIMD3(x, 22.5, 7.1), SIMD3(x, 41, 9.4), 0.45, finish, "chair-spindle", parent: chair)
            }
            _ = box(19, 3.5, 1.4, SCNVector3(0, 41.5, 9.4), "chair-back-rail", material: finish, parent: chair)
            flattened(chair, name: chair.name!, to: node)
        }
        // A 42 cm wide 19-line goban spans 20 units: these are roughly
        // 9 cm diameter × 10 cm tall mugs, with a substantial 400–450 ml interior.
        for side: CGFloat in [-1, 1] {
            let cup = SCNNode(); cup.name = "coffee-cup"
            cup.position = SCNVector3(side * 21.5, tableY, -side * 17.5)
            let ceramic = SCNMaterial(); ceramic.lightingModel = .physicallyBased
            ceramic.diffuse.contents = NSColor(srgbRed: 0.89, green: 0.86, blue: 0.78, alpha: 1)
            ceramic.emission.contents = ceramic.diffuse.contents; ceramic.emission.intensity = 0.16
            ceramic.roughness.contents = 0.30; ceramic.clearCoat.contents = 0.28
            _ = piece(Self.mugBase(), ceramic, SCNVector3Zero, "cup-rounded-base", parent: cup)
            let footClay=ceramic.copy() as! SCNMaterial
            footClay.diffuse.contents=NSColor(srgbRed:0.66,green:0.62,blue:0.52,alpha:1)
            footClay.roughness.contents=0.9; footClay.clearCoat.contents=0
            _ = piece(SCNTorus(ringRadius:1.72,pipeRadius:0.09),footClay,SCNVector3(0,0.09,0),"cup-foot-ring",parent:cup)
            let shell = SCNTube(innerRadius: 1.86, outerRadius: 2.15, height: 4.25)
            shell.radialSegmentCount = 96
            _ = piece(shell, ceramic, SCNVector3(0, 2.675, 0), "cup-body", parent: cup)
            let rim = piece(SCNTorus(ringRadius: 2.005, pipeRadius: 0.145), ceramic, SCNVector3(0, 4.8, 0), "cup-rim", parent: cup)
            rim.scale.y = 0.7
            let handle = piece(SCNTorus(ringRadius: 1.1, pipeRadius: 0.28), ceramic,
                               SCNVector3(side * 2.55, 2.6, 0), "cup-handle", parent: cup)
            handle.eulerAngles.x = .pi / 2; handle.scale.y = 1.15
            let coffee = Self.color(0.075, 0.035, 0.014, bounce: 0.02)
            coffee.lightingModel = .physicallyBased; coffee.roughness.contents = 0.23
            _ = piece(SCNCylinder(radius: 1.855, height: 0.04), coffee, SCNVector3(0, 4.28, 0), "drink", parent: cup)
            addMugArtwork(to: cup, ceramic: ceramic, asteroid: side < 0)
            flattened(cup, name: "coffee-cup", to: node)
            let emitter = SCNNode(); emitter.name = "coffee-steam"
            emitter.position = SCNVector3(cup.position.x, cup.position.y + 4.85, cup.position.z)
            emitter.castsShadow = false; emitter.isHidden = true; emitter.addParticleSystem(Self.makeSteam())
            node.addChildNode(emitter); mistEmitters.append(emitter)
        }
    }

    private static func mugBase() -> SCNGeometry {
        let profile:[(CGFloat,CGFloat)] = [(0,0.12),(1.55,0.12),(1.72,0.09),(1.83,0.10),
            (1.94,0.16),(2.04,0.25),(2.11,0.37),(2.15,0.55)]
        let count=96
        var vertices:[SCNVector3]=[], normals:[SCNVector3]=[], uv:[CGPoint]=[], indices:[Int32]=[]
        for (ring,p) in profile.enumerated() {
            let before=profile[max(0,ring-1)], after=profile[min(profile.count-1,ring+1)]
            let dr=Float(after.0-before.0), dy=Float(after.1-before.1)
            for j in 0...count {
                let a=CGFloat(j)*2 * .pi/CGFloat(count)
                vertices.append(SCNVector3(sin(a)*p.0,p.1,cos(a)*p.0))
                normals.append(SCNVector3(simd_normalize(SIMD3(Float(sin(a))*dy,-dr,Float(cos(a))*dy))))
                uv.append(CGPoint(x:CGFloat(j)/CGFloat(count),y:p.1))
                if ring<profile.count-1 && j<count { let k=Int32(ring*(count+1)+j),n=k+Int32(count+1);indices += [k,k+1,n,k+1,n+1,n] }
            }
        }
        return SCNGeometry(sources:[.init(vertices:vertices),.init(normals:normals),.init(textureCoordinates:uv)],elements:[.init(indices:indices,primitiveType:.triangles)])
    }

    /// Print the unchanged portrait artwork onto both sides of the ceramic.
    /// Mesh UVs preserve its aspect ratio; there is no product-photo background.
    private func addMugArtwork(to cup: SCNNode, ceramic: SCNMaterial, asteroid: Bool) {
        guard let image = EnvironmentMaterials.image(asteroid ? "marvit-but-first-coffee-asteroid.jpg" : "marvit-but-first-coffee-monster.jpg") else { return }
        let printMaterial = ceramic.copy() as! SCNMaterial
        printMaterial.name = "Lawrence Marvit — But First… Coffee: " + (asteroid ? "Asteroid" : "Monster")
        printMaterial.diffuse.contents = image; printMaterial.emission.contents = image
        printMaterial.emission.intensity = 0.16
        printMaterial.diffuse.maxAnisotropy = 16; printMaterial.diffuse.mipFilter = .linear
        let height: CGFloat = 4.1, radius: CGFloat = 2.157
        let width = height * image.size.width / image.size.height
        // Aim the print toward the seated player; ceramic and handle stay put.
        let printFacing = CGFloat(atan2(-cup.position.x, 13.2 - cup.position.z))
        for facing: CGFloat in [printFacing, printFacing + .pi] {
            var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uv: [CGPoint] = [], indices: [Int32] = []
            for i in 0...40 {
                let u = CGFloat(i) / 40, angle = facing + (u - 0.5) * width / radius
                for v: CGFloat in [0, 1] {
                    vertices.append(SCNVector3(radius * sin(angle), 0.42 + v * height, radius * cos(angle)))
                    normals.append(SCNVector3(sin(angle), 0, cos(angle)))
                    uv.append(CGPoint(x: u, y: 1 - v))
                }
                if i < 40 { let j = Int32(i * 2); indices += [j, j+2, j+1, j+1, j+2, j+3] }
            }
            let mesh = SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals), .init(textureCoordinates: uv)],
                                   elements: [.init(indices: indices, primitiveType: .triangles)])
            let printNode = add(mesh, printMaterial, SCNVector3Zero, to: cup)
            printNode.name = "coffee-mug-artwork"
        }
    }

    private static func makeSteam() -> SCNParticleSystem {
        let mist = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [NSColor.white.cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                locations: [0, 1])!
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                       endCenter: CGPoint(x: 32, y: 32), endRadius: 30, options: [])
            return true
        }
        let steam = SCNParticleSystem()
        steam.particleImage = mist; steam.blendMode = .alpha
        steam.isLightingEnabled = false; steam.isAffectedByGravity = false
        steam.birthRate = 0; steam.speedFactor = 0; steam.particleLifeSpan = 5; steam.particleLifeSpanVariation = 0.5
        steam.emitterShape = SCNSphere(radius: 0.28)
        steam.emittingDirection = SCNVector3(0, 1, 0); steam.spreadingAngle = 12
        steam.particleVelocity = 0.45; steam.particleVelocityVariation = 0.08
        steam.acceleration = SCNVector3(0.025, 0.015, 0.008)
        steam.particleColor = NSColor(white: 0.95, alpha: 1)
        steam.particleSize = 0.7; steam.warmupDuration = 3
        let fade = CAKeyframeAnimation(); fade.keyTimes = [0, 0.18, 0.55, 1]; fade.values = [0, 0.055, 0.035, 0]
        let spread = CAKeyframeAnimation(); spread.keyTimes = [0, 0.5, 1]; spread.values = [0.45, 0.9, 1.35]
        steam.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade),
                                     .size: SCNParticlePropertyController(animation: spread)]
        return steam
    }

    func setMotionEnabled(_ enabled: Bool) {
        guard enabled != motionEnabled else { return }
        motionEnabled = enabled
        stationDisplayClock?.isPaused = !enabled
        for emitter in mistEmitters {
            emitter.isHidden = !enabled
            for system in emitter.particleSystems ?? [] {
                system.reset(); system.speedFactor = enabled ? 1 : 0
                system.birthRate = enabled ? (emitter.name == "incense-smoke" ? 4 : 2) : 0
            }
        }
    }

    /// Nearby objects give the panoramic grove parallax without blocking play.
    private func makeNearbyWoodland() {
        var rng = Random(seed: 7259)
        let variants = EnvironmentMaterials.woodlandFerns
        let plants = SCNNode()
        for i in 0..<18 {
            let a = (CGFloat(i) + rng.next()*0.9)/18 * 2 * .pi
            let radius: CGFloat = 32 + rng.next()*18
            let x = sin(a)*radius, z = cos(a)*radius
            // Keep the board, bowls and player's approach clear.
            if z > 15 && abs(x) < 23 { continue }
            guard !variants.isEmpty else { continue }
            let fern = SCNNode(geometry: variants[i % variants.count])
            fern.position = SCNVector3(x,-1.015,z)
            // Four scanned growth habits, gently varied in scale and bearing.
            // Their crowns are at the origin; the lowest fronds enter the soil.
            let size = 17 + rng.next()*7
            fern.scale = SCNVector3(size, size*(0.86+rng.next()*0.22), size)
            fern.eulerAngles.y = .init(rng.next()*2 * .pi)
            plants.addChildNode(fern)
        }
        let grove = flattened(plants,name:"nearby-ferns-and-moss")
        grove.enumerateChildNodes { child, _ in child.name = "nearby-woodland-mesh" }
    }

    /// Rake grooves have real depth and normals, so the garden sun determines
    /// both their lit faces and self-shadowing. Their crests meet the board feet.
    static func gardenGroundHeight(x: CGFloat, z: CGFloat) -> CGFloat {
        let radius = hypot(x,z)
        let fade = max(0,min(1,(85-radius)/25))
        let bend = 1.5*sin(x/28) + 0.45*sin(x/11)
            + 2.8*exp(-pow((x+29)/10,2))*tanh((z+13)/9)
        let phase = (z + bend) * (2 * CGFloat.pi / 2.2)
        return -1.015 - fade * 0.20 * (1-cos(phase))
    }

    private func makeZenGardenDetails() {
        let gravel = SCNNode(geometry: Self.zenGravelGeometry)
        gravel.name = "nearby-loose-gravel"
        node.addChildNode(gravel)
        if let url = EnvironmentMaterials.assetURL("zen-garden-stone.scn"),
           let source = try? SCNScene(url:url),
           let geometry = source.rootNode.childNodes.compactMap({ $0.geometry }).first {
            let stone = EnvironmentMaterials.scanned("zen-stone")
            stone.lightingModel = .lambert
            stone.emission.contents = stone.diffuse.contents; stone.emission.intensity = 0.045
            stone.roughness.contents = 0.94; stone.normal.intensity = 0.38
            stone.multiply.contents = NSColor(srgbRed:0.82,green:0.85,blue:0.80,alpha:1)
            for (x,z,size,angle) in [(CGFloat(-29),CGFloat(-13),CGFloat(0.54),CGFloat(0.4)),(26,-34,0.68,-0.7)] {
                let shape = geometry.copy() as! SCNGeometry; shape.materials = [stone]
                let rock = SCNNode(geometry:shape)
                rock.name = "nearby-zen-stone"
                rock.position = SCNVector3(x,-3.5,z)
                rock.scale = SCNVector3(size,size*0.68,size*0.8); rock.eulerAngles.y = .init(angle)
                node.addChildNode(rock)
            }
        }
        guard let image = EnvironmentMaterials.image("zen-maple-leaf.png") else { return }
        let leaf = SCNMaterial(); leaf.name = "fallen-japanese-maple"
        leaf.lightingModel = .lambert; leaf.isDoubleSided = true
        leaf.diffuse.contents = image; leaf.transparent.contents = image; leaf.transparencyMode = .aOne
        leaf.diffuse.mipFilter = .linear; leaf.diffuse.maxAnisotropy = 16
        leaf.shaderModifiers = [.fragment: """
        #pragma body
        if (_output.color.a < 0.4) { discard_fragment(); }
        _output.color.a = 1.0;
        """]
        let leaves = SCNNode()
        var random = Random(seed:8240)
        for (x,z) in [(CGFloat(-14),CGFloat(-16)),(15,16),(-25,7),(28,-16),(-8,24),(24,3)] {
            // Acer palmatum blades vary substantially; use 60–90 mm specimens.
            // Match the equipment scale: a 22.2 mm stone spans 0.96 model units,
            // and the 6.9-unit bowl is about 160 mm wide. Compensate for the
            // cutout's transparent margins (1178 of 1254 pixels contain leaf).
            let bladeMillimetres = 60 + random.next()*30
            let size = bladeMillimetres * (0.96 / 22.2) / (1178.0 / 1254.0)
            let angle = random.next()*2 * .pi
            var points: [SCNVector3] = [], uv: [CGPoint] = [], indices: [Int32] = []
            // Fine enough to follow the rake crests without chords cutting
            // through the gravel and making an intact blade look fragmented.
            let divisions = 24
            for row in 0...divisions { for column in 0...divisions {
                let lx = (CGFloat(column)/CGFloat(divisions)-0.5)*size
                let lz = (CGFloat(row)/CGFloat(divisions)-0.5)*size
                let px = x+lx*cos(angle)-lz*sin(angle), pz = z+lx*sin(angle)+lz*cos(angle)
                let curl = 0.045*pow(abs(lx)/(size/2),2)
                points.append(SCNVector3(px,Self.gardenGroundHeight(x:px,z:pz)+0.20+curl,pz))
                uv.append(CGPoint(x:CGFloat(column)/CGFloat(divisions),y:CGFloat(row)/CGFloat(divisions)))
                if row<divisions && column<divisions {
                    let stride = Int32(divisions+1), k = Int32(row*(divisions+1)+column)
                    indices += [k,k+stride,k+1,k+1,k+stride,k+stride+1]
                }
            }}
            let mesh = SCNGeometry(sources:[.init(vertices:points),.init(normals:Array(repeating:SCNVector3(0,1,0),count:points.count)),.init(textureCoordinates:uv)],elements:[.init(indices:indices,primitiveType:.triangles)])
            add(mesh,leaf,SCNVector3Zero,to:leaves)
        }
        flattened(leaves,name:"nearby-zen-maple-leaves")
    }

    /// A dense bed of separate angular grains, not isolated stones on a smooth
    /// plane. Batching and caching keep it to one draw call and one construction.
    /// 0.30–0.48 units is approximately 7–11 mm at the equipment's physical scale.
    private static let zenGravelGeometry: SCNGeometry = {
        var random = Random(seed: 64829)
        var points: [SCNVector3] = [], normals: [SCNVector3] = []
        var colors: [SIMD4<Float>] = [], indices: [Int32] = []
        let spacing: CGFloat = 0.35, extent = 158
        points.reserveCapacity(850_000); normals.reserveCapacity(850_000)
        colors.reserveCapacity(850_000); indices.reserveCapacity(3_500_000)
        for row in -extent...extent { for column in -extent...extent {
            let x = (CGFloat(column) + (row % 2 == 0 ? 0 : 0.5) + (random.next()-0.5)*0.65)*spacing
            let z = (CGFloat(row) + (random.next()-0.5)*0.65)*spacing
            let distance = hypot(x,z)
            guard distance < 55 else { continue }
            let fade = min(1, (55-distance)/7)
            let radius = 0.15 + random.next()*0.09
            let aspect = 0.72 + random.next()*0.40
            let angle = random.next()*2 * .pi
            let height = (0.10 + random.next()*0.075)*fade
            let epsilon: CGFloat = 0.03
            let dx = Float((gardenGroundHeight(x:x+epsilon,z:z)-gardenGroundHeight(x:x-epsilon,z:z))/(2*epsilon))
            let dz = Float((gardenGroundHeight(x:x,z:z+epsilon)-gardenGroundHeight(x:x,z:z-epsilon))/(2*epsilon))
            let up = simd_normalize(SIMD3<Float>(-dx,1,-dz))
            let tangent = simd_normalize(SIMD3<Float>(1,dx,0))
            let bitangent = simd_cross(tangent,up)
            let tone = Float(0.60 + random.next()*0.32)
            let warm = Float(random.next()*0.025)
            let color = SIMD4<Float>(tone+warm,tone,tone-warm*0.6,1)
            let start = Int32(points.count)
            // An uneven lower rim and narrower upper crown give each grain
            // chipped edges; the open underside is buried in the gravel bed.
            for level in 0...1 { for side in 0..<5 {
                let a = angle + CGFloat(side)*2 * .pi/5
                let r = radius*(0.82+random.next()*0.30)*(level == 0 ? 1 : 0.66)
                let px = x+cos(a)*r, pz = z+sin(a)*r*aspect
                let y = gardenGroundHeight(x:px,z:pz) + (level == 0 ? -0.025 : height*(0.72+random.next()*0.24))
                points.append(SCNVector3(px,y,pz))
                // Orient grain normals with the rake slope as well as geometry:
                // otherwise all the grain crowns erase the rake's directional shading.
                let normal = simd_normalize(tangent*Float(cos(a))
                    + up*(level == 0 ? 0.35 : 1.25) + bitangent*Float(sin(a)/aspect))
                normals.append(SCNVector3(normal))
                colors.append(color)
            }}
            points.append(SCNVector3(x,gardenGroundHeight(x:x,z:z)+height,z))
            normals.append(SCNVector3(up)); colors.append(color)
            for side in 0..<5 {
                let a = start+Int32(side), b = start+Int32((side+1)%5)
                indices += [a,a+5,b, b,a+5,b+5, a+5,start+10,b+5]
            }
        }}
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(data:colorData,semantic:.color,vectorCount:colors.count,
            usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16)
        let mesh = SCNGeometry(sources:[.init(vertices:points),.init(normals:normals),colorSource],
            elements:[.init(indices:indices,primitiveType:.triangles)])
        let material = SCNMaterial()
        material.name = "loose-pale-granite"; material.lightingModel = .lambert
        material.diffuse.contents = NSColor.white
        material.emission.contents = NSColor(white:0.025,alpha:1)
        material.roughness.contents = 0.96
        mesh.materials = [material]
        return mesh
    }()

    static let incensePosition = SCNVector3(17,0,-13)

    private func makeNearbyIncense() {
        let assembly=SCNNode(), wood=EnvironmentMaterials.scanned("weathered_brown_planks")
        wood.multiply.contents=NSColor(srgbRed:0.28,green:0.19,blue:0.12,alpha:1)
        let bronze=Self.color(0.24,0.18,0.09,bounce:0.04)
        bronze.lightingModel = .physicallyBased; bronze.metalness.contents=0.68; bronze.roughness.contents=0.62
        let top=add(SCNBox(width:9,height:0.8,length:8,chamferRadius:0.25),wood,SCNVector3(0,4,0),to:assembly)
        for x:CGFloat in [-3.3,3.3] { for z:CGFloat in [-2.8,2.8] {
            add(SCNBox(width:0.9,height:4,length:0.9,chamferRadius:0.1),wood,SCNVector3(x,1.1,z),to:assembly)
        }}
        // Interior -> lip -> outer wall -> underside: no solid cap can hide ash.
        let vessel = GoEquipment3D.lathe(profile:[CGPoint(x:0,y:4.6),CGPoint(x:1.4,y:4.7),
            CGPoint(x:1.8,y:5.0),CGPoint(x:2.05,y:5.7),CGPoint(x:2.08,y:6.65),
            CGPoint(x:2.15,y:6.78),CGPoint(x:2.28,y:6.6),CGPoint(x:2.4,y:5.7),
            CGPoint(x:2.2,y:4.9),CGPoint(x:1.5,y:4.3),CGPoint(x:0,y:4.3)])
        add(vessel,bronze,SCNVector3Zero,to:assembly)
        makeIncenseAsh()
        let incense = Self.color(0.24,0.13,0.065,bounce:0.03)
        let ash = Self.color(0.47,0.44,0.39,bounce:0.05)
        let ember = Self.color(0.18,0.055,0.018,bounce:0)
        ember.emission.contents = NSColor(srgbRed:0.42,green:0.09,blue:0.018,alpha:1)
        ember.emission.intensity = 0.35
        // Unequal burned lengths, fragile pale ash tips, and one spent stick.
        for (i,height) in [Float(2.5),3.35,1.6].enumerated() {
            let base = SIMD3<Float>(Float(i-1)*0.5,6.48,0)
            let tip = SIMD3<Float>(Float(i-1)*0.63,6.6+height,Float(i)*0.12-0.12)
            let ashStart = tip - SIMD3<Float>(0,0.30,0)
            limb(base,ashStart,0.062,incense,to:assembly)
            limb(ashStart,tip,0.07,ash,to:assembly)
            if i < 2 {
                ball(SCNVector3(tip),SCNVector3(0.065,0.045,0.065),ember,to:assembly)
                let emitter = SCNNode(); emitter.name = "incense-smoke"
                emitter.position = SCNVector3(CGFloat(Self.incensePosition.x)+CGFloat(tip.x),CGFloat(tip.y)+0.06,CGFloat(Self.incensePosition.z)+CGFloat(tip.z))
                emitter.isHidden = true
                let smoke = Self.makeSteam()
                smoke.emitterShape = SCNSphere(radius:0.045)
                smoke.particleLifeSpan = 10; smoke.particleLifeSpanVariation = 1.2
                smoke.particleVelocity = 0.48; smoke.particleVelocityVariation = 0.06
                smoke.spreadingAngle = 7
                smoke.acceleration = SCNVector3(0.018,0.008,-0.009)
                smoke.particleColor = NSColor(srgbRed:0.72,green:0.74,blue:0.76,alpha:1)
                smoke.warmupDuration = 6
                let fade = CAKeyframeAnimation(); fade.keyTimes = [0,0.12,0.45,1]; fade.values = [0,0.085,0.04,0]
                let spread = CAKeyframeAnimation(); spread.keyTimes = [0,0.4,1]; spread.values = [0.16,0.65,1.6]
                smoke.propertyControllers = [.opacity:SCNParticlePropertyController(animation:fade),
                                             .size:SCNParticlePropertyController(animation:spread)]
                emitter.addParticleSystem(smoke); node.addChildNode(emitter); mistEmitters.append(emitter)
            }
        }
        _ = top
        let batch=flattened(assembly,name:"nearby-monastery-incense")
        batch.position=Self.incensePosition
    }

    /// A slightly heaped, powdery gray bed with tiny charcoal flecks.
    private func makeIncenseAsh() {
        let size = 512
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,
            colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
        var random = Random(seed:8149)
        let pixels = bitmap.bitmapData!
        for y in 0..<size { for x in 0..<size {
            let grain = random.next()
            let cloudy = sin(CGFloat(x)*0.037+sin(CGFloat(y)*0.024))*0.025
                + sin(CGFloat(y)*0.061+CGFloat(x)*0.017)*0.018
            let gray = 0.67 + cloudy + (grain-0.5)*0.13 - (grain < 0.025 ? 0.22 : 0)
            let i=(y*size+x)*4
            pixels[i]=UInt8(gray*255); pixels[i+1]=UInt8(gray*255)
            pixels[i+2]=UInt8((gray*0.98)*255); pixels[i+3]=255
        }}
        let image = NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: size, height: size))
        let ash = SCNMaterial(); ash.name = "powdery-incense-ash"; ash.lightingModel = .physicallyBased
        ash.diffuse.contents = image; ash.roughness.contents = 1.0
        ash.emission.contents = image; ash.emission.intensity = 0.08
        ash.diffuse.mipFilter = .linear; ash.diffuse.maxAnisotropy = 8
        let rings=24, segments=96
        var points:[SCNVector3]=[], normals:[SCNVector3]=[], uv:[CGPoint]=[], indices:[Int32]=[]
        for ring in 0...rings { for j in 0...segments {
            let r=CGFloat(ring)/CGFloat(rings)*2.035, a=CGFloat(j)/CGFloat(segments)*2 * .pi
            let x=cos(a)*r,z=sin(a)*r
            let h=6.52+0.09*(1-r*r/4.15)+0.016*sin(x*9+z*5)*sin(z*11-x*4)
            points.append(SCNVector3(x,h,z)); normals.append(SCNVector3(0,1,0))
            uv.append(CGPoint(x:x/4.07+0.5,y:z/4.07+0.5))
            if ring<rings && j<segments {
                let k=Int32(ring*(segments+1)+j),n=k+Int32(segments+1)
                indices += [k,k+1,n,k+1,n+1,n]
            }
        }}
        let mesh=SCNGeometry(sources:[.init(vertices:points),.init(normals:normals),.init(textureCoordinates:uv)],
            elements:[.init(indices:indices,primitiveType:.triangles)])
        let bed=add(mesh,ash,Self.incensePosition,to:node); bed.name="nearby-incense-ash"
    }

    /// Both imaginative settings use a real supported table and close, solid
    /// props. Their background photographs provide the architecture beyond it.
    private func makeImaginativeFurniture() {
        let lab=kind == .laboratory, prefix=lab ? "inventor-" : "tomorrow-"
        let tableY=kind.equipmentSurfaceY-kind.sceneryOffset
        let wood=EnvironmentMaterials.scanned("weathered_brown_planks")
        wood.diffuse.contents=EnvironmentMaterials.image("coffee-table-wood.png") ?? wood.diffuse.contents
        wood.multiply.contents=lab ? NSColor(srgbRed:0.61,green:0.47,blue:0.33,alpha:1) : NSColor(srgbRed:0.34,green:0.51,blue:0.48,alpha:1)
        wood.normal.intensity=lab ? 0.35 : 0.09; wood.roughness.contents=lab ? 0.75 : 0.36
        wood.emission.contents=wood.diffuse.contents; wood.emission.intensity=0.035
        let metal=Self.color(lab ? 0.31 : 0.53,lab ? 0.19 : 0.38,lab ? 0.10 : 0.17,bounce:0.03)
        metal.lightingModel = .physicallyBased; metal.metalness.contents=0.72; metal.roughness.contents=lab ? 0.54 : 0.32
        let dark=Self.color(0.055,0.065,0.06,bounce:0.04)
        let ceramic=Self.color(0.67,0.64,0.53,bounce:0.04)
        let props=SCNNode()
        func box(_ w:CGFloat,_ h:CGFloat,_ d:CGFloat,_ x:CGFloat,_ y:CGFloat,_ z:CGFloat,_ m:SCNMaterial,_ parent:SCNNode) {
            add(SCNBox(width:w,height:h,length:d,chamferRadius:min(0.22,h/4)),m,SCNVector3(x,y,z),to:parent)
        }
        let top=add(SCNBox(width:70,height:2,length:52,chamferRadius:0.35),wood,SCNVector3(0,tableY-1,0),to:node)
        top.name=prefix+"tabletop"
        let support=SCNPhysicsBody(type:.static,shape:SCNPhysicsShape(geometry:SCNBox(width:70,height:2,length:52,chamferRadius:0),options:[.collisionMargin:0.005]))
        support.categoryBitMask=2; support.collisionBitMask=1; support.friction=0.6; support.restitution=0.015
        top.physicsBody=support
        if lab {
            for x:CGFloat in [-29,29] { for z:CGFloat in [-21,21] { box(3,tableY-1,3,x,(tableY-1)/2-1.015,z,wood,props) }}
        } else {
            add(SCNCylinder(radius:4.4,height:tableY-1),metal,SCNVector3(0,(tableY-1)/2-1.015,0),to:props)
            add(SCNCylinder(radius:16,height:1.2),metal,SCNVector3(0,-0.4,0),to:props)
            for z:CGFloat in [-25.5,25.5] { box(69,0.45,0.45,0,tableY-0.4,z,metal,props) }
        }
        // Two stools, close enough to complete the table's human scale.
        for sign:CGFloat in [-1,1] {
            add(SCNCylinder(radius:7.4,height:1.6),wood,SCNVector3(0,20,sign*34),to:props)
            for x:CGFloat in [-4.7,4.7] { for z:CGFloat in [-4.7,4.7] {
                limb(SIMD3(Float(x),19,Float(sign*34+z)),SIMD3(Float(x*1.25),-1,Float(sign*34+z*1.25)),0.65,metal,to:props)
            }}
        }
        let surface=SCNNode(); surface.position.y = .init(tableY)
        props.addChildNode(surface)
        func gauge(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat,_ radius:CGFloat) {
            let housing=add(SCNCylinder(radius:radius,height:0.5),metal,SCNVector3(x,y,z),to:surface); housing.eulerAngles.x = .pi/2
            let dial=SCNMaterial(); dial.lightingModel = .lambert; dial.diffuse.contents=Self.instrumentDial()
            add(SCNPlane(width:radius*1.75,height:radius*1.75),dial,SCNVector3(x,y,z+0.27),to:surface)
        }
        if lab {
            // Copper coil, grooved ceramic insulators and a battered instrument.
            box(7,2,6,25,1,-18,dark,surface)
            add(SCNCylinder(radius:1.7,height:8),dark,SCNVector3(25,6,-18),to:surface)
            for j in 0..<22 { add(SCNTorus(ringRadius:1.75,pipeRadius:0.095),metal,SCNVector3(25,2.5+CGFloat(j)*0.31,-18),to:surface) }
            add(SCNTorus(ringRadius:2.4,pipeRadius:0.7),metal,SCNVector3(25,10,-18),to:surface)
            box(9,6,4,-24,3,-20,wood,surface)
            gauge(-25.5,4,-17.8,1.8); gauge(-21.6,4,-17.8,1.05)
            for i in 0..<4 { add(SCNSphere(radius:0.28),dark,SCNVector3(-27+CGFloat(i)*1.8,1.5,-17.7),to:surface) }
            let green=Self.color(0.09,0.23,0.15,bounce:0.1); green.lightingModel = .physicallyBased; green.roughness.contents=0.22
            green.clearCoat.contents=0.6
            for (x,z,h): (CGFloat,CGFloat,CGFloat) in [(-27,-10,5),(-24,-12,3.8),(19,-20,5.2),(22,-23,4)] {
                ball(SCNVector3(x,h*0.38,z),SCNVector3(1.3,h*0.38,1.3),green,to:surface)
                add(SCNCylinder(radius:0.48,height:h*0.4),green,SCNVector3(x,h*0.84,z),to:surface)
                add(SCNCylinder(radius:0.5,height:0.35),wood,SCNVector3(x,h*1.04,z),to:surface)
            }
            for j in 0..<3 {
                let book=SCNNode(); book.position=SCNVector3(-20,0.5+CGFloat(j)*0.9,-23); book.eulerAngles.y = .init(CGFloat(j)*0.12-0.2)
                box(7,0.55,5,0,0,0,ceramic,book)
                for y:CGFloat in [-0.34,0.34] { box(7.3,0.12,5.3,0,y,0,dark,book) }
                surface.addChildNode(book)
            }
            for j in 0..<44 {
                let a=Float(j)*0.18,b=Float(j+1)*0.18
                limb(SIMD3(25+cos(a)*3.5,0.18,-9+sin(a)*3.5),SIMD3(25+cos(b)*3.5,0.18,-9+sin(b)*3.5),0.12,dark,to:surface)
            }
        } else {
            // Streamlined radio/navigation console and a model finned rocket.
            box(12,3.8,6,-23,1.9,-19,wood,surface)
            gauge(-25,2.2,-15.8,1.25); gauge(-21,2.2,-15.8,1.25)
            for i in 0..<4 { box(0.25,1.8,0.2,-19+CGFloat(i)*0.45,2,-15.8,metal,surface) }
            add(SCNCylinder(radius:3.7,height:0.5),metal,SCNVector3(24,0.25,-19),to:surface)
            let rocket=SCNNode(); rocket.position=SCNVector3(24,0.7,-19)
            ball(SCNVector3(0,4.5,0),SCNVector3(1.4,4.5,1.4),ceramic,to:rocket)
            for j in 0..<3 {
                let fin=add(SCNPyramid(width:2.5,height:3.6,length:0.35),metal,SCNVector3Zero,to:rocket)
                fin.position=SCNVector3(sin(CGFloat(j)*2 * .pi/3)*1.25,1.2,cos(CGFloat(j)*2 * .pi/3)*1.25)
                fin.eulerAngles.y = .init(CGFloat(j)*2 * .pi/3)
            }
            add(SCNSphere(radius:0.45),dark,SCNVector3(0,5.5,1.25),to:rocket)
            surface.addChildNode(rocket)
        }
        // SceneKit's flattenedClone can silently return an empty mesh when
        // a large primitive batch exceeds its index limit. Keep modest batches.
        // Bake nested prop transforms before batching. SceneKit may discard a
        // geometry-free intermediate node's offset in a flattened clone.
        var parts: [SCNNode] = []
        surface.enumerateChildNodes { child, _ in if child.geometry != nil { parts.append(child) } }
        let transforms = parts.map { surface.convertTransform($0.transform, from: $0.parent) }
        for child in surface.childNodes { child.removeFromParentNode() }
        for (part, transform) in zip(parts, transforms) {
            part.removeFromParentNode(); part.transform = transform; surface.addChildNode(part)
        }
        surface.removeFromParentNode()
        flattened(props,name:prefix+"furniture-frame")
        var batch=0
        while !surface.childNodes.isEmpty {
            let group=SCNNode(); group.position=surface.position
            for child in Array(surface.childNodes.prefix(8)) { group.addChildNode(child) }
            flattened(group,name:prefix+"foreground-\(batch)")
            batch += 1
        }
    }

    private static func instrumentDial() -> NSImage {
        NSImage(size:NSSize(width:256,height:256),flipped:false) { rect in
            NSColor(srgbRed:0.75,green:0.69,blue:0.51,alpha:1).setFill(); rect.fill()
            for i in 0...36 {
                let angle=CGFloat(i)/36 * .pi*1.5 + .pi*0.75
                let outer=CGPoint(x:128+cos(angle)*109,y:128+sin(angle)*109)
                let inner=CGPoint(x:128+cos(angle)*(i%3 == 0 ? 88 : 98),y:128+sin(angle)*(i%3 == 0 ? 88 : 98))
                let path=NSBezierPath(); path.move(to:inner); path.line(to:outer); path.lineWidth=2
                NSColor(white:0.15,alpha:1).setStroke(); path.stroke()
            }
            let needle=NSBezierPath(); needle.move(to:CGPoint(x:128,y:128)); needle.line(to:CGPoint(x:78,y:195)); needle.lineWidth=4
            NSColor(srgbRed:0.36,green:0.13,blue:0.08,alpha:1).setStroke(); needle.stroke()
            return true
        }
    }

    /// A single invisible canopy mesh contributes to the existing sun shadow
    /// map. Real light occlusion shades stones and wood together, without a decal.
    private func makeCanopyShadow() {
        // The ground photograph is mostly canopy shade with small openings of
        // sunlight. Model that same topology: a continuous cover with irregular
        // holes, rather than isolated leaf silhouettes on an otherwise sunny board.
        let height: CGFloat = 19
        let shift = (height - 1) * 20 / 31.4
        let divisions = 128, extent: CGFloat = 50
        var vertices: [SCNVector3] = [], indices: [Int32] = []
        func noise(_ x: CGFloat, _ z: CGFloat) -> CGFloat {
            let ix = Int(floor(x)), iz = Int(floor(z))
            func value(_ x: Int, _ z: Int) -> CGFloat {
                var seed = UInt64(bitPattern: Int64(x)) &* 0x9e3779b97f4a7c15
                seed ^= UInt64(bitPattern: Int64(z)) &* 0xbf58476d1ce4e5b9
                seed &+= 73921
                seed = (seed ^ (seed >> 30)) &* 0xbf58476d1ce4e5b9
                seed = (seed ^ (seed >> 27)) &* 0x94d049bb133111eb
                seed ^= seed >> 31
                return CGFloat(seed >> 11) / 9007199254740992
            }
            func smooth(_ t: CGFloat) -> CGFloat { t * t * t * (t * (t * 6 - 15) + 10) }
            let u = smooth(x - CGFloat(ix)), v = smooth(z - CGFloat(iz))
            return (value(ix, iz) * (1 - u) + value(ix + 1, iz) * u) * (1 - v)
                 + (value(ix, iz + 1) * (1 - u) + value(ix + 1, iz + 1) * u) * v
        }
        // Sample a fixed, two-scale field once. Large foliage masses surround
        // smaller ragged gaps; nothing swims, loops or regenerates while playing.
        var samples: [(point: CGPoint, shade: CGFloat)] = []
        for row in 0...divisions {
            for column in 0...divisions {
                let x = CGFloat(column) / CGFloat(divisions) * extent * 2 - extent
                let z = CGFloat(row) / CGFloat(divisions) * extent * 2 - extent
                let opening = noise((x + z * 0.22) / 4.6, z / 4.6) * 0.72
                            + noise(x / 1.7, (z - x * 0.15) / 1.7) * 0.28
                samples.append((CGPoint(x: x, y: z), 0.62 - opening))
            }
        }
        func triangle(_ a: Int, _ b: Int, _ c: Int) {
            let corners = [samples[a], samples[b], samples[c]]
            var polygon: [CGPoint] = []
            for i in 0..<3 {
                let start = corners[i], end = corners[(i + 1) % 3]
                if start.shade >= 0 { polygon.append(start.point) }
                if (start.shade >= 0) != (end.shade >= 0) {
                    let t = start.shade / (start.shade - end.shade)
                    polygon.append(CGPoint(x: start.point.x + (end.point.x - start.point.x) * t,
                                           y: start.point.y + (end.point.y - start.point.y) * t))
                }
            }
            guard polygon.count >= 3 else { return }
            let base = Int32(vertices.count)
            vertices += polygon.map { SCNVector3($0.x - shift, height - KayaFloorBoard.sceneryOffset, $0.y - shift) }
            for i in 1..<(polygon.count - 1) { indices += [base, base + Int32(i), base + Int32(i + 1)] }
        }
        for row in 0..<divisions {
            for column in 0..<divisions {
                let a = row * (divisions + 1) + column, b = a + 1
                let c = a + divisions + 1, d = c + 1
                triangle(a, b, c); triangle(b, d, c)
            }
        }
        let geometry=SCNGeometry(sources:[.init(vertices:vertices)],
            elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        let material=SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents=NSColor.white; material.isDoubleSided=true
        material.colorBufferWriteMask=[]
        // Depth writes are required by the shadow pass. Render after the visible
        // scene so the invisible geometry cannot obscure any camera-view pixels.
        material.writesToDepthBuffer=true
        let canopy=add(geometry,material,SCNVector3Zero,to:node)
        canopy.name="canopy-shadow-caster"; canopy.renderingOrder=10000
    }

    // Photographic distant scenery cannot occlude the playing surface. The
    // room's actual shoji walls manage their own camera cutaway separately.
    func updateVisibility(camera: SCNVector3) {}

    func setFlickering(_ enabled: Bool) {
        guard let lamp, let flame, enabled != flickering else { return }
        flickering = enabled
        flame.childNodes.first?.geometry?.firstMaterial?.setValue(enabled ? Float(1) : Float(0), forKey: "flameMotion")
        lamp.removeAction(forKey: "lamp-flicker")
        flame.removeAction(forKey: "flame-motion")
        guard enabled else {
            lamp.removeAllAnimations()
            lamp.light?.removeAllAnimations(); flame.removeAllAnimations()
            SCNTransaction.begin(); SCNTransaction.disableActions = true
            lamp.position = lampRestPosition
            lamp.light?.intensity = Self.caveLampIntensity; flame.scale = SCNVector3(1, 1, 1)
            SCNTransaction.commit()
            return
        }
        // Drive the shader explicitly from the scene animation clock; relying
        // on an implicit shader time can leave a static geometry cache in place.
        flame.runAction(.repeatForever(.customAction(duration:60) { node, elapsed in
            node.childNodes.first?.geometry?.firstMaterial?.setValue(Float(elapsed), forKey:"flameTime")
        }), forKey:"flame-motion")
        let rest = lampRestPosition
        var tick = 0
        lamp.runAction(.repeatForever(.sequence([.wait(duration: 0.125), .run { [weak flame] lamp in
            tick += 1
            let t = Double(tick) * 0.125
            let variation = Self.lampVariation(at: t)
            let shimmer = variation.brightness
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.125
            lamp.light?.intensity = Self.caveLampIntensity * CGFloat(1 + shimmer)
            // Move the existing light at eight updates per second. Its one
            // shadow map supplies the moving shadows; no extra light or physics.
            lamp.position = SCNVector3(rest.x + variation.offset.x,
                                      rest.y + variation.offset.y,
                                      rest.z + variation.offset.z)
            flame?.scale.y = .init(1 + shimmer * 0.7)
            SCNTransaction.commit()
        }])), forKey: "lamp-flicker")
    }

    /// Smooth, independently seeded fluctuations at two time scales. Unlike
    /// periodic sine waves these do not settle into an obvious repeated rhythm.
    static func lampVariation(at time: Double) -> (brightness: Double, offset: SCNVector3) {
        func noise(_ rate: Double, _ seed: UInt64) -> Double {
            let t = max(0, time) * rate, cell = UInt64(t)
            func sample(_ i: UInt64) -> Double {
                var x = i &+ seed
                x = (x ^ (x >> 30)) &* 0xbf58476d1ce4e5b9
                x = (x ^ (x >> 27)) &* 0x94d049bb133111eb
                x ^= x >> 31
                return Double(x >> 11) / 9007199254740992 * 2 - 1
            }
            let f = t - floor(t), ease = f * f * (3 - 2 * f)
            return sample(cell) * (1 - ease) + sample(cell + 1) * ease
        }
        return (noise(0.73, 109) * 0.017 + noise(3.17, 971) * 0.008,
            SCNVector3(noise(1.31, 533) * 0.065, noise(2.09, 827) * 0.035, noise(0.91, 199) * 0.055))
    }

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, bounce: CGFloat = 0.35) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .lambert
        m.diffuse.contents = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        m.emission.contents = m.diffuse.contents; m.emission.intensity = bounce
        return m
    }
    private struct Random {
        var seed: UInt64 = 9731
        mutating func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 11) / 9007199254740992
        }
    }
    @discardableResult private func add(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SCNVector3, to root: SCNNode) -> SCNNode {
        g.materials = [m]; let n = SCNNode(geometry: g); n.position = p; root.addChildNode(n); return n
    }
    private func ball(_ p: SCNVector3, _ scale: SCNVector3, _ m: SCNMaterial, to root: SCNNode, segments: Int = 16) {
        let g = SCNSphere(radius: 1); g.segmentCount = segments
        add(g, m, p, to: root).scale = scale
    }
    private func limb(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ radius: CGFloat, _ m: SCNMaterial, to root: SCNNode) {
        let g = SCNCylinder(radius: radius, height: CGFloat(simd_length(b-a))); g.radialSegmentCount = 9
        let n = add(g, m, SCNVector3((a+b)/2), to: root)
        n.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: simd_normalize(b-a))
    }
    @discardableResult private func flattened(_ root: SCNNode, name: String, to parent: SCNNode? = nil) -> SCNNode {
        let result = root.flattenedClone(); result.name = name
        (parent ?? node).addChildNode(result); return result
    }

    /// Small deterministic grain texture, prepared once per scene, not per frame.
    @discardableResult private func ground(_ base: (CGFloat, CGFloat, CGFloat), bounce: CGFloat = 0.25) -> SCNMaterial {
        let m = Self.color(base.0, base.1, base.2, bounce: bounce)
        let size = 256
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        var random = Random(); let pixels = bitmap.bitmapData!
        for y in 0..<size { for x in 0..<size {
            let noise = (random.next() - 0.5) * 0.09
            let i = (y * size + x) * 4
            for (channel, value) in [base.0,base.1,base.2].enumerated() {
                pixels[i+channel] = UInt8(max(0, min(255, (value + noise) * 255)))
            }
            pixels[i+3] = 255
        }}
        let image = NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: size, height: size))
        m.diffuse.contents = image; m.emission.contents = image
        for property in [m.diffuse, m.emission] {
            property.wrapS = .repeat; property.wrapT = .repeat
            property.contentsTransform = SCNMatrix4MakeScale(60,60,1)
            property.mipFilter = .linear; property.minificationFilter = .linear; property.maxAnisotropy = 8
        }
        let n = add(SCNPlane(width: 900, height: 900), m, SCNVector3(0,-1.015,0), to: node)
        n.eulerAngles.x = -.pi / 2; n.name = "environment-ground"
        return m
    }

    /// Project the photograph onto a real floor around the board. Its baked
    /// detail and shadows remain fixed under camera translation; the distant
    /// panorama supplies the rest of the view without a forest of draw calls.
    private func makePhotographicGround() {
        guard let image = EnvironmentMaterials.panorama(kind) else {
            ground((0.34,0.33,0.29)); return
        }
        // Use the same azimuth and elevation mapping for the surrounding image
        // and its floor projection. SceneKit's background panorama convention
        // otherwise rotates the distant room relative to the floor.
        let latitudeCount=48, longitudeCount=128
        // Mirror the summit's surroundings and projected floor together so
        // the sunset sits to the right, without resampling the source image.
        let panoramaDirection: CGFloat = kind == .mountainSummit ? -1 : 1
        let windowMask = kind == .spaceStation ? EnvironmentMaterials.image("station-window-cutout.png") : nil
        let exterior = kind == .spaceStation ? EnvironmentMaterials.image("station-orbital-exterior.png") : nil
        let layeredStation = windowMask != nil && exterior != nil
        let roomRadius: CGFloat = layeredStation ? 220 : 400
        let centerY: CGFloat = kind.usesTableBoard ? 56.985 : 26.985
        var skyVertices:[SCNVector3]=[], skyUV:[CGPoint]=[], skyIndices:[Int32]=[]
        for latitude in 0...latitudeCount {
            let elevation=CGFloat(latitude)/CGFloat(latitudeCount) * .pi - .pi/2
            for longitude in 0...longitudeCount {
                let azimuth=CGFloat(longitude)/CGFloat(longitudeCount)*2 * .pi
                skyVertices.append(SCNVector3(roomRadius*sin(azimuth)*cos(elevation),
                    centerY+roomRadius*sin(elevation),-roomRadius*cos(azimuth)*cos(elevation)))
                skyUV.append(CGPoint(x:0.5+panoramaDirection*CGFloat(longitude)/CGFloat(longitudeCount),
                                     y:1-CGFloat(latitude)/CGFloat(latitudeCount)))
                if latitude<latitudeCount && longitude<longitudeCount {
                    let k=Int32(latitude*(longitudeCount+1)+longitude), n=k+Int32(longitudeCount+1)
                    skyIndices += [k,k+1,n,k+1,n+1,n]
                }
            }
        }
        let sky=SCNGeometry(sources:[.init(vertices:skyVertices),.init(textureCoordinates:skyUV)],
            elements:[SCNGeometryElement(indices:skyIndices,primitiveType:.triangles)])
        let skyMaterial=SCNMaterial(); skyMaterial.lightingModel = .constant
        skyMaterial.diffuse.contents=image; skyMaterial.diffuse.wrapS = .repeat
        skyMaterial.diffuse.mipFilter = .linear; skyMaterial.isDoubleSided=true
        skyMaterial.writesToDepthBuffer=false
        if kind == .cave {
            // The panorama contains photographed lighting. Attenuate it as well
            // as the actual lamps so the right wall cannot read as an entrance.
            skyMaterial.shaderModifiers = [.surface: """
            #pragma body
            float side = sin((_surface.diffuseTexcoord.x - 0.5) * 6.2831853);
            float darkness = mix(0.045,0.012,smoothstep(-0.1,0.8,side));
            _surface.diffuse.rgb *= darkness;
            """]
        }
        if layeredStation {
            // A closed outer sphere has no image edges to reveal during a pan.
            // It is over five times farther away than the window frame.
            let ratio = CGFloat(1200) / roomRadius
            let distantVertices = skyVertices.map { v in
                SCNVector3(CGFloat(v.x)*ratio, centerY+(CGFloat(v.y)-centerY)*ratio, CGFloat(v.z)*ratio)
            }
            let distant = SCNGeometry(sources: [.init(vertices: distantVertices), .init(textureCoordinates: skyUV)],
                elements: [SCNGeometryElement(indices: skyIndices, primitiveType: .triangles)])
            let space = SCNMaterial(); space.lightingModel = .constant
            space.diffuse.contents = exterior; space.diffuse.wrapS = .repeat
            space.diffuse.mipFilter = .linear; space.isDoubleSided = true
            space.writesToDepthBuffer = false
            let outside = add(distant, space, SCNVector3Zero, to: node)
            outside.name = "orbital-exterior"; outside.renderingOrder = -200
            makeStationWindowDividers(centerY: centerY)
            skyMaterial.transparent.contents = windowMask
            skyMaterial.transparent.wrapS = .repeat
            skyMaterial.transparent.mipFilter = .linear
            skyMaterial.transparencyMode = .aOne
            skyMaterial.shaderModifiers = [.fragment: """
            #pragma body
            if (_output.color.a < 0.5) { discard_fragment(); }
            _output.color.a = 1.0;
            """]
        }
        let skyNode=add(sky,skyMaterial,SCNVector3Zero,to:node)
        skyNode.name="photographic-surroundings"; skyNode.renderingOrder = -100
        let rings = kind == .japaneseGarden ? 420 : 48
        let segments = kind == .japaneseGarden ? 768 : 128
        // The summit ledge ends before the valley; a full 150-unit floor would
        // project a flat translucent shelf over the distant mountains.
        let radius: CGFloat=kind.usesTableBoard ? 350 : kind == .mountainSummit ? 75 : 150
        let opticalHeight: CGFloat=kind.usesTableBoard ? 58 : 28
        var vertices:[SCNVector3]=[], normals:[SCNVector3]=[], uv:[CGPoint]=[], maskUV:[CGPoint]=[], indices:[Int32]=[]
        for ring in 0...rings {
            let r=radius*pow(CGFloat(ring)/CGFloat(rings),1.5)
            for j in 0...segments {
                let a=CGFloat(j)*2 * .pi/CGFloat(segments)
                let x=sin(a)*r, z = -cos(a)*r
                if kind == .japaneseGarden {
                    let y = Self.gardenGroundHeight(x: x, z: z), epsilon: CGFloat = 0.025
                    let dx = (Self.gardenGroundHeight(x:x+epsilon,z:z)-Self.gardenGroundHeight(x:x-epsilon,z:z))/(2*epsilon)
                    let dz = (Self.gardenGroundHeight(x:x,z:z+epsilon)-Self.gardenGroundHeight(x:x,z:z-epsilon))/(2*epsilon)
                    vertices.append(SCNVector3(x,y,z))
                    normals.append(SCNVector3(simd_normalize(SIMD3<Float>(Float(-dx),1,Float(-dz)))))
                } else {
                    vertices.append(SCNVector3(x,-1.015,z)); normals.append(SCNVector3(0,1,0))
                }
                uv.append(CGPoint(x:0.5+panoramaDirection*CGFloat(j)/CGFloat(segments),y:0.5+atan2(opticalHeight,max(0.001,r)) / .pi))
                maskUV.append(CGPoint(x:x/(radius*2)+0.5,y:z/(radius*2)+0.5))
                if ring<rings && j<segments {
                    let k=Int32(ring*(segments+1)+j), n=k+Int32(segments+1)
                    indices += [k,k+1,n,k+1,n+1,n]
                }
            }
        }
        let geometry=SCNGeometry(sources:[.init(vertices:vertices),.init(normals:normals),.init(textureCoordinates:uv),.init(textureCoordinates:maskUV)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        let m=SCNMaterial(); m.lightingModel = .lambert
        m.diffuse.contents=image; m.diffuse.intensity=1.25
        m.emission.contents=image; m.emission.intensity = kind == .moon ? 0.025 : 0.10
        for channel in [m.diffuse,m.emission] { channel.wrapS = .repeat; channel.mipFilter = .linear; channel.maxAnisotropy=8 }
        let mask=NSImage(size:NSSize(width:128,height:128),flipped:false) { _ in
            guard let ctx=NSGraphicsContext.current?.cgContext else { return false }
            let colors=[NSColor.white.cgColor,NSColor.white.cgColor,NSColor(white:1,alpha:0).cgColor]
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:[0,0.6,1])!
            ctx.drawRadialGradient(gradient,startCenter:CGPoint(x:64,y:64),startRadius:0,endCenter:CGPoint(x:64,y:64),endRadius:64,options:[.drawsAfterEndLocation])
            return true
        }
        if kind == .monastery {
            makeMonasteryFloor(mask: mask)
            return
        }
        if kind == .yugenRoom {
            makeYugenFloor(mask: mask)
            return
        }
        m.transparent.contents=mask; m.transparent.mappingChannel=1; m.transparencyMode = .aOne
        EnvironmentMaterials.addGroundDetail(to: m, kind: kind)
        m.writesToDepthBuffer=true
        add(geometry,m,SCNVector3Zero,to:node).name="photographic-ground"
    }

    /// Nihon Ki-in's room has a pale blue-green rectangular rug over straight
    /// tatami. Geometry, rather than a radial photograph, defines every edge.
    private func makeYugenFloor(mask: NSImage) {
        func mesh(_ rectangles: [(CGFloat, CGFloat, CGFloat, CGFloat)], y: CGFloat, tile: CGFloat) -> SCNGeometry {
            var vertices: [SCNVector3] = [], uv: [CGPoint] = [], fadeUV: [CGPoint] = [], indices: [Int32] = []
            for (x0, z0, x1, z1) in rectangles {
                let start = Int32(vertices.count)
                for (x, z) in [(x0,z0),(x0,z1),(x1,z1),(x1,z0)] {
                    vertices.append(SCNVector3(x,y,z))
                    uv.append(CGPoint(x:x/tile,y:z/tile))
                    fadeUV.append(CGPoint(x:x/300+0.5,y:z/300+0.5))
                }
                indices += [start,start+1,start+2,start,start+2,start+3]
            }
            return SCNGeometry(sources: [.init(vertices:vertices),
                .init(normals:Array(repeating:SCNVector3(0,1,0),count:vertices.count)),
                .init(textureCoordinates:uv),.init(textureCoordinates:fadeUV)],
                elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        }
        func fading(_ material: SCNMaterial) {
            material.transparent.contents = mask; material.transparent.mappingChannel = 1
            material.transparencyMode = .aOne
        }
        let binding = SCNMaterial(); binding.lightingModel = .lambert
        binding.diffuse.contents = NSColor(srgbRed:0.19,green:0.23,blue:0.19,alpha:1)
        fading(binding)
        add(mesh([(-150,-150,150,150)],y:-1.07,tile:1),binding,SCNVector3Zero,to:node).name = "yugen-mat-bindings"
        let tatami = SCNMaterial(); tatami.lightingModel = .lambert
        tatami.diffuse.contents = NSImage(named:TatamiTexture.assetName) ?? NSColor(srgbRed:0.68,green:0.64,blue:0.43,alpha:1)
        tatami.emission.contents = tatami.diffuse.contents; tatami.emission.intensity = 0.07
        for property in [tatami.diffuse,tatami.emission] {
            property.wrapS = .mirror; property.wrapT = .mirror
            property.mipFilter = .linear; property.minificationFilter = .linear; property.maxAnisotropy = 16
        }
        fading(tatami)
        let unitsPerCM = (20 * CGFloat(1.0773)) / 45.5
        let width = 90 * unitsPerCM, length = width * 2, border = 2 * unitsPerCM
        var mats: [(CGFloat,CGFloat,CGFloat,CGFloat)] = []
        for row in -2...1 { for column in -4...3 {
            let x = CGFloat(column)*width, z = CGFloat(row)*length
            mats.append((x+border/2,z+0.035,x+width-border/2,z+length-0.035))
        }}
        add(mesh(mats,y:-1.055,tile:96*unitsPerCM),tatami,SCNVector3Zero,to:node).name = "yugen-floor-mats"
        let hem = SCNMaterial(); hem.lightingModel = .lambert
        hem.diffuse.contents = NSColor(srgbRed:0.39,green:0.47,blue:0.43,alpha:1)
        add(mesh([(-42.2,-58.2,42.2,58.2)],y:-1.035,tile:1),hem,SCNVector3Zero,to:node).name = "yugen-rug-binding"
        let rug = SCNMaterial(); rug.name = "yugen-flat-woven-rug"; rug.lightingModel = .lambert
        rug.diffuse.contents = NSColor(srgbRed:0.59,green:0.69,blue:0.65,alpha:1)
        rug.multiply.contents = EnvironmentMaterials.image("yugen-carpet-color.jpg") ?? NSColor(white:0.2,alpha:1)
        rug.normal.contents = EnvironmentMaterials.image("yugen-carpet-normal.jpg"); rug.normal.intensity = 0.12
        for property in [rug.multiply,rug.normal] {
            property.wrapS = .repeat; property.wrapT = .repeat
            property.mipFilter = .linear; property.minificationFilter = .linear; property.maxAnisotropy = 16
        }
        rug.shaderModifiers = [.surface: """
        #pragma body
        float grain = dot(_surface.multiply.rgb, float3(0.2126,0.7152,0.0722));
        _surface.diffuse.rgb *= mix(1.0,clamp(grain / 0.03373,0.65,1.35),0.28);
        _surface.emission.rgb = _surface.diffuse.rgb * 0.08;
        _surface.multiply = float4(1.0);
        """]
        add(mesh([(-42,-58,42,58)],y:-1.015,tile:18),rug,SCNVector3Zero,to:node).name = "photographic-ground"
    }

    /// Curved, solid mullions sit just inside the window shell. Their depth,
    /// worn edges and bolted collars provide a near reference for the exterior.
    private func makeStationWindowDividers(centerY: CGFloat) {
        let metal = Self.stationFinish("station-worn-ivory.png", tint: 0.85, metalness: 0.4)
        metal.emission.intensity = 0.35
        let seal = Self.stationFinish("station-worn-graphite.png", tint: 0.24, metalness: 0.1)
        let bolt = Self.stationFinish("station-worn-ivory.png", tint: 0.8, metalness: 0.8)
        for azimuth: CGFloat in [-0.38, 0.38] {
            let rib = SCNNode()
            for i in 0..<24 {
                let elevation = CGFloat(i) * 1.08 / 24 + 0.005
                let radius: CGFloat = 215
                let position = SCNVector3(0, centerY+radius*sin(elevation), -radius*cos(elevation))
                for (width, depth, material) in [(CGFloat(6.6), CGFloat(2.0), seal), (5.0, 4.0, metal)] {
                    let box = SCNBox(width: width, height: radius*1.08/24+0.15, length: depth, chamferRadius: 0.2)
                    let part = SCNNode(geometry: Self.stationMappedBox(box, origin: position))
                    part.geometry?.firstMaterial = material
                    part.position = position; part.eulerAngles.x = .init(elevation)
                    rib.addChildNode(part)
                }
                if i % 6 == 0 {
                    let collar = SCNNode(geometry: SCNBox(width: 6.8, height: 2.8, length: 4.6, chamferRadius: 0.25))
                    collar.geometry?.firstMaterial = metal
                    collar.position = position; collar.eulerAngles.x = .init(elevation)
                    rib.addChildNode(collar)
                    for x: CGFloat in [-1.35, 1.35] {
                        let head = SCNNode(geometry: SCNSphere(radius: 0.35))
                        head.geometry?.firstMaterial = bolt
                        head.position = SCNVector3(x, centerY+(radius-2.4)*sin(elevation), -(radius-2.4)*cos(elevation))
                        head.eulerAngles.x = .init(elevation); head.scale.z = 0.4
                        rib.addChildNode(head)
                    }
                }
            }
            let divider = rib.flattenedClone()
            divider.eulerAngles.y = .init(-azimuth)
            divider.name = "viewport-scuffed-mullion"
            node.addChildNode(divider)
        }
    }

    /// Batched, individually laid boards. Their long axis is world X, horizontal
    /// in the seated view. Real joints and planar UVs avoid the panorama's pole.
    private func makeMonasteryFloor(mask: NSImage) {
        var random = Random(seed: 4183)
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
        var uv: [CGPoint] = [], maskUV: [CGPoint] = [], tones: [CGPoint] = [], indices: [Int32] = []
        var z: CGFloat = -150
        while z < 150 {
            let width = min(6.5 + random.next() * 4.5, 150 - z)
            var x: CGFloat = -150
            var first = true
            while x < 150 {
                let length = min((first ? 30 : 85) + random.next() * 65, 150 - x)
                let offset = CGPoint(x: random.next() * 3, y: random.next() * 3)
                let tone = 0.72 + random.next() * 0.48
                // Each edge has its own worn contour; chipped lips and unequal
                // end clearances reveal the recessed, dark joints beneath.
                let gap = 0.055 + random.next() * 0.13
                let endGap = 0.045 + random.next() * 0.20
                let strips = max(1, Int(ceil(length / 2.8)))
                let start = Int32(vertices.count)
                for segment in 0...strips {
                    let px = x + endGap + (length - endGap * 2) * CGFloat(segment) / CGFloat(strips)
                    let lowerChip = random.next() < 0.14 ? random.next() * 0.26 : random.next() * 0.035
                    let upperChip = random.next() < 0.14 ? random.next() * 0.26 : random.next() * 0.035
                    for pz in [z + gap + lowerChip, z + width - gap - upperChip] {
                        vertices.append(SCNVector3(px, -1.015, pz)); normals.append(SCNVector3(0, 1, 0))
                        let scanRow = floor(offset.y * 4)
                        uv.append(CGPoint(x: (px - x) / 110 + offset.x,
                            y: 0.045 + scanRow * 0.076 + (pz - z) / width * 0.054))
                        maskUV.append(CGPoint(x: px / 300 + 0.5, y: pz / 300 + 0.5))
                        tones.append(CGPoint(x: tone, y: 0))
                    }
                    if segment < strips {
                        let k = start + Int32(segment * 2)
                        indices += [k,k+1,k+2,k+2,k+1,k+3]
                    }
                }
                x += length; first = false
            }
            z += width
        }
        let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals),
            .init(textureCoordinates: uv), .init(textureCoordinates: maskUV), .init(textureCoordinates: tones)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let wood = EnvironmentMaterials.scanned("weathered_brown_planks")
        wood.name = "monastery-worn-floorboards"
        wood.normal.intensity = 0.70
        wood.emission.contents = wood.diffuse.contents; wood.emission.intensity = 0.035
        let white = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill(); return true
        }
        wood.multiply.contents = white; wood.multiply.mappingChannel = 2
        wood.transparent.contents = mask; wood.transparent.mappingChannel = 1; wood.transparencyMode = .aOne
        for channel in [wood.diffuse, wood.normal, wood.roughness, wood.ambientOcclusion, wood.emission] {
            channel.wrapS = .repeat; channel.wrapT = .repeat
            channel.mipFilter = .linear; channel.minificationFilter = .linear; channel.maxAnisotropy = 16
        }
        wood.shaderModifiers = [.surface: """
        #pragma body
        float tone = _surface.multiplyTexcoord.x;
        float2 floorPosition = (_surface.transparentTexcoord - float2(0.5)) * 300.0;
        // Broad irregular rubbed patches follow each plank, without tiled decals.
        float2 wearUV = floorPosition / float2(8.0,3.2) + tone * 19.0;
        float2 cell = floor(wearUV), f = fract(wearUV);
        f = f*f*(3.0-2.0*f);
        float4 hashes = fract(sin(float4(dot(cell,float2(127.1,311.7)),
            dot(cell+float2(1,0),float2(127.1,311.7)),
            dot(cell+float2(0,1),float2(127.1,311.7)),
            dot(cell+float2(1,1),float2(127.1,311.7))))*43758.5453);
        float wear = smoothstep(0.30,0.77,mix(mix(hashes.x,hashes.y,f.x),mix(hashes.z,hashes.w,f.x),f.y));
        float3 grain = _surface.diffuse.rgb;
        float gray = dot(grain,float3(0.2126,0.7152,0.0722));
        _surface.diffuse.rgb = mix(grain*float3(0.52,0.40,0.30),
            gray*float3(0.83,0.74,0.62),wear*0.72)*tone;
        // Sparse, unequal grain-aligned scratches with worn pale edges.
        float2 scratchUV = floorPosition / float2(8.5,1.9) + tone*71.0;
        float2 scratchCell = floor(scratchUV), sf = fract(scratchUV);
        float seed = fract(sin(dot(scratchCell,float2(12.9898,78.233)))*43758.5453);
        float line = abs(sf.y-(0.2+seed*0.6));
        float ends = smoothstep(0.03,0.16,sf.x)*(1.0-smoothstep(0.45+seed*0.35,0.95,sf.x));
        float aa = max(fwidth(line),0.005);
        float scratch = (1.0-smoothstep(0.004,0.028+aa,line))*ends*step(0.36,seed);
        float edge = (1.0-smoothstep(0.018,0.070+aa,line))*ends*step(0.36,seed);
        _surface.diffuse.rgb *= 1.0-scratch*0.47;
        _surface.diffuse.rgb += float3(0.035,0.027,0.018)*(edge-scratch);
        _surface.emission.rgb *= tone*(0.72+wear*0.28)*(1.0-scratch*0.47);
        // Unequal diagonal scrapes and deeper grain-following gouges. Dark
        // troughs, exposed pale lips and tilted normals give the damage depth.
        float2 scarUV = float2(floorPosition.x + floorPosition.y * 0.28, floorPosition.y) / float2(13.0,4.3) + tone*103.0;
        float2 scarCell = floor(scarUV), gf = fract(scarUV);
        float gs = fract(sin(dot(scarCell,float2(93.17,17.43)))*19642.349);
        float center = 0.18 + gs*0.64;
        float signedLine = gf.y - center - 0.06*sin(gf.x*4.0+gs*9.0);
        float gougeEnds = smoothstep(0.04,0.18,gf.x)*(1.0-smoothstep(0.48+gs*0.20,0.92,gf.x));
        float width = 0.009 + gs*0.025;
        float gaa = max(fwidth(signedLine),0.002);
        float gouge = (1.0-smoothstep(width,width+gaa,abs(signedLine)))*gougeEnds*step(0.57,gs);
        float lip = (1.0-smoothstep(width+gaa,width+0.018+gaa,abs(signedLine)))*gougeEnds*step(0.57,gs);
        _surface.diffuse.rgb *= 1.0-gouge*0.72;
        _surface.diffuse.rgb += float3(0.075,0.053,0.032)*max(0.0,lip-gouge);
        float3 scarNormal = normalize(float3(-0.12,1.0,sign(signedLine)*0.9));
        float3 viewScarNormal = normalize((scn_node.normalTransform * float4(scarNormal,0.0)).xyz);
        _surface.normal = normalize(mix(_surface.normal,viewScarNormal,gouge*0.6));
        _surface.emission.rgb *= 1.0-gouge*0.72;
        // Dry, abraded wood has broad muted reflections, never polished patches.
        _surface.roughness = clamp(0.82+_surface.roughness*0.14+scratch*0.04+gouge*0.05,0.84,0.99);
        _surface.multiply = float4(1.0);
        """]
        add(geometry, wood, SCNVector3Zero, to: node).name = "photographic-ground"
        // A dark substrate is visible only through the narrow physical joints.
        let backing = Self.color(0.045, 0.029, 0.020, bounce: 0.08)
        backing.transparent.contents = mask; backing.transparencyMode = .aOne
        let underlay = add(SCNPlane(width: 300, height: 300), backing, SCNVector3(0, -1.16, 0), to: node)
        underlay.eulerAngles.x = -.pi / 2; underlay.name = "monastery-floor-joints"
    }

    /// Compressed round zafu, with irregular pleats, a sewn rim and worn cloth.
    private func makeMonasteryCushions() {
        let profile: [(CGFloat, CGFloat)] = [(0,3.85),(1.5,3.92),(3.5,4.15),(5.2,4.6),(6.5,4.9),
            (7.1,4.6),(7.5,4.0),(7.65,3.1),(7.6,2.0),(7.35,0.8),(6.8,0.18),(4,0.12),(0,0.12)]
        let segments = 128
        var vertices: [SCNVector3] = [], uv: [CGPoint] = [], indices: [Int32] = []
        for (ring, pair) in profile.enumerated() {
            for j in 0...segments {
                let a = CGFloat(j) * 2 * .pi / CGFloat(segments)
                let pleat = ring >= 5 && ring <= 10 ? 0.16 * pow(0.5 + 0.5*cos(a*36 + 0.2*sin(a*5)), 4) : 0
                let r = pair.0 * (1 + 0.018*sin(a*3) + 0.009*cos(a*7)) - pleat
                let y = pair.1 + (ring < 6 ? 0.08*sin(a*13)*pair.0/7.5 : 0)
                vertices.append(SCNVector3(r*sin(a), y, r*cos(a)*0.96))
                uv.append(CGPoint(x:0.5 + sin(a)*pair.0/16, y:0.5 + cos(a)*pair.0/16))
                if ring < profile.count-1 && j < segments {
                    let k = Int32(ring*(segments+1)+j), next = k + Int32(segments+1)
                    indices += [k,next,k+1,k+1,next,next+1]
                }
            }
        }
        var normals = Array(repeating: SIMD3<Float>.zero, count: vertices.count)
        for i in stride(from:0,to:indices.count,by:3) {
            let a=Int(indices[i]), b=Int(indices[i+1]), c=Int(indices[i+2])
            let n=simd_cross(SIMD3<Float>(vertices[b])-SIMD3<Float>(vertices[a]),SIMD3<Float>(vertices[c])-SIMD3<Float>(vertices[a]))
            normals[a]+=n; normals[b]+=n; normals[c]+=n
        }
        let geometry=SCNGeometry(sources:[.init(vertices:vertices),.init(normals:normals.map { SCNVector3(simd_length_squared($0)>0.000001 ? simd_normalize($0) : SIMD3(0,1,0)) }),.init(textureCoordinates:uv)],elements:[.init(indices:indices,primitiveType:.triangles)])
        let cloth = SCNMaterial(); cloth.name = "worn-indigo-zafu"; cloth.lightingModel = .physicallyBased
        cloth.diffuse.contents = EnvironmentMaterials.image("zafu-worn-cloth.png") ?? NSColor.darkGray
        cloth.normal.contents = EnvironmentMaterials.image("zabuton-cloth-normal.jpg"); cloth.normal.intensity = 0.16
        cloth.roughness.contents = 0.96
        cloth.emission.contents = cloth.diffuse.contents; cloth.emission.intensity = 0.025
        cloth.diffuse.mipFilter = .linear; cloth.diffuse.maxAnisotropy = 16
        for (side,z) in [("player",CGFloat(23)),("opponent",CGFloat(-23))] {
            let cushion=SCNNode(); cushion.name="zabuton-\(side)"; cushion.position=SCNVector3(0,-1.015,z)
            cushion.eulerAngles.y = side == "player" ? 0.23 : -0.5
            node.addChildNode(cushion)
            add(geometry,cloth,SCNVector3Zero,to:cushion).name="zabuton-body-\(side)"
            let thread = Self.color(0.28,0.27,0.24,bounce:0.06), seam=SCNNode()
            for j in 0..<96 {
                let a=Float(j)*2 * .pi/96, b=Float(j+1)*2 * .pi/96
                limb(SIMD3(sin(a)*7.12,4.58,cos(a)*6.84),SIMD3(sin(b)*7.12,4.58,cos(b)*6.84),0.035,thread,to:seam)
            }
            for j in 0..<12 {
                let a = Float(j)*0.024 + 0.8
                limb(SIMD3(sin(a)*7.25,3.4,cos(a)*6.96),SIMD3(sin(a+0.015)*7.3,3.85,cos(a+0.015)*7.0),0.025,thread,to:seam)
            }
            flattened(seam,name:"zabuton-seam-\(side)",to:cushion)
        }
    }

    /// Reference-informed floor chairs and separate padded elbow rests, as in
    /// the Nihon Ki-in's Yugen-no-ma. All parts are batched into two seat meshes.
    private func makeYugenSeats() {
        let wood = EnvironmentMaterials.scanned("fine_grained_wood")
        wood.multiply.contents = NSColor(srgbRed: 0.32, green: 0.17, blue: 0.12, alpha: 1)
        wood.roughness.contents = EnvironmentMaterials.image("weathered_brown_planks-rough.jpg") ?? 0.62
        wood.diffuse.contents = EnvironmentMaterials.image("coffee-table-wood.png") ?? wood.diffuse.contents
        wood.normal.intensity = 0.28
        wood.emission.contents = wood.diffuse.contents; wood.emission.intensity = 0.04
        let cloth = Self.color(0.44, 0.43, 0.27, bounce: 0.14)
        cloth.lightingModel = .physicallyBased; cloth.roughness.contents = 0.9
        cloth.normal.contents = EnvironmentMaterials.image("zabuton-cloth-normal.jpg")
        cloth.normal.intensity = 0.16
        // A restrained woven floral motif, with tiny thread variation. It is
        // upholstery, not a repeated photograph of furniture or a flat cutout.
        cloth.diffuse.contents = EnvironmentMaterials.image("yugen-worn-brocade.png") ?? NSColor.brown
        cloth.emission.contents = cloth.diffuse.contents; cloth.emission.intensity = 0.035
        cloth.diffuse.mipFilter = .linear; cloth.diffuse.maxAnisotropy = 16
        wood.shaderModifiers = [.surface: """
        #pragma body
        float2 uv = _surface.diffuseTexcoord;
        float edge = 1.0 - smoothstep(0.015, 0.085, min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y)));
        float rub = edge * (0.45 + 0.55*sin(uv.x*71.0+uv.y*37.0)*sin(uv.y*53.0));
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(0.26,0.13,0.055), rub*0.28);
        _surface.roughness = clamp(_surface.roughness - rub*0.18, 0.3, 0.85);
        """]
        for (side, sign) in [("player", CGFloat(1)), ("opponent", CGFloat(-1))] {
            let seat = SCNNode()
            func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ radius: CGFloat, _ material: SCNMaterial) {
                add(SCNBox(width:w,height:h,length:d,chamferRadius:radius),material,SCNVector3(x,y,z),to:seat)
            }
            // Low runners, a gently reclined upholstered back, and broad cushion.
            for x: CGFloat in [-8.6,8.6] {
                box(1.1,0.8,19,x,0.4,0,0.18,wood)
                let post = add(SCNBox(width:1.0,height:15,length:1.2,chamferRadius:0.2),wood,SCNVector3(x,7.5,8),to:seat)
                post.eulerAngles.x = 0.10
            }
            box(17,0.7,16,0,0.9,0,0.25,wood)
            box(16.8,1.8,15.8,0,2.0,0,0.8,cloth)
            let back = add(SCNBox(width:16.4,height:11.8,length:1.3,chamferRadius:0.55),cloth,SCNVector3(0,8.8,8),to:seat)
            back.eulerAngles.x = 0.10
            // One independent armrest to each player's right; clear of bowls.
            for z: CGFloat in [-4.5,4.5] {
                box(5.3,0.65,1.5,13,0.33,z,0.2,wood)
                box(1.1,7,1.2,13,3.7,z,0.2,wood)
            }
            box(5.5,0.7,14,13,7.1,0,0.3,wood)
            box(5.9,1.6,14.3,13,8.1,0,0.75,cloth)
            let batch = flattened(seat, name:"yugen-furniture-\(side)")
            batch.position = SCNVector3(0,-1.015,sign * 25)
            batch.eulerAngles.y = sign > 0 ? 0 : .pi
        }
    }

    /// A floor-grown flowstone column: flared foot, uneven vertical flutes,
    /// layered mineral lips and a rounded, worn crown supporting the lamp.
    static let caveLampBaseHeight: CGFloat = 10
    static let caveLampIntensity: CGFloat = 1600
    // Board coordinates. Keep the source outside the entire playing surface,
    // low enough for long shadows, without moving the visible lantern.
    static let caveLampWorldPosition = SCNVector3(28,14,-24)

    private static func caveLampStalagmite() -> SCNGeometry {
        let rings = 128, segments = 96
        let height = Float(caveLampBaseHeight + 1.015)
        var points: [SIMD3<Float>] = []
        for ring in 0...rings {
            let t = Float(ring) / Float(rings), y = t * (height + 0.8) - 0.8
            let radius = 1.62 + 2.1 * pow(1-t,0.95) + 0.9 * exp(-t*14)
                + 1.6 * exp(-max(0,y)*1.8) // Low stone apron at the floor.
            for j in 0..<segments {
                let angle = Float(j) / Float(segments) * 2 * .pi
                // Narrow runoff ribs merge into broader lobes at the base.
                let flutes = 0.10*sin(angle*7 + t*1.4) + 0.045*cos(angle*11 - t*2)
                let asymmetry = 0.12*sin(angle*3+0.8) * (1-t)
                let layers = 0.055*sin(y*4.8 + sin(angle*3)*0.9)
                    + 0.026*sin(y*11.3 + cos(angle*5))
                let r = radius * (1 + flutes + asymmetry) + layers * sin(t * .pi)
                // The narrow crown meets the lowered lamp base.
                let crownBlend = min(1, max(0, (1-t)*10))
                let x = cos(angle)*r + 0.75*sin(t * .pi)
                let z = sin(angle)*r*0.91 - 0.32*sin(t * .pi)
                points.append(SIMD3(x, y - crownBlend*0.06*sin(angle*5), z))
            }
        }
        var indices: [Int32] = []
        for ring in 0..<rings { for j in 0..<segments {
            let a = Int32(ring*segments+j), b = Int32(ring*segments+(j+1)%segments)
            let c = a+Int32(segments), d = b+Int32(segments)
            indices += [a,c,b,b,c,d]
        }}
        let center = Int32(points.count); points.append(SIMD3(0,height,0))
        let last = Int32(rings*segments)
        for j in 0..<segments { indices += [last+Int32(j),center,last+Int32((j+1)%segments)] }
        var normals = Array(repeating: SIMD3<Float>.zero, count: points.count)
        for i in stride(from:0,to:indices.count,by:3) {
            let a=Int(indices[i]), b=Int(indices[i+1]), c=Int(indices[i+2])
            let n=simd_cross(points[b]-points[a],points[c]-points[a])
            normals[a] += n; normals[b] += n; normals[c] += n
        }
        let mesh = SCNGeometry(sources: [
            SCNGeometrySource(vertices: points.map { SCNVector3($0.x,$0.y,$0.z) }),
            SCNGeometrySource(normals: normals.map {
                let n=simd_normalize($0); return SCNVector3(n.x,n.y,n.z)
            }),
            SCNGeometrySource(textureCoordinates: points.map { CGPoint(x:CGFloat($0.x/8),y:CGFloat($0.y/8)) })
        ], elements: [SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        mesh.name = "flowstone-stalagmite"
        return mesh
    }

    private func makeCave() {
        makePhotographicGround()
        let pedestal = add(Self.caveLampStalagmite(), EnvironmentMaterials.caveStalagmite(groundOrigin: SCNVector3(19,0,-16)),
                           SCNVector3(19,-1.015,-16), to: node)
        pedestal.name = "oil-lamp-rock"
        let lantern = SCNNode()
        let metal = EnvironmentMaterials.scanned("fine_grained_wood")
        metal.diffuse.contents = NSColor(srgbRed:0.19,green:0.14,blue:0.085,alpha:1)
        metal.emission.contents=NSColor(srgbRed:0.14,green:0.09,blue:0.04,alpha:1)
        metal.emission.intensity=0.12
        metal.lightingModel = .blinn
        metal.specular.contents = NSColor(white:0.12,alpha:1); metal.shininess = 32
        metal.normal.intensity=0.15; metal.metalness.contents=0.8; metal.roughness.contents=0.65
        let reservoir = SCNCylinder(radius:1.25,height:1.1); reservoir.radialSegmentCount = 48
        add(reservoir,metal,SCNVector3(24,14.55,-18),to:lantern)
        for (y,r) in [(14.05,1.22),(15.05,1.20),(18.55,1.1)] {
            let rim=SCNTorus(ringRadius:r,pipeRadius:0.09); rim.ringSegmentCount=48; rim.pipeSegmentCount=8
            add(rim,metal,SCNVector3(24,y,-18),to:lantern)
        }
        add(SCNCylinder(radius:0.35,height:0.35),metal,SCNVector3(24,15.25,-18),to:lantern)
        for dx: CGFloat in [-1.25,1.25] { limb(SIMD3(Float(24+dx),14.8,-18),SIMD3(Float(24+dx),18.8,-18),0.095,metal,to:lantern) }
        add(SCNCone(topRadius:0.65,bottomRadius:1.4,height:0.65),metal,SCNVector3(24,18.85,-18),to:lantern)
        let handle = SCNTorus(ringRadius:1.05,pipeRadius:0.075); handle.ringSegmentCount = 40; handle.pipeSegmentCount = 8
        add(handle,metal,SCNVector3(24,20.2,-18),to:lantern).eulerAngles.x = .pi/2
        flattened(lantern,name:"oil-lamp-housing")
        let glass=SCNMaterial(); glass.lightingModel = .blinn
        glass.diffuse.contents=NSColor(white:0.75,alpha:0.09)
        glass.specular.contents=NSColor(white:1,alpha:1); glass.shininess=120
        glass.transparency=0.20; glass.isDoubleSided=true; glass.writesToDepthBuffer=false
        let chimney=SCNCylinder(radius:0.99,height:3.15); chimney.radialSegmentCount=48
        add(chimney,glass,SCNVector3(24,16.9,-18),to:node).name="oil-lamp-glass"
        let fireNode=SCNNode(); fireNode.position=SCNVector3(24,15.45,-18)
        fireNode.name="oil-lamp-flame"; node.addChildNode(fireNode); flame=fireNode
        // A photographic flame with additive optical glow stays translucent.
        // Only this tiny card faces the viewer; the lamp remains solid geometry.
        let fire=SCNMaterial(); fire.lightingModel = .constant
        fire.diffuse.contents=EnvironmentMaterials.image("oil-flame.png") ?? NSColor.orange
        fire.blendMode = .add; fire.isDoubleSided=true; fire.writesToDepthBuffer=false
        fire.diffuse.mipFilter = .linear
        fire.setValue(Float(0), forKey: "flameMotion")
        fire.setValue(Float(0), forKey: "flameTime")
        // Bend the tip while anchoring the wick. Independent, overlapping
        // frequencies make the silhouette visibly breathe without pulsing the room.
        fire.shaderModifiers = [.geometry: """
        #pragma arguments
        float flameMotion;
        float flameTime;
        #pragma body
        float t = flameTime;
        float h = clamp((_geometry.position.y + 1.05) / 2.1, 0.0, 1.0);
        float sway = 0.24 * sin(t * 7.3) + 0.11 * sin(t * 13.7 + 1.2);
        _geometry.position.x += flameMotion * h * h * sway;
        _geometry.position.y += flameMotion * h * (0.22 * sin(t * 9.1) + 0.10 * sin(t * 17.3));
        _geometry.position.x *= 1.0 + flameMotion * h * 0.12 * sin(t * 11.9);
        """]
        let flameMesh = SCNPlane(width:1.3,height:2.1)
        flameMesh.widthSegmentCount = 4; flameMesh.heightSegmentCount = 16
        let card=add(flameMesh,fire,SCNVector3(0,1.05,0),to:fireNode)
        let facing=SCNBillboardConstraint(); facing.freeAxes = .Y; card.constraints=[facing]
        let light = SCNNode(); light.name = "oil-lamp-light"; light.position = SCNVector3(24,17,-18)
        light.light = SCNLight(); light.light?.type = .spot
        light.look(at:SCNVector3(0,-1,0))
        light.light?.spotInnerAngle=70; light.light?.spotOuterAngle=90
        light.light?.color = NSColor(srgbRed:1,green:0.73,blue:0.43,alpha:1)
        // Keep the playing surface in the bright part of the falloff, including
        // the far corner. The visible lamp stays on its original support.
        light.light?.intensity = Self.caveLampIntensity; light.light?.attenuationStartDistance = 40
        light.light?.attenuationEndDistance = 140; light.light?.attenuationFalloffExponent = 1
        light.light?.castsShadow = true; light.light?.categoryBitMask = -1
        light.light?.shadowMapSize=CGSize(width:2048,height:2048)
        light.light?.shadowSampleCount=16; light.light?.shadowRadius=1
        light.light?.shadowColor=NSColor(white:0,alpha:0.96); light.light?.shadowBias=0.003
        light.light?.zNear=0.5; light.light?.zFar=110
        node.addChildNode(light); lamp = light
        for child in node.childNodes where child.name != "photographic-ground" && child.name != "environment-ground" && child.name != "photographic-surroundings" {
            if child !== pedestal {
                child.position.x -= 5; child.position.z += 2
                #if os(iOS)
                child.position.y += Float(Self.caveLampBaseHeight) - 14
                #else
                child.position.y += Self.caveLampBaseHeight - 14
                #endif
            }
        }
        let source = Self.caveLampWorldPosition
        light.position = SCNVector3(Float(source.x), Float(source.y) - Float(kind.sceneryOffset), Float(source.z))
        // Aim at the playing surface, not the cave floor below the slab.
        light.look(at: SCNVector3(0, 1 - Float(kind.sceneryOffset), 0))
        lampRestPosition = light.position
    }
}
