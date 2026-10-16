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
        configure(view)
        window = NSWindow(contentRect: view.bounds, styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "SGF Screensaver Preview"; window.contentView = view
        window.center(); window.makeKeyAndOrderFront(nil)
        saver.startAnimation()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.saver.animateOneFrame() }
        if testing { DispatchQueue.main.async { self.test() } }
        else { NSApp.activate(ignoringOtherApps: true) }
    }
    func configure(_ view: ScreenSaverView) {
        if let i = CommandLine.arguments.firstIndex(of: "--configuration-root"), i + 1 < CommandLine.arguments.count {
            view.perform(NSSelectorFromString("setConfigurationRoot:"), with: CommandLine.arguments[i + 1])
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); saver?.stopAnimation() }
    func test() {
        func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        require((saver.value(forKey: "loadedGameCount") as? Int ?? 0) > 0, "Configured folder loads")
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
        configure(second)
        second.startAnimation(); require(second.value(forKey: "displayedMove") as? Int == 0, "Independent preview state")
        second.stopAnimation()
        if let i = CommandLine.arguments.firstIndex(of: "--configuration-root"), i + 1 < CommandLine.arguments.count {
            let root = URL(fileURLWithPath: CommandLine.arguments[i + 1]), file = root.appendingPathComponent("configuration.json")
            let original = try! Data(contentsOf: file)
            defer { try! original.write(to: file, options: .atomic) }
            var config = try! JSONSerialization.jsonObject(with: original) as! [String: Any]
            func save() { try! JSONSerialization.data(withJSONObject: config).write(to: file, options: .atomic) }
            config["enabled"] = false; save(); settle(1.3)
            require(saver.value(forKey: "playbackRunning") as? Bool == false, "Disable setting stops active playback")
            let stopped = saver.value(forKey: "displayedMove") as? Int
            settle(1.7)
            require(saver.value(forKey: "displayedMove") as? Int == stopped, "Disabled playback stays stopped")
            config["enabled"] = true; save(); settle(1.3)
            require(saver.value(forKey: "playbackRunning") as? Bool == true, "Re-enable resumes active saver")
            let generation = UUID().uuidString
            let replacement = root.appendingPathComponent("Libraries").appendingPathComponent(generation)
            try! FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: replacement) }
            try! "(;SZ[13];B[dd];W[jj])".write(to: replacement.appendingPathComponent("replacement.sgf"), atomically: true, encoding: .utf8)
            config["generation"] = generation; config["gameCount"] = 1; save(); settle(1.3)
            require(saver.value(forKey: "displayedBoardSize") as? Int == 13 && saver.value(forKey: "displayedGame") as? String == "replacement.sgf", "A published folder replacement loads in the active saver")
            require(saver.value(forKey: "displayedBlackCaptures") as? Int == 0 && saver.value(forKey: "displayedWhiteCaptures") as? Int == 0, "New game starts with empty lids")

            // White captures one black stone, then Black captures two white stones.
            let capturesID = UUID().uuidString
            let captures = root.appendingPathComponent("Libraries").appendingPathComponent(capturesID)
            try! FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: captures) }
            try! "(;SZ[9]PL[W]PB[Alice]PW[Bob]AB[aa][ha][hb][gc][fb]AW[ba][ga][gb];W[ab];B[fa])".write(to: captures.appendingPathComponent("captures.sgf"), atomically: true, encoding: .utf8)
            config["generation"] = capturesID; save(); settle(1.2)
            require(saver.value(forKey: "displayedBlackCaptures") as? Int == 0 && saver.value(forKey: "displayedWhiteCaptures") as? Int == 0, "Replacing the library clears old captures")
            settle(3.4)
            require(saver.value(forKey: "displayedBlackCaptures") as? Int == 1, "Upper lid contains the captured black stone")
            require(saver.value(forKey: "displayedWhiteCaptures") as? Int == 2, "Lower lid contains two captured white stones")
            saver.stopAnimation()
            for (name, size) in [("capture-lids", NSSize(width: 1200, height: 850)), ("capture-lids-small", NSSize(width: 320, height: 220)), ("capture-lids-portrait", NSSize(width: 600, height: 1000))] {
                window.setContentSize(size); saver.needsDisplay = true; settle(0.1); capture(name)
            }
            saver.startAnimation()
            config["generation"] = generation; save(); settle(1.2)
            require(saver.value(forKey: "displayedBlackCaptures") as? Int == 0 && saver.value(forKey: "displayedWhiteCaptures") as? Int == 0, "Both captured-stone lids reset after leaving the capture game")
        }
        print("PASS: signed bundle load, rendering at full/preview/portrait sizes, real timed playback, stop/restart, independent instances, enable/disable, folder changes, both capture colors/counts and lid resets")
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
