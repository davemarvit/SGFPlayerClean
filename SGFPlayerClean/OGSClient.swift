//
//  OGSClient.swift
//  SGFPlayerClean
//
//  Created: 2025-11-30
//  Updated: 2025-12-04 (Precise Time Formatting)
//

import Foundation
import Security
import Combine

class OGSClient: NSObject, ObservableObject {
    
    @Published var isConnected = false
    @Published var activeGameID: Int?
    @Published var lastError: String?
    
    @Published var isAuthenticated = false
    @Published var username: String?
    @Published var playerID: Int?
    @Published var userRank: Double?
    
    @Published var playerColor: Stone?
    @Published var blackTimeRemaining: TimeInterval?
    @Published var whiteTimeRemaining: TimeInterval?
    @Published var blackPeriodsRemaining: Int?
    @Published var whitePeriodsRemaining: Int?
    @Published var blackPeriodTime: TimeInterval?
    @Published var whitePeriodTime: TimeInterval?

    @Published var availableGames: [OGSChallenge] = []
    
    internal var webSocketTask: URLSessionWebSocketTask?
    internal var urlSession: URLSession?
    internal var pingTimer: Timer?
    
    internal let keychainService = "com.davemarvit.SGFPlayerClean.OGS"
    internal var isSubscribedToSeekgraph = false
    
    override init() {
        super.init()
        setupSession()
        loadCredentials()
    }
    
    private func setupSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }

    // MARK: - Connection Logic
    func connect() {
        disconnect(isReconnecting: true)
        
        guard let url = URL(string: "wss://online-go.com/socket.io/?EIO=3&transport=websocket") else { return }
        
        if urlSession == nil { setupSession() }
        
        print("OGS: 🔌 Connecting...")
        
        var request = URLRequest(url: url)
        request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // HEARTBEAT: Ping "2" every 2 seconds
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.webSocketTask?.send(.string("2")) { _ in }
        }
        
        receiveMessage()
    }
    
    func disconnect(isReconnecting: Bool = false) {
        pingTimer?.invalidate()
        pingTimer = nil
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        if !isReconnecting {
            DispatchQueue.main.async {
                self.isConnected = false
                self.isSubscribedToSeekgraph = false
                self.availableGames.removeAll()
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handleSocketRawMessage(text) }
                self.receiveMessage()
            case .failure(let error):
                if (error as NSError).code != 57 && (error as NSError).code != -999 {
                    print("OGS: ❌ Socket Error: \(error.localizedDescription)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if !self.isConnected { self.connect() }
                    }
                }
                DispatchQueue.main.async { self.isConnected = false }
            }
        }
    }

    private func handleSocketRawMessage(_ text: String) {
        if text.starts(with: "2") {
            webSocketTask?.send(.string("3")) { _ in }
            return
        }
        if text.starts(with: "3") { return }
        if text.starts(with: "0") { return }
        
        if text.starts(with: "40") {
            print("OGS: ✅ Connected")
            DispatchQueue.main.async { self.isConnected = true }
            self.subscribeToSeekgraph(force: true)
            if let user = self.username, let pass = self.getStoredPassword() {
                self.authenticate(username: user, password: pass) { _, _ in }
            }
            return
        }
        
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

        switch eventName {
        case "seekgraph/global":
            if let challenges = json[1] as? [[String: Any]] { handleSeekGraph(challenges) }
        case "automatch/start":
             if let data = json[1] as? [String: Any], let gameId = data["game_id"] as? Int {
                 print("OGS: 🎯 Match Found! \(gameId)")
                 DispatchQueue.main.async { self.activeGameID = gameId }
             }
        case let name where name.contains("/gamedata"):
            if let gameData = json[1] as? [String: Any] { handleGameData(gameData) }
        case let name where name.contains("/move"):
            if let moveData = json[1] as? [String: Any] { handleMove(moveData) }
        case let name where name.contains("/clock"):
            if let clockData = json[1] as? [String: Any] { handleClock(clockData) }
        default: break
        }
    }
    
    // MARK: - Seek Graph
    func subscribeToSeekgraph(force: Bool = false) {
        guard webSocketTask != nil else { return }
        if isSubscribedToSeekgraph && !force { return }
        let msg = "42[\"seek_graph/connect\",{\"channel\":\"global\"}]"
        webSocketTask?.send(.string(msg)) { _ in }
        isSubscribedToSeekgraph = true
        print("OGS: 📡 Subscribed to SeekGraph")
    }
    
    func unsubscribeFromSeekgraph() {
        let msg = "42[\"seek_graph/disconnect\",{\"channel\":\"global\"}]"
        webSocketTask?.send(.string(msg)) { _ in }
        isSubscribedToSeekgraph = false
    }
    
    private func handleSeekGraph(_ challenges: [[String: Any]]) {
        var idsToRemove: Set<Int> = []
        var toUpsert: [OGSChallenge] = []
        
        // Helper to format seconds nicely: 65 -> "1m 5s", 60 -> "1m", 30 -> "30s"
        func fmtTime(_ s: Int) -> String {
            if s < 60 { return "\(s)s" }
            if s % 60 == 0 { return "\(s/60)m" }
            return "\(s/60)m \(s%60)s"
        }
        
        for item in challenges {
            if let deleteID = item["delete"] as? Bool, deleteID == true, let id = item["challenge_id"] as? Int {
                idsToRemove.insert(id)
                continue
            }
            
            guard let id = item["challenge_id"] as? Int,
                  let username = item["username"] as? String,
                  let rank = item["rank"] as? Double else { continue }
            
            let width = item["width"] as? Int ?? 19
            let height = item["height"] as? Int ?? 19
            
            // --- TIME PARSING START ---
            var timeControlString = "Unknown"
            var isCorrespondence = false
            
            if let tcDict = item["time_control"] as? [String: Any] {
                // Check Speed
                if let spd = tcDict["speed"] as? String, spd == "correspondence" { isCorrespondence = true }
                
                // Format String based on System
                if let system = tcDict["system"] as? String {
                    if system == "byoyomi" {
                        // "1m + 5x 30s"
                        let main = fmtTime(tcDict["main_time"] as? Int ?? 0)
                        let pTime = fmtTime(tcDict["period_time"] as? Int ?? 0)
                        let pCount = tcDict["periods"] as? Int ?? 0
                        timeControlString = "\(main) + \(pCount)x \(pTime)"
                        
                    } else if system == "fischer" {
                        // "2m 30s + 15s 4m max"
                        let initTime = fmtTime(tcDict["initial_time"] as? Int ?? 0)
                        let inc = fmtTime(tcDict["time_increment"] as? Int ?? 0)
                        let max = fmtTime(tcDict["max_time"] as? Int ?? 0)
                        
                        timeControlString = "\(initTime) + \(inc)"
                        if (tcDict["max_time"] as? Int ?? 0) > 0 {
                            timeControlString += " \(max) max"
                        }
                        
                    } else if system == "canadian" {
                        // "10m + 15/5m"
                        let main = fmtTime(tcDict["main_time"] as? Int ?? 0)
                        let pTime = fmtTime(tcDict["period_time"] as? Int ?? 0)
                        let stones = tcDict["stones_per_period"] as? Int ?? 0
                        timeControlString = "\(main) + \(stones)/\(pTime)"
                        
                    } else if system == "simple" {
                        let perMove = fmtTime(tcDict["time_per_move"] as? Int ?? 0)
                        timeControlString = "\(perMove)/mv"
                        
                    } else {
                        timeControlString = system.capitalized
                    }
                }
            } else if let tcStr = item["time_control"] as? String {
                timeControlString = tcStr
            }
            
            if let tpm = item["time_per_move"] as? Int, tpm > 10800 { isCorrespondence = true }
            if isCorrespondence { timeControlString = "correspondence" }
            // --- TIME PARSING END ---
            
            var startedString: String? = nil
            if let startedBool = item["started"] as? Bool, startedBool == true {
                startedString = "Started"
            } else if let startedInt = item["started"] as? Int, startedInt > 0 {
                startedString = "Started"
            } else if let startedStr = item["started"] as? String, !startedStr.isEmpty {
                startedString = startedStr
            }
            
            let challengerInfo = ChallengerInfo(id: 0, username: username, ranking: rank, professional: false)
            let gameInfo = GameInfo(
                id: 0, name: nil, width: width, height: height, rules: "japanese",
                ranked: true, handicap: 0, komi: nil,
                timeControl: timeControlString,
                timeControlParameters: nil,
                disableAnalysis: false, pauseOnWeekends: false,
                black: nil, white: nil,
                started: startedString,
                blackLost: false, whiteLost: false, annulled: false
            )
            
            let challenge = OGSChallenge(id: id, challenger: challengerInfo, game: gameInfo, challengerColor: "auto", minRanking: 0, maxRanking: 0, created: nil)
            toUpsert.append(challenge)
        }
        
        DispatchQueue.main.async {
            if !idsToRemove.isEmpty {
                self.availableGames.removeAll { idsToRemove.contains($0.id) }
            }
            for challenge in toUpsert {
                if let index = self.availableGames.firstIndex(where: { $0.id == challenge.id }) {
                    self.availableGames[index] = challenge
                } else {
                    self.availableGames.append(challenge)
                }
            }
            self.availableGames.sort {
                let p1 = $0.game.started == nil
                let p2 = $1.game.started == nil
                if p1 != p2 { return p1 }
                return $0.id > $1.id
            }
        }
    }
    
    // MARK: - Game Actions
    func joinGame(gameID: Int) {
        print("OGS: 🎮 Joining Game \(gameID)")
        let connectMsg = "42[\"game/connect\",{\"game_id\":\(gameID),\"chat\":true}]"
        webSocketTask?.send(.string(connectMsg)) { _ in }
    }
    
    internal func handleGameData(_ data: [String: Any]) {
        NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["moves": data["moves"] ?? [], "gameData": data])
        if let clock = data["clock"] as? [String: Any] { handleClock(clock) }
    }
    
    internal func handleMove(_ data: [String: Any]) {
        guard let moveArr = data["move"] as? [Any], moveArr.count >= 2, let x = moveArr[0] as? Int, let y = moveArr[1] as? Int else { return }
        NotificationCenter.default.post(name: NSNotification.Name("OGSMoveReceived"), object: nil, userInfo: ["x": x, "y": y])
    }
    
    internal func handleClock(_ data: [String: Any]) {
        if let whiteTime = data["white_time"] as? Double { DispatchQueue.main.async { self.whiteTimeRemaining = whiteTime } }
        if let blackTime = data["black_time"] as? Double { DispatchQueue.main.async { self.blackTimeRemaining = blackTime } }
    }
    
    // MARK: - Automatch
    func startAutomatch() {
        print("OGS: 🔍 Starting Automatch (JSON Payload)...")
        let uuidString = UUID().uuidString
        let payload: [String: Any] = [
            "uuid": uuidString,
            "size_speed_options": [["size": "19x19", "speed": "live", "system": "byoyomi"]],
            "lower_rank_diff": -3,
            "upper_rank_diff": 3,
            "rules": ["condition": "required", "value": "japanese"],
            "handicap": ["condition": "no-preference", "value": "disabled"]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonPayload = try? JSONSerialization.jsonObject(with: jsonData),
              let finalData = try? JSONSerialization.data(withJSONObject: ["automatch/find_match", jsonPayload]),
              let finalString = String(data: finalData, encoding: .utf8) else { return }
        
        webSocketTask?.send(.string("42" + finalString)) { error in
            if let error = error { print("OGS: ❌ Automatch Send Error: \(error.localizedDescription)") }
        }
    }
    
    // MARK: - Custom Challenges
    func postCustomGame(settings: GameSettings, completion: @escaping (Bool, String?) -> Void) {
        print("OGS: 🎮 Posting Custom Game...")
        guard isAuthenticated else { completion(false, "Not authenticated"); return }
        
        ensureCSRFToken { token in
            guard let token = token else { completion(false, "CSRF Error"); return }
            
            guard let url = URL(string: "https://online-go.com/api/v1/challenges") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://online-go.com", forHTTPHeaderField: "Referer")
            request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")
            request.setValue(token, forHTTPHeaderField: "X-CSRFToken")
            
            var timeParams: [String: Any] = [
                "main_time": settings.mainTimeMinutes * 60,
                "time_control": settings.timeControlSystem.apiValue,
                "system": settings.timeControlSystem.apiValue,
                "pause_on_weekends": false
            ]
            timeParams["speed"] = "live"
            if settings.timeControlSystem == .byoyomi {
                timeParams["period_time"] = settings.periodTimeSeconds
                timeParams["periods"] = settings.periods
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
                    "time_control_parameters": timeParams
                ] as [String: Any]
            ]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            self.urlSession?.dataTask(with: request) { data, response, error in
                if let httpResp = response as? HTTPURLResponse, (200...201).contains(httpResp.statusCode) {
                    print("OGS: ✅ Challenge Posted")
                    DispatchQueue.main.async { completion(true, nil) }
                } else {
                    print("OGS: ❌ Challenge Post Failed")
                    DispatchQueue.main.async { completion(false, "Server Error") }
                }
            }.resume()
        }
    }
    
    // MARK: - Auth
    func authenticate(username: String? = nil, password: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        let user = username ?? self.username
        let pass = password ?? getStoredPassword()
        guard let user = user, let pass = pass else { completion(false, "No credentials"); return }
        
        ensureCSRFToken { token in
            guard let t = token else { completion(false, "CSRF Error"); return }
            self.performLogin(username: user, password: pass, csrfToken: t, completion: completion)
        }
    }
    
    private func ensureCSRFToken(completion: @escaping (String?) -> Void) {
        if let cookies = HTTPCookieStorage.shared.cookies, let token = cookies.first(where: { $0.name == "csrftoken" })?.value {
            completion(token); return
        }
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { completion(nil); return }
        self.urlSession?.dataTask(with: url) { _, _, _ in
            if let cookies = HTTPCookieStorage.shared.cookies, let token = cookies.first(where: { $0.name == "csrftoken" })?.value {
                completion(token)
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    private func performLogin(username: String, password: String, csrfToken: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://online-go.com/api/v0/login") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://online-go.com", forHTTPHeaderField: "Referer")
        request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")
        request.setValue(csrfToken, forHTTPHeaderField: "X-CSRFToken")
        
        let body = ["username": username, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        self.urlSession?.dataTask(with: request) { data, response, _ in
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                DispatchQueue.main.async { completion(false, "Login Failed") }
                return
            }
            self.fetchUserConfig()
            DispatchQueue.main.async {
                self.isAuthenticated = true
                self.username = username
                self.saveCredentials(username: username, password: password)
                completion(true, nil)
            }
        }.resume()
    }
    
    private func fetchUserConfig() {
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { return }
        self.urlSession?.dataTask(with: url) { data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let user = json["user"] as? [String: Any] else { return }
            
            if let id = user["id"] as? Int { DispatchQueue.main.async { self.playerID = id } }
            if let rank = user["ranking"] as? Double { DispatchQueue.main.async { self.userRank = rank } }
            if let jwt = json["user_jwt"] as? String { self.authenticateSocket(jwt: jwt) }
        }.resume()
    }
    
    private func authenticateSocket(jwt: String) {
        let payload = ["jwt": jwt]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        webSocketTask?.send(.string("42[\"authenticate\",\(jsonString)]")) { _ in }
    }

    // MARK: - Keychain
    func saveCredentials(username: String, password: String) {
        let data = password.data(using: .utf8)!
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: username, kSecValueData as String: data]
        SecItemDelete(query as CFDictionary); SecItemAdd(query as CFDictionary, nil)
    }
    private func loadCredentials() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecReturnAttributes as String: true, kSecReturnData as String: true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let existing = item as? [String: Any], let user = existing[kSecAttrAccount as String] as? String {
            self.username = user
        }
    }
    func deleteCredentials() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService]
        SecItemDelete(query as CFDictionary)
        self.username = nil; self.isAuthenticated = false
    }
    private func getStoredPassword() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecReturnData as String: true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }
}

extension OGSClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("OGS: 🟢 WebSocket Connected")
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("OGS: 🔴 WebSocket Closed")
        DispatchQueue.main.async { self.isConnected = false }
    }
}
