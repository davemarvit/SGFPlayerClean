import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}
private func require(_ condition: @autoclosure () -> Bool, _ message: String = "Check failed") {
    if !condition() { fail(message) }
}

@MainActor final class ObservationFixture: ObservableObject {
    let model: AppModel
    @Published var showSheet = false
    var started = false
    var sheetCompleted = false

    init() {
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe")
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        model = AppModel()
    }

    func ready() {
        model.ogsClient.username = "Review Fixture"
        model.ogsClient.isAuthenticated = true
        model.ogsClient.isSocketAuthenticated = true
        model.ogsClient.isConnected = true
    }

    func pressObserve(in window: NSWindow) {
        guard let host = window.contentView else { fail("Missing content view") }
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fail("Cannot capture view") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        do { try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request]) }
        catch { fail("Cannot locate Observe button: \(error)") }
        guard let label = request.results?.first(where: {
            $0.topCandidates(1).first?.string.lowercased() == "observe game"
        }) else { fail("Observe button text not found") }
        let box = label.boundingBox
        let point = NSPoint(x: host.bounds.width * box.midX,
                            y: host.bounds.height * (host.isFlipped ? 1 - box.midY : box.midY))
        let location = host.convert(point, to: nil)
        window.makeKeyAndOrderFront(nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: type, location: location,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { fail("Cannot make mouse event") }
            return event
        }
        // Mouse-down may enter a nested tracking loop; queue mouse-up first.
        NSApplication.shared.postEvent(event(.leftMouseUp), atStart: false)
        window.sendEvent(event(.leftMouseDown))
    }

    func check() async {
        guard !started else { return }
        started = true
        func settle() async { try? await Task.sleep(nanoseconds: 600_000_000) }
        await settle()
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
            fail("No main SwiftUI window")
        }
        ready()
        await settle()
        pressObserve(in: window)
        await settle()
        require(model.ogsClient.activeGameID == 7, "Sidebar did not run the real observation action")
        require(window.isVisible, "Sidebar Observe closed the main window")

        showSheet = true
        await settle()
        ready()
        await settle()
        guard let sheet = window.attachedSheet else { fail("Observation sheet missing") }
        pressObserve(in: sheet)
        await settle()
        require(model.ogsClient.activeGameID == 8 && sheetCompleted)
        require(!showSheet && window.attachedSheet == nil, "Observe sheet did not close")
        require(window.isVisible, "Sheet Observe closed the main window")
        model.ogsClient.disconnect()
        print("PASS: Actual Observe button presses in a SwiftUI WindowGroup keep the main window open; only the observation sheet closes. All networking denied.")
        exit(0)
    }
}

@main struct ObservationWindowCheck: App {
    @StateObject private var fixture = ObservationFixture()
    var body: some Scene {
        WindowGroup {
            OGSObservationBrowserView(gameLink: "7")
                .environmentObject(fixture.model)
                .frame(width: 480, height: 400)
                .sheet(isPresented: $fixture.showSheet) {
                    OGSObservationBrowserView(gameLink: "8", didObserve: {
                        fixture.sheetCompleted = true
                        fixture.showSheet = false
                    })
                    .environmentObject(fixture.model)
                    .frame(width: 480, height: 400)
                }
                .task { await fixture.check() }
        }
    }
}
