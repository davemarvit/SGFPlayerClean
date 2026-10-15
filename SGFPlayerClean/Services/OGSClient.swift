// ========================================================
// FILE: ./Services/OGSClient.swift
// VERSION: v16.185 (Final Integrity Audit / Zero-Dups)
// ========================================================

import Foundation
import Combine




class OGSClient: NSObject, ObservableObject {
    let buildVersion = "16.185"
    static let defaultObservationOnly = false
    @Published var observationOnly: Bool
    private let observationError = NSError(domain: "OGSReview", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "This review app supports observation only."])

    /// Each running review owns its cookie jar; OGSReviewSessionStore restores/saves
    /// its verified login separately from the working app's cookie store.
    static func reviewSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        return config
    }

    static func observationGameID(_ input: String) -> Int? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func positiveID(_ value: String) -> Int? {
            guard !value.isEmpty, value.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let id = Int(value), id > 0 else { return nil }
            return id
        }
        if let id = positiveID(text) { return id }
        guard let url = URLComponents(string: text), url.scheme == "https",
              url.host == "online-go.com" || url.host == "www.online-go.com",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        let path = url.path.split(separator: "/")
        guard path.count == 2, path[0] == "game" else { return nil }
        return positiveID(String(path[1]))
    }
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var isSocketAuthenticated = false
    @Published var isReconcilingMoves = false
    @Published var isAuthenticated = false
    @Published var lastError: String? = nil
    @Published var username: String?
    @Published var playerID: Int?
    @Published var userRank: Int? // OGS Rank Integer (0=30k ... 29=1k, 30=1d)
    @Published var userJWT: String?
    
    @Published var activeGameID: Int? {
        didSet {
             if oldValue != activeGameID {
                 gameEventGeneration += 1
                 resetScoringSubmission()
                 removedStones = []
                 scoreSummary = nil
                 strictSekiMode = false
                 phase = nil
                 isGameFinished = false
                 activeGameResult = nil
                 activeGameOutcome = nil
                 blackPlayerID = nil
                 whitePlayerID = nil
                 playerColor = nil
                 lastKnownRemoteMoveNumber = nil
                 currentStateVersion = 0
                 blackCaptures = 0; whiteCaptures = 0
                 isReconcilingMoves = false
                 komi = nil; gameRules = nil
                 if pendingGameID != activeGameID {
                     gameStateReader.cancel()
                     pendingGameID = nil
                 }
                 if activeGameID != nil { stopChallengePruner() }
                 else if isConnected { startChallengePruner() }
                 NSLog("[OGS-DEBUG] 🎮 activeGameID CHANGED: \(oldValue ?? -1) -> \(activeGameID ?? -1)")
             }
        }
    }
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
    @Published private(set) var observedGames: [OGSObservedGame] = []
    @Published private(set) var observedGamesPage = 0
    @Published private(set) var observedGamesTotal = 0
    @Published private(set) var hasMoreObservedGames = false
    @Published private(set) var isLoadingObservedGames = false
    @Published private(set) var observedGamesError: String?
    static let observedGamesPageSize = 20
    private var observedGamesRequest: (id: Int, page: Int)?
    private var observedGamesTimeout: OGSCancellable?
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
    @Published var phase: String? = "play" {
        didSet {
            if phase != oldValue {
                resetScoringSubmission()
                if phase == "play" { removedStones = []; scoreSummary = nil }
            }
        }
    }
    @Published var removedStones: Set<BoardPosition> = [] {
        didSet { if removedStones != oldValue { resetScoringSubmission() } }
    }
    @Published private(set) var scoreSummary: OGSScoreSummary?
    @Published private(set) var strictSekiMode = false {
        didSet { if strictSekiMode != oldValue { resetScoringSubmission() } }
    }
    @Published private(set) var scoreAcceptance: OGSScoreAcceptance = .none
    @Published private(set) var scoringError: String?
    private var scoringTimeout: OGSCancellable?
    private var scoringSubmissionGeneration = 0
    private var scoringBoardWidth = 19
    private var scoringBoardHeight = 19
    @Published var komi: Double? // NEW: Komi Display
    
    // Debugging
    @Published var lastReceivedEvent: String = ""

    // MARK: - Private Protocol State
    private var lastClockSnapshot: [String: Any]?
    private var hasEnteredRoom: Bool = false
    
    // Keep-Alive
    private var keepAliveTimer: Timer?
    private var activeChallengeID: Int?
    private var activeChallengeGameID: Int?
    
    private(set) var isSearchingForGame: Bool = false
    @Published var connectionStatus: String = "Disconnected"
    @Published var serverLatency: Double = 0.0
    
    // Graveyard: Track deleted challenge IDs to prevent stale REST data from resurrecting them (Zombies)
    // Map ID -> Time of Deletion. We keep them for ~30-60s.
    private var graveyard: [Int: Date] = [:]
    
    private var currentAutomatchUUID: String? // Track active Automatch request
    private lazy var connection: OGSConnectionController = {
        let controller = OGSConnectionController { [originHeader, userAgent, socketFactory, cookieStorage = urlSession.configuration.httpCookieStorage] in
            if let socketFactory { return socketFactory() }
            // Keep the existing Socket.IO endpoint and message format during lifecycle extraction.
            var request = URLRequest(url: URL(string: "wss://wsp.online-go.com/socket.io/?EIO=4&transport=websocket")!)
            request.setValue(originHeader, forHTTPHeaderField: "Origin")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            return OGSURLSessionSocket(request: request, cookieStorage: cookieStorage)
        }
        controller.onStateChange = { [weak self] state in self?.handleConnectionState(state) }
        controller.onMessage = { [weak self] text in
            guard let self else { return }
            if text != "2" && text != "3" { self.writeToBlackBox(text, direction: "IN") }
            self.handleIncomingProtocolMessage(text)
        }
        controller.onError = { [weak self] error in self?.lastError = error.localizedDescription }
        return controller
    }()
    private let reviewSessionStore: OGSReviewSessionStore?
    private let urlSession: URLSession
    private let socketFactory: (() -> OGSWebSocket)?
    private let scoringScheduler: OGSConnectionScheduler
    private lazy var httpTransport = OGSURLSessionHTTPTransport(session: urlSession)
    private lazy var lobbyReader = OGSPaginatedReader<OGSChallenge>(transport: httpTransport)
    private lazy var gameStateReader = OGSJSONReader(transport: httpTransport)
    private lazy var userConfigReader = OGSJSONReader(transport: httpTransport)
    private var pendingGameID: Int?
    private var initialLobbyCheck: OGSCancellable?
    private var loginTask: URLSessionDataTask?
    private var identityGeneration = 0
    private var connectionEventGeneration = 0
    private var gameEventGeneration = 0
    private var gameMoveRevision = 0
    private var challengeGeneration = 0
    private var challengeTask: URLSessionDataTask?

    private var socketPingTimer: Timer?
    private var handshakeTimer: Timer?
    private var socketNamespaceReady = false
    private var socketAuthAttempted = false
    private var socketAuthTimeout: OGSCancellable?
    private var enginePulseTimer: Timer?
    private var lobbyChallenges: [Int: OGSChallenge] = [:]
    // Grace Period: Track when we locally added a challenge. 
    // We will NOT prune a challenge via REST if it was added < 15s ago (Eventual Consistency Protection)
    private var challengeCreationTimes: [Int: Date] = [:] 
    private var challengePruneTimer: Timer?
    private var lastReportedLatency: Int = 85
    var currentStateVersion: Int = 0
    private var requestSequence: Int = 100 // Client-side request counter
    
    private let originHeader = "https://online-go.com"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    override convenience init() {
        #if SGF_OFFLINE_REVIEW
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        #elseif SGF_OGS_REVIEW
        let config = Self.reviewSessionConfiguration()
        #else
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        #endif
        #if SGF_OGS_REVIEW
        let sessionStore = OGSReviewSessionStore.defaultStore()
        #else
        let sessionStore: OGSReviewSessionStore? = nil
        #endif
        self.init(session: URLSession(configuration: config, delegate: nil, delegateQueue: .main),
                  reviewSessionStore: sessionStore)
    }

    /// The app and offline fixtures use the same client with different transport dependencies.
    init(session: URLSession, socketFactory: (() -> OGSWebSocket)? = nil,
         scoringScheduler: OGSConnectionScheduler = OGSMainQueueScheduler(),
         observationOnly: Bool = OGSClient.defaultObservationOnly,
         reviewSessionStore: OGSReviewSessionStore? = nil) {
        self.reviewSessionStore = reviewSessionStore
        self.observationOnly = observationOnly
        self.scoringScheduler = scoringScheduler
        self.urlSession = session
        self.socketFactory = socketFactory
        super.init()
        if let reviewSessionStore {
            do {
                for cookie in try reviewSessionStore.load() {
                    urlSession.configuration.httpCookieStorage?.setCookie(cookie)
                }
            } catch {
                lastError = "Saved review login could not be read. Please sign in again."
            }
        }
        #if SGF_OFFLINE_REVIEW
        connectionStatus = "Offline review — OGS blocked"
        #else
        fetchUserConfig()
        #endif
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
    func fetchUserConfig(completion: ((Bool, String?) -> Void)? = nil) {
        #if SGF_OFFLINE_REVIEW
        completion?(false, "OGS is disabled in the offline review app.")
        return
        #else
        let identity = identityGeneration
        let url = URL(string: "https://online-go.com/api/v1/ui/config")!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        userConfigReader.load(request) { [weak self] result in
            guard let self, self.identityGeneration == identity else {
                completion?(false, "Login cancelled"); return
            }
            switch result {
            case .success(let json):
                guard let user = json["user"] as? [String: Any],
                      let id = self.robustInt(user["id"]), id > 0,
                      let jwt = json["user_jwt"] as? String,
                      !jwt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.disconnect()
                    self.clearIdentity()
                    self.forgetReviewSession()
                    completion?(false, "OGS did not return a signed-in account.")
                    return
                }
                // Never carry a socket authenticated as another account into this identity.
                if let oldID = self.playerID, oldID != id { self.disconnect() }
                self.username = user["username"] as? String
                self.playerID = id
                self.userRank = self.robustInt(user["ranking"])
                self.userJWT = jwt
                self.isAuthenticated = true
                if let store = self.reviewSessionStore {
                    do { try store.save(self.urlSession.configuration.httpCookieStorage?.cookies ?? []) }
                    catch { self.lastError = "Signed in, but this review login could not be saved for next time." }
                }
                completion?(true, nil)
            case .failure(let error):
                if let httpError = error as? OGSHTTPError, case .status(let status) = httpError,
                   status == 401 || status == 403 {
                    self.disconnect()
                    self.clearIdentity()
                    self.forgetReviewSession()
                }
                if (error as? URLError)?.code != .cancelled { self.lastError = error.localizedDescription }
                completion?(false, error.localizedDescription)
            }
        }
        #endif
    }

    private func clearIdentity() {
        userJWT = nil
        playerID = nil
        username = nil
        userRank = nil
        playerColor = nil
        myActiveGames.removeAll()
        isAuthenticated = false
        isSocketAuthenticated = false
    }

    func connect() {
        #if SGF_OFFLINE_REVIEW
        connectionStatus = "Offline review — OGS blocked"
        #else
        connection.connect()
        #endif
    }

    func disconnect() {
        clearObservedGames()
        invalidateChallengeRequest()
        connection.disconnect()
        stopChallengeKeepAlive()
    }

    private func handleConnectionState(_ state: OGSConnectionState) {
        isConnected = state == .connected
        if isConnected {
            connectionStatus = "Connected"
            lastError = nil
            startHandshakeMonitor()
            startChallengePruner()
            return
        }

        // Invalidate work already queued by the previous socket, as well as future callbacks.
        clearObservedGames()
        connectionEventGeneration += 1
        resetScoringSubmission()
        // Subscriptions and room membership belong to one socket, not the whole app lifetime.
        isSocketAuthenticated = false
        socketNamespaceReady = false
        socketAuthAttempted = false
        socketAuthTimeout?.cancel(); socketAuthTimeout = nil
        isSubscribedToSeekgraph = false
        gameStateReader.cancel()
        pendingGameID = nil
        handshakeTimer?.invalidate(); handshakeTimer = nil
        socketPingTimer?.invalidate(); socketPingTimer = nil
        stopEnginePulse()
        stopClockTimer()
        stopChallengePruner()
        lastClockSnapshot = nil
        lobbyChallenges.removeAll()
        availableGames = []
        switch state {
        case .disconnected: connectionStatus = "Disconnected"
        case .connecting: connectionStatus = "Connecting…"
        case .reconnecting(let delay): connectionStatus = "Reconnecting in \(Int(delay))s…"
        case .connected: break
        }
    }

    // MARK: - Authentication
    func logout() {
        identityGeneration += 1
        loginTask?.cancel(); loginTask = nil
        userConfigReader.cancel()
        // 1. Disconnect Socket
        disconnect()
        
        clearIdentity()
        forgetReviewSession()
        if reviewSessionStore != nil { activeGameID = nil }

        // 3. Clear Cookies
        if let cookies = urlSession.configuration.httpCookieStorage?.cookies(for: URL(string: "https://online-go.com")!) {
            for cookie in cookies {
                urlSession.configuration.httpCookieStorage?.deleteCookie(cookie)
            }
        }
        
        // 4. Clear Defaults if any
        UserDefaults.standard.removeObject(forKey: "ods_session_token") // Example
        
        objectWillChange.send()
    }
    
    private func forgetReviewSession() {
        guard let store = reviewSessionStore else { return }
        for cookie in urlSession.configuration.httpCookieStorage?.cookies ?? [] {
            urlSession.configuration.httpCookieStorage?.deleteCookie(cookie)
        }
        do { try store.clear() }
        catch { lastError = "Could not remove the saved review login from this Mac." }
    }

    func login(username: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        identityGeneration += 1
        let identity = identityGeneration
        invalidateChallengeRequest()
        loginTask?.cancel()
        userConfigReader.cancel()
        guard identityGeneration == identity else { completion(false, "Login cancelled"); return }
        disconnect()
        clearIdentity()
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
        if let cookies = urlSession.configuration.httpCookieStorage?.cookies(for: URL(string: "https://online-go.com")!),
           let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value {
            req.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
            req.setValue(csrf, forHTTPHeaderField: "X-XSRF-TOKEN") // Redundancy
        }
        
        let body = ["username": username, "password": password]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        loginTask = urlSession.dataTask(with: req) { [weak self] data, response, error in
            guard let self, self.identityGeneration == identity else {
                completion(false, "Login cancelled")
                return
            }
            self.loginTask = nil
            if let http = response as? HTTPURLResponse {
                // NSLog("[OGS-AUTH] Login Response: \(http.statusCode)")
                if http.statusCode == 200 || http.statusCode == 204 {
                    // Success! Cookies should be set automatically by URLSession.
                    // Now refresh config to get JWT.
                    self.fetchUserConfig(completion: completion)
                } else {
                    completion(false, "Login failed (Code \(http.statusCode))")
                }
            } else {
                completion(false, error?.localizedDescription ?? "Network Error")
            }
        }
        loginTask?.resume()
    }

    func opponentName(for myID: Int?) -> String? {
        guard let myID = myID else { return nil }
        if myID == blackPlayerID { return whitePlayerName }
        if myID == whitePlayerID { return blackPlayerName }
        return nil
    }
    
    // MARK: - REST API Calls
    func fetchGameState(gameID: Int, completion: @escaping ([String: Any]?) -> Void) {
        gameStateReader.cancel()
        pendingGameID = gameID
        let revision = gameMoveRevision
        let ts = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://online-go.com/api/v1/games/\(gameID)?t=\(ts)")!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        if let jwt = userJWT { request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization") }
        gameStateReader.load(request) { [weak self] result in
            guard let self else { completion(nil); return }
            self.pendingGameID = nil
            switch result {
            case .success(let json):
                if self.activeGameID == gameID, self.gameMoveRevision != revision {
                    completion(nil)
                    self.requestMoveResync()
                    return
                }
                completion(json)
            case .failure(let error):
                if (error as? URLError)?.code != .cancelled { self.lastError = error.localizedDescription }
                completion(nil)
            }
        }
    }

    /// Recover gaps/conflicts with a read, never by resending a move.
    func requestMoveResync() {
        guard isConnected, let id = activeGameID else { return }
        isReconcilingMoves = true
        guard pendingGameID == nil else { return }
        let context = makeGameNotification(name: Notification.Name("OGSGameDataReceived"), userInfo: [:])
        let revision = gameMoveRevision
        fetchGameState(gameID: id) { [weak self] root in
            guard let self, self.acceptsGameNotification(context) else { return }
            guard let root else { return }
            // A snapshot requested before a newer move must not undo that move.
            guard self.gameMoveRevision == revision else {
                self.requestMoveResync(); return
            }
            var game = (root["gamedata"] as? [String: Any]) ?? root
            if game["id"] == nil && game["game_id"] == nil { game["game_id"] = id }
            NotificationCenter.default.post(self.makeGameNotification(name: context.name,
                userInfo: ["gameData": game, "reconcileMoves": true, "moveRevision": revision]))
        }
    }

    func acceptChallenge(challengeID: Int, completion: @escaping (Int?, Error?) -> Void) {
        guard !observationOnly else { completion(nil, observationError); return }
        NSLog("[OGS-ACTION] Accepting Challenge \(challengeID)...")
        guard let url = URL(string: "https://online-go.com/api/v1/challenges/\(challengeID)/accept"), let jwt = userJWT else {
            completion(nil, OGSHTTPError.status(401)); return
        }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        if let cookies = urlSession.configuration.httpCookieStorage?.cookies(for: URL(string: "https://online-go.com")!),
           let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value { request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken") }
        
        performChallengeRequest(request) { [weak self] result in
            switch result {
            case .success(let json):
                guard let self else { completion(nil, URLError(.cancelled)); return }
                if let id = self.robustInt(json["id"]) ?? self.robustInt(json["game_id"]) ?? self.robustInt(json["game"]) {
                    self.isSearchingForGame = false
                    completion(id, nil)
                } else {
                    self.isSearchingForGame = false
                    completion(nil, OGSHTTPError.invalidJSON)
                }
            case .failure(let error): completion(nil, error)
            }
        }
    }

    /// Challenge mutations are sent once. Never retry an ambiguously accepted POST.
    private func performChallengeRequest(_ request: URLRequest,
                                         completion: @escaping (Result<[String: Any], Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard challengeTask == nil else {
            completion(.failure(NSError(domain: "OGSClient", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "A challenge request is already in progress"])))
            return
        }
        let generation = challengeGeneration
        isSearchingForGame = true
        challengeTask = urlSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.challengeGeneration == generation else {
                    completion(.failure(URLError(.cancelled)))
                    return
                }
                self.challengeTask = nil
                do {
                    if let error { throw error }
                    guard let response = response as? HTTPURLResponse, let data else {
                        throw OGSHTTPError.invalidResponse
                    }
                    let body = try OGSHTTPResponse(data: data, response: response).validatedData()
                    guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                        throw OGSHTTPError.invalidJSON
                    }
                    completion(.success(json))
                } catch {
                    self.isSearchingForGame = false
                    completion(.failure(error))
                }
            }
        }
        challengeTask?.resume()
    }

    private func invalidateChallengeRequest() {
        challengeGeneration += 1
        challengeTask?.cancel()
        challengeTask = nil
        isSearchingForGame = false
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

    func fetchSGF(gameID: Int, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: "https://online-go.com/api/v1/games/\(gameID)/sgf") else {
            completion(nil); return
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        _ = httpTransport.get(request) { result in
            do {
                let response = try result.get()
                completion(try response.validatedData())
            } catch {
                NSLog("[OGS-SGF] Download failed: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    func createChallenge(setup: ChallengeSetup, completion: @escaping (Bool, String?) -> Void) {
        guard !observationOnly else { completion(false, observationError.localizedDescription); return }
        // Note: Added trailing slash to avoid potential 301 redirects dropping POST body
        guard let jwt = userJWT, let url = URL(string: "https://online-go.com/api/v1/challenges/") else {
             completion(false, "Not authenticated"); return
        }
        
        self.currentAutomatchUUID = nil
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(originHeader, forHTTPHeaderField: "Referer")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        if let cookies = urlSession.configuration.httpCookieStorage?.cookies(for: URL(string: "https://online-go.com")!),
           let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value { 
            request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
            request.setValue(csrf, forHTTPHeaderField: "X-XSRF-TOKEN") // Redundancy for strict proxies
        }
        
        let payload = setup.toDictionary()
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            NSLog("[OGS-REST] 📤 Creating Challenge Payload:\n\(jsonString)")
        }
        
        performChallengeRequest(request) { [weak self] result in
            switch result {
            case .success(let json):
                guard let self else { completion(false, "Request cancelled"); return }
                if let id = self.robustInt(json["id"]) ?? self.robustInt(json["challenge_id"]) ?? self.robustInt(json["challenge"]) {
                    let gameID = self.robustInt(json["game"]) ?? self.robustInt(json["game_id"])
                    self.startChallengeKeepAlive(challengeID: id, gameID: gameID)
                    completion(true, nil)
                } else {
                    self.isSearchingForGame = false
                    completion(false, json["detail"] as? String ?? "Invalid challenge response")
                }
            case .failure(let error): completion(false, error.localizedDescription)
            }
        }
    }

    func startChallengeKeepAlive(challengeID: Int, gameID: Int?) {
        guard !observationOnly else { return }
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
        guard isConnected, let cid = activeChallengeID else { return }
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
        guard !observationOnly else { return }
        invalidateChallengeRequest()
        let generation = challengeGeneration
        let identity = identityGeneration
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
        request.setValue(originHeader, forHTTPHeaderField: "Referer") // Essential for Django CSRF
        
        // Add Cookies if needed (usually good idea)
        if let cookies = urlSession.configuration.httpCookieStorage?.cookies(for: URL(string: "https://online-go.com")!) {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            if let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value {
                request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
                request.setValue(csrf, forHTTPHeaderField: "X-XSRF-TOKEN") // Redundancy for strict proxies
                NSLog("[OGS-AUTH-DEBUG] 🍪 Cookies Attached. CSRF Found: Yes. Count: \(cookies.count)")
            } else {
                NSLog("[OGS-AUTH-DEBUG] 🍪 Cookies Attached. CSRF Found: NO. Count: \(cookies.count)")
            }
        } else {
             NSLog("[OGS-AUTH-DEBUG] ⚠️ No Cookies Found for online-go.com")
        }
        
        NSLog("[OGS-AUTH-DEBUG] 🚀 Attempting Cancel Challenge \(challengeID). User: \(self.username ?? "nil") ID: \(self.playerID ?? -1). JWT Length: \(jwt.count)")

        urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self, self.identityGeneration == identity, self.challengeGeneration == generation else { return }
            if let http = response as? HTTPURLResponse {
                NSLog("[OGS-CANCEL-DEBUG] 📡 Cancel Response: \(http.statusCode)")
                if (200...299).contains(http.statusCode) || http.statusCode == 404 || http.statusCode == 403 {
                     if self.lobbyChallenges[challengeID] != nil {
                             NSLog("[OGS-CANCEL-DEBUG] 🧹 Force Removing Challenge \(challengeID) from Local State (Status: \(http.statusCode)).")
                             self.lobbyChallenges.removeValue(forKey: challengeID)
                             self.refreshLobbyUI()
                     }
                }
                
                if http.statusCode == 403 {
                    NSLog("[OGS-AUTH-DEBUG] ⛔️ 403 Forbidden. Auth Mismatch? Triggering Config Refresh.")
                    self.fetchUserConfig()
                }
            }
            
            if let e = error { NSLog("[OGS] ❌ Cancel Challenge Failed: \(e)") }
            else { NSLog("[OGS] ✅ Challenge Cancel Request Sent: \(challengeID)") }
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
        guard !observationOnly else { return }
        self.isSearchingForGame = true
        let params: [String: Any] = ["game_params": ["size": 19, "speed": "live"], "lower_rank": 30, "upper_rank": 9]
        sendAction("automatch/start", payload: params)
    }

    func sendChat(gameID: Int, text: String) {
        sendAction("game/chat", payload: ["game_id": gameID, "body": text, "type": "main"])
    }

    func sendUndoRequest(gameID: Int, moveNumber: Int) {
        guard gameID == activeGameID, isConnected, isSocketAuthenticated, isGameParticipant, !isReconcilingMoves else { return }
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
         guard gameID == activeGameID, isConnected, isSocketAuthenticated, isGameParticipant, !isReconcilingMoves else { return }
         self.isRequestingUndo = true
         NSLog("[OGS-CLIENT] ↩️ sendUndoAccept: Flag SET to TRUE")
        sendAction("game/undo/accept", payload: ["game_id": gameID, "move_number": moveNumber], sequence: currentStateVersion + 1)
    }

    func sendUndoReject(gameID: Int) {
        sendAction("game/undo/cancel", payload: ["game_id": gameID])
    }
    
    // MARK: - Scoring
    var isScoringPhase: Bool { OGSScoring.isScoring(phase) }
    var isScoreAccepted: Bool { scoreAcceptance == .confirmed }
    var isGameParticipant: Bool {
        guard !observationOnly else { return false }
        return isAccountGameParticipant
    }

    /// Identity is independent of the selected UI mode and its read-only policy.
    var isAccountGameParticipant: Bool {
        guard let playerID, playerID > 0 else { return false }
        return playerID == blackPlayerID || playerID == whitePlayerID
    }

    var hasOngoingAccountGame: Bool {
        (!isGameFinished && activeGameID != nil && isAccountGameParticipant) ||
            !myActiveGames.subtracting(finishedGameIDs).isEmpty
    }

    /// Stop viewing a board without signing out, resigning, or closing the socket.
    func leaveViewedGame() {
        if let id = activeGameID {
            if isAccountGameParticipant && !isGameFinished { myActiveGames.insert(id) }
            sendAction("game/disconnect", payload: ["game_id": id])
        }
        stopEnginePulse(); stopClockTimer()
        activeGameID = nil
    }
    var canEditScore: Bool {
        isConnected && isSocketAuthenticated && isGameParticipant && !isReconcilingMoves && activeGameID != nil &&
        isScoringPhase && !isGameFinished && scoreAcceptance != .resuming && scoreAcceptance != .updating
    }

    private func resetScoringSubmission() {
        scoringSubmissionGeneration += 1
        scoringTimeout?.cancel(); scoringTimeout = nil
        scoreAcceptance = .none
        scoringError = nil
    }

    private func beginScoringSubmission(_ state: OGSScoreAcceptance) {
        resetScoringSubmission()
        scoreAcceptance = state
        let game = gameEventGeneration
        let connection = connectionEventGeneration
        let submission = scoringSubmissionGeneration
        scoringTimeout = scoringScheduler.schedule(after: 15) { [weak self] in
            guard let self, self.gameEventGeneration == game,
                  self.connectionEventGeneration == connection, self.scoringSubmissionGeneration == submission,
                  self.scoreAcceptance == state else { return }
            self.resetScoringSubmission()
            self.scoringError = "OGS has not confirmed this request. Check the connection and review the board before trying again."
        }
    }

    func acceptScore(gameID: Int) {
        guard activeGameID == gameID, canEditScore, scoreAcceptance == .none else { return }
        beginScoringSubmission(.submitting)
        sendAction("game/removed_stones/accept", payload: [
            "game_id": gameID,
            "stones": OGSScoring.encodePositions(removedStones),
            "strict_seki_mode": strictSekiMode
        ])
    }

    func rejectScore(gameID: Int) {
        guard activeGameID == gameID, canEditScore else { return }
        beginScoringSubmission(.resuming)
        // OGS resumes play through this command; an undo is a separate action.
        sendAction("game/removed_stones/reject", payload: ["game_id": gameID])
    }

    func sendRemovedStones(gameID: Int, stones: String, removed: Bool) {
        guard activeGameID == gameID, canEditScore, !stones.isEmpty,
              OGSScoring.decodePositions(stones, width: scoringBoardWidth, height: scoringBoardHeight) != nil else { return }
        beginScoringSubmission(.updating)
        sendAction("game/removed_stones/set", payload: ["game_id": gameID, "removed": removed, "stones": stones])
    }

    private func applyGamePhase(_ newPhase: String) {
        guard ["play", "stone removal", "scoring", "finished"].contains(newPhase) else { return }
        phase = newPhase
        if newPhase == "play" {
            isGameFinished = false
            activeGameResult = nil
            activeGameOutcome = nil
            startClockTimer()
        } else {
            stopClockTimer()
            if newPhase == "finished" {
                isGameFinished = true; stopEnginePulse()
                if let id = activeGameID { finishedGameIDs.insert(id); myActiveGames.remove(id) }
            }
        }
    }

    /// Used by both socket gamedata and REST game loading. Omitted marks preserve prior state;
    /// an explicit empty string clears them, including at game end.
    func applyScoringSnapshot(_ data: [String: Any]) {
        if let id = robustInt(data["game_id"]) ?? robustInt(data["id"]), id != activeGameID { return }
        if let width = robustInt(data["width"]), (1...52).contains(width) { scoringBoardWidth = width }
        if let height = robustInt(data["height"]), (1...52).contains(height) { scoringBoardHeight = height }
        if let value = data["phase"] as? String { applyGamePhase(value) }
        if let strict = data["strict_seki_mode"] as? Bool { strictSekiMode = strict }
        if let text = data["removed"] as? String { handleInboundRemovedStones(text) }
        else if let values = data["removed"] as? [String] { handleInboundRemovedStones(values.joined()) }
        else if let values = data["removed_stones"] as? [String] { handleInboundRemovedStones(values.joined()) }
        if data["score"] != nil { scoreSummary = OGSScoreSummary.parse(data["score"]) }
        if let players = data["players"] as? [String: Any] {
            for color in ["black", "white"] {
                guard let player = players[color] as? [String: Any],
                      let id = robustInt(player["id"]), id == playerID,
                      let stones = player["accepted_stones"] as? String else { continue }
                confirmScore(playerID: id, stones: stones, strict: player["accepted_strict_seki_mode"] as? Bool ?? false)
            }
        }
    }

    private func confirmScore(playerID id: Int, stones: String, strict: Bool) {
        guard isScoringPhase, isGameParticipant, scoreAcceptance != .updating, scoreAcceptance != .resuming,
              id == playerID || id == 0,
              OGSScoring.decodePositions(stones, width: scoringBoardWidth, height: scoringBoardHeight) == removedStones,
              strict == strictSekiMode else { return }
        resetScoringSubmission()
        scoreAcceptance = .confirmed
    }

    private func handleRemovedStonesUpdate(_ data: [String: Any]) {
        guard isScoringPhase || phase == "finished" else { return }
        if let strict = data["strict_seki_mode"] as? Bool { strictSekiMode = strict }
        if let all = data["all_removed"] as? String { handleInboundRemovedStones(all) }
        else if let text = data["stones"] as? String, let removed = data["removed"] as? Bool,
                let positions = OGSScoring.decodePositions(text, width: scoringBoardWidth, height: scoringBoardHeight) {
            if removed { removedStones.formUnion(positions) }
            else { removedStones.subtract(positions) }
        }
    }

    func subscribeToSeekgraph() {
        sendAction("seek_graph/connect", payload: ["channel": "global"])
        self.isSubscribedToSeekgraph = true
        // REST Sync Disabled to prevent "Flood" of stale/zombie games.
        // We rely on the WebSocket 'seekgraph' events for Truth.
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

    /// Preserve queue ordering while rejecting work from a disconnected socket or replaced game.
    private func enqueueSocketUpdate(gameScoped: Bool = true, _ update: @escaping () -> Void) {
        let connection = connectionEventGeneration
        let game = gameEventGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.connectionEventGeneration == connection,
                  !gameScoped || self.gameEventGeneration == game else { return }
            update()
        }
    }

    private struct GameNotificationContext {
        let connection: Int
        let game: Int
        let gameID: Int?
        let offlineSimulation: Bool
    }

    /// Capture this before deferring delivery. Consumers validate it after their own queue hop.
    func makeGameNotification(name: Notification.Name, userInfo: [AnyHashable: Any],
                              offlineSimulation: Bool = false) -> Notification {
        var info = userInfo
        info["_ogsContext"] = GameNotificationContext(connection: connectionEventGeneration,
            game: gameEventGeneration, gameID: activeGameID, offlineSimulation: offlineSimulation)
        return Notification(name: name, object: self, userInfo: info)
    }

    func acceptsGameNotification(_ notification: Notification) -> Bool {
        guard notification.object as? OGSClient === self,
              let context = notification.userInfo?["_ogsContext"] as? GameNotificationContext else { return false }
        if let revision = notification.userInfo?["moveRevision"] as? Int, revision != gameMoveRevision { return false }
        return (isConnected || context.offlineSimulation) && context.connection == connectionEventGeneration &&
            context.game == gameEventGeneration && context.gameID == activeGameID && activeGameID != nil
    }

    // MARK: - Inbound Message Processing
    private func handleIncomingProtocolMessage(_ text: String) {
        if text.hasPrefix("0") { sendRaw("40"); return }
        if text.hasPrefix("40") {
             socketNamespaceReady = true
             startSocketHeartbeat();
             sendSocketAuth();
             // SoundManager.shared.play("opponent_connected") // USER REQUEST: Silence
             return
        }
        if text == "2" { sendRaw("3"); return }
        
        // Socket.IO acknowledgement ID precedes the JSON array.
        if text.hasPrefix("43") {
            handleObservedGamesReply(text)
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
        guard let event = OGSSocketEvent(json: json) else { return }
        let eventName = event.name
        let payload = event.object
        // Reject unrelated game packets before they can modify version, phase, or clocks.
        if eventName.hasPrefix("game/") {
            let parts = eventName.components(separatedBy: "/")
            guard parts.count >= 3, let packetID = Int(parts[1]), packetID == activeGameID else { return }
            if ["move", "gamedata", "undo_accepted"].contains(parts[2]) { gameMoveRevision += 1 }
        }

        if eventName.hasSuffix("/gamedata") {
            let notification = makeGameNotification(name: Notification.Name("OGSGameDataReceived"), userInfo: ["gameData": payload])
            NotificationCenter.default.post(notification)
            return
        }

        if eventName.hasSuffix("/phase"), let value = event.payload as? String {
            applyGamePhase(value)
            return
        }
        if eventName.hasSuffix("/removed_stones_accepted") {
            applyScoringSnapshot(payload)
            if phase == "finished", let stones = payload["stones"] as? String { handleInboundRemovedStones(stones) }
            if payload["outcome"] != nil || payload["phase"] as? String == "finished" { applyGameResult(payload) }
            if let id = robustInt(payload["player_id"]), let stones = payload["stones"] as? String {
                confirmScore(playerID: id, stones: stones, strict: payload["strict_seki_mode"] as? Bool ?? false)
            }
            return
        }

        // FIREHOSE LOGGING (Time Capsule Mode: Selective)
        if eventName.contains("seek_graph") {
             // NSLog("[OGS-TRACE] 🔍 Seekgraph Event: \(eventName)")
             
             // SeekGraph Logic Moved Here:
             // seek_graph can be a LIST (Initial State) or a SINGLE Object (Update/Add)
             if let data = event.containerData {
                 // 1. Try Array (Initial Batch)
                 if let list = try? JSONDecoder().decode([OGSChallenge].self, from: data) {
                     self.enqueueSocketUpdate(gameScoped: eventName.hasPrefix("game/")) {
                         NSLog("[OGS-LOBBY] 📦 Received Batch of \(list.count) Challenges via Socket")
                         for c in list { self.processSocketChallenge(c) }
                         self.refreshLobbyUI()
                     }
                 } 
                 // 2. Try Single Object (Incremental Update)
                 else {
                     do {
                         let challenge = try JSONDecoder().decode(OGSChallenge.self, from: data)
                         self.enqueueSocketUpdate(gameScoped: eventName.hasPrefix("game/")) {
                             self.processSocketChallenge(challenge)
                             self.refreshLobbyUI()
                         }
                     } catch {
                         NSLog("[OGS-DECODE-ERR] ❌ Failed to decode seek_graph: \(error)")
                     }
                 }
             }
        }
        
        if eventName.hasPrefix("game/"), let sv = robustInt(payload["state_version"]) {
            self.currentStateVersion = max(self.currentStateVersion, sv)
        }

        if isAuthenticated && socketAuthAttempted && !isSocketAuthenticated && (eventName == "authenticated" || eventName == "notification" || eventName.contains("seekgraph")) {
            self.enqueueSocketUpdate(gameScoped: eventName.hasPrefix("game/")) {
                guard !self.isSocketAuthenticated else { return }
                self.socketAuthTimeout?.cancel(); self.socketAuthTimeout = nil
                self.isSocketAuthenticated = true
                self.subscribeToSeekgraph()
                self.performPostAuthSubscriptions() // UPDATED
            }
        }

        // PILLAR: SURGICAL DISCOVERY & FIREWALL
        if eventName == "active_game" || (eventName == "notification" && payload["type"] as? String == "gameStarted") {
            // FIX: Do NOT default to "play". Require explicit phase.
            let phase = payload["phase"] as? String
            if phase == "finished", let id = robustInt(payload["game_id"]) ?? robustInt(payload["id"]) {
                enqueueSocketUpdate {
                    guard self.myActiveGames.contains(id) else { return }
                    self.finishedGameIDs.insert(id)
                    self.myActiveGames.remove(id)
                    if id == self.activeGameID { self.applyGamePhase("finished") }
                }
            }
            if phase == "play" || phase == "stone removal" {
                let bid = robustInt(payload["black_id"]) ?? robustInt((payload["black"] as? [String: Any])?["id"])
                let wid = robustInt(payload["white_id"]) ?? robustInt((payload["white"] as? [String: Any])?["id"])
                
                self.enqueueSocketUpdate(gameScoped: eventName.hasPrefix("game/")) {
                    if bid == self.playerID || wid == self.playerID {
                        if let gid = self.robustInt(payload["game_id"]) ?? self.robustInt(payload["id"]) {
                            if self.activeGameID == gid, let phase { self.applyGamePhase(phase) }
                            // FIX: Only track as "Active" if Phase is Play AND No Outcome
                            if (phase == "play" || phase == "stone removal") && (payload["outcome"] == nil || payload["outcome"] is NSNull) {
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
                            
                            
                            if (!self.observationOnly && self.isSearchingForGame) || self.activeGameID == gid {
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

        
        // AUTOMATCH CONFIRMATION
        if eventName == "automatch/available/add" {
            // Server is confirming our request!
            let uuid = payload["uuid"] as? String
            NSLog("[OGS-AUTOMATCH] ✅ Request Active. UUID: \(uuid ?? "?")")
            return
        }

        // Check for Game Over signals immediately
        if eventName.hasPrefix("game/"), let phase = payload["phase"] as? String, phase == "finished" {
            self.isGameFinished = true
            self.stopEnginePulse()
            self.stopClockTimer()
        }
        if eventName.hasPrefix("game/"), payload["outcome"] is String {
            self.isGameFinished = true
            self.stopClockTimer()
        }

        if eventName.hasSuffix("/clock") {
            if !self.isGameFinished {
                 if let p = payload as? [String: Any] { self.lastClockSnapshot = p; handleInboundClock(p) }
            }
        } else if eventName.hasSuffix("/move") {
            handleIncomingMove(payload)
        } else if eventName.hasSuffix("/chat") {
            handleIncomingChat(payload)
        } else if eventName.hasSuffix("/undo_requested") {
            let number = robustInt(payload["move_number"]) ?? robustInt(event.payload)
            let requester = robustInt(payload["requested_by"])
            if let number, number > 0, isGameParticipant,
               requester != playerID, requester != nil || !isRequestingUndo {
                undoRequestedUsername = requester == blackPlayerID ? (blackPlayerName ?? "Black") :
                    requester == whitePlayerID ? (whitePlayerName ?? "White") : (opponentName(for: playerID) ?? "Opponent")
                undoRequestedMoveNumber = number
            }
        } else if eventName.hasSuffix("/stone_removal") {
            if let text = payload["removed"] as? String { handleInboundRemovedStones(text) }
            else if let values = payload["removed"] as? [String] { handleInboundRemovedStones(values.joined()) }
        } else if eventName.hasSuffix("/removed_stones") {
            handleRemovedStonesUpdate(payload)
        }

        else if eventName.hasSuffix("/undo_accepted") {
            // The payload can be a number, string, or object. Fetch the complete post-undo state
            // instead of guessing whether the number is a move index or a count of removed moves.
            gameStateReader.cancel()
            pendingGameID = nil
            undoRequestedUsername = nil
            undoRequestedMoveNumber = nil
            requestMoveResync()
        } else if eventName.contains("/undo/reject") || eventName.contains("/undo/cancel") || eventName.hasSuffix("/undo_canceled") {
            NSLog("OGS: ↩️ Undo Cancelled/Rejected event received: \(eventName)")
            self.enqueueSocketUpdate(gameScoped: eventName.hasPrefix("game/")) {
                self.isRequestingUndo = false
                self.undoRequestedUsername = nil
                self.undoRequestedMoveNumber = nil
            }
        } else if eventName == "seekgraph/global" {
            // FIX: Handle both Full Sync (Array) and Incremental Updates (Dictionary)
            // Previously, receiving a Dictionary (e.g. delete:1) caused 'items' cast to fail
            // but 'removeAll()' had already run, wiping the lobby.
            
            if let items = event.payload as? [[String: Any]] {
                // FULL SYNC / BATCH UPDATE: Merge strategy.
                // Do NOT wipe (removeAll) because the server sends partial batches here too.
                // OGS sends explicit "delete" keys for removal.
                for i in items { updateLobbyItem(i) }
                refreshLobbyUI()
            } else if let item = event.payload as? [String: Any] {
                // INCREMENTAL UPDATE: Add/Update/Delete Single
                updateLobbyItem(item)
                refreshLobbyUI()
            }
        } else if eventName == "net/ping" {
            handleNetPing(payload)
        }
    }

    // MARK: - Logic Handlers (Atomic)
    func applyAcceptedGameData(_ p: [String: Any]) {
        let gid = self.robustInt(p["game_id"]) ?? self.robustInt(p["id"]) ?? activeGameID
        NSLog("[OGS-DATA] 📦 handleInboundGameData for \(gid ?? -1). Keys: \(p.keys.sorted())")

        guard gid == self.activeGameID else { return }
        let players = p["players"] as? [String: Any]
        self.currentHandicap = self.robustInt(p["handicap"]) ?? 0
        self.lastKnownRemoteMoveNumber = (p["moves"] as? [[Any]])?.count

        // Phase A: Identity & Rank Parsing
        let blackObj = (players?["black"] as? [String: Any])
        let whiteObj = (players?["white"] as? [String: Any])

        self.blackPlayerID = self.robustInt(blackObj?["id"]) ?? self.robustInt(p["black_player_id"])
        self.whitePlayerID = self.robustInt(whiteObj?["id"]) ?? self.robustInt(p["white_player_id"])

        self.blackPlayerName = blackObj?["username"] as? String ?? self.blackPlayerName
        self.whitePlayerName = whiteObj?["username"] as? String ?? "White"

        NSLog("[OGS-DEBUG-COLOR] 📥 Parsed Game Data. MyID: \(self.playerID ?? -1). BlackID: \(self.blackPlayerID ?? -1). WhiteID: \(self.whitePlayerID ?? -1).")

        let bR = (blackObj?["ranking"] as? Double) ?? (blackObj?["rank"] as? Double)
        let bR_int = (blackObj?["ranking"] as? Int) ?? (blackObj?["rank"] as? Int)
        self.blackPlayerRank = bR ?? bR_int.map { Double($0) }

        let wR = (whiteObj?["ranking"] as? Double) ?? (whiteObj?["rank"] as? Double)
        let wR_int = (whiteObj?["ranking"] as? Int) ?? (whiteObj?["rank"] as? Int)
        self.whitePlayerRank = wR ?? wR_int.map { Double($0) }
        self.blackPlayerCountry = blackObj?["country"] as? String
        self.whitePlayerCountry = whiteObj?["country"] as? String

        // Phase B: Game Rules & Ranked Status
        self.gameRules = p["rules"] as? String
        if let ranked = p["ranked"] as? Bool { self.isRanked = ranked }
        if let k = p["komi"] as? Double { self.komi = k }
        else if let kstr = p["komi"] as? String { self.komi = Double(kstr) }


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
                per_move: tcDict["per_move"] as? Int,
                speed: tcDict["speed"] as? String // FIX: Added missing field
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
                per_move: params["per_move"] as? Int,
                speed: params["speed"] as? String // FIX: Added missing field
            )
            self.activeGameTimeControl = ChallengeHelpers.formatTimeControl(tc: tc, params: tp, perMove: nil)

            if let pt = tp.period_time {
                self.blackPeriodLength = Double(pt)
                self.whitePeriodLength = Double(pt)
            }
        }

        // Phase C: Initial Clock State
        if let clock = p["clock"] as? [String: Any] {
            self.lastClockSnapshot = clock
            self.handleInboundClock(clock)
        }

        self.hasEnteredRoom = true

        self.applyScoringSnapshot(p)

        if let version = robustInt(p["state_version"]) { currentStateVersion = version }
        self.applyGameResult(p)

        self.identityLockCheck()
        self.objectWillChange.send()

        // Re-Ensure Clock is Running (in case connectToGame started it but we didn't have players yet)
        if !self.isGameFinished && self.phase == "play" {
            self.startClockTimer()
        }
    }



    private func applyGameResult(_ p: [String: Any]) {
        if let outcome = p["outcome"] as? String {
            self.isGameFinished = true
            // FIX: Use Game ID from payload directly.
            let targetGID = self.robustInt(p["game_id"]) ?? self.robustInt(p["id"]) ?? self.activeGameID
            if let gid = targetGID {
                self.enqueueSocketUpdate {
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

            if let wid = winnerID, wid > 0 {
                // Logic: Personalized Outcome Message & Structured Result
                if let pid = self.playerID, self.isGameParticipant {
                    if wid == pid {
                        let opponentName = (winnerName == self.blackPlayerName) ? (self.whitePlayerName ?? "White") : (self.blackPlayerName ?? "Black")
                        self.activeGameOutcome = "You won by \(outcome)"
                        self.activeGameResult = GameResult(
                            title: "You Win",
                            subtitle: "You beat \(opponentName) by \(outcome)",
                            method: "Victory", // Simplified
                            isMe: true
                        )
                    } else {
                        // Opponent won
                        let opponentName = (wid == self.blackPlayerID) ? (self.blackPlayerName ?? "Black") : (self.whitePlayerName ?? "White")
                        self.activeGameOutcome = "Your opponent, \(opponentName), wins by \(outcome)"
                         self.activeGameResult = GameResult(
                            title: "You Lost",
                            subtitle: "You lost to \(opponentName) by \(outcome)",
                            method: "Defeat", // Simplified
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
                if outcome.lowercased().contains("draw") || (winnerID == 0 && ["0", "0 points", "0.0 points", "jigo"].contains(outcome.lowercased())) {
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
                self.enqueueSocketUpdate {
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
                 self.enqueueSocketUpdate {
                     NSLog("[OGS-LOBBY] 🧼 REMOVING Finished Game \(gid) from Active List (Count: \(self.myActiveGames.count))")
                     self.myActiveGames.remove(gid)
                     self.finishedGameIDs.insert(gid) // NEW: Remember it's finished
                 }
            }
            // If phase is missing, DO NOT CHANGE isGameFinished.
            // (It might be a partial update for a finished game)
        }
    }

    private func handleInboundClock(_ data: [String: Any]) {
        self.enqueueSocketUpdate {
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
        guard let number = robustInt(data["move_number"]), number > 0 else { requestMoveResync(); return }
        if number > (lastKnownRemoteMoveNumber ?? 0) {
            lastKnownRemoteMoveNumber = number
            undoRequestedUsername = nil
            undoRequestedMoveNumber = nil
            isRequestingUndo = false
        }
        // Board reconciliation determines the turn and captures, including handicap and duplicates.
        NotificationCenter.default.post(makeGameNotification(name: NSNotification.Name("OGSMoveReceived"), userInfo: data))
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
        
        self.enqueueSocketUpdate {
             NotificationCenter.default.post(self.makeGameNotification(name: NSNotification.Name("OGSChatReceived"), userInfo: data))
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
            
            // 1. Ensure Auth
            if !self.isSocketAuthenticated { self.sendSocketAuth() }
            
            // 2. Ensure Lobby Subscription (if no active game)
            else if !self.isSubscribedToSeekgraph && self.activeGameID == nil {
                self.subscribeToSeekgraph()
            }
            
            // 3. Ensure Game Room Connection
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
        
        self.enqueueSocketUpdate {
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
        guard let jwt = userJWT, !jwt.isEmpty, let pid = playerID, pid > 0,
              isConnected, socketNamespaceReady, !socketAuthAttempted else { return }
        socketAuthAttempted = true
        let generation = connectionEventGeneration
        socketAuthTimeout = scoringScheduler.schedule(after: 15) { [weak self] in
            guard let self, self.connectionEventGeneration == generation, !self.isSocketAuthenticated else { return }
            self.lastError = "Socket authentication could not be confirmed. Reconnect to retry."
        }
        let payload: [String: Any] = ["jwt": jwt, "player_id": pid, "username": username ?? ""]
        NSLog("[OGS-AUTH] Authenticating WebSocket")
        sendAction("authenticate", payload: payload)
    }

    private func identityLockCheck() {
        guard let myID = self.playerID else { 
            NSLog("[OGS-DEBUG-COLOR] ⚠️ identityLockCheck Skipped. No PlayerID.")
            return 
        }
        
        let oldColor = self.playerColor
        if myID == self.blackPlayerID { self.playerColor = .black }
        else if myID == self.whitePlayerID { self.playerColor = .white }
        
        if self.playerColor != oldColor {
             NSLog("[OGS-DEBUG-COLOR] 🎨 Color Locked: \(self.playerColor.map { "\($0)" } ?? "nil") (MyID: \(myID) vs B:\(self.blackPlayerID ?? -1)/W:\(self.whitePlayerID ?? -1))")
        }
    }

    /// Fetch a fresh list, or append its next bounded batch as the user scrolls.
    func loadMoreObservedGames() {
        guard hasMoreObservedGames, !isLoadingObservedGames else { return }
        fetchObservedGames(page: observedGamesPage + 1)
    }

    func fetchObservedGames(page: Int = 0) {
        #if SGF_OFFLINE_REVIEW
        observedGamesError = "OGS is disabled in the offline review app."
        return
        #else
        guard isSocketAuthenticated, isConnected else {
            observedGamesError = "Connect to OGS to load current games."
            return
        }
        guard page >= 0, page < Int.max / Self.observedGamesPageSize else { return }
        if page > 0 {
            guard hasMoreObservedGames, page == observedGamesPage + 1, observedGamesRequest == nil else { return }
        }
        if observedGamesRequest?.page == page { return }
        observedGamesTimeout?.cancel()
        requestSequence += 1
        let id = requestSequence
        observedGamesRequest = (id, page)
        isLoadingObservedGames = true
        observedGamesError = nil
        observedGamesTimeout = scoringScheduler.schedule(after: 12) { [weak self] in
            guard let self, self.observedGamesRequest?.id == id else { return }
            self.observedGamesRequest = nil
            self.observedGamesTimeout = nil
            self.isLoadingObservedGames = false
            self.observedGamesError = "The game list did not arrive. Try Refresh."
        }
        sendAction("gamelist/query", payload: ["list": "live", "sort_by": "rank", "where": [:],
            "from": page * Self.observedGamesPageSize, "limit": Self.observedGamesPageSize], acknowledgementID: id)
        #endif
    }

    private func clearObservedGames() {
        observedGamesRequest = nil
        observedGamesTimeout?.cancel(); observedGamesTimeout = nil
        isLoadingObservedGames = false
        observedGames = []
        observedGamesPage = 0
        observedGamesTotal = 0
        hasMoreObservedGames = false
        observedGamesError = nil
    }

    private func handleObservedGamesReply(_ text: String) {
        let body = text.dropFirst(2)
        let digits = body.prefix { $0 >= "0" && $0 <= "9" }
        guard let id = Int(digits), let pending = observedGamesRequest, pending.id == id else { return }
        observedGamesRequest = nil
        observedGamesTimeout?.cancel(); observedGamesTimeout = nil
        isLoadingObservedGames = false
        guard let data = String(body.dropFirst(digits.count)).data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let response = args.first as? [String: Any],
              let size = response["size"] as? Int, size >= 0,
              let rows = response["results"] as? [[String: Any]],
              args.count < 2 || args[1] is NSNull else {
            observedGamesError = "Could not load current games. Try Refresh."
            return
        }
        // Games may move between server pages while being played. Update duplicate IDs
        // in place, rather than rendering duplicates or dropping earlier loaded games.
        var combined = pending.page == 0 ? [] : observedGames
        var indices = Dictionary(uniqueKeysWithValues: combined.enumerated().map { ($0.element.id, $0.offset) })
        var seen: Set<Int> = []
        for game in rows.prefix(Self.observedGamesPageSize).compactMap(OGSObservedGame.init)
            where seen.insert(game.id).inserted {
            if let index = indices[game.id] { combined[index] = game }
            else { indices[game.id] = combined.count; combined.append(game) }
        }
        observedGames = OGSObservedGame.strongestFirst(combined)
        observedGamesPage = pending.page
        observedGamesTotal = size
        hasMoreObservedGames = !rows.isEmpty && pending.page * Self.observedGamesPageSize + min(rows.count, Self.observedGamesPageSize) < size
        observedGamesError = nil
    }

    private func sendAction(_ event: String, payload: [String: Any], sequence: Int? = nil, acknowledgementID: Int? = nil) {
        if observationOnly {
            let allowed: Set<String> = ["authenticate", "game/connect", "game/disconnect",
                "net/ping", "net/pong", "game/latency", "seek_graph/connect",
                "ui-pushes/subscribe", "automatch/available/subscribe", "automatch/list", "user/monitor", "gamelist/query"]
            guard allowed.contains(event) else {
                lastError = observationError.localizedDescription
                return
            }
        }
        let json = tightJson(payload)
        let prefix = "42" + (acknowledgementID.map(String.init) ?? "")
        let packet = (sequence != nil) ? "\(prefix)[\"\(event)\",\(json),\(sequence!)]" : "\(prefix)[\"\(event)\",\(json)]"
        // if event != "net/ping" { NSLog("[OGS-SOCKET] 📤 Sending: \(packet)") } // SILENCED FOR TIME CAPSULE
        sendRaw(packet)
    }

    private func sendRaw(_ text: String) {
        // Authentication packets contain a bearer token; keep it out of debug history.
        let loggedText = text.contains("\"authenticate\"") ? "authenticate [credentials redacted]" : text
        writeToBlackBox(loggedText, direction: "OUT ATTEMPT")
        connection.send(text)
    }

    private func tightJson(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []), let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }



    // Helper: Process Socket Challenges
    private func processSocketChallenge(_ challenge: OGSChallenge) {
        // FILTER: 1X10S Debug
        let name = challenge.challenger?.username ?? "Unknown"
        if name.lowercased().contains("1x10s") {
            NSLog("[OGS-DEBUG-TARGET] 🎯 Found Target '1X10S'! ID: \(challenge.id). GameID: \(challenge.game_id ?? -1). Speed: \(challenge.speed ?? "nil"). Started: \(challenge.game_started ?? false)")
        }

        // DUPLICATE CHECK
        let existing = self.lobbyChallenges.values.first(where: { $0.game_id != nil && $0.game_id == challenge.game_id })
        if let ex = existing, ex.id != challenge.id {
             // NSLog("[OGS-DUPE?] 👯‍♀️ Challenge \(challenge.id) is dupe of \(ex.id) (GameID: \(challenge.game_id ?? -1))")
        }
        
        // ZOMBIE / FILTER CHECK
        if challenge.game_started == true { return }
        
        self.lobbyChallenges[challenge.id] = challenge
        self.challengeCreationTimes[challenge.id] = Date()
    }


    private func finalizeLobbySync(_ challenges: [OGSChallenge]) {
        dispatchPrecondition(condition: .onQueue(.main))
        let validIDs = Set(challenges.filter {
            $0.game_started != true &&
            ($0.phase == nil || ($0.phase != "play" && $0.phase != "finished")) &&
            $0.outcome == nil
        }.map { $0.id })

        var prunedCount = 0
        for id in self.lobbyChallenges.keys where !validIDs.contains(id) {
            // Give newly received socket challenges time to reach the REST listing.
            if let birth = self.challengeCreationTimes[id], Date().timeIntervalSince(birth) < 15 {
                continue
            }
            self.lobbyChallenges.removeValue(forKey: id)
            self.challengeCreationTimes.removeValue(forKey: id)
            prunedCount += 1
        }

        // Preserve socket ownership of additions; REST is only a pruning safety net.
        if prunedCount > 0 {
            NSLog("[OGS-LOBBY] Pruned \(prunedCount) challenges via complete REST snapshot.")
        }
        self.refreshLobbyUI()
    }

    // MARK: - Graveyard Logic (Anti-Zombie)
    private func addToGraveyard(_ id: Int) {
        self.graveyard[id] = Date()
        // NSLog("[OGS-GRAVE] ⚰️ Buried Challenge \(id) to prevent resurrection.")
    }
    
    private func cleanupGraveyard() {
        let now = Date()
        // Keep explicitly deleted items dead for 45s (covering reasonably long socket/REST drifts)
        let expiry: TimeInterval = 45 
        let oldLimit = now.addingTimeInterval(-expiry)
        
        let initialCount = graveyard.count
        graveyard = graveyard.filter { $0.value > oldLimit }
        
        if graveyard.count < initialCount {
            // NSLog("[OGS-GRAVE] 🧹 Cleaned up \(initialCount - graveyard.count) expired grave records.")
        }
    }

    /// Explicitly remove a challenge (e.g. when 404 is encountered on Accept)
    func forceRemoveChallenge(id: Int) {
        DispatchQueue.main.async { [weak self] in
             guard let self = self else { return }
             if self.lobbyChallenges[id] != nil {
                 self.lobbyChallenges.removeValue(forKey: id)
                 self.addToGraveyard(id) // Ensure it stays dead
                 NSLog("[OGS-LOBBY] 🧹 Force-removed zombie challenge \(id)")
                 self.refreshLobbyUI()
             }
        }
    }

    private func updateLobbyItem(_ dict: [String: Any]) {
        // CASE 1: Delete Command { "delete": 12345 } or { "challenge_id": 123, "delete": true }
        if let deleteID = robustInt(dict["delete"]) {
            // NSLog("[OGS-LOBBY-DEBUG] 🗑️ Socket Delete Command for \(deleteID)")
            self.lobbyChallenges.removeValue(forKey: deleteID)
            self.addToGraveyard(deleteID)
            return
        }
        
        guard let id = robustInt(dict["challenge_id"]) ?? robustInt(dict["game_id"]) else { return }
        
        if dict["delete"] != nil { 
            // NSLog("[OGS-LOBBY-DEBUG] 🗑️ Socket Delete Flag for \(id)")
            self.lobbyChallenges.removeValue(forKey: id)
            self.addToGraveyard(id)
            return 
        }
        
        // [DEBUG LOGGING: TIME CAPSULE MODE]
        // Log RAW dictionary for direct comparison with Browser DevTools
        // let rawLog = tightJson(dict)
        // NSLog("[OGS-TRACE] RAW Item \(id): \(rawLog)") 

        // HANDLE Game Started Events (Remove from Lobby)
        if let started = dict["game_started"] as? Bool, started == true {
             // NSLog("[OGS-LOBBY] 🏁 Game Started Event for \(id) -> REMOVING Challenge.")
             self.lobbyChallenges.removeValue(forKey: id)
             self.addToGraveyard(id)
             return
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: dict), 
           let ch = try? JSONDecoder().decode(OGSChallenge.self, from: data) {
            
            // GUARD: Prevent invalid/broken challenges (e.g. Automatch leakage or bad decode)
            // Fix: Explicitly check for nil username (which becomes "Unknown" in UI)
            if ch.id == 0 || (ch.challenger?.username ?? "Unknown") == "Unknown" {
                 // NSLog("[OGS-LOBBY] 🛡️ Ignored Invalid Challenge. ID: \(ch.id), User: \(ch.challenger?.username ?? "nil")")
                 return
            }

            self.lobbyChallenges[id] = ch
            
            // Check if it's mine
            if let pid = self.playerID, let creatorID = ch.challenger?.id, pid == creatorID {
                // NSLog("[OGS-TRACE] 🟢 Found MY Challenge: \(id). Creator: \(ch.challenger?.username ?? "?") (\(creatorID))")
            }
        } else {
             // LOGGING: Identify why we failed to decode
             NSLog("[OGS-TRACE] ⚠️ Failed to decode item ID \(id): \(dict)")
        }
    }

    private func refreshLobbyUI() {
        DispatchQueue.main.async { [weak self] in
            self?.performLobbyRefresh()
        }
    }

    private func performLobbyRefresh() {
        var filtered: [OGSChallenge] = []
        var droppedCount = 0
        
        for ch in self.lobbyChallenges.values {
            // Filter: If this challenge represents a game I am already in
            // Logic: Check if challenge ID matches an active game ID (common reuse)
            // Or if I am the challenger
            
            var shouldSkip = false
            let gid = ch.id // In many lobby payloads, id is the game_id
            
            if self.myActiveGames.contains(gid) || self.finishedGameIDs.contains(gid) {
                 shouldSkip = true
                 // NSLog("[OGS-FILTER] 🚫 Filtering challenge \(ch.id) (Game ID \(gid)) - Already in Active/Finished list.")
            } else if let mine = self.playerID, let cid = ch.challenger?.id, cid == mine {
                 // I am the challenger, but is it Active?
                 if self.myActiveGames.contains(gid) { 
                     shouldSkip = true 
                     // NSLog("[OGS-FILTER] 🚫 Filtering my challenge \(ch.id) - It is now an active game.")
                 }
            }
            
            if !shouldSkip {
                filtered.append(ch)
            } else {
                droppedCount += 1
            }
        }
        
        if droppedCount > 0 {
            // NSLog("[OGS-LOBBY] Filtered out \(droppedCount) challenges (Active/Finished). Available: \(filtered.count)")
        }
        
        self.availableGames = filtered.sorted(by: { $0.id > $1.id })
        
        // LOGGING: Pipeline Stage 2 - Available for UI
        NSLog("[OGS-TRACE] 📦 performLobbyRefresh complete. Available Games: \(self.availableGames.count) (Dropped: \(droppedCount))")
        
        self.objectWillChange.send()
    }

    func robustDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let s = v as? String { return Double(s) }
        if let i = v as? Int { return Double(i) }
        return nil
    }
    private func handleInboundRemovedStones(_ text: String) {
        guard isScoringPhase || phase == "finished",
              let positions = OGSScoring.decodePositions(text, width: scoringBoardWidth, height: scoringBoardHeight) else { return }
        if scoreAcceptance == .updating { resetScoringSubmission() }
        removedStones = positions
    }

    private func startChallengePruner() {
        stopChallengePruner()
        guard isConnected, activeGameID == nil else { return }
        // Keep the existing five-second check cadence; the reader prevents overlapping requests.
        challengePruneTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkActiveChallenges()
        }
        initialLobbyCheck = OGSMainQueueScheduler().schedule(after: 2) { [weak self] in
            self?.initialLobbyCheck = nil
            self?.checkActiveChallenges()
        }
    }

    private func stopChallengePruner() {
        challengePruneTimer?.invalidate(); challengePruneTimer = nil
        initialLobbyCheck?.cancel(); initialLobbyCheck = nil
        lobbyReader.cancel()
    }

    func checkActiveChallenges() {
        guard isConnected, activeGameID == nil, !isSearchingForGame else { return }
        var request = URLRequest(url: URL(string: "https://online-go.com/api/v1/challenges/")!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(originHeader, forHTTPHeaderField: "Origin")
        if let jwt = userJWT { request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization") }
        lobbyReader.load(request) { [weak self] result in
            guard let self, self.isConnected, self.activeGameID == nil else { return }
            switch result {
            case .success(let challenges):
                // Retain the existing empty-list safeguard until live lobby semantics are verified.
                if !challenges.isEmpty { self.finalizeLobbySync(challenges) }
            case .failure(let error):
                NSLog("[OGS-REST] Lobby refresh discarded: \(error.localizedDescription)")
            }
        }
    }
}


/// Persists only OGS cookies for this separately identified review app. Passwords
/// and JWTs are not stored. The server must validate the session on every launch.
final class OGSReviewSessionStore {
    let fileURL: URL
    init(fileURL: URL) { self.fileURL = fileURL }

    static func defaultStore() -> OGSReviewSessionStore {
        // UI probes have their own bundle ID and must never borrow a real login.
        let identifier = Bundle.main.bundleIdentifier ?? "com.davemarvit.SGFPlayerClean.review-session-probe"
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return OGSReviewSessionStore(fileURL: root.appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("SessionCookies.plist"))
    }

    private func isOGSCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "online-go.com" || domain.hasSuffix(".online-go.com")
    }

    func save(_ cookies: [HTTPCookie]) throws {
        let records = cookies.filter { isOGSCookie($0) && ($0.expiresDate == nil || $0.expiresDate! > Date()) }
            .compactMap { cookie -> [String: Any]? in
                guard let properties = cookie.properties else { return nil }
                return Dictionary(uniqueKeysWithValues: properties.map { key, value in
                    (key.rawValue, (value as? URL)?.absoluteString as Any? ?? value)
                })
            }
        let data = try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)
        let directory = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // The directory is private before the atomic write creates a replacement file.
        try data.write(to: fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func load() throws -> [HTTPCookie] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: fileURL), options: [], format: nil)
        guard let records = object as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        return records.compactMap { record in
            let properties = Dictionary(uniqueKeysWithValues: record.map { (HTTPCookiePropertyKey($0.key), $0.value) })
            guard let cookie = HTTPCookie(properties: properties), isOGSCookie(cookie),
                  cookie.expiresDate == nil || cookie.expiresDate! > Date() else { return nil }
            return cookie
        }
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
}
