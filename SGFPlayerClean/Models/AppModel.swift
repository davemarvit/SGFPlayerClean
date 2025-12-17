//
//  AppModel.swift
//  SGFPlayerClean
//
//  v3.79: Wires up Local Undo.
//  - Listens for OGSUndoAccepted and triggers BoardVM replay.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - Enums
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

enum OGSBrowserTab: String, CaseIterable {
    case challenge = "Challenge"
    case watch = "Watch"
}

// MARK: - AppModel
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
    
    @Published var browserTab: OGSBrowserTab = .challenge
    @Published var isCreatingChallenge: Bool = false
    
    // MARK: - Debugging
    @Published var showDebugDashboard: Bool = false
    
    @Published var layoutVM = LayoutViewModel()
    
    var boardVM: BoardViewModel?

    private var stoneClickPlayer: AVAudioPlayer?
    private var autoAdvanceTimer: Timer?
    private let folderKey = "sgfplayer.folderURL"
    private let lastGameKey = "sgfplayer.lastGame"
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.boardVM = BoardViewModel(player: player, ogsClient: ogsClient)
        
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
    
    // MARK: - OGS Logic (FIXED v3.24)
    func joinOnlineGame(id: Int) {
        print("AppModel: 🌍 User Requested ID \(id)")
        
        // 1. Reset Board
        player.clear()
        selection = nil
        boardVM?.resetToEmpty()
        
        // 2. Determine if it is a Challenge or a Game
        let isChallenge = ogsClient.availableGames.contains(where: { $0.id == id })
        
        if isChallenge {
            print("AppModel: ⚠️ Target is a CHALLENGE. Waiting for conversion...")
            // We do NOT set activeGameID yet, because it's the wrong ID (Challenge ID).
            // We call REST accept and wait for the "Game Started" socket event (or REST response).
            
            ogsClient.acceptChallenge(challengeID: id) { [weak self] newGameID, error in
                if let gameID = newGameID {
                    print("AppModel: ✅ REST Accept returned Real Game ID: \(gameID)")
                    self?.finalizeJoin(gameID: gameID)
                } else {
                    print("AppModel: ⚠️ REST Accept failed. Hoping for Socket event.")
                }
            }
        } else {
            // It's likely an existing Game (resume) or spectating
            print("AppModel: 🚀 Target is likely a GAME. Optimistic Join.")
            finalizeJoin(gameID: id)
        }
    }
    
    private func finalizeJoin(gameID: Int) {
        DispatchQueue.main.async {
            self.ogsClient.activeGameID = gameID
            self.ogsClient.joinGame(gameID: gameID)
        }
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
            
        // NEW: Handle Undo Accepted (Local Replay)
        NotificationCenter.default.publisher(for: NSNotification.Name("OGSUndoAccepted"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                print("AppModel: ↩️ Undo Accepted Notification. Replaying history locally...")
                self?.boardVM?.undoLastOnlineMove()
            }
            .store(in: &cancellables)
    }
    
    private func handleOGSGameLoad(_ notification: Notification) {
        // Stop the retry loop immediately
        ogsClient.cancelJoinRetry()
        
        guard let userInfo = notification.userInfo,
              let gameData = userInfo["gameData"] as? [String: Any] else { return }
        
        print("AppModel: 📦 OGS Game Loaded. Initializing Online Board...")
        boardVM?.stopAutoPlay()
        player.clear()
        
        // CRITICAL FIX: Reset board to ensure no stale stones remain from before Undo
        boardVM?.resetToEmpty()
        
        func getInt(_ value: Any?) -> Int? {
            if let i = value as? Int { return i }
            if let s = value as? String { return Int(s) }
            return nil
        }
        
        // 1. Setup Handicap
        var initialStones: [BoardPosition: Stone] = [:]
        
        if let explicitPlacement = gameData["free_handicap_placement"] as? [Any] {
            print("AppModel: Found \(explicitPlacement.count) explicit handicap stones")
            for item in explicitPlacement {
                if let coords = item as? [Any], coords.count >= 2,
                   let x = getInt(coords[0]), let y = getInt(coords[1]) {
                    initialStones[BoardPosition(y, x)] = .black
                }
            }
        } else if let handicapCount = getInt(gameData["handicap"]), handicapCount > 0 {
            print("AppModel: Found standard handicap count: \(handicapCount)")
            let boardWidth = getInt(gameData["width"]) ?? 19
            if boardWidth == 19 {
                let coordsList = getStandardHandicapCoordinates(count: handicapCount)
                for coords in coordsList {
                    initialStones[BoardPosition(coords[1], coords[0])] = .black
                }
            }
        }
        
        let width = getInt(gameData["width"]) ?? 19
        let height = getInt(gameData["height"]) ?? 19
        
        // 2. Initialize Online Board
        boardVM?.initializeOnlineGame(width: width, height: height, initialStones: initialStones)
        
        // 3. Replay Moves
        let moves = (userInfo["moves"] as? [[Any]]) ?? []
        print("AppModel: Replaying \(moves.count) history moves")
        
        for moveData in moves {
            if moveData.count >= 2, let x = getInt(moveData[0]), let y = getInt(moveData[1]) {
                boardVM?.handleRemoteMove(x: x, y: y, playerId: nil)
            }
        }
    }
    
    private func getStandardHandicapCoordinates(count: Int) -> [[Int]] {
        let stars: [String: [Int]] = [
            "TR": [15,3], "TL": [3,3], "BR": [15,15], "BL": [3,15],
            "MM": [9,9],
            "ML": [3,9], "MR": [15,9], "TM": [9,3], "BM": [9,15]
        ]
        
        switch count {
        case 2: return [stars["TR"]!, stars["BL"]!]
        case 3: return [stars["TR"]!, stars["BL"]!, stars["BR"]!]
        case 4: return [stars["TR"]!, stars["BL"]!, stars["BR"]!, stars["TL"]!]
        case 5: return [stars["TR"]!, stars["BL"]!, stars["BR"]!, stars["TL"]!, stars["MM"]!]
        case 6: return [stars["TR"]!, stars["BL"]!, stars["BR"]!, stars["TL"]!, stars["ML"]!, stars["MR"]!]
        case 7: return [stars["TR"]!, stars["BL"]!, stars["BR"]!, stars["TL"]!, stars["ML"]!, stars["MR"]!, stars["MM"]!]
        case 8: return [stars["TR"]!, stars["BL"]!, stars["BR"]!, stars["TL"]!, stars["ML"]!, stars["MR"]!, stars["TM"]!, stars["BM"]!]
        case 9: return [stars["TR"]!, stars["BL"]!, stars["BR"]!, stars["TL"]!, stars["ML"]!, stars["MR"]!, stars["TM"]!, stars["BM"]!, stars["MM"]!]
        default: return []
        }
    }
    
    private func handleOGSMove(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let x = userInfo["x"] as? Int, let y = userInfo["y"] as? Int else { return }
        if x >= 0 && y >= 0 {
            playStoneClickSound()
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
        boardVM?.loadGame(gameWrapper)
        
        if AppSettings.shared.startGameOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let vm = self.boardVM {
                    vm.startAutoPlay()
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
