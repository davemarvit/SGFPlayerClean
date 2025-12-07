//
//  OGSClient.swift
//  SGFPlayerClean
//
//  Created: 2025-11-30
//  Updated: 2025-12-07 (Added Debugging & Broadened Parsing)
//

import Foundation
import Security
import Combine

class OGSClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    
    @Published var isConnected = false
    @Published var activeGameID: Int?
    @Published var lastError: String?
    
    @Published var isAuthenticated = false
    @Published var username: String?
    @Published var playerID: Int?
    @Published var userRank: Double?
    
    @Published var playerColor: Stone?
    
    // Metadata
    @Published var blackPlayerName: String?
    @Published var whitePlayerName: String?
    @Published var blackPlayerRank: Double?
    @Published var whitePlayerRank: Double?
    
    // Clocks
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
    
    // Limit debug logs so we don't flood the console
    private var debugLogCount = 0
    
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
                self.activeGameID = nil
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
        if text.starts(with: "3") || text.starts(with: "0") { return }
        
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
        
        // --- HELPERS ---
        func fmtTime(_ s: Int) -> String {
            if s == 0 { return "0s" } // Avoid empty/confusing output
            if s < 60 { return "\(s)s" }
            if s % 60 == 0 { return "\(s/60)m" }
            return "\(s/60)m \(s%60)s"
        }
        
        // Robust Extractor for JSON values (Int, Double, String)
        func getInt(_ dict: [String: Any], key: String) -> Int {
            if let i = dict[key] as? Int { return i }
            if let d = dict[key] as? Double { return Int(d) }
            if let s = dict[key] as? String {
                if let i = Int(s) { return i }
                // Sometimes it might be "20m". This simple parser won't catch that, but OGS usually sends raw ints.
                return 0
            }
            return 0
        }
        // ----------------
        
        for item in challenges {
            if let deleteID = item["delete"] as? Bool, deleteID == true {
                if let id = item["challenge_id"] as? Int { idsToRemove.insert(id) }
                continue
            }
            guard let id = item["challenge_id"] as? Int, let username = item["username"] as? String else { continue }
            
            // --- DEBUG LOGGING (First 5 items only) ---
            if debugLogCount < 5 {
                debugLogCount += 1
                if let tc = item["time_control"] {
                    print("DEBUG TC [\(id)]: \(tc)")
                }
            }
            // ------------------------------------------

            let rank = item["rank"] as? Double ?? 0.0
            let width = item["width"] as? Int ?? 19
            let height = item["height"] as? Int ?? 19
            
            var timeControlString = "Unknown"
            var isCorrespondence = false
            var timeControlParamsJson: String? = nil
            
            // 1. Try to find the params dictionary
            var tcParams: [String: Any]? = item["time_control"] as? [String: Any]
            
            // Fallback: Check "time_control_parameters" if "time_control" was just a string
            if tcParams == nil {
                if let extraParams = item["time_control_parameters"] as? [String: Any] {
                    tcParams = extraParams
                }
            }
            
            // 2. Process Dictionary
            if let params = tcParams {
                // Save JSON for potential future use
                if let jsonData = try? JSONSerialization.data(withJSONObject: params), let str = String(data: jsonData, encoding: .utf8) {
                    timeControlParamsJson = str
                }
                
                if let spd = params["speed"] as? String, spd == "correspondence" { isCorrespondence = true }
                
                // Extract System (handle missing key safely)
                let systemRaw = (params["system"] as? String) ?? (item["time_control"] as? String) ?? "unknown"
                let system = systemRaw.lowercased().trimmingCharacters(in: .whitespaces)

                if system.contains("byo") { // Matches "byoyomi", "byo_yomi"
                    let main = fmtTime(getInt(params, key: "main_time"))
                    let pTime = fmtTime(getInt(params, key: "period_time"))
                    let pCount = getInt(params, key: "periods")
                    timeControlString = "\(main) + \(pCount)x\(pTime)"
                    
                } else if system.contains("fisch") || system.contains("fisher") { // Matches "fischer", "fisher"
                    let initTime = fmtTime(getInt(params, key: "initial_time"))
                    let inc = fmtTime(getInt(params, key: "time_increment"))
                    timeControlString = "\(initTime) + \(inc)/mv"
                    
                } else if system.contains("canadian") {
                    let main = fmtTime(getInt(params, key: "main_time"))
                    let pTime = fmtTime(getInt(params, key: "period_time"))
                    let stones = getInt(params, key: "stones_per_period")
                    timeControlString = "\(main) + \(stones)/\(pTime)"
                    
                } else if system.contains("simple") {
                    let perMove = fmtTime(getInt(params, key: "per_move"))
                    timeControlString = "\(perMove)/mv"
                    
                } else {
                    timeControlString = system.capitalized
                }
            } else if let tcStr = item["time_control"] as? String {
                // If we really only got a string and no params anywhere
                timeControlString = tcStr.capitalized
            }
            
            // Override for correspondence if duration is massive
            if let tpm = item["time_per_move"] as? Int, tpm > 10800 { isCorrespondence = true }
            if isCorrespondence { timeControlString = "Correspondence" }
            
            var startedString: String? = nil
            if let startedBool = item["started"] as? Bool, startedBool == true { startedString = "Started" }
            
            let challengerInfo = ChallengerInfo(id: 0, username: username, ranking: rank, professional: false)
            let gameInfo = GameInfo(
                id: 0,
                name: nil,
                width: width,
                height: height,
                rules: "japanese",
                ranked: true,
                handicap: 0,
                komi: nil,
                timeControl: timeControlString,
                timeControlParameters: timeControlParamsJson,
                disableAnalysis: false,
                pauseOnWeekends: false,
                black: nil,
                white: nil,
                started: startedString,
                blackLost: false,
                whiteLost: false,
                annulled: false
            )
            
            let challenge = OGSChallenge(id: id, challenger: challengerInfo, game: gameInfo, challengerColor: "auto", minRanking: 0, maxRanking: 0, created: nil)
            toUpsert.append(challenge)
        }
        
        DispatchQueue.main.async {
            if !idsToRemove.isEmpty { self.availableGames.removeAll { idsToRemove.contains($0.id) } }
            for challenge in toUpsert {
                if let index = self.availableGames.firstIndex(where: { $0.id == challenge.id }) { self.availableGames[index] = challenge }
                else { self.availableGames.append(challenge) }
            }
            self.availableGames.sort { ($0.game.started == nil) && ($1.game.started != nil) }
        }
    }
    
    // MARK: - Game Actions
    func joinGame(gameID: Int) {
        print("OGS: 🎮 Joining Game \(gameID)")
        let connectMsg = "42[\"game/connect\",{\"game_id\":\(gameID),\"chat\":true}]"
        webSocketTask?.send(.string(connectMsg)) { _ in }
    }
    
    func acceptChallenge(challengeID: Int, completion: @escaping (Int?) -> Void) {
        print("OGS: 🤝 Accepting Challenge \(challengeID)...")
        guard isAuthenticated else { completion(nil); return }
        
        ensureCSRFToken { token in
            guard let token = token else { completion(nil); return }
            guard let url = URL(string: "https://online-go.com/api/v1/challenges/\(challengeID)/accept") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://online-go.com", forHTTPHeaderField: "Referer")
            request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")
            request.setValue(token, forHTTPHeaderField: "X-CSRFToken")
            request.httpBody = "{}".data(using: .utf8)
            
            self.urlSession?.dataTask(with: request) { data, _, _ in
                guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { completion(nil); return }
                
                var foundID: Int? = nil
                if let id = json["id"] as? Int { foundID = id }
                else if let id = json["game_id"] as? Int { foundID = id }
                else if let id = json["game"] as? Int { foundID = id }
                else if let gameObj = json["game"] as? [String: Any], let id = gameObj["id"] as? Int { foundID = id }
                
                DispatchQueue.main.async { completion(foundID) }
            }.resume()
        }
    }
    
    func sendMove(gameID: Int, x: Int, y: Int) {
        let moveString = SGFCoordinates.toSGF(x: x, y: y)
        print("OGS: 📤 Sending Move \(x),\(y) -> \"\(moveString)\" for Game \(gameID)")
        let payload: [String: Any] = ["game_id": gameID, "move": moveString]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload), let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        webSocketTask?.send(.string("42[\"game/move\",\(jsonString)]")) { _ in }
    }
    
    internal func handleGameData(_ data: [String: Any]) {
        if let bid = data["black_player_id"] as? Int, bid == self.playerID {
            DispatchQueue.main.async { self.playerColor = .black }
        } else if let wid = data["white_player_id"] as? Int, wid == self.playerID {
            DispatchQueue.main.async { self.playerColor = .white }
        } else {
            DispatchQueue.main.async { self.playerColor = nil }
        }
        
        if let players = data["players"] as? [String: Any] {
            if let black = players["black"] as? [String: Any] {
                DispatchQueue.main.async { self.blackPlayerName = black["username"] as? String; self.blackPlayerRank = black["ranking"] as? Double }
            }
            if let white = players["white"] as? [String: Any] {
                DispatchQueue.main.async { self.whitePlayerName = white["username"] as? String; self.whitePlayerRank = white["ranking"] as? Double }
            }
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["moves": data["moves"] ?? [], "gameData": data])
        if let clock = data["clock"] as? [String: Any] { handleClock(clock) }
    }
    
    internal func handleMove(_ data: [String: Any]) {
        guard let moveArr = data["move"] as? [Any], moveArr.count >= 2, let x = moveArr[0] as? Int, let y = moveArr[1] as? Int else { return }
        NotificationCenter.default.post(name: NSNotification.Name("OGSMoveReceived"), object: nil, userInfo: ["x": x, "y": y])
    }
    
    internal func handleClock(_ data: [String: Any]) {
        DispatchQueue.main.async {
            // Helper to extract time regardless of Double vs String/Int
            func extractTime(_ key: String) -> Double? {
                if let d = data[key] as? Double { return d }
                if let i = data[key] as? Int { return Double(i) }
                return nil
            }
            
            if let wt = extractTime("white_time") { self.whiteTimeRemaining = wt }
            if let bt = extractTime("black_time") { self.blackTimeRemaining = bt }
            
            if let wp = data["white_periods"] as? Int { self.whitePeriodsRemaining = wp }
            if let bp = data["black_periods"] as? Int { self.blackPeriodsRemaining = bp }
        }
    }
    
    // MARK: - Delegates
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("OGS: 🟢 WebSocket Connected")
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("OGS: 🔴 WebSocket Closed")
        DispatchQueue.main.async { self.isConnected = false }
    }
    
    // MARK: - Auth & Utils
    func startAutomatch() { /* ... */ }
    func postCustomGame(settings: GameSettings, completion: @escaping (Bool, String?) -> Void) { /* ... */ }
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
        if let cookies = HTTPCookieStorage.shared.cookies, let token = cookies.first(where: { $0.name == "csrftoken" })?.value { completion(token); return }
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { completion(nil); return }
        self.urlSession?.dataTask(with: url) { _, _, _ in
            if let cookies = HTTPCookieStorage.shared.cookies, let token = cookies.first(where: { $0.name == "csrftoken" })?.value { completion(token) } else { completion(nil) }
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
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { completion(false, "Login Failed"); return }
            self.fetchUserConfig()
            DispatchQueue.main.async {
                self.isAuthenticated = true; self.username = username; self.saveCredentials(username: username, password: password)
                completion(true, nil)
            }
        }.resume()
    }
    
    private func fetchUserConfig() {
        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else { return }
        self.urlSession?.dataTask(with: url) { data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let user = json["user"] as? [String: Any] else { return }
            if let id = user["id"] as? Int { DispatchQueue.main.async { self.playerID = id } }
            if let rank = user["ranking"] as? Double { DispatchQueue.main.async { self.userRank = rank } }
            if let jwt = json["user_jwt"] as? String { self.authenticateSocket(jwt: jwt) }
        }.resume()
    }
    
    private func authenticateSocket(jwt: String) {
        let payload = ["jwt": jwt]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload), let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        webSocketTask?.send(.string("42[\"authenticate\",\(jsonString)]")) { _ in }
    }

    func saveCredentials(username: String, password: String) {
        let data = password.data(using: .utf8)!
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: username, kSecValueData as String: data]
        SecItemDelete(query as CFDictionary); SecItemAdd(query as CFDictionary, nil)
    }
    private func loadCredentials() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecReturnAttributes as String: true, kSecReturnData as String: true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let existing = item as? [String: Any], let user = existing[kSecAttrAccount as String] as? String { self.username = user }
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
