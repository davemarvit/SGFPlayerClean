import AppKit
import SwiftUI

@MainActor enum PhysicalReviewTests {
    static func run() throws -> Int {
        var checks = 0, now = ProcessInfo.processInfo.systemUptime
        func check(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("physical-review-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: "PhysicalGo/Tests/Fixtures/IncompleteCapture")
        let sgf = try String(contentsOf: fixture.appendingPathComponent("before.sgf"), encoding: .utf8)
        let observed = try JSONDecoder().decode([Occupancy].self, from: Data(contentsOf: fixture.appendingPathComponent("observed.json")))
        func make(_ text: String, after: [Occupancy]) throws -> GameRecorder {
            let file = root.appendingPathComponent(UUID().uuidString + ".sgf")
            try text.write(to: file, atomically: true, encoding: .utf8)
            let game = SGFGame.from(tree: try SGFParser.parse(text: text))
            let player = SGFPlayer(); player.load(game: game); player.seek(to: game.moves.count)
            var history = DeferredMoveHistory(); history.size = game.boardSize
            history.baseMove = game.moves.count; history.anchorSignature = RecordingIdentity.signature(for: game)
            history.sections = [.init(reviewNumber: 1, before: DeferredMoveHistory.states(player.board), after: after,
                                      reason: "Observed board change", firstSeen: now, confirmedAt: now)]
            try JSONEncoder().encode(history).write(to: file.deletingPathExtension().appendingPathExtension("reviews.json"))
            let recorder = GameRecorder(storage: root); recorder.clock.audible = false
            try recorder.restoreSavedGame(from: file); recorder.attachClock(.init())
            return recorder
        }
        func feed(_ recorder: GameRecorder, _ values: [Occupancy], count: Int = 5) {
            for _ in 0..<count {
                now += 0.21
                recorder.consume(.init(readings: values.enumerated().map {
                    .init(row: $0.offset / recorder.game.boardSize, col: $0.offset % recorder.game.boardSize,
                          occupancy: $0.element, confidence: 1, delta: 0)
                }, size: recorder.game.boardSize), now: now)
            }
        }
        func render(_ recorder: GameRecorder, _ id: UUID, _ name: String, turns: Int) throws {
            let host = NSHostingView(rootView: ReviewSectionView(recorder: recorder, id: id, orientation: .init(turns)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 780), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua); host.appearance = window.appearance
            window.contentView = host; window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2)); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: TestArtifacts.file("physical-reviews/" + name + ".png"))
            window.orderOut(nil)
        }

        let capture = try make(sgf, after: observed)
        var announcements = [String]()
        capture.clock.onResumeAnnouncement = { announcements.append($0) }
        let original = capture.reviewHistory.sections[0], id = original.id
        let plan = capture.captureReviewPlan(id)!
        check(plan.point == 314 && plan.captured == [294, 312, 313], "Actual capture was misidentified")
        check(plan.remaining(in: nil) == [312], "Capture guidance marked the capturing stone or already removed stones")
        check(capture.boardRestorationPlan(id) == nil, "Capture was confused with a bumped stone")
        let pausedCapture=LocalPlayPresentation(recorder:capture,clock:capture.clock)
        check(pausedCapture.correction?.id == id && pausedCapture.correction?.title == "Finish capture…", "Paused capture offered a misleading Resume")
        capture.resume()
        let checkingCapture=LocalPlayPresentation(recorder:capture,clock:capture.clock)
        check(checkingCapture.correction?.id == id && !checkingCapture.automaticHold, "Unresolved capture was presented as passive camera checking")
        capture.pause()
        check(capture.confirmCaptureReview(id, now: now) != nil, "Capture saved without fresh evidence")
        check(capture.captureVerificationStatus(plan, now: now) == .waitingForCamera, "Missing camera view has no actionable reason")
        try render(capture, id, "incomplete-capture", turns: 3)
        feed(capture, observed)
        check(!capture.captureRemovalVerified(plan, now: now), "Captured stone still present was accepted")
        check(capture.captureVerificationStatus(plan, now: now) == .different([312]), "Capture blocker did not identify the remaining stone")
        feed(capture, plan.target, count: 4)
        check(!capture.captureRemovalVerified(plan, now: now), "Removal confirmed before enough fresh frames")
        check(capture.captureVerificationStatus(plan, now: now) == .checking, "Matching view was confused with a board error")
        feed(capture, plan.target, count: 1)
        check(capture.captureRemovalVerified(plan, now: now), "Stable complete capture did not verify")
        check(!capture.captureRemovalVerified(plan, now: now + 2), "Stale camera evidence verified removal")
        check(capture.captureVerificationStatus(plan, now: now + 2) == .waitingForCamera, "Stale-view guidance claims the board is ready")
        var unclear = plan.target; unclear[312] = .uncertain; feed(capture, unclear)
        check(!capture.captureRemovalVerified(plan, now: now), "Unknown captured point was treated as removed")
        check(capture.captureVerificationStatus(plan, now: now) == .unclear([312]), "Unclear captured intersection was not explained")
        var changed = plan.target; changed[0] = .white; feed(capture, changed)
        check(!capture.captureRemovalVerified(plan, now: now), "Unrelated new stone was hidden by capture confirmation")
        changed = plan.target; changed[314] = .empty; feed(capture, changed)
        check(!capture.captureRemovalVerified(plan, now: now), "Removing the capturing stone was accepted")
        changed = plan.target; changed[0] = .uncertain; feed(capture, changed)
        check(capture.captureRemovalVerified(plan, now: now), "Unchanged background uncertainty blocked a verified capture")
        let partialViews = try JSONDecoder().decode([String].self, from: Data(contentsOf: fixture.appendingPathComponent("corrected-partial-views.json")))
        for position in partialViews {
            feed(capture, position.map { $0 == "B" ? .black : $0 == "W" ? .white : $0 == "?" ? .uncertain : .empty }, count: 1)
        }
        check(partialViews.count == 20 && partialViews.allSatisfy { $0.filter { $0 == "?" }.count > 18 }, "Live partial-view fixture no longer exercises the disabled-button regression")
        check(capture.captureRemovalVerified(plan, now: now), "Actual corrected board stayed disabled because of unchanged background uncertainty")
        changed = [Occupancy](repeating: .uncertain, count: plan.target.count)
        for p in plan.captured.union([plan.point]) { changed[p] = plan.target[p] }
        feed(capture, changed)
        check(!capture.captureRemovalVerified(plan, now: now), "Broad obstruction was accepted as a clear corrected board")
        check(capture.captureVerificationStatus(plan, now: now) == .obstructed(357), "Broad camera obstruction has no explanation")
        now += 0.21
        capture.consume(.init(readings: [], size: capture.game.boardSize, lightingBlocked: true), now: now)
        check(!capture.captureRemovalVerified(plan, now: now), "Unreadable view retained confirmation evidence")
        feed(capture, plan.target, count: 4)
        check(!capture.captureRemovalVerified(plan, now: now), "Unreadable view did not reset the fresh-frame count")
        feed(capture, plan.target, count: 1)
        capture.suspendVision("Camera interrupted", preserveOrder: true)
        check(!capture.captureRemovalVerified(plan, now: now), "Camera interruption retained confirmation evidence")
        feed(capture, plan.target)
        let black = capture.clock.engine.black, white = capture.clock.engine.white
        check(capture.confirmCaptureReview(id, now: now) == nil, "Verified capture failed to save")
        check(capture.moveCount == 46 && capture.nextPlayer == .white && !capture.hasDeferredMoves, "Capture changed turn or retained a false gap")
        check(LocalPlayPresentation(recorder:capture,clock:capture.clock).correction == nil, "Saved capture did not restore normal Resume controls")
        check(DeferredMoveHistory.states(capture.positions.last!) == plan.target, "Captured stones survived in the saved game")
        check(capture.clock.engine.black == black && capture.clock.engine.white == white && !capture.clock.running, "Capture review changed clocks")
        check(announcements.isEmpty && capture.clock.pendingResumeAnnouncement == "Capture complete.", "Capture announced a restart while paused")
        check(capture.reviewHistory.sections[0].before == original.before && capture.reviewHistory.sections[0].after == original.after,
              "Capture review overwrote its original snapshots")
        check(capture.confirmCaptureReview(id, now: now) != nil && capture.moveCount == 46, "Repeated confirmation duplicated the capture")
        let reopened = GameRecorder(storage: root); reopened.clock.audible = false
        try reopened.restoreSavedGame(from: capture.autosaveURL!)
        check(reopened.moveCount == 46 && !reopened.hasDeferredMoves, "Capture resolution failed restart")
        check(reopened.clock.pendingResumeAnnouncement == "Capture complete.", "Restart lost the pending capture announcement")
        reopened.clock.onResumeAnnouncement = { announcements.append($0) }
        reopened.clock.resume(at: now)
        if reopened.clock.requiresReview {
            check(announcements.isEmpty && !reopened.clock.running, "Clock review gate falsely announced resumption")
            _ = reopened.clock.correct(black: reopened.clock.engine.black, white: reopened.clock.engine.white, blackToPlay: false, moveCount: reopened.moveCount, at: now)
            reopened.clock.resume(at: now)
        }
        check(reopened.clock.running && announcements == ["Capture complete. Clocks resumed. White to play."], "Capture restart announcement was missing or named the wrong player")
        reopened.clock.resume(at: now)
        reopened.clock.pause(at: now); reopened.clock.resume(at: now)
        check(announcements.count == 1, "Capture restart announcement repeated")
        reopened.clock.pause(at: now)
        var history = capture.reviewHistory
        history.sections[0] = original
        history.sections.append(.init(before: plan.target, after: plan.target, moves: [], reason: "Later section", firstSeen: now, confirmedAt: now))
        var prefix = capture.game; prefix.moves = Array(prefix.moves.prefix(45))
        check(CaptureReviewPlan.make(history: history, id: id, context: prefix) == nil, "Capture action ignored a later section")
        history.sections = [original]; history.sections[0].after[0] = .black
        check(CaptureReviewPlan.make(history: history, id: id, context: prefix) == nil, "Multiple placements were called one capture")
        history.sections[0] = original; history.sections[0].after[314] = .white
        check(CaptureReviewPlan.make(history: history, id: id, context: prefix) == nil, "Wrong color was called a capture")

        let koText = "(;GM[1]FF[4]AP[PhysicalGo:0.121]SZ[9]RU[Japanese];B[ab];W[bb];B[ba];W[ac];B[cb];W[cc];B[ii];W[bd];B[hi];W[gi];B[bc])"
        let koGame = SGFGame.from(tree: try SGFParser.parse(text: koText))
        let koPlayer = SGFPlayer(); koPlayer.load(game: koGame); koPlayer.seek(to: koGame.moves.count)
        var recapture = DeferredMoveHistory.states(koPlayer.board); recapture[10] = .white
        let illegalCapture = try make(koText, after: recapture)
        check(illegalCapture.pendingCaptureReview == nil, "Incomplete ko recapture bypassed full game history")

        let simple = "(;GM[1]FF[4]AP[PhysicalGo:0.121]SZ[9]RU[Japanese];B[ee];W[cc])"
        var base = [Occupancy](repeating: .empty, count: 81); base[40] = .black; base[20] = .white
        var bumped = base; bumped[40] = .empty; bumped[41] = .black
        let restore = try make(simple, after: bumped), restoreID = restore.reviewHistory.sections[0].id
        let restoration = restore.boardRestorationPlan(restoreID)!
        check(restoration.kind == .displaced(from: 40, to: 41, color: .black), "Neighbor displacement was not identified")
        check(restore.captureReviewPlan(restoreID) == nil, "Moved stone became a capture")
        try render(restore, restoreID, "bumped-stone", turns: 1)
        check(restore.confirmBoardRestoration(restoreID, now: now) != nil, "Restoration saved without verification")
        feed(restore, bumped)
        check(!restore.boardRestorationVerified(restoration, now: now), "Still displaced stone was accepted")
        var hidden = base; hidden[40] = .uncertain; feed(restore, hidden)
        check(!restore.boardRestorationVerified(restoration, now: now), "Unseen restored intersection was accepted")
        feed(restore, base)
        let originalText = restore.sgf(), originalClock = restore.clock.engine
        check(restore.confirmBoardRestoration(restoreID, now: now) == nil, "Restored stone failed to clear review")
        check(restore.moveCount == 2 && restore.nextPlayer == .black && !restore.hasDeferredMoves, "Restoration invented a move")
        check(restore.clock.engine.black == originalClock.black && restore.clock.engine.white == originalClock.white, "Restoration changed clock values")
        check(restore.clock.pendingResumeAnnouncement == "Board position restored.", "Restoration lost its restart announcement")
        check(SGFGame.from(tree: try SGFParser.parse(text: originalText)).moves.count == restore.moveCount, "Restoration changed accepted history")
        check(restore.reviewHistory.sections[0].after == bumped, "Restoration lost the original snapshot")
        var missing = base; missing[20] = .empty
        let removed = try make(simple, after: missing)
        check(removed.pendingBoardRestoration?.kind == .missing, "Missing stone was forced into move order")
        check(ReviewChangeKind.classify(before: base, after: missing) == .missing, "Missing-stone category lost")
        var colors = base; colors[40] = .white
        check(ReviewChangeKind.classify(before: base, after: colors) == .colorChanges, "Color mismatch category lost")
        let wrongColor = try make(simple, after: colors)
        check(wrongColor.pendingBoardRestoration == nil && wrongColor.pendingCaptureReview == nil, "Changed color was silently restored")
        var extras = base; extras[60] = .black; extras[70] = .white
        check(ReviewChangeKind.classify(before: base, after: extras) == .additions, "Real additions lost sequence review")
        var far = base; far[40] = .empty; far[80] = .black
        check(try make(simple, after: far).pendingBoardRestoration == nil, "Distant changes were assumed to be a bump")
        restore.clock.finish(at: now)
        check(restore.clock.pendingResumeAnnouncement == nil, "Ending a game retained an obsolete restart announcement")
        print("PASS: \(checks) physical-review checks: actual incomplete capture, fresh removal, stale/unknown/changed views, legal history, clocks, restart, bumped/missing stones, color changes and native guidance")
        return checks
    }
}
