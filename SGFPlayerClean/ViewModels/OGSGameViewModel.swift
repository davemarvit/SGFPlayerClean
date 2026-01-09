// MARK: - File: OGSGameViewModel.swift (v4.205)
import Foundation
import Combine

class OGSGameViewModel: ObservableObject {
    @Published var gameInfo: GameInfo?
    @Published var isMyTurn: Bool = false
    @Published var gameStatus: String = "Connecting..."
    @Published var gamePhase: String = "none"
    
    private var ogsClient: OGSClient
    private var player: SGFPlayer
    private var cancellables = Set<AnyCancellable>()
    
    init(ogsClient: OGSClient, player: SGFPlayer, timeControl: TimeControlManager) {
        self.ogsClient = ogsClient
        self.player = player
        setupObservers()
    }
    
    private func setupObservers() {
        ogsClient.$activeGameID.sink { [weak self] id in
            if id == nil {
                self?.gameStatus = "Not in a game"
                self?.gamePhase = "none"
            }
        }.store(in: &cancellables)
        
        ogsClient.$currentPlayerID.sink { [weak self] current in
            guard let self = self, let myID = self.ogsClient.playerID else { return }
            self.isMyTurn = (current == myID)
            self.gameStatus = self.isMyTurn ? "Your turn" : "Waiting for opponent"
        }.store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("OGSGameDataReceived"))
            .sink { [weak self] notification in
                if let data = notification.userInfo?["gameData"] as? [String: Any],
                   let phase = data["phase"] as? String {
                    DispatchQueue.main.async { self?.gamePhase = phase }
                }
            }.store(in: &cancellables)
    }
    
    func pass() {
        guard let id = ogsClient.activeGameID else { return }
        // PILLAR: Refactored call site
        ogsClient.sendPass(gameID: id)
    }
    
    func resign() {
        guard let id = ogsClient.activeGameID else { return }
        ogsClient.resignGame(gameID: id)
    }
    
    func startQuickMatch() {
        ogsClient.startAutomatch()
    }
}
