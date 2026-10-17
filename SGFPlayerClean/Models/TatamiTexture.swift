import AppKit

/// Physical scale shared by the app and native screensaver. Approximately 64
/// weave divisions at 1.5 cm each fill this square; a Japanese board is 45.5 cm long.
/// Standard weave reference: https://www.warashibekobo.com/p/3/
enum TatamiTexture {
    static let assetName = "tatami-woven-v4-3008.png"
    static let tileCentimetres: CGFloat = 96
    static let boardLengthCentimetres: CGFloat = 45.5

    static func tileSide(boardHeight: CGFloat) -> CGFloat {
        boardHeight * tileCentimetres / boardLengthCentimetres
    }

    /// Reflect alternate repeats so every join uses identical edge pixels.
    /// A fixed origin prevents the floor sliding when the window gets wider.
    static func draw(image: NSImage?, in bounds: CGRect, boardHeight: CGFloat) {
        NSColor(calibratedRed: 0.54, green: 0.55, blue: 0.36, alpha: 1).setFill()
        bounds.fill()
        let side = tileSide(boardHeight: boardHeight)
        guard let image, side.isFinite, side > 0, !bounds.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.clip()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = false
        for row in 0..<Int(ceil(bounds.height / side)) {
            for column in 0..<Int(ceil(bounds.width / side)) {
                NSGraphicsContext.saveGraphicsState()
                let mirrorX = column % 2 == 1, mirrorY = row % 2 == 1
                let transform = NSAffineTransform()
                transform.translateX(by: bounds.minX + CGFloat(column + (mirrorX ? 1 : 0)) * side,
                                     yBy: bounds.minY + CGFloat(row + (mirrorY ? 1 : 0)) * side)
                transform.scaleX(by: mirrorX ? -1 : 1, yBy: mirrorY ? -1 : 1)
                transform.concat()
                image.draw(in: CGRect(x: 0, y: 0, width: side, height: side),
                           from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.high])
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

final class TatamiSurfaceView: NSView {
    var boardHeight: CGFloat = 455 { didSet { if oldValue != boardHeight { needsDisplay = true } } }
    var texture: NSImage? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        TatamiTexture.draw(image: texture, in: bounds, boardHeight: boardHeight)
    }
}
