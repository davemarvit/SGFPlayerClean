import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

final class AppModel: ObservableObject {
    @AppStorage("verboseLogging") var verboseLogging: Bool = false
    @AppStorage("viewMode") var viewMode: ViewMode = .view2D

    @Published var folderURL: URL? { didSet { persistFolderURL() } }
    @Published var games: [SGFGameWrapper] = []
    @Published var selection: SGFGameWrapper? = nil { didSet { persistLastGame() } }
    @Published var activePlaylist: [SGFGameWrapper] = []
    @Published var gameCacheManager = GameCacheManager()
    @Published var player = SGFPlayer()
    @Published var isLoadingGames: Bool = false

    @Published var ogsClient = OGSClient()
    @Published var timeControl = TimeControlManager()
    @Published var ogsGame: OGSGameViewModel?
    @Published var gameSettings: GameSettings = GameSettings.load()
    @Published var isOnlineMode: Bool = false
    @Published var showPreGameOverlay: Bool = false
    @Published var browserTab: OGSBrowserTab = .challenge
    @Published var isCreatingChallenge: Bool = false
    @Published var showDebugDashboard: Bool = false
    @Published var layoutVM = LayoutViewModel()
    
    var boardVM: BoardViewModel?
    private var stoneClickPlayer: AVAudioPlayer?
    private var autoAdvanceTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.boardVM = BoardViewModel(player: player, ogsClient: ogsClient)
        restoreFolderURL()
        if let url = folderURL { loadFolder(url) }
        setupAudio()
        self.ogsGame = OGSGameViewModel(ogsClient: ogsClient, player: player, timeControl: timeControl)
        self.ogsClient.connect()
        
        setupOGSObservers()
        setupAutoAdvanceMonitor()
        
        self.ogsClient.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        
        self.ogsClient.$activeGameID.receive(on: RunLoop.main).sink { [weak self] newID in
            if newID != nil {
                self?.boardVM?.resetToEmpty()
                self?.selection = nil
                self?.player.clear()
            }
        }.store(in: &cancellables)
    }
    
    func joinOnlineGame(id: Int) {
        DispatchQueue.main.async {
            self.ogsClient.activeGameAuth = nil
            self.player.clear(); self.selection = nil; self.boardVM?.resetToEmpty()
            if self.ogsClient.availableGames.contains(where: { $0.id == id }) {
                self.ogsClient.acceptChallenge(challengeID: id) { [weak self] newGameID, _ in
                    if let gameID = newGameID { self?.finalizeJoin(gameID: gameID) }
                }
            } else { self.finalizeJoin(gameID: id) }
        }
    }
    
    private func finalizeJoin(gameID: Int) {
        DispatchQueue.main.async {
            self.ogsClient.activeGameID = gameID
            self.ogsClient.fetchGameState(gameID: gameID) { [weak self] (rootJson: [String: Any]?) in
                guard let self = self, let root = rootJson else { return }
                var payload: [String: Any] = [:]
                if let inner = root["gamedata"] as? [String: Any] { payload = inner } else { payload = root }
                DispatchQueue.main.async {
                    if let auth = root["auth"] as? String { self.ogsClient.activeGameAuth = auth }
                    let userInfo: [String: Any] = ["gameData": payload, "moves": payload["moves"] ?? []]
                    let n = Notification(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: userInfo)
                    self.handleOGSGameLoad(n)
                    self.ogsClient.connectToGame(gameID: gameID)
                }
            }
        }
    }
    
    private func setupOGSObservers() {
        let c = NotificationCenter.default
        c.publisher(for: NSNotification.Name("OGSGameDataReceived")).receive(on: RunLoop.main).sink { [weak self] n in self?.handleOGSGameLoad(n) }.store(in: &cancellables)
        c.publisher(for: NSNotification.Name("OGSMoveReceived")).receive(on: RunLoop.main).sink { [weak self] n in self?.handleOGSMove(n) }.store(in: &cancellables)
        c.publisher(for: NSNotification.Name("OGSUndoAccepted")).receive(on: RunLoop.main).sink { [weak self] _ in self?.boardVM?.undoLastOnlineMove() }.store(in: &cancellables)
    }
    
    private func handleOGSGameLoad(_ notification: Notification) {
        ogsClient.cancelJoinRetry()
        guard let userInfo = notification.userInfo, let gameData = userInfo["gameData"] as? [String: Any] else { return }
        boardVM?.stopAutoPlay(); player.clear(); boardVM?.resetToEmpty()
        if let auth = gameData["auth"] as? String { ogsClient.activeGameAuth = auth }
        if let players = gameData["players"] as? [String: Any] {
            if let w = players["white"] as? [String: Any] { ogsClient.whitePlayerID = w["id"] as? Int; ogsClient.whitePlayerName = w["username"] as? String; ogsClient.whitePlayerRank = (w["ranking"] as? Double) ?? (w["rank"] as? Double) }
            if let b = players["black"] as? [String: Any] { ogsClient.blackPlayerID = b["id"] as? Int; ogsClient.blackPlayerName = b["username"] as? String; ogsClient.blackPlayerRank = (b["ranking"] as? Double) ?? (b["rank"] as? Double) }
        }
        if let clock = gameData["clock"] as? [String: Any] {
            if let current = clock["current_player"] as? Int { ogsClient.currentPlayerID = current }
            if let bDict = clock["black_time"] as? [String: Any] { if let t = bDict["thinking_time"] as? Double { ogsClient.blackTimeRemaining = t } }
            else if let bTime = clock["black_time"] as? Double { ogsClient.blackTimeRemaining = bTime }
            if let wDict = clock["white_time"] as? [String: Any] { if let t = wDict["thinking_time"] as? Double { ogsClient.whiteTimeRemaining = t } }
            else if let wTime = clock["white_time"] as? Double { ogsClient.whiteTimeRemaining = wTime }
        }
        if let pid = ogsClient.playerID {
            if pid == ogsClient.blackPlayerID { ogsClient.playerColor = .black } else if pid == ogsClient.whitePlayerID { ogsClient.playerColor = .white }
        }
        let width = (gameData["width"] as? Int) ?? 19
        boardVM?.initializeOnlineGame(width: width, height: width, initialStones: [:])
        let moves = (userInfo["moves"] as? [[Any]]) ?? []
        for m in moves { if m.count >= 2, let x = m[0] as? Int, let y = m[1] as? Int { boardVM?.handleRemoteMove(x: x, y: y, playerId: nil) } }
    }
    
    private func handleOGSMove(_ notification: Notification) {
        guard let userInfo = notification.userInfo, let x = userInfo["x"] as? Int, let y = userInfo["y"] as? Int else { return }
        playStoneClickSound(); boardVM?.handleRemoteMove(x: x, y: y, playerId: userInfo["player_id"] as? Int)
    }

    func setupAutoAdvanceMonitor() {
        guard let b = boardVM else { return }
        b.$currentMoveIndex.combineLatest(b.$isAutoPlaying).sink { [weak self] m, p in
            if p && m >= b.totalMoves && m > 0 { self?.autoAdvanceTimer?.invalidate(); self?.autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in self?.advanceToNextGame(from: self?.activePlaylist ?? []) } }
        }.store(in: &cancellables)
    }
    private func setupAudio() { if let url = Bundle.main.url(forResource: "Stone_click_1", withExtension: "mp3") { stoneClickPlayer = try? AVAudioPlayer(contentsOf: url); stoneClickPlayer?.prepareToPlay() } }
    func playStoneClickSound() { stoneClickPlayer?.play() }
    func selectGame(_ g: SGFGameWrapper) { selection = g; boardVM?.loadGame(g) }
    func pickRandomGame(from l: [SGFGameWrapper]) { if !l.isEmpty { selectGame(l[Int.random(in: 0..<l.count)]) } }
    func advanceToNextGame(from l: [SGFGameWrapper]) {
        guard !l.isEmpty, let i = l.firstIndex(where: { $0.id == selection?.id }) else { if let f = l.first { selectGame(f) }; return }
        selectGame(l[(i + 1) % l.count])
    }
    func promptForFolder() { let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; if p.runModal() == .OK, let u = p.url { folderURL = u; loadFolder(u) } }
    func reload() { if let url = folderURL { loadFolder(url) } }
    private func loadFolder(_ u: URL) {
        isLoadingGames = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default; var urls: [URL] = []
            if let en = fm.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) { for case let f as URL in en { if f.pathExtension.lowercased() == "sgf" { urls.append(f) } } }
            urls.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }; var p: [SGFGameWrapper] = []
            for f in urls { if let d = try? Data(contentsOf: f), let t = String(data: d, encoding: .utf8), let tree = try? SGFParser.parse(text: t) { p.append(SGFGameWrapper(url: f, game: SGFGame.from(tree: tree))) } }
            DispatchQueue.main.async { self.games = p; self.activePlaylist = p; self.isLoadingGames = false; if let f = p.first { self.selectGame(f) } }
        }
    }
    private func persistFolderURL() { if let u = folderURL, let b = try? u.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(b, forKey: "sgfplayer.folderURL") } }
    private func restoreFolderURL() { if let b = UserDefaults.standard.data(forKey: "sgfplayer.folderURL") { var isStale = false; if let u = try? URL(resolvingBookmarkData: b, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) { if u.startAccessingSecurityScopedResource() { folderURL = u } } } }
    private func persistLastGame() { if let s = selection { UserDefaults.standard.set(s.url.lastPathComponent, forKey: "sgfplayer.lastGame") } }
}
