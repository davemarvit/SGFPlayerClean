import XCTest
@testable import SGFPlayerNetworking

final class ScreensaverLibraryTests: XCTestCase {
    var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }
    func fixture(_ name: String = "source") throws -> URL {
        let folder = temporary.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try "(;SZ[9]PB[Alice];B[dd];W[ee])".write(to: folder.appendingPathComponent("game.sgf"), atomically: true, encoding: .utf8)
        try "(;SZ[9];B[aa](;W[bb])(;W[cc]))".write(to: folder.appendingPathComponent("nested/game.SGF"), atomically: true, encoding: .utf8)
        return folder
    }
    func testRecursiveImportCopiesGamesAndPreservesEnabledState() throws {
        let source = try fixture(), root = temporary.appendingPathComponent("cache")
        let original = try Data(contentsOf: source.appendingPathComponent("game.sgf"))
        try "garbage".write(to: source.appendingPathComponent("bad.sgf"), atomically: true, encoding: .utf8)
        let first = try ScreensaverLibrary.prepare(folder: source, root: root)
        XCTAssertEqual(first.gameCount, 2); XCTAssertEqual(first.skippedCount, 1)
        XCTAssertFalse(first.enabled)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("game.sgf")), original)
        var enabled = first; enabled.enabled = true; try enabled.save(root: root)
        let refreshed = try ScreensaverLibrary.prepare(folder: source, root: root)
        XCTAssertTrue(refreshed.enabled); XCTAssertNotEqual(refreshed.generation, first.generation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.libraryURL(root: root)!.path))
        XCTAssertEqual(try ScreensaverConfiguration.load(root: root), refreshed)
    }
    func testFailedReplacementKeepsPriorConfigurationAndLibrary() throws {
        let root = temporary.appendingPathComponent("cache"), source = try fixture()
        let previous = try ScreensaverLibrary.prepare(folder: source, root: root)
        let empty = temporary.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ScreensaverLibrary.prepare(folder: empty, root: root))
        XCTAssertThrowsError(try ScreensaverLibrary.prepare(folder: empty.appendingPathComponent("missing"), root: root))
        XCTAssertEqual(try ScreensaverConfiguration.load(root: root), previous)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Libraries").path).count, 1)
    }
    func testKeepsOnlyCurrentAndPreviousCompletedGeneration() throws {
        let root = temporary.appendingPathComponent("cache"), source = try fixture()
        let old = try ScreensaverLibrary.prepare(folder: source, root: root)
        let previous = try ScreensaverLibrary.prepare(folder: source, root: root)
        let current = try ScreensaverLibrary.prepare(folder: source, root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.libraryURL(root: root)!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.libraryURL(root: root)!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.libraryURL(root: root)!.path))
    }
    func testImportCannotReimportItsOwnPlaybackCache() throws {
        let source = try fixture(), root = source.appendingPathComponent("PlaybackCache")
        let first = try ScreensaverLibrary.prepare(folder: source, root: root)
        let second = try ScreensaverLibrary.prepare(folder: source, root: root)
        XCTAssertEqual(second.gameCount, 2)
        XCTAssertThrowsError(try ScreensaverLibrary.prepare(folder: root, root: root))
        XCTAssertThrowsError(try ScreensaverLibrary.prepare(folder: first.libraryURL(root: root)!, root: root))
        XCTAssertEqual(try ScreensaverConfiguration.load(root: root), second)
    }
    func testRejectsUnexpectedSchemaAndEscapingLibraryPath() throws {
        let root = temporary.appendingPathComponent("cache"), source = try fixture()
        var config = try ScreensaverLibrary.prepare(folder: source, root: root)
        config.generation = "../../something"
        XCTAssertNil(config.libraryURL(root: root)); try config.save(root: root)
        XCTAssertThrowsError(try ScreensaverConfiguration.load(root: root))
        config.generation = UUID().uuidString; config.version = 2; try config.save(root: root)
        XCTAssertThrowsError(try ScreensaverConfiguration.load(root: root))
    }
}
