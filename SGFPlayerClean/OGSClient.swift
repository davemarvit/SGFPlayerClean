//
//  OGSClient.swift
//  SGFPlayerClean
//
//  Part 1: Core & Auth (v3.73)
//  - v3.73: Auto-Rejoin Logic & Explicit Keep-Alive.
//  - Automatically rejoins the active game room upon socket reconnection.
//  - Implements Engine.IO "2" -> "3" Ping/Pong heartbeat.
//

import Foundation
import Combine
import Security

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
    
    // MARK: - Internal Properties
    internal var webSocketTask: URLSessionWebSocketTask?
    internal var urlSession: URLSession?
    internal var pingTimer: Timer?
    internal var clockTimer: Timer?
    internal var challengePollTimer: Timer?
    internal var joinRetryTimer: Timer?
    internal var isSubscribedToSeekgraph = false
    
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
        
        print("OGS: 🔌 Connecting to WSP (v4)...")
        var request = URLRequest(url: url)
        request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")
        
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://online-go.com")!) {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        }
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        lastMessageReceived = Date()
        
        // WATCHDOG & KEEP-ALIVE
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let silence = Date().timeIntervalSince(self.lastMessageReceived)
            if silence > 35.0 {
                print("OGS: ⚠️ Watchdog Timeout (Silence: \(Int(silence))s). Reconnecting...")
                self.connect()
                return
            }
            
            // Proactive Ping (Engine.IO '3')
            self.webSocketTask?.send(.string("3")) { error in
                if error != nil {
                    print("OGS: ❌ Send Ping Failed. Reconnecting...")
                    self.connect()
                }
            }
        }
        receiveMessage()
    }
    
    func disconnect(isReconnecting: Bool = false) {
        pingTimer?.invalidate()
        clockTimer?.invalidate()
        challengePollTimer?.invalidate()
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
                self.availableGames.removeAll()
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
                    // SERVER PING ("2") -> CLIENT PONG ("3")
                    if text == "2" {
                        self.webSocketTask?.send(.string("3")) { _ in }
                        self.receiveMessage()
                        return
                    }
                    self.handleSocketRawMessage(text)
                }
                self.receiveMessage()
            case .failure(let error):
                print("OGS: ❌ Socket Error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.isConnected = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { if !self.isConnected { self.connect() } }
            }
        }
    }
    
    // MARK: - Delegates
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("OGS: 🟢 WebSocket Connected")
        
        // 1. Send Handshake
        self.webSocketTask?.send(.string("40")) { _ in }
        
        // 2. Try Auth
        if self.userJWT != nil {
            sendSocketAuth()
        } else {
            print("OGS: ⚠️ No JWT yet. Socket waiting for Config Fetch...")
        }
        
        DispatchQueue.main.async { self.isConnected = true }
        
        // 3. AUTO-REJOIN LOGIC (CRITICAL FIX for Ghost Stones/Timeouts)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.isSubscribedToSeekgraph { self.subscribeToSeekgraph(force: true) }
            
            if let gameID = self.activeGameID {
                print("OGS: 🔄 Restoration - Automatically re-joining Game \(gameID)")
                self.joinGame(gameID: gameID)
            }
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("OGS: 🔴 WebSocket Closed")
        DispatchQueue.main.async { self.isConnected = false; self.isSocketAuthenticated = false }
    }
    
    // MARK: - Auth Logic
    func loadCredentials() {
        if let data = KeychainHelper.load(service: keychainService, account: "session_id"),
           let sessionID = String(data: data, encoding: .utf8) {
            print("OGS: 🔑 Loaded Session ID from Keychain")
            applySessionCookie(sessionID)
            return
        }
        
        if let url = URL(string: "https://online-go.com"),
           let cookies = HTTPCookieStorage.shared.cookies(for: url),
           cookies.contains(where: { $0.name == "sessionid" }) {
            print("OGS: 🍪 Found existing Session Cookie.")
            self.isAuthenticated = true
            fetchUserConfig()
            return
        }
        print("OGS: ⚠️ No Credentials found. Guest Mode.")
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
                // Parse JWT
                var foundJWT: String?
                if let user = json["user"] as? [String: Any], let jwt = user["jwt"] as? String {
                    foundJWT = jwt
                } else if let jwt = json["user_jwt"] as? String {
                    foundJWT = jwt
                }
                
                if let jwt = foundJWT {
                    DispatchQueue.main.async {
                        self.userJWT = jwt
                        print("OGS: 🎟️ JWT Acquired")
                        if self.isConnected { self.sendSocketAuth() }
                    }
                }
                
                // Parse Profile
                DispatchQueue.main.async {
                    if let user = json["user"] as? [String: Any] {
                        self.username = user["username"] as? String
                        self.playerID = user["id"] as? Int
                        if let r = user["ranking"] as? Int { self.userRank = Double(r) }
                    }
                    print("OGS: 👤 User Profile Loaded: \(self.username ?? "Unknown")")
                }
            }
        }.resume()
    }
    
    // Helper to send Auth Packet
    func sendSocketAuth() {
        guard let jwt = self.userJWT else { return }
        print("OGS: 🔐 Sending Authenticate Packet...")
        let authMsg = "42[\"authenticate\",{\"jwt\":\"\(jwt)\"}]"
        self.webSocketTask?.send(.string(authMsg)) { _ in }
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
    
    // MARK: - Game Actions (Public API)
    
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
        webSocketTask?.send(.string("42[\"game/connect\",\(json)]")) { _ in }
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
        webSocketTask?.send(.string("42[\"game/move\",\(json)]")) { _ in }
    }
    
    func sendPass(gameID: Int) {
        let json = "{\"game_id\":\(gameID),\"move\":\"..\",\"auth\":\"\(activeGameAuth ?? "")\"}"
        webSocketTask?.send(.string("42[\"game/move\",\(json)]")) { _ in }
    }
    
    func sendUndoRequest(gameID: Int, moveNumber: Int) {
        print("OGS: ↩️ Sending Undo Request for Game \(gameID), Move \(moveNumber)")
        let json = "{\"game_id\":\(gameID),\"move_number\":\(moveNumber),\"player_id\":\(playerID ?? 0),\"auth\":\"\(activeGameAuth ?? "")\"}"
        webSocketTask?.send(.string("42[\"game/undo/request\",\(json)]")) { _ in }
    }
    
    func sendUndoAccept(gameID: Int) {
        guard let moveNum = undoRequestedMoveNumber else {
            print("OGS: ⚠️ Cannot accept undo: Move number unknown.")
            return
        }
        print("OGS: ✅ Accepting Undo Request for Move \(moveNum)")
        let json = "{\"game_id\":\(gameID),\"move_number\":\(moveNum),\"auth\":\"\(activeGameAuth ?? "")\"}"
        webSocketTask?.send(.string("42[\"game/undo/accept\",\(json)]")) { _ in }
        DispatchQueue.main.async { self.undoRequestedUsername = nil }
    }
    
    func sendUndoReject(gameID: Int) {
        print("OGS: ❌ Rejecting Undo Request")
        DispatchQueue.main.async { self.undoRequestedUsername = nil }
    }
    
    func resignGame(gameID: Int) {
        let json = "{\"game_id\":\(gameID),\"player_id\":\(playerID ?? 0),\"auth\":\"\(activeGameAuth ?? "")\"}"
        webSocketTask?.send(.string("42[\"game/resign\",\(json)]")) { _ in
            DispatchQueue.main.async { self.isGameFinished = true; self.clockTimer?.invalidate() }
        }
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
    
    // MARK: - SeekGraph
    
    func subscribeToSeekgraph(force: Bool = false) {
        if webSocketTask != nil && (!isSubscribedToSeekgraph || force) {
            webSocketTask?.send(.string("42[\"seek_graph/connect\",{\"channel\":\"global\"}]")) { _ in }
            isSubscribedToSeekgraph = true
            print("OGS: 📡 Subscribed to SeekGraph")
        }
        startChallengePolling()
    }
    
    func unsubscribeFromSeekgraph() {
        webSocketTask?.send(.string("42[\"seek_graph/disconnect\",{\"channel\":\"global\"}]")) { _ in }
        isSubscribedToSeekgraph = false
        challengePollTimer?.invalidate()
    }
    
    internal func startChallengePolling() {
        challengePollTimer?.invalidate()
        guard let url = URL(string: "https://online-go.com/api/v1/challenges") else { return }
        let task = urlSession?.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return }
            self.handleSeekGraph(results)
        }
        task?.resume()
        challengePollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.startChallengePolling()
        }
    }
    
    func startAutomatch() { /* stub */ }
    func postCustomGame(settings: GameSettings, completion: @escaping (Bool, String?) -> Void) { /* stub */ }
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
