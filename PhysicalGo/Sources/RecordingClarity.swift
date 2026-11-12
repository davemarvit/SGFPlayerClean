import Foundation

/// Ordinary play shows stable, actionable conflicts. Raw classification flicker
/// remains available in diagnostics, and never overwrites recorded identities.
@MainActor enum RecordingClarity {
    enum Action:Equatable {
        case review(UUID)
        case pendingPlacement(number:Int)
        case missedMoves(point:Int)
        case recordedPlacement(number:Int)
    }
    /// One policy for board clicks and the highlighted-stone review button.
    /// Camera-only detections are not pending placement ambiguities.
    static func action(at point:Int,recorder:GameRecorder)->Action {
        if let capture=recorder.pendingCaptureReview,capture.captured.union([capture.point]).contains(point) {return .review(capture.id)}
        if let restoration=recorder.pendingBoardRestoration,restoration.changed.contains(point) {return .review(restoration.id)}
        if let section=recorder.reviewHistory.sections.last(where:{!$0.committed && $0.moves == nil && $0.before.indices.contains(point) && $0.before[point] != $0.after[point]}) {return .review(section.id)}
        let history=recorder.tentativeHistory
        if let path=history.bestCandidate,let offset=path.moves.indices.last(where:{
            path.moves[$0]==point || (path.locationChoices[$0]?.contains(point) ?? false)
        }) {return .pendingPlacement(number:recorder.moveCount+offset+1)}
        let position=BoardPosition(point/recorder.game.boardSize,point%recorder.game.boardSize)
        if let number=HistoricalMoveCorrection.moveNumber(at:position,through:recorder.moveCount,game:recorder.game,positions:recorder.positions) {return .recordedPlacement(number:number)}
        return .missedMoves(point:point)
    }
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
        let cameraOnly=InterpretationDetectionMarks.make(board:recorder.interpretedBoard,observation:observation,size:recorder.game.boardSize)
            .filter{$0.kind == .untracked && issues[$0.point] != nil}
        if !cameraOnly.isEmpty {
            return "The translucent stones are camera detections outside the retained move sequence. Click a marked stone to review the missing moves, then accept the sequence. Existing pending moves are included."
        }
        if issues.values.contains(.placement) {
            return "A stone’s intersection is ambiguous at the orange rings. Center the marked stones on their intended intersections. Click a marked stone to confirm its intended location."
        }
        if issues.values.contains(.capture) {
            return "A capture needs checking at the orange rings. Remove captured stones and keep the capturing stone in place."
        }
        if issues.values.contains(.newMove) {
            return "The new stone at the orange ring needs a clearer view. Clear your hand; center it if it is between intersections."
        }
        if !issues.isEmpty {
            return "A persistent camera disagreement is marked with orange rings. Click a marked stone to review its recorded placement. Keep correctly placed physical stones where they are; change the game record only if it is wrong."
        }
        if recorder.pendingMoveCount>0 {
            return "Checking the new move. Previously recorded stones are retained; no stone adjustment is currently needed."
        }
        return nil
    }
}
