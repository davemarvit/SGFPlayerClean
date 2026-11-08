import SwiftUI
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct PlayingEnvironmentsCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        for kind in PlayingEnvironment.allCases {
            guard let image = EnvironmentMaterials.panorama(kind),
                  let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!) else {
                require(false, "Bundled panorama: \(kind.title)"); return
            }
            let expected = kind == .gardenRoom ? (8192, 4096) : (3548, 1774)
            require(bitmap.pixelsWide == expected.0 && bitmap.pixelsHigh == expected.1,
                    "Full-resolution bundled panorama: \(kind.title)")
        }
        let exterior = NSBitmapImageRep(data: EnvironmentMaterials.image("station-orbital-exterior.png")!.tiffRepresentation!)!
        require(exterior.pixelsWide == 3548 && exterior.pixelsHigh == 1774, "Enhanced station exterior")
        require(EnvironmentMaterials.image("leaf-color.png") != nil,"Bundled leaf texture")
        require(EnvironmentMaterials.image("kaya-endgrain-v2.png") != nil,"Bundled kaya end grain")
        let settings = AppSettings.shared
        settings.isMuted = true; settings.folderURL = nil
        settings.environment3D = .gardenRoom
        settings.camera3DDistance = 42; settings.camera3DRotationX = -0.12; settings.camera3DRotationY = -0.25
        settings.camera3DPanX = 0; settings.camera3DPanY = 0
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        app.aiAnalysisEnabled = false; app.showRightPanel = false; app.viewMode = .view3D
        let sgf = "(;SZ[19];B[dd];W[pd];B[dp];W[pp];B[cf];W[nc])"
        let game = SGFGame.from(tree: try SGFParser.parse(text: sgf))
        let url = URL(fileURLWithPath: "/private/tmp/sgf-environments-\(UUID()).sgf")
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        app.selectGame(SGFGameWrapper(url: url, game: game)); app.boardVM?.goToEnd()
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:1200,height:850),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance = NSAppearance(named:.darkAqua)
        let host = NSHostingView(rootView: ContentView3D().environmentObject(app))
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle(_ seconds: Double = 0.25) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        settle()
        let live = UnifiedInteractiveSceneView.lastActiveView!
        let originalScene = live.scene!
        let originalBowl = originalScene.rootNode.childNode(withName:"black-stone-bowl",recursively:true)!
        let originalCamera = live.pointOfView!
        for kind in PlayingEnvironment.allCases {
            settings.environment3D = kind; settle()
            require(UserDefaults.standard.string(forKey:"environment3D") == kind.rawValue,"Choice saved: \(kind.title)")
            require(live.scene === originalScene,"Switch reuses the scene")
            // Environment changes deliberately start a new arrival with the same camera.
            require(live.pointOfView === originalCamera,"Switch reuses the camera")
            require(originalScene.rootNode.childNode(withName:"environment-\(kind.rawValue)",recursively:true) != nil,"Settings updates visible scene: \(kind.title)")
            require(originalScene.rootNode.childNode(withName:"black-stone-bowl",recursively:true) === originalBowl,"Switch preserves settled bowl")
            require(app.boardVM?.currentMoveIndex == 6,"Switch preserves game position")
        }
        settings.environment3D = .cave; settings.lampFlicker = true; settle()
        let lamp = originalScene.rootNode.childNode(withName:"oil-lamp-light",recursively:true)!
        require(live.isPlaying && live.rendersContinuously,"Idle cave keeps its flicker running")
        var intensities: [CGFloat] = []
        var positions: [CGFloat] = []
        let visibleFlame = originalScene.rootNode.childNode(withName:"oil-lamp-flame",recursively:true)!
        let flameMaterial = visibleFlame.childNodes.first!.geometry!.firstMaterial!
        let startingPhase = (flameMaterial.value(forKey:"flameTime") as? NSNumber)?.floatValue ?? 0
        for _ in 0..<10 { settle(0.15); intensities.append(lamp.light!.intensity); positions.append(lamp.position.x) }
        let endingPhase = (flameMaterial.value(forKey:"flameTime") as? NSNumber)?.floatValue ?? 0
        require(endingPhase > startingPhase + 0.5,"Visible flame animation advances in the real idle view")
        require(positions.max()! - positions.min()! > 0.01,"Flicker moves the shadow-casting light")
        require(intensities.max()! - intensities.min()! > 5,"Lamp actually flickers in the live view")
        require(intensities.allSatisfy { abs($0 - PlayingEnvironmentScene.caveLampIntensity) < PlayingEnvironmentScene.caveLampIntensity * 0.075 },"Flicker remains gentle")
        settings.lampFlicker = false; settle()
        require(UserDefaults.standard.object(forKey:"lampFlicker") as? Bool == false,"Flicker preference saved")
        require(lamp.action(forKey:"lamp-flicker") == nil && lamp.light!.intensity == PlayingEnvironmentScene.caveLampIntensity,"Toggle stops flicker")
        require(!live.isPlaying && !live.rendersContinuously,"Disabling flicker stops idle rendering")
        require(abs(lamp.position.x - PlayingEnvironmentScene.caveLampWorldPosition.x) < 0.001,"Disabling flicker restores the light position")
        settings.lampFlicker = true; settle()
        settings.environment3D = .moon; settle()
        require(lamp.action(forKey:"lamp-flicker") == nil,"Leaving cave stops animation")
        // Render the real settings drawer, including its cave-specific control.
        settings.environment3D = .cave; settle()
        let panel = NSHostingView(rootView: SettingsPanel(app:app,isPresented:.constant(true)))
        panel.frame = NSRect(x:0,y:0,width:370,height:850); host.addSubview(panel)
        settle()
        let image = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
        panel.cacheDisplay(in:panel.bounds,to:image)
        try image.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/sgf-environment-settings.png"))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let picker=descendants(panel).compactMap { $0 as? NSPopUpButton }.first!
        require(PlayingEnvironment.allCases.allSatisfy { picker.itemTitles.contains($0.title) },"Actual Settings menu lists all environment choices")
        picker.selectItem(withTitle:PlayingEnvironment.moon.title)
        picker.menu!.performActionForItem(at:picker.indexOfSelectedItem)
        settle()
        require(settings.environment3D == .moon,"Settings menu changes the saved environment")
        require(originalScene.rootNode.childNode(withName:"environment-moon",recursively:true) != nil,"Native menu changes the live scene")
        settings.environment3D = .cave; settle()
        // Dismantling the view must release the active animation.
        window.contentView = NSView(); settle()
        require(lamp.action(forKey:"lamp-flicker") == nil,"Hidden 3D view stops lamp animation")
        let twoD=NSHostingView(rootView:ContentView2D().environmentObject(app))
        window.contentView=twoD
        for size in [CGSize(width:1200,height:850),CGSize(width:800,height:1000)] {
            window.setContentSize(size); settle(); twoD.layoutSubtreeIfNeeded()
            let layout=ContentView2D.getLayout(area:size)
            require(layout.bW+2*(layout.gap+layout.lidD)<size.width,"Both lid columns fit the 2D viewport")
            let bitmap=twoD.bitmapImageRepForCachingDisplay(in:twoD.bounds)!
            twoD.cacheDisplay(in:twoD.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/sgf-lids-2d-\(Int(size.width)).png"))
        }
        print("PASS: live settings, persistence, game/camera identity preservation, actual flicker, toggle, and cleanup")
    }
}
