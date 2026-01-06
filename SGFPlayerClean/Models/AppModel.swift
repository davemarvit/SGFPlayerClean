// ========================================================
// FILE: ./Models/AppModel.swift
// VERSION: v4.800 (Restore Handicap Bump)
// ========================================================
import Foundation
import SwiftUI
import Combine
import AVFoundation

final class AppModel: ObservableObject {
    @AppStorage("verboseLogging") var verboseLogging: Bool = false
    @AppStorage("viewMode") var viewMode: ViewMode = .view2D
    
    @Published var folderURL: URL? { didSet { persistFolderURL() } }
    @Published var games: [SGFGameWrapper] = []
    @Published var selection: SGFGameWrapper? = nil { didSet { persistLastGame() } }
    @Published var activePlaylist: [SGFGameWrapper] = []
    
    @Published var player = SGFPlayer()
    @Published var isLoadingGames: Bool = false
    
    @Published var ogsClient = OGSClient()
    @Published var layoutVM = LayoutViewModel()
    @Published var timeControl = TimeControlManager()
    @Published var ogsGame: OGSGameViewModel?
    @Published var gameCacheManager = GameCacheManager()
    
    @Published var isOnlineMode: Bool = false
    @Published var showPreGameOverlay: Bool = false
    @Published var browserTab: OGSBrowserTab = .challenge
    @Published var isCreatingChallenge: Bool = false
    @Published var showDebugDashboard: Bool = false
    
    var boardVM: BoardViewModel?
    private var stoneClickPlayer: AVAudioPlayer?
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        self.boardVM = BoardViewModel(player: player, ogsClient: ogsClient)
        self.ogsGame = OGSGameViewModel(ogsClient: ogsClient, player: player, timeControl: timeControl)
        restoreFolderURL()
        if let url = folderURL { loadFolder(url) }
        setupAudio()
        self.ogsClient.connect()
        setupOGSObservers()
    }
    
    // MARK: - Online Game Logic
    func joinOnlineGame(id: Int) {
        print("🔍 [AppModel] Joining game \(id)...")
        player.clear()
        self.ogsClient.acceptChallenge(challengeID: id) { [weak self] newGameID, _ in
            if let gameID = newGameID {
                print("🔍 [AppModel] Challenge accepted. New Game ID: \(gameID)")
                self?.finalizeJoin(gameID: gameID)
            } else { print("❌ [AppModel] Failed to accept challenge.") }
        }
    }
    
    private func finalizeJoin(gameID: Int) {
        print("🔍 [AppModel] Fetching game state for \(gameID)...")
        self.ogsClient.fetchGameState(gameID: gameID) { [weak self] (rootJson: [String: Any]?) in
            guard let self = self, let root = rootJson else { print("❌ [AppModel] fetchGameState returned nil."); return }
            var payload: [String: Any] = [:]
            if let inner = root["gamedata"] as? [String: Any] { payload = inner } else { payload = root }
            
            DispatchQueue.main.async {
                if let auth = root["auth"] as? String {
                    self.ogsClient.activeGameAuth = auth
                    print("🔍 [AppModel] Auth Token Captured.")
                }
                NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": payload])
                self.ogsClient.connectToGame(gameID: gameID)
            }
        }
    }
    
    private func setupOGSObservers() {
        let c = NotificationCenter.default
        c.publisher(for: NSNotification.Name("OGSGameDataReceived")).receive(on: RunLoop.main).sink { [weak self] n in self?.handleOGSGameLoad(n) }.store(in: &cancellables)
        c.publisher(for: NSNotification.Name("OGSMoveReceived")).receive(on: RunLoop.main).sink { [weak self] n in self?.handleOGSMoveUpdate(n) }.store(in: &cancellables)
    }
    
    // MARK: - Parsing Logic
    private func handleOGSGameLoad(_ notification: Notification) {
        print("🔍 [AppModel] handleOGSGameLoad triggered.")
        guard let userInfo = notification.userInfo, let gameData = userInfo["gameData"] as? [String: Any] else { return }
        
        player.clear()
        var initialStones: [BoardPosition: Stone] = [:]
        
        // 1. Initial State String
        if let state = gameData["initial_state"] as? [String: Any] {
            if let bStr = state["black"] as? String {
                let chars = Array(bStr)
                for i in stride(from: 0, to: chars.count, by: 2) {
                    if i + 1 < chars.count {
                        let coord = String(chars[i...i+1])
                        if let (x, y) = SGFCoordinates.parse(coord) { initialStones[BoardPosition(y, x)] = .black }
                    }
                }
            }
            if let wStr = state["white"] as? String {
                let chars = Array(wStr)
                for i in stride(from: 0, to: chars.count, by: 2) {
                    if i + 1 < chars.count {
                        let coord = String(chars[i...i+1])
                        if let (x, y) = SGFCoordinates.parse(coord) { initialStones[BoardPosition(y, x)] = .white }
                    }
                }
            }
        }
        
        // 2. Free Handicap Fallback
        if let handicapStones = gameData["free_handicap_placement"] as? [[Int]] {
            for coords in handicapStones {
                if coords.count >= 2 { initialStones[BoardPosition(coords[1], coords[0])] = .black }
            }
        }
        
        print("✅ [AppModel] Parsed \(initialStones.count) stones.")
        
        let nextTurn: Stone = (gameData["initial_player"] as? String == "white") ? .white : .black
        var moveNumber = gameData["move_number"] as? Int ?? 0
        let handicap = gameData["handicap"] as? Int ?? 0
        let moves = gameData["moves"] as? [[Any]] ?? []
        
        // v4.800: RESTORED HANDICAP BUMP
        // If handicap exists and no moves played, OGS treats handicap as Move 1.
        // We set our internal clock to 1 so the next move sent is #2.
        if handicap > 0 && moves.isEmpty && moveNumber == 0 && nextTurn == .white {
            print("⚠️ [AppModel] Handicap detected. Bumping base move number to 1.")
            moveNumber = 1
        }
        
        boardVM?.initializeOnlineGame(
            width: gameData["width"] as? Int ?? 19,
            height: gameData["height"] as? Int ?? 19,
            initialStones: initialStones,
            nextTurn: nextTurn,
            moveNumber: moveNumber
        )
        
        // Replay history
        print("🔍 [AppModel] Replaying \(moves.count) moves.")
        for m in moves {
            if m.count >= 2, let x = m[0] as? Int, let y = m[1] as? Int {
                boardVM?.handleRemoteMove(x: x, y: y, playerId: nil)
            }
        }
    }
    
    private func handleOGSMoveUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        if let m = userInfo["move"] as? [Any], m.count >= 2,
           let x = m[0] as? Int, let y = m[1] as? Int,
           let mn = userInfo["move_number"] as? Int {
            let pid = userInfo["player_id"] as? Int
            let color: Stone = (pid == ogsClient.blackPlayerID) ? .black : .white
            print("⚡️ [AppModel] Live Move: \(x),\(y) (\(color)) #\(mn)")
            playStoneClickSound()
            player.applyOnlineMove(color: color, x: x, y: y, moveNumber: mn)
        }
    }
    
    // MARK: - File & Audio Logic (Unchanged)
    private func setupAudio() {
        if let url = Bundle.main.url(forResource: "Stone_click_1", withExtension: "mp3") {
            stoneClickPlayer = try? AVAudioPlayer(contentsOf: url); stoneClickPlayer?.prepareToPlay()
        }
    }
    func playStoneClickSound() { stoneClickPlayer?.play() }
    func selectGame(_ g: SGFGameWrapper) { selection = g; boardVM?.loadGame(g) }
    func promptForFolder() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true
        if p.runModal() == .OK, let u = p.url { folderURL = u; loadFolder(u) }
    }
    func loadFolder(_ u: URL) {
        isLoadingGames = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default; var urls: [URL] = []
            if let en = fm.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let f as URL in en { if f.pathExtension.lowercased() == "sgf" { urls.append(f) } }
            }
            urls.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            var p: [SGFGameWrapper] = []
            for f in urls {
                if let d = try? Data(contentsOf: f), let t = String(data: d, encoding: .utf8), let tree = try? SGFParser.parse(text: t) {
                    p.append(SGFGameWrapper(url: f, game: SGFGame.from(tree: tree)))
                }
            }
            DispatchQueue.main.async { self.games = p; self.activePlaylist = p; self.isLoadingGames = false; if let f = p.first { self.selectGame(f) } }
        }
    }
    private func persistFolderURL() { if let u = folderURL, let b = try? u.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(b, forKey: "sgfplayer.folderURL") } }
    private func restoreFolderURL() { if let b = UserDefaults.standard.data(forKey: "sgfplayer.folderURL") { var isStale = false; if let u = try? URL(resolvingBookmarkData: b, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) { if u.startAccessingSecurityScopedResource() { folderURL = u } } } }
    private func persistLastGame() { if let s = selection { UserDefaults.standard.set(s.url.lastPathComponent, forKey: "sgfplayer.lastGame") } }
}
