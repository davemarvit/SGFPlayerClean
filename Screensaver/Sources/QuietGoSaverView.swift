import AppKit
import ScreenSaver
import QuartzCore

@objc(QuietGoSaverView)
final class QuietGoSaverView: ScreenSaverView {
    private var playlist: SaverPlaylist?
    private var configurationRoot = ScreensaverConfiguration.root
    private var generation: String?
    private var playbackEnabled = false
    private var lastConfigCheck: TimeInterval = 0
    private var configurationErrorReported = false
    // Apple can draw the view before startAnimation checks the saved folder.
    // That first frame is just tatami, not a premature setup/error message.
    private var configurationMessage = ""
    private var wood: NSImage?
    private var tatami: NSImage?
    private var blackStone: NSImage?
    private var whiteStone: NSImage?
    private var lids: [NSImage?] = []
    private var whiteVariants: [NSImage?] = []
    private let stoneShadow = NSGradient(colorsAndLocations:
        (NSColor.black.withAlphaComponent(0.48), 0.0),
        (NSColor.black.withAlphaComponent(0.42), 0.60),
        (NSColor.black.withAlphaComponent(0.13), 0.86),
        (NSColor.black.withAlphaComponent(0.0), 1.0))!
    private var stopObserver: NSObjectProtocol?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        prepare()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        prepare()
    }
    private func prepare() {
        animationTimeInterval = 0.2 // Board is redrawn only when a move changes.
        let bundle = Bundle(for: QuietGoSaverView.self)
        func image(_ name: String) -> NSImage? {
            bundle.url(forResource: name, withExtension: nil).flatMap { NSImage(contentsOf: $0) }
        }
        wood = image("board_kaya.jpg"); tatami = image("tatami.jpg")
        blackStone = image("stone_black.png"); whiteStone = image("stone_white.png")
        lids = [image("go_lid_1.png"), image("go_lid_2.png")]
        whiteVariants = (1...5).map { image(String(format: "clam_%02d.png", $0)) }
        stopObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main) { [weak self] _ in
            self?.stopAnimation()
        }
        SaverPlaylist.log.notice("View initialized; preview=\(self.isPreview, privacy: .public)")
    }
    deinit { if let stopObserver { DistributedNotificationCenter.default().removeObserver(stopObserver) } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func startAnimation() {
        super.startAnimation()
        SaverPlaylist.log.notice("Native animation started")
        refreshConfiguration(force: true)
        if playbackEnabled { playlist?.start(at: CACurrentMediaTime()) }
        needsDisplay = true
    }
    @objc func setConfigurationRoot(_ path: String) {
        playlist?.stop(); playlist = nil; generation = nil
        configurationRoot = URL(fileURLWithPath: path, isDirectory: true)
        refreshConfiguration(force: true)
    }
    private func refreshConfiguration(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastConfigCheck >= 1 else { return }
        lastConfigCheck = now
        do {
            let config = try ScreensaverConfiguration.load(root: configurationRoot)
            configurationErrorReported = false
            let changed = generation != config.generation
            if changed {
                playlist?.stop()
                playlist = SaverPlaylist(folder: config.libraryURL(root: configurationRoot)!)
                generation = config.generation
            }
            if config.enabled != playbackEnabled || changed {
                playbackEnabled = config.enabled
                if config.enabled && isAnimating { playlist?.start(at: now) }
                else { playlist?.stop() }
                needsDisplay = true
            }
            configurationMessage = "Quiet Go playback is off. Enable it in SGF Player’s Screensaver settings."
        } catch {
            if !configurationErrorReported {
                let failure = error as NSError
                SaverPlaylist.log.error("Cannot read playback configuration: \(failure.domain, privacy: .public) \(failure.code, privacy: .public); root=\(self.configurationRoot.path, privacy: .private)")
                configurationErrorReported = true
            }
            playlist?.stop(); playbackEnabled = false
            configurationMessage = "Choose a games folder in SGF Player’s Screensaver settings."
            needsDisplay = true
        }
    }
    override func stopAnimation() {
        playlist?.stop(); super.stopAnimation()
    }
    override func animateOneFrame() {
        guard isAnimating else { return }
        refreshConfiguration()
        if playbackEnabled, playlist?.advance(at: CACurrentMediaTime()) == true { needsDisplay = true }
    }
    // Read-only hooks let the standalone host test the actual installed bundle.
    @objc var displayedBoardSize: Int { playlist?.player.board.size ?? 0 }
    @objc var displayedMove: Int { playlist?.player.currentIndex ?? 0 }
    @objc var displayedGame: String { playlist?.file?.lastPathComponent ?? "" }
    @objc var loadedGameCount: Int { playlist?.files.count ?? 0 }
    @objc var playbackRunning: Bool { playlist?.running ?? false }
    @objc var displayedBlackCaptures: Int { playlist?.player.blackStonesCaptured ?? 0 }
    @objc var displayedWhiteCaptures: Int { playlist?.player.whiteStonesCaptured ?? 0 }
    @objc var displayedStatusMessage: String {
        playbackEnabled ? (playlist?.errorMessage ?? "") : configurationMessage
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.10, alpha: 1).setFill(); bounds.fill()
        tatami?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        guard playbackEnabled, let playlist, let game = playlist.game else {
            if !displayedStatusMessage.isEmpty {
                drawText(displayedStatusMessage, in: bounds.insetBy(dx: 20, dy: bounds.height * 0.45), size: max(12, bounds.width / 60))
            }
            return
        }
        let layout = SaverLayout(bounds: bounds)
        let board = layout.board, width = board.width
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = width * 0.02; shadow.shadowOffset = .zero; shadow.set()
        NSColor.black.setFill()
        board.insetBy(dx: width * 0.012, dy: width * 0.012)
            .offsetBy(dx: width * 0.012, dy: width * 0.012).fill()
        NSGraphicsContext.restoreGraphicsState()
        wood?.draw(in: board, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let grid = board.insetBy(dx: width * 0.065, dy: width * 0.065)
        let pitchX = grid.width / CGFloat(game.boardSize - 1), pitchY = grid.height / CGFloat(game.boardSize - 1)
        func point(_ p: BoardPosition) -> NSPoint { NSPoint(x: grid.minX + CGFloat(p.col) * pitchX, y: grid.minY + CGFloat(p.row) * pitchY) }
        let lines = NSBezierPath(); lines.lineWidth = max(0.4, width / 1200)
        for i in 0..<game.boardSize {
            let x = grid.minX + CGFloat(i) * pitchX, y = grid.minY + CGFloat(i) * pitchY
            lines.move(to: NSPoint(x: x, y: grid.minY)); lines.line(to: NSPoint(x: x, y: grid.maxY))
            lines.move(to: NSPoint(x: grid.minX, y: y)); lines.line(to: NSPoint(x: grid.maxX, y: y))
        }
        NSColor.black.withAlphaComponent(0.75).setStroke(); lines.stroke()
        let stars: [Int] = game.boardSize == 19 ? [3,9,15] : game.boardSize == 13 ? [3,6,9] : game.boardSize == 9 ? [2,4,6] : []
        NSColor.black.setFill()
        for r in stars { for c in stars {
            if game.boardSize != 19 && (r == stars[1]) != (c == stars[1]) { continue }
            let p = point(BoardPosition(r,c)), radius = width * 0.004
            NSBezierPath(ovalIn: NSRect(x: p.x-radius, y: p.y-radius, width: radius*2, height: radius*2)).fill()
        } }
        let diameter = pitchX * 0.97
        // Place the shadow itself in flipped view coordinates (down and right).
        // NSShadow's vertical offset can differ between Apple's layer-backed
        // screensaver host and bitmap preview rendering. A radial falloff has
        // the same direction in both contexts, opposite the upper-left highlight.
        for position in playlist.player.board.stones.keys {
            drawStoneShadow(at: point(position), diameter: diameter)
        }
        for (position, color) in playlist.player.board.stones {
            let p = point(position), rect = NSRect(x: p.x-diameter/2, y: p.y-diameter/2, width: diameter, height: diameter)
            if let image = color == .black ? blackStone : whiteStone {
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else {
                (color == .black ? NSColor.black : .white).setFill(); NSBezierPath(ovalIn: rect).fill()
            }
        }
        if let move = playlist.player.lastMove, move.x >= 0, move.y >= 0,
           playlist.player.board.stones[BoardPosition(move.y,move.x)] == move.color {
            let p = point(BoardPosition(move.y,move.x)), radius = diameter * 0.09
            NSColor.systemRed.setFill(); NSBezierPath(ovalIn: NSRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2)).fill()
        }
        drawLid(in: layout.blackLid, white: false, count: displayedBlackCaptures, seed: playlist.player.captureSeed)
        drawLid(in: layout.whiteLid, white: true, count: displayedWhiteCaptures, seed: playlist.player.captureSeed)
        let title = "● \(game.info.playerBlack ?? "Black")   ○ \(game.info.playerWhite ?? "White")   ·   \(playlist.player.currentIndex)/\(playlist.player.maxIndex)"
        drawText(title, in: layout.caption, size: max(9, min(18, bounds.width / 70)))
    }
    private func drawStoneShadow(at point: NSPoint, diameter: CGFloat) {
        let center = NSPoint(x: point.x + diameter * 0.085, y: point.y + diameter * 0.085)
        stoneShadow.draw(fromCenter: center, radius: 0, toCenter: center, radius: diameter * 0.56, options: [])
    }
    private func drawLid(in rect: NSRect, white: Bool, count: Int, seed: UInt64) {
        let image = lids[white ? 1 : 0]
        // The asset's transparent border leaves room for a soft, down-right shadow.
        drawStoneShadow(at: NSPoint(x: rect.midX, y: rect.midY), diameter: rect.width * 0.84)
        image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        let pile = CapturePileLayout.stones(count: count,
            seed: CapturePileLayout.lidSeed(game: seed, whiteStones: white))
        let diameter = rect.width * 0.15 * (white ? 0.995 : 1.015)
        // Draw from low to high so a new stone can rest on the existing pile.
        for stone in pile.sorted(by: { $0.height < $1.height }) {
            let center = NSPoint(x: rect.midX + stone.x * rect.width, y: rect.midY + stone.y * rect.height)
            drawStoneShadow(at: center, diameter: diameter)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byDegrees: stone.angle * 0.08 - 14.4)
            transform.scaleX(by: 1, yBy: stone.tilt); transform.concat()
            let image = white ? (whiteVariants[Int(stone.angle) % 5] ?? whiteStone) : blackStone
            image?.draw(in: NSRect(x: -diameter/2, y: -diameter/2, width: diameter, height: diameter), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        }
        let fontSize = max(9, min(16, rect.width * 0.065))
        let label = String(max(0, count))
        let textWidth = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)]).width
        let badge = NSRect(x: rect.maxX - textWidth - 14, y: rect.maxY - fontSize - 8, width: textWidth + 12, height: fontSize + 7)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
        drawText(label, in: badge.insetBy(dx: 4, dy: 2), size: fontSize)
    }
    private func drawText(_ text: String, in rect: NSRect, size: CGFloat) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let shadow = NSShadow(); shadow.shadowColor = .black; shadow.shadowBlurRadius = 3
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .shadow: shadow])
    }
}
