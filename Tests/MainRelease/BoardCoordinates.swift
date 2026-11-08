import SwiftUI
import SceneKit
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct BoardCoordinatesCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        let settings = AppSettings.shared
        settings.folderURL = nil; settings.isMuted = true
        settings.showBoardCoordinates = false
        let app = AppModel()
        app.aiAnalysisEnabled = false
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let output = URL(fileURLWithPath: "/private/tmp/sgf-board-coordinates")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 960), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.orderFront(nil); defer { window.orderOut(nil) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
        func capture(_ host: NSView, _ name: String) throws -> NSBitmapImageRep {
            settle(); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            return bitmap
        }
        let scene = SceneManager3D()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene.scene; renderer.pointOfView = scene.cameraNode
        require((0..<19).map(GoBoardCoordinates.column).joined() == "ABCDEFGHJKLMNOPQRST", "19 columns skip I")
        for size in [9, 13, 19] {
            let fixture = "(;SZ[\(size)]AB[aa][ai][ia])"
            let url = output.appendingPathComponent("fixture.sgf")
            try fixture.write(to: url, atomically: true, encoding: .utf8)
            app.selectGame(SGFGameWrapper(url: url, game: SGFGame.from(tree: try SGFParser.parse(text: fixture))))
            app.mode = .review
            let vm = app.boardVM!
            scene.updateBoardSize(size)
            scene.updateBoardCoordinates(true)
            func coordinateGroup() -> SCNNode? { scene.scene.rootNode.childNode(withName: "board-coordinates", recursively: true) }
            let group = coordinateGroup()!
            require(group.childNodes.count == size * 4, "Four labeled edges for \(size)")
            let leftNumbers = group.childNodes.filter { $0.name == "board-coordinate-1" }
            require(leftNumbers.count == 2 && leftNumbers.allSatisfy { $0.position.z > 0 }, "Row 1 is bottom")
            require(group.childNodes.filter { $0.name == "board-coordinate-\(size)" }.allSatisfy { $0.position.z < 0 }, "Largest row is top")
            let positions = group.childNodes.map(\.position)
            scene.updateBoardCoordinates(true)
            require(coordinateGroup() === group, "Repeated updates reuse labels")
            scene.updateEnvironment(.coffeeShop, flicker: false, motion: false)
            require(coordinateGroup()?.childNodes.count == size * 4, "Labels survive rebuilt board")
            scene.updateCameraPosition(distance: 31, rotationX: 0.45, rotationY: 0, panX: 0, panY: 0)
            scene.updateStones(from: vm.displayedStones, lastMove: nil, moveIndex: 0, settings: settings, animate: false)
            SCNTransaction.flush(); settle()
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1100, height: 1000), antialiasingMode: .multisampling4X)
            try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("3d-\(size).png"))
            require(positions.count == size * 4, "All labels positioned")
            scene.updateBoardCoordinates(false)
            require(coordinateGroup() == nil, "Turning off removes all 3D labels")
            scene.updateBoardSize(size == 19 ? 9 : 19)
            require(coordinateGroup() == nil, "Hidden stays hidden after resize")

            let boardSize = CGSize(width: 820, height: 880)
            let host = NSHostingView(rootView: BoardView2D(boardVM: vm, layoutVM: app.layoutVM, size: boardSize).environmentObject(app).frame(width: 900, height: 960))
            window.contentView = host
            settings.showBoardCoordinates = false
            let off = try capture(host, "2d-\(size)-off")
            settings.showBoardCoordinates = true
            require(UserDefaults.standard.bool(forKey: "showBoardCoordinates"), "Enabled preference saved")
            let on = try capture(host, "2d-\(size)-on")
            require(on.representation(using: .png, properties: [:]) != off.representation(using: .png, properties: [:]), "Existing 2D view redraws on toggle")
            let rect = BoardView2D.gridRect(in: boardSize, boardSize: size, showsCoordinates: true)
            let pitch = rect.width / CGFloat(size - 1)
            require(rect.minX >= pitch * 1.09, "Labels fit in margin away from edge stones")
            settings.showBoardCoordinates = false
            require(!UserDefaults.standard.bool(forKey: "showBoardCoordinates"), "Disabled preference saved")
            let restored = try capture(host, "2d-\(size)-restored")
            require(restored.representation(using: .png, properties: [:]) == off.representation(using: .png, properties: [:]), "Turning off restores exact board appearance")
        }
        UserDefaults.standard.set(true, forKey: "settings.playback.expanded")
        UserDefaults.standard.set(false, forKey: "settings.environment.expanded")
        let host = NSHostingView(rootView: Color.black.overlay { SettingsPanel(app: app, isPresented: .constant(true)) })
        window.contentView = host
        let bitmap = try capture(host, "settings")
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
        let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        require(words.contains("Show Board Coordinates"), "Playback setting is visible")
        let label = request.results!.first { $0.topCandidates(1).first?.string == "Show Board Coordinates" }!
        let box = label.boundingBox
        let point = NSPoint(x: host.bounds.width * box.maxX + 25,
                            y: host.bounds.height * (host.isFlipped ? 1 - box.midY : box.midY))
        let location = host.convert(point, to: nil)
        for expected in [true, false] {
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            }
            NSApplication.shared.postEvent(event(.leftMouseUp), atStart: false)
            window.sendEvent(event(.leftMouseDown)); window.sendEvent(event(.leftMouseUp)); settle()
            require(settings.showBoardCoordinates == expected, "Actual Playback switch changes preference")
        }
        print("PASS: coordinate convention, four edges, 9/13/19, saved toggle, live 2D redraw/removal, 3D removal/rebuild, margin clearance and settings UI")
    }
}
