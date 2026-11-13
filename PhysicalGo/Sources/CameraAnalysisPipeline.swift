import Foundation
import CoreGraphics

/// Processes immutable camera snapshots off the main thread. It has no game,
/// clock, persistence or UI dependencies. ExperimentModel checks its revision
/// before applying a result, so a stopped or reconfigured session stays isolated.
final class CameraAnalysisPipeline {
    struct Input {
        let target: CGImage
        let calibration: BoardCalibration
        let threshold: Double
        let reference: GrayFrame?
        let referenceCalibration: BoardCalibration?
        let straighten: Bool
        let longAxisRows: Bool
        let checkStoneAspect: Bool
        let previousStoneCount: Int
        let pendingAxis: Bool?
        let trackingAnchor: AutoGridDetector.TrackingAnchor?
        let alignmentExpected: [Occupancy]
        let checkAlignment: Bool
        let trackingState: EstablishedStoneTracker
        let trackingExpected: [Occupancy]
        let trackingContext: String
        let trackingManualPoints: Set<Int>
        let trackingFresh: Bool
        let trackingTime: Double
        var checkHands=false
        var handTracking=HandOutlineTracker()
        var handTimestampSource="callback"
        var emptyLighting=KnownEmptyLighting()
        var lightingContext:String?
    }
    struct Output {
        let handPose:HandMotionPose?
        let handObstructed:Bool?
        let handOutline:HandOutlineTracker.Result?
        let handTracking:HandOutlineTracker
        let frame: GrayFrame?
        let exposureFailure: Bool
        let alignmentReport: [String:Any]
        let aligned: BoardCalibration?
        let result: BoardObservation?
        let trackedObservation: BoardObservation?
        let trackingResult: EstablishedStoneTracker
        let stoneAspect: StoneAspectEstimator.Estimate?
        let applyAspect: Bool
        let geometry: BoardRectifiedGeometry?
        let corrected: CGImage?
        let emptyLighting:KnownEmptyLighting
        let rawResult:BoardObservation?
    }
    private let queue = DispatchQueue(label: "PhysicalGo.detection", qos: .userInitiated)
    func submit(_ input: Input, completion: @escaping @MainActor (Output) -> Void) {
        queue.async {
            let output = Self.process(input)
            DispatchQueue.main.async { completion(output) }
        }
    }
    static func process(_ input: Input) -> Output {
        let target = input.target
        let calibration = input.calibration
        let threshold = input.threshold
        let reference = input.reference
        let referenceCalibration = input.referenceCalibration
        let straighten = input.straighten
        let longAxisRows = input.longAxisRows
        let checkStoneAspect = input.checkStoneAspect
        let previousStoneCount = input.previousStoneCount
        let pendingAxis = input.pendingAxis
        let trackingAnchor = input.trackingAnchor
        let alignmentExpected = input.alignmentExpected
        let checkAlignment = input.checkAlignment
        let trackingState = input.trackingState
        let trackingExpected = input.trackingExpected
        let trackingContext = input.trackingContext
        let trackingManualPoints = input.trackingManualPoints
        let trackingFresh = input.trackingFresh
        let trackingTime = input.trackingTime
        let handPose=input.checkHands ? BoardHandDetector.pose(image:target,calibration:calibration):nil
        let frame=GrayFrame(image:target)
        let exposureFailure=frame.map {LightingCompensation.exposureFailure(frame:$0,calibration:calibration)} ?? false
        var alignmentReport:[String:Any]=["outcome":checkAlignment ? "unavailable":"tracking disabled"]
        let aligned:BoardCalibration? = exposureFailure ? nil : checkAlignment
            ? frame.flatMap { frame in trackingAnchor.flatMap { AutoGridDetector.track(frame:frame,from:calibration,anchor:$0,expected:alignmentExpected,report:{alignmentReport=$0}) } } : calibration
        if checkAlignment,aligned==nil,alignmentReport["rejectionReason"]==nil {
            alignmentReport["rejectionReason"]=frame==nil ? "camera frame decoding failed":"tracking anchor unavailable"
        }
        var handTracking=input.handTracking
        let handOutline:HandOutlineTracker.Result?
        if input.checkHands,input.trackingFresh,let frame,!exposureFailure,
           aligned != nil || BoardAlignmentGate.likelyObstruction(alignmentReport) {
            handOutline=handTracking.observe(HandOutlineSampling.sample(frame,calibration:aligned ?? calibration),
                pose:handPose,at:trackingTime,source:input.handTimestampSource)
        } else {handTracking.reset();handOutline=nil}
        let handObstructed=handOutline != nil ? handOutline!.obstructed:handPose?.obstructed(size:calibration.size)
        var result:BoardObservation? = exposureFailure
            ? BoardObservation(readings:(0..<calibration.size*calibration.size).map {
                .init(row:$0/calibration.size,col:$0%calibration.size,occupancy:.uncertain,confidence:0,delta:0)
            },size:calibration.size,notice:"The board is too dark or overexposed to read.",lightingBlocked:true)
            : aligned.flatMap { current in
            frame.flatMap { frame -> BoardObservation? in
                if let reference {
                    return BoardDetector.detect(frame:frame,reference:reference,calibration:current,
                        threshold:threshold,referenceCalibration:referenceCalibration)
                }
                return BoardAppearanceDetector.detect(frame:frame,calibration:current,threshold:threshold)
            }
        }
        let rawResult=result
        var emptyLighting=input.emptyLighting
        if let raw=result,let frame,let aligned {
            result=emptyLighting.observe(raw,frame:frame,calibration:aligned,expected:trackingExpected,
                context:input.lightingContext ?? trackingContext,now:trackingTime,
                valid:trackingFresh && handObstructed != true && trackingManualPoints.isEmpty,
                appearanceThreshold:threshold)
        } else {emptyLighting.suspend()}
        var tracker=trackingState
        let trackedObservation:BoardObservation?
        if var raw=result {
            raw.manualPoints.formUnion(trackingManualPoints)
            trackedObservation=tracker.observe(raw,expected:trackingExpected,context:trackingContext,
                now:trackingTime,valid:trackingFresh && aligned != nil)
        } else {tracker.reset();trackedObservation=nil}
        let trackingResult=tracker
        let stoneAspect:StoneAspectEstimator.Estimate?
        if checkStoneAspect,let frame,let aligned,let result,!result.lightingBlocked {
            stoneAspect=StoneAspectEstimator.estimate(frame:frame,calibration:aligned,readings:result.readings)
        } else { stoneAspect=nil }
        // Changing an established stone-based choice needs agreement on a second check.
        let applyAspect=stoneAspect.map { previousStoneCount==0 || $0.longAxisRows==longAxisRows || pendingAxis==$0.longAxisRows } ?? false
        let displayRows=applyAspect ? stoneAspect!.longAxisRows : longAxisRows
        // Presentation can keep the last established transform while alignment
        // is checked. This renders the CURRENT pixels; it does not authorize
        // recognition or recording from an unverified frame (both remain nil).
        let geometry = straighten ? BoardRectifiedGeometry(calibration:aligned ?? calibration,longAxisRows:displayRows) : nil
        let corrected = geometry.flatMap { BoardRectifier.render(target,geometry:$0) }
        return Output(handPose:handPose,handObstructed:handObstructed,handOutline:handOutline,handTracking:handTracking,frame: frame, exposureFailure: exposureFailure, alignmentReport: alignmentReport, aligned: aligned, result: result, trackedObservation: trackedObservation, trackingResult: trackingResult, stoneAspect: stoneAspect, applyAspect: applyAspect, geometry: geometry, corrected: corrected,emptyLighting:emptyLighting,rawResult:rawResult)
    }
}
