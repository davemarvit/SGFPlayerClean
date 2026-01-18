// MARK: - File: OGSGameViewModel.swift (v4.205)
import Foundation
import Combine

class OGSGameViewModel: ObservableObject {
    @Published var gameInfo: GameInfo?
    @Published var isMyTurn: Bool = false
    @Published var gameStatus: String = "Connecting..."
    @Published var gamePhase: String = "none"
    
    @Published var chatMessages: [OGSChatMessage] = []
    
    private var ogsClient: OGSClient
    private var player: SGFPlayer
    private var cancellables = Set<AnyCancellable>()
    
    init(ogsClient: OGSClient, player: SGFPlayer, timeControl: TimeControlManager) {
        self.ogsClient = ogsClient
        self.player = player
        setupObservers()
        setupChatObservers()
    }
    
    private func setupObservers() {
        ogsClient.$activeGameID.sink { [weak self] id in
            if id == nil {
                self?.gameStatus = "Not in a game"
                self?.gamePhase = "none"
                self?.chatMessages = []
            } else {
                // Clear chat when joining a new game (or we could fetch history if OGS provided it easily)
                // OGS sends recent chat in 'gamedata' usually, but for now we start fresh or rely on connection data.
                self?.chatMessages = []
            }
        }.store(in: &cancellables)
        
        ogsClient.$currentPlayerID.sink { [weak self] current in
            guard let self = self, let myID = self.ogsClient.playerID else { return }
            self.isMyTurn = (current == myID)
            self.gameStatus = self.isMyTurn ? "Your turn" : "Waiting for opponent"
        }.store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("OGSGameDataReceived"))
            .sink { [weak self] notification in
                if let data = notification.userInfo?["gameData"] as? [String: Any] {
                    if let phase = data["phase"] as? String {
                        DispatchQueue.main.async { self?.gamePhase = phase }
                    }
                    
                    // Optional: Parse existing chat history from gamedata["chat"]
                    if let chatArray = data["chat"] as? [[String: Any]] {
                        self?.parseInitialChat(chatArray)
                    }
                }
            }.store(in: &cancellables)
    }
    
    private func setupChatObservers() {
        NotificationCenter.default.publisher(for: NSNotification.Name("OGSChatReceived"))
            .sink { [weak self] notification in
                guard let self = self, let data = notification.userInfo as? [String: Any] else { return }
                // Verify it belongs to active game (payload usually has game_id, or we infer)
                // OGSClient filters events by gameID usually, but check content just in case or trust client.
                // Note: OGSClient `processEventMessage` checks gameID for specific prefixes, but general chat might bleed?
                // `handleIncomingChat` calls verify gameID in payload?
                // The payload from OGS for chat usually lacks game_id in the *body* sometimes, 
                // but the event name `game/123/chat` ensures it's the right game.
                
                self.handleIncomingChat(data)
            }.store(in: &cancellables)
    }
    
    private func handleIncomingChat(_ data: [String: Any]) {
        // OGS Protocol Update (Jan 2026):
        // Payload comes in two flavors:
        // 1. Nested: { "line": { "username": "Dave", "body": "Hello", ... }, "channel": "main" }
        // 2. Flat (Legacy/System): { "username": "System", "body": "...", "type": "main" }
        
        var body: String?
        var username: String?
        var type: String = "main"
        var date: Date = Date()
        
        if let line = data["line"] as? [String: Any] {
            username = line["username"] as? String
            body = line["body"] as? String
            if let ts = line["date"] as? Int { date = Date(timeIntervalSince1970: TimeInterval(ts)) }
            type = (data["channel"] as? String) ?? "main" // 'channel' is strictly 'main' or 'spectator' usually
        } else {
            // Flat Layout
            username = data["username"] as? String
            body = data["body"] as? String
            type = (data["type"] as? String) ?? "main"
        }
        
        guard let safeUser = username, let safeBody = body else { return }
        
        // Type check
        // let type = data["type"] as? String ?? "main" // Already parsed above

        
        let isMe = (safeUser == ogsClient.username)
        let msg = OGSChatMessage(
            timestamp: date,
            sender: safeUser,
            message: safeBody,
            isSelf: isMe,
            type: type
        )
        
        DispatchQueue.main.async {
            // Append and generic limit
            self.chatMessages.append(msg)
            if self.chatMessages.count > 100 { self.chatMessages.removeFirst() }
        }
    }
    
    private func parseInitialChat(_ chatArray: [[String: Any]]) {
        // "chat": [ { "username":..., "body":..., "date":... } ]
        var loaded: [OGSChatMessage] = []
        for c in chatArray {
             guard let username = c["username"] as? String,
                   let body = c["body"] as? String else { continue }
             let isMe = (username == ogsClient.username)
             let date = (c["date"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
             
             loaded.append(OGSChatMessage(
                timestamp: date,
                sender: username,
                message: body,
                isSelf: isMe,
                type: (c["type"] as? String) ?? "main"
             ))
        }
        // Sort by date just in case
        loaded.sort { $0.timestamp < $1.timestamp }
        
        DispatchQueue.main.async {
            self.chatMessages = loaded
        }
    }
    
    func sendChat(_ text: String) {
        guard let id = ogsClient.activeGameID, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Optimistic Update? OGS echoes back the chat, so wait for echo to avoid dupes.
        // But for UI responsiveness, users like instant feedback.
        // OGS echo is fast. Let's wait for echo to be safe against lag/failure.
        
        // DEBUG TRACE for Spaces Issue
        NSLog("[OGS-CHAT-TRACE] ViewModel received: '\(text)' (Hex: \(text.data(using: .utf8)?.map { String(format: "%02x", $0) }.joined() ?? ""))")
        
        ogsClient.sendChat(gameID: id, text: text)
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
