import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct LibraryLoadingCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe", "Isolated test identity")
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.analysisEnabled = false
        AppSettings.shared.isMuted = true
        AppSettings.shared.folderURL = nil
        AppSettings.shared.shuffleGameOrder = false
        let app = AppModel()
        app.mode = .review
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func fixture(_ filename: String, _ metadata: String) throws -> URL {
            let url = directory.appendingPathComponent(filename)
            try "(;GM[1]FF[4]SZ[9]\(metadata);B[aa];W[bb])".write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        let first = try fixture("first.sgf", "PB[zebra]PW[Alice]DT[2024-12-01]")
        let second = try fixture("second.SGF", "PB[alice]PW[Zebra]DT[2026-02-01]")
        let missing = try fixture("missing.sgf", "")
        let tie = try fixture("tie.sgf", "PB[ALICE]PW[zebra]DT[2026-02-01]")
        try "not a game".write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let panel = AppModel.makeSGFOpenPanel()
        require(panel.canChooseFiles && panel.canChooseDirectories && !panel.allowsMultipleSelection,
                "One picker accepts either a file or a directory")
        require(panel.prompt == "Open" && panel.allowedContentTypes.first?.preferredFilenameExtension == "sgf", "Open prompt and SGF filter")
        let folderPanel = AppModel.makeSGFOpenPanel(folderOnly: true)
        require(!folderPanel.canChooseFiles && folderPanel.canChooseDirectories, "Settings folder chooser remains folder-only")
        try app.openSGFSelection(second)
        require(app.games.count == 1 && app.selection?.url == second && app.player.maxIndex == 2, "Single SGF loads without siblings")
        require(app.mode == .review && !app.player.isPlaying && app.player.currentIndex == 2, "Single game opens paused at the main-line end")
        let selectedID = app.selection!.id
        do {
            try app.openSGFSelection(directory.appendingPathComponent("missing-file.sgf"))
            require(false, "Missing file should fail")
        } catch {}
        require(app.selection?.id == selectedID && app.games.count == 1, "Failed open preserves current game")
        func waitForFolder() {
            let deadline = Date().addingTimeInterval(5)
            while !app.loadingStatus.hasPrefix("✅") && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            require(app.loadingStatus.hasPrefix("✅"), "Folder load finished: \(app.loadingStatus)")
        }
        try app.openSGFSelection(directory)
        waitForFolder()
        require(Set(app.games.map { $0.url.standardizedFileURL.path }) == Set([first, second, missing, tie].map { $0.standardizedFileURL.path }), "Folder loads SGFs including uppercase extension; ignores other files")
        require(AppSettings.shared.folderURL == directory, "Folder choice is remembered")
        // Fixed collection order makes tie and missing-value expectations explicit.
        app.games = [first, second, missing, tie].map { url in app.games.first { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }! }
        app.selectGame(app.games[1])
        app.player.stepForward()
        let reviewID = app.selection!.id, position = app.player.currentIndex
        let cases: [(AppModel.GameSortMethod, [URL])] = [
            (.date, [second, tie, first, missing]),
            (.oldestDate, [first, second, tie, missing]),
            (.name, [second, tie, first, missing]),
            (.whitePlayer, [first, second, tie, missing]),
            (.defaultIndex, [first, second, missing, tie])
        ]
        for (sort, expected) in cases {
            app.gameSortMethod = sort
            require(app.sortedGames.map { $0.url.standardizedFileURL.path } == expected.map { $0.standardizedFileURL.path }, "Correct order for \(sort.label)")
            require(app.selection?.id == reviewID && app.player.currentIndex == position, "Sorting preserves review")
            require(UserDefaults.standard.string(forKey: "gameSortMethod") == sort.rawValue, "Sort choice persists")
        }
        app.gameSortMethod = .date
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: RightPanelView().environmentObject(app).frame(width: 320, height: 900))
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([recognition])
        let labels = recognition.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        require(labels.contains { $0.contains("Load SGFs") }, "Load button visible in narrow sidebar: \(labels)")
        require(labels.contains { $0.contains("Sort by") } && labels.contains { $0.contains("newest first") },
                "Sort label and full selected option visible in narrow sidebar: \(labels)")
        window.orderOut(nil)
        app.loadFolder(directory)
        try app.openSGFSelection(first)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        require(app.games.count == 1 && app.selection?.url == first && app.loadingStatus == "Loaded 1 game.", "Stale folder load cannot replace single-file choice")
        let empty = directory.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        app.loadFolder(directory)
        app.loadFolder(empty)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        require(app.games.isEmpty && app.loadingStatus.contains("0 SGF"), "Latest folder choice wins, including empty folders")
        print("PASS: File/folder picker, single game, folder import, errors, all sort orders, stable ties, missing metadata, review preservation, persistence and overlapping imports.")
    }
}
