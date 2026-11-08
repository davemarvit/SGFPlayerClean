import AppKit
import CoreImage

// Offline assembly of overlapping, AI-enhanced panorama tiles. Inputs are
// registered against the source before blending; the horizontal seam wraps.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let records = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("tiles.json"))) as! [[String: Any]]
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
let width = 3548, height = 1774, tileSize = 1280
var sum = [Float](repeating: 0, count: width * height * 3)
var weights = [Float](repeating: 0, count: width * height)
func smooth(_ lo: Double, _ hi: Double, _ value: Double) -> Float {
    let t = max(0, min(1, (value-lo)/(hi-lo)))
    return Float(t*t*(3-2*t))
}
for (index, record) in records.enumerated() {
    let name = record["file"] as! String
    let x = record["x"] as! Int, top = record["top"] as! Int
    let image = CIImage(contentsOf: folder.appendingPathComponent("aligned-" + name))!
    var pixels = [UInt8](repeating: 0, count: tileSize*tileSize*4)
    context.render(image, toBitmap: &pixels, rowBytes: tileSize*4,
        bounds: CGRect(x: 0, y: 0, width: tileSize, height: tileSize), format: .RGBA8, colorSpace: colorSpace)
    let column = index % 3
    let leftOverlap: Double = [48,25,73][column]
    let rightOverlap: Double = [25,73,48][column]
    for localY in 0..<tileSize {
        let worldY = top*2 + localY
        guard worldY >= 0 && worldY < height else { continue }
        let fromTop = Double(worldY)/2
        // Limit the long vertical overlap to a narrow, smooth blend centered
        // between rows. This avoids mixing different reconstructed details
        // over most of the image.
        let vertical = top == 0 ? 1-smooth(427.5,459.5,fromTop) : smooth(427.5,459.5,fromTop)
        if vertical == 0 { continue }
        for localX in 0..<tileSize {
            let worldX = (x*2 + localX + width) % width
            let horizontal = smooth(0,leftOverlap,Double(localX)/2)
                * smooth(0,rightOverlap,Double(tileSize-1-localX)/2)
            let weight = horizontal*vertical
            let dst = worldY*width+worldX, src = (localY*tileSize+localX)*4
            weights[dst] += weight
            for channel in 0..<3 { sum[dst*3+channel] += Float(pixels[src+channel])*weight }
        }
    }
}
var bytes = [UInt8](repeating: 255, count: width*height*4)
for i in weights.indices {
    precondition(weights[i] > 0, "Tile coverage has a hole at pixel \(i)")
    for c in 0..<3 { bytes[i*4+c] = UInt8(max(0,min(255,round(sum[i*3+c]/weights[i])))) }
}
let result = CIImage(bitmapData: Data(bytes), bytesPerRow: width*4,
    size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: colorSpace)
try context.writePNGRepresentation(of: result, to: output, format: .RGBA8, colorSpace: colorSpace)
print("Stitched full 360-degree panorama: \(width) x \(height) at \(output.path)")
