import SwiftUI
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
@main struct OpenMainLineCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil; AppSettings.shared.analysisEnabled = false; AppSettings.shared.isMuted = true
        let app = AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("open-mainline-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("branching.sgf")
        let sgf = "(;SZ[9]AW[bb]AB[ab][ba][cb];B[bc](;W[gg];B[hh]C[Main final])(;W[fg];B[fh];W[ff]))"
        try sgf.write(to: url, atomically: true, encoding: .utf8)
        try app.openSGFSelection(url)
        let vm = app.boardVM!
        func finalMainLine() {
            require(!app.player.isPlaying && vm.currentMoveIndex == 3 && app.player.maxIndex == 3,
                    "Open pauses at final main-line move, not longer alternative")
            require(vm.reviewTree!.isMainLine && vm.reviewTree!.nodes[vm.reviewTree!.selectedID].comment == "Main final",
                    "Selected node belongs to the main line")
            require(vm.blackCapturedCount == 1 && app.player.board.stones[BoardPosition(7, 7)] == .black,
                    "Final board and captures match the recorded line")
        }
        finalMainLine()
        vm.goToStart(); vm.placeStone(at: BoardPosition(2, 2))
        require(vm.reviewDraftSaved && !vm.reviewTree!.isMainLine && vm.currentMoveIndex == 1,
                "Fixture saves an early alternative in the review draft")
        let edited = vm.reviewSGFData()
        try app.openSGFSelection(url)
        finalMainLine()
        require(vm.reviewDraftSaved && vm.reviewSGFData() == edited, "Reopening preserves edits without selecting their old position")
        let original = try String(contentsOf: url)
        require(original == sgf, "Original SGF is untouched")
        vm.goToStart(); app.selectGame(app.games[0]); finalMainLine()
        let empty = SGFGameWrapper(url: folder.appendingPathComponent("empty.sgf"),
            game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9]AB[aa])")))
        app.selectGame(empty)
        require(vm.currentMoveIndex == 0 && app.player.board.stones.count == 1, "Setup-only game remains at its sole position")
        let unsupported = SGFGameWrapper(url: folder.appendingPathComponent("setup-edit.sgf"),
            game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9];B[aa];AB[bb];W[cc])")))
        app.selectGame(unsupported)
        require(vm.currentMoveIndex == 1 && app.player.board.stones[BoardPosition(0, 0)] == .black && vm.reviewTreeError != nil,
                "Unsupported setup edits retain the playable prefix with an explanation")
        print("PASS: file and library opens select final main-line board/captures, longer alternatives and old draft selection cannot override it, edits/source preserved, setup-only and unsupported-setup fallback")
    }
}
