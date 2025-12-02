//
//  SGFPlayerCleanApp.swift
//  SGFPlayerClean
//
//  Purpose: Main application entry point
//  Now with 2D/3D mode switching
//

import SwiftUI

@main
struct SGFPlayerCleanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
            print("📂 File picker response: \(response == .OK ? "OK" : "Cancel")")
            if response == .OK, let url = panel.url {
                print("📂 Selected file: \(url.path)")
                print("📂 Posting notification...")
                NotificationCenter.default.post(
                    name: NSNotification.Name("LoadSGFFile"),
                    object: url
                )
                print("📂 Notification posted")
            } else {
                print("📂 No file selected or picker cancelled")
            }
        }
    }
}

