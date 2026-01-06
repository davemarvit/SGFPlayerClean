// ========================================================
// FILE: ./Services/OGSClient.swift
// VERSION: v16.092 (State-Observer-Fixed / Handshake-Traced)
// ========================================================

import Foundation
import Combine

class OGSClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    let buildVersion = "16.092"
    
    // MARK: - Published State (Strict UI Refresh)
    @Published var isConnected = false
    @Published var isSocketAuthenticated = false
    @Published var isAuthenticated = false
    @Published var lastError: String? = nil
    @Published var username: String?
    @Published var playerID: Int?
    @Published var userJWT: String?
    
    @Published var activeGameID: Int?
    @Published var activeGameAuth: String?
    @Published var playerColor: Stone?
    @Published var currentPlayerID: Int?
    @Published var blackPlayerID: Int?; @Published var whitePlayerID: Int?
    @Published var availableGames: [OGSChallenge] = []
    @Published var isSubscribedToSeekgraph = false
    @Published var trafficLogs: [NetworkLogEntry] = []
    
    // Identity, Clocks & Undo
    @Published var blackPlayerName: String?; @Published var whitePlayerName: String?
    @Published var blackTimeRemaining: TimeInterval?; @Published var whiteTimeRemaining: TimeInterval?
    @Published var undoRequestedUsername: String? = nil
    @Published var undoRequestedMoveNumber: Int? = nil

    // MARK: - Internal State
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var socketPingTimer: Timer?
    private var enginePulseTimer: Timer?
    private var lobbyChallenges: [Int: OGSChallenge] = [:]
    
    private var lastServerThinkingTime: Double = 3600.0
    private var turnStartLocalTime: Date?
    private var lastReportedLatency: Int = 85
    private var currentStateVersion: Int = 0
    private var sessionMsgID: Int = 1
    
    private let originHeader = "https://online-go.com"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        // Explicitly route delegate to main thread to fix State Inspector lag
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
        logTraffic(direction: "SYS", content: "Init Build \(buildVersion)")
        fetchUserConfig()
    }

    // MARK: - Handshake Level 1: REST
    func fetchUserConfig() {
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { return }
        var request = URLRequest(url: url)
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        urlSession?.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let d = data,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            
            DispatchQueue.main.async {
                if let user = json["user"] as? [String: Any] {
                    self.username = user["username"] as? String
                    self.playerID = user["id"] as? Int
                }
                self.userJWT = json["user_jwt"] as? String
                self.isAuthenticated = (self.userJWT != nil)
                
                if self.isAuthenticated { self.connect() }
                self.objectWillChange.send() // Force SwiftUI refresh
            }
        }.resume()
    }

    // MARK: - Handshake Level 2: WebSocket Setup
    func connect() {
        guard webSocketTask == nil || webSocketTask?.state == .completed else { return }
        let urlString = "wss://wsp.online-go.com/socket.io/?EIO=4&transport=websocket"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.logTraffic(direction: "SYS", content: "Socket Stream Opened")
            self.objectWillChange.send()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.isSocketAuthenticated = false
            self.webSocketTask = nil
            self.logTraffic(direction: "SYS", content: "Socket Closed (\(closeCode.rawValue))")
            self.objectWillChange.send()
            // Auto-reconnect to catch game transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.connect() }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            if case .success(let message) = result, case .string(let text) = message {
                // ALL protocol logic forced to main thread to prevent state desync
                DispatchQueue.main.async { self.handleIncomingProtocolMessage(text) }
                self.receiveMessage()
            }
        }
    }

    // MARK: - Handshake Level 3: Engine.IO (The 0 -> 40 sequence)
    private func handleIncomingProtocolMessage(_ text: String) {
        // RAW TRACE: Crucial to see why reconnects might stall
        if !isSocketAuthenticated { self.logTraffic(direction: "RAW", content: "In: \(text.prefix(60))") }

        if text.hasPrefix("0") {
            self.sendRaw("40") // Handshake Connect
            self.logTraffic(direction: "OUT", content: "Handshake: 40")
            return
        }
        
        if text.hasPrefix("40") {
            self.startSocketHeartbeat()
            self.sendSocketAuth()
            // Re-connect to game context if it was interrupted by the socket reset
            if let gid = self.activeGameID { self.connectToGame(gameID: gid) }
            return
        }

        if text == "2" { sendRaw("3"); return } // Keep-alive
        if text.hasPrefix("42") { processEventMessage(String(text.dropFirst(2))) }
    }

    private func processEventMessage(_ json: String) {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 2 else { return }
        
        let event = array[0] as? String ?? ""
        let payload = array[1]
        
        // Sequence Anchor: Mandatory for Move 9 stability
        if let p = payload as? [String: Any], let sv = p["state_version"] as? Int {
            self.currentStateVersion = max(self.currentStateVersion, sv)
        }

        switch event {
        case "net/ping":
            if let p = payload as? [String: Any], let clientVal = p["client"] {
                let serverTime = Int64(Date().timeIntervalSince1970 * 1000)
                sendRaw("42" + jsonString(["net/pong", ["client": clientVal, "server": serverTime]]))
            }
        case "seekgraph/global":
            if let challenges = payload as? [[String: Any]] {
                for item in challenges { updateLobbyItem(item) }
                refreshLobbyUI()
            }
        case "seek_graph/add", "seek_graph/remove":
            processSeekgraphItem(payload as? [String: Any] ?? [:])
            
        case "authenticate", "notification":
            if !self.isSocketAuthenticated {
                self.isSocketAuthenticated = true
                self.subscribeToSeekgraph()
                self.logTraffic(direction: "AUTH", content: "Success")
                self.objectWillChange.send()
            }
            
        case _ where event.contains("gamedata"):
            if let p = payload as? [String: Any] { handleInboundGameData(p) }
            
        case _ where event.contains("move"):
            if let p = payload as? [String: Any] { handleIncomingMove(p) }
            
        case _ where event.contains("clock"):
             self.handleInboundClock(payload as? [String: Any] ?? [:])
        default: break
        }
    }

    // MARK: - Game Transition (The Accept Fix)

    func acceptChallenge(challengeID: Int, completion: @escaping (Int?, Error?) -> Void) {
        guard let url = URL(string: "https://online-go.com/api/v1/challenges/\(challengeID)/accept"),
              let jwt = userJWT else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        request.httpBody = "{}".data(using: .utf8)
        
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://online-go.com")!),
           let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value {
            request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
        }
        
        logTraffic(direction: "OUT", content: "REST: Accepting #\(challengeID)")
        
        urlSession?.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let d = data, let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let newGameID = json["id"] as? Int {
                DispatchQueue.main.async {
                    self.activeGameID = newGameID
                    self.connectToGame(gameID: newGameID) // Link context immediately
                    self.objectWillChange.send() // FORCE TRANSITION
                    completion(newGameID, nil)
                }
            } else {
                DispatchQueue.main.async { completion(nil, error) }
            }
        }.resume()
    }

    // MARK: - Move Sequence Stabilization (Move 9+)
    func sendMove(gameID: Int, x: Int, y: Int, moveNumber: Int) {
        let coord = SGFCoordinates.toSGF(x: x, y: y)
        let blur = Int.random(in: 1200...1900)
        let elapsed = turnStartLocalTime != nil ? Date().timeIntervalSince(turnStartLocalTime!) : 0.0
        let calculatedMainTime = (self.lastServerThinkingTime - elapsed) * 1000.0 - Double(blur)
        
        let moveDict: [String: Any] = [ "game_id": gameID, "move": coord, "blur": blur, "clock": ["main_time": max(0, calculatedMainTime), "timed_out": false] ]
        // Move msgID MUST stay anchored to state_version
        let msgID = self.currentStateVersion + 1
        sendRaw("42" + jsonString(["game/move", moveDict, msgID]))
        self.currentStateVersion += 1
        logTraffic(direction: "OUT", content: "Move #\(msgID): \(coord)")
    }

    // MARK: - Dimension Logic (Replay-to-Live Bridge)
    private func handleInboundGameData(_ p: [String: Any]) {
        let players = p["players"] as? [String: Any]
        DispatchQueue.main.async {
            self.blackPlayerID = (players?["black"] as? [String: Any])?["id"] as? Int ?? p["black_player_id"] as? Int
            self.whitePlayerID = (players?["white"] as? [String: Any])?["id"] as? Int ?? p["white_player_id"] as? Int
            self.blackPlayerName = (players?["black"] as? [String: Any])?["username"] as? String
            self.whitePlayerName = (players?["white"] as? [String: Any])?["username"] as? String
            
            if let pid = self.playerID { self.playerColor = (pid == self.blackPlayerID) ? .black : .white }
            if let gid = p["game_id"] as? Int { self.activeGameID = gid }
            if let sv = p["state_version"] as? Int { self.currentStateVersion = sv }
            
            // Broadcast gamedata to BoardViewModel to resize 19x19 -> 9x9
            NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": p])
            
            self.logTraffic(direction: "SYS", content: "Game Loaded: \(p["width"] ?? 0)x\(p["height"] ?? 0)")
            self.objectWillChange.send()
        }
    }

    private func handleIncomingMove(_ data: [String: Any]) {
        if let sv = data["state_version"] as? Int { self.currentStateVersion = max(self.currentStateVersion, sv) }
        self.turnStartLocalTime = Date()
        NotificationCenter.default.post(name: NSNotification.Name("OGSMoveReceived"), object: nil, userInfo: data)
    }

    private func handleInboundClock(_ data: [String: Any]) {
        DispatchQueue.main.async {
            if let cur = data["current_player"] as? Int { self.currentPlayerID = cur }
            if let b = data["black_time"] as? [String: Any], let bt = b["thinking_time"] as? Double { self.blackTimeRemaining = bt }
            if let w = data["white_time"] as? [String: Any], let wt = w["thinking_time"] as? Double { self.whiteTimeRemaining = wt }
        }
    }

    private func refreshLobbyUI() {
        self.availableGames = lobbyChallenges.values.filter { $0.game != nil }.sorted(by: { $0.id > $1.id })
        self.objectWillChange.send()
    }

    private func updateLobbyItem(_ dict: [String: Any]) {
        guard let id = (dict["challenge_id"] as? Int) ?? (dict["game_id"] as? Int) else { return }
        if dict["delete"] != nil { self.lobbyChallenges.removeValue(forKey: id); return }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let ch = try? JSONDecoder().decode(OGSChallenge.self, from: data) {
            self.lobbyChallenges[id] = ch
        }
    }

    private func processSeekgraphItem(_ dict: [String: Any]) {
        guard let id = (dict["challenge_id"] as? Int) ?? (dict["game_id"] as? Int) else { return }
        if dict["delete"] != nil || (dict.keys.contains("challenge_id") && !dict.keys.contains("game")) {
            self.lobbyChallenges.removeValue(forKey: id)
        } else { updateLobbyItem(dict) }
        refreshLobbyUI()
    }

    private func startSocketHeartbeat() {
        socketPingTimer?.invalidate()
        socketPingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in self?.sendRaw("2") }
    }

    private func startEngineHeartbeat(gameID: Int) {
        enginePulseTimer?.invalidate()
        enginePulseTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            self.sendRaw("42" + self.jsonString(["game/latency", ["game_id": gameID, "latency": self.lastReportedLatency]]))
        }
    }

    private func sendSocketAuth() {
        guard let jwt = userJWT, isConnected else { return }
        sendPacket(event: "authenticate", payload: ["jwt": jwt])
        self.logTraffic(direction: "OUT", content: "Auth Sent")
    }

    private func jsonString(_ obj: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    private func sendRaw(_ text: String) { webSocketTask?.send(.string(text)) { _ in } }
    
    private func logTraffic(direction: String, content: String) {
        DispatchQueue.main.async {
            let entry = NetworkLogEntry(direction: direction, content: content, isHeartbeat: false)
            self.trafficLogs.append(entry); if self.trafficLogs.count > 50 { self.trafficLogs.removeFirst() }
        }
    }

    private func sendPacket(event: String, payload: Any) {
        sendRaw("42" + jsonString([event, payload, self.sessionMsgID]))
        self.sessionMsgID += 1
    }

    // VM Boilerplate logic
    func subscribeToSeekgraph() { sendRaw("42" + jsonString(["seek_graph/connect", ["channel": "global"]])); self.isSubscribedToSeekgraph = true }
    func cancelChallenge(challengeID: Int) { sendPacket(event: "seek_graph/remove", payload: ["challenge_id": challengeID]) }
    func connectToGame(gameID: Int) { self.activeGameID = gameID; self.startEngineHeartbeat(gameID: gameID); sendRaw("42" + jsonString(["game/connect", ["game_id": gameID, "chat": true]])) }
    func resignGame(gameID: Int) { sendRaw("42" + jsonString(["game/resign", ["game_id": gameID]])) }
    func startAutomatch() { sendPacket(event: "automatch/start", payload: ["game_params": ["size": 19, "speed": "live"], "lower_rank": 30, "upper_rank": 9]) }
    func createChallenge(setup: ChallengeSetup, completion: @escaping (Bool, String?) -> Void) { sendRaw("42" + jsonString(["seek_graph/add", setup.toDictionary()])); completion(true, nil) }
    func sendPass(gameID: Int, moveNumber: Int) { sendRaw("42" + jsonString(["game/move", ["game_id": gameID, "move": ".."], self.currentStateVersion + 1])) }
    func sendUndoRequest(gameID: Int, moveNumber: Int) { sendRaw("42" + jsonString(["game/undo_request", ["game_id": gameID, "move_number": moveNumber]])) }
    func sendUndoAccept(gameID: Int) { sendRaw("42" + jsonString(["game/undo_accept", ["game_id": gameID, "move_number": self.undoRequestedMoveNumber ?? 0]])) }
    func sendUndoReject(gameID: Int) { sendRaw("42" + jsonString(["game/undo_reject", ["game_id": gameID]])) }
    func fetchGameState(gameID: Int, completion: @escaping ([String: Any]?) -> Void) { completion(nil) }
}
