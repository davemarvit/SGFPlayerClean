import Foundation
import Combine

/// The server owns online history. A move is sent once and displayed only after its echo.
@MainActor final class TabletOnline: ObservableObject {
    let client: OGSClient
    let chat: OGSGameViewModel
    private weak var game: TabletGame?
    @Published private(set) var loadedGameID: Int?
    @Published private(set) var awaitingMove = false
    @Published var busy = false
    @Published var message: String?
    @Published var showLobby = true
    @Published var browsingObservedGames = false
    @Published private(set) var blackRankLabel = "Rank unavailable"
    @Published private(set) var whiteRankLabel = "Rank unavailable"

    func playerLabel(_ color: Stone) -> String {
        guard let id = client.activeGameID, loadedGameID == id else { return "Loading player…" }
        let name = color == .black ? client.blackPlayerName : client.whitePlayerName
        let rank = color == .black ? blackRankLabel : whiteRankLabel
        return "\(name ?? "Name unavailable") (\(rank))"
    }
    private func updatePlayerRanks(_ data: [String: Any], gameID: Int) {
        let players = data["players"] as? [String: Any]
        let listed = client.observedGames.first { $0.id == gameID }
        func rank(_ color: String, listedRank: String?) -> String {
            let player = players?[color] as? [String: Any]
            let hasRank = player?["ranking"] != nil || player?["rank"] != nil || player?["ratings"] != nil
            let value = hasRank ? OGSObservedGame.rank(player).label : (listedRank ?? "?")
            return value == "?" ? "Rank unavailable" : value
        }
        blackRankLabel = rank("black", listedRank: listed?.blackRank)
        whiteRankLabel = rank("white", listedRank: listed?.whiteRank)
    }
    private var subscriptions = Set<AnyCancellable>()
    private var moveTimeout: Task<Void, Never>?
    private var submittedAtMove: Int?
    private var foreground = true
    private var sessionGeneration = UUID()

    init(game: TabletGame, client: OGSClient = OGSClient()) {
        self.game = game; self.client = client
        chat = OGSGameViewModel(ogsClient: client, player: game.player, timeControl: TimeControlManager())
        client.observationOnly = false
        client.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.objectWillChange.send(); self?.game?.objectWillChange.send()
        }.store(in: &subscriptions)
        client.$isAuthenticated.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] authenticated in
            guard let self, authenticated, self.foreground, self.game?.isOnline == true else { return }
            self.client.connect()
        }.store(in: &subscriptions)
        client.$isSocketAuthenticated.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] ready in
            guard let self, self.game?.isOnline == true else { return }
            if ready {
                if let id = self.client.activeGameID {
                    self.client.isReconcilingMoves = true
                    self.client.connectToGame(gameID: id)
                    self.client.requestMoveResync()
                    if self.showLobby { self.refreshBrowser() }
                } else { self.refreshBrowser() }
            } else {
                self.game?.selectedPoint = nil
                if self.client.activeGameID != nil { self.client.isReconcilingMoves = true }
            }
        }.store(in: &subscriptions)
        client.$phase.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] phase in
            if phase != "play" { self?.game?.selectedPoint = nil }
        }.store(in: &subscriptions)
        client.$activeGameID.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] id in
            guard let self, self.game?.isOnline == true, let id, self.loadedGameID != id else { return }
            self.game?.selectedPoint = nil
            self.showLobby = false
            self.game?.title = "OGS game \(id)"
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Notification.Name("OGSGameDataReceived"))
            .sink { [weak self] in self?.receiveSnapshot($0) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Notification.Name("OGSMoveReceived"))
            .sink { [weak self] in self?.receiveMove($0) }.store(in: &subscriptions)
    }

    var canMove: Bool {
        guard let game, game.isOnline, let id = client.activeGameID else { return false }
        return foreground && loadedGameID == id && client.canPlayMoves && !awaitingMove &&
            game.player.currentIndex == game.player.maxIndex && game.player.turn == client.playerColor
    }
    var status: String {
        if !client.isAuthenticated { return "Sign in to Online-Go.com" }
        if !client.isSocketAuthenticated { return client.connectionStatus == "Connected" ? "Authenticating…" : client.connectionStatus }
        guard client.activeGameID != nil else { return "Choose a game in the OGS lobby" }
        if client.isReconcilingMoves || loadedGameID != client.activeGameID { return "Refreshing game…" }
        if client.isGameFinished { return client.activeGameResult?.title ?? "Game finished" }
        if client.isScoringPhase { return "Review scoring" }
        if awaitingMove { return "Waiting for OGS to confirm your move…" }
        if !client.isGameParticipant { return "Spectating" }
        return canMove ? "Your turn" : "Opponent’s turn"
    }
    var territory: [BoardPosition: Stone] {
        guard client.showsScoringMarks, let summary = client.scoringDisplaySummary, let size = game?.player.board.size else { return [:] }
        var result: [BoardPosition: Stone] = [:]
        for (color, text) in [(Stone.black, summary.black.scoringPositions), (.white, summary.white.scoringPositions)] {
            if let text, let points = OGSScoring.decodePositions(text, width: size, height: size) { for point in points { result[point] = color } }
        }
        return result
    }
    var deadStones: Set<BoardPosition> { client.showsScoringMarks ? client.removedStones : [] }

    func start(observing: Bool = false) {
        foreground = true
        client.observationOnly = observing
        browsingObservedGames = observing
        showLobby = true
        if client.isAuthenticated { client.connect() }
        if client.isSocketAuthenticated { refreshBrowser() }
    }
    func browse(observing: Bool) {
        browsingObservedGames = observing
        showLobby = true
        refreshBrowser()
    }
    func refreshBrowser() {
        guard client.isSocketAuthenticated else { return }
        if browsingObservedGames { client.refreshObservedGames() }
        else if client.activeGameID == nil { client.refreshChallengeLobby() }
    }
    func login(username: String, password: String) {
        guard !busy else { return }
        busy = true; message = nil
        let generation = sessionGeneration
        client.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password) { [weak self] success, error in
            guard let self, self.sessionGeneration == generation else { return }
            self.busy = false
            self.message = success ? nil : error
            if success, self.foreground, self.game?.isOnline == true { self.client.connect() }
        }
    }
    func join(_ id: Int, observing: Bool = false) {
        guard id > 0, client.isSocketAuthenticated, game?.isOnline == true, !busy else { return }
        clearPendingMove()
        client.leaveViewedGame()
        client.observationOnly = observing
        if observing { client.stopChallengeKeepAlive() }
        loadedGameID = nil
        game?.player.load(game: SGFGame()); game?.selectedPoint = nil
        client.activeGameID = id; client.isReconcilingMoves = true
        game?.title = "OGS game \(id)"; showLobby = false; message = nil
        client.connectToGame(gameID: id)
        client.requestMoveResync()
    }
    func lobby() {
        clearPendingMove(); client.leaveViewedGame(); loadedGameID = nil
        game?.player.load(game: SGFGame()); game?.selectedPoint = nil; game?.title = "Online play"
        client.observationOnly = false; browsingObservedGames = false
        showLobby = true; client.refreshChallengeLobby()
    }
    func accept(_ challenge: OGSChallenge) {
        guard client.isSocketAuthenticated, !busy else { return }
        client.observationOnly = false
        busy = true; message = nil
        let generation = sessionGeneration
        client.acceptChallenge(challengeID: challenge.id) { [weak self] id, error in
            guard let self, self.sessionGeneration == generation else { return }
            self.busy = false
            if let id { self.client.myActiveGames.insert(id); self.join(id) }
            else { self.message = error?.localizedDescription ?? "OGS did not return a game. Refresh the lobby before trying again." }
        }
    }
    func create(_ setup: ChallengeSetup) {
        guard !busy, client.isSocketAuthenticated else { return }
        client.observationOnly = false
        busy = true; message = nil
        let generation = sessionGeneration
        client.createChallenge(setup: setup) { [weak self] success, error in
            guard let self, self.sessionGeneration == generation else { return }
            self.busy = false
            self.message = success ? "Challenge posted. Keep this app open while waiting for an opponent." : error
        }
    }
    func pick(_ point: BoardPosition) {
        guard let game, loadedGameID == client.activeGameID else { return }
        if client.canEditScore, foreground, let id = client.activeGameID {
            let group = game.player.getGroup(at: point)
            if !group.isEmpty { client.sendRemovedStones(gameID: id, stones: OGSScoring.encodePositions(group), removed: !client.removedStones.contains(point)) }
            return
        }
        guard canMove, game.player.moveRejection(color: game.player.turn, x: point.col, y: point.row) == nil else { game.selectedPoint = nil; return }
        game.selectedPoint = point
    }
    func play(pass: Bool) {
        guard canMove, let game, let id = client.activeGameID, pass || game.selectedPoint != nil else { return }
        let point = pass ? nil : game.selectedPoint
        guard game.player.moveRejection(color: game.player.turn, x: point?.col ?? -1, y: point?.row ?? -1) == nil else { return }
        submittedAtMove = game.player.maxIndex
        awaitingMove = true; game.selectedPoint = nil
        if pass { client.sendPass(gameID: id) }
        else if let point { client.sendMove(gameID: id, x: point.col, y: point.row) }
        moveTimeout?.cancel()
        moveTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.awaitingMove, self.client.activeGameID == id else { return }
            self.message = "The move has not been confirmed. Refreshing the board before you can play again."
            self.client.isReconcilingMoves = true
            self.client.requestMoveResync()
        }
    }
    private func clearPendingMove() { moveTimeout?.cancel(); moveTimeout = nil; awaitingMove = false; submittedAtMove = nil }

    func receiveSnapshot(_ notification: Notification) {
        guard let game, game.isOnline, client.acceptsGameNotification(notification),
              let info = notification.userInfo, let data = info["gameData"] as? [String: Any],
              let id = client.activeGameID,
              (client.robustInt(data["game_id"]) ?? client.robustInt(data["id"]) ?? id) == id else { return }
        guard let snapshot = OGSGameSnapshot(data), snapshot.game.boardSize <= 25 else {
            client.isReconcilingMoves = true
            message = "This game has unsupported or incomplete board data. Try refreshing."
            return
        }
        let changedGame = loadedGameID != id
        switch game.player.reconcileOnlineSnapshot(snapshot, recovery: info["reconcileMoves"] as? Bool == true, newGame: loadedGameID != id) {
        case .stale: return
        case .needsResync: client.requestMoveResync(); return
        case .applied: break
        }
        loadedGameID = id
        if changedGame { showLobby = false }
        client.applyAcceptedGameData(data)
        updatePlayerRanks(data, gameID: id)
        client.isReconcilingMoves = false; client.isRequestingUndo = false
        if client.isAccountGameParticipant && !client.isGameFinished { client.myActiveGames.insert(id) }
        if !awaitingMove || game.player.maxIndex > (submittedAtMove ?? -1) || info["reconcileMoves"] as? Bool == true { clearPendingMove() }
        message = nil; game.selectedPoint = nil
        updateBoard()
    }
    func receiveMove(_ notification: Notification) {
        guard let game, game.isOnline, client.acceptsGameNotification(notification), let info = notification.userInfo else { return }
        guard loadedGameID == client.activeGameID, loadedGameID != nil,
              let number = client.robustInt(info["move_number"]), number > 0 else { client.requestMoveResync(); return }
        if let id = client.robustInt(info["game_id"]), id != loadedGameID { return }
        let coordinates: (Int, Int)?
        if let move = info["move"] as? [Any], move.count >= 2, let x = client.robustInt(move[0]), let y = client.robustInt(move[1]) { coordinates = (x,y) }
        else if let move = info["move"] as? String { coordinates = ["..","pass"].contains(move) ? (-1,-1) : SGFCoordinates.parse(move) }
        else { coordinates = nil }
        guard let (x,y) = coordinates else { client.requestMoveResync(); return }
        let color: Stone
        if let id = client.robustInt(info["player_id"]) {
            if id == client.blackPlayerID { color = .black }
            else if id == client.whitePlayerID { color = .white }
            else { client.requestMoveResync(); return }
        } else { color = game.player.playerToMove(at: number - 1) }
        switch game.player.applyOnlineMove(color: color, x: x, y: y, moveNumber: number) {
        case .needsResync: client.requestMoveResync()
        case .duplicate: game.player.recordOnlineVersion(client.robustInt(info["state_version"]))
        case .applied:
            game.player.recordOnlineVersion(client.robustInt(info["state_version"]))
            clearPendingMove(); message = nil; game.selectedPoint = nil; updateBoard()
        }
    }
    private func updateBoard() {
        guard let game else { return }
        client.currentPlayerID = game.player.turn == .black ? client.blackPlayerID : client.whitePlayerID
        client.blackCaptures = game.player.capturesByBlack; client.whiteCaptures = game.player.capturesByWhite
        game.title = "\(client.blackPlayerName ?? "Black") vs \(client.whitePlayerName ?? "White")"
        game.positionID = UUID(); game.objectWillChange.send()
    }
    func suspend() {
        foreground = false; game?.selectedPoint = nil
        if client.activeGameID != nil { client.isReconcilingMoves = true }
        client.disconnect()
    }
    func resume() {
        foreground = true
        guard game?.isOnline == true else { return }
        let generation = sessionGeneration
        client.fetchUserConfig { [weak self] success, error in
            guard let self, self.foreground, self.game?.isOnline == true, self.sessionGeneration == generation else { return }
            if success { self.client.connect() }
            else { self.message = error }
        }
    }
    func reconnect() { suspend(); resume() }
    func leave() {
        sessionGeneration = UUID(); busy = false
        clearPendingMove(); client.leaveViewedGame(); loadedGameID = nil
        client.observationOnly = true; client.stopChallengeKeepAlive()
        // Keep account notifications while foregrounded, so local AI cannot assist an ongoing game.
        showLobby = false
    }
    func reviewFinishedGame() {
        guard let id = client.activeGameID, client.isGameFinished, !busy else { return }
        busy = true
        let generation = sessionGeneration
        client.fetchSGFDownload(gameID: id) { [weak self] data, filename in
            DispatchQueue.main.async {
                guard let self, self.sessionGeneration == generation, self.client.activeGameID == id, let game = self.game else { return }
                self.busy = false
                guard let data, let text = String(data: data, encoding: .utf8), (try? SGFParser.parse(text: text)) != nil else { self.message = "Could not download this game's SGF. Try again."; return }
                game.leaveOnline()
                do { try game.load(text: text, name: filename.map { ($0 as NSString).deletingPathExtension } ?? "OGS game \(id)") }
                catch { game.error = error.localizedDescription }
            }
        }
    }
    func logout() {
        leave(); client.logout(); client.observationOnly = false; showLobby = true; message = nil
        game?.player.load(game: SGFGame()); game?.title = "Online play"
    }
}
