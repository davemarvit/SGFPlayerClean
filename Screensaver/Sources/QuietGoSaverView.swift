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
    private var configurationMessage = "Choose a games folder in SGF Player’s Screensaver settings."
    private var wood: NSImage?
    private var tatami: NSImage?
    private var blackStone: NSImage?
    private var whiteStone: NSImage?
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

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.10, alpha: 1).setFill(); bounds.fill()
        tatami?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        guard playbackEnabled, let playlist, let game = playlist.game else {
            drawText(playbackEnabled ? (playlist?.errorMessage ?? "Loading games…") : configurationMessage, in: bounds.insetBy(dx: 20, dy: bounds.height * 0.45), size: max(12, bounds.width / 60))
            return
        }
        let width = max(1, min(bounds.width * 0.88, max(1, bounds.height - 34) * 0.96 / 1.0773))
        let height = width * 1.0773
        let board = NSRect(x: (bounds.width - width) / 2, y: max(2, (bounds.height - height - 24) / 2), width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = width * 0.02; shadow.shadowOffset = NSSize(width: width * 0.012, height: -width * 0.012); shadow.set()
        NSColor(calibratedRed: 0.8, green: 0.6, blue: 0.3, alpha: 1).setFill(); board.fill()
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
        NSGraphicsContext.saveGraphicsState()
        let stoneShadow = NSShadow()
        stoneShadow.shadowColor = NSColor.black.withAlphaComponent(0.48)
        stoneShadow.shadowBlurRadius = max(0.8, diameter * 0.09)
        stoneShadow.shadowOffset = NSSize(width: diameter * 0.085, height: diameter * 0.085)
        stoneShadow.set()
        NSColor.black.setFill()
        for position in playlist.player.board.stones.keys {
            let p = point(position), d = diameter * 0.94
            NSBezierPath(ovalIn: NSRect(x: p.x-d/2, y: p.y-d/2, width: d, height: d)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
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
        let title = "● \(game.info.playerBlack ?? "Black")   ○ \(game.info.playerWhite ?? "White")   ·   \(playlist.player.currentIndex)/\(playlist.player.maxIndex)"
        drawText(title, in: NSRect(x: bounds.width * 0.05, y: board.maxY + 7, width: bounds.width * 0.9, height: max(18, bounds.height * 0.035)), size: max(9, min(18, bounds.width / 70)))
    }
    private func drawText(_ text: String, in rect: NSRect, size: CGFloat) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let shadow = NSShadow(); shadow.shadowColor = .black; shadow.shadowBlurRadius = 3
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .shadow: shadow])
    }
}
