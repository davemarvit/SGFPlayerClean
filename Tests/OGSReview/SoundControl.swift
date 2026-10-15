import SwiftUI
import AVFoundation
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class SoundHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct SoundControlCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        let settings = AppSettings.shared
        settings.isMuted = false; settings.masterVolume = 0.6
        settings.stoneVolume = 0.25; settings.voiceVolume = 0.4
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SoundHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        let model = AppModel(ogsClient: client)
        func settle(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            (view as? T) ?? view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
        func player(_ name: String) -> AVAudioPlayer {
            Mirror(reflecting: model).children.first { $0.label == name }!.value as! AVAudioPlayer
        }
        let stones = [player("clickPlayer"), player("captureSinglePlayer"), player("captureMultiPlayer")]
        let voices = Mirror(reflecting: SoundManager.shared).children.first { $0.label == "players" }!.value as! [String: AVAudioPlayer]
        let voice = voices["game_started"]!
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: AppModeControls().environmentObject(model).frame(width: 1100, height: 100))
        window.orderFront(nil); settle()
        defer { window.orderOut(nil); settings.isMuted = true; client.disconnect() }
        guard let button = find(SoundHoldButton.self, in: window.contentView!) else { require(false, "Missing speaker button"); return }
        func click(hold: TimeInterval = 0.05) {
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            }
            let release = Timer(timeInterval: hold, repeats: false) { _ in NSApp.postEvent(event(.leftMouseUp), atStart: false) }
            RunLoop.main.add(release, forMode: .eventTracking)
            button.mouseDown(with: event(.leftMouseDown))
            release.invalidate(); settle()
        }
        require(stones.allSatisfy { abs($0.volume - 0.15) < 0.001 }, "Initial stone balance")
        click()
        require(settings.isMuted && stones.allSatisfy { $0.volume == 0 }, "Short click mutes all stones")
        click()
        require(!settings.isMuted && settings.masterVolume == 0.6, "Second click restores previous volume")
        click(hold: 0.65)
        require(!settings.isMuted && settings.masterVolume == 0.6, "Hold must not also toggle mute on release")
        func capture(_ view: NSView, to path: String) {
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        capture(window.contentView!, to: "/private/tmp/sgf-sound-toolbar.png")
        let popoverWindows = NSApp.windows.filter { $0 != window && $0.isVisible }
        if let view = popoverWindows.first?.contentView { capture(view, to: "/private/tmp/sgf-sound-popover.png") }
        guard let slider = popoverWindows.compactMap({ $0.contentView.flatMap { find(NSSlider.self, in: $0) } }).first else {
            require(false, "Hold did not reveal volume slider"); return
        }
        slider.doubleValue = 0.3; slider.sendAction(slider.action, to: slider.target); settle()
        require(abs(settings.masterVolume - 0.3) < 0.001, "Slider updates master volume")
        require(settings.stoneVolume == 0.25 && settings.voiceVolume == 0.4, "Master preserves stone/voice balance")
        require(stones.allSatisfy { abs($0.volume - 0.075) < 0.001 } && abs(voice.volume - 0.12) < 0.001, "Master reaches both audio paths")
        settings.isMuted = true
        slider.doubleValue = 0.4; slider.sendAction(slider.action, to: slider.target); settle()
        require(!settings.isMuted, "Raising slider unmutes")
        slider.doubleValue = 0; slider.sendAction(slider.action, to: slider.target); settle()
        button.performClick(nil); settle()
        require(!settings.isMuted && abs(settings.masterVolume - 0.4) < 0.001, "Click at zero restores last audible volume")
        require(UserDefaults.standard.double(forKey: "masterVolume") == settings.masterVolume, "Volume persists in probe domain")
        for popover in popoverWindows { popover.performClose(nil) }; settle()
        let right = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        button.rightMouseDown(with: right); settle()
        require(NSApp.windows.contains { $0 != window && $0.isVisible && $0.contentView.flatMap { find(NSSlider.self, in: $0) } != nil }, "Right click reveals slider")
        // Run actual audio players at zero individual volume to avoid audible tests.
        settings.stoneVolume = 0; settings.voiceVolume = 0
        model.viewMode = .view2D
        model.playSound(.place); SoundManager.shared.play("game_started")
        require(stones[0].isPlaying && voice.isPlaying, "Actual clips started silently")
        settings.isMuted = true
        require(stones.allSatisfy { !$0.isPlaying } && !voice.isPlaying, "Mute immediately stops active stone and voice clips")
        settings.isMuted = false; model.viewMode = .view3D
        model.playSound(.captureMultiple)
        settings.isMuted = true; settings.isMuted = false
        settle(0.6)
        require(stones.allSatisfy { !$0.isPlaying && $0.currentTime == 0 }, "Mute cancels pending 3D placement and capture sounds even after unmuting")
        settings.masterVolume = 0
        model.playSound(.place); SoundManager.shared.play("game_started"); settle(0.2)
        require(stones.allSatisfy { !$0.isPlaying } && !voice.isPlaying, "Zero master volume stays silent")
        print("PASS: Native click toggles mute; hold/right-click reveal slider without toggling; master preserves balance and saved level; all audio paths and pending 3D clips honor mute. Network denied; audio tests inaudible.")
    }
}
