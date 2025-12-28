// MARK: - File: OGSClient.swift (v4.208)
import Foundation
import Combine

class OGSClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var isSocketAuthenticated = false
    @Published var isSubscribedToSeekgraph = false
    @Published var activeGameID: Int?
    @Published var activeGameAuth: String?
    @Published var isAuthenticated = false
    @Published var username: String?
    @Published var playerID: Int?
    @Published var userJWT: String? { didSet { if userJWT != nil && isConnected { sendSocketAuth() } } }
    @Published var playerColor: Stone?
    @Published var currentPlayerID: Int?
    @Published var availableGames: [OGSChallenge] = []
    @Published var trafficLogs: [NetworkLogEntry] = []
    @Published var lastError: String? = nil
    
    @Published var blackPlayerID: Int?; @Published var whitePlayerID: Int?
    @Published var blackPlayerName: String?; @Published var whitePlayerName: String?
    @Published var blackPlayerRank: Double?; @Published var whitePlayerRank: Double?
    @Published var blackTimeRemaining: TimeInterval?; @Published var whiteTimeRemaining: TimeInterval?
    
    @Published var undoRequestedUsername: String? = nil
    @Published var undoRequestedMoveNumber: Int? = nil

    private var pingTimer: Timer?
    internal var webSocketTask: URLSessionWebSocketTask?
    internal var urlSession: URLSession?
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        loadCredentials(); fetchUserConfig()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.connect() }
    }

    func connect() {
        guard let url = URL(string: "wss://wsp.online-go.com/") else { return }
        var request = URLRequest(url: url); request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")
        webSocketTask = urlSession?.webSocketTask(with: request); webSocketTask?.resume(); receiveMessage()
    }
    
    func sendSocketAuth() { if let jwt = self.userJWT, isConnected { sendSocketMessage("[\"authenticate\",{\"jwt\":\"\(jwt)\"}]") } }
    func subscribeToSeekgraph() { if isConnected { sendSocketMessage("[\"seek_graph/connect\",{\"channel\":\"global\"}]"); DispatchQueue.main.async { self.isSubscribedToSeekgraph = true } } }

    // MARK: - Mandatory Interface Logic (The Zombie Play Fix)
    func sendMove(gameID: Int, x: Int, y: Int) {
        let moveString = SGFCoordinates.toSGF(x: x, y: y)
        var payload: [String: Any] = ["game_id": gameID, "move": moveString, "blur": Int.random(in: 100...1000)]
        if let pid = self.playerID { payload["player_id"] = pid }; if let auth = self.activeGameAuth { payload["auth"] = auth }
        if let json = try? JSONSerialization.data(withJSONObject: payload), let s = String(data: json, encoding: .utf8) { sendSocketMessage("[\"game/move\",\(s)]") }
    }

    func sendPass(gameID: Int) {
        var payload: [String: Any] = ["game_id": gameID]
        if let pid = self.playerID { payload["player_id"] = pid }; if let auth = self.activeGameAuth { payload["auth"] = auth }
        if let json = try? JSONSerialization.data(withJSONObject: payload), let s = String(data: json, encoding: .utf8) { sendSocketMessage("[\"game/pass\",\(s)]") }
    }

    func resignGame(gameID: Int) {
        var payload: [String: Any] = ["game_id": gameID]
        if let auth = self.activeGameAuth { payload["auth"] = auth }; if let pid = self.playerID { payload["player_id"] = pid }
        if let json = try? JSONSerialization.data(withJSONObject: payload), let s = String(data: json, encoding: .utf8) { sendSocketMessage("[\"game/resign\",\(s)]") }
    }

    func fetchGameState(gameID: Int, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: "https://online-go.com/api/v1/games/\(gameID)") else { return }
        urlSession?.dataTask(with: url) { data, _, _ in if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { completion(json) } }.resume()
    }

    func connectToGame(gameID: Int) {
        var p: [String: Any] = ["game_id": gameID, "chat": true]
        if let a = self.activeGameAuth { p["auth"] = a }
        if let json = try? JSONSerialization.data(withJSONObject: p), let s = String(data: json, encoding: .utf8) { sendSocketMessage("[\"game/connect\",\(s)]") }
    }

    func createChallenge(setup: ChallengeSetup, completion: @escaping (Bool, String?) -> Void) {
        ensureCSRFToken { token in
            guard let token = token, let url = URL(string: "https://online-go.com/api/v1/challenges") else { return }
            var req = URLRequest(url: url); req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.setValue(token, forHTTPHeaderField: "X-CSRFToken")
            req.httpBody = try? JSONSerialization.data(withJSONObject: setup.toDictionary())
            self.urlSession?.dataTask(with: req) { _, resp, _ in completion((resp as? HTTPURLResponse)?.statusCode == 201, nil) }.resume()
        }
    }

    func acceptChallenge(challengeID: Int, completion: @escaping (Int?, String?) -> Void) {
        guard let url = URL(string: "https://online-go.com/api/v1/challenges/\(challengeID)/accept") else { return }
        ensureCSRFToken { token in
            var req = URLRequest(url: url); req.httpMethod = "POST"
            if let t = token { req.setValue(t, forHTTPHeaderField: "X-CSRFToken") }
            self.urlSession?.dataTask(with: req) { data, _, _ in
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let gId = json["game_id"] as? Int { completion(gId, nil) }
                else { completion(nil, "Error") }
            }.resume()
        }
    }

    func sendUndoRequest(gameID: Int, moveNumber: Int) { sendSocketMessage("[\"game/undo/request\",{\"game_id\":\(gameID),\"move_number\":\(moveNumber)}]") }
    func sendUndoReject(gameID: Int) { sendSocketMessage("[\"game/undo/reject\",{\"game_id\":\(gameID)}]") }
    func sendUndoAccept(gameID: Int) { sendSocketMessage("[\"game/undo/accept\",{\"game_id\":\(gameID)}]") }
    func cancelChallenge(challengeID: Int) { sendSocketMessage("[\"seek_graph/remove\",{\"challenge_id\":\(challengeID)}]") }
    func startAutomatch() {}
    func cancelJoinRetry() {}

    // MARK: - Internal Session Logic
    private func startHighLevelPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            self?.sendSocketMessage("[\"net/ping\",{\"client\":\(timestamp)}]")
        }
    }
    func handleSocketRawMessage(_ text: String) {
        guard let data = text.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [Any], array.count >= 2, let eventName = array[0] as? String else { return }
        let payload = array[1]
        if eventName == "authenticate" { DispatchQueue.main.async { self.isSocketAuthenticated = true; self.startHighLevelPing() } }
        if eventName == "net/pong" { return }
        if eventName == "seekgraph/global" {
            if let list = payload as? [[String: Any]] { for dict in list { processSeekgraphItem(dict) } }
            else if let dict = payload as? [String: Any] { processSeekgraphItem(dict) }
        }
        if eventName.hasSuffix("/gamedata"), let d = payload as? [String: Any] {
            if let a = d["auth"] as? String { DispatchQueue.main.async { self.activeGameAuth = a } }
            NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": d, "moves": d["moves"] ?? []])
        }
    }
    private func processSeekgraphItem(_ dict: [String: Any]) {
        DispatchQueue.main.async {
            if let deleteID = dict["challenge_id"] as? Int, dict["delete"] != nil { self.availableGames.removeAll { $0.id == deleteID } }
            else if let id = dict["challenge_id"] as? Int {
                if let challengeData = try? JSONSerialization.data(withJSONObject: dict), let challenge = try? JSONDecoder().decode(OGSChallenge.self, from: challengeData) {
                    if let idx = self.availableGames.firstIndex(where: { $0.id == id }) { self.availableGames[idx] = challenge }
                    else { self.availableGames.append(challenge) }
                }
            }
        }
    }
    internal func sendSocketMessage(_ text: String) {
        guard let task = webSocketTask else { return }
        let entry = NetworkLogEntry(direction: "⬆️", content: text, isHeartbeat: text == "2" || text == "3" || text.contains("net/ping"))
        DispatchQueue.main.async { self.trafficLogs.insert(entry, at: 0); if self.trafficLogs.count > 100 { self.trafficLogs.removeLast() } }
        task.send(.string(text)) { _ in }
    }
    internal func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            if case .success(let message) = result, case .string(let text) = message {
                if text == "2" { self.sendSocketMessage("3") } else { self.handleSocketRawMessage(text) }
                self.receiveMessage()
            } else { DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { self.connect() } }
        }
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.isConnected = true; self.sendSocketAuth(); self.subscribeToSeekgraph() }
    }
    func fetchUserConfig() {
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { return }
        urlSession?.dataTask(with: url) { data, _, _ in
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let user = json["user"] as? [String: Any] {
                DispatchQueue.main.async { self.username = user["username"] as? String; self.playerID = user["id"] as? Int; self.userJWT = user["jwt"] as? String; self.isAuthenticated = true }
            }
        }.resume()
    }
    func ensureCSRFToken(completion: @escaping (String?) -> Void) {
        urlSession?.dataTask(with: URL(string: "https://online-go.com/api/v1/ui/config")!) { _, _, _ in
            completion(self.urlSession?.configuration.httpCookieStorage?.cookies(for: URL(string: "https://online-go.com")!)?.first(where: { $0.name == "csrftoken" })?.value)
        }.resume()
    }
    func loadCredentials() {
        if let data = KeychainHelper.load(service: "com.davemarvit.SGFPlayerClean.OGS", account: "session_id"), let sid = String(data: data, encoding: .utf8) {
            let cookie = HTTPCookie(properties: [.domain: "online-go.com", .path: "/", .name: "sessionid", .value: sid, .secure: "TRUE", .expires: NSDate(timeIntervalSinceNow: 31556926)])
            urlSession?.configuration.httpCookieStorage?.setCookie(cookie!)
        }
    }
}
