// ========================================================
// FILE: ./Models/AppModel.swift
// VERSION: v4.881 (Discovery Coordination / Explicit Alignment)
// ========================================================
import Foundation
import SwiftUI
import Combine
import AVFoundation

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("viewMode") var viewMode: ViewMode = .view2D
    @Published var games: [SGFGameWrapper] = []
    @Published var selection: SGFGameWrapper? = nil
    @Published var player = SGFPlayer()
    @Published var ogsClient = OGSClient()
    @Published var layoutVM = LayoutViewModel()
    @Published var timeControl = TimeControlManager()
    @Published var ogsGame: OGSGameViewModel?
    @Published var isOnlineMode: Bool = false
    @Published var isCreatingChallenge: Bool = false
    @Published var showDebugDashboard: Bool = false
    @Published var boardVM: BoardViewModel?
    
    private var cancellables: Set<AnyCancellable> = []
    private var currentActiveInternalGameID: Int? = nil
    private var stoneClickPlayer: AVAudioPlayer?

    init() {
        let bVM = BoardViewModel(player: player, ogsClient: ogsClient)
        self.boardVM = bVM
        self.ogsGame = OGSGameViewModel(ogsClient: ogsClient, player: player, timeControl: timeControl)
        
        ogsClient.$activeGameID
            .receive(on: RunLoop.main)
            .sink { [weak self] gid in
                if gid != nil { self?.isOnlineMode = true }
            }.store(in: &cancellables)

        ogsClient.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        setupAudio(); self.ogsClient.connect(); setupOGSObservers()
    }
    
    private func robustInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }
    
    func joinOnlineGame(id: Int) {
        self.player.clear()
        self.boardVM?.resetToEmpty()
        self.currentActiveInternalGameID = nil
        self.isOnlineMode = false
        
        // PILLAR: Explicit parameter typing to resolve inference errors
        self.ogsClient.acceptChallenge(challengeID: id) { [weak self] (newGameID: Int?, error: Error?) in
            guard let self = self else { return }
            if let gid = newGameID {
                self.ogsClient.fetchGameState(gameID: gid) { [weak self] (rootJson: [String: Any]?) in
                    guard let root = rootJson else { return }
                    let data = (root["gamedata"] as? [String: Any]) ?? root
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": data])
                    }
                }
            }
        }
    }
    
    private func setupOGSObservers() {
        let nc = NotificationCenter.default
        nc.publisher(for: NSNotification.Name("OGSGameDataReceived")).receive(on: RunLoop.main).sink { [weak self] n in self?.handleOGSGameLoad(n) }.store(in: &cancellables)
        nc.publisher(for: NSNotification.Name("OGSMoveReceived")).receive(on: RunLoop.main).sink { [weak self] n in self?.handleOGSMoveUpdate(n) }.store(in: &cancellables)
    }
    
    private func handleOGSGameLoad(_ notification: Notification) {
        guard let userInfo = notification.userInfo, let gameData = userInfo["gameData"] as? [String: Any] else { return }
        
        let gameID = robustInt(gameData["game_id"]) ?? robustInt(gameData["id"]) ?? 0
        guard gameID == ogsClient.activeGameID else { return }
        
        let isSameGame = (currentActiveInternalGameID == gameID)
        self.isOnlineMode = true
        
        if !isSameGame || player.board.stones.isEmpty {
            currentActiveInternalGameID = gameID
            
            let width = gameData["width"] as? Int ?? 19
            let height = gameData["height"] as? Int ?? 19
            var initialStones: [BoardPosition: Stone] = [:]
            
            if let state = gameData["initial_state"] as? [String: Any] {
                ["black", "white"].forEach { col in
                    if let str = state[col] as? String {
                        let color: Stone = col == "black" ? .black : .white
                        let chars = Array(str)
                        for i in stride(from: 0, to: chars.count, by: 2) {
                            if i + 1 < chars.count, let (x, y) = SGFCoordinates.parse(String(chars[i...i+1])) {
                                initialStones[BoardPosition(y, x)] = color
                            }
                        }
                    }
                }
            }
            
            let initialTurnColor: Stone = (gameData["initial_player"] as? String == "white") ? .white : .black
            let stateVersion = robustInt(gameData["state_version"]) ?? robustInt(gameData["move_number"]) ?? 0
            
            boardVM?.initializeOnlineGame(width: width, height: height, initialStones: initialStones, nextPlayer: initialTurnColor, stateVersion: stateVersion)
            
            let moveHistory = gameData["moves"] as? [[Any]] ?? []
            var turnColor = initialTurnColor
            for m in moveHistory {
                if m.count >= 2, let x = robustInt(m[0]), let y = robustInt(m[1]) {
                    if x >= 0 && y >= 0 { boardVM?.handleRemoteMove(x: x, y: y, color: turnColor) }
                    turnColor = turnColor.opponent
                }
            }
        }
        
        boardVM?.syncState()
        self.objectWillChange.send()
    }
    
    private func handleOGSMoveUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        if let gid = robustInt(userInfo["game_id"]), gid != ogsClient.activeGameID { return }

        var x: Int = -1
        var y: Int = -1
        if let mArr = userInfo["move"] as? [Any], mArr.count >= 2 {
            x = robustInt(mArr[0]) ?? -1
            y = robustInt(mArr[1]) ?? -1
        } else if let mStr = userInfo["move"] as? String {
            if let (sx, sy) = SGFCoordinates.parse(mStr) { x = sx; y = sy }
        }
        
        if x >= 0 && y >= 0 {
            if let mn = robustInt(userInfo["move_number"]) {
                let color: Stone
                if let pid = robustInt(userInfo["player_id"]) {
                    color = (pid == ogsClient.blackPlayerID) ? .black : .white
                } else {
                    color = (ogsClient.currentHandicap > 0) ? ((mn % 2 == 0) ? .black : .white) : ((mn % 2 == 0) ? .white : .black)
                }
                playStoneClickSound()
                player.applyOnlineMove(color: color, x: x, y: y, moveNumber: mn)
            }
        }
    }
    
    private func setupAudio() { if let url = Bundle.main.url(forResource: "Stone_click_1", withExtension: "mp3") { stoneClickPlayer = try? AVAudioPlayer(contentsOf: url); stoneClickPlayer?.prepareToPlay() } }
    func playStoneClickSound() { stoneClickPlayer?.play() }
    func selectGame(_ g: SGFGameWrapper) { selection = g; boardVM?.loadGame(g) }
    func promptForFolder() { /* Implementation */ }
    func loadFolder(_ u: URL) { /* Implementation */ }
}
