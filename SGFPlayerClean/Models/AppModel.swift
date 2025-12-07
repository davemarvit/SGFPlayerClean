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
    
    // Shared UI State
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
    
    // MARK: - OGS Logic
    func joinOnlineGame(id: Int) {
        print("AppModel: 🌍 Request to join ID \(id)")
        player.clear()
        selection = nil
        
        if ogsClient.availableGames.contains(where: { $0.id == id }) {
            print("AppModel: 🧐 ID \(id) is a Challenge. Accepting...")
            ogsClient.acceptChallenge(challengeID: id) { [weak self] newGameID in
                if let gameID = newGameID {
                    print("AppModel: 🔀 Challenge Accepted. Connecting to Game \(gameID)")
                    self?.ogsClient.activeGameID = gameID
                    self?.ogsClient.joinGame(gameID: gameID)
                } else {
                    print("AppModel: ❌ Failed to accept challenge.")
                }
            }
        } else {
            print("AppModel: 🧐 ID \(id) assumed to be Active Game. Connecting...")
            ogsClient.activeGameID = id
            ogsClient.joinGame(gameID: id)
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
    }
    
    private func handleOGSGameLoad(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let gameData = userInfo["gameData"] as? [String: Any],
              let moves = userInfo["moves"] as? [[Any]] else { return }
        
        print("AppModel: 📦 OGS Game Loaded. Parsing...")
        boardVM?.stopAutoPlay()
        player.clear()
        
        // 1. HANDICAP DETECTION & PLACEMENT
        var manualHandicapStones: [[Int]] = []
        
        if let explicitPlacement = gameData["free_handicap_placement"] as? [[Int]], !explicitPlacement.isEmpty {
            manualHandicapStones = explicitPlacement
            print("AppModel: ⚫️ Found \(explicitPlacement.count) Explicit Handicap Stones.")
        } else if let handicapCount = gameData["handicap"] as? Int, handicapCount > 0 {
            // GENERATE STANDARD COORDINATES
            let boardWidth = gameData["width"] as? Int ?? 19
            let boardHeight = gameData["height"] as? Int ?? 19
            if boardWidth == 19 && boardHeight == 19 {
                manualHandicapStones = getStandardHandicapCoordinates(count: handicapCount)
                print("AppModel: ⚠️ Generated \(manualHandicapStones.count) Standard Handicap Stones.")
            } else {
                print("AppModel: ❌ Unsupported board size for auto-handicap: \(boardWidth)x\(boardHeight)")
            }
        }
        
        // PLAY HANDICAP STONES
        // We play them as standard Black moves. This advances 'player.currentIndex'.
        // Example: 9 stones -> Index becomes 9.
        // Standard turn logic (Even=Black, Odd=White) means Move 9 is White's turn.
        // This effectively handles the "White moves first" rule without special flags.
        if !manualHandicapStones.isEmpty {
            for coords in manualHandicapStones {
                if coords.count >= 2 {
                    player.playMoveOptimistically(color: .black, x: coords[0], y: coords[1])
                }
            }
            // Ensure we don't double-compensate in VM
            boardVM?.isHandicapGame = false
        } else {
            // Reset flag just in case
            boardVM?.isHandicapGame = false
        }
        
        // 2. PROCESS MOVES
        print("AppModel: 📜 Replaying \(moves.count) historical moves...")
        for moveData in moves {
            if moveData.count >= 2, let x = moveData[0] as? Int, let y = moveData[1] as? Int {
                if x >= 0 && y >= 0 {
                    let nextColor = boardVM?.nextTurnColor ?? .black
                    player.playMoveOptimistically(color: nextColor, x: x, y: y)
                }
            }
        }
        player.seek(to: player.maxIndex)
    }
    
    // Helper for 19x19 star points
    private func getStandardHandicapCoordinates(count: Int) -> [[Int]] {
        // Standard OGS/SGF Star Points (0-indexed):
        // TL(3,3), TM(9,3), TR(15,3)
        // ML(3,9), MM(9,9), MR(15,9)
        // BL(3,15), BM(9,15), BR(15,15)
        
        // Fixed sets for 19x19 based on Japanese rules commonly used
        let stars: [String: [Int]] = [
            "TR": [15,3], "TL": [3,3], "BR": [15,15], "BL": [3,15],
            "MM": [9,9], // Tengen
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
        playStoneClickSound()
        // BoardViewModel listens to this same notification to update its state
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
