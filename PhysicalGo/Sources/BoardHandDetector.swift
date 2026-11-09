import Vision
import CoreGraphics

/// A hand pose is an obstruction cue, not evidence that a legal move occurred.
/// Vision uses bottom-left coordinates; board calibration uses top-left.
enum BoardHandDetector {
    static func obstructed(image:CGImage,calibration:BoardCalibration)->Bool? {
        let request=VNDetectHumanHandPoseRequest();request.maximumHandCount=4
        do {
            try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
            for hand in request.results ?? [] {
                let points=try hand.recognizedPoints(.all)
                for point in points.values where point.confidence>=0.25 {
                    guard let grid=calibration.gridPoint(for:.init(x:point.location.x,y:1-point.location.y)) else {continue}
                    // Include the small wooden margin beyond the corner intersections.
                    if (-0.75...Double(calibration.size)-0.25).contains(grid.x),
                       (-0.75...Double(calibration.size)-0.25).contains(grid.y) {return true}
                }
            }
            return false
        } catch {return nil}
    }
}
