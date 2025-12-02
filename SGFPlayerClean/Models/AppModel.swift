// MARK: - File: AppModel.swift
import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case view2D = "2D"
    case view3D = "3D"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .view2D: return "2D Board"
        case .view3D: return "3D Board"
        }
    }
}

// Global Enum for OGS Tabs
enum OGSBrowserTab: String, CaseIterable {
    case challenge = "Challenge"
    case watch = "Watch"
}

final class AppModel: ObservableObject {
    @AppStorage("verboseLogging") var verboseLogging: Bool = false
    @AppStorage("viewMode") var viewMode: ViewMode = .view2D

    // MARK: - Core State
    @Published var folderURL: URL? { didSet { persistFolderURL() } }
    @Published var games: [SGFGameWrapper] = []
    @Published var selection: SGFGameWrapper? = nil { didSet { persistLastGame() } }
    @Published var activePlaylist: [SGFGameWrapper] = []
    @Published var gameCacheManager = GameCacheManager()
    @Published var player = SGFPlayer()
    @Published var isLoadingGames: Bool = false

    // MARK: - OGS Integration
    @Published var ogsClient = OGSClient()
    @Published var timeControl = TimeControlManager()
    @Published var ogsGame: OGSGameViewModel?
    @Published var gameSettings: GameSettings = GameSettings.load()
    @Published var isOnlineMode: Bool = false
    @Published var showPreGameOverlay: Bool = false
    
    // Shared UI State (Persists between 2D/3D)
    @Published var browserTab: OGSBrowserTab = .challenge
    @Published var isCreatingChallenge: Bool = false
    
    // Shared ViewModel reference
    var boardVM: BoardViewModel?

    private var stoneClickPlayer: AVAudioPlayer?
    private var autoAdvanceTimer: Timer?
    private let folderKey = "sgfplayer.folderURL"
    private let lastGameKey = "sgfplayer.lastGame"
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.boardVM = BoardViewModel(player: player)
        
        restoreFolderURL()
        if let url = folderURL { loadFolder(url) }
        setupAudio()

        self.ogsGame = OGSGameViewModel(ogsClient: ogsClient, player: player, timeControl: timeControl)
        self.ogsClient.connect()
        
        setupOGSObservers()
        setupAutoAdvancement()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let self = self, self.ogsClient.isConnected {
                self.selection = nil
                self.player.clear()
            }
        }
    }
    
    // MARK: - OGS Logic
    func joinOnlineGame(id: Int) {
        print("AppModel: 🌍 Joining OGS Game \(id)")
        player.clear()
        selection = nil
        ogsClient.joinGame(gameID: id)
    }
    
    private func setupOGSObservers() {
        NotificationCenter.default.publisher(for: NSNotification.Name("OGSGameDataReceived"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in self?.handleOGSGameLoad(notification) }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("OGSMoveReceived"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in self?.handleOGSMove(notification) }
            .store(in: &cancellables)
    }
    
    private func handleOGSGameLoad(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let moves = userInfo["moves"] as? [[Any]] else { return }
        
        print("AppModel: 📦 OGS Game Loaded with \(moves.count) moves")
        boardVM?.stopAutoPlay()
        player.clear()
        
        for moveData in moves {
            if moveData.count >= 2, let x = moveData[0] as? Int, let y = moveData[1] as? Int {
                if x >= 0 && y >= 0 {
                    let color = (player.currentIndex % 2 == 0) ? Stone.black : Stone.white
                    player.playMoveOptimistically(color: color, x: x, y: y)
                }
            }
        }
        player.seek(to: player.maxIndex)
    }
    
    private func handleOGSMove(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let x = userInfo["x"] as? Int, let y = userInfo["y"] as? Int else { return }
        playStoneClickSound()
        if x >= 0 && y >= 0 {
            let color = (player.currentIndex % 2 == 0) ? Stone.black : Stone.white
            player.playMoveOptimistically(color: color, x: x, y: y)
        }
    }

    // MARK: - Auto Advancement
    func setupAutoAdvancement() {
        guard let boardVM = boardVM else { return }
        boardVM.$currentMoveIndex
            .combineLatest(boardVM.$isAutoPlaying)
            .sink { [weak self] moveIndex, isPlaying in
                guard let self = self, let boardVM = self.boardVM else { return }
                if isPlaying && moveIndex >= boardVM.totalMoves && moveIndex > 0 {
                    self.autoAdvanceTimer?.invalidate()
                    self.autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        self.advanceToNextGame(from: self.activePlaylist)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Audio
    private func setupAudio() {
        guard let soundURL = Bundle.main.url(forResource: "Stone_click_1", withExtension: "mp3") else { return }
        try? stoneClickPlayer = AVAudioPlayer(contentsOf: soundURL)
        stoneClickPlayer?.prepareToPlay()
    }
    func playStoneClickSound() { stoneClickPlayer?.play() }

    // MARK: - Game Navigation
    func selectGame(_ gameWrapper: SGFGameWrapper) {
        selection = gameWrapper
        
        // Load into VM
        boardVM?.loadGame(gameWrapper)
        
        // DEBUG: Log immediate state
        print("AppModel: 📥 Selected \(gameWrapper.url.lastPathComponent). Start on Launch: \(AppSettings.shared.startGameOnLaunch)")
        
        if AppSettings.shared.startGameOnLaunch {
            print("AppModel: 🚀 Scheduling auto-play...")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let vm = self.boardVM {
                    print("AppModel: ▶️ Triggering Play on BoardViewModel. Moves: \(vm.totalMoves)")
                    vm.startAutoPlay()
                } else {
                    print("AppModel: ❌ ERROR - boardVM is nil during auto-play attempt!")
                }
            }
        }
    }

    func pickRandomGame(from gameList: [SGFGameWrapper]) {
        guard !gameList.isEmpty else { return }
        selectGame(gameList[Int.random(in: 0..<gameList.count)])
    }

    func advanceToNextGame(from gameList: [SGFGameWrapper]) {
        guard !gameList.isEmpty, let current = selection,
              let index = gameList.firstIndex(where: { $0.id == current.id }) else {
            if let first = gameList.first { selectGame(first) }
            return
        }
        let nextIndex = (index + 1) % gameList.count
        selectGame(gameList[nextIndex])
    }

    // MARK: - File Loading
    func promptForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
            loadFolder(url)
        }
    }

    func reload() { if let url = folderURL { loadFolder(url) } }

    private func loadFolder(_ url: URL) {
        DispatchQueue.main.async { self.isLoadingGames = true }
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var urls: [URL] = []
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "sgf" { urls.append(fileURL) }
                }
            }
            urls.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            var parsed: [SGFGameWrapper] = []
            for fileURL in urls {
                if let data = try? Data(contentsOf: fileURL),
                   let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii),
                   let tree = try? SGFParser.parse(text: text) {
                    let game = SGFGame.from(tree: tree)
                    parsed.append(SGFGameWrapper(url: fileURL, game: game))
                }
            }
            
            DispatchQueue.main.async {
                self.games = parsed
                self.activePlaylist = parsed
                self.isLoadingGames = false

                if let first = parsed.first {
                    let restored = self.restoreLastGame(from: parsed) ?? first
                    print("AppModel: 📂 Folder loaded. Selecting game: \(restored.url.lastPathComponent)")
                    self.selectGame(restored)
                } else {
                    self.selection = nil
                }
            }
        }
    }

    // MARK: - Persistence
    private func persistFolderURL() {
        guard let url = folderURL else { UserDefaults.standard.removeObject(forKey: folderKey); return }
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: folderKey)
        }
    }

    private func restoreFolderURL() {
        guard let bookmark = UserDefaults.standard.data(forKey: folderKey) else { return }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            if url.startAccessingSecurityScopedResource() { folderURL = url }
        }
    }

    private func persistLastGame() {
        if let sel = selection { UserDefaults.standard.set(sel.url.lastPathComponent, forKey: lastGameKey) }
        else { UserDefaults.standard.removeObject(forKey: lastGameKey) }
    }

    private func restoreLastGame(from games: [SGFGameWrapper]) -> SGFGameWrapper? {
        guard let name = UserDefaults.standard.string(forKey: lastGameKey) else { return nil }
        return games.first { $0.url.lastPathComponent == name }
    }
}
