import Foundation
import Combine

class OGSGameViewModel: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var currentGameID: Int?
    @Published var gamePhase: String = "none"
    
    private var ogsClient: OGSClient
    private var player: SGFPlayer
    private var timeControl: TimeControlManager
    
    init(ogsClient: OGSClient, player: SGFPlayer, timeControl: TimeControlManager) {
        self.ogsClient = ogsClient
        self.player = player
        self.timeControl = timeControl
    }
}
