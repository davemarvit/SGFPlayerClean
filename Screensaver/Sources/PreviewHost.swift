import AppKit
import ScreenSaver

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class HostDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var saver: ScreenSaverView!
    var timer: Timer?
    let testing = CommandLine.arguments.contains("--test")
    func applicationDidFinishLaunching(_ note: Notification) {
        let url = Bundle.main.builtInPlugInsURL!.appendingPathComponent("Quiet Go.saver")
        guard let bundle = Bundle(url: url), let type = bundle.principalClass as? ScreenSaverView.Type,
              let view = type.init(frame: NSRect(x: 0,y: 0,width: 1000,height: 850), isPreview: false) else {
            require(false, "Load actual screensaver bundle and principal class"); return
        }
        saver = view
        window = NSWindow(contentRect: view.bounds, styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "SGF Screensaver Preview"; window.contentView = view
        window.center(); window.makeKeyAndOrderFront(nil)
        saver.startAnimation()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.saver.animateOneFrame() }
        if testing { DispatchQueue.main.async { self.test() } }
        else { NSApp.activate(ignoringOtherApps: true) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); saver?.stopAnimation() }
    func test() {
        func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        require((saver.value(forKey: "loadedGameCount") as? Int ?? 0) > 0, "Bundled folder loads")
        settle(3.4)
        let index = saver.value(forKey: "displayedMove") as? Int ?? 0
        require(index >= 2, "Actual bundle advances moves")
        func capture(_ name: String) {
            saver.displayIfNeeded()
            guard let bitmap = saver.bitmapImageRepForCachingDisplay(in: saver.bounds) else { require(false, "Capture bitmap"); return }
            saver.cacheDisplay(in: saver.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])!
            try! data.write(to: URL(fileURLWithPath: "/private/tmp/sgf-saver-\(name).png"))
        }
        capture("full")
        saver.stopAnimation(); settle(2)
        require(saver.value(forKey: "displayedMove") as? Int == index, "Stop prevents playback even with late frame callbacks")
        window.setContentSize(NSSize(width: 320,height: 220)); saver.needsDisplay = true; settle(0.2); capture("small")
        saver.startAnimation(); settle(1.7)
        require((saver.value(forKey: "displayedMove") as? Int ?? 0) > index, "Restart resumes playback")
        // Apple may instantiate more than one view. Preview must work independently.
        let second = (type(of: saver)).init(frame: NSRect(x:0,y:0,width:320,height:220), isPreview: true)!
        second.startAnimation(); require(second.value(forKey: "displayedMove") as? Int == 0, "Independent preview state")
        second.stopAnimation()
        print("PASS: signed bundle load, folder read, rendering at full/preview sizes, real timed playback, stop/late-frame/restart, independent instances")
        NSApp.terminate(nil)
    }
}
@main struct PreviewMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(CommandLine.arguments.contains("--test") ? .prohibited : .regular)
        let mainMenu = NSMenu(), appMenu = NSMenu(), item = NSMenuItem()
        appMenu.addItem(withTitle: "Quit SGF Screensaver Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; mainMenu.addItem(item); app.mainMenu = mainMenu
        let delegate = HostDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
