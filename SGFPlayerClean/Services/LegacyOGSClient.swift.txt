import Foundation
import Security
import SwiftUI

/// Represents the current phase of an OGS game
enum GamePhase: String {
    case preGame    // No active game, showing game setup UI
    case playing    // Game in progress, accepting moves
    case scoring    // Game finished, in scoring phase
    case finished   // Game complete, showing results
}

/// Represents the outcome of a finished game
enum GameOutcome: String {
    case blackWins = "B"        // Black wins by points or resignation
    case whiteWins = "W"        // White wins by points or resignation
    case tie = "0"              // Tie game (rare in Go)
    case timeout = "Timeout"    // Win by timeout
    case resignation = "Resignation"  // Win by resignation
    case cancellation = "Cancellation"  // Game cancelled
    case unknown = "?"          // Unknown outcome
}

/// Represents the final result of a game
struct GameResult {
    let gameID: Int
    let outcome: GameOutcome
    let winner: Stone?          // nil if tie or unknown
    let blackScore: Double
    let whiteScore: Double
    let winReason: String       // "resignation", "timeout", "points", etc.

    /// Score margin (absolute difference)
    var margin: Double {
        abs(blackScore - whiteScore)
    }

    /// Human-readable description of the result
    var winDescription: String {
        if let winner = winner {
            let winnerName = winner == .black ? "Black" : "White"
            if winReason == "resignation" || winReason == "Resignation" {
                return "\(winnerName) wins by resignation"
            } else if winReason == "timeout" || winReason == "Timeout" {
                return "\(winnerName) wins by timeout"
            } else {
                return "\(winnerName) wins by \(String(format: "%.1f", margin)) points"
            }
        } else {
            return "Game ended in a tie"
        }
    }
}

/// OGS (Online Go Server) WebSocket client for real-time game communication
class OGSClient: NSObject, ObservableObject {
    // MARK: - Debug Settings
    @AppStorage("verboseLogging") private var verboseLogging: Bool = false

    @Published var isConnected = false
    @Published var currentGameID: Int?
    @Published var lastError: String?
    @Published var blackTimeRemaining: TimeInterval?
    @Published var whiteTimeRemaining: TimeInterval?
    @Published var blackPeriodsRemaining: Int?
    @Published var whitePeriodsRemaining: Int?
    @Published var blackPeriodTime: TimeInterval?  // Length of each byo-yomi period
    @Published var whitePeriodTime: TimeInterval?  // Length of each byo-yomi period
    @Published var currentPlayerColor: Stone = .black
    @Published var playerColor: Stone?  // The color we are playing (also known as myColor)
    @Published var isAuthenticated = false
    @Published var username: String?
    @Published var playerID: Int?  // OGS player ID for the authenticated user
    @Published var userRank: Double?  // User's rank for filtering challenges

    // MARK: - Live Play State
    /// Current game phase - drives UI visibility and interaction
    @Published var gamePhase: GamePhase = .preGame
    /// Game result when the game is finished
    @Published var gameResult: GameResult? = nil

    // MARK: - Automatch State
    /// UUID of the current automatch request (if any)
    @Published var activeAutomatchUUID: String?
    /// Whether an automatch search is currently active
    @Published var isSearchingForMatch: Bool = false

    // MARK: - Challenge State
    /// Whether a challenge is being sent
    @Published var isSendingChallenge: Bool = false
    /// Available games/challenges that can be accepted
    @Published var availableGames: [OGSChallenge] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var authToken: String?
    private var jwtToken: String?  // JWT token for WebSocket authentication
    private let keychainService = "com.davemarvit.SGFPlayer3D.OGS"
    private var authCompletionHandler: ((Bool, String?) -> Void)?
    private var authTimeoutTimer: Timer?
    private var wsAuthPending = false  // Track if WebSocket auth is in progress
    private var isSubscribedToSeekgraph = false  // Track if we're subscribed to seekgraph
    private var reconnectAttempts = 0  // Track number of reconnection attempts
    private var maxReconnectAttempts = 5  // Maximum reconnection attempts before giving up
    private var lastSeekgraphMessageTime: Date?  // Track last seekgraph message for health monitoring
    private var seekgraphHealthTimer: Timer?  // Timer to check seekgraph health
    private let seekgraphStaleTimeout: TimeInterval = 60  // Consider seekgraph stale after 60s of no messages

    // v3.84: Challenge keepalive tracking
    private var activeChallengeID: Int?  // Currently active challenge that needs keepalives
    private var activeGameID: Int?  // Game ID associated with the active challenge
    private var challengeKeepaliveTimer: Timer?  // Timer to send periodic challenge/keepalive messages

    // Track last posted game state to prevent duplicate reloads
    private var lastPostedGameID: Int? = nil
    private var lastPostedMoveCount: Int = -1

    /// Returns true if it's our turn to play
    var isMyTurn: Bool {
        guard let myColor = playerColor else { return false }
        return currentPlayerColor == myColor
    }

    private func log(_ message: String) {
        NSLog(message)
        let logPath = "/tmp/sgfplayer_ogs.log"
        let timestamp = Date()
        let logLine = "[\(timestamp)] \(message)\n"
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
            }
        }
    }

    override init() {
        super.init()
        NSLog("OGS: ========== OGSClient v3.84 BUILD MARKER ==========")
        log("OGS: ========== v3.84 BUILD MARKER ==========")
        log("OGS: 🔧 Initializing OGSClient (self=\(Unmanaged.passUnretained(self).toOpaque()))...")
        // IMPORTANT: Initialize URLSession in init, not lazily
        // SwiftUI @StateObject requires proper initialization here
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300

        let queue = OperationQueue()
        queue.name = "OGSClient.WebSocket"

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        log("OGS: 🔧 URLSession created: \(String(describing: urlSession))")
        log("OGS: 🔧 URLSession delegate: \(String(describing: urlSession?.delegate))")
        loadCredentials()
    }

    // MARK: - Keychain Methods

    private func loadCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess,
           let existingItem = item as? [String: Any],
           let usernameData = existingItem[kSecAttrAccount as String] as? String,
           let passwordData = existingItem[kSecValueData as String] as? Data,
           let password = String(data: passwordData, encoding: .utf8) {
            self.username = usernameData
            NSLog("OGS: 🔑 Loaded credentials for user: \(usernameData)")
        }
    }

    func saveCredentials(username: String, password: String) {
        // Delete any existing credential first
        deleteCredentials()

        let passwordData = password.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: username,
            kSecValueData as String: passwordData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            self.username = username
            NSLog("OGS: 🔑 Saved credentials for user: \(username)")
        } else {
            NSLog("OGS: ❌ Failed to save credentials: \(status)")
        }
    }

    func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(query as CFDictionary)
        self.username = nil
        self.isAuthenticated = false
        NSLog("OGS: 🔑 Deleted stored credentials")
    }

    private func getStoredPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess,
           let passwordData = item as? Data,
           let password = String(data: passwordData, encoding: .utf8) {
            return password
        }
        return nil
    }

    /// Connect to OGS WebSocket server
    func connect() {
        // v3.86 FIX: Browser uses PLAIN WebSocket (not Socket.io) on wsp.online-go.com
        // Messages are plain JSON arrays: ["event", data] - NO Socket.io framing (no 42 prefix, no EIO handshake)
        guard let url = URL(string: "wss://wsp.online-go.com/") else {
            lastError = "Invalid WebSocket URL"
            return
        }

        // Ensure URLSession exists - recreate if needed
        if urlSession == nil {
            NSLog("OGS: ⚠️ URLSession was nil, recreating...")
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = HTTPCookieStorage.shared
            config.httpCookieAcceptPolicy = .always
            urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        }

        log("OGS: 🔌 Connecting to OGS WebSocket at \(url.absoluteString)")

        // Don't use custom headers - let URLSession handle the WebSocket upgrade
        guard let session = urlSession else {
            log("OGS: ❌ URLSession is nil!")
            lastError = "URLSession not initialized"
            return
        }

        webSocketTask = session.webSocketTask(with: url)
        log("OGS: 🔧 WebSocket task created: \(String(describing: webSocketTask))")
        log("OGS: 🔧 Task state before resume: \(webSocketTask?.state.rawValue ?? -1)")
        webSocketTask?.resume()
        log("OGS: 🔧 Task state after resume: \(webSocketTask?.state.rawValue ?? -1)")

        // Start receiving immediately (like the working standalone test)
        log("OGS: 🔧 Starting to receive messages...")
        receiveMessage()
    }

    /// Authenticate with OGS using REST API (not WebSocket)
    /// OGS uses cookie-based authentication: login via /api/v0/login, then WebSocket inherits the session
    func authenticate(username: String? = nil, password: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        NSLog("OGS: 🔑 ========== AUTHENTICATE CALLED (REST API) ==========")

        let user = username ?? self.username
        let pass = password ?? getStoredPassword()

        NSLog("OGS: 🔑 Username: \(user ?? "nil")")
        NSLog("OGS: 🔑 Password length: \(pass?.count ?? 0)")

        guard let user = user, let pass = pass else {
            NSLog("OGS: ❌ No credentials available")
            completion(false, "No credentials available")
            return
        }

        // Step 1: Get CSRF token by making a dummy POST to login endpoint
        // OGS sets the csrftoken cookie in the response when we attempt to POST to /api/v0/login
        NSLog("OGS: 🔑 Step 1: Getting CSRF token from login endpoint")
        guard let loginURL = URL(string: "https://online-go.com/api/v0/login") else {
            completion(false, "Invalid login URL")
            return
        }

        let session = URLSession.shared
        var dummyRequest = URLRequest(url: loginURL)
        dummyRequest.httpMethod = "POST"
        dummyRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Send empty body to trigger CSRF cookie
        let emptyData = try! JSONSerialization.data(withJSONObject: [:])
        dummyRequest.httpBody = emptyData

        let dummyTask = session.dataTask(with: dummyRequest) { data, response, error in
            // We expect this to fail (403), but it should set the csrftoken cookie
            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("OGS: ❌ Invalid response from dummy request")
                DispatchQueue.main.async {
                    completion(false, "Invalid response from login endpoint")
                }
                return
            }

            NSLog("OGS: 📄 Dummy request response status: \(httpResponse.statusCode) (expected 403)")

            // Extract CSRF token from Set-Cookie header
            var csrfToken: String? = nil
            if let headerFields = httpResponse.allHeaderFields as? [String: String],
               let url = response?.url {
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
                for cookie in cookies {
                    NSLog("OGS: 🍪 Cookie: \(cookie.name) = \(cookie.value)")
                    if cookie.name == "csrftoken" {
                        csrfToken = cookie.value
                        NSLog("OGS: 🔑 Found CSRF token: \(cookie.value)")
                    }
                }
            }

            guard let token = csrfToken else {
                NSLog("OGS: ❌ No CSRF token found in response cookies")
                DispatchQueue.main.async {
                    completion(false, "No CSRF token found")
                }
                return
            }

            // Step 2: Login with CSRF token (cookie is already set, just need to send token in header)
            NSLog("OGS: 🔑 Step 2: Logging in with CSRF token")

            var loginRequest = URLRequest(url: loginURL)
            loginRequest.httpMethod = "POST"
            loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            loginRequest.setValue("https://online-go.com", forHTTPHeaderField: "Referer")
            loginRequest.setValue("https://online-go.com", forHTTPHeaderField: "Origin")
            loginRequest.setValue(token, forHTTPHeaderField: "X-CSRFToken")

            let loginData: [String: String] = [
                "username": user.trimmingCharacters(in: .whitespaces),
                "password": pass
            ]

            do {
                loginRequest.httpBody = try JSONSerialization.data(withJSONObject: loginData)
            } catch {
                NSLog("OGS: ❌ Failed to encode login data: \(error)")
                DispatchQueue.main.async {
                    completion(false, "Failed to encode login data")
                }
                return
            }

            NSLog("OGS: 📤 Sending login request with CSRF token")

            let loginTask = session.dataTask(with: loginRequest) { data, response, error in
                if let error = error {
                    NSLog("OGS: ❌ Login request failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false, "Login request failed: \(error.localizedDescription)")
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    NSLog("OGS: ❌ Invalid response type")
                    DispatchQueue.main.async {
                        completion(false, "Invalid response type")
                    }
                    return
                }

                NSLog("OGS: 🔍 Login response status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 200 {
                    NSLog("OGS: ✅ Login successful! Session cookies established.")

                    // Parse response to extract player ID and rank
                    var extractedPlayerID: Int? = nil
                    var extractedRank: Double? = nil
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        NSLog("OGS: 📦 Login response JSON: \(json)")
                        // OGS login response includes player info
                        if let id = json["id"] as? Int {
                            extractedPlayerID = id
                            NSLog("OGS: 🆔 Extracted player ID: \(id)")
                        }
                        // Extract rank (could be "ranking" or "rank" field)
                        if let ranking = json["ranking"] as? Double {
                            extractedRank = ranking
                            NSLog("OGS: 📊 Extracted user rank: \(ranking)")
                        } else if let rank = json["rank"] as? Double {
                            extractedRank = rank
                            NSLog("OGS: 📊 Extracted user rank: \(rank)")
                        } else if let rank = json["rank"] as? Int {
                            extractedRank = Double(rank)
                            NSLog("OGS: 📊 Extracted user rank: \(rank)")
                        }
                    }

                    // Save credentials for future use
                    if username != nil && password != nil {
                        self.saveCredentials(username: user, password: pass)
                    }

                    // After successful login, get JWT token for WebSocket authentication
                    self.fetchJWTToken { jwtSuccess in
                        DispatchQueue.main.async {
                            self.isAuthenticated = true
                            self.username = user
                            // playerID is now set by fetchJWTToken from ui/config - don't overwrite it
                            // Only set from login response if not already set
                            if self.playerID == nil, let extractedID = extractedPlayerID {
                                self.playerID = extractedID
                            }
                            self.userRank = extractedRank

                            // Fetch user rank from ui/config (more reliable than login response)
                            self.fetchUserRank()

                            // If WebSocket is already connected, send authenticate message with new JWT
                            if self.isConnected, let jwt = self.jwtToken {
                                NSLog("OGS: 🔑 Sending WebSocket authenticate with new JWT token")
                                // v3.86: Plain JSON format (NO Socket.io prefix)
                                let authMessage = """
                                ["authenticate",{"jwt":"\(jwt)"}]
                                """
                                let wsMessage = URLSessionWebSocketTask.Message.string(authMessage)
                                self.webSocketTask?.send(wsMessage) { error in
                                    if let error = error {
                                        NSLog("OGS: ❌ Failed to send WebSocket auth: \(error.localizedDescription)")
                                    } else {
                                        NSLog("OGS: ✅ WebSocket authenticate message sent (no reconnect needed)")
                                    }
                                }
                            }

                            completion(true, nil)
                        }
                    }
                } else {
                    var errorMessage = "Login failed with status \(httpResponse.statusCode)"
                    if let data = data, let responseText = String(data: data, encoding: .utf8) {
                        NSLog("OGS: ❌ Login error response: \(responseText)")
                        errorMessage = responseText
                    }
                    DispatchQueue.main.async {
                        completion(false, errorMessage)
                    }
                }
            }

            loginTask.resume()
        }

        dummyTask.resume()
        NSLog("OGS: 🔑 ========== AUTHENTICATE END ==========")
    }

    /// Fetch JWT token for WebSocket authentication
    private func fetchJWTToken(completion: @escaping (Bool) -> Void) {
        NSLog("OGS: 🔑 Fetching JWT token from /api/v1/ui/config")

        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else {
            NSLog("OGS: ❌ Invalid UI config URL")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                NSLog("OGS: ❌ Failed to fetch JWT: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let jwt = json["user_jwt"] as? String else {
                NSLog("OGS: ❌ No JWT token in ui/config response")
                completion(false)
                return
            }

            NSLog("OGS: ✅ Got JWT token: \(jwt.prefix(20))...")
            self?.jwtToken = jwt

            // Also extract user rank and ID from ui/config if available
            NSLog("OGS: 🔍 Checking for user rank and ID in ui/config response...")
            if let user = json["user"] as? [String: Any] {
                NSLog("OGS: 🔍 Found user object, keys: \(user.keys)")

                // Extract user ID
                if let userId = user["id"] as? Int {
                    DispatchQueue.main.async {
                        self?.playerID = userId
                        NSLog("OGS: 🆔 Extracted player ID from ui/config: \(userId)")
                    }
                } else {
                    NSLog("OGS: ⚠️ No id field found in user object")
                }

                // Extract user rank
                if let ranking = user["ranking"] as? Double {
                    // Skip rank -100 (unranked/provisional players)
                    if ranking >= 0 {
                        DispatchQueue.main.async {
                            self?.userRank = ranking
                            NSLog("OGS: 📊 Extracted user rank from ui/config: \(ranking)")
                        }
                    } else {
                        NSLog("OGS: ⚠️ User rank is \(ranking) (provisional/unranked), not filtering by rank")
                    }
                } else if let ranking = user["ranking"] as? Int {
                    if ranking >= 0 {
                        DispatchQueue.main.async {
                            self?.userRank = Double(ranking)
                            NSLog("OGS: 📊 Extracted user rank from ui/config: \(ranking)")
                        }
                    } else {
                        NSLog("OGS: ⚠️ User rank is \(ranking) (provisional/unranked), not filtering by rank")
                    }
                } else {
                    NSLog("OGS: ⚠️ No ranking field found in user object")
                }
            } else {
                NSLog("OGS: ⚠️ No user object in ui/config response")
            }

            completion(true)
        }.resume()
    }

    /// Disconnect from OGS
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        NSLog("OGS: 🔌 Disconnected from OGS")
    }

    /// Fetch user's rank from the API (called after authentication)
    func fetchUserRank() {
        NSLog("OGS: 📊 Fetching user rank from /api/v1/ui/config...")

        guard let url = URL(string: "https://online-go.com/api/v1/ui/config") else {
            NSLog("OGS: ❌ Invalid UI config URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                NSLog("OGS: ❌ Failed to fetch user rank: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                NSLog("OGS: ❌ Failed to parse ui/config response")
                return
            }

            NSLog("OGS: 🔍 Checking for user rank in ui/config response...")
            if let user = json["user"] as? [String: Any] {
                NSLog("OGS: 🔍 Found user object, keys: \(user.keys)")
                if let ranking = user["ranking"] as? Double {
                    // Skip rank -100 (unranked/provisional players)
                    if ranking >= 0 {
                        DispatchQueue.main.async {
                            self?.userRank = ranking
                            NSLog("OGS: 📊 ✅ Extracted user rank: \(ranking)")
                        }
                    } else {
                        NSLog("OGS: ⚠️ User rank is \(ranking) (provisional/unranked), not filtering by rank")
                    }
                } else if let ranking = user["ranking"] as? Int {
                    if ranking >= 0 {
                        DispatchQueue.main.async {
                            self?.userRank = Double(ranking)
                            NSLog("OGS: 📊 ✅ Extracted user rank: \(ranking)")
                        }
                    } else {
                        NSLog("OGS: ⚠️ User rank is \(ranking) (provisional/unranked), not filtering by rank")
                    }
                } else {
                    NSLog("OGS: ⚠️ No ranking field found in user object")
                }
            } else {
                NSLog("OGS: ⚠️ No user object in ui/config response")
            }
        }.resume()
    }

    // MARK: - Automatch Methods

    /// Start searching for a game via automatch
    /// - Parameter settings: Game settings (board size, time control, rank range, etc.)
    func startAutomatch(settings: GameSettings) {
        NSLog("OGS: 🎯 startAutomatch called - isConnected: \(isConnected), isAuthenticated: \(isAuthenticated)")
        NSLog("OGS: 🎯 WebSocket task state: \(webSocketTask?.state.rawValue ?? -1)")

        guard isConnected else {
            NSLog("OGS: ❌ Cannot start automatch - not connected")
            lastError = "Not connected to OGS"
            return
        }

        guard isAuthenticated else {
            NSLog("OGS: ❌ Cannot start automatch - not authenticated")
            lastError = "Please log in to play games"
            return
        }

        // Generate a UUID for this automatch request
        let uuid = UUID().uuidString
        NSLog("OGS: 🎯 Starting automatch with UUID: \(uuid)")

        // Convert board size to OGS format ("19x19", "13x13", "9x9")
        let sizeString = "\(settings.boardSize)x\(settings.boardSize)"

        // Determine speed based on time settings (computed)
        let speed = settings.gameSpeed

        // Calculate rank differences
        var lowerRankDiff = -36  // Default: allow all lower ranks
        var upperRankDiff = 36   // Default: allow all higher ranks

        if settings.restrictRank, let userRank = self.userRank {
            switch settings.ranksBelow {
            case .any:
                lowerRankDiff = -36
            case .limit(let delta):
                lowerRankDiff = -delta
            }

            switch settings.ranksAbove {
            case .any:
                upperRankDiff = 36
            case .limit(let delta):
                upperRankDiff = delta
            }
        }

        // Build automatch preferences structure
        let preferences: [String: Any] = [
            "uuid": uuid,
            "size_speed_options": [
                [
                    "size": sizeString,
                    "speed": speed,
                    "system": settings.timeControlSystem.apiValue
                ]
            ],
            "lower_rank_diff": lowerRankDiff,
            "upper_rank_diff": upperRankDiff,
            "rules": [
                "condition": "required",
                "value": "japanese"
            ],
            "handicap": [
                "condition": "no-preference",
                "value": "disabled"
            ]
        ]

        // Convert to JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: preferences),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            NSLog("OGS: ❌ Failed to serialize automatch preferences")
            lastError = "Failed to create automatch request"
            return
        }

        // Send automatch/find_match message
        let message = "42[\"automatch/find_match\",\(jsonString)]"
        NSLog("OGS: 🎯 ==================== SENDING AUTOMATCH REQUEST ====================")
        NSLog("OGS: 🎯 Message: \(message)")
        NSLog("OGS: 🎯 Preferences JSON: \(jsonString)")
        NSLog("OGS: 🎯 ==================================================================")

        // Also write to file for debugging
        if let logData = "SENDING AUTOMATCH: \(message)\n".data(using: .utf8) {
            let logPath = NSHomeDirectory() + "/Desktop/automatch_debug.log"
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(logData)
                handle.closeFile()
            } else {
                try? logData.write(to: URL(fileURLWithPath: logPath))
            }
        }

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                NSLog("OGS: ❌ Error sending automatch request: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                    self?.isSearchingForMatch = false
                }
            } else {
                NSLog("OGS: ✅ Automatch request sent successfully")
                DispatchQueue.main.async {
                    self?.activeAutomatchUUID = uuid
                    self?.isSearchingForMatch = true
                }
            }
        }
    }

    /// Cancel an active automatch request
    /// - Parameter uuid: The UUID of the automatch request to cancel (uses active UUID if not specified)
    func cancelAutomatch(uuid: String? = nil) {
        let uuidToCancel = uuid ?? activeAutomatchUUID

        guard let uuidToCancel = uuidToCancel else {
            NSLog("OGS: ⚠️ No active automatch to cancel")
            return
        }

        NSLog("OGS: 🛑 Canceling automatch with UUID: \(uuidToCancel)")

        // Build cancel message
        let cancelData: [String: Any] = ["uuid": uuidToCancel]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: cancelData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            NSLog("OGS: ❌ Failed to serialize cancel request")
            return
        }

        let message = "42[\"automatch/cancel\",\(jsonString)]"
        NSLog("OGS: 🛑 Sending cancel request: \(message)")

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                NSLog("OGS: ❌ Error sending cancel request: \(error.localizedDescription)")
            } else {
                NSLog("OGS: ✅ Cancel request sent successfully")
                DispatchQueue.main.async {
                    self?.activeAutomatchUUID = nil
                    self?.isSearchingForMatch = false
                }
            }
        }
    }

    // MARK: - Challenge Methods

    /// Send a direct challenge to a specific player
    /// - Parameters:
    ///   - username: The OGS username to challenge
    ///   - settings: Game settings (board size, time control, etc.)
    func sendChallenge(to username: String, settings: GameSettings) {
        let logPath = NSHomeDirectory() + "/Desktop/challenge_debug.log"
        let logMsg = "[\(Date())] sendChallenge called for username: \(username)\n"
        try? logMsg.data(using: .utf8)?.write(to: URL(fileURLWithPath: logPath), options: .atomic)

        NSLog("OGS: ⚔️ Sending challenge to \(username)")

        guard isAuthenticated else {
            let errMsg = "[\(Date())] ERROR: Not authenticated\n"
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(errMsg.data(using: .utf8)!)
                handle.closeFile()
            }
            NSLog("OGS: ❌ Cannot send challenge - not authenticated")
            lastError = "Please log in to send challenges"
            return
        }

        let authMsg = "[\(Date())] Authenticated, sending challenge\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(authMsg.data(using: .utf8)!)
            handle.closeFile()
        }

        DispatchQueue.main.async {
            self.isSendingChallenge = true
        }

        // First, look up the player ID from username
        lookupPlayerID(username: username) { [weak self] playerID in
            guard let self = self, let playerID = playerID else {
                NSLog("OGS: ❌ Could not find player: \(username)")
                DispatchQueue.main.async {
                    self?.lastError = "Player '\(username)' not found"
                    self?.isSendingChallenge = false
                }
                return
            }

            self.sendChallengeToPlayerID(playerID, settings: settings)
        }
    }

    private func lookupPlayerID(username: String, completion: @escaping (Int?) -> Void) {
        let logPath = NSHomeDirectory() + "/Desktop/challenge_debug.log"
        let lookupMsg = "[\(Date())] Looking up player ID for: \(username)\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(lookupMsg.data(using: .utf8)!)
            handle.closeFile()
        }

        let urlString = "https://online-go.com/api/v1/players?username=\(username)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { data, response, error in
            let logPath = NSHomeDirectory() + "/Desktop/challenge_debug.log"

            if let error = error {
                let errMsg = "[\(Date())] Lookup ERROR: \(error.localizedDescription)\n"
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(errMsg.data(using: .utf8)!)
                    handle.closeFile()
                }
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let firstResult = results.first,
                  let id = firstResult["id"] as? Int else {
                let failMsg = "[\(Date())] Failed to parse player ID for \(username)\n"
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(failMsg.data(using: .utf8)!)
                    handle.closeFile()
                }
                NSLog("OGS: ❌ Failed to lookup player ID for \(username)")
                completion(nil)
                return
            }

            let successMsg = "[\(Date())] Found player ID: \(id) for \(username)\n"
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(successMsg.data(using: .utf8)!)
                handle.closeFile()
            }

            NSLog("OGS: ✅ Found player ID \(id) for username \(username)")
            completion(id)
        }.resume()
    }

    private func sendChallengeToPlayerID(_ playerID: Int, settings: GameSettings) {
        let logPath = NSHomeDirectory() + "/Desktop/challenge_debug.log"
        let startMsg = "[\(Date())] Sending challenge to player ID: \(playerID)\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(startMsg.data(using: .utf8)!)
            handle.closeFile()
        }

        // OGS uses cookie-based authentication - session cookies are automatically sent by URLSession
        // Also need CSRF protection headers
        // CRITICAL: Use player-specific endpoint for direct challenges (matches OGS web interface)
        let url = URL(string: "https://online-go.com/api/v1/players/\(playerID)/challenge")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://online-go.com", forHTTPHeaderField: "Referer")
        request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")

        // Get CSRF token from cookies
        if let cookies = HTTPCookieStorage.shared.cookies(for: url),
           let csrfCookie = cookies.first(where: { $0.name == "csrftoken" }) {
            request.setValue(csrfCookie.value, forHTTPHeaderField: "X-CSRFToken")
            NSLog("OGS: ✅ Added CSRF token to challenge request: \(csrfCookie.value)")
        } else {
            NSLog("OGS: ⚠️ No CSRF token found in cookies")
        }

        // Build time control parameters (different for Fischer vs others)
        var timeControlParams: [String: Any] = [
            "time_control": settings.timeControlSystem.apiValue,
            "system": settings.timeControlSystem.apiValue,
            "main_time": settings.mainTimeMinutes * 60  // Convert to seconds
        ]

        // Add system-specific parameters
        switch settings.timeControlSystem {
        case .fischer:
            timeControlParams["time_increment"] = settings.fischerIncrementSeconds
            timeControlParams["max_time"] = settings.fischerMaxTimeMinutes * 60  // Convert to seconds
        case .byoyomi, .canadian, .simple:
            timeControlParams["period_time"] = settings.periodTimeSeconds
            timeControlParams["periods"] = settings.periods
        case .absolute, .none:
            // No additional parameters needed
            break
        }

        // Build challenge request body
        // NOTE: Player ID is in the URL (/players/{id}/challenge), NOT in the body
        let challengeData: [String: Any] = [
            "challenger_color": settings.colorPreference.apiValue,
            "game": [
                "width": settings.boardSize,
                "height": settings.boardSize,
                "ranked": settings.ranked,
                "handicap": settings.handicap.apiValue,
                "komi_auto": settings.komi == .automatic ? "automatic" : "custom",
                "disable_analysis": settings.disableAnalysis,
                "rules": settings.rules.apiValue,
                "time_control": settings.timeControlSystem.apiValue,
                "time_control_parameters": timeControlParams
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: challengeData) else {
            NSLog("OGS: ❌ Failed to serialize challenge data")
            DispatchQueue.main.async {
                self.lastError = "Failed to create challenge"
                self.isSendingChallenge = false
            }
            return
        }

        request.httpBody = jsonData

        // Log all headers and body to debug file
        let headersMsg = "[\(Date())] Request headers: \(request.allHTTPHeaderFields ?? [:])\n"
        let bodyMsg = "[\(Date())] Request body: \(String(data: jsonData, encoding: .utf8) ?? "nil")\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(headersMsg.data(using: .utf8)!)
            handle.write(bodyMsg.data(using: .utf8)!)
            handle.closeFile()
        }

        NSLog("OGS: ⚔️ Sending challenge request: \(String(data: jsonData, encoding: .utf8) ?? "")")
        NSLog("OGS: 📋 Request headers: \(request.allHTTPHeaderFields ?? [:])")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let logPath = NSHomeDirectory() + "/Desktop/challenge_debug.log"

            DispatchQueue.main.async {
                self?.isSendingChallenge = false
            }

            if let error = error {
                let errMsg = "[\(Date())] HTTP ERROR: \(error.localizedDescription)\n"
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(errMsg.data(using: .utf8)!)
                    handle.closeFile()
                }
                NSLog("OGS: ❌ Challenge request failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.lastError = "Challenge failed: \(error.localizedDescription)"
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                let statusMsg = "[\(Date())] HTTP Status: \(httpResponse.statusCode)\n"
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(statusMsg.data(using: .utf8)!)
                    handle.closeFile()
                }

                NSLog("OGS: ⚔️ Challenge response status: \(httpResponse.statusCode)")

                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    let respMsg = "[\(Date())] Response: \(responseString)\n"
                    if let handle = FileHandle(forWritingAtPath: logPath) {
                        handle.seekToEndOfFile()
                        handle.write(respMsg.data(using: .utf8)!)
                        handle.closeFile()
                    }
                    NSLog("OGS: ⚔️ Challenge response: \(responseString)")
                }

                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    let successMsg = "[\(Date())] SUCCESS! Challenge sent.\n"
                    if let handle = FileHandle(forWritingAtPath: logPath) {
                        handle.seekToEndOfFile()
                        handle.write(successMsg.data(using: .utf8)!)
                        handle.closeFile()
                    }
                    NSLog("OGS: ✅ Challenge sent successfully!")

                    // v3.116: Extract game_id and challenge_id from response and start keepalives
                    // This ensures activeChallengeID is set so we can detect when the game starts
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let gameID = json["game"] as? Int,
                       let challengeID = json["challenge"] as? Int {
                        NSLog("OGS: 🎮 Challenge created - game_id: \(gameID), challenge_id: \(challengeID)")
                        self?.startChallengeKeepalive(challengeID: challengeID, gameID: gameID)
                    } else {
                        NSLog("OGS: ⚠️ Could not extract challenge/game IDs from response")
                    }

                    DispatchQueue.main.async {
                        self?.lastError = nil
                    }
                } else {
                    let errorMsg = "Challenge failed with status \(httpResponse.statusCode)"
                    let failMsg = "[\(Date())] FAILED: \(errorMsg)\n"
                    if let handle = FileHandle(forWritingAtPath: logPath) {
                        handle.seekToEndOfFile()
                        handle.write(failMsg.data(using: .utf8)!)
                        handle.closeFile()
                    }
                    NSLog("OGS: ❌ \(errorMsg)")
                    DispatchQueue.main.async {
                        self?.lastError = errorMsg
                    }
                }
            }
        }.resume()
    }

    // MARK: - Available Games / Public Challenges

    /// Subscribe to seekgraph to get real-time updates of available challenges
    /// This uses socket.io, not REST API
    /// - Parameter force: If true, resubscribe even if already subscribed (for recovery)
    func subscribeToSeekgraph(force: Bool = false) {
        guard isConnected else {
            NSLog("OGS: ⚠️ Cannot subscribe to seekgraph - not connected")
            return
        }

        // Don't subscribe if already subscribed (unless forcing)
        if isSubscribedToSeekgraph && !force {
            NSLog("OGS: 📊 Already subscribed to seekgraph, skipping")
            return
        }

        if force {
            NSLog("OGS: 📊 Force re-subscribing to seekgraph...")
        } else {
            NSLog("OGS: 📊 Subscribing to seekgraph...")
        }

        // v3.86: Plain JSON format (NO Socket.io prefix)
        let message = """
        ["seek_graph/connect",{"channel":"global"}]
        """

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                NSLog("OGS: ❌ Error subscribing to seekgraph: \(error.localizedDescription)")
            } else {
                NSLog("OGS: ✅ Seekgraph subscription sent")
                self?.isSubscribedToSeekgraph = true
                self?.lastSeekgraphMessageTime = Date()  // Reset timer on (re)subscribe
                self?.startSeekgraphHealthMonitoring()
            }
        }
    }

    /// Start monitoring seekgraph health
    private func startSeekgraphHealthMonitoring() {
        // Cancel any existing timer
        seekgraphHealthTimer?.invalidate()

        // Check health every 30 seconds
        seekgraphHealthTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkSeekgraphHealth()
        }

        NSLog("OGS: 🏥 Seekgraph health monitoring started")
    }

    /// Check if seekgraph is still receiving messages
    private func checkSeekgraphHealth() {
        guard isSubscribedToSeekgraph else { return }

        guard let lastMessageTime = lastSeekgraphMessageTime else {
            NSLog("OGS: ⚠️ Seekgraph health check: No messages received yet")
            return
        }

        let timeSinceLastMessage = Date().timeIntervalSince(lastMessageTime)

        if timeSinceLastMessage > seekgraphStaleTimeout {
            NSLog("OGS: ❌ Seekgraph STALE! No messages for \(Int(timeSinceLastMessage))s (threshold: \(Int(seekgraphStaleTimeout))s)")
            NSLog("OGS: 🔄 Auto-recovering: forcing seekgraph resubscribe...")

            // Mark as not subscribed and force resubscribe
            isSubscribedToSeekgraph = false
            subscribeToSeekgraph(force: true)
        } else {
            NSLog("OGS: ✅ Seekgraph healthy - last message \(Int(timeSinceLastMessage))s ago")
        }
    }

    /// Unsubscribe from seekgraph updates
    func unsubscribeFromSeekgraph() {
        guard isConnected else { return }

        if !isSubscribedToSeekgraph {
            NSLog("OGS: 📊 Not subscribed to seekgraph, nothing to unsubscribe")
            return
        }

        NSLog("OGS: 📊 Unsubscribing from seekgraph...")

        // v3.86: Plain JSON format (NO Socket.io prefix)
        let message = """
        ["seek_graph/disconnect",{"channel":"global"}]
        """

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                NSLog("OGS: ❌ Error unsubscribing from seekgraph: \(error.localizedDescription)")
            } else {
                NSLog("OGS: ✅ Seekgraph unsubscribed")
                self?.isSubscribedToSeekgraph = false
            }
        }
    }

    /// Fetch available games/challenges from OGS
    /// - Parameter completion: Callback with array of challenges or error
    /// NOTE: This is now deprecated in favor of subscribeToSeekgraph() which uses socket.io
    func fetchAvailableGames(completion: @escaping ([OGSChallenge]?, String?) -> Void) {
        NSLog("OGS: 📋 fetchAvailableGames called - using seekgraph subscription instead")

        // Simply subscribe to seekgraph - the data will arrive via socket messages
        subscribeToSeekgraph()

        // Call completion immediately to satisfy the callback
        // Real data will be populated via socket messages
        completion(availableGames, nil)
    }

    /// Post a custom game/challenge to OGS
    /// - Parameters:
    ///   - settings: Game settings configuration
    ///   - completion: Callback with success status and error message if any
    func postCustomGame(settings: GameSettings, completion: @escaping (Bool, String?) -> Void) {
        NSLog("OGS: 🎮 Posting custom game with settings: \(settings)")

        guard isAuthenticated else {
            NSLog("OGS: ❌ Cannot post game - not authenticated")
            completion(false, "Not authenticated")
            return
        }

        // v3.84 FIX: Ensure WebSocket is connected before creating challenge
        // Challenge needs immediate game/connect + keepalive messages, which require active WebSocket
        guard isConnected else {
            NSLog("OGS: ❌ Cannot post game - WebSocket not connected")
            NSLog("OGS: 💡 Please wait for WebSocket to connect before creating challenges")
            completion(false, "WebSocket not connected. Please wait a moment and try again.")
            return
        }

        guard let url = URL(string: "https://online-go.com/api/v1/challenges") else {
            NSLog("OGS: ❌ Invalid challenges URL")
            completion(false, "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add CSRF protection headers
        if let csrfCookie = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "csrftoken" }) {
            request.setValue(csrfCookie.value, forHTTPHeaderField: "X-CSRFToken")
        }
        request.setValue("https://online-go.com/play", forHTTPHeaderField: "Referer")
        request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")
        // Add User-Agent to match browser behavior
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        // CRITICAL FIX: Manually set Cookie header from HTTPCookieStorage
        // URLSession doesn't always automatically include cookies, so we build the header ourselves
        if let cookies = HTTPCookieStorage.shared.cookies?.filter({ $0.domain.contains("online-go.com") }), !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            NSLog("OGS: 🍪 Manually set Cookie header: \(cookieHeader)")
        }

        // DEBUG: Log all cookies and headers being sent
        NSLog("OGS: 🔍 ========== CHALLENGE REQUEST HEADERS DEBUG ==========")
        if let allCookies = HTTPCookieStorage.shared.cookies {
            NSLog("OGS: 🔍 Total cookies in storage: \(allCookies.count)")
            for cookie in allCookies.filter({ $0.domain.contains("online-go.com") }) {
                NSLog("OGS: 🔍 Cookie: \(cookie.name) = \(cookie.value) (domain: \(cookie.domain))")
            }
        }
        NSLog("OGS: 🔍 Request URL: \(request.url?.absoluteString ?? "nil")")
        NSLog("OGS: 🔍 Request Method: \(request.httpMethod ?? "nil")")
        if let headers = request.allHTTPHeaderFields {
            for (key, value) in headers {
                NSLog("OGS: 🔍 Header: \(key) = \(value)")
            }
        }
        NSLog("OGS: 🔍 =================================================")

        // Calculate rank range based on user's rank and restrictions
        var minRank = 0
        var maxRank = 36  // Maximum rank (9d professional)

        if settings.restrictRank, let userRank = self.userRank {
            // Apply rank restrictions based on user's selections
            switch settings.ranksBelow {
            case .any:
                minRank = 0
            case .limit(let delta):
                minRank = max(0, Int(userRank) - delta)
            }

            switch settings.ranksAbove {
            case .any:
                maxRank = 36
            case .limit(let delta):
                maxRank = min(36, Int(userRank) + delta)
            }

            NSLog("OGS: 🎮 Setting rank range: \(minRank) to \(maxRank) (user rank: \(Int(userRank)))")
        } else {
            // No rank restriction - allow all ranks
            NSLog("OGS: 🎮 No rank restrictions - allowing all ranks (0 to 36)")
        }

        // Build time control parameters - MUST be an object with ALL required fields
        // Based on actual working OGS browser requests
        var timeControlParams: [String: Any] = [
            "main_time": settings.mainTimeMinutes * 60,  // Seconds
            "time_control": settings.timeControlSystem.apiValue,  // Duplicate required!
            "system": settings.timeControlSystem.apiValue,  // Also required!
            "pause_on_weekends": false
        ]

        // Add speed classification
        let totalSeconds = settings.mainTimeMinutes * 60
        let speed: String
        if totalSeconds < 10 * 60 {
            speed = "blitz"
        } else if totalSeconds < 20 * 60 {
            speed = "rapid"
        } else if totalSeconds < 24 * 60 * 60 {
            speed = "live"
        } else {
            speed = "correspondence"
        }
        timeControlParams["speed"] = speed

        // Add system-specific parameters
        switch settings.timeControlSystem {
        case .fischer:
            timeControlParams["time_increment"] = settings.fischerIncrementSeconds
            timeControlParams["max_time"] = settings.fischerMaxTimeMinutes * 60
        case .byoyomi, .canadian, .simple:
            timeControlParams["period_time"] = settings.periodTimeSeconds
            timeControlParams["periods"] = settings.periods
            timeControlParams["periods_min"] = 1
            timeControlParams["periods_max"] = 300
        case .absolute, .none:
            // Minimal parameters for absolute/none
            break
        }

        // Build request body matching EXACT OGS browser format
        let body: [String: Any] = [
            // Top-level fields
            "initialized": false,
            "min_ranking": minRank,
            "max_ranking": maxRank,
            "challenger_color": settings.colorPreference.apiValue,
            "rengo_auto_start": 0,

            // Game object
            "game": [
                "name": settings.gameName,
                "rules": settings.rules.apiValue,
                "ranked": settings.ranked,
                "width": settings.boardSize,
                "height": settings.boardSize,
                "handicap": settings.handicap.apiValue,  // -1 for automatic
                "komi_auto": "automatic",  // Always automatic for now
                "disable_analysis": settings.disableAnalysis,
                "initial_state": nil as String?,
                "pause_on_weekends": false,
                "private": settings.inviteOnly,
                "rengo": false,
                "rengo_casual_mode": true,  // Browser uses TRUE for non-rengo games
                "time_control": settings.timeControlSystem.apiValue,
                "time_control_parameters": timeControlParams  // Object, not string!
            ] as [String: Any]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            NSLog("OGS: 🎮 Custom game request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "?")")
        } catch {
            NSLog("OGS: ❌ Failed to encode custom game request: \(error)")
            completion(false, "Failed to encode request")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("OGS: ❌ Custom game request failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("OGS: ❌ Invalid HTTP response")
                completion(false, "Invalid response")
                return
            }

            NSLog("OGS: 🎮 Custom game response status: \(httpResponse.statusCode)")

            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                NSLog("OGS: 🎮 Custom game response (full): \(responseString)")
                // Also write to file for detailed inspection
                let logPath = "/Users/Dave/Desktop/ogs_create_game_response.json"
                try? responseString.write(toFile: logPath, atomically: true, encoding: .utf8)
                NSLog("OGS: 🎮 Response saved to: \(logPath)")
            }

            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                NSLog("OGS: ✅ Custom game posted successfully!")

                // Extract game_id and challenge_id for debugging AND starting keepalives
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let gameID = json["game"] as? Int,
                   let challengeID = json["challenge"] as? Int {
                    NSLog("OGS: 🎮 Challenge created - game_id: \(gameID), challenge_id: \(challengeID)")

                    // v3.84 FIX: Start sending challenge keepalives immediately
                    // Browser clients send game/connect + periodic challenge/keepalive to prevent deletion
                    self.startChallengeKeepalive(challengeID: challengeID, gameID: gameID)
                } else {
                    NSLog("OGS: ⚠️ Could not extract challenge/game IDs from response - keepalives will NOT be sent!")
                }

                completion(true, nil)
            } else {
                let errorMsg = "Failed with status \(httpResponse.statusCode)"
                NSLog("OGS: ❌ \(errorMsg)")
                completion(false, errorMsg)
            }
        }.resume()
    }

    // MARK: - Challenge Keepalive (v3.84)

    /// Start sending periodic keepalive messages for a challenge
    /// Browser clients send game/connect immediately, then challenge/keepalive every ~2 seconds
    private func startChallengeKeepalive(challengeID: Int, gameID: Int) {
        NSLog("OGS: 💓 Starting challenge keepalive for challenge:\(challengeID) game:\(gameID)")

        // Store IDs
        activeChallengeID = challengeID
        activeGameID = gameID

        // Send immediate game/connect message (browser does this right after creating challenge)
        sendGameConnect(gameID: gameID)

        // Stop any existing timer
        challengeKeepaliveTimer?.invalidate()

        // Start timer to send keepalive every 2 seconds
        challengeKeepaliveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sendChallengeKeepalive()
        }

        NSLog("OGS: ✅ Challenge keepalive timer started (every 2 seconds)")
    }

    /// Stop sending challenge keepalive messages
    private func stopChallengeKeepalive() {
        guard activeChallengeID != nil else {
            return  // No active challenge
        }

        NSLog("OGS: 💓 Stopping challenge keepalive for challenge:\(activeChallengeID ?? 0)")

        challengeKeepaliveTimer?.invalidate()
        challengeKeepaliveTimer = nil
        activeChallengeID = nil
        activeGameID = nil

        NSLog("OGS: ✅ Challenge keepalive stopped")
    }

    /// Send game/connect message (browser sends this immediately after challenge creation)
    private func sendGameConnect(gameID: Int) {
        guard isConnected else {
            NSLog("OGS: ⚠️ Cannot send game/connect - not connected")
            return
        }

        // v3.86: Plain JSON format (NO Socket.io prefix)
        let message = """
        ["game/connect",{"game_id":\(gameID)}]
        """

        NSLog("OGS: 📤 Sending game/connect for game:\(gameID)")

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(wsMessage) { error in
            if let error = error {
                NSLog("OGS: ❌ Error sending game/connect: \(error.localizedDescription)")
            } else {
                NSLog("OGS: ✅ game/connect sent successfully")
            }
        }
    }

    /// Send a single challenge/keepalive message
    private func sendChallengeKeepalive() {
        guard let challengeID = activeChallengeID, let gameID = activeGameID else {
            NSLog("OGS: ⚠️ Cannot send keepalive - no active challenge")
            stopChallengeKeepalive()
            return
        }

        guard isConnected else {
            NSLog("OGS: ⚠️ Cannot send keepalive - not connected")
            return
        }

        // v3.86: Plain JSON format (NO Socket.io prefix)
        let message = """
        ["challenge/keepalive",{"challenge_id":\(challengeID),"game_id":\(gameID)}]
        """

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(wsMessage) { error in
            if let error = error {
                NSLog("OGS: ❌ Error sending challenge/keepalive: \(error.localizedDescription)")
            } else {
                // Only log occasionally to avoid spam (every 10th keepalive = every 20 seconds)
                if Int.random(in: 1...10) == 1 {
                    NSLog("OGS: 💓 challenge/keepalive sent for challenge:\(challengeID)")
                }
            }
        }
    }

    /// Cancel a challenge that you created
    /// - Parameters:
    ///   - challengeID: The challenge ID to cancel
    ///   - completion: Callback with success status and error message if any
    func cancelChallenge(challengeID: Int, completion: @escaping (Bool, String?) -> Void) {
        NSLog("OGS: 🗑️ Canceling challenge \(challengeID)")

        guard isAuthenticated else {
            NSLog("OGS: ❌ Cannot cancel challenge - not authenticated")
            completion(false, "Not authenticated")
            return
        }

        guard let url = URL(string: "https://online-go.com/api/v1/challenges/\(challengeID)") else {
            NSLog("OGS: ❌ Invalid challenge URL")
            completion(false, "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        // Add CSRF protection headers
        if let csrfCookie = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "csrftoken" }) {
            request.setValue(csrfCookie.value, forHTTPHeaderField: "X-CSRFToken")
        }
        request.setValue("https://online-go.com", forHTTPHeaderField: "Referer")
        request.setValue("https://online-go.com", forHTTPHeaderField: "Origin")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("OGS: ❌ Cancel challenge request failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("OGS: ❌ Invalid HTTP response")
                completion(false, "Invalid response")
                return
            }

            NSLog("OGS: 🗑️ Cancel challenge response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200 || httpResponse.statusCode == 204 {
                NSLog("OGS: ✅ Challenge canceled successfully!")

                // v3.84: Stop keepalives when challenge is cancelled
                DispatchQueue.main.async {
                    self.stopChallengeKeepalive()
                }

                completion(true, nil)
            } else {
                let errorMsg = "Failed with status \(httpResponse.statusCode)"
                NSLog("OGS: ❌ \(errorMsg)")
                completion(false, errorMsg)
            }
        }.resume()
    }

    // MARK: - Game Play

    /// Send a move to OGS
    /// - Parameters:
    ///   - gameID: The game ID
    ///   - move: The move in SGF coordinates (e.g., "pd" for Q16)
    func sendMove(gameID: Int, move: String) {
        guard isConnected else {
            NSLog("OGS: ❌ Cannot send move - not connected")
            return
        }

        // v3.86: Plain JSON format (NO Socket.io prefix)
        let moveMessage = """
        ["game/move",{"game_id":\(gameID),"move":"\(move)"}]
        """

        let message = URLSessionWebSocketTask.Message.string(moveMessage)
        webSocketTask?.send(message) { error in
            if let error = error {
                NSLog("OGS: ❌ Error sending move: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
            } else {
                NSLog("OGS: ✅ Move sent: \(move)")
            }
        }
    }

    /// Request to undo the last move
    /// - Parameters:
    ///   - gameID: The game ID
    ///   - moveNumber: The current move number (used as validation)
    func requestUndo(gameID: Int, moveNumber: Int) {
        guard isConnected else {
            NSLog("OGS: ❌ Cannot request undo - not connected")
            return
        }

        let undoMessage = """
        ["game/undo/request",{"game_id":\(gameID),"move_number":\(moveNumber)}]
        """

        let message = URLSessionWebSocketTask.Message.string(undoMessage)
        webSocketTask?.send(message) { error in
            if let error = error {
                NSLog("OGS: ❌ Error requesting undo: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
            } else {
                NSLog("OGS: ✅ Undo request sent for game \(gameID) at move \(moveNumber)")
            }
        }
    }

    /// Send a pass move
    /// - Parameter gameID: The game ID
    func sendPass(gameID: Int) {
        guard isConnected else {
            NSLog("OGS: ❌ Cannot send pass - not connected")
            return
        }

        let passMessage = """
        ["game/move",{"game_id":\(gameID),"move":".."}]
        """

        let message = URLSessionWebSocketTask.Message.string(passMessage)
        webSocketTask?.send(message) { error in
            if let error = error {
                NSLog("OGS: ❌ Error sending pass: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
            } else {
                NSLog("OGS: ✅ Pass sent for game \(gameID)")
            }
        }
    }

    /// Resign from the game
    /// - Parameter gameID: The game ID
    func sendResign(gameID: Int) {
        guard isConnected else {
            NSLog("OGS: ❌ Cannot resign - not connected")
            return
        }

        let resignMessage = """
        ["game/resign",{"game_id":\(gameID)}]
        """

        let message = URLSessionWebSocketTask.Message.string(resignMessage)
        webSocketTask?.send(message) { error in
            if let error = error {
                NSLog("OGS: ❌ Error sending resign: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
            } else {
                NSLog("OGS: ✅ Resign sent for game \(gameID)")
            }
        }
    }

    /// Join a game to start receiving updates
    /// - Parameter gameID: The game ID to join
    func joinGame(gameID: Int) {
        NSLog("OGS: 🎮 joinGame() called with gameID: \(gameID)")
        NSLog("OGS: 🎮 isConnected: \(isConnected), isAuthenticated: \(isAuthenticated)")

        currentGameID = gameID

        // Fetch game data via REST API instead of WebSocket
        // This is more reliable and doesn't require special WebSocket subscriptions
        fetchGameData(gameID: gameID)
    }

    /// Fetch game data from OGS REST API
    private func fetchGameData(gameID: Int) {
        NSLog("OGS: 📡 Fetching game data via REST API for game \(gameID)")

        guard let url = URL(string: "https://online-go.com/api/v1/games/\(gameID)") else {
            NSLog("OGS: ❌ Invalid game URL")
            return
        }

        let session = URLSession.shared
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("OGS: ❌ Game data fetch failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.lastError = "Failed to load game: \(error.localizedDescription)"
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("OGS: ❌ Invalid response type")
                return
            }

            NSLog("OGS: 📡 Game data response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200, let data = data {
                do {
                    if let restResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        NSLog("OGS: ✅ Game data fetched successfully from REST API")

                        // REST API returns gamedata in a nested structure
                        // Extract the gamedata object which contains moves, game_id, etc.
                        if var gamedata = restResponse["gamedata"] as? [String: Any] {
                            NSLog("OGS: 📦 Extracted gamedata subdictionary")

                            // IMPORTANT: Extract ui_class from top-level players (not gamedata.players)
                            // gamedata.players doesn't include ui_class, but top-level players does
                            if let topLevelPlayers = restResponse["players"] as? [String: Any],
                               var gamedataPlayers = gamedata["players"] as? [String: Any] {

                                // Inject ui_class into gamedata.players.black
                                if let topBlack = topLevelPlayers["black"] as? [String: Any],
                                   var gamedataBlack = gamedataPlayers["black"] as? [String: Any] {
                                    if let uiClass = topBlack["ui_class"] as? String {
                                        gamedataBlack["ui_class"] = uiClass
                                        gamedataPlayers["black"] = gamedataBlack
                                        NSLog("OGS: 📦 Injected black ui_class: \(uiClass)")
                                    }
                                }

                                // Inject ui_class into gamedata.players.white
                                if let topWhite = topLevelPlayers["white"] as? [String: Any],
                                   var gamedataWhite = gamedataPlayers["white"] as? [String: Any] {
                                    if let uiClass = topWhite["ui_class"] as? String {
                                        gamedataWhite["ui_class"] = uiClass
                                        gamedataPlayers["white"] = gamedataWhite
                                        NSLog("OGS: 📦 Injected white ui_class: \(uiClass)")
                                    }
                                }

                                // Update gamedata with enriched players info
                                gamedata["players"] = gamedataPlayers
                            }

                            // Process the gamedata (which has the same structure as WebSocket game data)
                            DispatchQueue.main.async {
                                self.handleGameData(gamedata)

                                // Subscribe to WebSocket updates for this game
                                NSLog("OGS: 🔍 Checking if we should subscribe: isConnected=\(self.isConnected)")
                                if self.isConnected {
                                    NSLog("OGS: ✅ isConnected=true, calling subscribeToGame()")
                                    self.subscribeToGame(gameID: gameID)
                                } else {
                                    NSLog("OGS: ⚠️ isConnected=false, NOT subscribing to game yet")
                                    NSLog("OGS: ⚠️ You need to connect to OGS WebSocket first via settings")
                                }
                            }
                        } else {
                            NSLog("OGS: ❌ No gamedata field in REST response")
                            DispatchQueue.main.async {
                                self.lastError = "Invalid game data structure"
                            }
                        }
                    }
                } catch {
                    NSLog("OGS: ❌ Failed to parse game data: \(error)")
                    DispatchQueue.main.async {
                        self.lastError = "Failed to parse game data"
                    }
                }
            } else if httpResponse.statusCode == 429 {
                // Rate limited / throttled
                NSLog("OGS: ⚠️ API rate limit hit (429) - need to slow down polling")
                DispatchQueue.main.async {
                    self.lastError = "Rate limited - slowing down polling"
                    // Post notification to tell ContentView3D to back off
                    NotificationCenter.default.post(name: NSNotification.Name("OGSRateLimited"), object: nil)
                }
            } else {
                var errorMessage = "Game not found (status \(httpResponse.statusCode))"
                if let data = data, let responseText = String(data: data, encoding: .utf8) {
                    NSLog("OGS: ❌ Error response: \(responseText)")
                    // Check if error message contains "throttled"
                    if responseText.lowercased().contains("throttled") {
                        NSLog("OGS: ⚠️ Throttled error detected in response")
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: NSNotification.Name("OGSRateLimited"), object: nil)
                        }
                    }
                    errorMessage = responseText
                }
                DispatchQueue.main.async {
                    self.lastError = errorMessage
                }
            }
        }

        task.resume()
    }

    /// Subscribe to WebSocket updates for a game
    private func subscribeToGame(gameID: Int) {
        NSLog("OGS: 📡 Subscribing to WebSocket updates for game \(gameID)")

        // v3.86: Plain JSON format (NO Socket.io prefix)
        // Build game/connect message with player_id if available
        // player_id is required to receive clock events and other game updates
        let connectMessage: String
        if let playerID = playerID {
            NSLog("OGS: 🆔 Using player_id \(playerID) for subscription")
            connectMessage = """
            ["game/connect",{"game_id":\(gameID),"player_id":\(playerID),"chat":true}]
            """
        } else {
            NSLog("OGS: ⚠️ No player_id available - subscribing as spectator (may not receive all events)")
            connectMessage = """
            ["game/connect",{"game_id":\(gameID),"chat":false}]
            """
        }

        let message1 = URLSessionWebSocketTask.Message.string(connectMessage)
        webSocketTask?.send(message1) { error in
            if let error = error {
                NSLog("OGS: ❌ Error subscribing to game: \(error.localizedDescription)")
            } else {
                NSLog("OGS: ✅ Sent game/connect subscription for game \(gameID)")
            }
        }

        // v3.86: Plain JSON format (NO Socket.io prefix)
        // Format 2: Spectate the game (backup subscription)
        let spectateMessage = """
        ["spectate",{"game_id":\(gameID)}]
        """

        let message2 = URLSessionWebSocketTask.Message.string(spectateMessage)
        webSocketTask?.send(message2) { error in
            if let error = error {
                NSLog("OGS: ❌ Error sending spectate: \(error.localizedDescription)")
            } else {
                NSLog("OGS: ✅ Sent spectate request for game \(gameID)")
            }
        }
    }

    /// Convert board position to SGF move notation
    /// - Parameters:
    ///   - x: Column (0-18 for 19x19 board)
    ///   - y: Row (0-18 for 19x19 board)
    /// - Returns: SGF move string (e.g., "pd" for Q16)
    static func positionToSGF(x: Int, y: Int) -> String {
        let letters = "abcdefghijklmnopqrs"
        guard x >= 0 && x < letters.count && y >= 0 && y < letters.count else {
            return ""
        }
        let xChar = letters[letters.index(letters.startIndex, offsetBy: x)]
        let yChar = letters[letters.index(letters.startIndex, offsetBy: y)]
        return "\(xChar)\(yChar)"
    }

    /// Convert SGF move notation to board position
    /// - Parameter move: SGF move string (e.g., "pd")
    /// - Returns: Tuple of (x, y) coordinates or nil if invalid
    static func sgfToPosition(move: String) -> (x: Int, y: Int)? {
        let letters = "abcdefghijklmnopqrs"
        guard move.count == 2 else { return nil }

        let chars = Array(move)
        guard let xIndex = letters.firstIndex(of: chars[0]),
              let yIndex = letters.firstIndex(of: chars[1]) else {
            return nil
        }

        return (x: letters.distance(from: letters.startIndex, to: xIndex),
                y: letters.distance(from: letters.startIndex, to: yIndex))
    }

    private func receiveMessage() {
        if verboseLogging {
            NSLog("OGS: 🔄 receiveMessage() called - task state: \(webSocketTask?.state.rawValue ?? -1)")
        }
        webSocketTask?.receive { [weak self] result in
            guard let self = self else {
                NSLog("OGS: ⚠️ receiveMessage: self is nil")
                return
            }

            switch result {
            case .success(let message):
                if self.verboseLogging {
                    NSLog("OGS: ✅ Received message successfully")
                }
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }

                // Continue receiving messages
                if verboseLogging {
                    NSLog("OGS: 🔄 Calling receiveMessage() again to continue loop")
                }
                self.receiveMessage()

            case .failure(let error):
                NSLog("OGS: ❌ WebSocket receive error: \(error.localizedDescription)")
                NSLog("OGS: ❌ Error code: \(error)")

                // Check if socket is disconnected (task state 3 = .completed/disconnected)
                let taskState = self.webSocketTask?.state.rawValue ?? -1
                NSLog("OGS: 🔍 WebSocket task state after error: \(taskState)")

                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.isConnected = false
                }

                // If socket is disconnected, attempt full reconnection instead of just restarting receive loop
                if taskState == 3 || error.localizedDescription.contains("not connected") {
                    self.reconnectAttempts += 1
                    if self.reconnectAttempts <= self.maxReconnectAttempts {
                        let delay = min(Double(self.reconnectAttempts) * 2.0, 10.0) // Exponential backoff, max 10s
                        NSLog("OGS: 🔄 WebSocket disconnected. Attempting reconnection #\(self.reconnectAttempts) in \(delay)s...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            NSLog("OGS: 🔌 Reconnecting to WebSocket...")
                            self.connect()
                        }
                    } else {
                        NSLog("OGS: ❌ Max reconnection attempts (\(self.maxReconnectAttempts)) reached. Giving up.")
                        DispatchQueue.main.async {
                            self.lastError = "Connection lost after \(self.maxReconnectAttempts) reconnection attempts"
                        }
                    }
                } else {
                    // For other errors, try to continue receiving
                    NSLog("OGS: 🔄 Attempting to restart receive loop after error")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.receiveMessage()
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: String) {
        // Only log to console if verbose logging is enabled
        // (Still write to debug log file regardless)
        if verboseLogging {
            NSLog("OGS: 📨 Received: \(message)")
        }

        // Write to debug log file
        let logMessage = "[\(Date())] OGS: Received: \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            let logPath = NSHomeDirectory() + "/Desktop/sgfplayer_ogs_debug.log"
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }

        // v3.86: Plain WebSocket JSON format (NOT Socket.io)
        // Messages are plain JSON arrays: ["event_name", data]
        // No Socket.io protocol prefixes (0, 40, 42, etc.)

        // On first message, set connected and authenticate
        if !isConnected {
            log("OGS: ✅ Plain WebSocket connected - ready for authentication")
            NSLog("OGS: ✅ Plain WebSocket connected - ready for authentication")

            // Set connected flag on main queue
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = true
                // Reset reconnection counter on successful connection
                self?.reconnectAttempts = 0
                NSLog("OGS: ✅ Successfully connected to WebSocket (reconnect counter reset)")
                // Notify that OGS is now connected
                NotificationCenter.default.post(name: NSNotification.Name("OGSConnected"), object: nil)
            }

            // Send WebSocket authenticate message with JWT token (PLAIN JSON format)
            if let jwt = self.jwtToken {
                NSLog("OGS: 🔑 Sending WebSocket authenticate with JWT")
                let authMessage = """
                ["authenticate",{"jwt":"\(jwt)"}]
                """
                let wsMessage = URLSessionWebSocketTask.Message.string(authMessage)
                self.webSocketTask?.send(wsMessage) { error in
                    if let error = error {
                        NSLog("OGS: ❌ Failed to send WebSocket auth: \(error.localizedDescription)")
                    } else {
                        NSLog("OGS: ✅ WebSocket authenticate message sent")
                        self.wsAuthPending = true
                    }
                }
            } else {
                NSLog("OGS: ⚠️ No JWT token available for WebSocket auth")
            }

            // Credentials should already be loaded from init()
            NSLog("OGS: 🔧 Username from init: \(String(describing: self.username))")
            log("OGS: 🔧 Username from init: \(String(describing: self.username))")

            // Try to auto-authenticate if we have stored credentials
            // Note: username was loaded in init(), so we can check it here
            if let username = self.username {
                NSLog("OGS: 🔑 Auto-authenticating with stored credentials for user: \(username)")
                log("OGS: 🔑 Auto-authenticating with stored credentials for user: \(username)")

                // Need to wait a moment for isConnected to be set
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.authenticate { success, error in
                        if !success {
                            NSLog("OGS: ⚠️ Auto-authentication failed: \(error ?? "unknown") - staying connected anyway")
                            // Don't post OGSAuthFailed - just log it
                            // User can manually login if needed
                        } else {
                            NSLog("OGS: ✅ Auto-authentication successful")
                        }
                    }
                }
            } else {
                NSLog("OGS: ℹ️ No stored credentials - connected as guest. Can spectate games.")
                log("OGS: ℹ️ No stored credentials - connected as guest. Can spectate games.")
            }
        }

        // Parse all messages as plain JSON event arrays
        parseEventMessage(message)
    }

    private func parseEventMessage(_ message: String) {
        // v3.86: Parse plain JSON array (NO Socket.io prefix to strip)
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 2,
              let eventName = json[0] as? String else {
            NSLog("OGS: ⚠️ Could not parse event message: \(message)")
            return
        }

        // DEBUGGING: Log ALL events to catch authentication response
        // Temporarily always log to debug undo issues
        NSLog("OGS: 📨 EVENT RECEIVED: \(eventName)")
        if verboseLogging {
            NSLog("OGS: 📨 Full event data: \(json[1])")
        }

        // Also write to file for debugging
        if let logData = "RECEIVED EVENT: \(eventName)\n".data(using: .utf8) {
            let logPath = NSHomeDirectory() + "/Desktop/automatch_debug.log"
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(logData)
                handle.closeFile()
            }
        }

        // Suppress logging for noisy broadcast messages
        let suppressedEvents = ["active-bots", "active-players", "incident-report", "notification"]
        if verboseLogging && !suppressedEvents.contains(eventName) {
            NSLog("OGS: 📨 Event data: \(json[1])")
        }

        // Handle events - OGS uses game-specific event names like "game/12345/move"
        switch eventName {
        case "authenticate":
            NSLog("OGS: 🔑 ========== AUTHENTICATE EVENT MATCHED! ==========")
            if let authData = json[1] as? [String: Any] {
                NSLog("OGS: 🔑 Calling handleAuthentication with data: \(authData)")
                handleAuthentication(authData)
            } else {
                NSLog("OGS: ❌ Could not cast json[1] to [String: Any] for authenticate event")
            }
        case "auth", "authentication", "login":
            NSLog("OGS: 🔑 ========== ALT AUTH EVENT: \(eventName) ==========")
            if let authData = json[1] as? [String: Any] {
                handleAuthentication(authData)
            }
        case _ where eventName.contains("/move"):
            if let moveData = json[1] as? [String: Any] {
                handleMove(moveData)
            }
        case _ where eventName.contains("/gamedata"):
            if let gameData = json[1] as? [String: Any] {
                handleGameData(gameData)
            }
        case _ where eventName.contains("/clock"):
            NSLog("OGS: ⏰ ========== CLOCK EVENT MATCHED! ==========")
            NSLog("OGS: ⏰ Event name: \(eventName)")
            NSLog("OGS: ⏰ Full message: \(message)")
            if let clockData = json[1] as? [String: Any] {
                NSLog("OGS: ⏰ Successfully cast clockData dictionary, calling handleClock()")
                NSLog("OGS: ⏰ Clock data keys: \(clockData.keys.sorted())")
                handleClock(clockData)
            } else {
                NSLog("OGS: ❌ Failed to cast json[1] to [String: Any]. json[1] type: \(type(of: json[1]))")
            }
        case _ where eventName.contains("/undo"):
            NSLog("OGS: ↩️ ========== UNDO EVENT MATCHED! ==========")
            NSLog("OGS: ↩️ Event name: \(eventName)")
            NSLog("OGS: ↩️ Full message: \(message)")
            if let undoData = json[1] as? [String: Any] {
                NSLog("OGS: ↩️ Undo data: \(undoData)")
                handleUndo(eventName: eventName, data: undoData)
            } else {
                NSLog("OGS: ❌ Failed to cast undo data. json[1] type: \(type(of: json[1]))")
            }
        case "game/undo/request", "game/undo/requested":
            NSLog("OGS: ↩️ ========== UNDO REQUEST EVENT ==========")
            NSLog("OGS: ↩️ Full message: \(message)")
            if let undoData = json[1] as? [String: Any] {
                handleUndoRequest(eventName: eventName, data: undoData)
            }
        case "game/undo/accept", "game/undo/accepted":
            NSLog("OGS: ✅ ========== UNDO ACCEPTED ==========")
            if let undoData = json[1] as? [String: Any] {
                handleUndoAccepted(undoData)
            }
        case "game/undo/reject", "game/undo/rejected":
            NSLog("OGS: ❌ ========== UNDO REJECTED ==========")
            if let undoData = json[1] as? [String: Any] {
                handleUndoRejected(undoData)
            }
        case "automatch/entry":
            NSLog("OGS: 🎯 ========== AUTOMATCH ENTRY ==========")
            if let preferencesData = json[1] as? [String: Any] {
                handleAutomatchEntry(preferencesData)
            }
        case "automatch/start":
            NSLog("OGS: 🎯 ========== AUTOMATCH START - GAME FOUND! ==========")
            if let startData = json[1] as? [String: Any] {
                handleAutomatchStart(startData)
            }
        case "automatch/cancel":
            NSLog("OGS: 🎯 ========== AUTOMATCH CANCELED ==========")
            if let cancelData = json[1] as? [String: Any] {
                handleAutomatchCancel(cancelData)
            }
        case "seekgraph/global":
            NSLog("OGS: 📊 ========== SEEKGRAPH UPDATE ==========")
            if let seekgraphData = json[1] as? [[String: Any]] {
                NSLog("OGS: 📊 Received seekgraph with \(seekgraphData.count) items")
                handleSeekgraph(seekgraphData)
            } else {
                NSLog("OGS: ⚠️ Seekgraph data in unexpected format: \(type(of: json[1]))")
            }
        case "active-bots", "active-players", "incident-report", "notification":
            // Suppress these broadcast messages - they're noisy
            break
        case _ where eventName.contains("/latency"):
            // Suppress latency pings
            break
        default:
            // Temporarily always log unhandled events to debug undo
            if !["active-bots", "active-players", "incident-report", "notification"].contains(eventName) &&
               !eventName.contains("/latency") {
                NSLog("OGS: 📨 Unhandled event: \(eventName) - First 200 chars: \(message.prefix(200))")
            }
        }
    }

    private func handleAuthentication(_ authData: [String: Any]) {
        NSLog("OGS: 🔑 WebSocket authentication response: \(authData)")

        // Cancel the timeout timer
        authTimeoutTimer?.invalidate()
        authTimeoutTimer = nil

        // JWT auth response format: {"id": number, "username": string}
        if let userId = authData["id"] as? Int, let username = authData["username"] as? String {
            NSLog("OGS: ✅ WebSocket authentication successful - user: \(username) (id: \(userId))")
            DispatchQueue.main.async {
                self.wsAuthPending = false
                // Note: isAuthenticated is already set from REST login
                // This just confirms WebSocket is also authenticated
            }
        } else if let success = authData["success"] as? Bool, success {
            NSLog("OGS: ✅ Authentication successful")
            DispatchQueue.main.async {
                self.isAuthenticated = true
                self.wsAuthPending = false
                self.authCompletionHandler?(true, nil)
                self.authCompletionHandler = nil

                // Fetch user rank
                self.fetchUserRank()
            }
        } else if let error = authData["error"] as? String {
            NSLog("OGS: ❌ WebSocket authentication failed: \(error)")
            DispatchQueue.main.async {
                self.isAuthenticated = false
                self.wsAuthPending = false
                self.lastError = error
                self.authCompletionHandler?(false, error)
                self.authCompletionHandler = nil
            }
        } else {
            // Unknown response format or auth failed
            NSLog("OGS: ⚠️ WebSocket auth response format: \(authData)")
            DispatchQueue.main.async {
                self.wsAuthPending = false
                self.authCompletionHandler?(false, "Unknown response format")
                self.authCompletionHandler = nil
            }
        }
    }

    private func handleMove(_ moveData: [String: Any]) {
        // OGS move format: {"game_id": 123, "move_number": 45, "move": [x, y, time]}
        guard let moveArray = moveData["move"] as? [Any],
              moveArray.count >= 2 else {
            NSLog("OGS: ⚠️ Move data has invalid format: \(moveData)")
            return
        }

        // Extract x, y coordinates (OGS uses 0-indexed coordinates)
        // Passes are represented as (-1, -1) or coordinates outside the board
        guard let x = moveArray[0] as? Int,
              let y = moveArray[1] as? Int else {
            NSLog("OGS: ⚠️ Could not parse move coordinates from: \(moveArray)")
            return
        }

        let moveNumber = moveData["move_number"] as? Int ?? -1
        let isPass = (x < 0 || y < 0)  // Pass is represented by negative coordinates

        // CRITICAL: Extract time remaining from move data and sync clock
        // The move array contains [x, y, time] where time is the player's remaining time IN MILLISECONDS
        if moveArray.count >= 3 {
            if let timeRemainingMs = moveArray[2] as? Double {
                // Convert milliseconds to seconds
                let timeRemaining = timeRemainingMs / 1000.0
                NSLog("OGS: ⏱️ Move includes time: \(timeRemainingMs)ms = \(timeRemaining)s")

                // The time is for the player who JUST moved (whose clock was running)
                // currentPlayerColor is who moves NEXT, so the move was made by the OPPOSITE color
                let playerWhoMoved: Stone = (self.currentPlayerColor == .black) ? .white : .black

                // Update that player's time immediately
                DispatchQueue.main.async {
                    if playerWhoMoved == .black {
                        self.blackTimeRemaining = timeRemaining
                        NSLog("OGS: ⏱️ Synced Black time from move: \(timeRemaining)s")
                    } else {
                        self.whiteTimeRemaining = timeRemaining
                        NSLog("OGS: ⏱️ Synced White time from move: \(timeRemaining)s")
                    }
                }
            } else if let timeRemainingMs = moveArray[2] as? Int {
                // Sometimes time comes as Int instead of Double
                // Convert milliseconds to seconds
                let timeRemaining = Double(timeRemainingMs) / 1000.0
                NSLog("OGS: ⏱️ Move includes time (as Int): \(timeRemainingMs)ms = \(timeRemaining)s")

                let playerWhoMoved: Stone = (self.currentPlayerColor == .black) ? .white : .black

                DispatchQueue.main.async {
                    if playerWhoMoved == .black {
                        self.blackTimeRemaining = timeRemaining
                        NSLog("OGS: ⏱️ Synced Black time from move: \(timeRemaining)s")
                    } else {
                        self.whiteTimeRemaining = timeRemaining
                        NSLog("OGS: ⏱️ Synced White time from move: \(timeRemaining)s")
                    }
                }
            } else {
                NSLog("OGS: ⚠️ Move array[2] is not a number: \(type(of: moveArray[2]))")
            }
        } else {
            NSLog("OGS: ⚠️ Move array too short for time: count=\(moveArray.count)")
        }

        if isPass {
            NSLog("OGS: 🎯 Move #\(moveNumber) - PASS")
        } else {
            NSLog("OGS: 🎯 Move #\(moveNumber) received: (\(x), \(y))")
        }

        // IMPORTANT: currentPlayerColor represents whose turn it is to play NEXT
        // So the move that was just played is by the OPPOSITE color
        // If currentPlayerColor is Black, that means White just played
        let moveColor: Stone = (self.currentPlayerColor == .black) ? .white : .black
        NSLog("OGS: 🎨 Move was played by: \(moveColor == .black ? "Black" : "White") (next player: \(self.currentPlayerColor == .black ? "Black" : "White"))")

        // Toggle current player AFTER the move (for next turn)
        // This applies to both regular moves AND passes
        DispatchQueue.main.async {
            self.currentPlayerColor = (self.currentPlayerColor == .black) ? .white : .black
            NSLog("OGS: 🎨 After toggle, next player to move: \(self.currentPlayerColor == .black ? "Black" : "White")")
        }

        // Post notification for ContentView3D to handle
        // Include the color of the stone that was just played
        // For passes, x and y will be negative, which ContentView3D should handle
        NotificationCenter.default.post(
            name: NSNotification.Name("OGSMoveReceived"),
            object: nil,
            userInfo: [
                "x": x,
                "y": y,
                "moveNumber": moveNumber,
                "color": moveColor == .black ? "black" : "white",
                "isPass": isPass
            ]
        )
    }

    private func handleGameData(_ gameData: [String: Any]) {
        NSLog("OGS: 🎮 Game data received")
        NSLog("OGS: 🎮 handleGameData() - Thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")

        // Log the entire game data for debugging
        if let jsonData = try? JSONSerialization.data(withJSONObject: gameData, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            NSLog("OGS: 🎮 Full game data:\n\(jsonString)")
        }

        // Parse initial game state
        if let gameID = gameData["game_id"] as? Int {
            DispatchQueue.main.async {
                self.currentGameID = gameID
            }
            NSLog("OGS: 🎮 Game ID: \(gameID)")
        }

        // Extract clock information if available
        if let clock = gameData["clock"] as? [String: Any] {
            extractClockData(clock)
        }

        // Update game phase based on OGS phase field
        if let phase = gameData["phase"] as? String {
            NSLog("OGS: 🎮 Game phase from OGS: \(phase)")
            DispatchQueue.main.async {
                switch phase {
                case "play":
                    self.gamePhase = .playing
                    NSLog("OGS: 🎮 Updated gamePhase to .playing")
                case "stone removal", "finished":
                    self.gamePhase = .scoring
                    NSLog("OGS: 🎮 Updated gamePhase to .scoring")
                default:
                    NSLog("OGS: ⚠️ Unknown phase '\(phase)' - keeping current gamePhase")
                }
            }

            // If game is finished, extract the result data
            if phase == "finished" {
                NSLog("OGS: 🏁 ========== GAME FINISHED - EXTRACTING RESULT DATA ==========")
                NSLog("OGS: 🏁 All gameData keys: \(gameData.keys.sorted())")

                // Log potential scoring fields to discover the exact structure
                if let outcome = gameData["outcome"] {
                    NSLog("OGS: 🏁 outcome field: \(outcome) (type: \(type(of: outcome)))")
                }
                if let winner = gameData["winner"] {
                    NSLog("OGS: 🏁 winner field: \(winner) (type: \(type(of: winner)))")
                }
                if let whitePoints = gameData["white_points"] {
                    NSLog("OGS: 🏁 white_points field: \(whitePoints)")
                }
                if let blackPoints = gameData["black_points"] {
                    NSLog("OGS: 🏁 black_points field: \(blackPoints)")
                }
                if let whiteLost = gameData["white_lost"] {
                    NSLog("OGS: 🏁 white_lost field: \(whiteLost)")
                }
                if let blackLost = gameData["black_lost"] {
                    NSLog("OGS: 🏁 black_lost field: \(blackLost)")
                }
                if let endTime = gameData["end_time"] {
                    NSLog("OGS: 🏁 end_time field: \(endTime)")
                }

                // Extract game result data
                if let gameID = gameData["game_id"] as? Int {
                    self.extractGameResult(gameData: gameData, gameID: gameID)
                } else {
                    NSLog("OGS: ⚠️ Cannot extract game result - no game_id found")
                }
            }
        }

        // Get the current player (whose turn it is)
        if let playerToMove = gameData["player_to_move"] as? Int {
            NSLog("OGS: 🎮 Player to move: \(playerToMove)")
        }

        // Check which color we are playing
        // OGS typically includes player info in the game data
        if let players = gameData["players"] as? [String: Any] {
            NSLog("OGS: 🎮 Players info: \(players)")

            // Try to determine our color
            // OGS may send black/white player objects with player IDs
            if let black = players["black"] as? [String: Any],
               let white = players["white"] as? [String: Any] {
                NSLog("OGS: 🎮 Black player: \(black)")
                NSLog("OGS: 🎮 White player: \(white)")
            }
        }

        // Check if there's a "you" field or similar to identify our color
        if let myColor = gameData["player_color"] as? String {
            NSLog("OGS: 🎮 My color: \(myColor)")
            DispatchQueue.main.async {
                self.playerColor = myColor == "black" ? .black : .white
            }
        }

        // Determine whose turn it is from player_to_move
        if let playerToMove = gameData["player_to_move"] as? Int {
            // OGS uses player IDs, we need to map this to color
            // This will be set once we know which player we are
            NSLog("OGS: 🎮 Player to move ID: \(playerToMove)")
        }

        // Parse the moves array to load the complete game state
        NSLog("OGS: 🎮 Checking for moves array in gameData...")
        NSLog("OGS: 🎮 gameData keys: \(gameData.keys.sorted())")

        if let movesArray = gameData["moves"] as? [[Any]] {
            NSLog("OGS: 🎮 Found \(movesArray.count) moves in game data")

            // Extract player IDs for turn calculation
            var blackPlayerID: Int?
            var whitePlayerID: Int?
            if let players = gameData["players"] as? [String: Any] {
                if let black = players["black"] as? [String: Any],
                   let blackID = black["id"] as? Int {
                    blackPlayerID = blackID
                }
                if let white = players["white"] as? [String: Any],
                   let whiteID = white["id"] as? Int {
                    whitePlayerID = whiteID
                }
            }

            // Determine which color we are playing by comparing our playerID to black/white player IDs
            if let myPlayerID = self.playerID {
                if myPlayerID == blackPlayerID {
                    NSLog("OGS: 🎨 We are playing BLACK (our ID \(myPlayerID) matches black player)")
                    DispatchQueue.main.async {
                        self.playerColor = .black
                    }
                } else if myPlayerID == whitePlayerID {
                    NSLog("OGS: 🎨 We are playing WHITE (our ID \(myPlayerID) matches white player)")
                    DispatchQueue.main.async {
                        self.playerColor = .white
                    }
                } else {
                    NSLog("OGS: ⚠️ Our player ID \(myPlayerID) doesn't match black (\(blackPlayerID ?? -1)) or white (\(whitePlayerID ?? -1)) - we may be spectating")
                }
            } else {
                NSLog("OGS: ⚠️ playerID is nil - cannot determine our color")
            }

            // Get whose turn it is from the clock data (OGS sends it as "current_player" in the clock subdictionary)
            var playerToMoveID: Int?
            if let clock = gameData["clock"] as? [String: Any],
               let currentPlayerID = clock["current_player"] as? Int {
                playerToMoveID = currentPlayerID
                NSLog("OGS: 🎮 Current player (from clock): \(currentPlayerID)")
            } else if let currentPlayerID = gameData["player_to_move"] as? Int {
                // Fallback to player_to_move if it exists (some OGS endpoints may use this)
                playerToMoveID = currentPlayerID
                NSLog("OGS: 🎮 Player to move (from gameData): \(currentPlayerID)")
            }

            // Set currentPlayerColor based on whose turn it is
            // This is CRITICAL for correct color mapping and isMyTurn to work
            if let playerToMoveID = playerToMoveID {
                if playerToMoveID == blackPlayerID {
                    NSLog("OGS: 🎨 Setting currentPlayerColor to Black (player \(playerToMoveID) to move)")
                    DispatchQueue.main.async {
                        self.currentPlayerColor = .black
                    }
                } else if playerToMoveID == whitePlayerID {
                    NSLog("OGS: 🎨 Setting currentPlayerColor to White (player \(playerToMoveID) to move)")
                    DispatchQueue.main.async {
                        self.currentPlayerColor = .white
                    }
                } else {
                    NSLog("OGS: ⚠️ playerToMoveID \(playerToMoveID) doesn't match black (\(blackPlayerID ?? -1)) or white (\(whitePlayerID ?? -1))")
                }
            } else {
                NSLog("OGS: ⚠️ Could not determine current player from game data")
            }

            // Get handicap for proper turn calculation
            let handicap = gameData["handicap"] as? Int ?? 0

            // CRITICAL: Only post notification if game ID or move count changed
            // This prevents duplicate reloads that cause the board to go blank
            let currentMoveCount = movesArray.count
            let gameID = gameData["game_id"] as? Int ?? 0
            let shouldPostNotification = (lastPostedGameID != gameID) || (currentMoveCount > lastPostedMoveCount)

            if shouldPostNotification {
                NSLog("OGS: 🎮 Game state changed (gameID: \(lastPostedGameID?.description ?? "nil")→\(gameID), moves: \(lastPostedMoveCount)→\(currentMoveCount)) - posting notification")

                // Update trackers BEFORE posting to prevent race conditions
                lastPostedGameID = gameID
                lastPostedMoveCount = currentMoveCount

                // Send notification with all moves for ContentView3D to load
                let boardSize = gameData["width"] as? Int ?? 19
                NotificationCenter.default.post(
                    name: NSNotification.Name("OGSGameDataReceived"),
                    object: nil,
                    userInfo: [
                        "gameData": gameData,
                        "moves": movesArray,
                        "gameID": gameID,
                        "handicap": handicap,
                        "boardSize": boardSize,
                        "blackPlayerID": blackPlayerID as Any,
                        "whitePlayerID": whitePlayerID as Any,
                        "playerToMoveID": playerToMoveID as Any
                    ]
                )
                NSLog("OGS: 🎮 Notification posted successfully")
            } else {
                NSLog("OGS: 🎮 Game state unchanged (gameID: \(gameID), moves: \(currentMoveCount)) - skipping duplicate notification to prevent board clearing")
            }
        } else {
            NSLog("OGS: ❌ NO MOVES ARRAY FOUND in gameData!")
            NSLog("OGS: ❌ moves field type: \(type(of: gameData["moves"]))")
            if let movesField = gameData["moves"] {
                NSLog("OGS: ❌ moves field value: \(movesField)")
            }
        }

        // Extract player names and ranks for UI display
        if let players = gameData["players"] as? [String: Any] {
            if let blackPlayer = players["black"] as? [String: Any],
               let whitePlayer = players["white"] as? [String: Any],
               let blackName = blackPlayer["username"] as? String,
               let whiteName = whitePlayer["username"] as? String {

                // DEBUG: Log all keys in player objects to find rank field
                NSLog("OGS: 🔍 Black player keys: \(blackPlayer.keys.sorted())")
                NSLog("OGS: 🔍 White player keys: \(whitePlayer.keys.sorted())")
                NSLog("OGS: 🔍 Black player dict: \(blackPlayer)")

                // Extract ranks (OGS uses "rank" field as a Double)
                // Check for provisional/unrated players (ui_class: "provisional")
                let blackRankDouble = blackPlayer["rank"] as? Double
                let whiteRankDouble = whitePlayer["rank"] as? Double
                let blackUIClass = blackPlayer["ui_class"] as? String
                let whiteUIClass = whitePlayer["ui_class"] as? String
                let blackRank = formatOGSRank(blackRankDouble.map { Int($0) }, uiClass: blackUIClass)
                let whiteRank = formatOGSRank(whiteRankDouble.map { Int($0) }, uiClass: whiteUIClass)

                NSLog("OGS: 👥 Black: \(blackName) [\(blackRank)], White: \(whiteName) [\(whiteRank)]")

                // Send notification for player names and ranks
                NotificationCenter.default.post(
                    name: NSNotification.Name("OGSPlayerInfo"),
                    object: nil,
                    userInfo: [
                        "blackName": blackName,
                        "whiteName": whiteName,
                        "blackRank": blackRank,
                        "whiteRank": whiteRank,
                        "blackID": blackPlayer["id"] as? Int ?? 0,
                        "whiteID": whitePlayer["id"] as? Int ?? 0
                    ]
                )
            }
        }
    }

    private func handleClock(_ clockData: [String: Any]) {
        NSLog("OGS: ⏰ handleClock() called with data: \(clockData)")
        extractClockData(clockData)
        NSLog("OGS: ⏰ handleClock() finished, extractClockData completed")
    }

    private func extractClockData(_ clockData: [String: Any]) {
        // DEBUG: Log all clock data keys
        NSLog("OGS: 🔍 Clock data keys: \(clockData.keys.sorted())")
        NSLog("OGS: 🔍 Clock data: \(clockData)")

        // Check if OGS sent a server timestamp ("now" field) for latency compensation
        var latencyOffset: TimeInterval = 0
        if let nowMs = clockData["now"] as? Double {
            let serverTime = nowMs / 1000.0  // Convert ms to seconds
            let localTime = Date().timeIntervalSince1970
            latencyOffset = localTime - serverTime
            NSLog("OGS: ⏱️ Latency compensation: \(String(format: "%.3f", latencyOffset))s (server: \(String(format: "%.3f", serverTime)), local: \(String(format: "%.3f", localTime)))")
        } else if let nowInt = clockData["now"] as? Int {
            let serverTime = Double(nowInt) / 1000.0
            let localTime = Date().timeIntervalSince1970
            latencyOffset = localTime - serverTime
            NSLog("OGS: ⏱️ Latency compensation: \(String(format: "%.3f", latencyOffset))s")
        } else {
            NSLog("OGS: ⚠️ No 'now' timestamp in clock data - cannot compensate for latency")
        }

        // OGS sends time as nested dictionaries with "thinking_time" and "periods"
        if let blackTimeDict = clockData["black_time"] as? [String: Any] {
            NSLog("OGS: 🔍 Black time dict: \(blackTimeDict)")

            // Try Double first (most common), then String as fallback
            var timeValue: Double? = nil
            if let thinkingTimeDouble = blackTimeDict["thinking_time"] as? Double {
                timeValue = thinkingTimeDouble
                NSLog("OGS: ⏱️ Black time extracted as Double: \(thinkingTimeDouble)s")
            } else if let thinkingTimeString = blackTimeDict["thinking_time"] as? String,
                      let parsedTime = Double(thinkingTimeString) {
                timeValue = parsedTime
                NSLog("OGS: ⏱️ Black time extracted as String: \(parsedTime)s")
            } else {
                NSLog("OGS: ❌ Could not extract black thinking_time. Value: \(blackTimeDict["thinking_time"] ?? "nil"), Type: \(type(of: blackTimeDict["thinking_time"]))")
            }

            if let timeValue = timeValue {
                // Apply latency compensation - subtract the time that elapsed during network transfer
                let compensatedTime = max(0, timeValue - latencyOffset)
                DispatchQueue.main.async {
                    self.blackTimeRemaining = compensatedTime
                }
                NSLog("OGS: ⏱️ Black time: \(timeValue)s -> \(String(format: "%.2f", compensatedTime))s (offset: \(String(format: "%.3f", latencyOffset))s)")
            }

            if let periods = blackTimeDict["periods"] as? Int {
                DispatchQueue.main.async {
                    self.blackPeriodsRemaining = periods
                }
                NSLog("OGS: ⏱️ Black periods: \(periods)")
            }

            if let periodTime = blackTimeDict["period_time"] as? Double {
                DispatchQueue.main.async {
                    self.blackPeriodTime = periodTime
                }
                NSLog("OGS: ⏱️ Black period time: \(periodTime)s")
            }
        } else {
            NSLog("OGS: ❌ Could not extract black_time dictionary from clockData")
        }

        if let whiteTimeDict = clockData["white_time"] as? [String: Any] {
            NSLog("OGS: 🔍 White time dict: \(whiteTimeDict)")

            // Try Double first (most common), then String as fallback
            var timeValue: Double? = nil
            if let thinkingTimeDouble = whiteTimeDict["thinking_time"] as? Double {
                timeValue = thinkingTimeDouble
                NSLog("OGS: ⏱️ White time extracted as Double: \(thinkingTimeDouble)s")
            } else if let thinkingTimeString = whiteTimeDict["thinking_time"] as? String,
                      let parsedTime = Double(thinkingTimeString) {
                timeValue = parsedTime
                NSLog("OGS: ⏱️ White time extracted as String: \(parsedTime)s")
            } else {
                NSLog("OGS: ❌ Could not extract white thinking_time. Value: \(whiteTimeDict["thinking_time"] ?? "nil"), Type: \(type(of: whiteTimeDict["thinking_time"]))")
            }

            if let timeValue = timeValue {
                // Apply latency compensation - subtract the time that elapsed during network transfer
                let compensatedTime = max(0, timeValue - latencyOffset)
                DispatchQueue.main.async {
                    self.whiteTimeRemaining = compensatedTime
                }
                NSLog("OGS: ⏱️ White time: \(timeValue)s -> \(String(format: "%.2f", compensatedTime))s (offset: \(String(format: "%.3f", latencyOffset))s)")
            }

            if let periods = whiteTimeDict["periods"] as? Int {
                DispatchQueue.main.async {
                    self.whitePeriodsRemaining = periods
                }
                NSLog("OGS: ⏱️ White periods: \(periods)")
            }

            if let periodTime = whiteTimeDict["period_time"] as? Double {
                DispatchQueue.main.async {
                    self.whitePeriodTime = periodTime
                }
                NSLog("OGS: ⏱️ White period time: \(periodTime)s")
            }
        } else {
            NSLog("OGS: ❌ Could not extract white_time dictionary from clockData")
        }
    }

    private func extractGameResult(gameData: [String: Any], gameID: Int) {
        NSLog("OGS: 🏁 Extracting game result for game \(gameID)")

        // Extract outcome string (e.g., "B+15.5", "W+R", "W+T", "0" for tie)
        let outcomeString = gameData["outcome"] as? String ?? "?"
        NSLog("OGS: 🏁 Outcome string: '\(outcomeString)'")

        // Extract winner (player ID or nil for tie)
        let winnerID = gameData["winner"] as? Int
        NSLog("OGS: 🏁 Winner ID: \(winnerID?.description ?? "nil")")

        // Extract scores
        // OGS may send scores in different formats - try both direct fields and nested objects
        var blackScore: Double = 0.0
        var whiteScore: Double = 0.0

        // Try direct fields first
        if let blackPoints = gameData["black_points"] as? Double {
            blackScore = blackPoints
            NSLog("OGS: 🏁 Black score (direct): \(blackScore)")
        } else if let blackPoints = gameData["black_points"] as? Int {
            blackScore = Double(blackPoints)
            NSLog("OGS: 🏁 Black score (direct int): \(blackScore)")
        }

        if let whitePoints = gameData["white_points"] as? Double {
            whiteScore = whitePoints
            NSLog("OGS: 🏁 White score (direct): \(whiteScore)")
        } else if let whitePoints = gameData["white_points"] as? Int {
            whiteScore = Double(whitePoints)
            NSLog("OGS: 🏁 White score (direct int): \(whiteScore)")
        }

        // Try nested player objects if direct fields weren't found
        if blackScore == 0.0 || whiteScore == 0.0 {
            if let players = gameData["players"] as? [String: Any] {
                if let blackPlayer = players["black"] as? [String: Any],
                   let blackPts = blackPlayer["score"] as? Double {
                    blackScore = blackPts
                    NSLog("OGS: 🏁 Black score (nested): \(blackScore)")
                }
                if let whitePlayer = players["white"] as? [String: Any],
                   let whitePts = whitePlayer["score"] as? Double {
                    whiteScore = whitePts
                    NSLog("OGS: 🏁 White score (nested): \(whiteScore)")
                }
            }
        }

        // Determine winner color based on winner ID
        var winnerColor: Stone? = nil
        if let winnerID = winnerID {
            // Get black and white player IDs to compare
            if let players = gameData["players"] as? [String: Any],
               let blackPlayer = players["black"] as? [String: Any],
               let whitePlayer = players["white"] as? [String: Any],
               let blackPlayerID = blackPlayer["id"] as? Int,
               let whitePlayerID = whitePlayer["id"] as? Int {

                if winnerID == blackPlayerID {
                    winnerColor = .black
                    NSLog("OGS: 🏁 Winner is Black")
                } else if winnerID == whitePlayerID {
                    winnerColor = .white
                    NSLog("OGS: 🏁 Winner is White")
                }
            }
        } else {
            NSLog("OGS: 🏁 No winner - likely a tie")
        }

        // Parse outcome type and reason
        var outcomeType: GameOutcome = .unknown
        var winReason = "points"

        if outcomeString.contains("R") || outcomeString.contains("Resignation") {
            outcomeType = .resignation
            winReason = "resignation"
        } else if outcomeString.contains("T") || outcomeString.contains("Timeout") {
            outcomeType = .timeout
            winReason = "timeout"
        } else if outcomeString == "0" || outcomeString.contains("Tie") {
            outcomeType = .tie
            winReason = "tie"
        } else if outcomeString.contains("C") || outcomeString.contains("Cancellation") {
            outcomeType = .cancellation
            winReason = "cancellation"
        } else if outcomeString.starts(with: "B+") {
            outcomeType = .blackWins
            winReason = "points"
        } else if outcomeString.starts(with: "W+") {
            outcomeType = .whiteWins
            winReason = "points"
        }

        NSLog("OGS: 🏁 Outcome type: \(outcomeType), Win reason: \(winReason)")

        // Create GameResult object
        let result = GameResult(
            gameID: gameID,
            outcome: outcomeType,
            winner: winnerColor,
            blackScore: blackScore,
            whiteScore: whiteScore,
            winReason: winReason
        )

        NSLog("OGS: 🏁 Created GameResult: \(result.winDescription)")

        // Update published property on main thread
        DispatchQueue.main.async {
            self.gameResult = result
            NSLog("OGS: 🏁 gameResult published to UI")
        }
    }

    // MARK: - Undo Event Handlers

    private func handleUndo(eventName: String, data: [String: Any]) {
        NSLog("OGS: ↩️ handleUndo() - Event: \(eventName), Data: \(data)")

        // Route to specific handlers based on event name
        if eventName.contains("requested") || eventName.hasSuffix("/request") {
            handleUndoRequest(eventName: eventName, data: data)
        } else if eventName.contains("accepted") || eventName.hasSuffix("/accept") {
            handleUndoAccepted(data)
        } else if eventName.contains("rejected") || eventName.hasSuffix("/reject") {
            handleUndoRejected(data)
        }
    }

    private func handleUndoRequest(eventName: String, data: [String: Any]) {
        NSLog("OGS: ↩️ ========== UNDO REQUEST RECEIVED ==========")
        NSLog("OGS: ↩️ Event: \(eventName)")
        NSLog("OGS: ↩️ Data: \(data)")

        // Extract game ID from event name (format: "game/12345/undo_requested")
        let components = eventName.components(separatedBy: "/")
        guard components.count >= 2,
              let gameID = Int(components[1]),
              let moveNumber = data["move_number"] as? Int,
              let requestedBy = data["requested_by"] as? Int else {
            NSLog("OGS: ❌ Missing required fields in undo request")
            return
        }

        // Only show dialog if the request is from opponent (not ourselves)
        if requestedBy == self.playerID {
            NSLog("OGS: ↩️ Undo request is from us - ignoring")
            return
        }

        NSLog("OGS: ↩️ ✅ Opponent requested undo - showing dialog")

        // Post notification for UI to handle (show dialog to accept/reject)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("OGSUndoRequested"),
                object: nil,
                userInfo: ["gameID": gameID, "moveNumber": moveNumber]
            )
        }
    }

    private func handleUndoAccepted(_ data: [String: Any]) {
        NSLog("OGS: ✅ Undo request accepted")
        NSLog("OGS: ✅ Data: \(data)")

        // Reload game data to reflect the undo
        if let gameID = data["game_id"] as? Int {
            fetchGameData(gameID: gameID)
        }
    }

    private func handleUndoRejected(_ data: [String: Any]) {
        NSLog("OGS: ❌ Undo request rejected")
        NSLog("OGS: ❌ Data: \(data)")

        // Show notification to user
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("OGSUndoRejected"),
                object: nil,
                userInfo: data
            )
        }
    }

    /// Accept an undo request from opponent
    func acceptUndo(gameID: Int, moveNumber: Int) {
        guard isConnected else {
            NSLog("OGS: ❌ Cannot accept undo - not connected")
            return
        }

        let acceptMessage = """
        ["game/undo/accept",{"game_id":\(gameID),"move_number":\(moveNumber)}]
        """

        let message = URLSessionWebSocketTask.Message.string(acceptMessage)
        webSocketTask?.send(message) { error in
            if let error = error {
                NSLog("OGS: ❌ Error accepting undo: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
            } else {
                NSLog("OGS: ✅ Undo accepted for game \(gameID) at move \(moveNumber)")
            }
        }
    }

    /// Reject an undo request from opponent
    func rejectUndo(gameID: Int, moveNumber: Int) {
        guard isConnected else {
            NSLog("OGS: ❌ Cannot reject undo - not connected")
            return
        }

        let rejectMessage = """
        ["game/undo/reject",{"game_id":\(gameID),"move_number":\(moveNumber)}]
        """

        let message = URLSessionWebSocketTask.Message.string(rejectMessage)
        webSocketTask?.send(message) { error in
            if let error = error {
                NSLog("OGS: ❌ Error rejecting undo: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
            } else {
                NSLog("OGS: ✅ Undo rejected for game \(gameID) at move \(moveNumber)")
            }
        }
    }

    // MARK: - Automatch Event Handlers

    private func handleAutomatchEntry(_ preferencesData: [String: Any]) {
        NSLog("OGS: 🎯 ==================== AUTOMATCH ENTRY RECEIVED ====================")
        NSLog("OGS: 🎯 Server confirmed automatch request!")
        NSLog("OGS: 🎯 Data: \(preferencesData)")
        NSLog("OGS: 🎯 ==================================================================")

        // Also write to file for debugging
        if let logData = "RECEIVED AUTOMATCH ENTRY: \(preferencesData)\n".data(using: .utf8) {
            let logPath = NSHomeDirectory() + "/Desktop/automatch_debug.log"
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(logData)
                handle.closeFile()
            } else {
                try? logData.write(to: URL(fileURLWithPath: logPath))
            }
        }

        // Extract UUID from preferences
        if let uuid = preferencesData["uuid"] as? String {
            DispatchQueue.main.async {
                self.activeAutomatchUUID = uuid
                self.isSearchingForMatch = true
            }
            NSLog("OGS: 🎯 Automatch active with UUID: \(uuid)")
        }
    }

    private func handleAutomatchStart(_ startData: [String: Any]) {
        NSLog("OGS: 🎉 GAME FOUND! Data: \(startData)")

        // Extract game_id and uuid
        guard let gameID = startData["game_id"] as? Int else {
            NSLog("OGS: ❌ No game_id in automatch/start")
            return
        }

        if let uuid = startData["uuid"] as? String {
            NSLog("OGS: 🎯 Match found for UUID: \(uuid)")
        }

        NSLog("OGS: 🎮 Starting game \(gameID)")

        // Update state
        DispatchQueue.main.async {
            self.activeAutomatchUUID = nil
            self.isSearchingForMatch = false
            self.gamePhase = .playing

            // Join the game to start receiving updates
            self.joinGame(gameID: gameID)
        }
    }

    private func handleAutomatchCancel(_ cancelData: [String: Any]) {
        NSLog("OGS: 🛑 Automatch canceled: \(cancelData)")

        if let uuid = cancelData["uuid"] as? String {
            NSLog("OGS: 🛑 Canceled UUID: \(uuid)")
        }

        DispatchQueue.main.async {
            self.activeAutomatchUUID = nil
            self.isSearchingForMatch = false
        }
    }

    private func handleSeekgraph(_ seekgraphData: [[String: Any]]) {
        // Update health check timestamp
        lastSeekgraphMessageTime = Date()

        if verboseLogging {
            log("OGS: ========== v3.63 handleSeekgraph CALLED with \(seekgraphData.count) items ==========")
            NSLog("OGS: 📊 Processing \(seekgraphData.count) seekgraph update(s)...")
        }

        // If this is a large batch (>10 items), it's likely the initial snapshot - replace the list
        // Otherwise it's incremental updates - process one by one
        let isInitialSnapshot = seekgraphData.count > 10
        if verboseLogging && isInitialSnapshot {
            NSLog("OGS: 📊 Detected initial snapshot with \(seekgraphData.count) items - will replace entire list")
        }

        // Collect new games for batch update (if snapshot) or process incrementally
        var newGames: [OGSChallenge] = []

        // Save seekgraph data to file for debugging
        if let jsonData = try? JSONSerialization.data(withJSONObject: seekgraphData, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let logPath = NSHomeDirectory() + "/Desktop/ogs_seekgraph_debug.json"
            try? jsonString.write(toFile: logPath, atomically: true, encoding: .utf8)
        }

        // Process each update incrementally (add/remove from existing list)
        for (index, item) in seekgraphData.enumerated() {
            if verboseLogging {
                log("OGS: 🔍 Processing item \(index+1)/\(seekgraphData.count)")
            }
            guard let challengeID = item["challenge_id"] as? Int else {
                if verboseLogging {
                    log("OGS: ⚠️ Seekgraph item missing challenge_id")
                }
                continue
            }

            // Check if this is a delete message
            if item["delete"] != nil {
                if verboseLogging {
                    NSLog("OGS: 📊 ❌ DELETE challenge #\(challengeID)")
                    NSLog("OGS: 📊 ❌ DELETE PAYLOAD: \(item)")
                    // Log specific fields that might indicate why
                    if let deleteReason = item["delete"] as? String {
                        NSLog("OGS: 📊 ❌ DELETE REASON: \(deleteReason)")
                    }
                    if let error = item["error"] as? String {
                        NSLog("OGS: 📊 ❌ ERROR: \(error)")
                    }
                    if let message = item["message"] as? String {
                        NSLog("OGS: 📊 ❌ MESSAGE: \(message)")
                    }
                }
                DispatchQueue.main.async {
                    self.availableGames.removeAll { $0.id == challengeID }
                    if self.verboseLogging {
                        NSLog("OGS: 📊 Removed challenge #\(challengeID), now have \(self.availableGames.count) games")
                    }

                    // v3.84: Stop keepalives if this was our active challenge
                    if self.activeChallengeID == challengeID {
                        self.stopChallengeKeepalive()
                    }
                }
                continue
            }

            // Check if this is a game_started message (also remove)
            // v3.116: The field can be either "game_started" or "game_id" depending on message type
            var gameID: Int? = nil
            if let id = item["game_started"] as? Int {
                gameID = id
                NSLog("OGS: 📊 🎮 GAME STARTED (via game_started field) for challenge #\(challengeID), game ID: \(id)")
            } else if let id = item["game_id"] as? Int {
                // Only treat this as a game start if we're tracking this challenge
                // (All challenges have game_id, but we only care about ones we created/accepted)
                if self.activeChallengeID == challengeID {
                    gameID = id
                    NSLog("OGS: 📊 🎮 GAME STARTED (via game_id field) for challenge #\(challengeID), game ID: \(id)")
                }
            }

            if let gameID = gameID {
                DispatchQueue.main.async {
                    self.availableGames.removeAll { $0.id == challengeID }
                    NSLog("OGS: 📊 Removed started game #\(challengeID), now have \(self.availableGames.count) games")

                    // v3.84: Stop keepalives if this was our active challenge (game started = challenge accepted)
                    if self.activeChallengeID == challengeID {
                        self.stopChallengeKeepalive()
                    }

                    // v3.116: BUG FIX - Actually join the game that was just started!
                    // This is the critical missing piece - we need to call joinGame() to load the game data
                    NSLog("OGS: 🎮 Calling joinGame(\(gameID)) to load the started game")
                    self.joinGame(gameID: gameID)
                }
                continue
            }

            // This is an ADD message - add or update the challenge
            let minRank = item["min_rank"] as? Int ?? -1000
            let maxRank = item["max_rank"] as? Int ?? 1000
            let boardWidth = item["width"] as? Int ?? 0
            let boardHeight = item["height"] as? Int ?? 0
            let timeControl = item["time_control"] as? String ?? "unknown"

            let isRengo = item["rengo"] as? Bool ?? false
            let userChallenge = item["user_challenge"] as? Bool ?? false
            if verboseLogging {
                log("OGS: 📊 ➕ RECEIVED challenge #\(challengeID): rank[\(minRank)-\(maxRank)] board[\(boardWidth)x\(boardHeight)] time[\(timeControl)] rengo[\(isRengo)] userChallenge[\(userChallenge)]")
            }

            // NOTE: We intentionally INCLUDE user's own challenges so they can cancel them
            // OGS web filters these out, but we want to show them with a "Cancel" button
            // (The filtering code has been removed)

            // Skip rengo (team) games - OGS web filters these out by default
            if isRengo {
                if verboseLogging {
                    log("OGS: 📊 ❌ FILTERED challenge #\(challengeID) - RENGO (team game)")
                }
                continue
            }

            // Skip private games (invite-only to specific players)
            if let isPrivate = item["private"] as? Bool, isPrivate {
                if verboseLogging {
                    log("OGS: 📊 ❌ FILTERED challenge #\(challengeID) - PRIVATE game")
                }
                continue
            }

            // Filter by rank if user is authenticated and has a rank
            // OGS web DOES filter by rank - only shows games user is eligible for
            if let userRank = self.userRank {
                // Check if user's rank is within the acceptable range
                // Rank in OGS: higher number = stronger player (opposite of kyu/dan system)
                if Int(userRank) < minRank || Int(userRank) > maxRank {
                    if verboseLogging {
                        log("OGS: 📊 ❌ FILTERED challenge #\(challengeID) - RANK MISMATCH: user rank \(Int(userRank)) not in range [\(minRank)-\(maxRank)]")
                    }
                    continue
                }
            }

            if verboseLogging {
                log("OGS: 📊 ✅ ADD/UPDATE challenge #\(challengeID)")
            }
            if let challenge = convertSeekgraphToChallenge(item) {
                if isInitialSnapshot {
                    // For snapshot, collect all games
                    newGames.append(challenge)
                } else {
                    // For incremental updates, update immediately
                    DispatchQueue.main.async {
                        self.availableGames.removeAll { $0.id == challengeID }
                        self.availableGames.append(challenge)
                        if self.verboseLogging {
                            NSLog("OGS: 📊 Updated challenge #\(challengeID), now have \(self.availableGames.count) games")
                        }
                    }
                }
            }
        }

        // For snapshots, replace the entire list
        if isInitialSnapshot {
            DispatchQueue.main.async {
                self.availableGames = newGames
                if self.verboseLogging {
                    NSLog("OGS: 📊 Replaced availableGames with \(newGames.count) games from snapshot")
                }
            }
        }
    }

    private func convertSeekgraphToChallenge(_ seekgraphItem: [String: Any]) -> OGSChallenge? {
        // Seekgraph format is different from REST API format
        // We need to convert it to match our OGSChallenge struct

        guard let challengeID = seekgraphItem["challenge_id"] as? Int,
              let userID = seekgraphItem["user_id"] as? Int,
              let username = seekgraphItem["username"] as? String,
              let ranking = seekgraphItem["rank"] as? Double else {
            NSLog("OGS: ⚠️ Missing required fields in seekgraph item")
            return nil
        }

        let width = seekgraphItem["width"] as? Int ?? 19
        let height = seekgraphItem["height"] as? Int ?? 19
        let ranked = seekgraphItem["ranked"] as? Bool ?? false
        let handicap = seekgraphItem["handicap"] as? Int ?? 0
        let minRanking = seekgraphItem["min_rank"] as? Int ?? 0
        let maxRanking = seekgraphItem["max_rank"] as? Int ?? 100

        // Convert time_control_parameters from object to JSON string
        var timeControlParamsString: String? = nil
        if let timeControlParams = seekgraphItem["time_control_parameters"] as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: timeControlParams),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            timeControlParamsString = jsonString
        }

        // Convert komi to string if it's a number
        var komiString: String? = nil
        if let komiNum = seekgraphItem["komi"] as? Double {
            komiString = String(komiNum)
        } else if let komiNum = seekgraphItem["komi"] as? Int {
            komiString = String(komiNum)
        }

        // Build challenger info
        let challenger = ChallengerInfo(
            id: userID,
            username: username,
            ranking: ranking,
            professional: seekgraphItem["pro"] as? Bool ?? false
        )

        // Build game info
        let game = GameInfo(
            id: challengeID,
            name: seekgraphItem["name"] as? String,
            width: width,
            height: height,
            rules: seekgraphItem["rules"] as? String ?? "japanese",
            ranked: ranked,
            handicap: handicap == -1 ? 0 : handicap,  // -1 means automatic, treat as 0
            komi: komiString,
            timeControl: seekgraphItem["time_control"] as? String,
            timeControlParameters: timeControlParamsString,
            disableAnalysis: seekgraphItem["disable_analysis"] as? Bool ?? false,
            pauseOnWeekends: false,
            black: nil,  // Open challenge has no players yet
            white: nil,
            started: nil,
            blackLost: false,  // Seekgraph only shows active challenges
            whiteLost: false,
            annulled: false
        )

        // Build challenge
        let challenge = OGSChallenge(
            id: challengeID,
            challenger: challenger,
            game: game,
            challengerColor: seekgraphItem["challenger_color"] as? String ?? "automatic",
            minRanking: minRanking,
            maxRanking: maxRanking,
            created: nil
        )

        return challenge
    }

    private func schedulePing() {
        // Send ping every 25 seconds to keep connection alive
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self = self, self.isConnected else { return }

            let ping = URLSessionWebSocketTask.Message.string("2")
            self.webSocketTask?.send(ping) { error in
                if let error = error {
                    NSLog("OGS: ❌ Ping error: \(error.localizedDescription)")
                } else {
                    NSLog("OGS: 🏓 Ping sent")
                    // Schedule next ping
                    self.schedulePing()
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate
extension OGSClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let errMsg = "OGS: ❌ Task completed with error: \(error.localizedDescription)"
            NSLog(errMsg)
            print(errMsg)
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
                self.isConnected = false
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        let openMsg = "OGS: ✅ WebSocket opened with protocol: \(`protocol` ?? "none")"
        NSLog(openMsg)
        print(openMsg)

        // Update error display to show we're connected
        DispatchQueue.main.async {
            self.lastError = nil
        }

        // Note: isConnected will be set to true after namespace connection (message "40")
        // receiveMessage() is already called in connect()
        // Authentication happens after namespace connection, not here
        // receiveMessage() is already called in connect(), no need to call again
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        var reasonString = "none"
        if let reason = reason, let str = String(data: reason, encoding: .utf8) {
            reasonString = str
        }
        let closeMessage = "OGS: 🔌 WebSocket closed with code: \(closeCode.rawValue), reason: \(reasonString)"
        NSLog(closeMessage)
        print(closeMessage)

        // Detailed close code description
        var codeDescription = ""
        switch closeCode {
        case .invalid: codeDescription = "Invalid"
        case .normalClosure: codeDescription = "Normal Closure"
        case .goingAway: codeDescription = "Going Away"
        case .protocolError: codeDescription = "Protocol Error"
        case .unsupportedData: codeDescription = "Unsupported Data"
        case .noStatusReceived: codeDescription = "No Status Received"
        case .abnormalClosure: codeDescription = "Abnormal Closure"
        case .invalidFramePayloadData: codeDescription = "Invalid Frame Payload"
        case .policyViolation: codeDescription = "Policy Violation"
        case .messageTooBig: codeDescription = "Message Too Big"
        case .mandatoryExtensionMissing: codeDescription = "Mandatory Extension Missing"
        case .internalServerError: codeDescription = "Internal Server Error"
        case .tlsHandshakeFailure: codeDescription = "TLS Handshake Failure"
        @unknown default: codeDescription = "Unknown"
        }
        NSLog("OGS: 🔌 Close code description: \(codeDescription)")

        // Write to debug log
        let logMessage = "[\(Date())] \(closeMessage)\n"
        if let data = logMessage.data(using: .utf8) {
            let logPath = NSHomeDirectory() + "/Desktop/sgfplayer_ogs_debug.log"
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
            }
        }

        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = "Connection closed [\(codeDescription)]: \(reasonString)"
        }

        // Post notification about disconnection
        NotificationCenter.default.post(name: NSNotification.Name("OGSDisconnected"), object: nil)
    }

    // Format OGS rank number to string (e.g., -5 = 5k, 5 = 5d)
    // Handles provisional/unrated players (ui_class: "provisional")
    private func formatOGSRank(_ rankValue: Int?, uiClass: String? = nil) -> String {
        // Check if player is provisional/unrated
        if uiClass == "provisional" {
            return "?"
        }

        guard let rank = rankValue else { return "" }

        // OGS ranking system: 0-29 = 30k-1k, 30+ = 1d+
        if rank < 30 {
            // Kyu ranks: 0 = 30k, 28 = 2k, 29 = 1k
            let kyuRank = 30 - rank
            return "\(kyuRank)k"
        } else {
            // Dan ranks: 30 = 1d, 31 = 2d, 38 = 9d
            let danRank = rank - 29
            return "\(danRank)d"
        }
    }
}
