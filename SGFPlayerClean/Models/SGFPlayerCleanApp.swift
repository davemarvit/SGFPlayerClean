//
//  SGFPlayerCleanApp.swift
//  SGFPlayerClean
//
//  Purpose: Main application entry point
//  Ensures a single AppModel instance is shared across the app.
//

import SwiftUI

@main
struct SGFPlayerCleanApp: App {
    // Single source of truth for the entire application lifecycle
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(appModel.ogsClient)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open SGF File...") {
                    openSGFFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    /// Open SGF file picker
    private func openSGFFile() {
        print("📂 Opening file picker...")
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]
        panel.title = "Choose an SGF file"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                print("📂 Selected file: \(url.path)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("LoadSGFFile"),
                    object: url
                )
            }
        }
    }
}
