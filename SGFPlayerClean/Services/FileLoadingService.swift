//
//  FileLoadingService.swift
//  SGFPlayerClean
//
//  Created: 2025-11-26
//  Purpose: Centralized file loading and game library management
//
//  ARCHITECTURE:
//  - Replaces NotificationCenter-based file loading (tech debt removal)
//  - Manages game library state
//  - Reusable by any view that needs file operations
//

import Foundation
import SwiftUI

/// Service for loading SGF files and managing game library
class FileLoadingService: ObservableObject {

    // MARK: - Published State

    /// List of games loaded from folder
    @Published var games: [SGFGameWrapper] = []

    /// Currently selected game
    @Published var selection: SGFGameWrapper?

    /// Loading indicator
    @Published var isLoadingGames: Bool = false

    // MARK: - Dependencies

    private weak var boardVM: BoardViewModel?

    // MARK: - Initialization

    init(boardVM: BoardViewModel? = nil) {
        self.boardVM = boardVM
    }

    // MARK: - Public API

    /// Load a single SGF file
    func loadFile(from url: URL) {
        print("📂 Loading SGF file: \(url.path)")

        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let tree = try SGFParser.parse(text: text)
            let game = SGFGame.from(tree: tree)
            let wrapper = SGFGameWrapper(url: url, game: game)

            print("✅ Successfully loaded: \(wrapper.title ?? "Untitled")")

            // Load into BoardViewModel
            boardVM?.loadGame(wrapper)

        } catch {
            print("❌ Failed to load SGF file: \(error)")
        }
    }

    /// Load all games from a folder
    func loadGamesFromFolder(_ folderURL: URL) {
        // Set loading state
        DispatchQueue.main.async {
            self.isLoadingGames = true
        }

        // Save folder URL to settings
        AppSettings.shared.folderURL = folderURL

        // Load in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var sgfURLs: [URL] = []

            if let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "sgf" {
                        sgfURLs.append(fileURL)
                    }
                }
            }

            // Sort by path
            sgfURLs.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            // Shuffle if requested
            if AppSettings.shared.shuffleGameOrder {
                sgfURLs.shuffle()
                print("🔀 Shuffled game order")
            }

            print("📂 Found \(sgfURLs.count) games, loading all...")

            var parsed: [SGFGameWrapper] = []
            for fileURL in sgfURLs {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    let tree = try SGFParser.parse(text: text)
                    let game = SGFGame.from(tree: tree)
                    parsed.append(SGFGameWrapper(url: fileURL, game: game))
                } catch {
                    print("❌ Failed to parse \(fileURL.lastPathComponent): \(error)")
                }
            }

            // Update on main thread
            DispatchQueue.main.async {
                self.games = parsed

                // Auto-select and load first game if enabled
                if AppSettings.shared.startGameOnLaunch, let firstGame = parsed.first {
                    self.selection = firstGame
                    self.loadFile(from: firstGame.url)
                    print("🎮 Auto-launching first game: \(firstGame.title ?? "Untitled")")
                } else {
                    self.selection = parsed.first
                }

                self.isLoadingGames = false
                print("📚 Loaded \(parsed.count) games")
            }
        }
    }
}
