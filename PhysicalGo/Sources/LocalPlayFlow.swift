import Foundation

/// A single presentation of play intent and its current gate. Recording may keep
/// examining the board while clocks are held; that is checking, not another pause
/// requiring the user to press Resume again. Placement uncertainty alone is not a
/// clock-review gate.
enum LocalPlayFlow: Equatable {
    case idle, paused, checking, playing, clockReview, removingCapturedStones, storageBlocked, finished
}

@MainActor extension GameRecorder {
    var playFlow: LocalPlayFlow {
        if state == .idle {return .idle}
        if recoveryReadBlocked || storageWriter.error != nil || saveError != nil || pendingSaveError != nil || reviewSaveError != nil || (clock.enabled && clock.saveError != nil) {return .storageBlocked}
        if state == .finished {return .finished}
        if clock.requiresReview {return .clockReview}
        if state == .paused {return .paused}
        if clock.automaticCapturePaused {return .removingCapturedStones}
        if clock.enabled {return clock.running ? .playing:.checking}
        return synchronized ? .playing:.checking
    }
}
