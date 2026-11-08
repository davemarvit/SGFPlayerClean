import SwiftUI
import CryptoKit
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct LaunchPositionCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.analysisEnabled = false; AppSettings.shared.isMuted = true
        AppSettings.shared.folderURL = nil; AppSettings.shared.shuffleGameOrder = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("launch-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder); KataGoEngine.shared.stop() }
        let source = folder.appendingPathComponent("zz-last-game.sgf")
        let sgf = "(;SZ[9]PB[Last game]AW[bb]AB[ab][ba][cb];B[bc](;W[gg];B[hh])(;W[fg]C[Review branch];B[fh]))"
        try sgf.write(to: source, atomically: true, encoding: .utf8)
        for i in 0..<30 {
            try "(;SZ[19]PB[Old test game];B[aa])".write(to: folder.appendingPathComponent(String(format: "%02d-old.sgf", i)), atomically: true, encoding: .utf8)
        }
        AppSettings.shared.folderURL = folder
        UserDefaults.standard.set(AppMode.review.rawValue, forKey: "lastAppMode")
        var app: AppModel? = AppModel()
        func settle(_ duration: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
        func waitLibrary() {
            let deadline = Date().addingTimeInterval(3)
            while app!.games.count < 31 && Date() < deadline { settle(0.03) }
            require(app!.games.count == 31, "Entire library loads")
        }
        waitLibrary()
        require(app!.player.board.stones.isEmpty && app!.player.currentIndex == 0 && app!.selection == nil,
                "Without a saved position startup stays blank, even with a remembered library")
        app!.selectGame(app!.games.first { $0.url.resolvingSymlinksInPath() == source.resolvingSymlinksInPath() }!)
        let branch = app!.boardVM!.reviewTree!.nodes.first { $0.comment == "Review branch" }!.id
        app!.boardVM!.selectReviewNode(branch)
        let board = app!.player.board
        let captures = app!.boardVM!.blackCapturedCount
        settle()
        require(UserDefaults.standard.data(forKey: "lastBoardSessionV1") != nil, "Navigation autosaves without quitting")
        app!.ogsClient.disconnect(); app = nil
        app = AppModel(); waitLibrary()
        require(app!.selection?.url.resolvingSymlinksInPath() == source.resolvingSymlinksInPath() && app!.player.board == board && app!.player.currentIndex == 2,
                "Restore exact game and position beyond first library batch")
        require(app!.boardVM!.reviewTree?.selectedID == branch && app!.boardVM!.blackCapturedCount == captures,
                "Restore variation and captures")
        require(!app!.player.isPlaying, "Restoration is paused")
        // A later move after an edit must supersede the draft's saved selection.
        app!.boardVM!.addReviewMove(at: BoardPosition(6, 6))
        app!.boardVM!.goToStart()
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        app!.ogsClient.disconnect(); app = nil
        try FileManager.default.removeItem(at: source)
        AppSettings.shared.folderURL = nil
        UserDefaults.standard.removeObject(forKey: "folderURLBookmark")
        app = AppModel(); settle()
        require(app!.player.currentIndex == 0 && app!.boardVM!.reviewTree!.nodes.contains { $0.properties["B"] == ["gg"] },
                "Moved/deleted source still restores full edited game at latest navigation position")
        require(app!.player.board.stones.count == 4, "Initial setup is preserved")
        // Persist a blank board intentionally instead of resurrecting the old game.
        app!.newLocalGame(); settle(); app!.saveLaunchPosition()
        app!.ogsClient.disconnect(); app = nil; app = AppModel(); settle()
        require(app!.mode == .localPlay && app!.player.board.stones.isEmpty, "Explicit new blank board remains blank on relaunch")
        app!.boardVM!.placeStone(at: BoardPosition(3, 3)); settle()
        let local = app!.player.board
        app!.saveLaunchPosition(); app!.ogsClient.disconnect(); app = nil; app = AppModel(); settle()
        require(app!.mode == .localPlay && app!.player.board == local && app!.player.currentIndex == 1,
                "Local game also restores its position")
        require(app!.boardVM!.reviewTree == nil && !app!.isAIAvailable, "Restored local play keeps its play rules and AI policy")
        app!.ogsClient.disconnect(); app = nil
        UserDefaults.standard.set(Data("invalid".utf8), forKey: "lastBoardSessionV1")
        UserDefaults.standard.set(AppMode.review.rawValue, forKey: "lastAppMode")
        app = AppModel(); settle()
        require(app!.player.board.stones.isEmpty && app!.selection == nil, "Corrupt session falls back to blank")
        let empty = app!.boardVM!.reviewTree!
        let stale = empty.addingMove(color: .black, point: BoardPosition(0, 0))
        let digest = SHA256.hash(data: Data(empty.baseAnalysisID.utf8)).map { String(format: "%02x", $0) }.joined()
        let draft = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("ReviewDrafts")
            .appendingPathComponent(digest + ".json")
        try FileManager.default.createDirectory(at: draft.deletingLastPathComponent(), withIntermediateDirectories: true)
        let previousDraft = try? Data(contentsOf: draft)
        defer {
            if let previousDraft { try? previousDraft.write(to: draft) }
            else { try? FileManager.default.removeItem(at: draft) }
        }
        try JSONEncoder().encode(ReviewDraft(stale)).write(to: draft)
        app!.ogsClient.disconnect(); app = nil
        UserDefaults.standard.set(Data("invalid".utf8), forKey: "lastBoardSessionV1")
        app = AppModel(); settle()
        require(app!.player.board.stones.isEmpty, "An old blank-board draft must not resurrect a testing game at launch")
        app!.ogsClient.disconnect(); app = nil
        print("PASS: blank fallback, autosaved game/move/variation/captures, independent library loading, deleted-source and edited-SGF recovery, latest navigation over old draft, paused restoration, blank/local play, corrupt session")
    }
}
