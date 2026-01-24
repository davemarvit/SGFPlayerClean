// ========================================================
// FILE: ./Models/SceneManager3D.swift
// VERSION: v4.500 (HitTest Debug & Retina Fix)
// ========================================================
import Foundation
import SceneKit
import AppKit
import QuartzCore

class SceneManager3D: ObservableObject {
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
    private var boardSize: Int = 19
    private let boardThickness: CGFloat = 2.0
    // Dynamic Radius: 48% of cell width (leaves 4% gap)
    private var stoneRadius: CGFloat { effectiveCellWidth * 0.48 }
    private let stoneScaleY: CGFloat = 0.486
    private var previousLastMove: BoardPosition?
    private var effectiveCellWidth: CGFloat { CGFloat(18) / CGFloat(max(1, boardSize - 1)) }
    private var effectiveCellHeight: CGFloat { (CGFloat(18) / CGFloat(max(1, boardSize - 1))) * 1.0773 }

    // MARK: - Light Masks
    private let MaskBoard = 2
    private let MaskStones = 4

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
            print("🎨 [3D] Resizing Board to \(size)x\(size). CellWidth: \(String(format: "%.3f", effectiveCellWidth))")
            self.boardSize = size
            
            // 1. Recreate Board (Wood & Grid)
            createBoard()
            
            // 2. Recreate Stones (New Radius)
            setupMaterials()
            
            // 3. Clear Entity Cache
            stonesContainer.childNodes.forEach { $0.removeFromParentNode() }
            stoneNodeMap.removeAll()
            previousLastMove = nil
            
            // 4. Update Lids Position (Optional, but good for 9x9 centering)
            createLids()
        }
    }
    
    init() {
        scene.rootNode.addChildNode(worldAnchor); scene.rootNode.addChildNode(pivotNode); pivotNode.addChildNode(cameraNode); worldAnchor.addChildNode(stonesContainer)
        setupMaterials(); setupCamera(); setupLighting(); setupBackground(); setupEnvironment(); createBoard(); createLids(); setupGhostNode()
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
    func updateStones(from cache: [RenderStone], lastMove: BoardPosition?, moveIndex: Int, settings: AppSettings) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.2 // Soften transitions
        let w = CGFloat(boardSize - 1) * effectiveCellWidth; let h = CGFloat(boardSize - 1) * effectiveCellHeight; let offX = -w / 2.0; let offZ = -h / 2.0; let surfaceY = boardThickness / 2.0
        let currentPos = Set(cache.map { $0.id })
        for (pos, node) in stoneNodeMap { if !currentPos.contains(pos) { node.removeFromParentNode(); stoneNodeMap.removeValue(forKey: pos) } }
        
        for rs in cache {
            let x = CGFloat(rs.id.col) * effectiveCellWidth + offX + (rs.offset.x * effectiveCellWidth)
            let z = CGFloat(rs.id.row) * effectiveCellHeight + offZ + (rs.offset.y * effectiveCellHeight)
            
            // User Feedback: "Less transparent" (0.3 was too faint). Try 0.5.
            let targetOpacity: CGFloat = rs.isDead ? 0.5 : 1.0
            
            if let n = stoneNodeMap[rs.id] { 
                n.position = SCNVector3(x, surfaceY, z)
                n.opacity = targetOpacity
            } else {
                let anchor = SCNNode(); anchor.position = SCNVector3(x, surfaceY, z)
                let geom = rs.color == .black ? blackStoneGeometry : clamGeometries[(rs.id.row * 19 + rs.id.col) % 5]
                let s = SCNNode(geometry: geom); s.scale = SCNVector3(1, stoneScaleY, 1); s.eulerAngles.y = CGFloat(rs.id.col * rs.id.row); s.position = SCNVector3(0, stoneRadius * stoneScaleY, 0)
                
                // MASK: Stones see StoneAmbient + Sun
                s.categoryBitMask = MaskStones
                
                anchor.addChildNode(s); stonesContainer.addChildNode(anchor); stoneNodeMap[rs.id] = anchor
                anchor.opacity = targetOpacity
                
                if settings.showDropInAnimation { 
                    anchor.opacity = 0; anchor.position.y += 1.0; 
                    anchor.runAction(.group([.fadeOpacity(to: targetOpacity, duration: 0.15), .move(to: SCNVector3(x, surfaceY, z), duration: 0.15)])) 
                }
            }
        }
        // Always rebuild markers to respond to settings changes immediately
        if true {
            if let p = previousLastMove, let n = stoneNodeMap[p] { n.childNodes.filter({ $0.name?.contains("MARKER") ?? false }).forEach { $0.removeFromParentNode() } }
            if let c = lastMove, let n = stoneNodeMap[c] { let col = cache.first(where: { $0.id == c })?.color ?? .black; applyMarkers(to: n, color: col, index: moveIndex, settings: settings) }
            previousLastMove = lastMove
        }
        SCNTransaction.commit()
    }
    
    // NEW: Territory Rendering
    private var territoryNodes: [SCNNode] = []
    
    func updateTerritory(points: [BoardPosition: Stone]) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        territoryNodes.forEach { $0.removeFromParentNode() }
        territoryNodes.removeAll()
        
        guard !points.isEmpty else { SCNTransaction.commit(); return }
        
        let w = CGFloat(boardSize - 1) * effectiveCellWidth
        let h = CGFloat(boardSize - 1) * effectiveCellHeight
        let offX = -w / 2.0; let offZ = -h / 2.0
        let tY = boardThickness / 2.0 + 0.01 // Slightly above board
        
        let box = SCNBox(width: effectiveCellWidth * 0.3, height: 0.005, length: effectiveCellHeight * 0.3, chamferRadius: 0)
        
        for (pos, owner) in points {
            let x = CGFloat(pos.col) * effectiveCellWidth + offX
            let z = CGFloat(pos.row) * effectiveCellHeight + offZ
            
            let n = SCNNode(geometry: box)
            // Black Territory -> Black Square, White -> White Square
            n.geometry?.firstMaterial?.diffuse.contents = (owner == .black) ? NSColor.black : NSColor.white
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
    func updateCameraPosition(distance: CGFloat, rotationX: Float, rotationY: Float, panX: CGFloat, panY: CGFloat) { worldAnchor.position = SCNVector3(x: panX, y: 0, z: panY); worldAnchor.eulerAngles.y = CGFloat(rotationY); worldAnchor.eulerAngles.x = CGFloat(rotationX); let r = distance / 25.0; cameraNode.position = SCNVector3(x: 0, y: 15.0 * r, z: 20.0 * r); cameraNode.look(at: SCNVector3(x: 0, y: 0, z: 0)) }
    func updateCapturedStones(black: Int, white: Int) { guard let u = upperLidNode, let l = lowerLidNode else { return }; SCNTransaction.begin(); SCNTransaction.animationDuration = 0; updateLidDiff(lid: u, current: &upperLidStones, target: black, isWhite: true); updateLidDiff(lid: l, current: &lowerLidStones, target: white, isWhite: false); SCNTransaction.commit() }
    private func updateLidDiff(lid: SCNNode, current: inout [SCNNode], target: Int, isWhite: Bool) { if current.count == target { return }; if current.count > target { while current.count > target { current.last?.removeFromParentNode(); current.removeLast() } } else { for i in current.count..<target { let g = isWhite ? clamGeometries[i % 5] : blackStoneGeometry; let n = SCNNode(geometry: g); let phi = 137.5 * (.pi / 180.0); let r = (3.5 * 0.7) * sqrt(Double(i) / 100.0); let th = Double(i) * phi; n.position = SCNVector3(x: CGFloat(cos(th)*r), y: 0.15, z: CGFloat(sin(th)*r)); n.eulerAngles = SCNVector3(CGFloat.random(in: -0.2...0.2), CGFloat.random(in: 0...6), CGFloat.random(in: -0.2...0.2)); lid.addChildNode(n); current.append(n) } } }
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
    
    private func setupBackground() { scene.background.contents = NSColor(red: 0.01, green: 0.01, blue: 0.05, alpha: 1.0) }
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
    func createLids() { upperLidNode?.removeFromParentNode(); lowerLidNode?.removeFromParentNode(); upperLidNode = createLidNode(textureName: "go_lid_1", pos: SCNVector3(x: 14.0, y: -0.2, z: -5.0)); lowerLidNode = createLidNode(textureName: "go_lid_2", pos: SCNVector3(x: 14.0, y: -0.2, z: 5.0)); if let u = upperLidNode { worldAnchor.addChildNode(u) }; if let l = lowerLidNode { worldAnchor.addChildNode(l) } }
    private func createLidNode(textureName: String, pos: SCNVector3) -> SCNNode { let cyl = SCNCylinder(radius: 3.5, height: 0.3); let m = SCNMaterial(); m.diffuse.contents = NSImage(named: textureName) ?? NSColor.brown; cyl.materials = [m]; let n = SCNNode(geometry: cyl); n.position = pos; return n }
    private func setupGhostNode() { let s = SCNSphere(radius: stoneRadius); let m = SCNMaterial(); m.diffuse.contents = NSColor(white: 1.0, alpha: 0.5); s.materials = [m]; ghostNode = SCNNode(geometry: s); ghostNode?.opacity = 0.0; stonesContainer.addChildNode(ghostNode!) }
    func updateGhostStone(at pos: BoardPosition?, color: Stone?) { guard let p = pos, let c = color else { ghostNode?.opacity = 0.0; return }; let w = CGFloat(boardSize - 1) * effectiveCellWidth; let h = CGFloat(boardSize - 1) * effectiveCellHeight; let offX = -w / 2.0; let offZ = -h / 2.0; let surfaceY = boardThickness / 2.0; let x = CGFloat(p.col) * effectiveCellWidth + offX; let z = CGFloat(p.row) * effectiveCellHeight + offZ; ghostNode?.position = SCNVector3(x, surfaceY, z); if let mat = ghostNode?.geometry?.firstMaterial { mat.diffuse.contents = (c == .black) ? NSColor(white: 0.1, alpha: 0.6) : NSColor(white: 0.9, alpha: 0.6) }; ghostNode?.opacity = 1.0 }
    func clearGhostStone() { ghostNode?.opacity = 0.0 }
}
