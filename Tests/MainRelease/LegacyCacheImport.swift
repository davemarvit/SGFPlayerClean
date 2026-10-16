import Foundation
@testable import SGF_Player_OGS_Review

@main struct LegacyCacheImportCheck {
    @MainActor static func main() throws {
        guard let fixture = ProcessInfo.processInfo.environment["SGF_AI_IMPORT_FIXTURE"] else {
            fputs("Set SGF_AI_IMPORT_FIXTURE to a disposable copy of the legacy caches\n", stderr); exit(1)
        }
        let cache = URL(fileURLWithPath: fixture).appendingPathComponent("SGFPlayerClean/AICache")
        let engine = KataGoEngine(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/katago"),
            modelURL: Bundle.main.url(forResource: "kata1-b18", withExtension: "bin.gz")!, cacheDirectory: cache,
            legacyImportDirectories: ["main", "ogs-review", "offline-review"].map { cache.appendingPathComponent("ReviewImports/\($0)") })
        for name in ["91570056-132-DaveM-Goba-n.sgf", "n235711-Davem-2026-10-06.sgf"] {
            let path = "/Users/Dave/Go/Games/" + name
            let game = SGFGame.from(tree: try SGFParser.parse(text: String(contentsOfFile: path)))
            let player = SGFPlayer(); player.load(game: game)
            guard engine.loadAnalysisCache(for: path.replacingOccurrences(of: "/", with: "_"), game: player),
                  !engine.currentAnalysisData.isEmpty, !engine.isEngineRunning else {
                fputs("FAIL: compatible legacy analysis not reused for \(name)\n", stderr); exit(1)
            }
            print("PASS: \(name): reused \(engine.currentAnalysisData.count) positions without starting KataGo")
        }
        engine.stop()
    }
}
