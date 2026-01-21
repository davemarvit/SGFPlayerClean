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
    @Published var myActiveGames: Set<Int> = []
    @Published var finishedGameIDs: Set<Int> = [] // NEW: Persistent filter for Zombie games // Discovered active games for this user

    
    // UI Structure for Game Over
    struct GameResult {
        let title: String
        let subtitle: String
        let method: String
        let isMe: Bool
    }
    @Published var activeGameResult: GameResult?
    @Published var activeGameOutcome: String? // Legacy/Deprecated string for now
    @Published var playerColor: Stone?
    @Published var currentPlayerID: Int?
    var lastKnownRemoteMoveNumber: Int? // NEW: Track server's move number for Undo
    @Published var blackPlayerID: Int? = -1
    @Published var whitePlayerID: Int? = -1
    @Published var currentHandicap: Int = 0
    
    @Published var availableGames: [OGSChallenge] = []
    @Published var blackBoxContent: String = ""
    @Published var isSubscribedToSeekgraph = false
    @Published var trafficLogs: [NetworkLogEntry] = []
    
    @Published var blackPlayerRank: Double?
    @Published var whitePlayerRank: Double?
    @Published var blackPlayerCountry: String?
    @Published var whitePlayerCountry: String?

    @Published var blackPlayerName: String?
    @Published var whitePlayerName: String?
    
    @Published var blackTimeRemaining: TimeInterval?
    @Published var whiteTimeRemaining: TimeInterval?
    
    @Published var undoRequestedUsername: String? = nil
    @Published var undoRequestedMoveNumber: Int? = nil
    
    // LOGIC: Expectation Filter for Undo
    // When true, we ignore "stale" server updates that don't reduce the move count.
    @Published var isRequestingUndo: Bool = false {
        didSet {
            NSLog("[OGS-DEBUG] 🚩 isRequestingUndo CHANGED: \(oldValue) -> \(isRequestingUndo)")
        }
    }
    
    @Published var lastUndoneMoveNumber: Int? { // Guard against stale server data
        didSet {
            // NSLog("[OGS-DEBUG] 🛡️ lastUndoneMoveNumber CHANGED: \(oldValue ?? -1) -> \(lastUndoneMoveNumber ?? -1)")
        }
    }
    @Published var activeGameTimeControl: String?
    @Published var gameRules: String? // "japanese", "chinese"
    @Published var isRanked: Bool = false
    @Published var isGameFinished: Bool = false
    
    // Detailed Clock & State
    @Published var blackClockPeriods: Int?
    @Published var blackClockPeriodTime: Double?
    @Published var blackCaptures: Int = 0
    @Published var whiteClockPeriods: Int?
    @Published var whiteClockPeriodTime: Double?
    @Published var whiteCaptures: Int = 0
    
    // Byoyomi State (Phase B Step 5)
    @Published var blackPeriodLength: Double?

    @Published var whitePeriodLength: Double?
    
    // Scoring & Dead Stones
    @Published var phase: String? = "play"
    @Published var removedStones: Set<BoardPosition> = []
    
    // Debugging
    @Published var lastReceivedEvent: String = ""

    // MARK: - Private Protocol State
    private var lastClockSnapshot: [String: Any]?
    private var hasEnteredRoom: Bool = false
    
    // Keep-Alive
    private var keepAliveTimer: Timer?
    private var activeChallengeID: Int?
    private var activeChallengeGameID: Int?
    
    private var isSearchingForGame: Bool = false
    private var currentAutomatchUUID: String? // Track active Automatch request
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var socketPingTimer: Timer?
    private var handshakeTimer: Timer?
    private var enginePulseTimer: Timer?
    private var lobbyChallenges: [Int: OGSChallenge] = [:]
    private var lastReportedLatency: Int = 85
    var currentStateVersion: Int = 0
    private var requestSequence: Int = 100 // Client-side request counter
    
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
                        NSLog("[OGS-AUTH] ✅ Config Loaded. User: \(self.username ?? "nil") ID: \(self.playerID ?? -1)")
                    } else {
                         NSLog("[OGS-AUTH] ⚠️ Config Loaded but no 'user' object found.")
                    }
                    self.userJWT = json["user_jwt"] as? String
                    self.isAuthenticated = (self.userJWT != nil)
                    // if self.isAuthenticated { self.connect() } // DISABLED: AppModel controls connection
                    self.objectWillChange.send()
                }
            } else {
                 NSLog("[OGS-AUTH] ❌ fetchUserConfig JSON Parse Failed or No Data.")
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

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        isSocketAuthenticated = false
        socketPingTimer?.invalidate()
    }
    
    // MARK: - Authentication
    func logout() {
        // 1. Disconnect Socket
        disconnect()
        
        // 2. Clear Session Data
        self.userJWT = nil
        self.playerID = nil
        self.username = nil
        self.isAuthenticated = false
        
        // 3. Clear Cookies
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://online-go.com")!) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        
        // 4. Clear Defaults if any
        UserDefaults.standard.removeObject(forKey: "ods_session_token") // Example
        
        objectWillChange.send()
    }
    
    func login(username: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        // Attempt Session Login (Simulating Browser Form or API)
        // Note: For a robust 3rd party app, OAuth2 is preferred but requires Client ID/Secret.
        // We will try the undocumented UI login or simple legacy auth if available.
        // Strategy: Use the /api/v1/ui/login endpoint if it exists, or generic /login.
        
        // STRATEGY: Use the legacy /api/v0/login endpoint with CSRF protection.
        let url = URL(string: "https://online-go.com/api/v0/login")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(originHeader, forHTTPHeaderField: "Origin")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // CSRF INJECTION
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://online-go.com")!),
           let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value {
            req.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
            req.setValue(csrf, forHTTPHeaderField: "X-XSRF-TOKEN") // Redundancy
        }
        
        let body = ["username": username, "password": password]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        urlSession?.dataTask(with: req) { data, response, error in
            if let http = response as? HTTPURLResponse {
                // NSLog("[OGS-AUTH] Login Response: \(http.statusCode)")
                if http.statusCode == 200 || http.statusCode == 204 {
                    // Success! Cookies should be set automatically by URLSession.
                    // Now refresh config to get JWT.
                    self.fetchUserConfig()
                    completion(true, nil)
                } else {
                    let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                    // NSLog("[OGS-AUTH] Login Failed. Body: \(body)")
                    completion(false, "Login failed (Code \(http.statusCode))")
                }
            } else {
                completion(false, error?.localizedDescription ?? "Network Error")
            }
        }.resume()
    }

    func opponentName(for myID: Int?) -> String? {
        guard let myID = myID else { return nil }
        if myID == blackPlayerID { return whitePlayerName }
        if myID == whitePlayerID { return blackPlayerName }
        return nil
    }
    
    // MARK: - REST API Calls
    func fetchGameState(gameID: Int, completion: @escaping ([String: Any]?) -> Void) {
        // DEBUG TRACE: Who is calling this?
        let trace = Thread.callStackSymbols.joined(separator: "\n")
        // NSLog("[OGS-CS] 🚀 fetchGameState CALLED for \(gameID). Stack:\n\(trace)")
        
        let ts = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "https://online-go.com/api/v1/games/\(gameID)?t=\(ts)") else { completion(nil); return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData // FORCE FRESH DATA
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        if let jwt = userJWT { request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization") }
        urlSession?.dataTask(with: request) { data, _, _ in
            if let d = data, let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                // Debug REST Payload Structure
                let g = (json["gamedata"] as? [String: Any]) ?? json
                let m = g["moves"] as? [[Any]] ?? []
                
                // STATE VERSION SYNC
                if let sv = self.robustInt(g["state_version"]) ?? self.robustInt(g["move_number"]) {
                    DispatchQueue.main.async {
                         self.currentStateVersion = max(self.currentStateVersion, sv)
                         NSLog("[OGS-REST] 🔄 Updated State Version to \(self.currentStateVersion)")
                    }
                }
                
                NSLog("[OGS-REST] Fetched Game \(gameID). Moves: \(m.count)")
                
                if let initialState = g["initial_state"] as? [String: Any] {
                    NSLog("[OGS-REST] Has Initial State (Handicap/Setup)")
                }
                
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
        
        urlSession?.dataTask(with: request) { [weak self] data, response, error in
            
            guard let self = self else { return }
            if let d = data, let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let gid = self.robustInt(json["id"]) ?? self.robustInt(json["game_id"]) ?? self.robustInt(json["game"]) {
                DispatchQueue.main.async { completion(gid, nil) }
            } else {
                DispatchQueue.main.async { completion(nil, error) }
            }
        }.resume()
    }


    // MARK: - Native Socket Dispatchers
    func connectToGame(gameID: Int) {
        // FIX: If we are reconnecting to the SAME game and it is KNOWN FINISHED, do NOT reset flag.
        if self.activeGameID != gameID || !self.isGameFinished {
            self.isGameFinished = false
        }
        
        startEnginePulse(gameID: gameID)
        sendAction("game/connect", payload: ["game_id": gameID, "chat": true])
        guard !self.isGameFinished else { return } // Guard startClockTimer
        startClockTimer()
    }
    
    func sendMove(gameID: Int, x: Int, y: Int) {
        self.lastUndoneMoveNumber = nil // Disarm Ghost Guard (User is acting)
        let coord = SGFCoordinates.toSGF(x: x, y: y)
        var payload: [String: Any] = ["game_id": gameID, "move": coord, "blur": Int.random(in: 800...1200)]
        if let clock = lastClockSnapshot { payload["clock"] = clock }
        sendAction("game/move", payload: payload, sequence: currentStateVersion + 1)
    }

    func sendPass(gameID: Int) {
        self.lastUndoneMoveNumber = nil // Disarm Ghost Guard
        var payload: [String: Any] = ["game_id": gameID, "move": "..", "blur": 0]
        if let clock = lastClockSnapshot { payload["clock"] = clock }
        sendAction("game/move", payload: payload, sequence: currentStateVersion + 1)
    }

    func resignGame(gameID: Int) {
        // NSLog("[OGS-GAME] Resigning \(gameID)")
        sendAction("game/resign", payload: ["game_id": gameID])
    }

    func createChallenge(setup: ChallengeSetup, completion: @escaping (Bool, String?) -> Void) {
        // Guard: Needs Player ID and JWT
        // Note: Added trailing slash to avoid potential 301 redirects dropping POST body
        guard let jwt = userJWT, let url = URL(string: "https://online-go.com/api/v1/challenges/") else {
             completion(false, "Not authenticated"); return
        }
        
        self.isSearchingForGame = true
        self.currentAutomatchUUID = nil
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://online-go.com")!),
           let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value { 
            request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
            request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        }
        
        let payload = setup.toDictionary()
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            NSLog("[OGS-REST] 📤 Creating Challenge Payload:\n\(jsonString)")
        }
        
        urlSession?.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[OGS-REST] ❌ Error: \(error)")
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
                return
            }
            
            if let d = data, let responseString = String(data: d, encoding: .utf8) {
                // Log the raw response for debugging
                NSLog("[OGS-REST] 📥 Raw Response:\n\(responseString)")
                
                if let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    // Success Check: 'id', 'challenge_id', or 'challenge'
                    if let id = self.robustInt(json["id"]) ?? 
                                self.robustInt(json["challenge_id"]) ?? 
                                self.robustInt(json["challenge"]) {
                        NSLog("[OGS-REST] ✅ Challenge Created Successfully. ID: \(id)")
                        
                        // Capture Game ID if present for Keep-Alive
                        let gid = self.robustInt(json["game"]) ?? self.robustInt(json["game_id"])
                        
                        DispatchQueue.main.async { 
                            self.startChallengeKeepAlive(challengeID: id, gameID: gid)
                            completion(true, nil) 
                        }
                    } else if let detail = json["detail"] as? String {
                         NSLog("[OGS-REST] ⚠️ Failed: \(detail)")
                         DispatchQueue.main.async { completion(false, detail) }
                    } else {
                         NSLog("[OGS-REST] ⚠️ Server Error or Unknown: \(json)")
                         DispatchQueue.main.async { completion(false, "Server Error: \(responseString)") }
                    }
                } else {
                    DispatchQueue.main.async { completion(false, "Invalid data received") }
                }
            } else {
                    DispatchQueue.main.async { completion(false, "Empty response") }
            }
        }.resume()
    }

    func startChallengeKeepAlive(challengeID: Int, gameID: Int?) {
        stopChallengeKeepAlive()
        
        self.activeChallengeID = challengeID
        self.activeChallengeGameID = gameID
        
        NSLog("[OGS] 🔄 Starting Keep-Alive for Challenge \(challengeID)")
        
        // Send immediately
        sendKeepAlive()
        
        // Repeat every 2 seconds
        self.keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sendKeepAlive()
        }
    }
    
    private func sendKeepAlive() {
        guard let cid = activeChallengeID else { return }
        var payload: [String: Any] = ["challenge_id": cid]
        if let gid = activeChallengeGameID { payload["game_id"] = gid }
        
        // Log sparingly? Or verbose for now to confirm fix.
        // NSLog("[OGS-KEEP] 💓 KeepAlive C:\(cid)") 
        sendAction("challenge/keepalive", payload: payload)
    }
    
    func stopChallengeKeepAlive() {
        if let t = keepAliveTimer {
            t.invalidate()
            keepAliveTimer = nil
            NSLog("[OGS] 🛑 Stopped Keep-Alive")
        }
        activeChallengeID = nil
        activeChallengeGameID = nil
    }

    func cancelChallenge(challengeID: Int) {
        stopChallengeKeepAlive() // Stop pinging
        
        // OGS API: DELETE /api/v1/challenges/<id>/
        // Implementation TODO if needed, or use socket 'challenge/delete' if available?
        // Web usually uses DELETE REST endpoint or socket 'automatch/cancel'.
        // For REST challenges, DELETE is correct.
        
        guard let jwt = userJWT, let url = URL(string: "https://online-go.com/api/v1/challenges/\(challengeID)/") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        // Add Cookies if needed (usually good idea)
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://online-go.com")!) {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            if let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value {
                request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
            }
        }

        urlSession?.dataTask(with: request) { _, _, error in
            if let e = error { NSLog("[OGS] ❌ Cancel Challenge Failed: \(e)") }
            else { NSLog("[OGS] ✅ Challenge Cancelled: \(challengeID)") }
        }.resume()
        
        // Phase 1: Try Automatch Cancel (Priority)
        if let uuid = self.currentAutomatchUUID {
            NSLog("[OGS-DEBUG] 📤 Cancelling Automatch UUID: \(uuid)")
            sendAction("automatch/available/remove", payload: ["uuid": uuid])
            self.currentAutomatchUUID = nil
        }
        
        // Phase 2: Try Seekgraph Cancel (Legacy/Safety)
        // If the challenge ID is known (from lobby list), we can also try removing it directly
        // just in case it was a legacy seek or persisted.
        if challengeID > 0 {
             NSLog("[OGS-DEBUG] 📤 Cancelling Challenge ID: \(challengeID)")
             sendAction("seek_graph/remove", payload: ["challenge_id": challengeID])
        }
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
        self.isRequestingUndo = true
        // self.lastUndoneMoveNumber = moveNumber // REMOVED: Do not limit future moves!
        // NSLog("[OGS-CLIENT] ↩️ sendUndoRequest: Flag SET to TRUE. Guard Armed for \(moveNumber)")
        NSLog("[OGS-CLIENT] 🚀 Sending Undo Request for Move \(moveNumber)")
        // FIX: Use Server's Last Known Move Number if available (Avoid Ghost Moves)
        let targetMove = self.lastKnownRemoteMoveNumber ?? moveNumber
        NSLog("[OGS-CLIENT] 🚀 Sending Undo Request for Remote Move \(targetMove). (Original Local: \(moveNumber))")
        sendAction("game/undo/request", payload: ["game_id": gameID, "move_number": targetMove])
    }


    func sendUndoAccept(gameID: Int, moveNumber: Int) {
         self.isRequestingUndo = true
         NSLog("[OGS-CLIENT] ↩️ sendUndoAccept: Flag SET to TRUE")
        sendAction("game/undo/accept", payload: ["game_id": gameID, "move_number": moveNumber], sequence: currentStateVersion + 1)
    }

    func sendUndoReject(gameID: Int) {
        sendAction("game/undo/cancel", payload: ["game_id": gameID])
    }
    
    // MARK: - Scoring Actions
    func acceptScore(gameID: Int) {
        NSLog("[OGS-SCORING] 🤝 Accepting Score for \(gameID)")
        sendAction("stone_removal/accept", payload: ["game_id": gameID])
    }
    
    func sendRemovedStones(gameID: Int, stones: String, removed: Bool) {
        NSLog("[OGS-SCORING] 📤 Updating Removed Stones Delta: \(removed ? "REMOVE" : "REVIVE") \(stones)")
        // Web Protocol: { "game_id": 123, "removed": true/false, "stones": "aabb" }
        // Event: "game/removed_stones/set"
        let payload: [String: Any] = [
            "game_id": gameID,
            "removed": removed,
            "stones": stones
        ]
        sendAction("game/removed_stones/set", payload: payload)
    }

    
    func subscribeToSeekgraph() {
        sendAction("seek_graph/connect", payload: ["channel": "global"])
        self.isSubscribedToSeekgraph = true
    }
    
    func performPostAuthSubscriptions() {
        guard isConnected else { return }
        // PILLAR: Full Handshake from Web Trace
        // 1. Common Pushes
        sendAction("ui-pushes/subscribe", payload: ["channel": "announcements"])
        sendAction("ui-pushes/subscribe", payload: ["channel": "gotv"])
        
        // 2. Automatch (Essential for visibility)
        sendAction("automatch/available/subscribe", payload: [:])
        sendAction("automatch/list", payload: [:]) // Asks "What am I in?"
        
        // 3. Self Monitor (Optional but good for presence)
        if let pid = playerID {
            sendAction("user/monitor", payload: ["user_ids": [pid]])
        }
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
        if text.hasPrefix("40") {
             startSocketHeartbeat();
             sendSocketAuth();
             // SoundManager.shared.play("opponent_connected") // USER REQUEST: Silence
             return
        }
        if text == "2" { sendRaw("3"); return }
        
        // ACK Handling (43)
        if text.hasPrefix("43") {
            let clean = String(text.dropFirst(2))
            if let data = clean.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                let seq = array.first as? Int ?? -1
                let response = array.count > 1 ? array[1] : nil
                NSLog("[OGS-ACK] 📥 Msg \(seq): \(response ?? "OK")")
            }
            return
        }
        
        // Event Handling (42)
        if text.hasPrefix("42") {
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

        // FIREHOSE LOGGING (Temporary)
        if eventName != "net/ping" && eventName != "net/pong" && eventName != "seekgraph/global" {
             // NSLog("[OGS-EVT] 📩 Event: \(eventName) Payload: \(payload.keys)")
        }
        
        if let sv = robustInt(payload["state_version"]) { self.currentStateVersion = max(self.currentStateVersion, sv) }

        if !isSocketAuthenticated && (eventName == "authenticated" || eventName == "notification" || eventName.contains("seekgraph")) {
            DispatchQueue.main.async { 
                self.isSocketAuthenticated = true
                self.subscribeToSeekgraph()
                self.performPostAuthSubscriptions() // UPDATED
            }
        }

        // PILLAR: SURGICAL DISCOVERY & FIREWALL
        if eventName == "active_game" || (eventName == "notification" && payload["type"] as? String == "gameStarted") {
            // FIX: Do NOT default to "play". Require explicit phase.
            let phase = payload["phase"] as? String
            DispatchQueue.main.async { self.phase = phase } // Update Local Phase Tracker
            if phase == "play" || phase == "stone removal" {
                let bid = robustInt(payload["black_id"]) ?? robustInt((payload["black"] as? [String: Any])?["id"])
                let wid = robustInt(payload["white_id"]) ?? robustInt((payload["white"] as? [String: Any])?["id"])
                
                DispatchQueue.main.async {
                    if bid == self.playerID || wid == self.playerID {
                        if let gid = self.robustInt(payload["game_id"]) ?? self.robustInt(payload["id"]) {
                            // FIX: Only track as "Active" if Phase is Play AND No Outcome
                            if (phase == "play" || phase == "stone removal") && payload["outcome"] == nil {
                                // FIX: Don't re-add if we know it's finished locally (Shield 2.0)
                                let isKnownFinished = self.finishedGameIDs.contains(gid)
                                let isCurrentFinished = (self.activeGameID == gid && self.isGameFinished)
                                
                                if isKnownFinished || isCurrentFinished {
                                      // NSLog("[OGS-LOBBY] 🛡️ Shield Blocked \(gid). (Known: \(isKnownFinished), CurrentFinished: \(isCurrentFinished))")
                                } else {
                                     // Only log if it's NEW to reduce spam (though loop implies spam)
                                     if !self.myActiveGames.contains(gid) {
                                         // NSLog("[OGS-LOBBY] ✅ Added 'active_game' \(gid). Phase: \(phase ?? "nil"), Outcome: nil")
                                     }
                                     self.myActiveGames.insert(gid)
                                }
                            } else {
                                // NSLog("[OGS-LOBBY] ⚠️ Ignored 'active_game' \(gid). Phase: \(phase ?? "nil"), Outcome: \(payload["outcome"] ?? "nil")")
                            }
                            
                            // CLEANUP: Removed garbage 'moves' parsing block.
                            
                            
                            if self.isSearchingForGame || self.activeGameID == gid {
                                 // FIX: Debounce connection. Strict Check.
                                 if self.activeGameID == gid {
                                     // NSLog("[OGS-LOBBY] 🛑 Debounced connect for \(gid). Already Active.")
                                 } else {
                                    self.activeGameID = gid
                                    self.isSearchingForGame = false
                                    self.stopChallengeKeepAlive() // Game started, stop pinging
                                    self.currentAutomatchUUID = nil
                                    self.connectToGame(gameID: gid)
                                    SoundManager.shared.play("game_started")
                                 }
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
        
        // AUTOMATCH CONFIRMATION
        if eventName == "automatch/available/add" {
            // Server is confirming our request!
            let uuid = payload["uuid"] as? String
            NSLog("[OGS-AUTOMATCH] ✅ Request Active. UUID: \(uuid ?? "?")")
            return
        }

        // Check for Game Over signals immediately
        if let phase = payload["phase"] as? String, phase == "finished" {
            self.isGameFinished = true
            self.stopEnginePulse()
            self.stopClockTimer()
        }
        if payload["outcome"] != nil {
            self.isGameFinished = true
            self.stopClockTimer()
        }

        if eventName.hasSuffix("/gamedata") {
            self.hasEnteredRoom = true
            if let p = payload as? [String: Any] {
                if let clock = p["clock"] as? [String: Any] { self.lastClockSnapshot = clock }
                handleInboundGameData(p)
            }
        } else if eventName.hasSuffix("/clock") {
            if !self.isGameFinished {
                 if let p = payload as? [String: Any] { self.lastClockSnapshot = p; handleInboundClock(p) }
            }
        } else if eventName.hasSuffix("/move") {
            handleIncomingMove(payload)
        } else if eventName.hasSuffix("/chat") {
            handleIncomingChat(payload)
        } else if eventName.hasSuffix("/undo_requested") {
            if let p = payload as? [String: Any],
               let whomID = robustInt(p["requested_by"]),
               whomID != self.playerID {
                let name = (whomID == self.blackPlayerID) ? (self.blackPlayerName ?? "Black") : ((whomID == self.whitePlayerID) ? (self.whitePlayerName ?? "White") : "Opponent")
                
                DispatchQueue.main.async {
                    self.undoRequestedUsername = name
                    self.undoRequestedMoveNumber = p["move_number"] as? Int
                }
            }
        } else if eventName.hasSuffix("/stone_removal") {
             if let removed = payload["removed"] as? String {
                 NSLog("[OGS-SCORING] ♻️ Live Remove Update: \(removed)")
                 DispatchQueue.main.async { self.handleInboundRemovedStones(removed) }
             } else if let removedArr = payload["removed"] as? [String] {
                 let joined = removedArr.joined()
                 NSLog("[OGS-SCORING] ♻️ Live Remove Update (Arr): \(joined)")
                 DispatchQueue.main.async { self.handleInboundRemovedStones(joined) }
             }
        } else if eventName.hasSuffix("/stone_removal") {
             // ... existing logic ...
        } else if eventName.hasSuffix("/removed_stones") {
             // Web Protocol: { "removed": true, "stones": "...", "all_removed": "aabbcc" }
             if let all = payload["all_removed"] as? String {
                 NSLog("[OGS-SCORING] 📥 Received Full Update (all_removed): \(all)")
                 DispatchQueue.main.async { self.handleInboundRemovedStones(all) }
             } else if let stones = payload["stones"] as? String {
                 // Fallback if all_removed missing (delta logic?)
                 // But logs show all_removed is present.
                 NSLog("[OGS-SCORING] ⚠️ Partial update receiving logic not fully implemented, relying on 'all_removed'. Stones: \(stones)")
             }
        }

        else if eventName.contains("undo_accepted") {
            // NSLog("OGS: ↩️ Undo Accepted event received: \(eventName). Triggering State Fetch.")
            
            // 2. Trigger Fetch to clear the board (Server Truth)
            // The Proactive Fetch might have been blocked or too early. This is the confirmation.
            // We use activeGameID because the payload might not have it in this event format
            if let gid = self.activeGameID {
                self.fetchGameState(gameID: gid) { data in
                    guard let data = data else { return }
                    // Broadcast the fetched state so AppModel can update the board
                    let g = (data["gamedata"] as? [String: Any]) ?? data
                    DispatchQueue.main.async {
                         NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": g])
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.undoRequestedUsername = nil
                self.undoRequestedMoveNumber = nil
                // DO NOT disarm ghost guard here. Wait for Sync.
            }
            
        } else if eventName.contains("/undo/reject") || eventName.contains("/undo/cancel") {
            NSLog("OGS: ↩️ Undo Cancelled/Rejected event received: \(eventName)")
            DispatchQueue.main.async {
                self.isRequestingUndo = false
                self.undoRequestedUsername = nil
                self.undoRequestedMoveNumber = nil
            }
        } else if eventName == "seekgraph/global" {
            if let items = array[1] as? [[String: Any]] { for i in items { updateLobbyItem(i) }; refreshLobbyUI() }
        } else if eventName == "net/ping" {
            handleNetPing(payload)
        }
    }

    // MARK: - Logic Handlers (Atomic)
    private func handleInboundGameData(_ p: [String: Any]) {
        DispatchQueue.main.async {
            let gid = self.robustInt(p["game_id"]) ?? self.robustInt(p["id"])
            NSLog("[OGS-DATA] 📦 handleInboundGameData for \(gid ?? -1). Keys: \(p.keys.sorted())")
            
            guard gid == self.activeGameID else { return }
            let players = p["players"] as? [String: Any]
            self.currentHandicap = self.robustInt(p["handicap"]) ?? 0
            
            // Phase A: Identity & Rank Parsing
            let blackObj = (players?["black"] as? [String: Any])
            let whiteObj = (players?["white"] as? [String: Any])
            
            self.blackPlayerID = self.robustInt(blackObj?["id"]) ?? self.robustInt(p["black_player_id"])
            self.whitePlayerID = self.robustInt(whiteObj?["id"]) ?? self.robustInt(p["white_player_id"])
            
            self.blackPlayerName = blackObj?["username"] as? String ?? self.blackPlayerName
            self.whitePlayerName = whiteObj?["username"] as? String ?? "White"
            
            let bR = (blackObj?["ranking"] as? Double) ?? (blackObj?["rank"] as? Double)
            let bR_int = (blackObj?["ranking"] as? Int) ?? (blackObj?["rank"] as? Int)
            self.blackPlayerRank = bR ?? bR_int.map { Double($0) }
            
            let wR = (whiteObj?["ranking"] as? Double) ?? (whiteObj?["rank"] as? Double)
            let wR_int = (whiteObj?["ranking"] as? Int) ?? (whiteObj?["rank"] as? Int)
            self.whitePlayerRank = wR ?? wR_int.map { Double($0) }
            self.blackPlayerCountry = blackObj?["country"] as? String
            self.whitePlayerCountry = whiteObj?["country"] as? String
            
            // Phase B: Game Rules & Ranked Status
            if let r = p["rules"] as? String { self.gameRules = r.capitalized }
            if let ranked = p["ranked"] as? Bool { self.isRanked = ranked }
            
            
            // Phase B: Static Time Control
            // Case 1: time_control is a dictionary (common in GameData)
            if let tcDict = p["time_control"] as? [String: Any] {
                let sys = (tcDict["system"] as? String) ?? (tcDict["time_control"] as? String)
                let tp = TimeParameters(
                    time_control: sys,
                    main_time: (tcDict["main_time"] as? Int) ?? (tcDict["initial_time"] as? Int),
                    initial_time: tcDict["initial_time"] as? Int,
                    periods: tcDict["periods"] as? Int,
                    period_time: tcDict["period_time"] as? Int,
                    time_increment: tcDict["time_increment"] as? Int,
                    increment: tcDict["increment"] as? Int,
                    stones_per_period: tcDict["stones_per_period"] as? Int,
                    per_move: tcDict["per_move"] as? Int
                )
                self.activeGameTimeControl = ChallengeHelpers.formatTimeControl(tc: sys, params: tp, perMove: nil)
                
                if let pt = tp.period_time {
                    self.blackPeriodLength = Double(pt)
                    self.whitePeriodLength = Double(pt)
                }
            }
            // Case 2: time_control is a string and params are separate (common in Challenges)
            else if let tc = p["time_control"] as? String, let params = p["time_control_parameters"] as? [String: Any] {
                let tp = TimeParameters(
                    time_control: params["time_control"] as? String,
                    main_time: (params["main_time"] as? Int) ?? (params["initial_time"] as? Int),
                    initial_time: params["initial_time"] as? Int,
                    periods: params["periods"] as? Int,
                    period_time: params["period_time"] as? Int,
                    time_increment: params["time_increment"] as? Int,
                    increment: params["increment"] as? Int,
                    stones_per_period: params["stones_per_period"] as? Int,
                    per_move: params["per_move"] as? Int
                )
                self.activeGameTimeControl = ChallengeHelpers.formatTimeControl(tc: tc, params: tp, perMove: nil)
                
                if let pt = tp.period_time {
                    self.blackPeriodLength = Double(pt)
                    self.whitePeriodLength = Double(pt)
                }
            }
            
            // Phase C: Initial Clock State
            // FIX: Parse 'clock' immediately so we have 'current_player' for tickClock()
            if let cAny = p["clock"] {
                // DEBUG: Check Type of Clock
                NSLog("[OGS-CLOCK] 🔍 Check 'clock' Type: \(type(of: cAny))")
                if let clockData = cAny as? [String: Any] {
                     self.handleInboundClock(clockData)
                } else {
                     NSLog("[OGS-CLOCK] ❌ 'clock' is NOT [String:Any]. It is \(type(of: cAny))")
                }
            } else {
                 // Fallback: If no clock object, try to find 'current_player' at root?
                 // Usually gamedata has 'clock'.
            }
            
            // Remove debugs
            // print("DEBUG: ...")
            
            // Phase B: Captures
            if let prisoners = p["score_prisoners"] as? [String: Any] {
                self.blackCaptures = (prisoners["black"] as? Int) ?? self.blackCaptures
                self.whiteCaptures = (prisoners["white"] as? Int) ?? self.whiteCaptures
            }

            // Phase D: Dead Stone Parsing (Scoring)
            if let ph = p["phase"] as? String {
                self.phase = ph
            }
            
            if let removedStr = p["removed"] as? String {
                self.handleInboundRemovedStones(removedStr)
            } else if let removedArr = p["removed"] as? [String] {
                let joined = removedArr.joined()
                self.handleInboundRemovedStones(joined)
            } else if let scoreStones = p["score_stones"] as? [ [String: Any] ] {
                 // Format: [ { "x": 16, "y": 16, "c": "b" }, ... ]
                 // This acts as the DEFINITIVE list of dead stones in some contexts.
                 var newRemoved: Set<BoardPosition> = []
                 for stoneKey in scoreStones {
                      if let x = stoneKey["x"] as? Int, let y = stoneKey["y"] as? Int {
                          newRemoved.insert(BoardPosition(y, x))
                      }
                 }
                 self.removedStones = newRemoved
                 NSLog("[OGS-SCORING] 💀 Parsed \(newRemoved.count) Dead Stones from 'score_stones'")
            }
            // ...


            
            // Phase C: Game End State
            // FIX: LATCH Logic. If we already know it's finished, don't reset to false unless explicit "play" phase seen.
            if let moves = p["moves"] as? [[Any]] {
                 // Update Remote Move Number (Critical for Undo)
                 let initial = self.robustInt((p["initial_state"] as? [String:Any])?["move_number"]) ?? 0
                 self.lastKnownRemoteMoveNumber = moves.count + initial
                 // NSLog("[OGS-CLIENT] 🔢 Updated Remote Move Number to \(self.lastKnownRemoteMoveNumber ?? -1) (Moves: \(moves.count) + Initial: \(initial))")
            }

            // Phase C: Game End State
            // FIX: LATCH Logic. If we already know it's finished, don't reset to false unless explicit "play" phase seen.
            if let movenum = p["move_number"] as? Int {
                 self.currentStateVersion = movenum
                 // self.lastKnownRemoteMoveNumber = movenum // Redundant or conflicting? 
                 // 'move_number' in gamedata root is usually the *last* move number?
                 // Let's trust 'moves.count' + initial if available, else this.
            }
            if let outcome = p["outcome"] as? String {
                self.isGameFinished = true
                // FIX: Use Game ID from payload directly.
                let targetGID = self.robustInt(p["game_id"]) ?? self.robustInt(p["id"]) ?? self.activeGameID
                if let gid = targetGID { 
                    DispatchQueue.main.async { 
                        self.finishedGameIDs.insert(gid)
                        NSLog("[OGS-DATA] 🏁 Marked Game \(gid) as Finished. (Shield Size: \(self.finishedGameIDs.count))")
                        // FIX: Remove from Active List immediately to kill Lobby Loop
                        if self.myActiveGames.contains(gid) {
                            self.myActiveGames.remove(gid)
                            NSLog("[OGS-LOBBY] 🧼 REMOVING Finished Game \(gid) (Trigger: Outcome)")
                        }
                    } 
                }
                
                // Detailed Result Formatting
                let winnerID = self.robustInt(p["winner"])
                let winnerName = (winnerID == self.blackPlayerID) ? (self.blackPlayerName ?? "Black") : ((winnerID == self.whitePlayerID) ? (self.whitePlayerName ?? "White") : "Draw")
                
                // If outcome is just "Resignation", prepend winner. Otherwise usage: "White+Resign" (Raw) vs "White wins by Resignation" (Human)
                // OGS 'outcome' is usually like "Resignation" or "Timeout" or "3.5 points"
                // So we construct: "[Name] wins by [Outcome]"
                
                if let wid = winnerID {
                    // Logic: Personalized Outcome Message & Structured Result
                    if let pid = self.playerID {
                        if wid == pid {
                            self.activeGameOutcome = "You won by \(outcome)"
                            self.activeGameResult = GameResult(
                                title: "You Win",
                                subtitle: "Your opponent \(winnerName == self.blackPlayerName ? (self.whitePlayerName ?? "White") : (self.blackPlayerName ?? "Black"))",
                                method: "Lost by \(outcome.capitalized)",
                                isMe: true
                            )
                        } else {
                            // Opponent won
                            let opponentName = (wid == self.blackPlayerID) ? (self.blackPlayerName ?? "Black") : (self.whitePlayerName ?? "White")
                            self.activeGameOutcome = "Your opponent, \(opponentName), wins by \(outcome)"
                             self.activeGameResult = GameResult(
                                title: "You Lost",
                                subtitle: "Your opponent \(opponentName)",
                                method: "Won by \(outcome.capitalized)",
                                isMe: false
                            )
                        }
                        SoundManager.shared.playWinner(isMe: wid == pid, isDraw: false, method: outcome)
                    } else {
                        // Observer / No PID
                        self.activeGameOutcome = "\(winnerName) wins by \(outcome)"
                         self.activeGameResult = GameResult(
                            title: "Game Over",
                            subtitle: "\(winnerName) wins",
                            method: "By \(outcome.capitalized)",
                            isMe: false
                        )
                    }
                } else {
                    self.activeGameOutcome = "Game Ended: \(outcome)"
                    if outcome.lowercased().contains("draw") {
                        self.activeGameResult = GameResult(title: "Draw", subtitle: "It is a draw", method: "", isMe: false)
                        SoundManager.shared.playWinner(isMe: false, isDraw: true)
                    } else {
                         SoundManager.shared.play("game_over")
                    }
                }
                
                self.stopClockTimer()
                self.stopEnginePulse()
            } else if let phase = p["phase"] as? String, phase == "finished" {
                self.isGameFinished = true
                
                // Determine Winner for Sound
                // Note: p["outcome"] might not be here, usually separate event. 
                // But if we have outcome stored or inferred?
                // Actually safer to rely on 'outcome' block above if available.
                // Or just play generic 'game_over' here if we missed the specific outcome?
                // Let's rely on the outcome block (lines 802-834) to call playWinner if possible.
                // But lines 802-834 don't have playWinner call yet. Let's add it there in next step.
                // For now, keep generic game_over here as fallback.
                SoundManager.shared.play("game_over")
                
                self.stopClockTimer()
                self.stopEnginePulse()
                // FIX: Remove from Active List
                if let gid = self.activeGameID {
                    DispatchQueue.main.async { 
                         self.myActiveGames.remove(gid)
                         self.finishedGameIDs.insert(gid)
                         NSLog("[OGS-LOBBY] 🧼 REMOVING Finished Game \(gid) (Trigger: Phase Finished)")
                    }
                }
            } else {
                // Only reset if we are sure it's active (e.g. phase is explicit "play")
                // Otherwise keep existing state vs "Zombie" partial updates.
                if let phase = p["phase"] as? String, phase == "play" {
                    self.isGameFinished = false
                    self.activeGameOutcome = nil
                } else if self.isGameFinished, let gid = self.activeGameID {
                    // FIX: If we confirmed it's finished (and phase != play), remove from Active List
                     DispatchQueue.main.async { 
                         NSLog("[OGS-LOBBY] 🧼 REMOVING Finished Game \(gid) from Active List (Count: \(self.myActiveGames.count))")
                         self.myActiveGames.remove(gid)
                         self.finishedGameIDs.insert(gid) // NEW: Remember it's finished
                     }
                }
                // If phase is missing, DO NOT CHANGE isGameFinished. 
                // (It might be a partial update for a finished game)
            }

            self.identityLockCheck()
            NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": p])
            self.objectWillChange.send()
            
            // Re-Ensure Clock is Running (in case connectToGame started it but we didn't have players yet)
            if !self.isGameFinished {
                self.startClockTimer()
            }
        }
    }

    private func handleInboundClock(_ data: [String: Any]) {
        DispatchQueue.main.async {
            // DEBUG: Log the Clock Data to catch "Reset" issues
            // NSLog("[OGS-CLOCK] 🕒 Received Clock: \(data)")
            
            // Black Clock
            var bSnapshot: Double? = nil
            if let b = data["black_time"] as? [String: Any] {
                // FIX: Parse into local var, do NOT assign to property yet (avoids oscillation)
                bSnapshot = self.robustDouble(b["thinking_time"])
                if let per = b["periods"] as? Int { self.blackClockPeriods = per }
                if let pt = self.robustDouble(b["period_time"]) { self.blackClockPeriodTime = pt }
            }
            
            // White Clock
            var wSnapshot: Double? = nil
            if let w = data["white_time"] as? [String: Any] {
                wSnapshot = self.robustDouble(w["thinking_time"])
                if let per = w["periods"] as? Int { self.whiteClockPeriods = per }
                if let pt = self.robustDouble(w["period_time"]) { self.whiteClockPeriodTime = pt }
            }
            
            if let cur = self.robustInt(data["current_player"]) { self.currentPlayerID = cur }
            
            // FIX: Robustly handle missing 'now'
            let nowV: Double = self.robustDouble(data["now"]) ?? (Date().timeIntervalSince1970 * 1000.0)
            
            // DEBUG CLOCK SYNC
            // let expV = data["expiration"]
            // let curV = data["current_player"]
            // NSLog("[OGS-CLOCK-DEBUG] 🕰️ SYNC: Now: \(data["now"] ?? "nil") | Exp: \(expV ?? "nil") | Cur: \(curV ?? "nil")")
            
            // Calculate Final Times
            var finalBlackTime: Double? = bSnapshot
            var finalWhiteTime: Double? = wSnapshot
            
            // Apply Hybrid Logic to the ACTIVE player
            if let cur = self.currentPlayerID {
                let isBlackActive = (cur == self.blackPlayerID)
                let isActiveSnapshot = isBlackActive ? bSnapshot : wSnapshot
                
                // Parse Period Time & Count for Buffer
                let pObj = isBlackActive ? (data["black_time"] as? [String: Any]) : (data["white_time"] as? [String: Any])
                
                let cachedPeriodTime = isBlackActive ? self.blackClockPeriodTime : self.whiteClockPeriodTime
                let cachedPeriods = isBlackActive ? self.blackClockPeriods : self.whiteClockPeriods
                
                let pTime = self.robustDouble(pObj?["period_time"]) ?? cachedPeriodTime ?? 0.0
                let pCount = self.robustInt(pObj?["periods"]) ?? cachedPeriods ?? 0
                
                // FIX: Expiration includes ALL periods (e.g. 3 * 10s = 30s) if in Main Time.
                // Subtracting just one period left 20s "Extra". Now subtracting All.
                let totalBuffer = Double(pCount) * pTime
                
                if let exp = self.robustDouble(data["expiration"]), let snapshotVal = isActiveSnapshot {
                     // Live Time Calculation
                     let timeFromExp = max(0, (exp - nowV) / 1000.0)
                     let correctedLiveTime = max(0, timeFromExp - totalBuffer)
                     
                     // Hybrid: min(Snapshot, Live)
                     let properTime = min(snapshotVal, correctedLiveTime)
                     
                     // Log Logic
                     // let diff = abs(snapshotVal - properTime)
                     // if diff > 1.0 {
                     //    NSLog("[OGS-CLOCK-FIX] ⚖️ Sync Adjust: Snap \(Int(snapshotVal)) vs Live \(Int(correctedLiveTime)) (Buff: \(Int(totalBuffer))) -> \(Int(properTime))")
                     // }
                     
                     if isBlackActive { finalBlackTime = properTime }
                     else { finalWhiteTime = properTime }
                     
                } else {
                    // Fallback to snapshot (already set by default)
                }
            }
            
            // Final Assignment (Single Update)
            if let b = finalBlackTime { self.blackTimeRemaining = b }
            if let w = finalWhiteTime { self.whiteTimeRemaining = w }
            
            // Phase B: Update captures... (omitted)
            
            // Phase B: Update captures from clock? No, usually in move or gamedata.
            // But sometimes move events carry captures.
            // For now, rely on gamedata captures.
        }
    }

    private func handleIncomingMove(_ data: [String: Any]) {
        // Update Remote Move Number
        if let num = robustInt(data["move_number"]) {
            self.lastKnownRemoteMoveNumber = num
            // NSLog("[OGS-CLIENT] 🔢 Move Event -> Remote Move Number: \(num)")
        }
    
        // Any incoming move invalidates pending undo requests (moot)
        DispatchQueue.main.async {
            self.undoRequestedUsername = nil
            self.undoRequestedMoveNumber = nil
            self.isRequestingUndo = false
        }
        NotificationCenter.default.post(name: NSNotification.Name("OGSMoveReceived"), object: nil, userInfo: data)
        
        // Audio Trigger
        // If it's MY turn now, play "Your Move"
        if let next = self.currentPlayerID, next == self.playerID {
             SoundManager.shared.play("your_move")
        } else {
             // Opponent played (or self played, but local echo handled by UI? No, strictly server echo here)
             // OGS echoes my move too. If data["player_id"] != me, it's opponent.
             // But simpler: just play click for everyone? User wants "Spoken Phrases".
             // "Your Move" is the key request.
        }
    }

    private func handleIncomingChat(_ data: [String: Any]) {
        // Expected payload: { "player_id": 123, "username": "Foo", "body": "Hello", "type": "main" }
        // Note: Sometimes internal system messages or 'malkovich' might appear.
        
        let type = data["type"] as? String ?? "main"
        // For now, filter out 'malkovich' or 'system' unless desired. OGS usually sends 'main' for public chat.
        guard type == "main" || type == "spectator" else { return }
        
        // Dispatch Notification
        // We do basic parsing here, but ViewModel can re-parse or we can pass raw dict.
        // Passing raw dict keeps the pattern consistent.
        
        // NSLog("[OGS-CHAT] 💬 Chat Received: \(data["body"] ?? "") from \(data["username"] ?? "")")
        
        DispatchQueue.main.async {
             NotificationCenter.default.post(name: NSNotification.Name("OGSChatReceived"), object: nil, userInfo: data)
        }
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
    
    // MARK: - Clock Timer (Phase B Step 4)
    private var clockTimer: Timer?
    private var lastTickTime: Date?
    
    private func startClockTimer() {
        clockTimer?.invalidate()
        lastTickTime = Date()
        guard !self.isGameFinished else { return }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickClock()
        }
    }
    
    private func stopClockTimer() {
        clockTimer?.invalidate()
        clockTimer = nil
    }
    
    private func tickClock() {
        guard !isGameFinished else { stopClockTimer(); return }
        guard let last = lastTickTime else { lastTickTime = Date(); return }
        let now = Date()
        let delta = now.timeIntervalSince(last)
        lastTickTime = now
        
        // Only tick if we have a current player
        guard let current = currentPlayerID else { return }
        
        // Determine active player
        var isBlack = false
        if let bid = blackPlayerID, current == bid { isBlack = true }
        else if let wid = whitePlayerID, current == wid { isBlack = false }
        else { return } // Not one of the players
        
        DispatchQueue.main.async {
            if isBlack {
                let main = self.blackTimeRemaining ?? 0
                if main > 0 {
                    self.blackTimeRemaining = max(0, main - delta)
                    // Countdown Logic
                    if main <= 10.0 && main >= 1.0 {
                        SoundManager.shared.playCountdown(Int(floor(main)))
                    }
                    // FIX: Check updated value for transition to 0
                    if (main - delta) <= 0 { 
                         if self.playerID == self.blackPlayerID { SoundManager.shared.playByoyomiStart() }
                    }
                } else if var periods = self.blackClockPeriods, periods > 0 {
                    let pt = self.blackClockPeriodTime ?? 0
                    if pt > 0 {
                         self.blackClockPeriodTime = max(0, pt - delta)
                         // Countdown Logic (Byoyomi)
                         if pt <= 10.0 { SoundManager.shared.playCountdown(Int(floor(pt))) }
                     } else {
                         // Transition: Period Expired
                         periods -= 1
                         self.blackClockPeriods = periods
                         // Sound Trigger
                         if self.playerID == self.blackPlayerID {
                             if periods <= 0 { SoundManager.shared.play("timeout") }
                             else { SoundManager.shared.playPeriodCount(periods) }
                         }
                         
                         if periods > 0, let len = self.blackPeriodLength {
                             self.blackClockPeriodTime = len
                         } else {
                             self.blackClockPeriodTime = 0
                         }
                    }
                }
            } else {
                let main = self.whiteTimeRemaining ?? 0
                if main > 0 {
                    self.whiteTimeRemaining = max(0, main - delta)
                    // Countdown Logic
                    if main <= 10.0 && main >= 1.0 {
                        SoundManager.shared.playCountdown(Int(floor(main)))
                    }
                    // FIX: Check updated value for transition to 0
                    if (main - delta) <= 0 { 
                         if self.playerID == self.whitePlayerID { SoundManager.shared.playByoyomiStart() }
                    }
                } else if var periods = self.whiteClockPeriods, periods > 0 {
                    let pt = self.whiteClockPeriodTime ?? 0
                    if pt > 0 {
                         self.whiteClockPeriodTime = max(0, pt - delta)
                         // Countdown Logic (Byoyomi)
                         if pt <= 10.0 { SoundManager.shared.playCountdown(Int(floor(pt))) }
                    } else {
                         // Transition
                         periods -= 1
                         self.whiteClockPeriods = periods
                         
                         if self.playerID == self.whitePlayerID {
                            if periods <= 0 { SoundManager.shared.play("timeout") }
                            else { SoundManager.shared.playPeriodCount(periods) }
                         }
                         
                         if periods > 0, let len = self.whitePeriodLength {
                             self.whiteClockPeriodTime = len
                         } else {
                             self.whiteClockPeriodTime = 0
                         }
                    }
                }
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
        let payload: [String: Any] = ["jwt": jwt, "player_id": pid, "username": username ?? ""]
        NSLog("[OGS-AUTH] 🔐 Authenticating with: \(payload)")
        sendAction("authenticate", payload: payload)
    }

    private func identityLockCheck() {
        guard let myID = self.playerID else { return }
        if myID == self.blackPlayerID { self.playerColor = .black }
        else if myID == self.whitePlayerID { self.playerColor = .white }
    }

    private func sendAction(_ event: String, payload: [String: Any], sequence: Int? = nil) {
        let json = tightJson(payload)
        let packet = (sequence != nil) ? "42[\"\(event)\",\(json),\(sequence!)]" : "42[\"\(event)\",\(json)]"
        // if event != "net/ping" { NSLog("[OGS-SOCKET] 📤 Sending: \(packet)") }
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



    // ... (rest of methods) ...

    private func updateLobbyItem(_ dict: [String: Any]) {
        // CASE 1: Delete Command { "delete": 12345 } or { "challenge_id": 123, "delete": true }
        if let deleteID = robustInt(dict["delete"]) {
            self.lobbyChallenges.removeValue(forKey: deleteID)
            return
        }
        
        guard let id = robustInt(dict["challenge_id"]) ?? robustInt(dict["game_id"]) else { return }
        
        if dict["delete"] != nil { 
            self.lobbyChallenges.removeValue(forKey: id)
            return 
        }
        
        // DEBUG: Trace incoming items to see if we see our own
        if let data = try? JSONSerialization.data(withJSONObject: dict), 
           let ch = try? JSONDecoder().decode(OGSChallenge.self, from: data) {
            
            self.lobbyChallenges[id] = ch
            
            // Check if it's mine
            if let pid = self.playerID, let creatorID = ch.challenger?.id, pid == creatorID {
                NSLog("[OGS-LOBBY] 🟢 Found MY Challenge: \(id). Creator: \(ch.challenger?.username ?? "?") (\(creatorID))")
            }
        } else {
             NSLog("[OGS-LOBBY] ⚠️ Failed to decode item: \(dict)")
        }
    }

    private func refreshLobbyUI() {
        DispatchQueue.main.async { self.availableGames = self.lobbyChallenges.values.filter { $0.game != nil }.sorted(by: { $0.id > $1.id }); self.objectWillChange.send() }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.isConnected = true; self.objectWillChange.send() }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        NSLog("OGS: 🔌 WebSocket CLOSED.")
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.isSocketAuthenticated = false
            self?.stopClockTimer()
        }
    }
    func robustDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let s = v as? String { return Double(s) }
        if let i = v as? Int { return Double(i) }
        return nil
    }
    private func handleInboundRemovedStones(_ removedStr: String) {
        var newRemoved: Set<BoardPosition> = []
        let chars = Array(removedStr)
        for i in stride(from: 0, to: chars.count, by: 2) {
            if i + 1 < chars.count {
                let s = String(chars[i...i+1])
                if let (x, y) = SGFCoordinates.parse(s) {
                    newRemoved.insert(BoardPosition(y, x))
                }
            }
        }
        self.removedStones = newRemoved
        NSLog("[OGS-SCORING] 💀 Parsed \(newRemoved.count) Dead Stones. Raw: '\(removedStr)'")

    }


}
