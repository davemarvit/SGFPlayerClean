// ========================================================
// FILE: ./Models/SceneManager3D.swift
// VERSION: v4.500 (HitTest Debug & Retina Fix)
// ========================================================
import Foundation
import SceneKit
import AppKit
import QuartzCore
import simd

class SceneManager3D: NSObject, ObservableObject {
    static let backgroundColor = NSColor(srgbRed: 0.01, green: 0.01, blue: 0.05, alpha: 1)
    // ... (Init/Setup code identical to v4.401, omitted for brevity except changed HitTest) ...
    // COPY ALL properties and init from v4.401
    let scene = SCNScene(); let cameraNode = SCNNode(); let pivotNode = SCNNode()
    private let worldAnchor = SCNNode()
    private let stonesContainer = SCNNode()
    private var blackStoneGeometry: SCNGeometry?; private var clamGeometries: [SCNGeometry] = []
    private var stoneNodeMap: [BoardPosition: SCNNode] = [:]
    private var markerMaterial: SCNMaterial?; private var glowMaterial: SCNMaterial?
    private var whiteMaterial: SCNMaterial?; private var blackMaterial: SCNMaterial? // Store references
    private var boardNode: SCNNode?; private var ghostNode: SCNNode?
    private var upperLidStones: [SCNNode] = []; private var lowerLidStones: [SCNNode] = []
    private var upperLidNode: SCNNode?; private var lowerLidNode: SCNNode?
    private var aiHintNodes: [SCNNode] = [] // 3D AI OVERLAYS
    private var boardSize: Int = 19
    private let boardThickness: CGFloat = 2.0
    // Dynamic Radius: 48% of cell width (leaves 4% gap)
    private var stoneRadius: CGFloat { effectiveCellWidth * 0.48 }
    private let stoneScaleY: CGFloat = 0.486
    private let capturedStoneRadius: CGFloat = 0.48
    private var previousLastMove: BoardPosition?
    private lazy var koMarkerTexture: NSImage = {
        let size: CGFloat = 128
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let colors = [0.96, 0.9, 0.38, 0].map {
                NSColor(srgbRed: 0.9, green: 0.08, blue: 0.06, alpha: $0).cgColor
            }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors as CFArray, locations: [0, 0.22, 0.58, 1]) else { return false }
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
                                       endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size / 2, options: [])
            return true
        }
    }()
    private var effectiveCellWidth: CGFloat { CGFloat(18) / CGFloat(max(1, boardSize - 1)) }
    private var effectiveCellHeight: CGFloat { (CGFloat(18) / CGFloat(max(1, boardSize - 1))) * 1.0773 }

    // MARK: - Light Masks
    private let MaskBoard = 2
    private let MaskStones = 4
    
    // MARK: - Physics Integration
    private let PhysicsCategoryStone = 1 << 0
    private let PhysicsCategoryBowl  = 1 << 1

    // MARK: - Debug Settings
    // Production Values (Final)
    // White: Roughness 0.57, Coat 0.86, CoatRough 0.31
    // Lighting: Sun 0.76, Board 0.24, Stone 0.45, Env 1.76, Shadow 0.78
    @Published var whiteRoughness: Double = 0.57 { didSet { updateDebugSettings() } }
    @Published var whiteEmission: Double = 0.0 { didSet { updateDebugSettings() } }
    @Published var whiteClearCoat: Double = 0.86 { didSet { updateDebugSettings() } }
    @Published var whiteClearCoatRoughness: Double = 0.31 { didSet { updateDebugSettings() } }
    
    @Published var blackRoughness: Double = 0.41 { didSet { updateDebugSettings() } }
    
    @Published var lightIntensity: Double = 0.76 { didSet { updateDebugSettings() } }
    @Published var boardAmbientIntensity: Double = 0.24 { didSet { updateDebugSettings() } }
    @Published var stoneAmbientIntensity: Double = 0.45 { didSet { updateDebugSettings() } }
    @Published var envIntensity: Double = 1.76 { didSet { updateDebugSettings() } }
    @Published var shadowIntensity: Double = 0.78 { didSet { updateDebugSettings() } } // Locked Final Value
    
    func updateDebugSettings() {
        // print("DEBUG: updateDebugSettings. WR: \(whiteRoughness) | CC: \(whiteClearCoat)")
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        
        // 1. Board "Ambient" -> Textured Emission
        if let m = boardNode?.geometry?.firstMaterial {
            if m.emission.contents as? NSImage == nil { m.emission.contents = m.diffuse.contents }
            m.emission.intensity = CGFloat(boardAmbientIntensity)
        }
        
        // 2. Stone "Ambient" -> Emission
        let stoneEmit = CGFloat(stoneAmbientIntensity * 0.3)
        
        // Update White Material
        for g in clamGeometries {
            if let m = g.firstMaterial {
                m.roughness.contents = whiteRoughness
                m.emission.contents = NSColor(white: stoneEmit, alpha: 1.0)
                m.clearCoat.contents = whiteClearCoat
                m.clearCoatRoughness.contents = whiteClearCoatRoughness
            }
        }
        
        // Update Black Material
        blackStoneGeometry?.firstMaterial?.roughness.contents = blackRoughness
        blackStoneGeometry?.firstMaterial?.emission.contents = NSColor(white: stoneEmit * 0.5, alpha: 1.0)
        
        // 3. Global Lights
        worldAnchor.childNodes.forEach { n in
            if n.name == "SUN" {
                n.light?.color = NSColor(white: lightIntensity, alpha: 1.0)
                n.light?.categoryBitMask = -1
                // Update Shadow Opacity
                n.light?.shadowColor = NSColor(white: 0.0, alpha: CGFloat(shadowIntensity))
            }
            if n.name == "AMB_BOARD" || n.name == "AMB_STONE" { n.removeFromParentNode() }
        }
        
        // Ensure Global Ambient exists
        if worldAnchor.childNode(withName: "AMB_GLOBAL", recursively: false) == nil {
            let amb = SCNNode(); amb.name = "AMB_GLOBAL"
            amb.light = SCNLight(); amb.light?.type = .ambient
            amb.light?.color = NSColor(white: 0.05, alpha: 1.0)
            worldAnchor.addChildNode(amb)
        }
        
        // Environment
        scene.lightingEnvironment.intensity = CGFloat(envIntensity)
        SCNTransaction.commit()
        scene.lightingEnvironment.intensity = CGFloat(envIntensity)
        SCNTransaction.commit()
    }
    
    // MARK: - Dynamic Sizing
    func updateBoardSize(_ size: Int) {
        if self.boardSize != size {
            SCNTransaction.begin(); SCNTransaction.disableActions = true
            defer { SCNTransaction.commit() }
            print("🎨 [3D] Resizing Board to \(size)x\(size). CellWidth: \(String(format: "%.3f", effectiveCellWidth))")
            self.boardSize = size
            
            // 1. Recreate Board (Wood & Grid)
            createBoard()
            
            // 2. Recreate Stones (New Radius)
            setupMaterials()
            
            // 3. Clear Entity Cache
            stonesContainer.childNodes.forEach { $0.removeFromParentNode() }
            stoneNodeMap.removeAll()
            aiHintNodes.forEach { $0.removeFromParentNode() }
            aiHintNodes.removeAll()
            previousLastMove = nil
            
            // 4. Update Lids Position (Optional, but good for 9x9 centering)
            createLids()
        }
    }
    
    override init() {
        super.init()
        
        scene.rootNode.addChildNode(worldAnchor)
        scene.rootNode.addChildNode(pivotNode)
        pivotNode.addChildNode(cameraNode)
        worldAnchor.addChildNode(stonesContainer)
        setupMaterials()
        setupCamera()
        setupLighting()
        setupBackground()
        setupEnvironment()
        createBoard()
        createLids()
        setupGhostNode()
        
        // Stable physics timing for capture piles.
        scene.physicsWorld.speed = 1.0
        scene.physicsWorld.timeStep = 1.0 / 120.0
    }
    
    // ... (Insert setupMaterials, createBoard, etc from v4.401 here) ...
    
    // PASTE THESE HELPERS from v4.401: setupMaterials, generateRedGlowTexture, updateStones, applyMarkers, updateCameraPosition, updateCapturedStones, updateLidDiff, setupCamera, setupLighting, setupBackground, createBoard, createGridLines, createLids, createLidNode, setupGhostNode, updateGhostStone, clearGhostStone
    // (I am omitting them to save space, assuming you have v4.401 clipboard history. If not, I can reprint.)
    
    // UPDATED HIT TEST
    func hitTest(point: CGPoint, in view: SCNView) -> (x: Int, y: Int)? {
        // v4.500: Debug Hit Test
        // Convert point for Retina displays if needed
        // SCNView hitTest expects point in view's coordinate system (points), not pixels.
        // However, we verify if the boardNode is even found.
        
        let options: [SCNHitTestOption: Any] = [.searchMode: SCNHitTestSearchMode.all.rawValue, .rootNode: worldAnchor]
        let results = view.hitTest(point, options: options)
        
        guard let res = results.first(where: { $0.node == self.boardNode }) else {
            // print("HitTest Missed Board. Hits: \(results.count)")
            return nil
        }
        
        let w = CGFloat(boardSize - 1) * effectiveCellWidth
        let h = CGFloat(boardSize - 1) * effectiveCellHeight
        
        // Use local coordinates on the board node
        let local = res.localCoordinates
        let c = Int(round((CGFloat(local.x) + w/2.0) / effectiveCellWidth))
        let r = Int(round((CGFloat(local.z) + h/2.0) / effectiveCellHeight))
        
        if c >= 0 && c < boardSize && r >= 0 && r < boardSize {
            return (c, r)
        }
        return nil
    }
    
    // --- REST OF FILE IS IDENTICAL TO v4.401 ---
    // (Please ensure you include the full file content from v4.401 or ask me to reprint the whole block if unsure)
    
    private func setupMaterials() {
        // Clear old
        clamGeometries.removeAll()
        
        // BLACK STONE: slightly larger (Standard Go Physics: Black absorbs light, looks smaller, so is made physically larger)
        // We use base stoneRadius for Black.
        blackStoneGeometry = SCNSphere(radius: stoneRadius)
        let bM = SCNMaterial()
        bM.lightingModel = .physicallyBased
        bM.diffuse.contents = NSColor(white: 0.02, alpha: 1.0) // Deep Black
        bM.metalness.contents = 0.0
        bM.roughness.contents = 0.41 
        blackStoneGeometry?.materials = [bM]
        self.blackMaterial = bM
        
        let wM = SCNMaterial()
        wM.lightingModel = .physicallyBased
        wM.diffuse.contents = NSColor(white: 1.0, alpha: 1.0) // Natural White
        wM.metalness.contents = 0.0
        wM.roughness.contents = 0.97
        wM.emission.contents = NSColor(white: 0.0, alpha: 1.0)
        wM.clearCoat.contents = 1.0
        wM.clearCoatRoughness.contents = 0.31
        self.whiteMaterial = wM
        
        // WHITE STONE: slightly smaller (approx 98% of Black) to compensate for irradiation illusion
        let whiteRadius = stoneRadius * 0.98
        
        for _ in 0..<5 {
            let g = SCNSphere(radius: whiteRadius)
            g.materials = [wM]
            clamGeometries.append(g)
        }
        
        markerMaterial = SCNMaterial(); markerMaterial?.diffuse.contents = NSColor.red; markerMaterial?.emission.contents = NSColor.red
        glowMaterial = SCNMaterial(); glowMaterial?.lightingModel = .constant; glowMaterial?.blendMode = .alpha; glowMaterial?.diffuse.contents = generateRedGlowTexture(); glowMaterial?.writesToDepthBuffer = false
    }
    
    private func setupEnvironment() {
        let env = generateEnvironmentTexture()
        scene.lightingEnvironment.contents = env
        scene.lightingEnvironment.intensity = 1.0
        // scene.background.contents = env // Optional: Visible background or just reflections
    }
    

    private func generateRedGlowTexture() -> NSImage {
        let size = 128
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            let c = CGPoint(x: size/2, y: size/2)
            // Gradient: Slightly softened (0.7 max alpha vs 0.9)
            // "Less intense" as requested
            let cols = [
                NSColor.red.withAlphaComponent(0.7).cgColor,
                NSColor.red.withAlphaComponent(0.25).cgColor,
                NSColor.red.withAlphaComponent(0.0).cgColor
            ] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols, locations: [0.0, 0.6, 1.0])!
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size/2), options: .drawsBeforeStartLocation)
            return true
        }
    }
    func updateStones(from cache: [RenderStone], lastMove: BoardPosition?, moveIndex: Int, settings: AppSettings, animate: Bool = true) {
        let w = CGFloat(boardSize - 1) * effectiveCellWidth; let h = CGFloat(boardSize - 1) * effectiveCellHeight; let offX = -w / 2.0; let offZ = -h / 2.0; let surfaceY = boardThickness / 2.0
        let currentPos = Set(cache.map { $0.id })
        
        // Remove old stones
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animate ? 0.2 : 0
        for (pos, node) in stoneNodeMap { if !currentPos.contains(pos) { node.removeFromParentNode(); stoneNodeMap.removeValue(forKey: pos) } }
        SCNTransaction.commit()
        
        for rs in cache {
            let x = CGFloat(rs.id.col) * effectiveCellWidth + offX + (rs.offset.x * effectiveCellWidth)
            let z = CGFloat(rs.id.row) * effectiveCellHeight + offZ + (rs.offset.y * effectiveCellHeight)
            let targetOpacity: CGFloat = rs.isDead ? 0.5 : 1.0
            let geom = rs.color == .black ? blackStoneGeometry : clamGeometries[(rs.id.row * 19 + rs.id.col) % 5]
            
            if let n = stoneNodeMap[rs.id] {
                if !animate { n.removeAllActions() }
                // A game switch or history jump can replace the color at an occupied point.
                // Swap the whole mesh to preserve color-specific size without mutating shared materials.
                if let visual = n.childNode(withName: "board-stone", recursively: false), visual.geometry !== geom {
                    visual.geometry = geom
                }
                if n.hasActions {
                    n.opacity = targetOpacity
                } else {
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = animate ? 0.2 : 0
                    n.position = SCNVector3(x, surfaceY, z)
                    n.opacity = targetOpacity
                    SCNTransaction.commit()
                }
            } else {
                let anchor = SCNNode()
                let s = SCNNode(geometry: geom); s.scale = SCNVector3(1, stoneScaleY, 1); s.eulerAngles.y = CGFloat(rs.id.col * rs.id.row); s.position = SCNVector3(0, stoneRadius * stoneScaleY, 0)
                s.name = "board-stone"
                
                s.categoryBitMask = MaskStones
                anchor.addChildNode(s); stonesContainer.addChildNode(anchor); stoneNodeMap[rs.id] = anchor
                
                if settings.showDropInAnimation && animate {
                    // Set initial state outside of any SCNTransaction so it applies instantly before animation
                    anchor.position = SCNVector3(x, surfaceY + 1.0, z)
                    anchor.opacity = 0
                    
                    // Use SCNAction for the drop
                    anchor.runAction(.group([
                        .fadeOpacity(to: targetOpacity, duration: 0.15),
                        .move(to: SCNVector3(x, surfaceY, z), duration: 0.15)
                    ]))
                } else {
                    anchor.position = SCNVector3(x, surfaceY, z)
                    anchor.opacity = targetOpacity
                }
            }
        }
        
        // Always rebuild markers to respond to settings changes immediately
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animate ? 0.2 : 0
        if let p = previousLastMove, let n = stoneNodeMap[p] { n.childNodes.filter({ $0.name?.contains("MARKER") ?? false }).forEach { $0.removeFromParentNode() } }
        if let c = lastMove, let n = stoneNodeMap[c] { let col = cache.first(where: { $0.id == c })?.color ?? .black; applyMarkers(to: n, color: col, index: moveIndex, settings: settings) }
        previousLastMove = lastMove
        SCNTransaction.commit()
    }
    
    /// Number the hypothetical continuation on the stone anchors, so labels track
    /// board rotation and scale without changing the real game's move markers.
    func updateVariationNumbers(frame: AIVariationFrame?) {
        for node in stoneNodeMap.values {
            node.childNode(withName: "ai-variation-number", recursively: false)?.removeFromParentNode()
        }
        guard let frame else { return }
        for (point, number) in frame.numbers {
            guard let anchor = stoneNodeMap[point], let color = frame.stones[point] else { continue }
            let text = SCNText(string: String(number), extrusionDepth: 0)
            text.font = NSFont.boldSystemFont(ofSize: effectiveCellWidth * 0.48)
            text.flatness = 0.01
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color == .black ? NSColor.white : NSColor.black
            text.materials = [material]
            let label = SCNNode(geometry: text)
            label.name = "ai-variation-number"
            label.eulerAngles.x = -.pi / 2
            let (low, high) = text.boundingBox
            label.pivot = SCNMatrix4MakeTranslation(CGFloat((low.x + high.x) / 2), CGFloat((low.y + high.y) / 2), 0)
            label.position = SCNVector3(0, stoneRadius * stoneScaleY * 2 + 0.02, 0)
            anchor.addChildNode(label)
        }
    }

    private var recentQualityMarkers: [RecentMoveQualityMarker] = []
    func updateRecentMoveQuality(_ markers: [RecentMoveQualityMarker]) {
        guard markers != recentQualityMarkers || markers.contains(where: {
            stoneNodeMap[$0.position]?.childNode(withName: "ai-recent-quality", recursively: false) == nil
        }) else { return }
        recentQualityMarkers = markers
        for anchor in stoneNodeMap.values {
            anchor.childNode(withName: "ai-recent-quality", recursively: false)?.removeFromParentNode()
        }
        for marker in markers {
            guard let anchor = stoneNodeMap[marker.position] else { continue }
            let image = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { _ in
                let ring = NSBezierPath()
                ring.appendArc(withCenter: NSPoint(x: 128, y: 128), radius: 88,
                               startAngle: -45, endAngle: 225, clockwise: false)
                ring.lineCapStyle = .round
                (marker.stone == .black ? NSColor.white.withAlphaComponent(0.6) : NSColor.black.withAlphaComponent(0.65)).setStroke()
                ring.lineWidth = 19; ring.stroke()
                NSColor(marker.quality.color).setStroke()
                ring.lineWidth = 11; ring.stroke()
                var font = NSFont.boldSystemFont(ofSize: 58)
                while (marker.label as NSString).size(withAttributes: [.font: font]).width > 180 && font.pointSize > 24 {
                    font = NSFont.boldSystemFont(ofSize: font.pointSize - 2)
                }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: marker.stone == .black ? NSColor.white : NSColor.black]
                let size = (marker.label as NSString).size(withAttributes: attributes)
                (marker.label as NSString).draw(at: CGPoint(x: (256 - size.width) / 2, y: 40 - size.height / 2), withAttributes: attributes)
                return true
            }
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.writesToDepthBuffer = false
            let plane = SCNPlane(width: effectiveCellWidth * 0.85, height: effectiveCellWidth * 0.85)
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.name = "ai-recent-quality"
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(0, stoneRadius * stoneScaleY * 2 + 0.035, 0)
            node.castsShadow = false
            node.renderingOrder = 100
            anchor.addChildNode(node)
        }
    }

    // NEW: Territory Rendering
    private var territoryNodes: [SCNNode] = []
    private lazy var territoryMaterials: [Stone: SCNMaterial] = {
        Dictionary(uniqueKeysWithValues: Stone.allCases.map { owner in
            let color: NSColor = owner == .black ? .black : .white
            let texture = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { _ in
                guard let context = NSGraphicsContext.current?.cgContext,
                      let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [0.96, 0.9, 0.38, 0].map { color.withAlphaComponent($0).cgColor } as CFArray,
                        locations: [0, 0.22, 0.58, 1]) else { return false }
                context.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                           endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
                return true
            }
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = texture
            material.blendMode = .alpha
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            return (owner, material)
        })
    }()
    
    func updateAIHints(moves: [AIMoveInfo], isAvailable: Bool, root: AIRootInfo?, nextMove: BoardPosition?) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        
        aiHintNodes.forEach { $0.removeFromParentNode() }
        aiHintNodes.removeAll()
        
        guard isAvailable else {
            SCNTransaction.commit()
            return
        }
        
        let w = CGFloat(boardSize - 1) * effectiveCellWidth
        let h = CGFloat(boardSize - 1) * effectiveCellHeight
        let offX = -w / 2.0; let offZ = -h / 2.0
        
        // Slightly above the board surface, not floating way up over stones
        let tY = boardThickness / 2.0 + 0.01
        
        // Take top 10 moves
        var sorted = Array(moves.sorted { $0.winrate > $1.winrate }.prefix(10))
        
        // Force include historical nextMove if not in top 10 but evaluated by KataGo
        if let next = nextMove, !sorted.contains(where: { parseGTPCoord($0.move, size: boardSize) == next }) {
            if let missingMove = moves.first(where: { parseGTPCoord($0.move, size: boardSize) == next }) {
                sorted.append(missingMove)
            } else {
                let fallback = AIMoveInfo(move: toGTPCoord(next, size: boardSize), visits: 0, winrate: root?.winrate ?? 0, scoreLead: root?.scoreLead ?? 0, pv: nil)
                sorted.append(fallback)
            }
        }
        
        guard let best = sorted.first else { SCNTransaction.commit(); return }
        
        let rootWinrate = root?.winrate ?? best.winrate
        let rootScore = root?.scoreLead ?? best.scoreLead
        
        for move in sorted {
            if let pos = parseGTPCoord(move.move, size: boardSize) {
                let x = CGFloat(pos.col) * effectiveCellWidth + offX
                let z = CGFloat(pos.row) * effectiveCellHeight + offZ
                
                // Cylinder for AI Hint
                let hintRad = stoneRadius * 0.8
                let cyl = SCNCylinder(radius: hintRad, height: 0.005)
                
                // Diff calculating relative to ROOT evaluation, not absolute best
                let diff = rootWinrate - move.winrate
                let color: NSColor
                if diff < 0.05 { color = .systemGreen }
                else if diff < 0.15 { color = .systemYellow }
                else { color = .systemRed }
                
                let mat = SCNMaterial()
                mat.diffuse.contents = color.withAlphaComponent(0.50) // Less transparent than before
                mat.emission.contents = color.withAlphaComponent(0.20) // Slightly more vibrant
                cyl.materials = [mat]
                
                let n = SCNNode(geometry: cyl)
                n.position = SCNVector3(x, tY, z)
                n.name = "AI_HINT"
                n.categoryBitMask = MaskBoard // Expose this Node to the Ambient+Sun lighting arrays
                
                // Highlighting Rings
                let isBestMove = move.move == best.move
                let isNextPlayed = (pos == nextMove)
                
                if isBestMove && isNextPlayed {
                    // Double Ring (Blue and Black)
                    let ring1 = SCNTorus(ringRadius: hintRad * 0.95, pipeRadius: 0.01)
                    let r1Mat = SCNMaterial(); r1Mat.diffuse.contents = NSColor.blue
                    ring1.materials = [r1Mat]
                    let n1 = SCNNode(geometry: ring1); n1.position = SCNVector3(0, 0.005, 0)
                    n.addChildNode(n1)
                    
                    let ring2 = SCNTorus(ringRadius: hintRad * 0.85, pipeRadius: 0.01)
                    let r2Mat = SCNMaterial(); r2Mat.diffuse.contents = NSColor.black
                    ring2.materials = [r2Mat]
                    let n2 = SCNNode(geometry: ring2); n2.position = SCNVector3(0, 0.005, 0)
                    n.addChildNode(n2)
                } else if isBestMove {
                    let ring1 = SCNTorus(ringRadius: hintRad * 0.9, pipeRadius: 0.015)
                    let r1Mat = SCNMaterial(); r1Mat.diffuse.contents = NSColor.blue
                    ring1.materials = [r1Mat]
                    let n1 = SCNNode(geometry: ring1); n1.position = SCNVector3(0, 0.005, 0)
                    n.addChildNode(n1)
                } else if isNextPlayed {
                    let ring = SCNTorus(ringRadius: hintRad * 0.9, pipeRadius: 0.015)
                    let ringMat = SCNMaterial()
                    ringMat.diffuse.contents = NSColor.black
                    ringMat.emission.contents = NSColor.black.withAlphaComponent(0.5)
                    ring.materials = [ringMat]
                    let ringNode = SCNNode(geometry: ring)
                    ringNode.position = SCNVector3(0, 0.005, 0)
                    n.addChildNode(ringNode)
                }
                
                // Add Text (Delta % and Points)
                let deltaWin = (move.winrate - rootWinrate) * 100
                let deltaPt = move.scoreLead - rootScore
                
                let winStr = deltaWin > 0 ? String(format: "+%.1f%%", deltaWin) : String(format: "%.1f%%", deltaWin)
                let ptStr = deltaPt > 0 ? String(format: "+%.1f", deltaPt) : String(format: "%.1f", deltaPt)
                
                let tMat = SCNMaterial()
                tMat.diffuse.contents = NSColor.black // Black text for contrast
                
                // Winrate String Node
                let tWin = SCNText(string: winStr, extrusionDepth: 0.01)
                tWin.font = NSFont.boldSystemFont(ofSize: 0.5)
                tWin.alignmentMode = CATextLayerAlignmentMode.center.rawValue
                tWin.flatness = 0.01 // Smooth curves
                tWin.materials = [tMat]
                
                let tnWin = SCNNode(geometry: tWin)
                let (minW, maxW) = tWin.boundingBox
                tnWin.pivot = SCNMatrix4MakeTranslation(CGFloat((maxW.x - minW.x)/2.0 + minW.x), CGFloat((maxW.y - minW.y)/2.0 + minW.y), 0)
                tnWin.eulerAngles.x = -.pi / 2
                tnWin.position = SCNVector3(0, 0.02, -hintRad * 0.4) // Offset z backwards explicitly
                tnWin.scale = SCNVector3(hintRad * 1.5, hintRad * 1.5, hintRad * 1.5)
                n.addChildNode(tnWin)
                
                // Point String Node
                let tPt = SCNText(string: ptStr, extrusionDepth: 0.01)
                tPt.font = NSFont.boldSystemFont(ofSize: 0.5)
                tPt.alignmentMode = CATextLayerAlignmentMode.center.rawValue
                tPt.flatness = 0.01 // Smooth curves
                tPt.materials = [tMat]
                
                let tnPt = SCNNode(geometry: tPt)
                let (minP, maxP) = tPt.boundingBox
                tnPt.pivot = SCNMatrix4MakeTranslation(CGFloat((maxP.x - minP.x)/2.0 + minP.x), CGFloat((maxP.y - minP.y)/2.0 + minP.y), 0)
                tnPt.eulerAngles.x = -.pi / 2
                tnPt.position = SCNVector3(0, 0.02, hintRad * 0.4) // Offset z forwards explicitly
                tnPt.scale = SCNVector3(hintRad * 1.5, hintRad * 1.5, hintRad * 1.5)
                n.addChildNode(tnPt)
                
                worldAnchor.addChildNode(n)
                aiHintNodes.append(n)
            }
        }
        
        SCNTransaction.commit()
    }
    
    // KataGo coords: A1 to T19
    private func parseGTPCoord(_ s: String, size: Int) -> BoardPosition? {
        if s.lowercased() == "pass" { return nil }
        guard s.count >= 2 else { return nil }
        
        let letters = "ABCDEFGHJKLMNOPQRST" // Standard GTP skip I
        let uppercased = s.uppercased()
        let char = uppercased[uppercased.startIndex]
        
        guard let xIndex = letters.firstIndex(of: char) else { return nil }
        let x = letters.distance(from: letters.startIndex, to: xIndex)
        
        let numRange = uppercased.index(after: uppercased.startIndex)..<uppercased.endIndex
        let numStr = String(uppercased[numRange])
        guard let yMath = Int(numStr) else { return nil }
        
        // GTP Y is 1 at bottom, size at top. UI array has 0 at top.
        let y = size - yMath
        
        if x >= 0, x < size, y >= 0, y < size {
            return BoardPosition(y, x)
        }
        return nil
    }
    
    // Reverse lookup helper
    private func toGTPCoord(_ pos: BoardPosition, size: Int) -> String {
        let letters = "ABCDEFGHJKLMNOPQRST" // Standard GTP skip I
        guard pos.col >= 0, pos.col < letters.count else { return "" }
        let xIndex = letters.index(letters.startIndex, offsetBy: pos.col)
        let xChar = letters[xIndex]
        let yMath = size - pos.row
        return "\(xChar)\(yMath)"
    }
    
    func updateTerritory(points: [BoardPosition: Stone]) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        territoryNodes.forEach { $0.removeFromParentNode() }
        territoryNodes.removeAll()
        
        guard !points.isEmpty else { SCNTransaction.commit(); return }
        
        let w = CGFloat(boardSize - 1) * effectiveCellWidth
        let h = CGFloat(boardSize - 1) * effectiveCellHeight
        let offX = -w / 2.0; let offZ = -h / 2.0
        let tY = boardThickness / 2.0 + 0.01 // Slightly above board
        
        for (pos, owner) in points {
            let x = CGFloat(pos.col) * effectiveCellWidth + offX
            let z = CGFloat(pos.row) * effectiveCellHeight + offZ
            
            let plane = SCNPlane(width: effectiveCellWidth * 0.7, height: effectiveCellWidth * 0.7)
            plane.materials = [territoryMaterials[owner]!]
            let n = SCNNode(geometry: plane)
            n.name = "territory-\(owner.rawValue)"
            n.eulerAngles.x = -.pi / 2
            n.renderingOrder = 10
            n.castsShadow = false
            n.position = SCNVector3(x, tY, z)
            worldAnchor.addChildNode(n)
            territoryNodes.append(n)
            
            // Optional: Add small X if it's a "neutral" or Dame?
            // Usually points map has only B/W. 
        }
        SCNTransaction.commit()
    }

    private func applyMarkers(to group: SCNNode, color: Stone, index: Int, settings: AppSettings) {
        let apex = (stoneRadius * stoneScaleY * 2.0) + 0.01; let tc = color == .black ? NSColor.white : NSColor.black
        if settings.showLastMoveDot { let d = SCNNode(geometry: SCNSphere(radius: stoneRadius * 0.12)); d.geometry?.firstMaterial = markerMaterial; d.name = "MARKER_DOT"; d.position = SCNVector3(0, apex + 0.02, 0); group.addChildNode(d) }
        if settings.showLastMoveCircle { let r = SCNNode(geometry: SCNTorus(ringRadius: stoneRadius * 0.6, pipeRadius: 0.025)); r.geometry?.firstMaterial = markerMaterial; r.name = "MARKER_CIRCLE"; r.position = SCNVector3(0, apex, 0); group.addChildNode(r) }
        if settings.showMoveNumbers {
            let t = SCNText(string: "\(index)", extrusionDepth: 0.1); t.font = NSFont.boldSystemFont(ofSize: 0.45); t.flatness = 0.01; t.materials = [SCNMaterial()]; t.materials[0].diffuse.contents = tc
            let tn = SCNNode(geometry: t); tn.name = "MARKER_NUMBER"; tn.eulerAngles.x = -.pi/2
            let (min, max) = t.boundingBox; tn.pivot = SCNMatrix4MakeTranslation(CGFloat((max.x - min.x)/2.0 + min.x), CGFloat((max.y - min.y)/2.0 + min.y), 0)
            tn.position = SCNVector3(0, apex, 0); group.addChildNode(tn)
        }
        if settings.showBoardGlow || settings.showEnhancedGlow {
            // Enhanced = Old Normal (2.5)
            // Normal = 2.5 * 0.7 = 1.75
            let s = settings.showEnhancedGlow ? 2.5 : 1.75
            // Fix: Use effectiveCellWidth (Pitch) not stoneRadius, so it extends BEYOND the stone
            let dim = effectiveCellWidth * s
            let p = SCNNode(geometry: SCNPlane(width: dim, height: dim))
            p.geometry?.firstMaterial = glowMaterial
            p.name = "MARKER_GLOW"
            p.eulerAngles.x = -.pi/2
            // Y: Just above board (0.005) to avoid Z-fighting, but below heavy stone curvature
            p.position = SCNVector3(0, 0.005, 0)
            // Removed renderingOrder=3000 so it draws naturally behind/underopaque stone
            group.addChildNode(p)
        }
    }
    func updateCameraPosition(distance: CGFloat, rotationX: Float, rotationY: Float, panX: CGFloat, panY: CGFloat) {
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        // Previously the board and all physics bodies moved to change the view. A kinematic
        // lid could then strike settled stones at enormous velocity. Apply the inverse of
        // that transform to the camera instead: inverse(C) * W == inverse(inverse(W) * C).
        let viewTransform = SCNNode()
        viewTransform.position = SCNVector3(panX, 0, panY)
        viewTransform.eulerAngles = SCNVector3(CGFloat(rotationX), CGFloat(rotationY), 0)
        let r = distance / 25.0
        let baseCamera = SCNNode()
        baseCamera.position = SCNVector3(0, 15.0 * r, 20.0 * r)
        baseCamera.look(at: SCNVector3Zero)
        cameraNode.simdTransform = simd_inverse(viewTransform.simdTransform) * baseCamera.simdTransform
        scene.physicsWorld.gravity = SCNVector3(0, -19.62, 0)
        SCNTransaction.commit()
    }
    /// Counts are by capturing player. White's upper lid holds black stones, and vice versa.
    func updateCapturedStones(black: Int, white: Int) {
        guard let upper = upperLidNode, let lower = lowerLidNode else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        updateLidWalls(lid: upper)
        updateLidWalls(lid: lower)
        updateLidDiff(lid: upper, current: &upperLidStones, target: max(0, white), isWhite: false)
        updateLidDiff(lid: lower, current: &lowerLidStones, target: max(0, black), isWhite: true)
        updateCaptureLabel(lid: upper, count: max(0, white))
        updateCaptureLabel(lid: lower, count: max(0, black))
        SCNTransaction.commit()
    }

    private func updateCaptureLabel(lid: SCNNode, count: Int) {
        if let label = lid.childNode(withName: "capture-count", recursively: false)?.geometry as? SCNText {
            label.string = String(count)
            return
        }
        let text = SCNText(string: String(count), extrusionDepth: 0)
        text.font = NSFont.monospacedDigitSystemFont(ofSize: 0.6, weight: .bold)
        text.firstMaterial?.diffuse.contents = NSColor.white
        text.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: text)
        node.name = "capture-count"
        node.eulerAngles.x = -.pi / 2
        // Keep the exact count outside the pile, where stones cannot obscure it.
        node.position = SCNVector3(-0.4, 0.2, 4.0)
        lid.addChildNode(node)
    }

    private func updateLidDiff(lid: SCNNode, current: inout [SCNNode], target: Int, isWhite: Bool) { 
        if current.count == target { return }
        
        if current.count > target { 
            while current.count > target { 
                current.last?.removeFromParentNode()
                current.removeLast() 
            } 
        } else {
            let start = current.count
            // Add above the settled pile, which need not retain its original layered layout.
            let dropHeight = max(0.8, (current.map { $0.presentation.position.y }.max() ?? 0) + 0.65)
            for i in start..<target {
                let g = isWhite ? clamGeometries[i % 5] : blackStoneGeometry
                let n = SCNNode()
                let visual = SCNNode(geometry: g)
                visual.name = "capture-visual"
                n.addChildNode(visual)
                n.name = isWhite ? "captured-white" : "captured-black"
                
                // Lids have a fixed size even when the board changes to 9x9 or 13x13.
                // Space simultaneous captures in layers so physics starts without intersections.
                var positions: [(CGFloat, CGFloat)] = []
                for row in -2...2 {
                    for col in -2...2 where row * row + col * col <= 5 {
                        positions.append((CGFloat(col) * 1.05, CGFloat(row) * 1.05))
                    }
                }
                // Start small captures in the middle, rather than filling the outer row first.
                positions.sort {
                    let a = $0.0 * $0.0 + $0.1 * $0.1, b = $1.0 * $1.0 + $1.1 * $1.1
                    if a != b { return a < b }
                    return $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1
                }
                let position = positions[i % positions.count]
                let layer = (i - start) / positions.count
                n.position = SCNVector3(position.0, dropHeight + CGFloat(layer) * 0.52, position.1)
                n.eulerAngles = SCNVector3(0, CGFloat(i) * 2.39996, 0)
                let scale = capturedStoneRadius / stoneRadius
                visual.scale = SCNVector3(scale, scale * stoneScaleY, scale)

                // The physics parent stays at unit scale; only its visual child is flattened.
                // This prevents board-size-dependent scaling of the collision shape.
                let physGeom = SCNCylinder(radius: capturedStoneRadius, height: capturedStoneRadius * stoneScaleY * 2.0)
                let shape = SCNPhysicsShape(geometry: physGeom, options: nil)
                let body = SCNPhysicsBody(type: .dynamic, shape: shape)
                body.mass = 0.5 // Higher mass so they slam down
                body.restitution = 0.0 // Zero bounce
                body.friction = 2.0     // Extreme grip
                body.rollingFriction = 2.0 // Extreme spin lock
                body.damping = 0.35
                body.angularDamping = 0.9 // Extreme spin drag to force them flat
                
                body.categoryBitMask = PhysicsCategoryStone
                body.collisionBitMask = PhysicsCategoryStone | PhysicsCategoryBowl
                body.contactTestBitMask = PhysicsCategoryBowl
                n.physicsBody = body
                
                lid.addChildNode(n)
                current.append(n)
                
                // Optional: apply a tiny initial impulse to make the drop feel dynamic
                let impulse = SCNVector3(CGFloat.random(in: -0.01...0.01), 0, CGFloat.random(in: -0.01...0.01))
                body.applyForce(impulse, asImpulse: true)
            } 
        }
    }
    private func setupCamera() { let c = SCNCamera(); c.zNear = 0.1; c.zFar = 1000.0; cameraNode.camera = c; pivotNode.addChildNode(cameraNode); updateCameraPosition(distance: 25.0, rotationX: 0.75, rotationY: 0.0, panX: 0, panY: 0) }
    
    // UPDATED LIGHTING: Dual Ambient with Masks
    private func setupLighting() {
        // 1. Board Ambient (Mask 2)
        let ambBoard = SCNNode()
        ambBoard.name = "AMB_BOARD"
        ambBoard.light = SCNLight()
        ambBoard.light?.type = .ambient
        ambBoard.light?.color = NSColor(white: boardAmbientIntensity, alpha: 1.0)
        ambBoard.light?.categoryBitMask = MaskBoard // Only hits board
        worldAnchor.addChildNode(ambBoard)
        
        // 2. Stone Ambient (Mask 4)
        let ambStone = SCNNode()
        ambStone.name = "AMB_STONE"
        ambStone.light = SCNLight()
        ambStone.light?.type = .ambient
        ambStone.light?.color = NSColor(white: stoneAmbientIntensity, alpha: 1.0)
        ambStone.light?.categoryBitMask = MaskStones // Only hits stones
        worldAnchor.addChildNode(ambStone)
        
        // 3. Sun - Directional (Hits Everything - Default Mask -1)
        let dir = SCNNode()
        dir.name = "SUN"
        dir.light = SCNLight()
        dir.light?.type = .directional
        dir.light?.color = NSColor(white: lightIntensity, alpha: 1.0)
        dir.light?.castsShadow = true
        dir.light?.shadowColor = NSColor(white: 0.0, alpha: 0.75)
        dir.light?.shadowRadius = 2.0
        dir.light?.shadowSampleCount = 16
        dir.position = SCNVector3(-15, 25, -15)
        dir.look(at: SCNVector3(x: 0, y: 0, z: 0))
        worldAnchor.addChildNode(dir)
    }
    
    private func setupBackground() { scene.background.contents = Self.backgroundColor }
    // ... createBoard ...
    
    // ... generatedEnvironmentTexture ...
    private func generateEnvironmentTexture() -> NSImage {
        let size = 512
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            // Gradient Setup:
            // Top (1.0): Bright White (Sun/Sky)
            // Middle: Neutral Gray (Horizon)
            // Bottom (0.0): Warm White (Table Bounce) -> Fixes dark bottoms of stones
            let colors = [
                NSColor(white: 0.9, alpha: 1.0).cgColor, // Bottom (Bounce)
                NSColor(white: 0.5, alpha: 1.0).cgColor, // Horizon
                NSColor(white: 1.2, alpha: 1.0).cgColor  // Top (Sky)
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.45, 1.0])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
            return true
        }
    }
 
    private func createBoard() { boardNode?.removeFromParentNode(); let bW = CGFloat(boardSize + 1) * effectiveCellWidth; let bL = CGFloat(boardSize + 1) * effectiveCellHeight; let bG = SCNBox(width: bW, height: boardThickness, length: bL, chamferRadius: 0.0); let m = SCNMaterial(); m.diffuse.contents = NSImage(named: "board_kaya") ?? NSColor.brown; bG.materials = [m]; let n = SCNNode(geometry: bG); worldAnchor.addChildNode(n); self.boardNode = n;
        // MASK: Board sees BoardAmbient + Sun
        n.categoryBitMask = MaskBoard
        createGridLines()
    }
    private func createGridLines() { 
        guard let board = boardNode else { return }
        
        let tY = boardThickness / 2.0 + 0.002 // Slightly above board
        let w = CGFloat(boardSize - 1) * effectiveCellWidth
        let h = CGFloat(boardSize - 1) * effectiveCellHeight
        let lw = effectiveCellWidth * 0.02 // 2% thickness (Matches original 19x19 look of 0.02)
        
        for i in 0..<boardSize { 
            // Vertical Lines (Z-axis length)
            let lZ = SCNBox(width: lw, height: 0.001, length: h, chamferRadius: 0)
            lZ.firstMaterial?.diffuse.contents = NSColor.black
            let nZ = SCNNode(geometry: lZ)
            nZ.categoryBitMask = MaskBoard
            // X position varies, Z centered
            nZ.position = SCNVector3(x: CGFloat(i) * effectiveCellWidth - (w/2.0), y: tY, z: 0)
            board.addChildNode(nZ)
            
            // Horizontal Lines (X-axis length)
            let lX = SCNBox(width: w, height: 0.001, length: lw, chamferRadius: 0)
            lX.firstMaterial?.diffuse.contents = NSColor.black
            let nX = SCNNode(geometry: lX)
            nX.categoryBitMask = MaskBoard
            // Z position varies, X centered
            nX.position = SCNVector3(x: 0, y: tY, z: CGFloat(i) * effectiveCellHeight - (h/2.0))
            board.addChildNode(nX) 
        } 
    }
    func createLids() {
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        let black = lowerLidStones.count, white = upperLidStones.count
        upperLidStones.removeAll()
        lowerLidStones.removeAll()
        upperLidNode?.removeFromParentNode()
        lowerLidNode?.removeFromParentNode()
        
        upperLidNode = createLidNode(textureName: "go_lid_1", pos: SCNVector3(x: 14.0, y: -0.2, z: -5.0))
        lowerLidNode = createLidNode(textureName: "go_lid_2", pos: SCNVector3(x: 14.0, y: -0.2, z: 5.0))
        
        if let u = upperLidNode { worldAnchor.addChildNode(u) }
        if let l = lowerLidNode { worldAnchor.addChildNode(l) }
        upperLidNode?.name = "white-player-lid"
        lowerLidNode?.name = "black-player-lid"
        updateCapturedStones(black: black, white: white)
    }
    
    private func createLidNode(textureName: String, pos: SCNVector3) -> SCNNode {
        // 1. Visual Base (Solid Cylinder)
        let cyl = SCNCylinder(radius: 3.5, height: 0.3)
        let m = SCNMaterial()
        m.diffuse.contents = NSImage(named: textureName) ?? NSColor.brown
        cyl.materials = [m]
        let n = SCNNode(geometry: cyl)
        n.position = pos
        
        // One flat floor, rather than intersecting sloped boxes that can launch stones.
        // Cap the cylinder bottom as well
        let capBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: cyl, options: nil))
        capBody.categoryBitMask = PhysicsCategoryBowl
        capBody.collisionBitMask = PhysicsCategoryStone | PhysicsCategoryBowl
        capBody.contactTestBitMask = PhysicsCategoryStone
        n.physicsBody = capBody
        
        return n
    }
    func updateKoMarker(at point: BoardPosition?) {
        worldAnchor.childNode(withName: "ko-marker", recursively: false)?.removeFromParentNode()
        guard let point else { return }
        let plane = SCNPlane(width: effectiveCellWidth * 0.7, height: effectiveCellWidth * 0.7)
        let material = SCNMaterial()
        material.diffuse.contents = koMarkerTexture
        material.lightingModel = .constant
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.name = "ko-marker"
        node.eulerAngles.x = -.pi / 2
        node.castsShadow = false
        node.position = SCNVector3((CGFloat(point.col) - CGFloat(boardSize - 1) / 2) * effectiveCellWidth,
            boardThickness / 2 + 0.02, (CGFloat(point.row) - CGFloat(boardSize - 1) / 2) * effectiveCellHeight)
        worldAnchor.addChildNode(node)
    }

    private func updateLidWalls(lid: SCNNode) {
        guard lid.childNode(withName: "capture-walls", recursively: false) == nil else { return }
        // Fixed walls never change shape or position underneath a live pile. Invisible height
        // leaves ample headroom for captures; changing kinematic walls can impart large impulses.
        let height: CGFloat = 64
        let walls = SCNNode()
        walls.name = "capture-walls"
        // Overlapping boxes form a reliable convex collision ring, taller than the pile.
        for i in 0..<24 {
            let angle = CGFloat(i) * .pi / 12
            let geometry = SCNBox(width: 0.9, height: height, length: 0.35, chamferRadius: 0)
            let node = SCNNode()
            node.position = SCNVector3(sin(angle) * 3.15, height / 2, cos(angle) * 3.15)
            node.eulerAngles.y = angle
            node.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: geometry, options: nil))
            node.physicsBody?.categoryBitMask = PhysicsCategoryBowl
            node.physicsBody?.collisionBitMask = PhysicsCategoryStone
            walls.addChildNode(node)
        }
        lid.addChildNode(walls)
    }

    private func setupGhostNode() { let s = SCNSphere(radius: stoneRadius); let m = SCNMaterial(); m.diffuse.contents = NSColor(white: 1.0, alpha: 0.5); s.materials = [m]; ghostNode = SCNNode(geometry: s); ghostNode?.opacity = 0.0; stonesContainer.addChildNode(ghostNode!) }
    func updateGhostStone(at pos: BoardPosition?, color: Stone?) { guard let p = pos, let c = color else { ghostNode?.opacity = 0.0; return }; let w = CGFloat(boardSize - 1) * effectiveCellWidth; let h = CGFloat(boardSize - 1) * effectiveCellHeight; let offX = -w / 2.0; let offZ = -h / 2.0; let surfaceY = boardThickness / 2.0; let x = CGFloat(p.col) * effectiveCellWidth + offX; let z = CGFloat(p.row) * effectiveCellHeight + offZ; ghostNode?.position = SCNVector3(x, surfaceY, z); if let mat = ghostNode?.geometry?.firstMaterial { mat.diffuse.contents = (c == .black) ? NSColor(white: 0.1, alpha: 0.6) : NSColor(white: 0.9, alpha: 0.6) }; ghostNode?.opacity = 1.0 }
    func clearGhostStone() { ghostNode?.opacity = 0.0 }
}
