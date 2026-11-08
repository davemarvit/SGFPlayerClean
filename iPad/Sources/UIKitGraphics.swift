import UIKit
import SwiftUI

// Narrow adapter for the shared SceneKit texture builders. All produced images
// are native UIImages; the Mac target continues to use AppKit directly.
typealias NSColor = UIColor
typealias NSImage = UIImage
typealias NSFont = UIFont
typealias NSSize = CGSize
typealias NSPoint = CGPoint
typealias NSBezierPath = UIBezierPath

extension UIColor {
    func blended(withFraction fraction: CGFloat, of other: UIColor) -> UIColor? {
        guard fraction.isFinite else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var otherR: CGFloat = 0, otherG: CGFloat = 0, otherB: CGFloat = 0, otherA: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a),
              other.getRed(&otherR, green: &otherG, blue: &otherB, alpha: &otherA) else { return nil }
        let amount = min(1, max(0, fraction)), remaining = 1 - amount
        return UIColor(red: r * remaining + otherR * amount, green: g * remaining + otherG * amount,
                       blue: b * remaining + otherB * amount, alpha: a * remaining + otherA * amount)
    }
    convenience init(srgbRed: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: srgbRed, green: green, blue: blue, alpha: alpha)
    }
}
extension UIImage {
    convenience init?(contentsOf url: URL) { self.init(contentsOfFile: url.path) }
    convenience init(cgImage: CGImage, size: CGSize) { self.init(cgImage: cgImage, scale: CGFloat(cgImage.width) / size.width, orientation: .up) }
    convenience init(size: CGSize, flipped: Bool, drawingHandler: (CGRect) -> Bool) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            if !flipped {
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
            }
            _ = drawingHandler(CGRect(origin: .zero, size: size))
        }
        self.init(cgImage: rendered.cgImage!)
    }
}
extension CGRect { func fill() { UIGraphicsGetCurrentContext()?.fill(self) } }
extension UIBezierPath {
    func line(to point: CGPoint) { addLine(to: point) }
    func appendArc(withCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool = false) {
        addArc(withCenter: center, radius: radius, startAngle: startAngle * .pi / 180, endAngle: endAngle * .pi / 180, clockwise: clockwise)
    }
}
struct NSGraphicsContext {
    let cgContext: CGContext
    static var current: NSGraphicsContext? { UIGraphicsGetCurrentContext().map { NSGraphicsContext(cgContext: $0) } }
}
final class NSBitmapImageRep {
    enum ColorSpaceName { case deviceRGB }
    private let context: CGContext
    var bitmapData: UnsafeMutablePointer<UInt8>? { context.data?.assumingMemoryBound(to: UInt8.self) }
    var cgImage: CGImage? { context.makeImage() }
    init?(bitmapDataPlanes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide: Int, pixelsHigh: Int,
          bitsPerSample: Int, samplesPerPixel: Int, hasAlpha: Bool, isPlanar: Bool,
          colorSpaceName: ColorSpaceName, bytesPerRow: Int, bitsPerPixel: Int) {
        guard bitsPerSample == 8, samplesPerPixel == 4, hasAlpha, !isPlanar, bitsPerPixel == 32,
              let context = CGContext(data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        self.context = context
    }
}
