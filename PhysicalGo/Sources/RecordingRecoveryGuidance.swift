import Foundation

/// Spoken actions use the same evidence and displayed coordinates as review.
/// A suspected displacement is a question to check, never a command to relocate
/// a stone based only on an uncertain camera reading.
@MainActor extension GameRecorder {
    func spokenRecoveryInstruction(orientation:BoardOrientation = .init(0))->String {
        func locations(_ points:[Int])->String {
            let sorted=Array(Set(points)).sorted()
            return sorted.prefix(3).map{BoardCoordinates.name(point:$0,size:game.boardSize,orientation:orientation)}.joined(separator:", ")
                + (sorted.count>3 ? ", and \(sorted.count-3) other intersections":"")
        }
        let prefix=clock.enabled && !clock.running ? "Clocks paused.":"Please pause play."
        if saveError != nil || pendingSaveError != nil || reviewSaveError != nil || recoveryReadBlocked || clock.saveError != nil {
            return "\(prefix) The game could not be saved or restored safely. Check the save error on screen before playing another move."
        }
        if let remaining=automaticCaptureRemainingPoints {
            if !automaticCaptureConflictPoints.isEmpty {
                return "Clocks remain paused. The camera and recorded board disagree at \(locations(automaticCaptureConflictPoints)). Compare those intersections with the interpretation board before correcting anything."
            }
            if state == .paused {
                let action=remaining.isEmpty ? "Captured intersections look empty."
                    : "Finish removing the captured stones at \(locations(remaining)), then move your hands clear."
                return "Clocks remain paused. \(action) Press Resume when ready to verify the complete board."
            }
            return remaining.isEmpty
                ? "\(prefix) Captured intersections look empty. Keep hands clear while the complete board is verified."
                : "\(prefix) Finish removing the captured stones at \(locations(remaining)), then move your hands clear. The clocks restart after verification."
        }
        if let capture=pendingCaptureReview {
            let remaining=capture.remaining(in:reviewCameraPosition).sorted()
            let action=remaining.isEmpty ? "Keep hands clear while the board is verified."
                : "Remove the remaining captured stones at \(locations(remaining)), then move your hands clear."
            return "\(prefix) \(action) Open Review \(reviewHistory.sections.last?.reviewNumber ?? 1) and choose Confirm capture when available."
        }
        if let section=reviewHistory.sections.last(where:{!$0.committed && $0.moves==nil}) {
            let review="Review \(section.reviewNumber ?? 1)"
            let lead=clock.running ? "Move history needs review." : prefix
            let changed=section.before.indices.filter {section.before[$0] != section.after[$0]}
            if let restoration=boardRestorationPlan(section.id),case let .displaced(from,to,color)=restoration.kind {
                return "\(lead) A \(color.rawValue) stone may have moved from \(locations([from])) to \(locations([to])). Open \(review). If the saved location is wrong, drag the saved stone to its intended intersection and confirm the correction. Restore it only if it was bumped."
            }
            switch ReviewChangeKind.classify(before:section.before,after:section.after) {
            case .missing:
                return "\(lead) Recorded stones appear missing at \(locations(changed)). Open \(review). Restore accidental removals, or review the capture if they were captured."
            case .colorChanges:
                return "\(lead) Stone colors differ at \(locations(changed)). Check the physical colors in \(review), then correct the camera reading or review the moves."
            case .additions:
                let turn=clock.awaitingTurn ? " Then choose whose turn it is before resuming." : ""
                return "\(lead) New stones at \(locations(changed)) need checking. Open \(review) to enter the actual moves or undo accidental additions.\(turn)"
            case .mixed:
                return "\(lead) Placements and removals differ at \(locations(changed)). Open \(review) and compare with the physical board before choosing a correction."
            }
        }
        if clock.requiresReview {return "\(prefix) Check both clock times on screen and confirm them before resuming."}
        if clock.awaitingTurn {return "\(prefix) The next player is uncertain. Choose Black or White on screen to continue the clock."}
        if handOverBoard {return "\(prefix) Move your hands out of the board view and wait for verification. Keep the camera in place."}
        let placements=adjustmentIssues.filter{$0.value == .placement}.map(\.key)
        let centering=adjustmentIssues.filter{$0.value == .centering}.map(\.key)
        if !centering.isEmpty {return "\(prefix) Check stone centering near \(locations(centering)). If a stone was bumped, center it on its recorded intersection; otherwise check the saved location before moving it."}
        if !placements.isEmpty {return "\(prefix) Check that stones at \(locations(placements)) are centered on their intended intersections, then move your hands clear."}
        let conflicts=adjustmentIssues.filter{$0.value == .conflict}.map(\.key)
        if !conflicts.isEmpty {return "\(prefix) The camera and recorded board disagree at \(locations(conflicts)). Compare those intersections with the interpretation board before correcting anything."}
        let candidates=adjustmentIssues.keys.sorted()+pendingConfidence.compactMap(\.point)
        if !candidates.isEmpty {return "\(prefix) Moves near \(locations(candidates)) are not confirmed. Keep hands clear. If they remain highlighted, compare the physical stones with the interpretation board."}
        if unclearPointCount>max(2,game.boardSize*game.boardSize/20) {
            return "\(prefix) Too much of the board is unreadable. Clear obstructions and check for darkness or glare. Keep the stones in place."
        }
        return "\(prefix) The next move is not verified. Keep hands clear, then compare the physical board with the highlighted intersections on screen."
    }
}
