//
//  OGSClient.swift
//  SGFPlayerClean
//
//  Created: 2025-11-30
//  Updated: 2025-12-02 (Added Automatch)
//  Purpose: Handles OGS WebSocket connection (Socket.IO) and REST Authentication/Challenges
//

import Foundation
import Security
import Combine

/// Represents the current phase of an OGS game
enum GamePhase: String {
    case preGame    // No active game, showing game setup UI
    case playing    // Game in progress, accepting moves
    case scoring    // Game finished, in scoring phase
    case finished   // Game complete, showing results
}

/// OGS (Online Go Server) WebSocket client for real-time game communication
class OGSClient: NSObject, ObservableObject {
    
    // MARK: - Public State
    @Published var isConnected = false
    @Published var activeGameID: Int? // Updated when Automatch finds a game
    @Published var lastError: String?
    
    // Player Clocks
    @Published var blackTimeRemaining: TimeInterval?
    @Published var whiteTimeRemaining: TimeInterval?
    @Published var blackPeriodsRemaining: Int?
    @Published var whitePeriodsRemaining: Int?
    @Published var blackPeriodTime: TimeInterval?
    @Published var whitePeriodTime: TimeInterval?
    
    // Player Info
    @Published var currentPlayerColor: Stone = .black
    @Published var playerColor: Stone?
    @Published var isAuthenticated = false
    @Published var username: String?
    @Published var playerID: Int?
    @Published var userRank: Double?

    // Game & UI State
    @Published var gamePhase: GamePhase = .preGame
    @Published var availableGames: [OGSChallenge] = []
    @Published var isSendingChallenge: Bool = false
    
    // MARK: - Internal State
    internal var webSocketTask: URLSessionWebSocketTask?
    internal var urlSession: URLSession?
    internal let keychainService = "com.davemarvit.SGFPlayerClean.OGS"
    internal var isSubscribedToSeekgraph = false
    
    override init() {
        super.init()
        setupSession()
        loadCredentials()
    }
    
    private func setupSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }

    // MARK: - Connection Logic

    func connect() {
        guard let url = URL(string: "wss://online-go.com/socket.io/?EIO=3&transport=websocket") else { return }
        
        if urlSession == nil { setupSession() }
        
        log("OGS: 🔌 Connecting to \(url.absoluteString)")
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveMessage()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        isSubscribedToSeekgraph = false
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleSocketRawMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleSocketRawMessage(text)
                    }
                @unknown default: break
                }
                self.receiveMessage() // Loop
                
            case .failure(let error):
                self.log("OGS: ❌ WebSocket error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func handleSocketRawMessage(_ text: String) {
        // Socket.IO Ping/Pong
        if text == "2" {
            webSocketTask?.send(.string("3")) { _ in }
            return
        }
        
        // Connect Confirmation
        if text.starts(with: "0") {
            log("OGS: ✅ Socket.IO Handshake Success")
            return
        }
        
        // Namespace Connection
        if text.starts(with: "40") {
            log("OGS: ✅ Namespace Connected")
            DispatchQueue.main.async { self.isConnected = true }
            if let user = self.username, let pass = self.getStoredPassword() {
                self.authenticate(username: user, password: pass) { _, _ in }
            }
            return
        }
        
        // Event Message (42["event", data])
        if text.starts(with: "42") {
            let jsonText = String(text.dropFirst(2))
            parseEventMessage(jsonText)
        }
    }

    private func parseEventMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 2,
              let eventName = json[0] as? String else { return }
        
        // Log interesting events (suppress spam)
        if !["active_users", "active_games"].contains(eventName) {
            log("OGS: 📩 Event: \(eventName)")
        }

        switch eventName {
        case "seekgraph/global":
            if let challenges = json[1] as? [[String: Any]] { handleSeekGraph(challenges) }
            
        case "automatch/start":
             if let data = json[1] as? [String: Any],
                let gameId = data["game_id"] as? Int {
                 handleAutomatchFound(gameId: gameId)
             }
            
        case let name where name.contains("/move"):
            if let moveData = json[1] as? [String: Any] { handleMove(moveData) }
            
        case let name where name.contains("/gamedata"):
            if let gameData = json[1] as? [String: Any] { handleGameData(gameData) }
            
        case let name where name.contains("/clock"):
            if let clockData = json[1] as? [String: Any] { handleClock(clockData) }
            
        default:
            break
        }
    }
    
    // MARK: - Helper Logging
    internal func log(_ msg: String) {
        print(msg)
    }
}

// MARK: - Automatch & Seek Graph
extension OGSClient {
    
    func startAutomatch() {
        log("OGS: 🔍 Starting Automatch...")
        
        // 1. Create Payload (Using the struct from OGSModels)
        let payload = AutomatchPayload.standard()
        
        // 2. Encode to JSON
        guard let jsonData = try? JSONEncoder().encode(payload),
              let jsonPayload = try? JSONSerialization.jsonObject(with: jsonData) else {
            log("OGS: ❌ Failed to encode Automatch payload")
            return
        }
        
        // 3. Construct Socket.IO Message: 42["automatch/find_match", {payload}]
        let messageArray: [Any] = ["automatch/find_match", jsonPayload]
        
        guard let finalData = try? JSONSerialization.data(withJSONObject: messageArray),
              let finalString = String(data: finalData, encoding: .utf8) else { return }
        
        let socketMessage = "42" + finalString
        
        // 4. Send
        webSocketTask?.send(.string(socketMessage)) { error in
            if let error = error {
                self.log("OGS: ❌ Automatch Send Error: \(error)")
            } else {
                self.log("OGS: 📤 Automatch Request Sent")
            }
        }
    }
    
    private func handleAutomatchFound(gameId: Int) {
        log("OGS: 🎯 Match Found! Game ID: \(gameId)")
        DispatchQueue.main.async {
            self.activeGameID = gameId
        }
    }

    func subscribeToSeekgraph(force: Bool = false) {
        if isSubscribedToSeekgraph && !force { return }
        let msg = "42[\"seek_graph/connect\",{\"channel\":\"global\"}]"
        webSocketTask?.send(.string(msg)) { _ in }
        isSubscribedToSeekgraph = true
        log("OGS: 📡 Subscribed to SeekGraph")
    }
    
    func unsubscribeFromSeekgraph() {
        let msg = "42[\"seek_graph/disconnect\",{\"channel\":\"global\"}]"
        webSocketTask?.send(.string(msg)) { _ in }
        isSubscribedToSeekgraph = false
    }
    
    private func handleSeekGraph(_ challenges: [[String: Any]]) {
        // (Existing seek graph logic preserved)
        var newChallenges: [OGSChallenge] = []
        
        for item in challenges {
            if let deleteID = item["delete"] as? Bool, deleteID == true,
               let id = item["challenge_id"] as? Int {
                DispatchQueue.main.async { self.availableGames.removeAll { $0.id == id } }
                continue
            }
            
            guard let id = item["challenge_id"] as? Int,
                  let username = item["username"] as? String,
                  let rank = item["rank"] as? Double else { continue }
            
            let width = item["width"] as? Int ?? 19
            let height = item["height"] as? Int ?? 19
            let timeControl = item["time_control"] as? String ?? "Unknown"
            
            let challengerInfo = ChallengerInfo(id: 0, username: username, ranking: rank, professional: false)
            let gameInfo = GameInfo(id: 0, name: nil, width: width, height: height, rules: "japanese", ranked: true, handicap: 0, komi: nil, timeControl: timeControl, timeControlParameters: nil, disableAnalysis: false, pauseOnWeekends: false, black: nil, white: nil, started: item["started"] as? String, blackLost: false, whiteLost: false, annulled: false)
            
            let challenge = OGSChallenge(id: id, challenger: challengerInfo, game: gameInfo, challengerColor: "auto", minRanking: 0, maxRanking: 0, created: nil)
            newChallenges.append(challenge)
        }
        
        if !newChallenges.isEmpty {
            DispatchQueue.main.async {
                if newChallenges.count > 5 { self.availableGames = newChallenges }
                else { self.availableGames.append(contentsOf: newChallenges) }
            }
        }
    }
}

// MARK: - Game Actions
extension OGSClient {
    func joinGame(gameID: Int) {
        log("OGS: 🎮 Joining Game \(gameID)")
        // Include "player_id" if we are logged in, otherwise we are just a spectator
        // Ideally we would inject player_id here, but for now we follow the existing pattern
        let connectMsg = "42[\"game/connect\",{\"game_id\":\(gameID),\"chat\":true}]"
        webSocketTask?.send(.string(connectMsg)) { _ in }
    }
    
    private func handleGameData(_ data: [String: Any]) {
        NotificationCenter.default.post(
            name: NSNotification.Name("OGSGameDataReceived"),
            object: nil,
            userInfo: ["moves": data["moves"] ?? [], "gameData": data]
        )
        if let clock = data["clock"] as? [String: Any] { handleClock(clock) }
    }
    
    private func handleMove(_ data: [String: Any]) {
        guard let moveArr = data["move"] as? [Any], moveArr.count >= 2,
              let x = moveArr[0] as? Int,
              let y = moveArr[1] as? Int else { return }
        
        NotificationCenter.default.post(name: NSNotification.Name("OGSMoveReceived"), object: nil, userInfo: ["x": x, "y": y])
    }
    
    private func handleClock(_ data: [String: Any]) {
        if let whiteTime = data["white_time"] as? Double { DispatchQueue.main.async { self.whiteTimeRemaining = whiteTime } }
        if let blackTime = data["black_time"] as? Double { DispatchQueue.main.async { self.blackTimeRemaining = blackTime } }
    }
}

// MARK: - Authentication & REST
extension OGSClient {
    
    func authenticate(username: String? = nil, password: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        let user = username ?? self.username
        let pass = password ?? getStoredPassword()
        
        guard let user = user, let pass = pass else {
            completion(false, "No credentials")
            return
        }
        
        guard let loginURL = URL(string: "https://online-go.com/api/v0/login") else { return }
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["username": user, "password": pass]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                DispatchQueue.main.async { completion(false, "Login failed") }
                return
            }
            
            self.fetchUserConfig()
            
            DispatchQueue.main.async {
                self.isAuthenticated = true
                self.username = user
                self.saveCredentials(username: user, password: pass)
                completion(true, nil)
            }
        }.resume()
    }
    
    private func fetchUserConfig() {
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let user = json["user"] as? [String: Any] else { return }
            
            if let id = user["id"] as? Int {
                DispatchQueue.main.async { self.playerID = id }
            }
            if let rank = user["ranking"] as? Double {
                DispatchQueue.main.async { self.userRank = rank }
            }
        }.resume()
    }

    /// Post a custom game/challenge to OGS
    func postCustomGame(settings: GameSettings, completion: @escaping (Bool, String?) -> Void) {
        // (Existing postCustomGame logic preserved exactly as was)
        log("OGS: 🎮 Posting custom game...")
        guard isAuthenticated else { completion(false, "Not authenticated"); return }
        guard let url = URL(string: "https://online-go.com/api/v1/challenges") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://online-go.com", forHTTPHeaderField: "Referer")
        request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")

        if let csrfCookie = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "csrftoken" }) {
            request.setValue(csrfCookie.value, forHTTPHeaderField: "X-CSRFToken")
        }

        var timeControlParams: [String: Any] = [
            "main_time": settings.mainTimeMinutes * 60,
            "time_control": settings.timeControlSystem.apiValue,
            "system": settings.timeControlSystem.apiValue,
            "pause_on_weekends": false
        ]
        
        let totalSeconds = settings.mainTimeMinutes * 60
        let speed = totalSeconds < 600 ? "blitz" : (totalSeconds < 1200 ? "rapid" : "live")
        timeControlParams["speed"] = speed

        switch settings.timeControlSystem {
        case .fischer:
            timeControlParams["time_increment"] = settings.fischerIncrementSeconds
            timeControlParams["max_time"] = settings.fischerMaxTimeMinutes * 60
        case .byoyomi, .canadian, .simple:
            timeControlParams["period_time"] = settings.periodTimeSeconds
            timeControlParams["periods"] = settings.periods
        default: break
        }

        let body: [String: Any] = [
            "initialized": false,
            "min_ranking": 0,
            "max_ranking": 36,
            "challenger_color": settings.colorPreference.apiValue,
            "game": [
                "name": settings.gameName,
                "rules": settings.rules.apiValue,
                "ranked": settings.ranked,
                "width": settings.boardSize,
                "height": settings.boardSize,
                "handicap": settings.handicap.apiValue,
                "komi_auto": "automatic",
                "disable_analysis": settings.disableAnalysis,
                "time_control": settings.timeControlSystem.apiValue,
                "time_control_parameters": timeControlParams
            ] as [String: Any]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResp = response as? HTTPURLResponse, (200...201).contains(httpResp.statusCode) {
                self.log("OGS: ✅ Challenge Posted Successfully")
                completion(true, nil)
            } else {
                self.log("OGS: ❌ Challenge Post Failed")
                completion(false, "Server Error")
            }
        }.resume()
    }
}

// MARK: - Keychain
extension OGSClient {
    func saveCredentials(username: String, password: String) {
        let data = password.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: username,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    internal func loadCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let existing = item as? [String: Any],
           let user = existing[kSecAttrAccount as String] as? String {
            self.username = user
        }
    }
    
    func deleteCredentials() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService]
        SecItemDelete(query as CFDictionary)
        self.username = nil
        self.isAuthenticated = false
    }
    
    internal func getStoredPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}

// MARK: - Delegate
extension OGSClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        log("OGS: 🟢 WebSocket Connected")
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        log("OGS: 🔴 WebSocket Closed")
        DispatchQueue.main.async { self.isConnected = false }
    }
}
