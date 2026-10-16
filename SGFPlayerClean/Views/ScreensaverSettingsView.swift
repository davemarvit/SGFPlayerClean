import SwiftUI

struct ScreensaverSettingsView: View {
    @ObservedObject var manager: ScreensaverManager
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Screensaver", systemImage: "display").font(.headline)
            Toggle("Quiet Go playback", isOn: Binding(get: { manager.enabled }, set: { manager.setEnabled($0) }))
                .toggleStyle(.switch).tint(.cyan)
            if let config = manager.configuration {
                Text(URL(fileURLWithPath: config.sourceFolderPath).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle).help(config.sourceFolderPath)
                Text("\(config.gameCount) games · Random order · Repeats continuously")
                    .foregroundStyle(.secondary)
            } else { Text("Choose a folder of SGF games to get started.").foregroundStyle(.secondary) }
            HStack {
                Button(manager.configuration == nil ? "Choose Folder…" : "Change Folder…") { manager.chooseFolder() }
                Button("Refresh") { Task { await manager.refresh() } }.disabled(manager.configuration == nil)
                if manager.busy { ProgressView().controlSize(.small) }
            }
            HStack {
                Button("Preview") { manager.preview() }.disabled(!manager.enabled || !manager.installed)
                Button("macOS Settings…") { manager.openSystemSettings() }
            }
            Text("Select Quiet Go in macOS Screen Saver settings to use it when your Mac is idle.")
                .foregroundStyle(.secondary)
            Text("Games are copied for playback while this app is closed. Refresh updates the copies; they also refresh when the app opens.")
                .foregroundStyle(.secondary)
            if let status = manager.status { Text(status).fixedSize(horizontal: false, vertical: true) }
        }
        .font(.caption).foregroundStyle(.white)
        .disabled(manager.busy)
        .accessibilityIdentifier("screensaver-settings")
    }
}
