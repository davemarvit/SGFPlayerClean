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
    private var boardNode: SCNNode?; private var ghostNode: SCNNode?
    private var upperLidStones: [SCNNode] = []; private var lowerLidStones: [SCNNode] = []
    private var upperLidNode: SCNNode?; private var lowerLidNode: SCNNode?
    private var boardSize: Int = 19; private let boardThickness: CGFloat = 2.0
    private let stoneRadius: CGFloat = 0.48; private let stoneScaleY: CGFloat = 0.486
    private var previousLastMove: BoardPosition?
    private var effectiveCellWidth: CGFloat { CGFloat(18) / CGFloat(max(1, boardSize - 1)) }
    private var effectiveCellHeight: CGFloat { (CGFloat(18) / CGFloat(max(1, boardSize - 1))) * 1.0773 }
    
    init() {
        scene.rootNode.addChildNode(worldAnchor); scene.rootNode.addChildNode(pivotNode); pivotNode.addChildNode(cameraNode); worldAnchor.addChildNode(stonesContainer)
        setupMaterials(); setupCamera(); setupLighting(); setupBackground(); createBoard(); createLids(); setupGhostNode()
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
        blackStoneGeometry = SCNSphere(radius: stoneRadius)
        let bM = SCNMaterial(); bM.diffuse.contents = NSColor(white: 0.1, alpha: 1.0); bM.specular.contents = NSColor(white: 0.3, alpha: 1.0); bM.lightingModel = .blinn; blackStoneGeometry?.materials = [bM]
        let wM = SCNMaterial(); wM.diffuse.contents = NSColor(white: 0.95, alpha: 1.0); wM.specular.contents = NSColor(white: 1.0, alpha: 1.0); wM.lightingModel = .blinn
        for i in 0..<5 { let v = CGFloat(i) * 0.015; let g = StoneMeshFactory.createStoneGeometry(radius: stoneRadius, thickness: stoneRadius * (0.55 + v)); g.materials = [wM]; clamGeometries.append(g) }
        markerMaterial = SCNMaterial(); markerMaterial?.diffuse.contents = NSColor.red; markerMaterial?.emission.contents = NSColor.red
        glowMaterial = SCNMaterial(); glowMaterial?.lightingModel = .constant; glowMaterial?.blendMode = .alpha; glowMaterial?.diffuse.contents = generateRedGlowTexture(); glowMaterial?.writesToDepthBuffer = false
    }
    private func generateRedGlowTexture() -> NSImage { let size = 128; return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in let ctx = NSGraphicsContext.current!.cgContext; let c = CGPoint(x: size/2, y: size/2); let cols = [NSColor.red.withAlphaComponent(0.75).cgColor, NSColor.red.withAlphaComponent(0.0).cgColor] as CFArray; let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols, locations: [0.0, 1.0])!; ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size/2), options: .drawsBeforeStartLocation); return true } }
    func updateStones(from cache: [RenderStone], lastMove: BoardPosition?, moveIndex: Int, settings: AppSettings) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        let w = CGFloat(boardSize - 1) * effectiveCellWidth; let h = CGFloat(boardSize - 1) * effectiveCellHeight; let offX = -w / 2.0; let offZ = -h / 2.0; let surfaceY = boardThickness / 2.0
        let currentPos = Set(cache.map { $0.id })
        for (pos, node) in stoneNodeMap { if !currentPos.contains(pos) { node.removeFromParentNode(); stoneNodeMap.removeValue(forKey: pos) } }
        for rs in cache {
            let x = CGFloat(rs.id.col) * effectiveCellWidth + offX + (rs.offset.x * effectiveCellWidth)
            let z = CGFloat(rs.id.row) * effectiveCellHeight + offZ + (rs.offset.y * effectiveCellHeight)
            if let n = stoneNodeMap[rs.id] { n.position = SCNVector3(x, surfaceY, z) } else {
                let anchor = SCNNode(); anchor.position = SCNVector3(x, surfaceY, z)
                let geom = rs.color == .black ? blackStoneGeometry : clamGeometries[(rs.id.row * 19 + rs.id.col) % 5]
                let s = SCNNode(geometry: geom); s.scale = SCNVector3(1, stoneScaleY, 1); s.eulerAngles.y = CGFloat(rs.id.col * rs.id.row); s.position = SCNVector3(0, stoneRadius * stoneScaleY, 0)
                anchor.addChildNode(s); stonesContainer.addChildNode(anchor); stoneNodeMap[rs.id] = anchor
                if settings.showDropInAnimation { anchor.opacity = 0; anchor.position.y += 1.0; anchor.runAction(.group([.fadeIn(duration: 0.15), .move(to: SCNVector3(x, surfaceY, z), duration: 0.15)])) }
            }
        }
        if previousLastMove != lastMove || true {
            if let p = previousLastMove, let n = stoneNodeMap[p] { n.childNodes.filter({ $0.name?.contains("MARKER") ?? false }).forEach { $0.removeFromParentNode() } }
            if let c = lastMove, let n = stoneNodeMap[c] { let col = cache.first(where: { $0.id == c })?.color ?? .black; applyMarkers(to: n, color: col, index: moveIndex, settings: settings) }
            previousLastMove = lastMove
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
        if settings.showBoardGlow || settings.showEnhancedGlow { let s = settings.showEnhancedGlow ? 4.5 : 3.2; let p = SCNNode(geometry: SCNPlane(width: stoneRadius * s, height: stoneRadius * s)); p.geometry?.firstMaterial = glowMaterial; p.name = "MARKER_GLOW"; p.eulerAngles.x = -.pi/2; p.position = SCNVector3(0, 0.02, 0); p.renderingOrder = 3000; group.addChildNode(p) }
    }
    func updateCameraPosition(distance: CGFloat, rotationX: Float, rotationY: Float, panX: CGFloat, panY: CGFloat) { worldAnchor.position = SCNVector3(x: panX, y: 0, z: panY); worldAnchor.eulerAngles.y = CGFloat(rotationY); worldAnchor.eulerAngles.x = CGFloat(rotationX); let r = distance / 25.0; cameraNode.position = SCNVector3(x: 0, y: 15.0 * r, z: 20.0 * r); cameraNode.look(at: SCNVector3(x: 0, y: 0, z: 0)) }
    func updateCapturedStones(black: Int, white: Int) { guard let u = upperLidNode, let l = lowerLidNode else { return }; SCNTransaction.begin(); SCNTransaction.animationDuration = 0; updateLidDiff(lid: u, current: &upperLidStones, target: black, isWhite: true); updateLidDiff(lid: l, current: &lowerLidStones, target: white, isWhite: false); SCNTransaction.commit() }
    private func updateLidDiff(lid: SCNNode, current: inout [SCNNode], target: Int, isWhite: Bool) { if current.count == target { return }; if current.count > target { while current.count > target { current.last?.removeFromParentNode(); current.removeLast() } } else { for i in current.count..<target { let g = isWhite ? clamGeometries[i % 5] : blackStoneGeometry; let n = SCNNode(geometry: g); let phi = 137.5 * (.pi / 180.0); let r = (3.5 * 0.7) * sqrt(Double(i) / 100.0); let th = Double(i) * phi; n.position = SCNVector3(x: CGFloat(cos(th)*r), y: 0.15, z: CGFloat(sin(th)*r)); n.eulerAngles = SCNVector3(CGFloat.random(in: -0.2...0.2), CGFloat.random(in: 0...6), CGFloat.random(in: -0.2...0.2)); lid.addChildNode(n); current.append(n) } } }
    private func setupCamera() { let c = SCNCamera(); c.zNear = 0.1; c.zFar = 1000.0; cameraNode.camera = c; pivotNode.addChildNode(cameraNode); updateCameraPosition(distance: 25.0, rotationX: 0.75, rotationY: 0.0, panX: 0, panY: 0) }
    private func setupLighting() { let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.color = NSColor(white: 0.4, alpha: 1.0); worldAnchor.addChildNode(amb); let dir = SCNNode(); dir.light = SCNLight(); dir.light?.type = .directional; dir.light?.color = NSColor(white: 0.8, alpha: 1.0); dir.light?.castsShadow = true; dir.position = SCNVector3(-10, 20, -10); dir.look(at: SCNVector3(x: 0, y: 0, z: 0)); worldAnchor.addChildNode(dir) }
    private func setupBackground() { scene.background.contents = NSColor(red: 0.01, green: 0.01, blue: 0.05, alpha: 1.0) }
    private func createBoard() { boardNode?.removeFromParentNode(); let bW = CGFloat(boardSize + 1) * effectiveCellWidth; let bL = CGFloat(boardSize + 1) * effectiveCellHeight; let bG = SCNBox(width: bW, height: boardThickness, length: bL, chamferRadius: 0.0); let m = SCNMaterial(); m.diffuse.contents = NSImage(named: "board_kaya") ?? NSColor.brown; bG.materials = [m]; let n = SCNNode(geometry: bG); worldAnchor.addChildNode(n); self.boardNode = n; createGridLines() }
    private func createGridLines() { let tY = boardThickness / 2.0 + 0.02; let w = CGFloat(boardSize - 1) * effectiveCellWidth; let h = CGFloat(boardSize - 1) * effectiveCellHeight; for i in 0..<boardSize { let lZ = SCNBox(width: w, height: 0.002, length: 0.02, chamferRadius: 0); lZ.firstMaterial?.diffuse.contents = NSColor.black; let nZ = SCNNode(geometry: lZ); nZ.position = SCNVector3(x: 0, y: tY, z: CGFloat(i) * effectiveCellHeight - (h/2.0)); worldAnchor.addChildNode(nZ); let lX = SCNBox(width: 0.02, height: 0.002, length: h, chamferRadius: 0); lX.firstMaterial?.diffuse.contents = NSColor.black; let nX = SCNNode(geometry: lX); nX.position = SCNVector3(x: CGFloat(i) * effectiveCellWidth - (w/2.0), y: tY, z: 0); worldAnchor.addChildNode(nX) } }
    func createLids() { upperLidNode?.removeFromParentNode(); lowerLidNode?.removeFromParentNode(); upperLidNode = createLidNode(textureName: "go_lid_1", pos: SCNVector3(x: 14.0, y: -0.2, z: -5.0)); lowerLidNode = createLidNode(textureName: "go_lid_2", pos: SCNVector3(x: 14.0, y: -0.2, z: 5.0)); if let u = upperLidNode { worldAnchor.addChildNode(u) }; if let l = lowerLidNode { worldAnchor.addChildNode(l) } }
    private func createLidNode(textureName: String, pos: SCNVector3) -> SCNNode { let cyl = SCNCylinder(radius: 3.5, height: 0.3); let m = SCNMaterial(); m.diffuse.contents = NSImage(named: textureName) ?? NSColor.brown; cyl.materials = [m]; let n = SCNNode(geometry: cyl); n.position = pos; return n }
    private func setupGhostNode() { let s = SCNSphere(radius: stoneRadius); let m = SCNMaterial(); m.diffuse.contents = NSColor(white: 1.0, alpha: 0.5); s.materials = [m]; ghostNode = SCNNode(geometry: s); ghostNode?.opacity = 0.0; stonesContainer.addChildNode(ghostNode!) }
    func updateGhostStone(at pos: BoardPosition?, color: Stone?) { guard let p = pos, let c = color else { ghostNode?.opacity = 0.0; return }; let w = CGFloat(boardSize - 1) * effectiveCellWidth; let h = CGFloat(boardSize - 1) * effectiveCellHeight; let offX = -w / 2.0; let offZ = -h / 2.0; let surfaceY = boardThickness / 2.0; let x = CGFloat(p.col) * effectiveCellWidth + offX; let z = CGFloat(p.row) * effectiveCellHeight + offZ; ghostNode?.position = SCNVector3(x, surfaceY, z); if let mat = ghostNode?.geometry?.firstMaterial { mat.diffuse.contents = (c == .black) ? NSColor(white: 0.1, alpha: 0.6) : NSColor(white: 0.9, alpha: 0.6) }; ghostNode?.opacity = 1.0 }
    func clearGhostStone() { ghostNode?.opacity = 0.0 }
}
