import AppKit
import ScreenSaver

// Run against a built saver and an isolated playback configuration. No user
// installation is changed: the test removes resources from its disposable copy.
@main struct SaverAssetLifetimeCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let saverURL = temp.appendingPathComponent("Quiet Go.saver")
        try fm.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: saverURL)
        let bundle = Bundle(url: saverURL)!
        let type = bundle.principalClass as! ScreenSaverView.Type
        let view = type.init(frame: NSRect(x: 0, y: 0, width: 1000, height: 850), isPreview: false)!
        view.perform(NSSelectorFromString("setConfigurationRoot:"), with: CommandLine.arguments[2])
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { view.stopAnimation(); window.orderOut(nil) }
        view.startAnimation()
        precondition(view.value(forKey: "displayedBoardSize") as? Int == 19)
        func capture(_ size: NSSize) -> [Double] {
            window.setContentSize(size)
            view.needsDisplay = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            var pixels = [Double]()
            // The outer right margin contains only tatami, even in the small preview.
            var texture = [Double]()
            for y in 0..<bitmap.pixelsHigh {
                let color = bitmap.colorAt(x: bitmap.pixelsWide - 3, y: y)!.usingColorSpace(.sRGB)!
                texture.append(Double(color.greenComponent))
            }
            precondition(texture.max()! - texture.min()! > 0.1, "Tatami must contain weave detail, not a flat fallback")
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
                    let c = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    pixels += [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
                }
            }
            return pixels
        }
        let sizes = [NSSize(width: 1000, height: 850), NSSize(width: 320, height: 220), NSSize(width: 600, height: 1000)]
        for layered in [false, true] {
            view.wantsLayer = layered
            let before = sizes.map(capture)
            let resources = saverURL.appendingPathComponent("Contents/Resources")
            let moved = temp.appendingPathComponent("Removed resources")
            try fm.moveItem(at: resources, to: moved)
            for _ in 0..<3 {
                view.stopAnimation(); view.startAnimation()
                for (size, expected) in zip(sizes, before) {
                    let actual = capture(size)
                    precondition(actual == expected, "Loaded images must survive removal of their bundle files, resize, and restart")
                }
            }
            try fm.moveItem(at: moved, to: resources)
        }
        print("PASS: tatami and equipment survive resource removal, repeated restart and resize in bitmap and layer-backed views.")
    }
}
