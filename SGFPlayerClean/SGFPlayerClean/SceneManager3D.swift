//
//  SceneManager3D.swift
//  SGFPlayerClean
//
//  Created: 2025-11-28
//  Updated: 2025-12-04 (Fade-Out Animation for Old Moves)
//  Purpose: 3D scene management for SceneKit board rendering
//

import Foundation
import SceneKit
import AppKit

class SceneManager3D: ObservableObject {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let pivotNode = SCNNode()

    private var boardNode: SCNNode?
    private var stoneNodes: [SCNNode] = []
    
    var settings: AppSettings?
    weak var boardVM: BoardViewModel?

    private var upperLidNode: SCNNode?
    private var lowerLidNode: SCNNode?
    private var upperLidStones: [SCNNode] = []
    private var lowerLidStones: [SCNNode] = []

    // Config
    private var boardSize: Int = 19
    private let baseCellWidth: CGFloat = 1.0
    private let baseCellHeight: CGFloat = 1.0773
    private let boardThickness: CGFloat = 2.0

    private var effectiveCellWidth: CGFloat {
        let scaleFactor = CGFloat(18) / CGFloat(boardSize - 1)
        return baseCellWidth * scaleFactor
    }
    private var effectiveCellHeight: CGFloat {
        let scaleFactor = CGFloat(18) / CGFloat(boardSize - 1)
        return baseCellHeight * scaleFactor
    }
    
    // Standard Stone Sizes
    private let stoneRadius: CGFloat = 0.48
    private let stoneScaleY: CGFloat = 0.486
    
    // Deep Red Color
    private let deepRedColor = NSColor(calibratedRed: 0.75, green: 0.0, blue: 0.0, alpha: 1.0)
    private let markerRedColor = NSColor(calibratedRed: 0.6, green: 0.0, blue: 0.0, alpha: 1.0)

    private var previousLastMove: (x: Int, y: Int)?
    private var previousBoardState: [[Stone?]] = []

    init() {
        setupCamera()
        setupLighting()
        setupBackground()
        createBoard()
        createLids()
        print("✅ SceneManager3D: Initialized with Fade-Out Glows")
    }

    // MARK: - Scene Setup
    private func setupBackground() {
        scene.background.contents = NSColor(red: 0.01, green: 0.01, blue: 0.05, alpha: 1.0)
    }

    private func setupCamera() {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 1000.0
        cameraNode.camera = camera
        pivotNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(pivotNode)
        pivotNode.addChildNode(cameraNode)
        updateCameraPosition(distance: 25.0, rotationX: -0.7, rotationY: 0.0, panX: 0, panY: 0)
    }
    
    func updateCameraPosition(distance: CGFloat, rotationX: Float, rotationY: Float, panX: CGFloat, panY: CGFloat) {
        pivotNode.eulerAngles.y = CGFloat(rotationY)
        pivotNode.eulerAngles.x = CGFloat(rotationX)
        let baseY: CGFloat = 15
        let baseZ: CGFloat = 20
        let distanceRatio = distance / 25.0
        cameraNode.position = SCNVector3(x: panX, y: baseY * distanceRatio + panY, z: baseZ * distanceRatio)
        cameraNode.look(at: SCNVector3(x: panX, y: panY, z: 0))
    }

    private func setupLighting() {
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = NSColor(white: 0.4, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light!.type = .directional
        directionalLight.light!.color = NSColor(white: 0.8, alpha: 1.0)
        directionalLight.light!.castsShadow = true
        directionalLight.position = SCNVector3(-10, 20, -10)
        directionalLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalLight)
    }

    // MARK: - Board Creation
    private func createBoard() {
        boardNode?.removeFromParentNode()
        scene.rootNode.childNodes.filter { node in
            (node.geometry is SCNBox || node.geometry is SCNSphere) && node.position.y >= -boardThickness
        }.forEach { $0.removeFromParentNode() }

        let boardWidth = CGFloat(boardSize + 1) * effectiveCellWidth
        let boardLength = CGFloat(boardSize + 1) * effectiveCellHeight
        let boardGeometry = SCNBox(width: boardWidth, height: boardThickness, length: boardLength, chamferRadius: 0.0)
        
        let material = SCNMaterial()
        if let kayaImage = NSImage(named: "board_kaya") {
            material.diffuse.contents = kayaImage
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
        } else {
            material.diffuse.contents = NSColor(red: 0.7, green: 0.5, blue: 0.3, alpha: 1.0)
        }
        material.specular.contents = NSColor(white: 0.3, alpha: 1.0)
        material.shininess = 0.1
        boardGeometry.materials = [material]

        let boardNode = SCNNode(geometry: boardGeometry)
        boardNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(boardNode)
        self.boardNode = boardNode
        
        let backingGeometry = SCNBox(width: boardWidth, height: 0.1, length: boardLength, chamferRadius: 0.0)
        let backingMaterial = SCNMaterial()
        backingMaterial.diffuse.contents = NSColor(red: 0.7, green: 0.5, blue: 0.3, alpha: 1.0)
        backingGeometry.materials = [backingMaterial]
        let backingNode = SCNNode(geometry: backingGeometry)
        backingNode.position = SCNVector3(0, -(boardThickness / 2.0 + 0.05), 0)
        scene.rootNode.addChildNode(backingNode)

        createGridLines()
    }
    
    private func createGridLines() {
        let lineThickness: CGFloat = 0.02
        let lineHeight: CGFloat = 0.002
        let lineColor = NSColor.black
        let boardTopY = boardThickness / 2.0 + 0.02
        let totalWidth = CGFloat(boardSize - 1) * effectiveCellWidth
        let totalHeight = CGFloat(boardSize - 1) * effectiveCellHeight

        for i in 0..<boardSize {
            let z = CGFloat(i) * effectiveCellHeight - (totalHeight / 2.0)
            let line = SCNBox(width: totalWidth, height: lineHeight, length: lineThickness, chamferRadius: 0)
            line.firstMaterial?.diffuse.contents = lineColor
            let node = SCNNode(geometry: line)
            node.position = SCNVector3(0, boardTopY, z)
            scene.rootNode.addChildNode(node)
        }
        for i in 0..<boardSize {
            let x = CGFloat(i) * effectiveCellWidth - (totalWidth / 2.0)
            let line = SCNBox(width: lineThickness, height: lineHeight, length: totalHeight, chamferRadius: 0)
            line.firstMaterial?.diffuse.contents = lineColor
            let node = SCNNode(geometry: line)
            node.position = SCNVector3(x, boardTopY, 0)
            scene.rootNode.addChildNode(node)
        }
        let stars: [(Int, Int)] = (boardSize == 19) ? [(3,3),(3,9),(3,15),(9,3),(9,9),(9,15),(15,3),(15,9),(15,15)] : []
        for (col, row) in stars {
            let x = CGFloat(col) * effectiveCellWidth - (totalWidth / 2.0)
            let z = CGFloat(row) * effectiveCellHeight - (totalHeight / 2.0)
            let star = SCNSphere(radius: 0.08)
            star.firstMaterial?.diffuse.contents = lineColor
            let node = SCNNode(geometry: star)
            node.position = SCNVector3(x, boardTopY + 0.01, z)
            scene.rootNode.addChildNode(node)
        }
    }

    // MARK: - Stone Rendering

    func updateStones(from board: BoardSnapshot, lastMove: (x: Int, y: Int)?) {
        if boardSize != board.size {
            boardSize = board.size
            createBoard()
            previousBoardState = []
        }
        
        // FADE OUT ANIMATION:
        // Before clearing stones, if there was a previous move that is DIFFERENT from the current one,
        // spawn a ghost glow there to fade out.
        if let prev = previousLastMove,
           let settings = settings,
           (settings.showBoardGlow || settings.showEnhancedGlow) {
            
            // Check if the previous move is no longer the last move
            // (either a new move happened, or we went backward)
            let isSameAsCurrent = (lastMove != nil && lastMove!.x == prev.x && lastMove!.y == prev.y)
            
            if !isSameAsCurrent {
                spawnFadeOutGlow(col: prev.x, row: prev.y, settings: settings)
            }
        }

        stoneNodes.forEach { $0.removeFromParentNode() }
        stoneNodes.removeAll()

        let totalWidth = CGFloat(boardSize - 1) * effectiveCellWidth
        let totalHeight = CGFloat(boardSize - 1) * effectiveCellHeight
        let offsetX = -totalWidth / 2.0
        let offsetZ = -totalHeight / 2.0
        
        let boardTopY = boardThickness / 2.0
        let stoneHalfHeight = stoneRadius * stoneScaleY
        let stoneY = boardTopY + stoneHalfHeight - 0.01

        for row in 0..<board.size {
            for col in 0..<board.size {
                if let stone = board.grid[row][col] {
                    var x = CGFloat(col) * effectiveCellWidth + offsetX
                    var z = CGFloat(row) * effectiveCellHeight + offsetZ

                    if let boardVM = boardVM {
                        let jitterOffset = boardVM.getJitterOffset(forPosition: BoardPosition(row, col))
                        x += jitterOffset.x * effectiveCellWidth
                        z += jitterOffset.y * effectiveCellHeight
                    }

                    let targetPosition = SCNVector3(x, stoneY, z)
                    let stoneNode = createSolidStone(color: stone, at: targetPosition, radius: stoneRadius)

                    let isLastMove = (lastMove != nil && lastMove!.x == col && lastMove!.y == row)
                    
                    if isLastMove {
                        addLastMoveIndicator(to: stoneNode, color: stone, radius: stoneRadius)
                        
                        if let settings = settings, (settings.showBoardGlow || settings.showEnhancedGlow) {
                            stoneNode.castsShadow = false
                            addGlow(to: stoneNode, settings: settings, stoneY: stoneY, boardTopY: boardTopY)
                        }
                    }

                    scene.rootNode.addChildNode(stoneNode)
                    stoneNodes.append(stoneNode)
                    
                    // Drop-In Animation
                    if isLastMove, let settings = settings, settings.showDropInAnimation {
                        stoneNode.position.y += 1.5
                        stoneNode.opacity = 0.0
                        
                        SCNTransaction.begin()
                        SCNTransaction.animationDuration = 0.3
                        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
                        stoneNode.position.y = targetPosition.y
                        stoneNode.opacity = 1.0
                        SCNTransaction.commit()
                    }
                }
            }
        }
        previousBoardState = board.grid
        previousLastMove = lastMove
    }

    private func createSolidStone(color: Stone, at position: SCNVector3, radius: CGFloat) -> SCNNode {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 48
        let material = SCNMaterial()

        switch color {
        case .black:
            material.diffuse.contents = NSColor(white: 0.1, alpha: 1.0)
            material.specular.contents = NSColor(white: 0.3, alpha: 1.0)
            material.roughness.contents = 0.4
        case .white:
            material.diffuse.contents = NSColor(white: 0.95, alpha: 1.0)
            material.specular.contents = NSColor(white: 1.0, alpha: 1.0)
            material.roughness.contents = 0.1
            material.shininess = 1.0
        }
        
        material.isDoubleSided = false
        material.lightingModel = .blinn
        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.scale = SCNVector3(1.0, stoneScaleY, 1.0)
        node.position = position
        node.castsShadow = true
        return node
    }
    
    private func addLastMoveIndicator(to stoneNode: SCNNode, color: Stone, radius: CGFloat) {
        if settings?.showLastMoveDot == true {
            let dot = SCNSphere(radius: radius * 0.15)
            dot.firstMaterial?.diffuse.contents = markerRedColor
            dot.firstMaterial?.emission.contents = markerRedColor
            let node = SCNNode(geometry: dot)
            node.position = SCNVector3(0, radius * 1.05, 0)
            stoneNode.addChildNode(node)
        }
    }
    
    private func addGlow(to stoneNode: SCNNode, settings: AppSettings, stoneY: CGFloat, boardTopY: CGFloat) {
        let isEnhanced = settings.showEnhancedGlow
        let scaleMultiplier: CGFloat = isEnhanced ? 1.8 : 1.5
        let glowRadius = stoneRadius * scaleMultiplier
        let plane = SCNPlane(width: glowRadius * 2, height: glowRadius * 2)
        
        let material = SCNMaterial()
        material.lightingModel = .constant
        let softness: CGFloat = isEnhanced ? 0.0 : 0.3
        material.diffuse.contents = generateGlowTexture(color: deepRedColor, size: 256, softness: softness)
        material.blendMode = .alpha
        material.transparencyMode = .default
        material.writesToDepthBuffer = false
        plane.materials = [material]
        
        let glowNode = SCNNode(geometry: plane)
        glowNode.eulerAngles.x = -.pi / 2
        glowNode.castsShadow = false
        glowNode.renderingOrder = 2000
        
        // Position fix relative to stone
        let worldFloorY = boardTopY + 0.005
        let offsetFromCenter = worldFloorY - stoneY
        let localY = offsetFromCenter / stoneScaleY
        
        glowNode.position = SCNVector3(0, localY, 0)
        
        let targetOpacity: CGFloat = isEnhanced ? 0.8 : 0.9
        glowNode.opacity = 0.0
        stoneNode.addChildNode(glowNode)
        
        if settings.showDropInAnimation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.15
                glowNode.opacity = targetOpacity
                SCNTransaction.commit()
            }
        } else {
            glowNode.opacity = targetOpacity
        }
    }
    
    // NEW: Spawns a standalone glow that fades out
    private func spawnFadeOutGlow(col: Int, row: Int, settings: AppSettings) {
        let isEnhanced = settings.showEnhancedGlow
        let scaleMultiplier: CGFloat = isEnhanced ? 1.8 : 1.5
        let glowRadius = stoneRadius * scaleMultiplier
        let plane = SCNPlane(width: glowRadius * 2, height: glowRadius * 2)
        
        let material = SCNMaterial()
        material.lightingModel = .constant
        let softness: CGFloat = isEnhanced ? 0.0 : 0.3
        material.diffuse.contents = generateGlowTexture(color: deepRedColor, size: 256, softness: softness)
        material.blendMode = .alpha
        material.transparencyMode = .default
        material.writesToDepthBuffer = false
        plane.materials = [material]
        
        let glowNode = SCNNode(geometry: plane)
        glowNode.eulerAngles.x = -.pi / 2
        glowNode.castsShadow = false
        glowNode.renderingOrder = 2000
        
        // Position logic (Manual calculation since no stone parent)
        let totalWidth = CGFloat(boardSize - 1) * effectiveCellWidth
        let totalHeight = CGFloat(boardSize - 1) * effectiveCellHeight
        let offsetX = -totalWidth / 2.0
        let offsetZ = -totalHeight / 2.0
        
        var x = CGFloat(col) * effectiveCellWidth + offsetX
        var z = CGFloat(row) * effectiveCellHeight + offsetZ
        
        if let boardVM = boardVM {
            let jitterOffset = boardVM.getJitterOffset(forPosition: BoardPosition(row, col))
            x += jitterOffset.x * effectiveCellWidth
            z += jitterOffset.y * effectiveCellHeight
        }
        
        let boardTopY = boardThickness / 2.0 + 0.005
        glowNode.position = SCNVector3(x, boardTopY, z)
        
        // Start visible, animate to 0
        let startOpacity: CGFloat = isEnhanced ? 0.8 : 0.9
        glowNode.opacity = startOpacity
        
        scene.rootNode.addChildNode(glowNode)
        
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        SCNTransaction.completionBlock = {
            glowNode.removeFromParentNode()
        }
        glowNode.opacity = 0.0
        SCNTransaction.commit()
    }

    private func generateGlowTexture(color: NSColor, size: Int, softness: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            let locations: [CGFloat] = [softness, 1.0]
            
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                let center = CGPoint(x: size/2, y: size/2)
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size)/2, options: .drawsBeforeStartLocation)
            }
        }
        img.unlockFocus()
        return img
    }

    // MARK: - Lids
    private func createLids() {
        upperLidNode?.removeFromParentNode()
        lowerLidNode?.removeFromParentNode()
        
        upperLidNode = createLidNode(textureName: "go_lid_1", position: SCNVector3(14.0, -0.2, -5.0), radius: 3.5)
        if let lid = upperLidNode { scene.rootNode.addChildNode(lid) }
        
        lowerLidNode = createLidNode(textureName: "go_lid_2", position: SCNVector3(14.0, -0.2, 5.0), radius: 3.5)
        if let lid = lowerLidNode { scene.rootNode.addChildNode(lid) }
    }
    
    private func createLidNode(textureName: String, position: SCNVector3, radius: CGFloat) -> SCNNode {
        let cyl = SCNCylinder(radius: radius, height: 0.3)
        cyl.radialSegmentCount = 64
        let mat = SCNMaterial()
        if let image = NSImage(named: textureName) {
            mat.diffuse.contents = image
        } else {
            mat.diffuse.contents = NSColor.brown
        }
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        mat.roughness.contents = 0.4
        mat.specular.contents = NSColor(white: 0.2, alpha: 1.0)
        cyl.materials = [mat]
        let node = SCNNode(geometry: cyl)
        node.position = position
        node.castsShadow = true
        return node
    }
    
    func updateCapturedStones(blackCaptured: Int, whiteCaptured: Int) {
        upperLidStones.forEach { $0.removeFromParentNode() }
        lowerLidStones.forEach { $0.removeFromParentNode() }
        upperLidStones.removeAll()
        lowerLidStones.removeAll()

        guard let upperLid = upperLidNode, let lowerLid = lowerLidNode else { return }
        let lidRadius: CGFloat = 3.5
        let stoneSize = stoneRadius

        for _ in 0..<blackCaptured {
            let pos = randomPositionInLid(radius: lidRadius * 0.7)
            let stone = createSolidStone(color: .white, at: pos, radius: stoneSize)
            stone.position.y = 0.15 + (stoneRadius * stoneScaleY)
            stone.castsShadow = false
            upperLid.addChildNode(stone)
            upperLidStones.append(stone)
        }
        for _ in 0..<whiteCaptured {
            let pos = randomPositionInLid(radius: lidRadius * 0.7)
            let stone = createSolidStone(color: .black, at: pos, radius: stoneSize)
            stone.position.y = 0.15 + (stoneRadius * stoneScaleY)
            stone.castsShadow = false
            lowerLid.addChildNode(stone)
            lowerLidStones.append(stone)
        }
    }
    
    private func randomPositionInLid(radius: CGFloat) -> SCNVector3 {
        let angle = Double.random(in: 0...2 * .pi)
        let dist = sqrt(Double.random(in: 0...1)) * Double(radius)
        return SCNVector3(CGFloat(cos(angle) * dist), 0.0, CGFloat(sin(angle) * dist))
    }
}
