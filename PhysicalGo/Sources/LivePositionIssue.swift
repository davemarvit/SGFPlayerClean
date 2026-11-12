import Foundation

/// Domain decisions shared by live markers and review entry points. Neither an
/// action nor a placement discrepancy implies a clock hold.
struct LivePositionIssue: Equatable, Identifiable {
    enum Case: Int, CaseIterable {
        case obstruction = 1, disagreement, nudged, displaced, placement
        case missedMove, moveOrder, recordedMove, capture, outage
    }
    enum Action: Equatable {
        case review(UUID), pendingPlacement(number: Int), missedMoves(point: Int)
        case recordedPlacement(number: Int), discrepancy(point: Int), recognition(point: Int)
        case recoverView, automaticCapture, captureProgress
    }
    enum Evidence:Equatable {case freshDiscrepancy, retainedPlacement, retainedSequence, legalCapture, unavailableView}
    enum Hold: Equatable {case timing, capture, manual, correction, storage, observationGap}
    let id: String
    let kind: Case
    let points: Set<Int>
    let action: Action?
    var hold: Hold? = nil
    var evidence:Evidence = .freshDiscrepancy
    var reconciling = false
    var markers: Set<Int> {action == nil || reconciling || kind == .outage ? [] : points}

    /// More specific explanations claim their points first. One capture or
    /// sequence therefore has one identity even across several intersections.
    static func coalesced(_ candidates: [Self]) -> [Self] {
        var claimed = Set<Int>(), result = [Self]()
        for issue in candidates {
            let remaining = issue.points.subtracting(claimed)
            guard issue.points.isEmpty || !remaining.isEmpty else {continue}
            result.append(Self(id: issue.id, kind: issue.kind, points: remaining,
                               action: issue.action, hold: issue.hold, evidence:issue.evidence, reconciling: issue.reconciling))
            claimed.formUnion(remaining)
        }
        return result
    }
}

/// Confirmation belongs to one position and one observed discrepancy. It is not
/// a recognition override and never modifies accepted or provisional history.
struct PositionAcknowledgment: Equatable {
    let position: String
    let point: Int
    let observed: Occupancy
}
