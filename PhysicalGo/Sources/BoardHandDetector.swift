import Vision
import CoreGraphics

/// A hand pose is an obstruction cue, not evidence that a legal move occurred.
/// Vision uses bottom-left coordinates; board calibration uses top-left.
enum BoardHandDetector {
    static func obstructed(image:CGImage,calibration:BoardCalibration)->Bool? {
        pose(image:image,calibration:calibration)?.obstructed(size:calibration.size)
    }
    static func pose(image:CGImage,calibration:BoardCalibration)->HandMotionPose? {
        let request=VNDetectHumanHandPoseRequest();request.maximumHandCount=4
        do {
            try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
            var hands=[[HandMotionPose.Point]]()
            for hand in request.results ?? [] {
                let points=try hand.recognizedPoints(.all)
                var joints=[HandMotionPose.Point]()
                for (name,point) in points where point.confidence>=0.25 {
                    guard let grid=calibration.gridPoint(for:.init(x:point.location.x,y:1-point.location.y)) else {continue}
                    joints.append(.init(id:name.rawValue.rawValue,x:grid.x,y:grid.y,confidence:Double(point.confidence)))
                }
                hands.append(joints)
            }
            return HandMotionPose(hands:hands,reliable:hands.allSatisfy{$0.count>=8})
        } catch {return nil}
    }
}
