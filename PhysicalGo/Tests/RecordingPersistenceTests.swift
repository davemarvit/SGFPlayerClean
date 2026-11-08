import Foundation

@main struct RecordingPersistenceTests {
    @MainActor static func main() throws {
        setbuf(stdout, nil)
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1; precondition(value, message)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recording-persistence-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var time = ProcessInfo.processInfo.systemUptime
        func feed(_ recorder: GameRecorder, _ colors: [Occupancy], _ count: Int = 7) {
            for _ in 0..<count {
                time += 0.21
                recorder.consume(.init(readings: colors.enumerated().map {
                    .init(row: $0.offset / 9, col: $0.offset % 9, occupancy: $0.element, confidence: 1, delta: 0)
                }, size: 9), now: time)
            }
        }
        func fresh() -> GameRecorder {
            let recorder = GameRecorder(storage: root); recorder.clock.audible = false
            recorder.start(size: 9)
            return recorder
        }
        func reopen(_ url: URL) throws -> GameRecorder {
            let recorder = GameRecorder(storage: root); recorder.clock.audible = false
            try recorder.restoreSavedGame(from: url)
            return recorder
        }
        let passing = fresh(); passing.pause(); passing.manualMove(at: BoardPosition(0, 1))
        let actual = SGFPlayer(); actual.load(game: passing.game); actual.seek(to: 1)
        passing.resume(); feed(passing, DeferredMoveHistory.states(actual.board))
        for point in [BoardPosition(0, 0), BoardPosition(6, 6), BoardPosition(7, 7)] {
            check(actual.tryPlayMove(color: actual.turn, x: point.col, y: point.row) == nil, "Invalid gap fixture")
        }
        feed(passing, DeferredMoveHistory.states(actual.board))
        check(passing.hasDeferredMoves && passing.reviewHistory.sections.last?.moves == nil && passing.canPass,
              "Expected an unresolved order with a known live turn")
        passing.pass()
        check(passing.state == .recording && !passing.reviewHistory.endRequested, "One pass after unknown order ended the game")
        passing.pass()
        check(passing.state == .finished && passing.reviewHistory.endRequested, "Two explicit passes did not end the game")

        let pending = fresh()
        var colors = [Occupancy](repeating: .empty, count: 81)
        feed(pending, colors)
        colors[10] = .black; feed(pending, colors, 2)
        colors[10] = .uncertain; feed(pending, colors)
        colors[20] = .white; feed(pending, colors, 2)
        colors[30] = .black; feed(pending, colors, 2)
        check(pending.moveCount == 0 && pending.pendingMoveCount == 3, "Expected three pending moves")
        let file = pending.autosaveURL!
        check(try reopen(file).pendingMoveCount == 3, "Live pending chronology was not checkpointed")
        pending.suspendVision("Camera stopped. The recorded game is preserved.", preserveOrder: true)
        check(try reopen(file).pendingMoveCount == 3, "Camera stop discarded durable pending chronology")
        check(pending.flushForExit(), "Shutdown flush unexpectedly failed")
        let restored = try reopen(file)
        check(restored.pendingMoveCount == 3 && restored.state == .paused, "Shutdown failed to preserve pending history")
        check(restored.moveCount == 0, "Restoring pending history prematurely accepted moves")

        let pendingFile = file.deletingPathExtension().appendingPathExtension("pending.json")
        let savedPending = try Data(contentsOf: pendingFile)
        try FileManager.default.removeItem(at: pendingFile)
        try FileManager.default.createDirectory(at: pendingFile, withIntermediateDirectories: false)
        check(!restored.flushForExit() && restored.pendingSaveError != nil, "Failed checkpoint allowed shutdown")
        restored.start(size: 13)
        check(restored.autosaveURL == file && restored.pendingMoveCount == 3,
              "Starting another game discarded pending history after a failed save")
        let otherFile = fresh().autosaveURL!
        do { try restored.restoreSavedGame(from: otherFile); check(false, "Opening another game discarded unsaved history") } catch {}
        check(restored.autosaveURL == file && restored.pendingMoveCount == 3,
              "Failed session switch replaced the current recording")
        try FileManager.default.removeItem(at: pendingFile)
        restored.retryRecordingSave()
        check(restored.pendingSaveError == nil && restored.flushForExit(), "Checkpoint retry did not recover")
        check(try reopen(file).pendingMoveCount == 3, "Retry lost pending chronology")

        let reviewsFile = file.deletingPathExtension().appendingPathExtension("reviews.json")
        let damagedBytes = Data("{incomplete-review".utf8)
        try damagedBytes.write(to: reviewsFile)
        let damaged = GameRecorder(storage: root); damaged.clock.audible = false
        do { try damaged.restoreSavedGame(from: file); check(false, "Invalid review file accepted") } catch {}
        check(damaged.recoveryReadBlocked && damaged.hasUnfinishedReviews, "Failed review load did not protect recording")
        let before = try Data(contentsOf: file)
        damaged.resume(); damaged.pass(); damaged.undo()
        feed(damaged, colors)
        check(damaged.state == .paused && !damaged.canPass && !damaged.canEdit, "Failed restore permitted game mutations")
        do { try damaged.savePendingCheckpoint(); check(false, "Failed load allowed writes") } catch {}
        damaged.retryReviewSave()
        check(try Data(contentsOf: reviewsFile) == damagedBytes, "Retry overwrote the damaged review file")
        check(try Data(contentsOf: file) == before, "Failed recovery changed the SGF")
        check(damaged.flushForExit(), "Read-only recovery unnecessarily prevented closing")
        check(try Data(contentsOf: reviewsFile) == damagedBytes, "Closing overwrote damaged review data")
        var validHistory = DeferredMoveHistory(); validHistory.size = 9
        try JSONEncoder().encode(validHistory).write(to: reviewsFile)
        try savedPending.write(to: pendingFile)
        damaged.retryReviewSave()
        check(!damaged.recoveryReadBlocked && damaged.reviewSaveError == nil && damaged.pendingMoveCount == 3,
              "Repair failed to restore both review and pending history")

        // Pending sidecars receive the same protection as review files.
        try damagedBytes.write(to: pendingFile)
        let badPending = GameRecorder(storage: root); badPending.clock.audible = false
        do { try badPending.restoreSavedGame(from: file); check(false, "Invalid pending file accepted") } catch {}
        badPending.resume(); badPending.retryRecordingSave()
        check(badPending.recoveryReadBlocked && badPending.state == .paused, "Invalid pending history permitted resume")
        check(try Data(contentsOf: pendingFile) == damagedBytes, "Retry overwrote invalid pending history")
        try savedPending.write(to: pendingFile)
        badPending.retryRecordingSave()
        check(!badPending.recoveryReadBlocked && badPending.pendingMoveCount == 3, "Pending-file repair did not recover")

        // A clock that failed to load stays disabled. Closing must preserve its
        // bytes, rather than wait forever for a disabled clock to save itself.
        let clockFile = otherFile.deletingPathExtension().appendingPathExtension("clock.json")
        try damagedBytes.write(to: clockFile)
        let badClock = try reopen(otherFile)
        check(!badClock.clock.enabled && badClock.clock.saveError != nil, "Damaged clock was not reported")
        check(badClock.flushForExit(), "An unreadable disabled clock prevented closing")
        check(try Data(contentsOf: clockFile) == damagedBytes, "Closing overwrote the damaged clock")
        print("PASS: \(checks) recording persistence checks: passes, live checkpoints, stop/reopen, shutdown failures, retries, damaged files and repair")
    }
}
