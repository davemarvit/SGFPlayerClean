import Foundation

struct ScreensaverConfiguration: Codable, Equatable {
    var version = 1
    var enabled = false
    var sourceFolderPath: String
    var sourceBookmark: Data?
    var generation: String
    var gameCount: Int
    var skippedCount: Int
    var refreshedAt: Date

    // FileManager.homeDirectoryForCurrentUser points inside the container when
    // Apple's legacy screensaver host loads us. Its read-only filesystem
    // entitlement permits this separate, non-sensitive playback library.
    static var root: URL {
        let home = NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/SGFPlayerScreensaver", isDirectory: true)
    }
    func libraryURL(root: URL = Self.root) -> URL? {
        guard UUID(uuidString: generation) != nil else { return nil }
        return root.appendingPathComponent("Libraries", isDirectory: true).appendingPathComponent(generation, isDirectory: true)
    }
    static func load(root: URL = Self.root) throws -> Self {
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: root.appendingPathComponent("configuration.json")))
        guard result.version == 1, result.libraryURL(root: root) != nil else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
    func save(root: URL = Self.root) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: root.appendingPathComponent("configuration.json"), options: .atomic)
    }
}

/// Publishes a complete generation atomically. Readers can finish their current
/// game while the app prepares another folder. Never edits source games/bundles.
enum ScreensaverLibrary {
    static func prepare(folder: URL, root: URL = ScreensaverConfiguration.root) throws -> ScreensaverConfiguration {
        let fm = FileManager.default
        let sourcePath = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let cachePath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard sourcePath != cachePath, !sourcePath.hasPrefix(cachePath + "/") else {
            throw NSError(domain: "SGFScreensaver", code: 3, userInfo: [NSLocalizedDescriptionKey: "Choose the original games folder, not the screensaver’s playback copies."])
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        _ = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let previous = try? ScreensaverConfiguration.load(root: root)
        let generation = UUID().uuidString
        let library = root.appendingPathComponent("Libraries").appendingPathComponent(generation)
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        var published = false
        defer { if !published { try? fm.removeItem(at: library) } }
        var count = 0, skipped = 0
        var enumerationError: Error?
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in enumerationError = error; return false }) else { throw CocoaError(.fileReadUnknown) }
        for case let url as URL in enumerator {
            if url.resolvingSymlinksInPath().standardizedFileURL.path == cachePath { enumerator.skipDescendants(); continue }
            guard url.pathExtension.lowercased() == "sgf" else { continue }
            let data: Data
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size > 0, size <= 2_000_000 else { skipped += 1; continue }
                data = try Data(contentsOf: url)
                guard data.count <= 2_000_000,
                      let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { skipped += 1; continue }
                let game = SGFGame.from(tree: try SGFParser.parse(text: text))
                let replay = try ReviewTree(game: game, analysisID: "screensaver", filename: url.lastPathComponent).playbackGame()
                guard (2...25).contains(replay.boardSize), !replay.moves.isEmpty else { skipped += 1; continue }
            } catch { skipped += 1; continue }
            // Any destination write failure aborts publication, preserving the
            // old library rather than silently publishing an incomplete copy.
            try data.write(to: library.appendingPathComponent(String(format: "%06d.sgf", count)), options: .atomic)
            count += 1
        }
        if let error = enumerationError { throw error }
        guard count > 0 else { throw NSError(domain: "SGFScreensaver", code: 1, userInfo: [NSLocalizedDescriptionKey: "No playable SGF games were found. The previous screensaver library has been kept."]) }
        let result = ScreensaverConfiguration(enabled: previous?.enabled ?? false, sourceFolderPath: folder.path,
            sourceBookmark: try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
            generation: generation, gameCount: count, skippedCount: skipped, refreshedAt: Date())
        try result.save(root: root); published = true
        // Retain the immediately previous generation for any reader mid-transition.
        let libraries = library.deletingLastPathComponent()
        for old in (try? fm.contentsOfDirectory(at: libraries, includingPropertiesForKeys: nil)) ?? [] {
            if UUID(uuidString: old.lastPathComponent) != nil,
               old.lastPathComponent != generation, old.lastPathComponent != previous?.generation { try? fm.removeItem(at: old) }
        }
        return result
    }
}
