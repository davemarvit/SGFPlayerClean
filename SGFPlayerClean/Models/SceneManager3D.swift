// ========================================================
// FILE: ./Models/SceneManager3D.swift
// VERSION: v4.500 (HitTest Debug & Retina Fix)
// ========================================================
import Foundation
import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import QuartzCore
import simd

protocol CameraArrivalPlayback: AnyObject {
    func updateEnvironmentPlayback()
}

class SceneManager3D: NSObject, ObservableObject {
    final class ArrivalCameraNode: SCNNode {
        var isPreparingOrArriving = false
    }
    static let backgroundColor = NSColor(srgbRed: 0.50, green: 0.51, blue: 0.43, alpha: 1)
    // ... (Init/Setup code identical to v4.401, omitted for brevity except changed HitTest) ...
    // COPY ALL properties and init from v4.401
    let scene = SCNScene(); let cameraNode = ArrivalCameraNode(); let pivotNode = SCNNode()
    private let worldAnchor = SCNNode()
    private let shoji = ShojiEnvironment()
    private var environments: [PlayingEnvironment: PlayingEnvironmentScene] = [:]
    private(set) var currentEnvironment: PlayingEnvironment = .gardenRoom
    private var environmentActive = true
    private var lampFlickerEnabled = true
    private var environmentMotionEnabled = true
    var equipmentOffsetX: CGFloat { currentEnvironment.equipmentOffsetX(boardWidth: CGFloat(boardSize + 1) * effectiveCellWidth) }
    private var canopySun: SCNNode?
    private var arrivalTimer: Timer?
    private var arrivalStartedAt: CFTimeInterval = 0
    private var arrivalDestination: simd_float4x4?
    private var recenterStart: simd_float4x4?
    private var recenterOpeningScale: CGFloat = 1
    private var arrivalOpening = (eye: SIMD3<Float>.zero, gaze: SIMD3<Float>.zero)
    private var arrivalOpeningOrientation = simd_quatf(real: 1, imag: .zero)
    private var playingFieldOfView: CGFloat = 60
    private var arrivalProgress: CGFloat = 1
    // Opt in only in the Mac board view; other consumers keep their existing behavior.
    let optimizesCameraArrival: Bool
    private var arrivalPreparationID: UUID?
    private var arrivalResourcesPrepared = false
    private var arrivalReleasedAt: TimeInterval?
    private weak var arrivalView: SCNView?
    private var arrivalViewPlayback: (playing: Bool, continuous: Bool)?
    private var arrivalShadowSamples: [(SCNLight, Int)] = []
    static let cameraArrivalMaximumHold: TimeInterval = 1.5
    var isCameraArriving: Bool { arrivalDestination != nil }
    static let cameraArrivalHoldDuration: TimeInterval = 1.0
    static let cameraArrivalSurveyDuration: TimeInterval = 7.0
    static let cameraArrivalDuration: TimeInterval = 12.0
    static let cameraArrivalTotalDuration = cameraArrivalHoldDuration + cameraArrivalDuration
    static let cameraRecenterDuration: TimeInterval = 1.1
    static let seatedCameraRotationX: Float = 0.44

    /// The grid keeps its physical span across board sizes; smaller grids have
    /// wider wooden margins. Allow for those margins at a comfortable seated pitch.
    static func seatedCameraDistance(boardSize: Int) -> CGFloat {
        let width = CGFloat(boardSize + 1) * 18 / CGFloat(max(1, boardSize - 1))
        return max(28, width * 1.4)
    }

    /// Preserve the viewport's existing fitting while gently narrowing the
    /// wider establishing lens to the normal playing lens during arrival.
    func updateCameraFieldOfView(_ degrees: CGFloat) {
        playingFieldOfView = degrees
        applyCameraFieldOfView()
    }

    private func applyCameraFieldOfView() {
        let openingScale = recenterStart != nil ? recenterOpeningScale
            : tan(currentEnvironment.arrivalFieldOfView * .pi / 360) / tan(.pi / 6)
        let scale = 1 + (openingScale - 1) * (1 - arrivalProgress)
        cameraNode.camera?.fieldOfView = 2 * atan(tan(playingFieldOfView * .pi / 360) * scale) * 180 / .pi
    }
    private let stonesContainer = SCNNode()
    private var blackStoneGeometry: SCNGeometry?; private var clamGeometries: [SCNGeometry] = []
    private var stoneNodeMap: [BoardPosition: SCNNode] = [:]
    private var markerMaterial: SCNMaterial?; private var glowMaterial: SCNMaterial?
    private var whiteMaterial: SCNMaterial?; private var blackMaterial: SCNMaterial? // Store references
    private var showsBoardCoordinates = false
    private var boardNode: SCNNode?; private var ghostNode: SCNNode?
    private var ghostLandingNode: SCNNode?
    private var boardCursorPosition: BoardPosition?
    private var ghostBoardPosition: BoardPosition?
    private var ghostColor: Stone?
    private static let ghostGlideKey = "ghost-glide"
    private static let stoneWobbleKey = "stone-landing-wobble"
    private final class StoneVisualNode: SCNNode {
        var landingRestAngles: SCNVector3?
    }
    private struct GhostPlacement {
        let point: BoardPosition
        let color: Stone
        let position: SCNVector3
        let geometry: SCNGeometry?
        let eulerAngles: SCNVector3
    }
    private var pendingGhostPlacement: GhostPlacement?
    private var reviewVariationNodes: [SCNNode] = []
    private var reviewVariations: [ReviewTree.BoardVariation] = []
    private lazy var boardCursorTexture: NSImage = {
        NSImage(size: NSSize(width: 128, height: 128), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let colors = [1.0, 0.95, 0.5, 0.0].map {
                NSColor(srgbRed: 1, green: 0.025, blue: 0.01, alpha: $0).cgColor
            }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray, locations: [0, 0.2, 0.55, 1]) else { return false }
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
            return true
        }
    }()
    private var upperLidStones: [SCNNode] = []; private var lowerLidStones: [SCNNode] = []
    private var upperLidNode: SCNNode?; private var lowerLidNode: SCNNode?
    private var aiHintNodes: [SCNNode] = [] // 3D AI OVERLAYS
    private var ownershipNodes: [SCNNode] = []
    private var displayedOwnership: [BoardPosition: AIOwnershipEstimate] = [:]
    private var ownershipBoardSize = 0
    private var boardSize: Int = 19
    private let boardThickness: CGFloat = 2.0
    // Dynamic Radius: 48% of cell width (leaves 4% gap)
    private var stoneRadius: CGFloat { effectiveCellWidth * 0.48 }
    private let stoneScaleY: CGFloat = 0.486
    private var placementHoverHeight: CGFloat { effectiveCellWidth * 1.5 }
    private let ghostOpacity: CGFloat = 0.48
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
        blackStoneGeometry?.firstMaterial?.emission.contents = NSColor.black
        
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
        applyEnvironmentLighting()
        SCNTransaction.commit()
    }
    
    /// Cache scenery and leave the board, camera and settled equipment intact.
    func updateEnvironment(_ kind: PlayingEnvironment, flicker: Bool, motion: Bool = true) {
        environmentMotionEnabled = motion
        lampFlickerEnabled = flicker
        if currentEnvironment != kind || environments[kind] == nil {
            finishCameraArrival()
            environments[currentEnvironment]?.setFlickering(false)
            environments[currentEnvironment]?.setMotionEnabled(false)
            environments[currentEnvironment]?.node.removeFromParentNode()
            let changesBoardStyle = currentEnvironment.usesTableBoard != kind.usesTableBoard
            let changesBoardFinish = currentEnvironment.boardTopAsset != kind.boardTopAsset
            currentEnvironment = kind
            scene.physicsWorld.gravity = SCNVector3(0, -kind.gravity, 0)
            if environments[kind] == nil { environments[kind] = PlayingEnvironmentScene(kind) }
            environments[kind]!.node.position.y = .init(kind.sceneryOffset)
            worldAnchor.addChildNode(environments[kind]!.node)
            if changesBoardStyle {
                createBoard()
                // Preserve the same lids and settled captures while moving
                // between floor equipment and a real tabletop arrangement.
                for name in ["white-player-lid", "black-player-lid", "white-stone-bowl", "black-stone-bowl"] {
                    guard let equipment = worldAnchor.childNode(withName: name, recursively: false) else { continue }
                    var settled: [(SCNNode, simd_float4x4)] = []
                    equipment.enumerateChildNodes { child, _ in
                        if child.physicsBody != nil { settled.append((child, child.presentation.simdTransform)) }
                    }
                    equipment.position.x = .init(equipment.position.x < 0 ? -equipmentOffsetX : equipmentOffsetX)
                    if name == "black-player-lid" { equipment.position.z = .init(kind.blackLidZ) }
                    if name == "black-stone-bowl" { equipment.position.z = .init(kind.blackBowlZ) }
                    equipment.position.y = .init(kind.equipmentSurfaceY + 0.165)
                    equipment.physicsBody?.resetTransform()
                    for (child, pose) in settled {
                        child.simdTransform = pose
                        child.physicsBody?.resetTransform()
                    }
                }
                let floor = worldAnchor.childNode(withName: "tatami-environment", recursively: false)
                floor?.position.y = .init(kind.sceneryOffset)
                floor?.childNodes.forEach { $0.physicsBody?.resetTransform() }
            }
            if changesBoardFinish && !changesBoardStyle { createBoard() }
            shoji.node.isHidden = kind != .gardenRoom
            // The invisible collision floor remains active for overflowing captures.
            worldAnchor.childNode(withName: "tatami-environment", recursively: false)?.childNodes.forEach {
                if $0.physicsBody == nil {
                    $0.isHidden = $0.name == "room-tatami" ? kind != .gardenRoom : true
                }
            }
            // A complete spherical panorama remains visible through every opening,
            // including when orbiting outside the cutaway walls.
            scene.background.contents = kind == .gardenRoom
                ? (EnvironmentMaterials.panorama(kind) ?? kind.background) : kind.background
            scene.fogColor = kind.background
            scene.fogStartDistance = kind == .spaceStation ? 1900 : 800
            scene.fogEndDistance = kind == .spaceStation ? 2000 : 950
            cameraNode.camera?.zFar = kind == .spaceStation ? 2000 : 1000
            applyEnvironmentLighting()
            environments[kind]?.updateVisibility(camera: cameraNode.worldPosition)
        }
        environments[kind]?.setFlickering(flicker && environmentActive)
        environments[kind]?.setMotionEnabled(motion && environmentActive)
    }

    func setEnvironmentActive(_ active: Bool) {
        if !active { finishCameraArrival() }
        environmentActive = active
        environments[currentEnvironment]?.setFlickering(active && lampFlickerEnabled)
        environments[currentEnvironment]?.setMotionEnabled(active && environmentMotionEnabled)
    }

    private func applyEnvironmentLighting() {
        let cave = currentEnvironment == .cave
        let gardenRoom = currentEnvironment == .gardenRoom
        let moon = currentEnvironment == .moon
        let summit = currentEnvironment == .mountainSummit
        let monastery = currentEnvironment == .monastery
        let tree = currentEnvironment == .tree
        let yugen = currentEnvironment == .yugenRoom
        let laboratory = currentEnvironment == .laboratory
        let station = currentEnvironment == .spaceStation
        let indoor = monastery || yugen || currentEnvironment.usesTableBoard
        // Compress the lamp's bright reflections instead of clipping white stones.
        cameraNode.camera?.wantsHDR = cave
        cameraNode.camera?.wantsExposureAdaptation = false
        cameraNode.camera?.exposureOffset = cave ? -0.15 : 0
        let sunNode = worldAnchor.childNode(withName: "SUN", recursively: false)
        let sun = sunNode?.light
        // The panorama's sun is at azimuth -45°, elevation 48°.
        sunNode?.position = SCNVector3(-20, 31.4, -20)
        sunNode?.look(at: SCNVector3Zero)
        sun?.color = cave ? NSColor(white: 0.035, alpha: 1) : NSColor(white: lightIntensity * (monastery ? 0.80 : laboratory ? 0.78 : 1), alpha: 1)
        sun?.castsShadow = true
        sun?.shadowColor = NSColor(white: 0, alpha: gardenRoom ? 0.60 : moon ? 0.96 : monastery || yugen || tree ? 0.94 : indoor ? 0.78 : 0.88)
        sun?.shadowRadius = gardenRoom ? 7 : moon ? 0.5 : tree ? 1.8 : monastery || yugen ? 1.6 : indoor ? 3 : 1.5
        sun?.shadowSampleCount = gardenRoom ? 32 : 16
        sun?.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun?.orthographicScale = 65
        sun?.zNear = 0.1; sun?.zFar = 180
        sun?.shadowBias = 0.025
        // A single shadow map only records the nearest occluder. A closed
        // canopy therefore erases the distinct shadows of objects beneath it.
        // Split the existing daylight into sun through foliage and soft sky
        // fill, whose shadow map excludes only the high canopy. Their energy
        // still sums to the original daylight; equipment occludes both paths.
        sun?.categoryBitMask = -1
        sun?.automaticallyAdjustsShadowProjection = true
        sun?.intensity = gardenRoom ? 650 : tree ? 480 : 1000
        if summit {
            // The panorama is mirrored at display time: its measured sun at
            // u=0.3185, v=0.4115 now lies at azimuth +65.3°, elevation 15.9°.
            sunNode?.position = SCNVector3(36, 11.4, -16.6)
            sunNode?.look(at: SCNVector3Zero)
            sun?.color = NSColor(srgbRed: lightIntensity, green: lightIntensity * 0.79,
                                 blue: lightIntensity * 0.57, alpha: 1)
            sun?.intensity = 1100
            sun?.shadowRadius = 1.8
            sun?.shadowBias = 0.008
        }
        if station {
            sun?.color = NSColor(srgbRed: lightIntensity * 0.78, green: lightIntensity * 0.88, blue: lightIntensity, alpha: 1)
            sun?.intensity = 850
            sun?.shadowRadius = 2
        }
        if tree, let sun, let sunNode {
            let foliage = canopySun ?? SCNNode()
            foliage.name = "SUN_CANOPY"
            foliage.light = sun.copy() as? SCNLight
            foliage.light?.categoryBitMask = -1
            foliage.light?.intensity = 520
            foliage.light?.shadowColor = NSColor(white: 0, alpha: 1)
            foliage.light?.shadowRadius = 3.8
            foliage.transform = sunNode.transform
            if foliage.parent == nil { worldAnchor.addChildNode(foliage) }
            canopySun = foliage
            // Category masks filter receivers, not shadow casters. Keep this
            // overhead fill's entire shadow frustum below the canopy at y=19.
            sunNode.position = SCNVector3(0, 17, 0)
            sunNode.look(at: SCNVector3Zero)
            sun.automaticallyAdjustsShadowProjection = false
            sun.zNear = 0.1; sun.zFar = 60
            sun.shadowRadius = 1.7
        } else {
            canopySun?.removeFromParentNode()
        }
        // The lamp is the cave's only directional/specular source. Even a weak
        // overhead sun or sky reflection adds a second highlight to dark stones
        // and fills shadows cast by the actual lamp from another direction.
        if cave { sun?.intensity = 0 }
        // Normal startup retains these legacy fill lights; the debug settings
        // path removes them. Limit both paths to the same faint cave bounce so
        // unshadowed ambient light cannot flatten stones or erase lamp shadows.
        worldAnchor.childNode(withName: "AMB_BOARD", recursively: false)?.light?.color =
            NSColor(white: cave ? 0.018 : summit ? 0.07 : boardAmbientIntensity, alpha: 1)
        worldAnchor.childNode(withName: "AMB_STONE", recursively: false)?.light?.color =
            NSColor(white: cave ? 0.018 : summit ? 0.09 : stoneAmbientIntensity, alpha: 1)
        scene.lightingEnvironment.intensity = CGFloat(envIntensity * (cave ? 0 : summit ? 0.55 : gardenRoom ? 0.95 : moon ? 0.45 : monastery ? 0.32 : tree ? 0.56 : yugen ? 0.58 : laboratory ? 0.45 : 0.85))
        worldAnchor.childNode(withName: "AMB_GLOBAL", recursively: false)?.light?.color =
            NSColor(white: cave ? 0.018 : 0.05, alpha: 1)
        whiteMaterial?.emission.contents = NSColor(white: cave ? 0 : summit ? 0.02 : stoneAmbientIntensity * 0.3, alpha: 1)
        // Let the nearby lamp model the slab and carved feet instead of flattening
        // their relief with the daylight bounce value.
        if let boardNode {
            let bounce = CGFloat(boardAmbientIntensity * (cave ? 0.035 : summit ? 0.16 : monastery ? 0.18 : tree || yugen ? 0.34 : 0.65))
            for material in boardNode.geometry?.materials ?? [] {
                material.emission.contents = material.diffuse.contents
                material.emission.intensity = bounce
            }
        }
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
            reviewVariationNodes.removeAll()
            reviewVariations.removeAll()
            setupGhostNode()
            aiHintNodes.forEach { $0.removeFromParentNode() }
            aiHintNodes.removeAll()
            previousLastMove = nil
            
            // 4. Update Lids Position (Optional, but good for 9x9 centering)
            createLids()
        }
    }
    
    init(optimizesCameraArrival: Bool = false) {
        self.optimizesCameraArrival = optimizesCameraArrival
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
        createTatamiFloor()
        shoji.node.position.y = .init(KayaFloorBoard.sceneryOffset)
        worldAnchor.addChildNode(shoji.node)
        shoji.updateVisibility(cameraPosition: cameraNode.worldPosition)
        createLids()
        setupGhostNode()
        
        // Stable physics timing for capture piles.
        scene.physicsWorld.gravity = SCNVector3(0, -19.62, 0)
        scene.physicsWorld.speed = 1.0
        scene.physicsWorld.timeStep = 1.0 / 120.0
        updateEnvironment(.gardenRoom, flicker: true)
    }
    
    // ... (Insert setupMaterials, createBoard, etc from v4.401 here) ...
    
    // PASTE THESE HELPERS from v4.401: setupMaterials, generateRedGlowTexture, updateStones, applyMarkers, updateCameraPosition, updateCapturedStones, updateLidDiff, setupCamera, setupLighting, setupBackground, createBoard, createGridLines, createLids, createLidNode, setupGhostNode, updateGhostStone, clearGhostStone
    // (I am omitting them to save space, assuming you have v4.401 clipboard history. If not, I can reprint.)
    
    /// Only the upward playing face blocks camera drags; the slab sides and feet remain draggable.
    func isPointOnBoard(_ point: CGPoint, in view: SCNView) -> Bool {
        guard let boardNode else { return false }
        guard let hit = view.hitTest(point, options: [.rootNode: boardNode,
            .searchMode: SCNHitTestSearchMode.all.rawValue]).first(where: { $0.node === boardNode }) else { return false }
        return hit.node === boardNode && hit.localNormal.y > 0.9 && hit.localCoordinates.y > 0.99
    }

    // UPDATED HIT TEST
    func hitTest(point: CGPoint, in view: SCNView) -> (x: Int, y: Int)? {
        // v4.500: Debug Hit Test
        // Convert point for Retina displays if needed
        // SCNView hitTest expects point in view's coordinate system (points), not pixels.
        // However, we verify if the boardNode is even found.
        
        let options: [SCNHitTestOption: Any] = [.searchMode: SCNHitTestSearchMode.all.rawValue, .rootNode: worldAnchor]
        let results = view.hitTest(point, options: options)

        // A raised preview can project away from its underlying intersection.
        // Clicking its visible stone still chooses that saved branch.
        for result in results {
            var ancestor: SCNNode? = result.node
            while let node = ancestor {
                if let index = reviewVariationNodes.firstIndex(where: { $0 === node }) {
                    let point = reviewVariations[index].position
                    return (point.col, point.row)
                }
                ancestor = node.parent
            }
            if result.node === boardNode { break }
        }
        
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
    
    /// Played, captured and supply stones share the same finish for their color.
    /// Retaining these materials across board resizing also updates settled piles.
    func stoneMaterial(isWhite: Bool) -> SCNMaterial {
        (isWhite ? whiteMaterial : blackMaterial)!
    }

    private func setupMaterials() {
        // Clear old
        clamGeometries.removeAll()
        
        // BLACK STONE: slightly larger (Standard Go Physics: Black absorbs light, looks smaller, so is made physically larger)
        // We use base stoneRadius for Black.
        blackStoneGeometry = SCNSphere(radius: stoneRadius)
        let bM = blackMaterial ?? SCNMaterial()
        bM.lightingModel = .physicallyBased
        bM.diffuse.contents = NSColor(white: 0.02, alpha: 1.0) // Deep Black
        bM.metalness.contents = 0.0
        bM.roughness.contents = blackRoughness
        bM.emission.contents = NSColor.black 
        blackStoneGeometry?.materials = [bM]
        self.blackMaterial = bM
        
        let wM = whiteMaterial ?? SCNMaterial()
        wM.lightingModel = .physicallyBased
        wM.diffuse.contents = NSColor(white: 1.0, alpha: 1.0) // Natural White
        wM.metalness.contents = 0.0
        wM.roughness.contents = whiteRoughness
        wM.emission.contents = NSColor(white: currentEnvironment == .cave ? 0 : currentEnvironment == .mountainSummit ? 0.02 : stoneAmbientIntensity * 0.3, alpha: 1.0)
        wM.clearCoat.contents = whiteClearCoat
        wM.clearCoatRoughness.contents = whiteClearCoatRoughness
        self.whiteMaterial = wM
        
        // WHITE STONE: slightly smaller (approx 98% of Black) to compensate for irradiation illusion
        let whiteRadius = stoneRadius * 0.98
        
        for _ in 0..<5 {
            let g = SCNSphere(radius: whiteRadius)
            g.materials = [wM]
            clamGeometries.append(g)
        }
        if optimizesCameraArrival {
            for geometry in [blackStoneGeometry].compactMap({ $0 }) + clamGeometries {
                guard let sphere = geometry as? SCNSphere else { continue }
                // Coverage includes the bounding sphere: retain the original mesh
                // before the stone grows large enough to expose polygon edges.
                geometry.levelsOfDetail = [(16, CGFloat(14)), (10, CGFloat(7))].map { segments, pixels in
                    let simpler = SCNSphere(radius: sphere.radius)
                    simpler.segmentCount = segments
                    simpler.materials = geometry.materials
                    return SCNLevelOfDetail(geometry: simpler, screenSpaceRadius: pixels)
                }
            }
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
    func updateStones(from cache: [RenderStone], lastMove: BoardPosition?, moveIndex: Int, settings: AppSettings, animate: Bool = true, emphasizeLastMove: Bool = false, settleOnLanding: Bool = false) {
        // A click snapshot belongs only to the next board update, never to a
        // later replay, game switch, or opponent move at the same intersection.
        let placement = pendingGhostPlacement
        pendingGhostPlacement = nil
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
                if !animate || !settleOnLanding || !settings.showDropInAnimation {
                    stopStoneWobble(on: n)
                }
                // A game switch or history jump can replace the color at an occupied point.
                // Swap the whole mesh to preserve color-specific size without mutating shared materials.
                // Retain the carried white stone's shell pattern after landing.
                // A board refresh only replaces its mesh when its color changes.
                if let visual = n.childNode(withName: "board-stone", recursively: false),
                   (visual.geometry === blackStoneGeometry) != (rs.color == .black) {
                    stopStoneWobble(on: n)
                    visual.geometry = geom
                    visual.eulerAngles.y = .init(rs.id.col * rs.id.row)
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
                // Establish the entire starting pose before exposing the node to
                // the scene. Only the explicit placement drop may animate; an
                // inherited transaction must never fly it out from world zero.
                SCNTransaction.begin(); SCNTransaction.disableActions = true
                let anchor = SCNNode()
                let s = StoneVisualNode(); s.geometry = geom; s.scale = SCNVector3(1, stoneScaleY, 1); s.eulerAngles.y = .init(rs.id.col * rs.id.row); s.position = SCNVector3(0, stoneRadius * stoneScaleY, 0)
                let carried = placement.flatMap { $0.point == rs.id && $0.color == rs.color ? $0 : nil }
                if let carried {
                    s.geometry = carried.geometry
                    s.eulerAngles = carried.eulerAngles
                }
                s.name = "board-stone"
                
                s.categoryBitMask = MaskStones
                anchor.addChildNode(s); stoneNodeMap[rs.id] = anchor
                
                if settings.showDropInAnimation && animate {
                    // A click during a glide starts at the visible stone, while
                    // the logical move and landing still use the clicked point.
                    if let carried {
                        var origin = carried.position
                        origin.y -= .init(stoneRadius * stoneScaleY)
                        anchor.position = origin
                    } else {
                        anchor.position = SCNVector3(CGFloat(rs.id.col) * effectiveCellWidth + offX,
                            surfaceY + placementHoverHeight, CGFloat(rs.id.row) * effectiveCellHeight + offZ)
                    }
                    anchor.opacity = targetOpacity
                    stonesContainer.addChildNode(anchor)
                    let drop = SCNAction.move(to: SCNVector3(x, surfaceY, z), duration: currentEnvironment.stoneDropDuration)
                    drop.timingMode = .easeIn
                    anchor.runAction(drop, forKey: "stone-placement-drop") { [weak self] in
                        DispatchQueue.main.async { self?.refreshAIHintVisibility() }
                    }
                    if settleOnLanding {
                        addStoneWobble(to: s, at: rs.id, after: currentEnvironment.stoneDropDuration)
                    }
                } else {
                    anchor.position = SCNVector3(x, surfaceY, z)
                    anchor.opacity = targetOpacity
                    stonesContainer.addChildNode(anchor)
                }
                SCNTransaction.commit()
            }
        }
        
        // Fade only the stone mesh, leaving its explanatory X readable. These
        // are visual estimates and never participate in capture/scoring physics.
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for rs in cache {
            guard let anchor = stoneNodeMap[rs.id],
                  let mesh = anchor.childNode(withName: "board-stone", recursively: false) else { continue }
            let strength = rs.isDead ? 0 : min(1, max(0, rs.predictedDeathStrength))
            mesh.opacity = 1 - 0.65 * strength
            updateLikelyDeadCross(on: anchor, color: rs.color, strength: strength)
        }
        SCNTransaction.commit()

        // Always rebuild markers to respond to settings changes immediately
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animate ? 0.2 : 0
        if let p = previousLastMove, let n = stoneNodeMap[p] { n.childNodes.filter({ $0.name?.contains("MARKER") ?? false }).forEach { $0.removeFromParentNode() } }
        if let c = lastMove, let n = stoneNodeMap[c] { let col = cache.first(where: { $0.id == c })?.color ?? .black; applyMarkers(to: n, color: col, index: moveIndex, settings: settings, forceDot: emphasizeLastMove) }
        previousLastMove = lastMove
        SCNTransaction.commit()
        refreshAIHintVisibility()
    }

    /// A brief, damped rock after contact. Only the mesh tilts: its board anchor,
    /// hit position, natural offset and annotation positions remain fixed.
    private func addStoneWobble(to stone: StoneVisualNode, at point: BoardPosition, after delay: TimeInterval) {
        let restAngles = stone.eulerAngles
        let restOrientation = stone.simdOrientation
        stone.landingRestAngles = restAngles
        let restPosition = stone.position
        let radius = (stone.geometry as? SCNSphere)?.radius ?? stoneRadius
        let flattening = stoneScaleY
        let direction = Float((point.row * 7 + point.col * 11) % 5 - 2) * .pi / 18
        let axis = SIMD3<Float>(cos(direction), 0, sin(direction))
        let duration: TimeInterval = 0.28
        let rock = SCNAction.customAction(duration: duration) { (node: SCNNode, elapsed: CGFloat) in
            let t: CGFloat = min(1, elapsed / CGFloat(duration))
            // One small tilt, a weaker return, then an almost imperceptible settle.
            let decay: CGFloat = (1 - t) * (1 - t)
            let wave: CGFloat = sin(3 * CGFloat.pi * t)
            let angle: CGFloat = (CGFloat.pi / 22.5) * wave * decay
            // Apply a board-space tilt before the stone's shell orientation.
            // Euler pitch/roll could cancel each other at some shell rotations.
            node.simdOrientation = simd_quatf(angle: Float(angle), axis: axis) * restOrientation
            // Preserve contact for the tilted flattened sphere; this minute
            // height correction prevents clipping, rather than adding a bounce.
            let up = node.simdOrientation.act(SIMD3<Float>(0, 1, 0))
            let cosTilt = CGFloat(up.y)
            let supportSquared: CGFloat = 1 - (1 - flattening * flattening) * cosTilt * cosTilt
            let support: CGFloat = radius * sqrt(max(0, supportSquared))
            var position = restPosition
            position.y += .init(max(0, support - radius * flattening))
            node.position = position
        }
        let reset = SCNAction.run { node in
            node.eulerAngles = restAngles
            node.position = restPosition
            (node as? StoneVisualNode)?.landingRestAngles = nil
        }
        stone.runAction(.sequence([.wait(duration: delay), rock, reset]), forKey: Self.stoneWobbleKey) { [weak self] in
            DispatchQueue.main.async { self?.refreshAIHintVisibility() }
        }
    }

    private func stopStoneWobble(on anchor: SCNNode) {
        guard let stone = anchor.childNode(withName: "board-stone", recursively: false) as? StoneVisualNode,
              stone.action(forKey: Self.stoneWobbleKey) != nil else { return }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        stone.removeAction(forKey: Self.stoneWobbleKey)
        stone.eulerAngles = stone.landingRestAngles ?? SCNVector3Zero
        stone.landingRestAngles = nil
        stone.position = SCNVector3(0, stoneRadius * stoneScaleY, 0)
        SCNTransaction.commit()
    }

    private func updateLikelyDeadCross(on anchor: SCNNode, color: Stone, strength: Double) {
        let existing = anchor.childNode(withName: "ai-likely-dead-cross", recursively: false)
        guard strength > 0 else { existing?.removeFromParentNode(); return }
        let cross = existing ?? SCNNode()
        if existing == nil {
            cross.name = "ai-likely-dead-cross"
            cross.castsShadow = false
            for angle in [-CGFloat.pi / 4, CGFloat.pi / 4] {
                let leg = SCNNode(geometry: SCNBox(width: 1, height: 0.01, length: 0.13, chamferRadius: 0))
                let material = SCNMaterial(); material.lightingModel = .constant
                leg.geometry?.materials = [material]
                leg.eulerAngles.y = .init(angle); leg.castsShadow = false
                cross.addChildNode(leg)
            }
            anchor.addChildNode(cross)
        }
        for leg in cross.childNodes {
            leg.geometry?.firstMaterial?.diffuse.contents = color == .black ? NSColor.white : NSColor.black
        }
        cross.position.y = .init(stoneRadius * stoneScaleY * 2 + 0.035)
        let span = stoneRadius * (0.5 + 0.6 * strength)
        cross.scale = SCNVector3(span, 1, span)
        cross.opacity = 0.3 + 0.7 * strength
    }

    func updateOwnershipOverlay(_ estimates: [BoardPosition: AIOwnershipEstimate]) {
        guard estimates != displayedOwnership || ownershipBoardSize != boardSize else { return }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        ownershipNodes.forEach { $0.removeFromParentNode() }; ownershipNodes.removeAll()
        displayedOwnership = estimates; ownershipBoardSize = boardSize
        guard let texture = AIOwnershipTexture.image(estimates: estimates, size: boardSize) else { return }
        let plane = SCNPlane(width: CGFloat(boardSize) * effectiveCellWidth,
                             height: CGFloat(boardSize) * effectiveCellHeight)
        let material = SCNMaterial()
        // Receive the same lighting and cast stone shadows as the wooden board.
        // The previous constant material washed shadows out with unlit white ink.
        material.lightingModel = .lambert
        material.diffuse.contents = texture
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.diffuse.wrapS = .clamp; material.diffuse.wrapT = .clamp
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.name = "ai-ownership-region"
        node.categoryBitMask = MaskBoard
        node.position.y = .init(boardThickness / 2 + 0.004)
        node.eulerAngles.x = -.pi / 2
        node.castsShadow = false
        worldAnchor.addChildNode(node); ownershipNodes.append(node)
    }
    
    /// Saved branches rest on the board; the floating ghost remains for new moves.
    func updateReviewVariations(_ choices: [ReviewTree.BoardVariation]) {
        guard choices != reviewVariations else { return }
        reviewVariationNodes.forEach { $0.removeFromParentNode() }
        reviewVariationNodes.removeAll()
        reviewVariations = choices
        for choice in choices {
            let point = choice.position
            let anchor = SCNNode()
            anchor.name = "review-variation-\(choice.id)"
            anchor.position = SCNVector3(
                (CGFloat(point.col) - CGFloat(boardSize - 1) / 2) * effectiveCellWidth,
                boardThickness / 2,
                (CGFloat(point.row) - CGFloat(boardSize - 1) / 2) * effectiveCellHeight)
            let stone = SCNNode(geometry: choice.color == .black ? blackStoneGeometry : clamGeometries[(point.row * 19 + point.col) % 5])
            stone.name = "review-variation-stone"
            stone.scale = SCNVector3(1, stoneScaleY, 1)
            stone.position.y = .init(stoneRadius * stoneScaleY)
            stone.eulerAngles.y = .init(point.col * point.row)
            stone.categoryBitMask = MaskStones
            stone.castsShadow = false
            stone.opacity = 0.45
            anchor.addChildNode(stone)

            stonesContainer.addChildNode(anchor)
            reviewVariationNodes.append(anchor)
        }
        updateBoardCursorIndicator()
    }

    /// Number the hypothetical continuation on the stone anchors, so labels track
    /// board rotation and scale without changing the real game's move markers.
    func updateVariationNumbers(frame: AIVariationFrame?) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        SCNTransaction.animationDuration = 0
        defer { SCNTransaction.commit() }
        for (point, node) in stoneNodeMap where frame?.numbers[point] == nil {
            node.childNode(withName: "ai-variation-number", recursively: false)?.removeFromParentNode()
        }
        guard let frame else { return }
        for (point, number) in frame.numbers {
            guard let anchor = stoneNodeMap[point], let color = frame.stones[point] else { continue }
            let ink = color == .black ? NSColor.white : NSColor.black
            if let existing = anchor.childNode(withName: "ai-variation-number", recursively: false) {
                if let text = existing.geometry as? SCNText, text.string as? String == String(number),
                   let currentInk = text.firstMaterial?.diffuse.contents as? NSColor,
                   currentInk.isEqual(ink) {
                    continue
                }
                existing.removeFromParentNode()
            }
            let text = SCNText(string: String(number), extrusionDepth: 0)
            text.font = NSFont.boldSystemFont(ofSize: effectiveCellWidth * 0.48)
            text.flatness = 0.01
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = ink
            text.materials = [material]
            let label = SCNNode(geometry: text)
            label.name = "ai-variation-number"
            label.eulerAngles.x = -.pi / 2
            let (low, high) = text.boundingBox
            label.pivot = SCNMatrix4MakeTranslation(.init(CGFloat((low.x + high.x) / 2)), .init(CGFloat((low.y + high.y) / 2)), .init(0))
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
                NSColor(MoveLossPalette.color(pointsLost: marker.pointsLost)).setStroke()
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

    private var selectedFeedback: SelectedMoveFeedback?
    private var selectedFeedbackPosition: BoardPosition?
    func updateSelectedMoveFeedback(_ feedback: SelectedMoveFeedback?, at position: BoardPosition?) {
        if feedback == selectedFeedback, position == selectedFeedbackPosition,
           let position, stoneNodeMap[position]?.childNode(withName: "ai-selected-feedback", recursively: false) != nil { return }
        selectedFeedback = feedback; selectedFeedbackPosition = position
        for anchor in stoneNodeMap.values {
            anchor.childNode(withName: "ai-selected-feedback", recursively: false)?.removeFromParentNode()
        }
        guard let feedback, feedback.hasStone, let position, let anchor = stoneNodeMap[position],
              let loss = feedback.stoneLossText, let chance = feedback.stoneChanceText else { return }
        let image = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { _ in
            for (text, centerY) in [(chance, CGFloat(196)), (loss, CGFloat(60))] {
                var font = NSFont.boldSystemFont(ofSize: 54)
                while (text as NSString).size(withAttributes: [.font: font]).width > 246 && font.pointSize > 22 {
                    font = NSFont.boldSystemFont(ofSize: font.pointSize - 1)
                }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: feedback.player == .black ? NSColor.white : NSColor.black,
                    .strokeColor: feedback.player == .black ? NSColor.black : NSColor.white, .strokeWidth: -3.5]
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: CGPoint(x: (256 - size.width) / 2, y: centerY - size.height / 2), withAttributes: attributes)
            }
            return true
        }
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = image; material.writesToDepthBuffer = false
        // This is an annotation, not part of the stone surface. Its text must not
        // disappear into the curved mesh when the camera is tilted.
        material.readsFromDepthBuffer = false
        let plane = SCNPlane(width: effectiveCellWidth * 1.1, height: effectiveCellWidth * 1.1)
        plane.materials = [material]
        let node = SCNNode(geometry: plane); node.name = "ai-selected-feedback"
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, stoneRadius * stoneScaleY * 2 + 0.035, 0)
        node.castsShadow = false; node.renderingOrder = 101
        anchor.addChildNode(node)
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
    
    private func refreshAIHintVisibility() {
        let placing = stoneNodeMap.values.contains {
            $0.action(forKey: "stone-placement-drop") != nil ||
            $0.childNode(withName: "board-stone", recursively: false)?.action(forKey: Self.stoneWobbleKey) != nil
        }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        aiHintNodes.forEach { $0.isHidden = placing }
        SCNTransaction.commit()
    }

    func updateAIHints(moves: [AIMoveInfo], isAvailable: Bool, root: AIRootInfo?, nextMove: BoardPosition?, playedColor: Stone? = nil) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        SCNTransaction.animationDuration = 0
        
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
        
        // The caller includes the historical move with its measured before/after cost.
        let sorted = moves

        let best = AIMovePresentation.ranked(sorted.filter { $0.visits > 0 }).first
        guard let fallback = best ?? sorted.first else { SCNTransaction.commit(); return }
        
        let rootWinrate = root?.winrate ?? fallback.winrate
        let rootScore = root?.scoreLead ?? fallback.scoreLead
        
        for move in sorted {
            if let pos = parseGTPCoord(move.move, size: boardSize),
               !reviewVariations.contains(where: { $0.position == pos }) {
                let x = CGFloat(pos.col) * effectiveCellWidth + offX
                let z = CGFloat(pos.row) * effectiveCellHeight + offZ
                
                // Cylinder for AI Hint
                let hintRad = stoneRadius * 0.8
                let cyl = SCNCylinder(radius: hintRad, height: 0.005)
                
                // Diff calculating relative to ROOT evaluation, not absolute best
                let isNextPlayed = (pos == nextMove)
                // HistoricalMoveHints supplies the played move's measured point loss.
                let lossColor = MoveLossPalette.sample(pointsLost: rootScore - move.scoreLead)
                let color = NSColor(lossColor.color)
                
                let mat = SCNMaterial()
                // Color encodes a numeric value: wood grain, grid lines and room
                // lighting must not change its hue or the contrast of its labels.
                mat.lightingModel = .constant
                mat.diffuse.contents = color.withAlphaComponent(1)
                cyl.materials = [mat]
                
                let n = SCNNode(geometry: cyl)
                n.position = SCNVector3(x, tY, z)
                n.name = "AI_HINT"
                n.categoryBitMask = MaskBoard // Expose this Node to the Ambient+Sun lighting arrays
                
                // Highlighting Rings
                let isBestMove = move.move == best?.move

                if isNextPlayed {
                    let ring = SCNTorus(ringRadius: hintRad * 0.97, pipeRadius: hintRad * 0.025)
                    let material = SCNMaterial()
                    material.lightingModel = .constant
                    material.diffuse.contents = color.blended(withFraction: 0.25, of: .black) ?? color
                    ring.materials = [material]
                    let node = SCNNode(geometry: ring)
                    node.name = "historical-move-inner-ring"
                    node.position.y = 0.008
                    n.addChildNode(node)
                }
                
                if isBestMove {
                    let ring = SCNTorus(ringRadius: hintRad * 0.84, pipeRadius: hintRad * 0.12)
                    let material = SCNMaterial(); material.diffuse.contents = NSColor.blue
                    material.lightingModel = .constant
                    ring.materials = [material]
                    let node = SCNNode(geometry: ring); node.position.y = 0.008
                    node.name = "ai-best-move-ring"
                    n.addChildNode(node)
                }
                if isNextPlayed {
                    for index in 0..<12 {
                        let angle = CGFloat(index) * .pi * 2 / 12
                        let dash = SCNBox(width: hintRad * 0.37, height: 0.012, length: hintRad * 0.11, chamferRadius: 0)
                        let material = SCNMaterial()
                        material.lightingModel = .constant
                        material.diffuse.contents = playedColor == .white ? NSColor.white : NSColor.black
                        dash.materials = [material]
                        let node = SCNNode(geometry: dash)
                        node.name = "historical-move-dash"
                        node.position = SCNVector3(sin(angle) * hintRad * 1.14, 0.012, cos(angle) * hintRad * 1.14)
                        node.eulerAngles.y = .init(angle)
                        n.addChildNode(node)
                    }
                }

                // Add Text (Delta % and Points)
                let deltaWin = (move.winrate - rootWinrate) * 100
                let deltaPt = move.scoreLead - rootScore
                
                let winStr = deltaWin > 0 ? String(format: "+%.1f%%", deltaWin) : String(format: "%.1f%%", deltaWin)
                let ptStr = deltaPt > 0 ? String(format: "+%.1f", deltaPt) : String(format: "%.1f", deltaPt)
                
                let tMat = SCNMaterial()
                tMat.lightingModel = .constant
                // White ink keeps red/purple badges readable in every environment.
                tMat.diffuse.contents = NSColor(lossColor.labelColor)
                
                // Winrate String Node
                let tWin = SCNText(string: winStr, extrusionDepth: 0.01)
                tWin.font = NSFont.boldSystemFont(ofSize: 0.5)
                tWin.alignmentMode = CATextLayerAlignmentMode.center.rawValue
                tWin.flatness = 0.01 // Smooth curves
                tWin.materials = [tMat]
                
                let tnWin = SCNNode(geometry: tWin)
                let (minW, maxW) = tWin.boundingBox
                tnWin.pivot = SCNMatrix4MakeTranslation(.init(CGFloat((maxW.x - minW.x)/2.0 + minW.x)), .init(CGFloat((maxW.y - minW.y)/2.0 + minW.y)), .init(0))
                tnWin.eulerAngles.x = -.pi / 2
                tnWin.position = SCNVector3(0, 0.02, -hintRad * 0.4) // Offset z backwards explicitly
                let winScale = isNextPlayed ? min(hintRad * 1.5, hintRad * 1.76 / max(CGFloat(maxW.x - minW.x), 0.001)) : hintRad * 1.5
                tnWin.scale = SCNVector3(winScale, winScale, winScale)
                n.addChildNode(tnWin)
                
                // Point String Node
                let tPt = SCNText(string: ptStr, extrusionDepth: 0.01)
                tPt.font = NSFont.boldSystemFont(ofSize: 0.5)
                tPt.alignmentMode = CATextLayerAlignmentMode.center.rawValue
                tPt.flatness = 0.01 // Smooth curves
                tPt.materials = [tMat]
                
                let tnPt = SCNNode(geometry: tPt)
                let (minP, maxP) = tPt.boundingBox
                tnPt.pivot = SCNMatrix4MakeTranslation(.init(CGFloat((maxP.x - minP.x)/2.0 + minP.x)), .init(CGFloat((maxP.y - minP.y)/2.0 + minP.y)), .init(0))
                tnPt.eulerAngles.x = -.pi / 2
                tnPt.position = SCNVector3(0, 0.02, hintRad * 0.4) // Offset z forwards explicitly
                let ptScale = isNextPlayed ? min(hintRad * 1.5, hintRad * 1.76 / max(CGFloat(maxP.x - minP.x), 0.001)) : hintRad * 1.5
                tnPt.scale = SCNVector3(ptScale, ptScale, ptScale)
                n.addChildNode(tnPt)
                
                // Analysis labels are annotations, not physical objects that
                // should cast changing number-shaped shadows onto moving stones.
                n.castsShadow = false
                n.enumerateChildNodes { child, _ in child.castsShadow = false }
                worldAnchor.addChildNode(n)
                aiHintNodes.append(n)
            }
        }
        
        refreshAIHintVisibility()
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

    private func applyMarkers(to group: SCNNode, color: Stone, index: Int, settings: AppSettings, forceDot: Bool) {
        let apex = (stoneRadius * stoneScaleY * 2.0) + 0.01; let tc = color == .black ? NSColor.white : NSColor.black
        if settings.showLastMoveDot || forceDot { let d = SCNNode(geometry: SCNSphere(radius: stoneRadius * 0.12)); d.geometry?.firstMaterial = markerMaterial; d.name = "MARKER_DOT"; d.position = SCNVector3(0, apex + 0.02, 0); group.addChildNode(d) }
        if settings.showLastMoveCircle { let r = SCNNode(geometry: SCNTorus(ringRadius: stoneRadius * 0.6, pipeRadius: 0.025)); r.geometry?.firstMaterial = markerMaterial; r.name = "MARKER_CIRCLE"; r.position = SCNVector3(0, apex, 0); group.addChildNode(r) }
        if settings.showMoveNumbers && !forceDot {
            let t = SCNText(string: "\(index)", extrusionDepth: 0.1); t.font = NSFont.boldSystemFont(ofSize: 0.45); t.flatness = 0.01; t.materials = [SCNMaterial()]; t.materials[0].diffuse.contents = tc
            let tn = SCNNode(geometry: t); tn.name = "MARKER_NUMBER"; tn.eulerAngles.x = -.pi/2
            let (min, max) = t.boundingBox; tn.pivot = SCNMatrix4MakeTranslation(.init(CGFloat((max.x - min.x)/2.0 + min.x)), .init(CGFloat((max.y - min.y)/2.0 + min.y)), .init(0))
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
        // Board, analysis and preference updates must not overwrite the flight.
        guard !isCameraArriving else { return }
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
        let previous = cameraNode.simdPosition
        var pose = simd_inverse(viewTransform.simdTransform) * baseCamera.simdTransform
        // Aim through the visual midpoint of the wooden playing surface. Aiming
        // at world zero leaves the raised, foreshortened board below the lens axis.
        // Calculate without pan so a deliberate user pan remains a real offset.
        viewTransform.position = SCNVector3Zero
        let unpanned = simd_inverse(viewTransform.simdTransform) * baseCamera.simdTransform
        let inverse = simd_inverse(unpanned)
        let halfX = Float(CGFloat(boardSize + 1) * effectiveCellWidth / 2)
        let halfZ = Float(CGFloat(boardSize + 1) * effectiveCellHeight / 2)
        let corners = [SIMD4<Float>(-halfX,1,-halfZ,1), SIMD4<Float>(halfX,1,-halfZ,1),
                       SIMD4<Float>(-halfX,1,halfZ,1), SIMD4<Float>(halfX,1,halfZ,1)].map { inverse * $0 }
        if corners.allSatisfy({ $0.z < -0.1 }) {
            let angles = corners.map { atan2($0.y, -$0.z) }
            let pitch = (angles.min()! + angles.max()!) / 2
            pose = pose * simd_float4x4(simd_quatf(angle: pitch, axis: SIMD3(1,0,0)))
        }
        cameraNode.simdTransform = pose
        keepCameraOutsideBoard(from: previous)
        shoji.updateVisibility(cameraPosition: cameraNode.worldPosition)
        environments[currentEnvironment]?.updateVisibility(camera: cameraNode.worldPosition)
        SCNTransaction.commit()
    }

    /// A padded slab volume protects both the eye and near clipping plane.
    /// Sweeping manual movement also prevents a large pan/zoom from tunnelling
    /// right through the wood and emerging on its opposite side.
    private func keepCameraOutsideBoard(from previous: SIMD3<Float>? = nil) {
        let half = SIMD3<Float>(Float(CGFloat(boardSize + 1) * effectiveCellWidth / 2), 0,
                               Float(CGFloat(boardSize + 1) * effectiveCellHeight / 2))
        let thickness: Float = currentEnvironment.usesTableBoard ? 2.4 : Float(KayaFloorBoard.slabThickness)
        cameraNode.simdPosition = Self.safeCameraPosition(cameraNode.simdPosition, from: previous,
            minimum: SIMD3(-half.x, 1 - thickness, -half.z), maximum: SIMD3(half.x, 1, half.z))
    }

    static func safeCameraPosition(_ proposed: SIMD3<Float>, from previous: SIMD3<Float>?,
                                   minimum: SIMD3<Float>, maximum: SIMD3<Float>) -> SIMD3<Float> {
        let padding: Float = 1.2
        let low = minimum - SIMD3(repeating: padding), high = maximum + SIMD3(repeating: padding)
        var point = proposed
        point.y = max(0.5, point.y)
        func inside(_ p: SIMD3<Float>) -> Bool { (0..<3).allSatisfy { p[$0] > low[$0] && p[$0] < high[$0] } }
        if let start = previous, !inside(start) {
            let delta = point - start
            var entry: Float = 0, exit: Float = 1, intersects = true
            for axis in 0..<3 {
                if abs(delta[axis]) < 0.00001 {
                    if start[axis] <= low[axis] || start[axis] >= high[axis] { intersects = false }
                } else {
                    let a = (low[axis] - start[axis]) / delta[axis], b = (high[axis] - start[axis]) / delta[axis]
                    entry = max(entry, min(a,b)); exit = min(exit, max(a,b))
                }
            }
            if intersects && entry < exit && entry >= 0 && entry < 1 {
                point = start + delta * max(0, entry - 0.0001)
            }
        }
        if inside(point) {
            // Recover invalid saved poses through the nearest exposed face.
            let distances = [point.x-low.x, high.x-point.x, high.y-point.y, point.z-low.z, high.z-point.z]
            switch distances.enumerated().min(by: { $0.element < $1.element })!.offset {
            case 0: point.x = low.x
            case 1: point.x = high.x
            case 2: point.y = high.y
            case 3: point.z = low.z
            default: point.z = high.z
            }
        }
        return point
    }

    /// Called once on entering 3D, after installing the final playing pose.
    /// A main-run-loop clock keeps input, scene updates and cancellation serialized.
    func beginCameraArrival(reduceMotion: Bool, renderer: SCNSceneRenderer? = nil) {
        finishCameraArrival()
        guard environmentActive && !reduceMotion else { return }
        arrivalDestination = cameraNode.simdTransform
        arrivalOpening = currentEnvironment.arrivalView
        // Compose the landscape with a level horizon, independently of the
        // camera's previous roll. Repeated look(at:) calls carry the current
        // up direction forward and can accumulate a roll that snaps at handoff.
        let openingCamera = SCNNode()
        openingCamera.simdPosition = arrivalOpening.eye
        openingCamera.look(at: SCNVector3(arrivalOpening.gaze),
            up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        arrivalOpeningOrientation = openingCamera.simdOrientation
        if optimizesCameraArrival {
            beginArrivalPreparation(renderer: renderer)
        }
        startCameraClock()
    }

    private func beginArrivalPreparation(renderer: SCNSceneRenderer?) {
        arrivalReleasedAt = nil
        arrivalResourcesPrepared = renderer == nil
        let id = UUID()
        arrivalPreparationID = id
        // Captures may continue settling, but do not delay the camera for them.
        cameraNode.isPreparingOrArriving = true
        if let view = renderer as? SCNView {
            arrivalView = view
            arrivalViewPlayback = (view.isPlaying, view.rendersContinuously)
            view.isPlaying = true
            view.rendersContinuously = true
        }
        renderer?.prepare([scene]) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.arrivalPreparationID == id else { return }
                // Failure still releases the gate; normal rendering can load lazily.
                self.arrivalResourcesPrepared = true
            }
        }
        scene.rootNode.enumerateChildNodes { [self] node, _ in
            guard let light = node.light, light.castsShadow, light.shadowSampleCount > 4 else { return }
            arrivalShadowSamples.append((light, light.shadowSampleCount))
            light.shadowSampleCount = 4
        }
    }

    private func restoreArrivalShadows() {
        for (light, samples) in arrivalShadowSamples { light.shadowSampleCount = samples }
        arrivalShadowSamples.removeAll()
    }

    /// Return from the actual orbit/pan/zoom position, without visiting the
    /// establishing view. Spherical travel takes the camera around the board
    /// instead of cutting through it when the user has orbited to the far side.
    func beginCameraRecenter(distance: CGFloat, rotationX: Float, reduceMotion: Bool) {
        let start = cameraNode.simdTransform
        let lensScale = tan((cameraNode.camera?.fieldOfView ?? playingFieldOfView) * .pi / 360)
            / tan(playingFieldOfView * .pi / 360)
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        finishCameraArrival()
        updateCameraPosition(distance: distance, rotationX: rotationX, rotationY: 0, panX: 0, panY: 0)
        if environmentActive && !reduceMotion && start != cameraNode.simdTransform {
            arrivalDestination = cameraNode.simdTransform
            recenterStart = start
            recenterOpeningScale = lensScale
            startCameraClock()
        }
        SCNTransaction.commit()
    }

    private func startCameraClock() {
        arrivalStartedAt = CACurrentMediaTime()
        updateCameraArrival(elapsed: 0)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.updateCameraArrival(elapsed: CACurrentMediaTime() - self.arrivalStartedAt)
        }
        timer.tolerance = 0.002
        arrivalTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Kept separate from the clock so rendered frames and interruption can be
    /// checked deterministically. The quintic easing has zero speed/acceleration
    /// at both ends; the curved path stays level initially, then gently descends.
    func updateCameraArrival(elapsed: TimeInterval) {
        guard let destination = arrivalDestination else { return }
        var elapsed = elapsed
        if arrivalPreparationID != nil && recenterStart == nil {
            if arrivalReleasedAt == nil {
                if elapsed >= Self.cameraArrivalHoldDuration &&
                    (arrivalResourcesPrepared || elapsed >= Self.cameraArrivalMaximumHold) {
                    arrivalReleasedAt = elapsed
                }
            }
            // Keep the one-second opening, allowing at most half a second more
            // for graphics preparation. The camera path and speed stay intact.
            elapsed = arrivalReleasedAt.map { elapsed - $0 + Self.cameraArrivalHoldDuration } ?? 0
        }
        let duration = recenterStart == nil ? Self.cameraArrivalDuration : Self.cameraRecenterDuration
        // Hold only the establishing view; returning to the board starts immediately.
        let hold = recenterStart == nil ? Self.cameraArrivalHoldDuration : 0
        guard elapsed < hold + duration else { finishCameraArrival(); return }
        let t = Float(max(0, elapsed - hold) / duration)
        let u = max(0, min(1, t * t * t * (t * (t * 6 - 15) + 10)))
        if let start = recenterStart {
            let from = SIMD3(start.columns.3.x, start.columns.3.y, start.columns.3.z)
            let to = SIMD3(destination.columns.3.x, destination.columns.3.y, destination.columns.3.z)
            let fromRadius = max(0.001, simd_length(from)), toRadius = max(0.001, simd_length(to))
            let turn = simd_quatf(from: from / fromRadius, to: to / toRadius)
            let direction = simd_slerp(simd_quatf(real: 1, imag: .zero), turn, u).act(from / fromRadius)
            SCNTransaction.begin(); SCNTransaction.disableActions = true
            arrivalProgress = CGFloat(u)
            applyCameraFieldOfView()
            if t == 0 {
                cameraNode.simdTransform = start
            } else {
                cameraNode.simdPosition = direction * ((1 - u) * fromRadius + u * toRadius)
                cameraNode.simdOrientation = simd_slerp(simd_quatf(start), simd_quatf(destination), u)
            }
            keepCameraOutsideBoard()
            shoji.updateVisibility(cameraPosition: cameraNode.worldPosition)
            environments[currentEnvironment]?.updateVisibility(camera: cameraNode.worldPosition)
            SCNTransaction.commit()
            return
        }
        let travelTime = max(0, elapsed - hold)
        let surveying = travelTime < Self.cameraArrivalSurveyDuration
        let stageTime = surveying ? travelTime / Self.cameraArrivalSurveyDuration
            : (travelTime - Self.cameraArrivalSurveyDuration) / (Self.cameraArrivalDuration - Self.cameraArrivalSurveyDuration)
        let stage = Float(max(0,min(1,stageTime)))
        let ease = stage*stage*stage*(stage*(stage*6-15)+10)
        // Restore once, early in the descent (only 6% along its eased path).
        // Keep map size and antialiasing unchanged to avoid buffer reallocation.
        if !surveying && stage >= 0.2 { restoreArrivalShadows() }
        let angle = currentEnvironment.arrivalSurveyAngle
        let surveyTurn = simd_quatf(angle:angle,axis:SIMD3(0,1,0))
        let surveyEye = surveyTurn.act(arrivalOpening.eye)
        let surveyOrientation = surveyTurn * arrivalOpeningOrientation
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        if surveying {
            // Keep the wide lens and altitude while slowly orbiting the setting.
            let turn = simd_quatf(angle:angle*ease,axis:SIMD3(0,1,0))
            cameraNode.simdPosition = turn.act(arrivalOpening.eye)
            cameraNode.simdOrientation = turn * arrivalOpeningOrientation
            arrivalProgress = 0
        } else {
            let start = surveyEye
            let end = SIMD3(destination.columns.3.x,destination.columns.3.y,destination.columns.3.z)
            let control1 = start + SIMD3<Float>((end.x-start.x)*0.25,0,(end.z-start.z)*0.25)
            let control2 = end + SIMD3<Float>(0,(start.y-end.y)*0.30,(start.z-end.z)*0.20)
            let v = 1-ease
            cameraNode.simdPosition = v*v*v*start+3*v*v*ease*control1+3*v*ease*ease*control2+ease*ease*ease*end
            cameraNode.simdOrientation = simd_slerp(surveyOrientation,simd_quatf(destination),ease)
            arrivalProgress = CGFloat(ease)
        }
        applyCameraFieldOfView()
        keepCameraOutsideBoard()
        shoji.updateVisibility(cameraPosition: cameraNode.worldPosition)
        environments[currentEnvironment]?.updateVisibility(camera: cameraNode.worldPosition)
        SCNTransaction.commit()
    }

    /// Returns whether an arrival was consumed, allowing the initiating click
    /// to be swallowed instead of passing through to a stone or another control.
    @discardableResult func finishCameraArrival() -> Bool {
        arrivalTimer?.invalidate(); arrivalTimer = nil
        arrivalPreparationID = nil
        arrivalReleasedAt = nil
        restoreArrivalShadows()
        cameraNode.isPreparingOrArriving = false
        if let view = arrivalView, let playback = arrivalViewPlayback {
            view.isPlaying = playback.playing
            view.rendersContinuously = playback.continuous
            // Environment motion may have been toggled during the tour.
            (view as? CameraArrivalPlayback)?.updateEnvironmentPlayback()
        }
        arrivalView = nil
        arrivalViewPlayback = nil
        guard let destination = arrivalDestination else { return false }
        arrivalDestination = nil
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        arrivalProgress = 1
        applyCameraFieldOfView()
        cameraNode.simdTransform = destination
        recenterStart = nil
        shoji.updateVisibility(cameraPosition: cameraNode.worldPosition)
        environments[currentEnvironment]?.updateVisibility(camera: cameraNode.worldPosition)
        SCNTransaction.commit()
        return true
    }
    /// Counts are by capturing player. White's upper lid holds black stones, and vice versa.
    private var captureSeed: UInt64 = 0
    func updateCapturedStones(black: Int, white: Int, seed: UInt64? = nil) {
        let changed = upperLidStones.count != max(0, white) || lowerLidStones.count != max(0, black)
            || seed.map { $0 != captureSeed } == true
        if let seed, captureSeed != seed {
            captureSeed = seed
            (upperLidStones + lowerLidStones).forEach { $0.removeFromParentNode() }
            upperLidStones.removeAll(); lowerLidStones.removeAll()
        }
        guard let upper = upperLidNode, let lower = lowerLidNode else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        updateLidDiff(lid: upper, current: &upperLidStones, target: max(0, white), isWhite: false)
        updateLidDiff(lid: lower, current: &lowerLidStones, target: max(0, black), isWhite: true)
        if changed { monitorCaptureRest() }
        SCNTransaction.commit()
    }

    /// Tiny contact jitter can keep Bullet's collision islands awake indefinitely.
    /// Put bodies to sleep only after their rendered pose has stayed still for a
    /// full second. New collisions wake them normally; capture changes restart
    /// this monitor. Nothing runs after the complete pile is asleep.
    private func monitorCaptureRest() {
        var previous: [ObjectIdentifier: simd_float4x4] = [:]
        var quietSamples = 0
        let key = "capture-rest-monitor"
        worldAnchor.runAction(.repeatForever(.sequence([.wait(duration: 0.2), .run { root in
            var bodies: [SCNPhysicsBody] = []
            var stable = true
            root.enumerateChildNodes { node, _ in
                guard node.name == "captured-black" || node.name == "captured-white",
                      let body = node.physicsBody else { return }
                bodies.append(body)
                let id = ObjectIdentifier(node), pose = node.presentation.simdTransform
                if let last = previous[id] {
                    // Disc spin around its own normal does not change support.
                    stable = stable && simd_length(pose.columns.3 - last.columns.3) < 0.025
                        && simd_length(pose.columns.1 - last.columns.1) < 0.06
                } else { stable = false }
                previous[id] = pose
            }
            quietSamples = stable ? quietSamples + 1 : 0
            // Sleep the entire contact island together: one awake stone would
            // immediately wake its neighbours if we slept them individually.
            if quietSamples >= 5 || bodies.allSatisfy({ $0.isResting }) {
                bodies.forEach { $0.setResting(true) }
                root.removeAction(forKey: key)
            }
        }])), forKey: key)
    }

    // Bake the flattened shape into vertices. A scale on the physics-shape root
    // is not reliable: a full sphere would overlap adjacent vertical drop layers.
    private lazy var blackCaptureShape = makeCapturedStoneCollisionShape(radius: capturedStoneRadius)
    private lazy var whiteCaptureShape = makeCapturedStoneCollisionShape(radius: capturedStoneRadius * 0.98)

    private func makeCapturedStoneCollisionShape(radius: CGFloat) -> SCNPhysicsShape {
        // Collision proxies need far fewer vertices than the visible stones.
        let rings = 8, segments = 16
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        for ring in 0...rings {
            let latitude = Double(ring) * Double.pi / Double(rings)
            for segment in 0..<segments {
                let longitude = Double(segment) * 2 * Double.pi / Double(segments)
                vertices.append(SCNVector3(Double(radius) * sin(latitude) * cos(longitude),
                    Double(radius * stoneScaleY) * cos(latitude),
                    Double(radius) * sin(latitude) * sin(longitude)))
                if ring < rings {
                    let a = Int32(ring * segments + segment)
                    let b = Int32(ring * segments + (segment + 1) % segments)
                    let c = a + Int32(segments), d = b + Int32(segments)
                    indices += [a, c, b, b, c, d]
                }
            }
        }
        let mesh = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        return SCNPhysicsShape(geometry: mesh, options: [
            .type: SCNPhysicsShape.ShapeType.convexHull, .collisionMargin: 0.005
        ])
    }

    private func updateLidDiff(lid: SCNNode, current: inout [SCNNode], target: Int, isWhite: Bool) { 
        if current.count == target { return }
        
        if current.count > target { 
            while current.count > target { 
                current.last?.removeFromParentNode()
                current.removeLast()
            }
            // A removed capture may have been supporting a stone that has gone to sleep.
            current.forEach { $0.physicsBody?.applyForce(SCNVector3(0, -0.001, 0), asImpulse: true) }
        } else {
            let start = current.count
            // Start restored piles close to supported positions. Dropping a whole
            // game's captures in tall columns splashes stones over a physical rim.
            var supports: [(position: SCNVector3, halfHeight: CGFloat)] = current.map { node in
                let transform = node.presentation.simdTransform
                let radius = capturedStoneRadius * (isWhite ? 0.98 : 1)
                let halfHeight = sqrt(pow(CGFloat(transform.columns.0.y) * radius, 2)
                    + pow(CGFloat(transform.columns.1.y) * radius * stoneScaleY, 2)
                    + pow(CGFloat(transform.columns.2.y) * radius, 2))
                return (node.presentation.position, halfHeight)
            }
            let arrivalLift: CGFloat = target - start <= 4 ? 0.45 : 0.035
            for i in start..<target {
                let g = isWhite ? clamGeometries[i % 5] : blackStoneGeometry
                let n = SCNNode()
                let visual = SCNNode(geometry: g)
                visual.name = "capture-visual"
                n.addChildNode(visual)
                n.name = isWhite ? "captured-white" : "captured-black"
                
                var random = CaptureRandom(state: CapturePileLayout.lidSeed(game: captureSeed,
                    whiteStones: isWhite) &+ UInt64(i) &* 0x9e3779b97f4a7c15)
                let halfHeight = capturedStoneRadius * stoneScaleY + 0.055
                var best = SCNVector3Zero
                var bestEnergy = CGFloat.greatestFiniteMagnitude
                for _ in 0..<48 {
                    let angle = CGFloat(random.unit()) * 2 * .pi
                    let radius = sqrt(CGFloat(random.unit())) * 2.2
                    let x = cos(angle) * radius, z = sin(angle) * radius
                    // Include the footprint so the outer edge starts above the slope.
                    var y = CaptureLidSurface.interiorHeight(at: radius + capturedStoneRadius) + halfHeight
                    for support in supports {
                        let distance = hypot(x - CGFloat(support.position.x), z - CGFloat(support.position.z))
                        let diameter = capturedStoneRadius * 2 + 0.025
                        if distance < diameter {
                            let separation = (support.halfHeight + halfHeight)
                                * sqrt(1 - pow(distance / diameter, 2))
                            y = max(y, CGFloat(support.position.y) + separation + 0.025)
                        }
                    }
                    let energy = y + CGFloat(random.unit()) * 0.055 + radius * 0.025
                    if energy < bestEnergy {
                        bestEnergy = energy
                        best = SCNVector3(x, y, z)
                    }
                }
                n.position = SCNVector3(best.x, best.y + .init(arrivalLift), best.z)
                supports.append((n.position, halfHeight))
                n.eulerAngles = SCNVector3((random.unit() - 0.5) * 0.16,
                    random.unit() * 2 * .pi, (random.unit() - 0.5) * 0.16)
                let scale = capturedStoneRadius / stoneRadius
                visual.scale = SCNVector3(scale, scale * stoneScaleY, scale)

                // The physics parent stays at unit scale; only its visual child is flattened.
                // This prevents board-size-dependent scaling of the collision shape.
                let shape = isWhite ? whiteCaptureShape : blackCaptureShape
                let body = SCNPhysicsBody(type: .dynamic, shape: shape)
                body.mass = 0.5
                body.restitution = 0.015
                body.friction = 0.55
                body.rollingFriction = 0.08
                body.damping = 0.45
                body.angularDamping = 0.45
                
                body.categoryBitMask = PhysicsCategoryStone
                body.collisionBitMask = PhysicsCategoryStone | PhysicsCategoryBowl
                body.contactTestBitMask = PhysicsCategoryBowl
                n.physicsBody = body
                
                lid.addChildNode(n)
                current.append(n)
                
                // Optional: apply a tiny initial impulse to make the drop feel dynamic
                let impulseScale: CGFloat = currentEnvironment == .spaceStation ? 0.1 : 1
                let impulse = SCNVector3((random.unit() - 0.5) * 0.02 * impulseScale, 0, (random.unit() - 0.5) * 0.02 * impulseScale)
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
        dir.look(at: SCNVector3(x: .init(0), y: .init(0), z: .init(0)))
        worldAnchor.addChildNode(dir)
    }
    
    private func setupBackground() {
        scene.background.contents = Self.backgroundColor
        scene.fogColor = Self.backgroundColor
        scene.fogStartDistance = 110
        scene.fogEndDistance = 290
    }

    private func createTatamiFloor() {
        // Everything remains in board coordinates while the camera moves.
        let floor = SCNNode()
        floor.name = "tatami-environment"
        floor.position.y = .init(KayaFloorBoard.sceneryOffset)
        worldAnchor.addChildNode(floor)
        let unitsPerCentimetre = (20 * 1.0773) / TatamiTexture.boardLengthCentimetres
        let width = 90 * unitsPerCentimetre
        let length = 180 * unitsPerCentimetre
        let border = 2 * unitsPerCentimetre
        let textureSide = TatamiTexture.tileCentimetres * unitsPerCentimetre

        let binding = SCNMaterial()
        binding.lightingModel = .lambert
        binding.diffuse.contents = NSColor(srgbRed: 0.21, green: 0.24, blue: 0.20, alpha: 1)
        let backing = SCNPlane(width: width * 19, height: length * 11)
        backing.materials = [binding]
        let base = SCNNode(geometry: backing)
        base.eulerAngles.x = -.pi / 2
        base.position.y = .init(-boardThickness / 2 - 0.025)
        base.categoryBitMask = MaskBoard
        base.castsShadow = false
        floor.addChildNode(base)

        // A full shallow lid can overflow. Give those stones the same floor that
        // is drawn under the board, rather than letting them fall out of the scene.
        let support = SCNNode()
        support.name = "tatami-collision-surface"
        support.position.y = .init(-boardThickness / 2 - 0.015 - 0.1)
        let slab = SCNBox(width: width * 19, height: 0.2, length: length * 11, chamferRadius: 0)
        support.physicsBody = captureSupportBody(for: slab)
        floor.addChildNode(support)

        let weave = SCNMaterial()
        weave.lightingModel = .lambert
        weave.diffuse.contents = NSImage(named: TatamiTexture.assetName)
            ?? NSColor(srgbRed: 0.54, green: 0.55, blue: 0.36, alpha: 1)
        weave.diffuse.wrapS = .mirror
        weave.diffuse.wrapT = .mirror
        weave.diffuse.contentsTransform = SCNMatrix4MakeScale(.init((width - 2 * border) / textureSide), .init((length - 0.08) / textureSide), .init(1))
        weave.diffuse.magnificationFilter = .linear
        weave.diffuse.minificationFilter = .linear
        weave.diffuse.mipFilter = .linear
        weave.diffuse.maxAnisotropy = 16
        // Crop the room floor at the window; the open-tatami setting retains
        // the full expanse. Geometry clipping preserves the weave's scale.
        let roomFloor=SCNNode(); roomFloor.name="room-tatami"
        let roomBase=SCNNode(geometry:SCNPlane(width:96,height:114))
        roomBase.geometry?.materials=[binding]; roomBase.eulerAngles.x = -.pi/2
        roomBase.position=SCNVector3(0,-1.025,23); roomBase.categoryBitMask=MaskBoard; roomBase.castsShadow=false
        roomFloor.addChildNode(roomBase)
        for row in -1...1 { for column in -2...2 {
            let cx=CGFloat(column)*width, cz=CGFloat(row)*length
            let left=max(-48,cx-(width-2*border)/2), right=min(48,cx+(width-2*border)/2)
            let back=max(-34,cz-(length-0.08)/2), front=min(80,cz+(length-0.08)/2)
            guard right>left && front>back else { continue }
            let material=weave.copy() as! SCNMaterial
            material.diffuse.contentsTransform=SCNMatrix4MakeScale(.init((right-left)/textureSide), .init((front-back)/textureSide), .init(1))
            let g=SCNPlane(width:right-left,height:front-back); g.materials=[material]
            let tile=SCNNode(geometry:g); tile.eulerAngles.x = -.pi/2
            tile.position=SCNVector3((left+right)/2,-1.015,(back+front)/2)
            tile.categoryBitMask=MaskBoard; tile.castsShadow=false; roomFloor.addChildNode(tile)
        }}
        floor.addChildNode(roomFloor)
        let mat = SCNPlane(width: width - 2 * border, height: length - 0.08)
        mat.materials = [weave]
        for row in -5...5 {
            for column in -9...9 {
                let node = SCNNode(geometry: mat)
                node.eulerAngles.x = -.pi / 2
                node.position = SCNVector3(CGFloat(column) * width,
                    -boardThickness / 2 - 0.015, CGFloat(row) * length)
                node.categoryBitMask = MaskBoard
                node.castsShadow = false
                floor.addChildNode(node)
            }
        }
    }
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
 
    private func createBoard() {
        boardNode?.removeFromParentNode()
        let width=CGFloat(boardSize+1)*effectiveCellWidth
        let length=CGFloat(boardSize+1)*effectiveCellHeight
        let thickness: CGFloat = currentEnvironment.usesTableBoard ? 2.4 : KayaFloorBoard.slabThickness
        let geometry=KayaFloorBoard.body(width:width,length:length,thickness:thickness)
        let material=SCNMaterial()
        material.name = currentEnvironment.boardTopAsset
        material.diffuse.contents=EnvironmentMaterials.image(currentEnvironment.boardTopAsset) ?? NSImage(named:"board_kaya") ?? NSColor.brown
        material.lightingModel = currentEnvironment.usesStoneBoard ? .physicallyBased : .lambert
        material.roughness.contents=currentEnvironment.usesStoneBoard ? 0.92 : currentEnvironment.usesAgedBoard ? 0.82 : 0.62
        material.metalness.contents = 0
        material.diffuse.mipFilter = .linear; material.diffuse.maxAnisotropy=8
        let endgrain=material.copy() as! SCNMaterial
        endgrain.name = currentEnvironment.boardEndgrainAsset
        endgrain.diffuse.contents=EnvironmentMaterials.image(currentEnvironment.boardEndgrainAsset) ?? material.diffuse.contents
        endgrain.emission.contents=endgrain.diffuse.contents
        endgrain.emission.intensity=CGFloat(boardAmbientIntensity)
        let sidegrain=material.copy() as! SCNMaterial
        if currentEnvironment.usesStoneBoard {
            sidegrain.name = currentEnvironment.boardEndgrainAsset
            sidegrain.diffuse.contents = endgrain.diffuse.contents
        }
        geometry.materials=[material,material,endgrain,endgrain,sidegrain,sidegrain]
        let board=SCNNode(geometry:geometry); board.name=currentEnvironment.usesTableBoard ? "kaya-table-board" : "kaya-floor-board"
        board.categoryBitMask=MaskBoard
        // Primitive boxes avoid the collision padding SceneKit adds to custom
        // mesh hulls, keeping a dropped stone in contact with the visible top.
        board.physicsBody=captureSupportBody(for:SCNBox(width:width,height:2,length:length,chamferRadius:0))
        let lowerHeight=thickness-2
        let lowerBody=SCNNode(); lowerBody.name="kaya-board-body-collider"
        lowerBody.position.y = .init(-1-lowerHeight/2)
        lowerBody.physicsBody=captureSupportBody(for:SCNBox(width:width,height:lowerHeight,length:length,chamferRadius:0))
        board.addChildNode(lowerBody)
        if !currentEnvironment.usesTableBoard {
            KayaFloorBoard.addFeet(to:board,width:width,length:length,
                material:currentEnvironment.usesStoneBoard ? sidegrain : material,
                stone:currentEnvironment.usesStoneBoard)
        }
        worldAnchor.childNode(withName:"equipment-contact-shadows",recursively:false)?.removeFromParentNode()
        worldAnchor.addChildNode(KayaFloorBoard.contactShadow(width:width,length:length,surfaceY:currentEnvironment.equipmentSurfaceY,equipmentX:equipmentOffsetX,blackBowlZ:currentEnvironment.blackBowlZ,blackLidZ:currentEnvironment.blackLidZ,hasFeet:!currentEnvironment.usesTableBoard,hasMugs:currentEnvironment == .coffeeShop))
        worldAnchor.addChildNode(board); boardNode=board
        createGridLines()
        updateBoardCoordinates(showsBoardCoordinates)
        // Resizing in the cave must retain the same subdued fill as entering it.
        if currentEnvironment.usesStoneBoard { applyEnvironmentLighting() }
    }

    func updateBoardCoordinates(_ visible: Bool) {
        showsBoardCoordinates = visible
        guard let board = boardNode else { return }
        let existing = board.childNode(withName: "board-coordinates", recursively: false)
        guard visible else { existing?.removeFromParentNode(); return }
        guard existing == nil else { return }
        let group = SCNNode(); group.name = "board-coordinates"
        let ink = SCNMaterial(); ink.diffuse.contents = NSColor.black
        ink.lightingModel = .constant
        let halfWidth = CGFloat(boardSize - 1) * effectiveCellWidth / 2
        let halfHeight = CGFloat(boardSize - 1) * effectiveCellHeight / 2
        func label(_ value: String, x: CGFloat, z: CGFloat) {
            let text = SCNText(string: value, extrusionDepth: 0)
            text.font = NSFont.systemFont(ofSize: effectiveCellWidth * 0.40, weight: .bold)
            text.flatness = 0.01; text.materials = [ink]
            let node = SCNNode(geometry: text); node.name = "board-coordinate-\(value)"
            let (low, high) = text.boundingBox
            node.pivot = SCNMatrix4MakeTranslation((low.x + high.x) / 2, (low.y + high.y) / 2, 0)
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(x: .init(x), y: 1.025, z: .init(z))
            node.castsShadow = false; node.categoryBitMask = MaskBoard
            group.addChildNode(node)
        }
        for index in 0..<boardSize {
            let x = CGFloat(index) * effectiveCellWidth - halfWidth
            let z = CGFloat(index) * effectiveCellHeight - halfHeight
            let letter = GoBoardCoordinates.column(index)
            let number = GoBoardCoordinates.row(index, boardSize: boardSize)
            label(letter, x: x, z: -halfHeight - effectiveCellHeight * 0.75)
            label(letter, x: x, z: halfHeight + effectiveCellHeight * 0.75)
            label(number, x: -halfWidth - effectiveCellWidth * 0.75, z: z)
            label(number, x: halfWidth + effectiveCellWidth * 0.75, z: z)
        }
        board.addChildNode(group)
    }

    private func captureSupportBody(for geometry: SCNGeometry) -> SCNPhysicsBody {
        let shape = SCNPhysicsShape(geometry: geometry, options: [.collisionMargin: 0.005])
        let body = SCNPhysicsBody(type: .static, shape: shape)
        body.friction = 0.6
        body.restitution = 0.015
        body.categoryBitMask = PhysicsCategoryBowl
        body.collisionBitMask = PhysicsCategoryStone
        body.contactTestBitMask = PhysicsCategoryStone
        return body
    }
    private func createGridLines() { 
        guard let board = boardNode else { return }
        
        #if os(iOS)
        // The iOS depth buffer needs more separation for the very thin grid.
        let tY = boardThickness / 2.0 + 0.02
        #else
        let tY = boardThickness / 2.0 + 0.002 // Slightly above board
        #endif
        let w = CGFloat(boardSize - 1) * effectiveCellWidth
        let h = CGFloat(boardSize - 1) * effectiveCellHeight
        // Continuous ink stays separate from worn wood and limestone texture.
        // Stronger lines preserve readability in the monastery and cave.
        let lw = effectiveCellWidth * (currentEnvironment.usesAgedBoard || currentEnvironment.usesStoneBoard ? 0.028 : 0.02)
        let ink = SCNMaterial()
        ink.diffuse.contents = NSColor.black
        ink.lightingModel = .constant
        
        for i in 0..<boardSize { 
            // Vertical Lines (Z-axis length)
            let lZ = SCNBox(width: lw, height: 0.001, length: h, chamferRadius: 0)
            lZ.materials = [ink]
            let nZ = SCNNode(geometry: lZ)
            nZ.name = "board-grid-line"
            nZ.castsShadow = false
            nZ.categoryBitMask = MaskBoard
            // X position varies, Z centered
            nZ.position = SCNVector3(x: .init(CGFloat(i) * effectiveCellWidth - (w/2.0)), y: .init(tY), z: .init(0))
            board.addChildNode(nZ)
            
            // Horizontal Lines (X-axis length)
            let lX = SCNBox(width: w, height: 0.001, length: lw, chamferRadius: 0)
            lX.materials = [ink]
            let nX = SCNNode(geometry: lX)
            nX.name = "board-grid-line"
            nX.castsShadow = false
            nX.categoryBitMask = MaskBoard
            // Z position varies, X centered
            nX.position = SCNVector3(x: .init(0), y: .init(tY), z: .init(CGFloat(i) * effectiveCellHeight - (h/2.0)))
            board.addChildNode(nX) 
        }

        let starPoints: [BoardPosition]
        switch boardSize {
        case 19:
            starPoints = [3, 9, 15].flatMap { row in [3, 9, 15].map { BoardPosition(row, $0) } }
        case 9, 13:
            let inset = boardSize == 9 ? 2 : 3
            let far = boardSize - 1 - inset
            starPoints = [BoardPosition(inset, inset), BoardPosition(inset, far),
                          BoardPosition(far, inset), BoardPosition(far, far),
                          BoardPosition(boardSize / 2, boardSize / 2)]
        default:
            starPoints = []
        }
        // Flat ink dots sit just above the grid, sharing its board-local coordinates
        // and depth separation so they survive every environment/board rebuild.
        let dot = SCNCylinder(radius: effectiveCellWidth * 0.09, height: 0.001)
        dot.radialSegmentCount = 32
        dot.firstMaterial?.diffuse.contents = NSColor.black
        dot.firstMaterial?.lightingModel = .constant
        for point in starPoints {
            let node = SCNNode(geometry: dot)
            node.name = "board-star-point"
            node.categoryBitMask = MaskBoard
            node.castsShadow = false
            node.position = SCNVector3(CGFloat(point.col) * effectiveCellWidth - w / 2,
                                       tY + 0.002, CGFloat(point.row) * effectiveCellHeight - h / 2)
            board.addChildNode(node)
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
        
        upperLidNode = createLidNode(textureName: "go_lid_1", pos: SCNVector3(x: .init(equipmentOffsetX), y: .init(currentEnvironment.equipmentSurfaceY + 0.165), z: .init(-6.0)))
        lowerLidNode = createLidNode(textureName: "go_lid_2", pos: SCNVector3(x: .init(-equipmentOffsetX), y: .init(currentEnvironment.equipmentSurfaceY + 0.165), z: .init(currentEnvironment.blackLidZ)))
        
        if let u = upperLidNode { worldAnchor.addChildNode(u) }
        if let l = lowerLidNode { worldAnchor.addChildNode(l) }
        upperLidNode?.name = "white-player-lid"
        lowerLidNode?.name = "black-player-lid"
        updateCapturedStones(black: black, white: white)
        GoEquipment3D.update(in: self)
    }
    
    private func createLidNode(textureName: String, pos: SCNVector3) -> SCNNode {
        let geometry = CaptureLidSurface.makeGeometry()
        let material = SCNMaterial()
        material.diffuse.contents = NSImage(named: textureName) ?? NSColor.brown
        material.lightingModel = .lambert
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = pos
        node.categoryBitMask = MaskBoard

        // The same closed surface is both the visible dish and its collision shell.
        // A convex hull would fill the hollow interior and turn it back into a disk.
        let shape = SCNPhysicsShape(geometry: CaptureLidSurface.makeGeometry(segments: 32, radialSteps: 12), options: [
            .type: SCNPhysicsShape.ShapeType.concavePolyhedron, .collisionMargin: 0.005
        ])
        let body = SCNPhysicsBody(type: .static, shape: shape)
        body.friction = 0.5
        body.restitution = 0.015
        body.categoryBitMask = PhysicsCategoryBowl
        body.collisionBitMask = PhysicsCategoryStone
        body.contactTestBitMask = PhysicsCategoryStone
        node.physicsBody = body
        return node
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

    private func setupGhostNode() {
        boardCursorPosition = nil
        ghostBoardPosition = nil
        ghostColor = nil
        pendingGhostPlacement = nil
        ghostNode?.removeFromParentNode()
        ghostLandingNode?.removeFromParentNode()
        let stone = SCNNode(geometry: blackStoneGeometry)
        stone.name = "ghost-stone"
        stone.scale = SCNVector3(1, stoneScaleY, 1)
        stone.categoryBitMask = MaskStones
        stone.castsShadow = false
        stone.opacity = 0
        stonesContainer.addChildNode(stone)
        ghostNode = stone

        let plane = SCNPlane(width: effectiveCellWidth * 0.72, height: effectiveCellWidth * 0.72)
        let material = SCNMaterial()
        material.diffuse.contents = boardCursorTexture
        material.lightingModel = .constant
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let landing = SCNNode(geometry: plane)
        landing.name = "ghost-landing-marker"
        landing.eulerAngles.x = -.pi / 2
        landing.castsShadow = false
        landing.opacity = 0
        stonesContainer.addChildNode(landing)
        ghostLandingNode = landing
    }

    func updateGhostStone(at pos: BoardPosition?, color: Stone?, animate: Bool = false) {
        guard let p = pos, let c = color, let stone = ghostNode else { clearGhostStone(); return }
        let wasVisible = ghostBoardPosition != nil && stone.opacity > 0
        let sameColor = ghostColor == c
        let changedPoint = ghostBoardPosition != p
        ghostBoardPosition = p
        let x = (CGFloat(p.col) - CGFloat(boardSize - 1) / 2) * effectiveCellWidth
        let z = (CGFloat(p.row) - CGFloat(boardSize - 1) / 2) * effectiveCellHeight
        let surfaceY = boardThickness / 2
        let destination = SCNVector3(x, surfaceY + placementHoverHeight + stoneRadius * stoneScaleY, z)
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        if !sameColor {
            stone.geometry = c == .black ? blackStoneGeometry : clamGeometries[(p.row * 19 + p.col) % 5]
            stone.eulerAngles.y = .init(p.col * p.row)
            ghostColor = c
        }
        if !animate || !wasVisible || !sameColor {
            stone.removeAction(forKey: Self.ghostGlideKey)
            stone.position = destination
        } else if changedPoint {
            // Interrupt from the rendered position, without queuing motion or
            // restarting the glide on repeated hover/analysis publications.
            let start = stone.action(forKey: Self.ghostGlideKey) == nil ? stone.position : stone.presentation.position
            stone.removeAction(forKey: Self.ghostGlideKey)
            stone.position = start
            let glide = SCNAction.move(to: destination, duration: 0.08)
            glide.timingMode = .easeOut
            stone.runAction(glide, forKey: Self.ghostGlideKey)
        }
        stone.opacity = ghostOpacity
        SCNTransaction.commit()
        updateBoardCursorIndicator()
    }

    /// Capture before the view model clears the hover or publishes the new board.
    /// This is presentation only: hit testing and legality stay with the caller.
    func prepareGhostPlacement(at point: BoardPosition, color: Stone) {
        pendingGhostPlacement = nil
        guard ghostBoardPosition == point, ghostColor == color,
              let stone = ghostNode, stone.opacity > 0 else { return }
        let position = stone.action(forKey: Self.ghostGlideKey) == nil ? stone.position : stone.presentation.position
        pendingGhostPlacement = GhostPlacement(point: point, color: color, position: position,
            geometry: stone.geometry, eulerAngles: stone.eulerAngles)
    }

    func cancelGhostPlacement() { pendingGhostPlacement = nil }

    func clearGhostStone() {
        ghostBoardPosition = nil
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        ghostNode?.removeAction(forKey: Self.ghostGlideKey)
        ghostNode?.opacity = 0
        SCNTransaction.commit()
        updateBoardCursorIndicator()
    }

    /// Keep a subdued pointer visible even when placement is unavailable.
    func updateBoardCursor(at position: BoardPosition?) {
        boardCursorPosition = position
        updateBoardCursorIndicator()
    }

    private func updateBoardCursorIndicator() {
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        guard let point = boardCursorPosition ?? ghostBoardPosition else {
            ghostLandingNode?.opacity = 0
            return
        }
        let occupied = stoneNodeMap[point] != nil
        let isVariation = reviewVariations.contains { $0.position == point }
        let surfaceY = boardThickness / 2 + (occupied || isVariation ? stoneRadius * stoneScaleY * 2 : 0)
        ghostLandingNode?.position = SCNVector3(
            (CGFloat(point.col) - CGFloat(boardSize - 1) / 2) * effectiveCellWidth,
            surfaceY + 0.025,
            (CGFloat(point.row) - CGFloat(boardSize - 1) / 2) * effectiveCellHeight)
        ghostLandingNode?.opacity = (point == ghostBoardPosition || isVariation) && !occupied ? 1 : 0.42
    }
}

/// A turned wooden dish, in the same units as the captured stones (diameter 0.96).
/// The rim and underside close the mesh; no invisible containment walls are needed.
enum CaptureLidSurface {
    static let innerRadius: CGFloat = 2.85
    static let outerRadius: CGFloat = 3.15
    static let floorHeight: CGFloat = 0.12
    static let rimHeight: CGFloat = 1.02

    static func interiorHeight(at radius: CGFloat) -> CGFloat {
        let t = min(1, max(0, radius / innerRadius))
        return floorHeight + (rimHeight - 0.08 - floorHeight) * (0.25 * t * t + 0.75 * pow(t, 4))
    }

    static func makeGeometry(segments: Int = 96, radialSteps: Int = 28) -> SCNGeometry {
        // Cross-section travels out across the floor, around the lip, down the
        // outer wall, then back under the foot. Revolving it makes a watertight dish.
        var profile: [CGPoint] = (0...radialSteps).map { index in
            let r = innerRadius * CGFloat(index) / CGFloat(radialSteps)
            return CGPoint(x: r, y: interiorHeight(at: r))
        }
        profile += [
            CGPoint(x: 2.89, y: 0.985), CGPoint(x: 2.95, y: rimHeight),
            CGPoint(x: 3.02, y: 1.01), CGPoint(x: 3.08, y: 0.97),
            CGPoint(x: 3.13, y: 0.90), CGPoint(x: outerRadius, y: 0.80),
            CGPoint(x: 3.12, y: 0.62), CGPoint(x: 3.04, y: 0.43),
            CGPoint(x: 2.91, y: 0.25), CGPoint(x: 2.72, y: 0.08),
            CGPoint(x: 2.48, y: -0.06), CGPoint(x: 2.20, y: -0.15),
            CGPoint(x: 1.80, y: -0.15), CGPoint(x: 0, y: -0.15)
        ]
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uv: [CGPoint] = []
        var indices: [Int32] = []
        for (ring, point) in profile.enumerated() {
            let before = profile[max(0, ring - 1)]
            let after = profile[min(profile.count - 1, ring + 1)]
            let dr = after.x - before.x, dy = after.y - before.y
            let length = max(0.001, hypot(dr, dy))
            for segment in 0...segments {
                let angle = CGFloat(segment) * 2 * .pi / CGFloat(segments)
                let c = cos(angle), s = sin(angle)
                vertices.append(SCNVector3(point.x * c, point.y, point.x * s))
                normals.append(SCNVector3(-dy / length * c, dr / length, -dy / length * s))
                // The source is a photograph with transparent space around the lid.
                // Sample only its wooden disk; map the outside to wood near the rim.
                let textureRadius = ring <= 30 ? point.x / 3.02 * 0.365 : 0.35 - (1.02 - point.y) * 0.015
                uv.append(CGPoint(x: 0.5 + textureRadius * c, y: 0.5 + textureRadius * s))
                if ring < profile.count - 1 && segment < segments {
                    let a = Int32(ring * (segments + 1) + segment)
                    let b = a + 1, d = a + Int32(segments + 1), e = d + 1
                    // Angular tangent crossed with the outward profile tangent faces up inside.
                    if point.x > 0 { indices += [a, b, d] }
                    if profile[ring + 1].x > 0 { indices += [b, e, d] }
                }
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uv)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}
