import AppKit
import CoreImage

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
let source = CIImage(contentsOf: sourceURL)!
let repeated = source.transformed(by: CGAffineTransform(translationX: -source.extent.width, y: 0))
    .composited(over: source)
    .composited(over: source.transformed(by: CGAffineTransform(translationX: source.extent.width, y: 0)))
let size: CGFloat = 640
var records: [[String: Any]] = []
for (row, top) in [0, 247].enumerated() {
    for (column, x) in [-48, 567, 1134].enumerated() {
        let rect = CGRect(x: CGFloat(x), y: source.extent.height - CGFloat(top) - size, width: size, height: size)
        let tile = repeated.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let name = "tile-\(row)-\(column).png"
        try context.writePNGRepresentation(of: tile, to: outputURL.appendingPathComponent(name), format: .RGBA8, colorSpace: colorSpace)
        records.append(["file": name, "x": x, "top": top, "size": 640])
    }
}
try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: outputURL.appendingPathComponent("tiles.json"))
