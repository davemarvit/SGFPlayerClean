import Foundation
import Combine

/// A preview of exactly one saved move. Physical restoration precedes the edit,
/// so canceling or closing the window cannot leave a half-applied history change.
@MainActor struct UndoMovePlan: Identifiable {
    let id = UUID()
    let signature: String
    let recordingURL: URL?
    let moveNumber: Int
    let color: Stone
    let point: BoardPosition?
    let target: BoardSnapshot
    let remove: [Int]
    let restore: [Int]
    let size: Int

    static func unavailableReason(_ recorder: GameRecorder) -> String? {
        if recorder.recoveryReadBlocked { return "Reload the saved recording before undoing a move." }
        if !recorder.hasGame || recorder.moveCount == 0 { return "There is no saved move to undo." }
        if recorder.state == .finished { return "Undo is available while the game is in progress." }
        if recorder.hasUnfinishedReviews || recorder.pendingMoveCount > 0 {
            return "Resolve pending board changes before undoing a saved move."
        }
        return nil
    }
    init?(recorder: GameRecorder) {
        guard Self.unavailableReason(recorder) == nil,
              recorder.positions.count > recorder.moveCount, let last = recorder.game.moves.last else { return nil }
        signature = RecordingIdentity.signature(for: recorder.game)
        recordingURL = recorder.autosaveURL
        moveNumber = recorder.moveCount; color = last.0
        point = last.1.map { BoardPosition($0.1, $0.0) }
        size = recorder.game.boardSize; target = recorder.positions[moveNumber - 1]
        let before = DeferredMoveHistory.states(recorder.positions[moveNumber])
        let after = DeferredMoveHistory.states(target)
        remove = before.indices.filter { before[$0].stone != nil && before[$0] != after[$0] }
        restore = after.indices.filter { after[$0].stone != nil && before[$0] != after[$0] }
    }
    func matches(_ observation: BoardObservation) -> Bool {
        guard !observation.lightingBlocked, observation.size == size,
              observation.readings.count == size * size,
              observation.readings.enumerated().allSatisfy({ $0.element.row == $0.offset / size && $0.element.col == $0.offset % size }) else { return false }
        return ReviewBoardVerification.matches(observation.signature,
            target: DeferredMoveHistory.states(target), requiredClear: Set(remove + restore))
    }
}

@MainActor final class UndoMoveSession: ObservableObject {
    let plan: UndoMovePlan
    @Published private(set) var revision = 0
    @Published private(set) var applied = false
    private var witnesses = [Double]()
    private var lastFrame: Double?
    private var status = ReviewBoardVerification.Status.waitingForCamera
    init(plan: UndoMovePlan) { self.plan = plan }
    func observeLive(_ observation: BoardObservation?, frameTime: Double?, isLive: Bool) {
        guard isLive, let frameTime else { invalidate(); return }
        observe(observation, now: frameTime)
    }
    func invalidate() {
        witnesses = []; lastFrame = nil; status = .waitingForCamera; revision += 1
    }
    func observe(_ observation: BoardObservation?, now: Double = ProcessInfo.processInfo.systemUptime) {
        defer { revision += 1 }
        guard now.isFinite, let observation, !observation.lightingBlocked,
              observation.size == plan.size, observation.readings.count == plan.size * plan.size else { invalidate(); return }
        if let lastFrame, now <= lastFrame { return }
        lastFrame = now
        status = ReviewBoardVerification.status(observation.signature, target: DeferredMoveHistory.states(plan.target), requiredClear: Set(plan.remove + plan.restore))
        guard plan.matches(observation) else { witnesses = []; return }
        if let last = witnesses.last {
            guard now > last else { return }
            if now - last > 0.5 { witnesses = [] }
        }
        witnesses.append(now); witnesses.removeAll { now - $0 > 2 }
    }
    func verified(now: Double = ProcessInfo.processInfo.systemUptime) -> Bool {
        verificationStatus(now: now) == .ready
    }
    func verificationStatus(now: Double = ProcessInfo.processInfo.systemUptime) -> ReviewBoardVerification.Status {
        guard let lastFrame, now >= lastFrame, now - lastFrame < 1.5 else { return .waitingForCamera }
        guard status == .ready else { return status }
        guard let last = witnesses.last, let first = witnesses.first,
              witnesses.count >= 5 && last - first >= 0.8 else { return .checking }
        return .ready
    }
    func confirm(_ recorder: GameRecorder, now: Double = ProcessInfo.processInfo.systemUptime) -> String? {
        guard !applied else { return "This move has already been undone. Retry saving if needed." }
        guard recorder.autosaveURL == plan.recordingURL else { return "The open recording changed. Close this preview and review Undo move again." }
        guard recorder.state == .paused, !recorder.reviewing, verified(now: now) else {
            return "Restore the board shown and wait for a fresh, steady camera view."
        }
        let error = recorder.undo(expectedSignature: plan.signature)
        applied = recorder.moveCount == plan.moveNumber - 1 && recorder.positions.last == plan.target
        return error
    }
    func retrySave(_ recorder: GameRecorder) -> String? {
        guard applied else { return "Confirm the undo first." }
        recorder.retryRecordingSave()
        return recorder.saveError ?? recorder.pendingSaveError ?? recorder.reviewSaveError ?? recorder.clock.saveError
    }
}
