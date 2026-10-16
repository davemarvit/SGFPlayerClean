import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
@main struct PlaylistTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ name: String, _ sgf: String) throws { try sgf.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        // Capture fixture: White's corner stone is captured on move 3.
        try write("01.sgf", "(;SZ[9]PB[Alice]PW[Bob];B[ba];W[aa];B[ab])")
        try write("02.sgf", "(;SZ[9]AB[cc]AW[gg];B[dd](;W[ee];B[])(;W[ff]))")
        try write("03.sgf", "not sgf")
        let list = SaverPlaylist(folder: folder, moveInterval: 1, endPause: 5)
        list.start(at: 0)
        check(list.files.count == 3 && list.player.maxIndex == 3 && list.player.currentIndex == 0, "Load first game paused on empty board")
        check(!list.advance(at: 0.9), "Move interval respected")
        for t in 1...3 { check(list.advance(at: Double(t)), "Advance move") }
        check(list.player.currentIndex == 3 && list.player.whiteStonesCaptured == 1, "Shared engine applies captures")
        check(list.player.board.stones[BoardPosition(0,0)] == nil, "Captured stone removed")
        check(!list.advance(at: 7.9), "Keep final position visible")
        check(list.advance(at: 8) && list.file?.lastPathComponent == "02.sgf", "Cycle to next game")
        check(list.player.board.stones.count == 2 && list.player.maxIndex == 3, "Setup and first variation are retained")
        _ = list.advance(at: 9); list.stop()
        check(!list.advance(at: 100) && list.player.currentIndex == 1, "Stop blocks late frames")
        list.start(at: 100)
        check(!list.advance(at: 100.9) && list.advance(at: 101), "Restart does not rush accumulated moves")
        _ = list.advance(at: 102); _ = list.advance(at: 107)
        check(list.file?.lastPathComponent == "01.sgf", "Malformed game skipped and playlist wraps")
        let empty = folder.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let missing = SaverPlaylist(folder: empty); missing.start(at: 0)
        check(missing.game == nil && missing.errorMessage != nil && !missing.advance(at: 1), "Empty library has useful error and no busy loop")
        if let argument = CommandLine.arguments.firstIndex(of: "--library"), argument + 1 < CommandLine.arguments.count {
            let library = URL(fileURLWithPath: CommandLine.arguments[argument + 1])
            var games = 0, moves = 0, skipped = 0
            for url in try FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil) where url.pathExtension.lowercased() == "sgf" {
                do {
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { skipped += 1; continue }
                    let source = SGFGame.from(tree: try SGFParser.parse(text: text))
                    let game = try ReviewTree(game: source, analysisID: "test", filename: url.lastPathComponent).playbackGame()
                    guard (2...25).contains(game.boardSize), !game.moves.isEmpty else { skipped += 1; continue }
                    let player = SGFPlayer(); player.load(game: game)
                    while player.currentIndex < player.maxIndex { player.stepForward() }
                    check(player.currentIndex == game.moves.count, "Whole SGF replay finishes")
                    check(player.board.stones.keys.allSatisfy { (0..<game.boardSize).contains($0.row) && (0..<game.boardSize).contains($0.col) }, "Replay stones stay inside board")
                    games += 1; moves += player.currentIndex
                } catch { skipped += 1 }
            }
            check(games > 0, "Library has playable games")
            print("PASS: full library replays: \(games) games, \(moves) moves; skipped \(skipped) unsupported/empty records")
        }
        print("PASS: folder playback, captures, setup, variations, pass, game-end pause/cycling, invalid SGFs, stop/restart, empty folder")
    }
}
