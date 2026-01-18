//
//  SGFPlayerCleanApp.swift
//  SGFPlayerClean
//
//  Purpose: Main application entry point
//  Ensures a single AppModel instance is shared across the app.
//

import SwiftUI
import SceneKit // Added for StoneLab

@main
struct SGFPlayerCleanApp: App {
    // Single source of truth for the entire application lifecycle
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 1000, minHeight: 700)
//            StoneLaboratoryView()
//                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open SGF File...") {
                    openSGFFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    /// Open SGF file picker
    private func openSGFFile() {
        print("📂 Opening file picker...")
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]
        panel.title = "Choose an SGF file"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                print("📂 Selected file: \(url.path)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("LoadSGFFile"),
                    object: url
                )
            }
        }
    }
}

// MARK: - Stone Laboratory
class StoneLabManager: ObservableObject {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let stoneNode = SCNNode()
    let lightNode = SCNNode()
    let ambientNode = SCNNode()
    
    // Debug Properties
    @Published var roughness: Double = 0.8 { didSet { updateMat() } }
    @Published var coat: Double = 1.0 { didSet { updateMat() } }
    @Published var coatRoughness: Double = 0.1 { didSet { updateMat() } }
    @Published var emission: Double = 0.05 { didSet { updateMat() } }
    
    @Published var sunIntensity: Double = 0.92 { didSet { updateLight() } }
    @Published var ambIntensity: Double = 0.62 { didSet { updateLight() } }
    @Published var envIntensity: Double = 0.59 { didSet { updateEnv() } }
    
    init() {
        // Camera
        let c = SCNCamera()
        c.zNear = 0.1
        c.zFar = 100
        cameraNode.camera = c
        cameraNode.position = SCNVector3(0, 5, 5)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)
        
        // Lighting (Matching SGFPlayerClean)
        lightNode.light = SCNLight()
        lightNode.light?.type = .directional
        lightNode.light?.castsShadow = true
        lightNode.position = SCNVector3(-5, 10, -5)
        lightNode.look(at: SCNVector3(0,0,0))
        scene.rootNode.addChildNode(lightNode)
        
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        scene.rootNode.addChildNode(ambientNode)
        
        // Environment (Matching SGFPlayerClean)
        let size = 512
        let env = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            let colors = [NSColor(white: 1.2, alpha: 1.0).cgColor, NSColor(white: 0.6, alpha: 1.0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
            return true
        }
        scene.lightingEnvironment.contents = env
        scene.background.contents = NSColor(white: 0.1, alpha: 1.0)
        
        // Stone
        // Use a simple Sphere to eliminate MeshFactory variables first, OR use MeshFactory?
        // Let's use SCNSphere first to verify PBR works at all.
        let geo = SCNSphere(radius: 1.0)
        // Adjust scale to match "Shell" shape roughly
        stoneNode.geometry = geo
        stoneNode.scale = SCNVector3(1, 0.5, 1)
        scene.rootNode.addChildNode(stoneNode)
        
        // Initialize Values
        updateMat()
        updateLight()
        updateEnv()
    }
    
    func updateMat() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        let m = stoneNode.geometry!.firstMaterial!
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = roughness
        m.clearCoat.contents = coat
        m.clearCoatRoughness.contents = coatRoughness
        m.emission.contents = NSColor(white: emission, alpha: 1)
        SCNTransaction.commit()
    }
    
    func updateLight() {
        lightNode.light?.color = NSColor(white: sunIntensity, alpha: 1)
        ambientNode.light?.color = NSColor(white: ambIntensity, alpha: 1)
    }
    
    func updateEnv() {
        scene.lightingEnvironment.intensity = envIntensity
    }
}

struct StoneLaboratoryView: View {
    @StateObject var man = StoneLabManager()
    
    var body: some View {
        HStack {
            SceneView(scene: man.scene, pointOfView: man.cameraNode, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            ScrollView {
                VStack(alignment: .leading) {
                    Text("Stone Lab").font(.headline)
                    Divider()
                    Text("Roughness (Base)")
                    Slider(value: $man.roughness, in: 0...1)
                    Text("Clear Coat (Glass)")
                    Slider(value: $man.coat, in: 0...1)
                    Text("Coat Roughness")
                    Slider(value: $man.coatRoughness, in: 0...1)
                    Text("Emission")
                    Slider(value: $man.emission, in: 0...1)
                    Divider()
                    Text("Sun")
                    Slider(value: $man.sunIntensity, in: 0...3)
                    Text("Ambient")
                    Slider(value: $man.ambIntensity, in: 0...3)
                    Text("Environment")
                    Slider(value: $man.envIntensity, in: 0...3)
                }
                .padding()
                .frame(width: 250)
            }
        }
    }
}
