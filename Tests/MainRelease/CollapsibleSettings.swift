import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct CollapsibleSettingsCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil
        AppSettings.shared.isMuted = true
        AppSettings.shared.environment3D = .cave
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        app.aiAnalysisEnabled = false
        app.viewMode = .view3D
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let suite = "com.davemarvit.SGFPlayerClean.settings-layout.\(UUID().uuidString)"
        let expansionDefaults = UserDefaults(suiteName: suite)!
        defer { expansionDefaults.removePersistentDomain(forName: suite) }
        let background = Color(red: 0.8, green: 0.2, blue: 0.6)
        var host = NSHostingView(rootView: background.overlay { SettingsPanel(app: app, isPresented: .constant(true)).defaultAppStorage(expansionDefaults) })
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)); host.layoutSubtreeIfNeeded() }
        func capture(_ name: String? = nil) throws -> (NSBitmapImageRep, [VNRecognizedTextObservation]) {
            settle()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let name { try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-settings-\(name).png")) }
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return (bitmap, request.results ?? [])
        }
        func text(_ observation: VNRecognizedTextObservation) -> String { observation.topCandidates(1).first?.string ?? "" }
        func press(_ title: String) throws {
            let (_, observations) = try capture()
            func normalized(_ value: String) -> String { value.lowercased().replacingOccurrences(of: "l", with: "i") }
            guard let label = observations.first(where: { normalized(text($0)).contains(normalized(title)) }) else {
                print(observations.map(text)); require(false, "Missing section: \(title)"); return
            }
            let box = label.boundingBox
            let point = NSPoint(x: host.bounds.width * box.midX, y: host.bounds.height * (host.isFlipped ? 1 - box.midY : box.midY))
            let location = host.convert(point, to: nil)
            window.makeKeyAndOrderFront(nil)
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            }
            NSApplication.shared.postEvent(event(.leftMouseUp), atStart: false)
            window.sendEvent(event(.leftMouseDown))
            window.sendEvent(event(.leftMouseUp))
            settle()
        }
        func footerTop(_ observations: [VNRecognizedTextObservation]) -> CGFloat {
            guard let footer = observations.first(where: { text($0).contains("v1.0.47") }) else { require(false, "Footer is visible"); return 0 }
            return (1 - footer.boundingBox.midY) * host.bounds.height
        }
        let (initialBitmap, initial) = try capture("environment")
        let initialHeight = footerTop(initial)
        require(initialHeight < 650, "Environment-only panel hugs content")
        require(initial.contains { text($0).contains("Gentle lamp flicker") }, "Expanded environment exposes cave controls")
        // The exposed area must retain precisely the same scene pixels as the area beside the panel.
        let below = initialBitmap.colorAt(x: 100, y: initialBitmap.pixelsHigh - 40)!.usingColorSpace(.deviceRGB)!
        let beside = initialBitmap.colorAt(x: initialBitmap.pixelsWide - 40, y: initialBitmap.pixelsHigh - 40)!.usingColorSpace(.deviceRGB)!
        require(abs(below.redComponent - beside.redComponent) < 0.01 && below.redComponent > 0.7, "No glass or dimming extends below the panel")
        try press("3D environment")
        let (_, collapsed) = try capture("collapsed")
        let compactHeight = footerTop(collapsed)
        require(compactHeight < initialHeight - 50, "Collapsing environment shrinks the background")
        let sections = [("Playback", "playback", "Move Delay"), ("Last move markers", "markers", "Move Numbers"), ("AI Engine", "ai", "Analyze quietly"), ("Screensaver", "screensaver", "Quiet Go playback"), ("Library", "library", "Choose Folder")]
        for (title, key, detail) in sections {
            try press(title)
            let (_, expanded) = try capture()
            require(expanded.contains { text($0).contains(detail) }, "\(title) reveals its controls")
            require(footerTop(expanded) > compactHeight + 30, "\(title) grows the panel")
            require(expansionDefaults.bool(forKey: "settings.\(key).expanded"), "\(title) saves expansion")
            if key == "ai" {
                _ = try capture("ai-expanded")
                require(expanded.contains { text($0).contains("Enable analysis") }, "Master analysis toggle is visible")
                AppSettings.shared.analysisEnabled = false
                _ = try capture("analysis-off")
                AppSettings.shared.analysisEnabled = true
                _ = try capture("analysis-on")
            }
            try press(title)
            let (_, hidden) = try capture()
            require(!hidden.contains { text($0).contains(detail) }, "\(title) hides its controls")
            require(abs(footerTop(hidden) - compactHeight) < 3, "\(title) restores compact height")
        }
        try press("Playback")
        window.contentView = NSView()
        let reopened = NSHostingView(rootView: background.overlay { SettingsPanel(app: app, isPresented: .constant(true)).defaultAppStorage(expansionDefaults) })
        window.contentView = reopened
        host = reopened
        let (_, restored) = try capture()
        require(restored.contains { text($0).contains("Move Delay") }, "Expansion persists when recreated")
        // Resize with content taller than the available viewport, then scroll to the footer.
        window.setContentSize(NSSize(width: 800, height: 360)); settle()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let scroll = descendants(host).compactMap { $0 as? NSScrollView }.first!
        require(scroll.frame.height <= 340.5, "Panel stays within short windows")
        let document = scroll.documentView!
        require(document.bounds.height > scroll.contentView.bounds.height, "Overflow remains scrollable")
        document.scroll(NSPoint(x: 0, y: document.bounds.height)); settle()
        let (_, scrolled) = try capture("short-scrolled")
        require(scrolled.contains { text($0).contains("v1.0.47") }, "Footer reachable by scrolling")
        window.setContentSize(NSSize(width: 800, height: 1100)); settle()
        require(scroll.frame.height < 900, "Panel shrinks back to content after resize")
        print("PASS: six clickable collapsible sections, remembered state, fitted glass, clear surroundings, window resize and overflow scrolling")
    }
}
