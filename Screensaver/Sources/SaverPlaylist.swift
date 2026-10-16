import Foundation
import os

final class SaverPlaylist {
    static let log = Logger(subsystem: "com.davemarvit.SGFPlayer.QuietSaver", category: "playback")
    let player = SGFPlayer()
    private(set) var game: SGFGame?
    private(set) var file: URL?
    private(set) var files: [URL] = []
    private(set) var errorMessage: String?
    private(set) var running = false
    private var playedGames = 0
    private var queue: [URL] = []
    private let shuffle: Bool
    private var nextMoveAt: TimeInterval = 0
    let moveInterval: TimeInterval
    let endPause: TimeInterval
    let folder: URL

    init(folder: URL, moveInterval: TimeInterval = 1.5, endPause: TimeInterval = 7, shuffle: Bool = true) {
        self.folder = folder; self.shuffle = shuffle
        self.moveInterval = max(0.1, moveInterval); self.endPause = max(0.1, endPause)
        reloadFiles()
    }
    func reloadFiles() {
        files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { url in
                guard url.pathExtension.lowercased() == "sgf",
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true, let bytes = values.fileSize else { return false }
                return bytes > 0 && bytes <= 2_000_000
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        queue = shuffle ? files.shuffled() : files.reversed()
        if queue.count > 1, queue.last == file { queue.swapAt(0, queue.count - 1) }
        if files.isEmpty { errorMessage = "No SGF games in the screensaver's Games folder." }
    }
    func start(at time: TimeInterval) {
        guard !running else { return }
        running = true
        if game == nil { loadNext(at: time) }
        else { nextMoveAt = time + (player.currentIndex == player.maxIndex ? endPause : moveInterval) }
        Self.log.notice("Started; files=\(self.files.count, privacy: .public), move=\(self.player.currentIndex, privacy: .public)")
    }
    func stop() {
        running = false
        player.pause()
        Self.log.notice("Stopped at move \(self.player.currentIndex, privacy: .public)")
    }
    @discardableResult func advance(at time: TimeInterval) -> Bool {
        guard running, time >= nextMoveAt else { return false }
        if game == nil || player.currentIndex >= player.maxIndex {
            loadNext(at: time)
        } else {
            player.stepForward()
            nextMoveAt = time + (player.currentIndex == player.maxIndex ? endPause : moveInterval)
            if player.currentIndex <= 3 || player.currentIndex.isMultiple(of: 25) {
                Self.log.notice("Move \(self.player.currentIndex, privacy: .public)/\(self.player.maxIndex, privacy: .public)")
            }
        }
        return true
    }
    private func loadNext(at time: TimeInterval) {
        if queue.isEmpty { reloadFiles() }
        for _ in files.indices {
            if queue.isEmpty { reloadFiles() }
            guard let url = queue.popLast() else { break }
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 2_000_000, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { continue }
                let original = SGFGame.from(tree: try SGFParser.parse(text: text))
                // Use the same guarded main-line interpretation as Review. In
                // particular, mid-game setup edits must not become root stones.
                let replay = try ReviewTree(game: original, analysisID: "screensaver", filename: url.lastPathComponent).playbackGame()
                guard (2...25).contains(replay.boardSize), !replay.moves.isEmpty else { continue }
                game = replay; file = url; errorMessage = nil; playedGames += 1
                player.load(game: replay)
                nextMoveAt = time + moveInterval
                Self.log.notice("Loaded game \(self.playedGames, privacy: .public); moves=\(self.player.maxIndex, privacy: .public)")
                return
            } catch { Self.log.error("Skipped unreadable or unsupported SGF") }
        }
        game = nil; file = nil; player.clear()
        errorMessage = files.isEmpty ? "No SGF games in the screensaver's Games folder." : "No playable SGF games found."
        nextMoveAt = time + 30 // A malformed library must not spin on every frame.
        Self.log.error("No playable games; files=\(self.files.count, privacy: .public)")
    }
}
