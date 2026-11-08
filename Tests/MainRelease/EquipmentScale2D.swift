import SwiftUI
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

// The probe deliberately cannot activate itself. Let the hosted board accept
// its synthetic first click, as it would in the user's already-active window.
private final class ClickableHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@main struct EquipmentScale2DCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.isMuted = true; AppSettings.shared.folderURL = nil
        let app = AppModel(); app.aiAnalysisEnabled = false; app.showRightPanel = false
        app.viewMode = .view2D
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let output = URL(fileURLWithPath: "/private/tmp/sgf-equipment-scale-2d")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        // Measure real artwork after SwiftUI layout, including all five clam images.
        for color in [Stone.black, .white] {
            for seed in 0..<(color == .black ? 1 : 5) {
                let diameter: CGFloat = color == .black ? 22.2 : 21.9
                let renderer = ImageRenderer(content: StoneView2D(color: color, seedOverride: seed, showsShadow: false)
                    .frame(width: diameter * 4, height: diameter * 4))
                renderer.scale = 2
                let image = renderer.cgImage!
                let bitmap = NSBitmapImageRep(cgImage: image)
                var minX = image.width, maxX = 0
                for y in 0..<image.height { for x in 0..<image.width {
                    if bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.5 {
                        minX = min(minX, x); maxX = max(maxX, x)
                    }
                } }
                require(abs(CGFloat(maxX - minX + 1) - diameter * 8) < 2, "Visible \(color) variant \(seed) matches its physical diameter")
            }
        }

        for area in [CGSize(width: 1200, height: 850), CGSize(width: 800, height: 1000), CGSize(width: 1800, height: 1000)] {
            let layout = ContentView2D.getLayout(area: area)
            let scale = layout.bW / 424.2
            let grid = GoEquipmentDimensions2D.gridRect(in: CGSize(width: layout.bW, height: layout.bH))
            require(abs(grid.width / 18 / scale - 22) < 0.001, "22 mm horizontal grid spacing")
            require(abs(grid.height / 18 / scale - 23.7) < 0.001, "23.7 mm vertical grid spacing")
            require(abs(layout.bowlD / scale - 185) < 0.001, "Bowl sprite retains calibrated physical projection")
            require(abs(layout.lidD / scale - 138.75) < 0.001, "Matching 13.875 cm lids")
            require(layout.bW + 2 * (layout.bowlD + layout.gap) <= area.width, "Full equipment columns fit")
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.orderOut(nil) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        func load(_ size: Int) throws {
            let sgf = "(;SZ[\(size)]AB[ba][ab][bc]AW[bb][ca][db][cc];B[cb];W[dd];B[ee];W[ff])"
            let game = SGFGame.from(tree: try SGFParser.parse(text: sgf))
            let url = output.appendingPathComponent("fixture-\(size).sgf")
            try sgf.write(to: url, atomically: true, encoding: .utf8)
            app.selectGame(SGFGameWrapper(url: url, game: game)); settle()
            app.boardVM!.goToEnd(); settle()
        }
        for boardSize in [19, 13, 9] {
            try load(boardSize)
            let host = NSHostingView(rootView: ContentView2D().environmentObject(app))
            window.contentView = host; window.orderFront(nil)
            for area in [CGSize(width: 1200, height: 850), CGSize(width: 800, height: 1000)] {
                window.setContentSize(area); settle(); host.layoutSubtreeIfNeeded()
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("board-\(boardSize)-\(Int(area.width)).png"))
            }
        }

        try load(19)
        let workspace = NSHostingView(rootView: BoardWorkspaceView(vm: app.boardVM!) {
            ContentView2D()
        }.environmentObject(app))
        window.contentView = workspace
        for area in [CGSize(width: 1200, height: 850), CGSize(width: 1800, height: 1000)] {
            window.setContentSize(area); settle(); workspace.layoutSubtreeIfNeeded()
            let bitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds)!
            workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("workspace-\(Int(area.width)).png"))
        }

        // Keep the capture component mounted while its player rewinds.
        let player = app.boardVM!.engine
        let captureHost = NSHostingView(rootView: PlayerCaptureLidView(player: player, stoneColor: .white,
            stoneSize: 44.4, lidNumber: 2, lidSize: 277.5))
        window.contentView = captureHost; window.setContentSize(CGSize(width: 320, height: 320))
        func capturePixels() -> Data {
            settle(); captureHost.layoutSubtreeIfNeeded()
            let bitmap = captureHost.bitmapImageRepForCachingDisplay(in: captureHost.bounds)!
            captureHost.cacheDisplay(in: captureHost.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])!
        }
        require(player.capturesByBlack == 1, "Fixture captures one white stone")
        let captured = capturePixels()
        player.seek(to: 0); let empty = capturePixels()
        require(captured != empty, "Rewind removes the displayed prisoner")
        player.seek(to: 4)
        require(capturePixels() == captured, "Replaying restores the exact same capture pixels")

        // Real native clicks on all four outer intersections after the margin change.
        let emptyGame = SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19])"))
        let emptyURL = output.appendingPathComponent("empty.sgf")
        try "(;SZ[19])".write(to: emptyURL, atomically: true, encoding: .utf8)
        app.selectGame(SGFGameWrapper(url: emptyURL, game: emptyGame)); settle()
        app.copyCurrentBoard(to: .localPlay); settle()
        let size = CGSize(width: 848.4, height: 909)
        window.setContentSize(size)
        let board = ClickableHost(rootView: BoardView2D(boardVM: app.boardVM!, layoutVM: app.layoutVM, size: size).environmentObject(app))
        window.contentView = board; window.setContentSize(size); window.makeKeyAndOrderFront(nil); settle()
        for (column, row) in [(0,0), (18,0), (0,18), (18,18), (9,9)] {
            let point = CGPoint(x: 28.2 + CGFloat(column) * 44, y: 27.9 + CGFloat(row) * 47.4)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: board.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
                if let queued = NSApp.nextEvent(matching: type == .leftMouseDown ? .leftMouseDown : .leftMouseUp, until: Date().addingTimeInterval(0.1), inMode: .default, dequeue: true) {
                    NSApp.sendEvent(queued)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            settle()
            require(app.boardVM!.engine.board.stones[BoardPosition(row, column)] != nil, "Click reaches intersection \(column),\(row)")
        }
        print("PASS: six rendered stone variants, physical grid/equipment at three window sizes, 19/13/9 previews, capture rewind/replay, and native edge/centre clicks")
    }
}
