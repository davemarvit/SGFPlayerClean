import SwiftUI
@testable import SGF_Player_OGS_Review

private func require(_ value: @autoclosure () throws -> Bool, _ message: String) {
    if (try? value()) != true { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct GameSavingCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        UserDefaults.standard.removeObject(forKey: "lastBoardSessionV1")
        UserDefaults.standard.removeObject(forKey: "lastAppMode")
        UserDefaults.standard.set(false, forKey: "isOnlineModePersistent")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("game-saving-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        AppSettings.shared.analysisEnabled = false
        AppSettings.shared.analyzeDuringPlay = false
        AppSettings.shared.isMuted = true
        AppSettings.shared.folderURL = nil
        AppSettings.shared.savedGamesFolderURL = temp
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let vm = app.boardVM!
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.65)) }
        func files() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil).filter { $0.pathExtension == "sgf" }
        }
        func load(_ url: URL) throws -> SGFGame { SGFGame.from(tree: try SGFParser.parse(text: String(contentsOf: url, encoding: .utf8))) }
        var info = SGFGame.Info()
        info.playerBlack = "  Lee Sedol "; info.playerWhite = "井山裕太"; info.date = "2016-03-09"
        require(info.suggestedFilename == "Lee Sedol vs 井山裕太 - 2016-03-09.sgf", "Names and historical date survive Unicode and whitespace")
        require(SGFGame.Info().suggestedFilename == "Black vs White - Undated.sgf", "Missing metadata is explicit")
        info.playerBlack = "A/B:C\\D\nE"; info.playerWhite = String(repeating: "棋", count: 300)
        require(!info.suggestedFilename.contains("/") && !info.suggestedFilename.contains(":"), "Filename components cannot create paths")
        require((info.suggestedFilename as NSString).lastPathComponent == info.suggestedFilename && info.suggestedFilename.utf8.count < 240, "Long Unicode names fit a filesystem component")
        info.date = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        require(!info.suggestedFilename.contains(",") && !info.suggestedFilename.contains("AM") && !info.suggestedFilename.contains("PM"), "Old local timestamps export as a date")

        func finishLocal() {
            app.player.confirmAnalysisSettings(rules: "Chinese", komi: "6.5")
            vm.passLocally(); vm.syncState()
            vm.passLocally(); vm.syncState()
            require(vm.localScoring?.result != nil, "Fixture has confirmed rules and komi")
            vm.confirmLocalScore(); settle()
        }
        app.newLocalGame()
        finishLocal()
        require(app.mode == .review && app.completedGameSaveError == nil, "Final local score automatically saves and opens Review: mode=\(app.mode), error=\(app.completedGameSaveError ?? "none")")
        let original = app.completedGameSaveURL!
        let originalBytes = try Data(contentsOf: original)
        let saved = try load(original)
        require(saved.moves.count == 2 && saved.moves.allSatisfy { $0.1 == nil } && saved.info.result != nil, "Saved original has both passes and result")
        let reviewName = original.deletingPathExtension().lastPathComponent + "-review.sgf"
        require(app.suggestedReviewFilename == reviewName, "Review name matches original with suffix")
        let beforeRetry = try files().count
        app.retryCompletedGameSave()
        require(try files().count == beforeRetry, "Retry does not duplicate a successful save")
        vm.selectReviewNode(0); vm.addReviewMove(at: BoardPosition(3, 3)); settle()
        let reviewURL = temp.appendingPathComponent(reviewName)
        let firstReview = try Data(contentsOf: reviewURL)
        vm.addReviewMove(at: BoardPosition(4, 4)); settle()
        require(try Data(contentsOf: reviewURL) != firstReview, "Further review edits overwrite the same review")
        require(try Data(contentsOf: original) == originalBytes, "Review editing preserves the finished original")
        require(try files().filter { $0.lastPathComponent.contains("-review") }.count == 1, "One canonical review per game")
        let parsedReview = try SGFParser.parse(text: String(contentsOf: reviewURL, encoding: .utf8))
        require(parsedReview.branches.count > 1, "Canonical review contains variations")
        vm.deleteSelectedReviewNode(); vm.undoReviewDeletion(); settle()
        require(try SGFWriter.serialize(SGFParser.parse(text: String(contentsOf: reviewURL, encoding: .utf8))) == SGFWriter.serialize(vm.reviewTree!.source), "Delete and undo autosave the current tree")

        // Reopening either file must find the same canonical review, even though
        // the analysis identity changes from the live-game ID to the file path.
        app.selectGame(SGFGameWrapper(url: original, game: try load(original)))
        require(app.suggestedReviewFilename == reviewName && vm.reviewTree!.source.branches.count == parsedReview.branches.count, "Reopened original restores its canonical review and all variations")
        app.selectGame(SGFGameWrapper(url: reviewURL, game: try load(reviewURL)))
        require(app.suggestedReviewFilename == reviewName, "Reopened review keeps the same filename")
        vm.selectReviewNode(0); vm.addReviewMove(at: BoardPosition(5, 5)); settle()
        require(try files().filter { $0.lastPathComponent.contains("-review") }.count == 1, "Reopening and editing never creates another review")

        // Another completed game with the same names/date must not replace the first.
        app.newLocalGame(); finishLocal()
        require(app.completedGameSaveURL != original && app.completedGameSaveURL!.lastPathComponent.contains("(2)"), "Same-day filename collisions get a numbered game")
        require(try Data(contentsOf: original) == originalBytes, "Collision leaves earlier game intact")

        // The production save callback remembers the destination for future saves.
        let changed = temp.appendingPathComponent("Chosen Folder")
        try FileManager.default.createDirectory(at: changed, withIntermediateDirectories: true)
        app.rememberSGFSave(to: changed.appendingPathComponent("export.sgf"))
        require(AppSettings.shared.savedGamesFolderURL.path == changed.path && UserDefaults.standard.string(forKey: "savedGamesFolderPath") == changed.path,
                "A successful Save SGF remembers its folder persistently")
        app.newLocalGame(); finishLocal()
        require(app.completedGameSaveURL?.deletingLastPathComponent().path == changed.path, "Next finished game uses the last save folder")

        // Failure is visible and retry saves the retained finished-game snapshot.
        let blocked = temp.appendingPathComponent("Not a folder")
        try Data("occupied".utf8).write(to: blocked)
        AppSettings.shared.savedGamesFolderURL = blocked
        app.newLocalGame(); finishLocal()
        require(app.completedGameSaveURL == nil && app.completedGameSaveError != nil, "Unwritable destination reports failure")
        AppSettings.shared.savedGamesFolderURL = changed
        app.retryCompletedGameSave()
        require(app.completedGameSaveURL != nil && app.completedGameSaveError == nil, "Changing location and retrying saves the game")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.orderOut(nil) }
        func capture<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String) throws {
            window.setContentSize(CGSize(width: width, height: height))
            let host = NSHostingView(rootView: view.preferredColorScheme(.dark).background(Color(nsColor: .windowBackgroundColor)))
            window.contentView = host; window.orderFront(nil); settle(); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sgf-save-\(name).png"))
        }
        try capture(CompletedGameResultBanner().environmentObject(app), width: 700, height: 180, name: "banner")
        UserDefaults.standard.set(false, forKey: "settings.environment.expanded")
        UserDefaults.standard.set(true, forKey: "settings.savedGames.expanded")
        try capture(SettingsPanel(app: app, isPresented: .constant(true)), width: 500, height: 900, name: "settings")
        print("PASS: readable safe names, local completion, full history/result, collisions, canonical review updates/delete/undo, original preservation, remembered save folder, errors and retry")
    }
}
