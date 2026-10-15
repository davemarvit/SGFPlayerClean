import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String = "Check failed") {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main struct ReviewUICheck {
    @MainActor static func main() throws {
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.stoneVolume = 0
        let model = AppModel()
        require(model.ogsClient.observationOnly, "Actual compiled review must default to observation only")
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.orderOut(nil); model.ogsClient.disconnect() }
        func render<V: View>(_ view: V) throws -> String {
            let host = NSHostingView(rootView: view.environmentObject(model))
            window.contentView = host
            window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ").lowercased()
        }
        let loggedOut = try render(OGSObservationBrowserView())
        require(loggedOut.contains("log in") && loggedOut.contains("observe game"), loggedOut)
        require(!loggedOut.contains("create challenge"), loggedOut)
        let login = try render(OGSLoginView(isPresented: .constant(true)))
        require(login.contains("login to ogs") && login.contains("password"), login)
        model.ogsClient.username = "Review Fixture"
        model.ogsClient.isAuthenticated = true
        model.ogsClient.isSocketAuthenticated = true
        let ready = try render(OGSObservationBrowserView())
        require(ready.contains("ready to observe") && ready.contains("review fixture"), ready)
        model.ogsClient.activeGameID = 7
        model.ogsClient.playerID = 1; model.ogsClient.blackPlayerID = 1
        require(!model.ogsClient.isGameParticipant)
        let active = try render(ActiveGamePanel())
        require(active.contains("game actions disabled"), active)
        require(!active.contains("resign") && !active.contains("say something"), active)
        print("PASS: Compiled OGS review is observation-only; login, game-link entry, ready status, and disabled game/chat UI render. All networking denied.")
    }
}
