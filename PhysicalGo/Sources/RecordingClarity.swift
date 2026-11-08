import Foundation

/// Ordinary play shows stable, actionable conflicts. Raw classification flicker
/// remains available in diagnostics, and never overwrites recorded identities.
@MainActor enum RecordingClarity {
    static func checkPoints(readings:[Occupancy],base:[Occupancy],after:[Occupancy])->Set<Int> {
        Set(BoardAdjustmentMonitor.evidence(readings:readings,base:base,after:after).keys)
    }
    static func checkPoints(recorder:GameRecorder,observation:BoardObservation?)->Set<Int> {
        guard recorder.hasGame,recorder.state != .finished,!recorder.awaitingFirstStart else {return []}
        if let capture=recorder.pendingCaptureReview {return capture.remaining(in:recorder.reviewCameraPosition)}
        if let restoration=recorder.pendingBoardRestoration {return restoration.remaining(in:recorder.reviewCameraPosition)}
        return Set(recorder.adjustmentIssues.keys)
    }
    static func explanation(recorder:GameRecorder,observation:BoardObservation?,orientation:BoardOrientation)->String? {
        guard recorder.hasGame,recorder.state != .finished,!recorder.awaitingFirstStart else {return nil}
        if let capture=recorder.pendingCaptureReview {
            return capture.remaining(in:recorder.reviewCameraPosition).isEmpty
                ? "The captured stones appear removed. Choose Finish capture to verify and save the capturing move."
                : "Remove the orange-ringed captured stones and leave the capturing stone in place. Choose Finish capture to verify the removal."
        }
        if let restoration=recorder.pendingBoardRestoration {
            if case .displaced = restoration.kind {
                return "A recorded stone may have been bumped to a neighboring intersection. Choose Check moved stones to compare with the saved position."
            }
            return "Recorded stones are missing. Choose Check moved stones to restore accidental removals or review actual captures."
        }
        let issues=recorder.adjustmentIssues
        if issues.values.contains(.placement) {
            return "A stone’s intersection is ambiguous at the orange rings. Center the marked stones on their intended intersections. If already correct, use Check highlighted intersections to confirm the camera reading."
        }
        if issues.values.contains(.capture) {
            return "A capture needs checking at the orange rings. Remove captured stones and keep the capturing stone in place."
        }
        if issues.values.contains(.newMove) {
            return "The new stone at the orange ring needs a clearer view. Clear your hand; center it if it is between intersections."
        }
        if !issues.isEmpty {
            return "A persistent camera disagreement is marked with orange rings. Check those locations; if the physical board is correct, use Check highlighted intersections to confirm the camera reading. Recorded stones are retained."
        }
        if recorder.pendingMoveCount>0 {
            return "Checking the new move. Previously recorded stones are retained; no stone adjustment is currently needed."
        }
        return nil
    }
}
