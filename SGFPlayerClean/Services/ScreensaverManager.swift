import AppKit
import Combine

@MainActor final class ScreensaverManager: ObservableObject {
    static let shared = ScreensaverManager()
    @Published private(set) var configuration: ScreensaverConfiguration?
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    @Published private(set) var installed = false
    let root: URL
    let installationURL: URL
    let templateURL: URL?
    private var refreshedOnLaunch = false

    init(root: URL = ScreensaverConfiguration.root, installationURL: URL? = nil, templateURL: URL? = nil) {
        self.root = root
        self.installationURL = installationURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/Quiet Go.saver")
        self.templateURL = templateURL ?? Bundle.main.resourceURL?.appendingPathComponent("Screensaver/Quiet Go.saver")
        configuration = try? ScreensaverConfiguration.load(root: root)
        installed = FileManager.default.fileExists(atPath: self.installationURL.path)
    }
    var enabled: Bool { configuration?.enabled == true }
    func chooseFolder(enableAfter: Bool = false) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose games for the screensaver"
        panel.prompt = "Use Folder"; panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let path = configuration?.sourceFolderPath { panel.directoryURL = URL(fileURLWithPath: path) }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                if await self.refresh(folder: url), enableAfter { self.setEnabled(true) }
            }
        }
    }
    @discardableResult func refresh(folder: URL? = nil) async -> Bool {
        guard !busy else { return false }
        var source = folder
        if source == nil, let saved = configuration {
            if let bookmark = saved.sourceBookmark {
                var stale = false
                source = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            }
            if source == nil { source = URL(fileURLWithPath: saved.sourceFolderPath) }
        }
        guard let source else { status = "Choose a games folder first."; return false }
        busy = true; status = "Preparing games…"
        let root = root
        do {
            let result = try await Task.detached(priority: .utility) { try ScreensaverLibrary.prepare(folder: source, root: root) }.value
            configuration = result
            status = "\(result.gameCount) games ready" + (result.skippedCount > 0 ? " · \(result.skippedCount) unsupported or oversized files skipped" : "")
            busy = false; return true
        } catch {
            status = "Could not refresh games: " + error.localizedDescription
            busy = false; return false
        }
    }
    func setEnabled(_ value: Bool) {
        guard !busy else { return }
        guard var settings = configuration else { if value { chooseFolder(enableAfter: true) }; return }
        do {
            if value { try install() }
            settings.enabled = value; try settings.save(root: root); configuration = settings
            status = value ? "Ready. Select Quiet Go in macOS Screen Saver settings." : "Quiet Go playback is off."
        } catch { status = "Could not update screensaver: " + error.localizedDescription }
    }
    func install() throws {
        guard let templateURL,
              FileManager.default.fileExists(atPath: templateURL.appendingPathComponent("Contents/MacOS/QuietGoSaver").path) else {
            throw NSError(domain: "SGFScreensaver", code: 2, userInfo: [NSLocalizedDescriptionKey: "This build does not include the screensaver. Install the complete app build."])
        }
        let fm = FileManager.default, parent = installationURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".QuietGo-\(UUID().uuidString).saver")
        try fm.copyItem(at: templateURL, to: staging)
        defer { try? fm.removeItem(at: staging) }
        if fm.fileExists(atPath: installationURL.path) {
            _ = try fm.replaceItemAt(installationURL, withItemAt: staging)
        } else { try fm.moveItem(at: staging, to: installationURL) }
        installed = true
    }
    func refreshOnLaunch() async {
        guard !refreshedOnLaunch, enabled else { return }
        refreshedOnLaunch = true
        do { try install() } catch { status = "Could not update screensaver: " + error.localizedDescription }
        _ = await refresh()
    }
    func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!)
    }
    func preview() {
        guard let preview = Bundle.main.resourceURL?.appendingPathComponent("Screensaver/SGF Screensaver Preview.app"),
              FileManager.default.fileExists(atPath: preview.path) else { status = "The screensaver preview is missing from this build."; return }
        NSWorkspace.shared.open(preview)
    }
}
