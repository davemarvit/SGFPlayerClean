import Foundation

/// Ordinary play shows stable, actionable conflicts. Raw classification flicker
/// remains available in diagnostics, and never overwrites recorded identities.
@MainActor enum RecordingClarity {
    typealias Action = LivePositionIssue.Action
    /// One policy for board clicks and the highlighted-stone review button.
    /// Camera-only detections are not pending placement ambiguities.
    static func issues(recorder:GameRecorder)->[LivePositionIssue] {
        guard recorder.hasGame,recorder.state != .finished,!recorder.awaitingFirstStart else {return []}
        var result=[LivePositionIssue]()
        if let points=recorder.automaticCaptureIssuePoints {
            result.append(.init(id:"automatic-capture:\(recorder.moveCount+1)",kind:.capture,points:points,action:.automaticCapture,hold:.capture,evidence:.legalCapture))
        }
        if let capture=recorder.pendingCaptureReview {
            result.append(.init(id:capture.id.uuidString,kind:.capture,points:capture.captured.union([capture.point]),action:.review(capture.id),hold:recorder.clock.automaticCapturePaused ? .capture:nil,evidence:.legalCapture))
        }
        if recorder.automaticCaptureIssuePoints==nil,let capture=recorder.captureProgressPlan {
            result.append(.init(id:"capture-progress:\(recorder.moveCount+1):\(capture.point)",kind:.capture,
                points:capture.captured.union([capture.point]),action:.captureProgress,evidence:.legalCapture))
        }
        if let restoration=recorder.pendingBoardRestoration {
            result.append(.init(id:restoration.id.uuidString,kind:.displaced,points:restoration.changed,action:.review(restoration.id)))
        }
        for section in recorder.reviewHistory.sections where !section.committed && section.moves == nil {
            let points=Set(section.before.indices.filter{section.before[$0] != section.after[$0]})
            result.append(.init(id:section.id.uuidString,kind:.moveOrder,points:points,action:.review(section.id),evidence:.retainedSequence))
        }
        if let path=recorder.tentativeHistory.bestCandidate {
            for offset in path.moves.indices {
                let points=(path.locationChoices[offset] ?? Set([path.moves[offset]])).union([path.moves[offset]])
                guard !points.isDisjoint(with:Set(recorder.adjustmentIssues.keys).union(recorder.placementAmbiguities.filter{$0.reviewID==nil}.flatMap(\.points))) else {continue}
                let number=recorder.moveCount+offset+1
                result.append(.init(id:"placement:\(number)",kind:.placement,points:points,action:.pendingPlacement(number:number),evidence:.retainedPlacement))
            }
        }
        var missing=Set<Int>()
        for point in recorder.adjustmentIssues.keys.sorted() {
            let position=BoardPosition(point/recorder.game.boardSize,point%recorder.game.boardSize)
            let saved=HistoricalMoveCorrection.moveNumber(at:position,through:recorder.moveCount,game:recorder.game,positions:recorder.positions) != nil
            if !saved {missing.insert(point);continue}
            let acknowledged=recorder.positionAcknowledgments[point] != nil
            result.append(.init(id:"discrepancy:\(point)",kind:.disagreement,points:[point],
                action:acknowledged ? .recognition(point:point):.discrepancy(point:point)))
        }
        if let first=missing.min() {
            result.append(.init(id:"missing-sequence",kind:.missedMove,points:missing,action:.missedMoves(point:first)))
        }
        if let hold=recorder.liveIssueHold {
            result.append(.init(id:"global-hold",kind:.outage,points:[],action:.recoverView,hold:hold,evidence:.unavailableView))
        }
        return LivePositionIssue.coalesced(result)
    }
    static func action(at point:Int,recorder:GameRecorder)->Action {
        if let action=issues(recorder:recorder).first(where:{$0.points.contains(point)})?.action {
            if case .missedMoves=action {return .missedMoves(point:point)}
            return action
        }
        // Historical browsing can request a point without a current issue.
        let position=BoardPosition(point/recorder.game.boardSize,point%recorder.game.boardSize)
        if let number=HistoricalMoveCorrection.moveNumber(at:position,through:recorder.moveCount,game:recorder.game,positions:recorder.positions) {return .recordedPlacement(number:number)}
        return .missedMoves(point:point)
    }
    static func checkPoints(readings:[Occupancy],base:[Occupancy],after:[Occupancy])->Set<Int> {
        Set(BoardAdjustmentMonitor.evidence(readings:readings,base:base,after:after).keys)
    }
    static func checkPoints(recorder:GameRecorder,observation:BoardObservation?)->Set<Int> {
        issues(recorder:recorder).reduce(into:Set<Int>()) {$0.formUnion($1.markers)}
    }
    static func explanation(recorder:GameRecorder,observation:BoardObservation?,orientation:BoardOrientation)->String? {
        guard recorder.hasGame,recorder.state != .finished,!recorder.awaitingFirstStart else {return nil}
        let decisions=Self.issues(recorder:recorder)
        if decisions.contains(where:{$0.action == .automaticCapture}) {return recorder.automaticCaptureStatus}
        if decisions.contains(where:{$0.action == .captureProgress}) {
            return "Remove the marked captured stones and keep the capturing stone in place. Click a ring to see capture progress; the configured clock policy remains in effect."
        }
        if !recorder.positionAcknowledgments.isEmpty {
            return "Recognition still disagrees with a confirmed recorded stone. Clear the view and click a marked intersection to address its current issue."
        }
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
            return "A stone’s intersection is ambiguous at the marked locations. Center the marked stones on their intended intersections. Click a marked stone to confirm its intended location."
        }
        if issues.values.contains(.capture) {
            return "A capture needs checking at the orange rings. Remove captured stones and keep the capturing stone in place."
        }
        if issues.values.contains(.newMove) {
            return "The new stone at the orange ring needs a clearer view. Clear your hand; center it if it is between intersections."
        }
        if !issues.isEmpty {
            return "A persistent camera disagreement is marked with orange rings. Click a marked stone to compare the evidence or confirm that the recorded position is correct. Keep correctly placed physical stones where they are; change the game record only if it is wrong."
        }
        if recorder.pendingMoveCount>0 {
            return "Checking the new move. Previously recorded stones are retained; no stone adjustment is currently needed."
        }
        return nil
    }
}
