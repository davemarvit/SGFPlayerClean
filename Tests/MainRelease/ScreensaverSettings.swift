import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
@main struct ScreensaverSettingsCheck {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = temp.appendingPathComponent("Source"), root = temp.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let sgf = "(;SZ[9]PB[Alice]PW[Bob];B[dd];W[ee];B[ff];W[gg];B[aa];W[bb];B[cc];W[hh])"
        try sgf.write(to: source.appendingPathComponent("one.sgf"), atomically: true, encoding: .utf8)
        try sgf.replacingOccurrences(of: "Alice", with: "Carol").write(to: source.appendingPathComponent("two.sgf"), atomically: true, encoding: .utf8)
        let template = Bundle.main.resourceURL!.appendingPathComponent("Screensaver/Quiet Go.saver")
        let installed = temp.appendingPathComponent("Installed/Quiet Go.saver")
        let manager = ScreensaverManager(root: root, installationURL: installed, templateURL: template)
        require(manager.configuration == nil && !manager.enabled, "New settings start unconfigured")
        let refreshed = await manager.refresh(folder: source)
        require(refreshed && manager.configuration?.gameCount == 2 && !manager.busy, "Prepare selected folder asynchronously")
        manager.setEnabled(true)
        require(manager.enabled && manager.installed && FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/MacOS/QuietGoSaver").path), "Enable installs the bundled screensaver")
        let first = try ScreensaverConfiguration.load(root: root)
        let empty = temp.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let failed = await manager.refresh(folder: empty)
        require(!failed && manager.configuration == first, "Failed selection retains working folder and enablement")
        manager.setEnabled(false)
        let disabled = try ScreensaverConfiguration.load(root: root)
        require(!disabled.enabled, "Disable persists")
        let restored = ScreensaverManager(root: root, installationURL: installed, templateURL: template)
        require(!restored.enabled && restored.configuration?.sourceFolderPath == source.path, "Folder and enablement survive relaunch")
        restored.setEnabled(true)
        require(restored.enabled && restored.installed, "Replacing installed bundle preserves successful enablement")
        await restored.refreshOnLaunch()
        require(restored.configuration?.gameCount == 2 && restored.configuration?.generation != first.generation, "App launch refreshes selected library")
        render(manager: restored)
        try root.path.write(to: URL(fileURLWithPath: "/private/tmp/sgf-integrated-fixture-path"), atomically: true, encoding: .utf8)
        print("PASS: folder import, failed-folder preservation, install/replace, enable/disable persistence, launch refresh, settings rendering")
    }
    @MainActor static func render(manager: ScreensaverManager) {
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:360,height:410), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: ScreensaverSettingsView(manager: manager).padding(16).frame(width:360,height:410).background(Color(white:0.15)))
        window.contentView = host; window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3)); host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-integrated-settings.png"))
        window.orderOut(nil)
    }
}
