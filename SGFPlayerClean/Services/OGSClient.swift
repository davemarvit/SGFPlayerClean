// ========================================================
// FILE: ./Services/OGSClient.swift
// VERSION: v16.185 (Final Integrity Audit / Zero-Dups)
// ========================================================

import Foundation
import Combine

class OGSClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    let buildVersion = "16.185"
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var isSocketAuthenticated = false
    @Published var isAuthenticated = false
    @Published var lastError: String? = nil
    @Published var username: String?
    @Published var playerID: Int?
    @Published var userJWT: String?
    
    @Published var activeGameID: Int?
    @Published var playerColor: Stone?
    @Published var currentPlayerID: Int?
    @Published var blackPlayerID: Int? = -1
    @Published var whitePlayerID: Int? = -1
    @Published var currentHandicap: Int = 0
    
    @Published var availableGames: [OGSChallenge] = []
    @Published var blackBoxContent: String = ""
    @Published var isSubscribedToSeekgraph = false
    @Published var trafficLogs: [NetworkLogEntry] = []
    
    @Published var blackPlayerName: String?
    @Published var whitePlayerName: String?
    @Published var blackTimeRemaining: TimeInterval?
    @Published var whiteTimeRemaining: TimeInterval?
    
    @Published var undoRequestedUsername: String? = nil
    @Published var undoRequestedMoveNumber: Int? = nil

    // MARK: - Private Protocol State
    private var lastClockSnapshot: [String: Any]?
    private var hasEnteredRoom: Bool = false
    private var isSearchingForGame: Bool = false
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var socketPingTimer: Timer?
    private var handshakeTimer: Timer?
    private var enginePulseTimer: Timer?
    private var lobbyChallenges: [Int: OGSChallenge] = [:]
    private var lastReportedLatency: Int = 85
    var currentStateVersion: Int = 0
    
    private let originHeader = "https://online-go.com"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        fetchUserConfig()
        startHandshakeMonitor()
    }

    // MARK: - Robust Parsing
    func robustInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    func writeToBlackBox(_ text: String, direction: String) {
        let entry = "[\(Date().formatted(date: .omitted, time: .standard))] \(direction): \(text)\n"
        DispatchQueue.main.async {
            self.blackBoxContent.insert(contentsOf: entry, at: self.blackBoxContent.startIndex)
            if self.blackBoxContent.count > 25000 { self.blackBoxContent = String(self.blackBoxContent.prefix(25000)) }
        }
    }

    // MARK: - Connection & Handshake
    func fetchUserConfig() {
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { return }
        var request = URLRequest(url: url)
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        urlSession?.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let d = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                DispatchQueue.main.async {
                    if let user = json["user"] as? [String: Any] {
                        self.username = user["username"] as? String
                        self.playerID = self.robustInt(user["id"])
                    }
                    self.userJWT = json["user_jwt"] as? String
                    self.isAuthenticated = (self.userJWT != nil)
                    if self.isAuthenticated { self.connect() }
                    self.objectWillChange.send()
                }
            }
        }.resume()
    }

    func connect() {
        guard webSocketTask == nil || webSocketTask?.state == .completed else { return }
        guard let url = URL(string: "wss://wsp.online-go.com/socket.io/?EIO=4&transport=websocket") else { return }
        var request = URLRequest(url: url)
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
    }

    // MARK: - REST API Calls
    func fetchGameState(gameID: Int, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: "https://online-go.com/api/v1/games/\(gameID)") else { completion(nil); return }
        var request = URLRequest(url: url); request.setValue(originHeader, forHTTPHeaderField: "Origin")
        if let jwt = userJWT { request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization") }
        urlSession?.dataTask(with: request) { data, _, _ in
            if let d = data, let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                DispatchQueue.main.async { completion(json) }
            } else { DispatchQueue.main.async { completion(nil) } }
        }.resume()
    }

    func acceptChallenge(challengeID: Int, completion: @escaping (Int?, Error?) -> Void) {
        self.isSearchingForGame = true
        guard let url = URL(string: "https://online-go.com/api/v1/challenges/\(challengeID)/accept"), let jwt = userJWT else {
            completion(nil, nil); return
        }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://online-go.com")!),
           let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value { request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken") }
        
        urlSession?.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let d = data, let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let gid = self.robustInt(json["id"]) {
                DispatchQueue.main.async { completion(gid, nil) }
            } else { DispatchQueue.main.async { completion(nil, error) } }
        }.resume()
    }

    // MARK: - Native Socket Dispatchers
    func connectToGame(gameID: Int) {
        startEnginePulse(gameID: gameID)
        sendAction("game/connect", payload: ["game_id": gameID, "chat": true])
    }
    
    func sendMove(gameID: Int, x: Int, y: Int) {
        let coord = SGFCoordinates.toSGF(x: x, y: y)
        var payload: [String: Any] = ["game_id": gameID, "move": coord, "blur": Int.random(in: 800...1200)]
        if let clock = lastClockSnapshot { payload["clock"] = clock }
        sendAction("game/move", payload: payload, sequence: currentStateVersion + 1)
    }

    func sendPass(gameID: Int) {
        var payload: [String: Any] = ["game_id": gameID, "move": "..", "blur": 0]
        if let clock = lastClockSnapshot { payload["clock"] = clock }
        sendAction("game/move", payload: payload, sequence: currentStateVersion + 1)
    }

    func resignGame(gameID: Int) {
        sendAction("game/resign", payload: ["game_id": gameID])
    }

    func createChallenge(setup: ChallengeSetup, completion: @escaping (Bool, String?) -> Void) {
        self.isSearchingForGame = true
        sendAction("seek_graph/add", payload: setup.toDictionary())
        completion(true, nil)
    }

    func cancelChallenge(challengeID: Int) {
        sendAction("seek_graph/remove", payload: ["challenge_id": challengeID])
    }

    func startAutomatch() {
        self.isSearchingForGame = true
        let params: [String: Any] = ["game_params": ["size": 19, "speed": "live"], "lower_rank": 30, "upper_rank": 9]
        sendAction("automatch/start", payload: params)
    }

    func sendChat(gameID: Int, text: String) {
        sendAction("game/chat", payload: ["game_id": gameID, "body": text, "type": "main"])
    }

    func sendUndoRequest(gameID: Int, moveNumber: Int) {
        sendAction("game/undo_request", payload: ["game_id": gameID, "move_number": moveNumber])
    }

    func sendUndoAccept(gameID: Int, moveNumber: Int) {
        sendAction("game/undo/accept", payload: ["game_id": gameID, "move_number": moveNumber], sequence: currentStateVersion + 1)
    }

    func sendUndoReject(gameID: Int) {
        sendAction("game/undo/cancel", payload: ["game_id": gameID])
    }

    func subscribeToSeekgraph() {
        sendAction("seek_graph/connect", payload: ["channel": "global"])
        self.isSubscribedToSeekgraph = true
    }

    // MARK: - Inbound Message Processing
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            if case .success(let message) = result, case .string(let text) = message {
                DispatchQueue.main.async { if !self.isConnected { self.isConnected = true } }
                if text != "2" && text != "3" { self.writeToBlackBox(text, direction: "IN") }
                DispatchQueue.main.async { self.handleIncomingProtocolMessage(text) }
                self.receiveMessage()
            }
        }
    }

    private func handleIncomingProtocolMessage(_ text: String) {
        if text.hasPrefix("0") { sendRaw("40"); return }
        if text.hasPrefix("40") { startSocketHeartbeat(); sendSocketAuth(); return }
        if text == "2" { sendRaw("3"); return }
        if text.hasPrefix("42") || text.hasPrefix("43") {
            var cleanJson = String(text.dropFirst(2))
            while let first = cleanJson.first, first.isNumber { cleanJson.removeFirst() }
            processEventMessage(cleanJson)
        }
    }

    private func processEventMessage(_ json: String) {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let eventName = array.first as? String else { return }
        
        let payload = array.count > 1 ? (array[1] as? [String: Any] ?? [:]) : [:]
        
        if let sv = robustInt(payload["state_version"]) { self.currentStateVersion = max(self.currentStateVersion, sv) }

        if !isSocketAuthenticated && (eventName == "authenticated" || eventName == "notification" || eventName.contains("seekgraph")) {
            DispatchQueue.main.async { self.isSocketAuthenticated = true; self.subscribeToSeekgraph() }
        }

        // PILLAR: SURGICAL DISCOVERY & FIREWALL
        if eventName == "active_game" || (eventName == "notification" && payload["type"] as? String == "gameStarted") {
            let phase = payload["phase"] as? String ?? "play"
            if phase == "play" || phase == "stone removal" {
                let bid = robustInt(payload["black_id"]) ?? robustInt((payload["black"] as? [String: Any])?["id"])
                let wid = robustInt(payload["white_id"]) ?? robustInt((payload["white"] as? [String: Any])?["id"])
                if bid == self.playerID || wid == self.playerID {
                    if let gid = robustInt(payload["game_id"]) ?? robustInt(payload["id"]) {
                        if self.isSearchingForGame || self.activeGameID == gid {
                            DispatchQueue.main.async {
                                self.activeGameID = gid
                                self.isSearchingForGame = false
                                self.connectToGame(gameID: gid)
                            }
                        }
                    }
                }
            }
        }

        if let gid = self.activeGameID, eventName.contains("game/") {
            let parts = eventName.components(separatedBy: "/")
            if parts.count >= 2, let packetID = Int(parts[1]) { guard packetID == gid else { return } }
        }

        if eventName.hasSuffix("/gamedata") {
            self.hasEnteredRoom = true
            if let p = payload as? [String: Any] {
                if let clock = p["clock"] as? [String: Any] { self.lastClockSnapshot = clock }
                handleInboundGameData(p)
            }
        } else if eventName.hasSuffix("/clock") {
            if let p = payload as? [String: Any] { self.lastClockSnapshot = p; handleInboundClock(p) }
        } else if eventName.hasSuffix("/move") {
            handleIncomingMove(payload)
        } else if eventName == "seekgraph/global" {
            if let items = array[1] as? [[String: Any]] { for i in items { updateLobbyItem(i) }; refreshLobbyUI() }
        } else if eventName == "net/ping" {
            handleNetPing(payload)
        }
        
        if let phase = payload["phase"] as? String, phase == "finished" { self.stopEnginePulse() }
    }

    // MARK: - Logic Handlers (Atomic)
    private func handleInboundGameData(_ p: [String: Any]) {
        DispatchQueue.main.async {
            let gid = self.robustInt(p["game_id"]) ?? self.robustInt(p["id"])
            guard gid == self.activeGameID else { return }
            let players = p["players"] as? [String: Any]
            self.currentHandicap = self.robustInt(p["handicap"]) ?? 0
            self.blackPlayerID = self.robustInt((players?["black"] as? [String: Any])?["id"]) ?? self.robustInt(p["black_player_id"])
            self.whitePlayerID = self.robustInt((players?["white"] as? [String: Any])?["id"]) ?? self.robustInt(p["white_player_id"])
            self.blackPlayerName = (players?["black"] as? [String: Any])?["username"] as? String ?? self.blackPlayerName
            self.whitePlayerName = (players?["white"] as? [String: Any])?["username"] as? String ?? "White"
            self.identityLockCheck()
            NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": p])
            self.objectWillChange.send()
        }
    }

    private func handleInboundClock(_ data: [String: Any]) {
        DispatchQueue.main.async {
            if let b = data["black_time"] as? [String: Any], let bt = b["thinking_time"] as? Double { self.blackTimeRemaining = bt }
            if let w = data["white_time"] as? [String: Any], let wt = w["thinking_time"] as? Double { self.whiteTimeRemaining = wt }
            if let cur = self.robustInt(data["current_player"]) { self.currentPlayerID = cur }
        }
    }

    private func handleIncomingMove(_ data: [String: Any]) {
        NotificationCenter.default.post(name: NSNotification.Name("OGSMoveReceived"), object: nil, userInfo: data)
    }

    private func handleNetPing(_ p: [String: Any]) {
        let serverTime = Int64(Date().timeIntervalSince1970 * 1000)
        let clientInt = (p["client"] as? NSNumber)?.int64Value ?? serverTime
        sendRaw("42[\"net/pong\",{\"client\":\(clientInt),\"server\":\(serverTime)}]")
    }

    // MARK: - Internal Maintenance Helpers
    private func startHandshakeMonitor() {
        handshakeTimer?.invalidate()
        handshakeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            if !self.isSocketAuthenticated { self.sendSocketAuth() }
            if let gid = self.activeGameID, self.isSocketAuthenticated, !self.hasEnteredRoom {
                self.connectToGame(gameID: gid)
            }
        }
    }

    private func startSocketHeartbeat() {
        socketPingTimer?.invalidate()
        socketPingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            self.sendAction("net/ping", payload: ["client": ts, "drift": 0, "latency": self.lastReportedLatency])
        }
    }

    private func startEnginePulse(gameID: Int) {
        enginePulseTimer?.invalidate()
        enginePulseTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            self.sendAction("game/latency", payload: ["game_id": gameID, "latency": self.lastReportedLatency])
        }
    }
    
    private func stopEnginePulse() { enginePulseTimer?.invalidate(); enginePulseTimer = nil; hasEnteredRoom = false }

    private func sendSocketAuth() {
        guard let jwt = userJWT, let pid = playerID, isConnected else { return }
        sendAction("authenticate", payload: ["jwt": jwt, "player_id": pid, "username": username ?? ""])
    }

    private func identityLockCheck() {
        guard let myID = self.playerID else { return }
        if myID == self.blackPlayerID { self.playerColor = .black }
        else if myID == self.whitePlayerID { self.playerColor = .white }
    }

    private func sendAction(_ event: String, payload: [String: Any], sequence: Int? = nil) {
        let json = tightJson(payload)
        let packet = (sequence != nil) ? "42[\"\(event)\",\(json),\(sequence!)]" : "42[\"\(event)\",\(json)]"
        sendRaw(packet)
    }

    private func sendRaw(_ text: String) {
        writeToBlackBox(text, direction: "OUT ATTEMPT")
        guard let task = webSocketTask, task.state == .running else { return }
        task.send(.string(text)) { _ in }
    }

    private func tightJson(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []), let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func updateLobbyItem(_ dict: [String: Any]) {
        guard let id = robustInt(dict["challenge_id"]) ?? robustInt(dict["game_id"]) else { return }
        if dict["delete"] != nil { self.lobbyChallenges.removeValue(forKey: id); return }
        if let data = try? JSONSerialization.data(withJSONObject: dict), let ch = try? JSONDecoder().decode(OGSChallenge.self, from: data) { self.lobbyChallenges[id] = ch }
    }

    private func refreshLobbyUI() {
        DispatchQueue.main.async { self.availableGames = self.lobbyChallenges.values.filter { $0.game != nil }.sorted(by: { $0.id > $1.id }); self.objectWillChange.send() }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.isConnected = true; self.objectWillChange.send() }
    }
}
