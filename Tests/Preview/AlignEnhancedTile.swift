import AppKit
import CoreImage
import Vision
import simd
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
let size: CGFloat = 1280
let reference = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 2.0])
let raw = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))!
let floating = raw.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: size/raw.extent.width])
let request = VNHomographicImageRegistrationRequest(targetedCIImage: floating)
try VNImageRequestHandler(ciImage: reference).perform([request])
let matrix = request.results!.first!.warpTransform
print(matrix)
func transform(_ m: simd_float3x3) -> CIImage {
 func point(_ x: Float, _ y: Float) -> CIVector {
  let p = m * SIMD3<Float>(x,y,1); return CIVector(x: CGFloat(p.x/p.z), y: CGFloat(p.y/p.z))
 }
 return floating.applyingFilter("CIPerspectiveTransform", parameters: ["inputTopLeft": point(0,1280), "inputTopRight": point(1280,1280), "inputBottomLeft": point(0,0), "inputBottomRight": point(1280,0)]).composited(over: reference).cropped(to: reference.extent)
}
func pixels(_ image: CIImage) -> [UInt8] {
 let small=image.applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:3.0]).transformed(by:CGAffineTransform(scaleX:0.1,y:0.1))
 var bytes=[UInt8](repeating:0,count:128*128*4)
 context.render(small,toBitmap:&bytes,rowBytes:128*4,bounds:CGRect(x:0,y:0,width:128,height:128),format:.RGBA8,colorSpace:colorSpace)
 return bytes
}
let target=pixels(reference)
func error(_ image: CIImage)->Double {
 let p=pixels(image); var sum=0.0
 for i in stride(from:0,to:p.count,by:4){for c in 0..<3 {let d=Double(p[i+c])-Double(target[i+c]);sum+=d*d}}
 return sum/Double(128*128*3)
}
let flip=simd_float3x3(columns:(SIMD3(1,0,0),SIMD3(0,-1,0),SIMD3(0,1280,1)))
let candidates=[matrix_identity_float3x3,matrix,matrix.inverse,flip*matrix*flip,flip*matrix.inverse*flip]
var best=floating;var bestError=error(floating)
for (i,m) in candidates.enumerated(){let out=transform(m), score=error(out);print(i,score);if score<bestError{best=out;bestError=score}}
// A tile that wraps the panorama has its join 48 source pixels from the left.
// Preserve an AI-repaired join instead of restoring the old color discontinuity.
let wrapRepair: Float = CommandLine.arguments.contains("--wrap-seam") ? 1 : 0
let kernel=CIColorKernel(source:"kernel vec4 restore(__sample high, __sample low, __sample reference, float wrap) { float correction = mix(1.0,smoothstep(24.0,96.0,abs(destCoord().x-96.0)),wrap); return vec4(clamp(high.rgb+(reference.rgb-low.rgb)*correction,0.0,1.0),1.0); }")!
let detail=kernel.apply(extent:reference.extent,arguments:[best,best.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:20.0]),reference.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:20.0]),wrapRepair])!
try context.writePNGRepresentation(of:detail,to:URL(fileURLWithPath:CommandLine.arguments[3]),format:.RGBA8,colorSpace:colorSpace)
