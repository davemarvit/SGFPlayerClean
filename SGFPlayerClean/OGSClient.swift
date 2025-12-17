//
//  OGSClient.swift
//  SGFPlayerClean
//
//  v3.100: UI Stability.
//  - Disconnect logic no longer clears the challenge list (prevents flickering).
//  - Ensures socket connection sends "seek_graph/connect" consistently.
//

import Foundation
import Combine
import Security

// MARK: - Debug Structs
struct NetworkLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let direction: String // "⬆️" (Sent) or "⬇️" (Received)
    let content: String
    let isHeartbeat: Bool
}

class OGSClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    
    // MARK: - State Properties
    @Published var isConnected = false
    @Published var isSocketAuthenticated = false
    @Published var activeGameID: Int?
    @Published var activeGameAuth: String?
    @Published var lastError: String?
    @Published var isGameFinished = false
    
    @Published var isAuthenticated = false
    @Published var username: String?
    @Published var playerID: Int?
    @Published var userRank: Double?
    @Published var userJWT: String?
    
    @Published var playerColor: Stone?
    @Published var currentPlayerID: Int?
    
    // Game Metadata
    @Published var komi: Double?
    
    // Player Metadata
    @Published var blackPlayerID: Int?
    @Published var whitePlayerID: Int?
    @Published var blackPlayerName: String?
    @Published var whitePlayerName: String?
    @Published var blackPlayerRank: Double?
    @Published var whitePlayerRank: Double?
    
    // Clock & Time
    @Published var blackTimeRemaining: TimeInterval?
    @Published var whiteTimeRemaining: TimeInterval?
    @Published var blackPeriodsRemaining: Int?
    @Published var whitePeriodsRemaining: Int?
    @Published var blackPeriodTime: TimeInterval?
    @Published var whitePeriodTime: TimeInterval?

    // Undo State
    @Published var undoRequestedUsername: String? = nil
    @Published var undoRequestedMoveNumber: Int? = nil

    @Published var availableGames: [OGSChallenge] = []
    
    // MARK: - Debugging State
    @Published var trafficLogs: [NetworkLogEntry] = []
    
    // MARK: - Internal Properties
    internal var webSocketTask: URLSessionWebSocketTask?
    internal var urlSession: URLSession?
    internal var pingTimer: Timer?
    internal var clockTimer: Timer?
    internal var joinRetryTimer: Timer?
    
    // Queue Flags
    internal var isSubscribedToSeekgraph = false
    private var wantsSeekGraph = false
    
    // Watchdog
    private var lastMessageReceived: Date = Date()
    
    internal let keychainService = "com.davemarvit.SGFPlayerClean.OGS"
    
    // MARK: - Initialization
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        loadCredentials()
    }

    // MARK: - Connection Logic
    func connect() {
        disconnect(isReconnecting: true)
        
        guard let url = URL(string: "wss://wsp.online-go.com/socket.io/?EIO=4&transport=websocket") else { return }
        
        logTraffic("🔌 Connecting to WSP (v4)...", direction: "⚡️")
        var request = URLRequest(url: url)
        request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")
        
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://online-go.com")!) {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        }
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        lastMessageReceived = Date()
        receiveMessage()
    }
    
    func disconnect(isReconnecting: Bool = false) {
        pingTimer?.invalidate()
        clockTimer?.invalidate()
        joinRetryTimer?.invalidate()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        if !isReconnecting {
            DispatchQueue.main.async {
                self.isConnected = false
                self.isSocketAuthenticated = false
                self.isSubscribedToSeekgraph = false
                self.activeGameID = nil
                self.activeGameAuth = nil
                // v3.100: Do NOT clear availableGames here to prevent UI flicker
            }
        } else {
            DispatchQueue.main.async { self.isConnected = false }
        }
    }

    // MARK: - Socket I/O
    
    internal func sendSocketMessage(_ text: String) {
        guard isConnected, webSocketTask != nil else { return }
        
        logTraffic(text, direction: "⬆️")
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                print("OGS: ❌ Send Error: \(error)")
                self?.logTraffic("❌ Send Error: \(error.localizedDescription)", direction: "⚠️")
            }
        }
    }
    
    internal func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            self.lastMessageReceived = Date()
            
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.logTraffic(text, direction: "⬇️")
                    if text == "2" {
                        self.webSocketTask?.send(.string("3")) { _ in }
                        self.receiveMessage()
                        return
                    }
                    self.handleSocketRawMessage(text)
                }
                self.receiveMessage()
            case .failure(let error):
                self.logTraffic("❌ Socket Error: \(error.localizedDescription)", direction: "⚠️")
                print("OGS: ❌ Socket Error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.isConnected = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { if !self.isConnected { self.connect() } }
            }
        }
    }
    
    // MARK: - Delegates
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logTraffic("🟢 WebSocket Connected", direction: "⚡️")
        
        DispatchQueue.main.async {
            self.isConnected = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.isConnected { self.sendSocketMessage("40") }
            }
            
            self.pingTimer?.invalidate()
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let silence = Date().timeIntervalSince(self.lastMessageReceived)
                if silence > 45.0 {
                    self.logTraffic("⚠️ Watchdog Timeout. Reconnecting...", direction: "⚡️")
                    self.connect()
                    return
                }
                self.sendSocketMessage("3")
            }
            
            if self.userJWT != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if self.isConnected { self.sendSocketAuth() }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.wantsSeekGraph || self.isSubscribedToSeekgraph {
                    self.logTraffic("🔄 Restoration - Subscribing to SeekGraph", direction: "📡")
                    self.subscribeToSeekgraph(force: true)
                    self.wantsSeekGraph = false
                }
                
                if let gameID = self.activeGameID {
                    self.logTraffic("🔄 Restoration - Re-joining Game \(gameID)", direction: "🎮")
                    self.joinGame(gameID: gameID)
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logTraffic("🔴 WebSocket Closed", direction: "⚡️")
        pingTimer?.invalidate()
        DispatchQueue.main.async { self.isConnected = false; self.isSocketAuthenticated = false }
    }
    
    // MARK: - Logging Helper
    internal func logTraffic(_ content: String, direction: String) {
        let isHeartbeat = (content == "2" || content == "3")
        let entry = NetworkLogEntry(direction: direction, content: content, isHeartbeat: isHeartbeat)
        
        DispatchQueue.main.async {
            if self.trafficLogs.count > 100 { self.trafficLogs.removeLast() }
            self.trafficLogs.insert(entry, at: 0)
        }
    }
    
    // MARK: - Auth Logic
    func loadCredentials() {
        if let data = KeychainHelper.load(service: keychainService, account: "session_id"),
           let sessionID = String(data: data, encoding: .utf8) {
            applySessionCookie(sessionID)
            return
        }
        if let url = URL(string: "https://online-go.com"),
           let cookies = HTTPCookieStorage.shared.cookies(for: url),
           cookies.contains(where: { $0.name == "sessionid" }) {
            self.isAuthenticated = true
            fetchUserConfig()
            return
        }
    }
    
    private func applySessionCookie(_ sessionID: String) {
        self.isAuthenticated = true
        let cookie = HTTPCookie(properties: [.domain: "online-go.com", .path: "/", .name: "sessionid", .value: sessionID, .secure: "TRUE", .expires: NSDate(timeIntervalSinceNow: 31556926)])
        if let cookie = cookie { urlSession?.configuration.httpCookieStorage?.setCookie(cookie) }
        fetchUserConfig()
    }
    
    func authenticate(username: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://online-go.com/api/v1/ui/login") else { return }
        let body = ["username": username, "password": password]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        urlSession?.dataTask(with: request) { data, response, error in
            if let _ = error { DispatchQueue.main.async { completion(false, "Network Error") }; return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                DispatchQueue.main.async { completion(false, "Login Failed") }; return
            }
            if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                for cookie in cookies where cookie.name == "sessionid" {
                    let _ = KeychainHelper.save(service: self.keychainService, account: "session_id", data: cookie.value.data(using: .utf8)!)
                    DispatchQueue.main.async {
                        self.isAuthenticated = true
                        self.fetchUserConfig()
                        completion(true, nil)
                    }
                    return
                }
            }
            DispatchQueue.main.async { completion(true, nil) }
        }.resume()
    }
    
    func fetchUserConfig() {
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { return }
        urlSession?.dataTask(with: url) { data, _, _ in
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var foundJWT: String?
                if let user = json["user"] as? [String: Any], let jwt = user["jwt"] as? String {
                    foundJWT = jwt
                } else if let jwt = json["user_jwt"] as? String {
                    foundJWT = jwt
                }
                
                if let jwt = foundJWT {
                    DispatchQueue.main.async {
                        self.userJWT = jwt
                        if self.isConnected { self.sendSocketAuth() }
                    }
                }
                DispatchQueue.main.async {
                    if let user = json["user"] as? [String: Any] {
                        self.username = user["username"] as? String
                        self.playerID = user["id"] as? Int
                        if let r = user["ranking"] as? Int { self.userRank = Double(r) }
                    }
                }
            }
        }.resume()
    }
    
    func sendSocketAuth() {
        guard let jwt = self.userJWT else { return }
        let authMsg = "42[\"authenticate\",{\"jwt\":\"\(jwt)\"}]"
        sendSocketMessage(authMsg)
    }
    
    func deleteCredentials() {
        let _ = KeychainHelper.delete(service: keychainService, account: "session_id")
        DispatchQueue.main.async { self.isAuthenticated = false; self.username = nil; self.playerID = nil; self.disconnect() }
    }
    
    internal func ensureCSRFToken(completion: @escaping (String?) -> Void) {
        if let url = URL(string: "https://online-go.com"), let cookies = urlSession?.configuration.httpCookieStorage?.cookies(for: url), let csrf = cookies.first(where: { $0.name == "csrftoken" }) {
            completion(csrf.value); return
        }
        refreshCSRFToken { success in
            if success, let url = URL(string: "https://online-go.com"), let cookies = self.urlSession?.configuration.httpCookieStorage?.cookies(for: url), let csrf = cookies.first(where: { $0.name == "csrftoken" }) {
                completion(csrf.value)
            } else { completion(nil) }
        }
    }
    
    internal func refreshCSRFToken(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { completion(false); return }
        urlSession?.dataTask(with: url) { _, resp, _ in completion((resp as? HTTPURLResponse)?.statusCode == 200) }.resume()
    }
    
    // MARK: - Game Actions
    
    func joinGame(gameID: Int) {
        print("OGS: 🎮 Joining Game \(gameID) (Starting Retry Loop)")
        sendJoinPayload(gameID: gameID)
        joinRetryTimer?.invalidate()
        joinRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            print("OGS: 🔁 Retrying Join Game \(gameID)...")
            self?.sendJoinPayload(gameID: gameID)
        }
    }
    
    private func sendJoinPayload(gameID: Int) {
        var json = "{\"game_id\":\(gameID),\"chat\":true"
        if let pid = self.playerID { json += ",\"player_id\":\(pid)" }
        json += "}"
        sendSocketMessage("42[\"game/connect\",\(json)]")
    }
    
    func cancelJoinRetry() {
        if joinRetryTimer != nil {
            print("OGS: ✅ Join Successful. Stopping Retry Loop.")
            joinRetryTimer?.invalidate()
            joinRetryTimer = nil
        }
    }
    
    func sendMove(gameID: Int, x: Int, y: Int) {
        let str = SGFCoordinates.toSGF(x: x, y: y)
        let json = "{\"game_id\":\(gameID),\"move\":\"\(str)\",\"auth\":\"\(activeGameAuth ?? "")\"}"
        sendSocketMessage("42[\"game/move\",\(json)]")
    }
    
    func sendPass(gameID: Int) {
        let json = "{\"game_id\":\(gameID),\"move\":\"..\",\"auth\":\"\(activeGameAuth ?? "")\"}"
        sendSocketMessage("42[\"game/move\",\(json)]")
    }
    
    func sendUndoRequest(gameID: Int, moveNumber: Int) {
        print("OGS: ↩️ Sending Undo Request for Game \(gameID), Move \(moveNumber)")
        let json = "{\"game_id\":\(gameID),\"move_number\":\(moveNumber),\"player_id\":\(playerID ?? 0),\"auth\":\"\(activeGameAuth ?? "")\"}"
        sendSocketMessage("42[\"game/undo/request\",\(json)]")
    }
    
    func sendUndoAccept(gameID: Int) {
        guard let moveNum = undoRequestedMoveNumber else { return }
        print("OGS: ✅ Accepting Undo Request for Move \(moveNum)")
        let json = "{\"game_id\":\(gameID),\"move_number\":\(moveNum),\"auth\":\"\(activeGameAuth ?? "")\"}"
        sendSocketMessage("42[\"game/undo/accept\",\(json)]")
        DispatchQueue.main.async { self.undoRequestedUsername = nil }
    }
    
    func sendUndoReject(gameID: Int) {
        print("OGS: ❌ Rejecting Undo Request")
        DispatchQueue.main.async { self.undoRequestedUsername = nil }
    }
    
    func resignGame(gameID: Int) {
        let json = "{\"game_id\":\(gameID),\"player_id\":\(playerID ?? 0),\"auth\":\"\(activeGameAuth ?? "")\"}"
        sendSocketMessage("42[\"game/resign\",\(json)]")
        DispatchQueue.main.async { self.isGameFinished = true; self.clockTimer?.invalidate() }
    }
    
    func acceptChallenge(challengeID: Int, completion: @escaping (Int?, String?) -> Void) {
        performAccept(challengeID: challengeID, retryCount: 1, completion: completion)
    }
    
    private func performAccept(challengeID: Int, retryCount: Int, completion: @escaping (Int?, String?) -> Void) {
        ensureCSRFToken { token in
            guard let token = token else { completion(nil, "Auth Error"); return }
            guard let url = URL(string: "https://online-go.com/api/v1/challenges/\(challengeID)/accept") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-CSRFToken")
            request.setValue("https://online-go.com", forHTTPHeaderField: "Referer")
            request.httpBody = "{}".data(using: .utf8)
            
            self.urlSession?.dataTask(with: request) { data, resp, err in
                if let _ = err { completion(nil, "Network Error"); return }
                guard let http = resp as? HTTPURLResponse else { completion(nil, "Invalid Resp"); return }
                
                if http.statusCode == 403 && retryCount > 0 {
                    self.refreshCSRFToken { success in
                        if success { self.performAccept(challengeID: challengeID, retryCount: retryCount - 1, completion: completion) }
                        else { completion(nil, "Session Expired") }
                    }
                    return
                }
                
                func getInt(_ v: Any?) -> Int? {
                    if let i = v as? Int { return i }
                    if let s = v as? String { return Int(s) }
                    return nil
                }
                
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let id = getInt(json["id"]) { completion(id, nil); return }
                    if let id = getInt(json["game_id"]) { completion(id, nil); return }
                    if let game = json["game"] as? [String: Any], let id = getInt(game["id"]) { completion(id, nil); return }
                }
                completion(nil, "Failed to join")
            }.resume()
        }
    }
    
    // MARK: - API Calls
    
    func startAutomatch() { }
    
    func postCustomGame(settings: GameSettings, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://online-go.com/api/v1/challenges") else { completion(false, "URL"); return }
        
        ensureCSRFToken { token in
            guard let token = token else { completion(false, "Auth Error"); return }
            
            let rules = "japanese"
            let time = "byoyomi"
            
            let json: [String: Any] = [
                "game": [
                    "name": "Challenge",
                    "rules": rules,
                    "ranked": settings.ranked,
                    "handicap": settings.handicap,
                    "time_control": time,
                    "time_control_parameters": [
                        "time_control": time,
                        "main_time": 600,
                        "period_time": 30,
                        "periods": 5
                    ],
                    "width": settings.boardSize,
                    "height": settings.boardSize,
                    "disable_analysis": false
                ],
                "challenger_color": "automatic",
                "min_ranking": -30,
                "max_ranking": 30
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-CSRFToken")
            request.setValue("https://online-go.com", forHTTPHeaderField: "Referer")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json)
            
            self.urlSession?.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 201 {
                    completion(true, nil)
                } else {
                    completion(false, "Failed (Status: \((response as? HTTPURLResponse)?.statusCode ?? 0))")
                }
            }.resume()
        }
    }
    
    // MARK: - SeekGraph (Socket Based)
    
    func subscribeToSeekgraph(force: Bool = false) {
        guard isConnected else {
            print("OGS: ⏳ Queuing SeekGraph subscription (Socket not ready)")
            self.wantsSeekGraph = true
            return
        }
        
        if webSocketTask != nil && (!isSubscribedToSeekgraph || force) {
            print("OGS: 📡 Subscribing to Global SeekGraph via Socket...")
            sendSocketMessage("42[\"seek_graph/connect\",{\"channel\":\"global\"}]")
            isSubscribedToSeekgraph = true
        }
    }
    
    func unsubscribeFromSeekgraph() {
        sendSocketMessage("42[\"seek_graph/disconnect\",{\"channel\":\"global\"}]")
        isSubscribedToSeekgraph = false
    }
}

// MARK: - Keychain Helper
struct KeychainHelper {
    static func save(service: String, account: String, data: Data) -> OSStatus {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecValueData: data] as [String: Any]
        SecItemDelete(query as CFDictionary); return SecItemAdd(query as CFDictionary, nil)
    }
    static func load(service: String, account: String) -> Data? {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: kCFBooleanTrue!, kSecMatchLimit: kSecMatchLimitOne] as [String: Any]
        var item: AnyObject?; let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == noErr ? (item as? Data) : nil
    }
    static func delete(service: String, account: String) -> OSStatus {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as [String: Any]
        return SecItemDelete(query as CFDictionary)
    }
}
