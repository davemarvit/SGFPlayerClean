import Foundation
import SwiftUI

/// Manages OGS game state and game management logic
/// Handles game loading, polling, player info, and game data processing
class OGSGameViewModel: ObservableObject {
    // MARK: - Published Properties

    // Game metadata
    @Published var blackName: String?
    @Published var whiteName: String?
    @Published var blackRank: String?
    @Published var whiteRank: String?
    @Published var komi: String?
    @Published var ruleset: String?
    @Published var blackCaptured: Int = 0
    @Published var whiteCaptured: Int = 0

    // Polling state
    private var pollingTimer: Timer?
    private var lastMoveCount: Int = 0
    private var backoffDelay: TimeInterval = 1.0
    private var pollingInterval: TimeInterval = 1.0
    private var isThrottled: Bool = false

    // MARK: - Dependencies

    private let ogsClient: OGSClient
    private let player: SGFPlayer
    private let timeControl: TimeControlManager

    // MARK: - Initialization

    init(ogsClient: OGSClient, player: SGFPlayer, timeControl: TimeControlManager) {
        self.ogsClient = ogsClient
        self.player = player
        self.timeControl = timeControl

        NSLog("OGSGameVM: 🎮 OGSGameViewModel initialized")
    }

    deinit {
        stopPolling()
    }

    // MARK: - Public Methods

    /// Handle incoming OGS game data notification
    func handleGameData(_ notification: Notification) {
        NSLog("OGSGameVM: 🎮 Received OGSGameDataReceived notification")
        guard let userInfo = notification.userInfo,
              let moves = userInfo["moves"] as? [[Any]],
              let gameID = userInfo["gameID"] as? Int,
              let gameData = userInfo["gameData"] as? [String: Any] else {
            NSLog("OGSGameVM: ❌ Invalid game data in notification")
            return
        }

        NSLog("OGSGameVM: 🎮 Loading OGS game \(gameID) with \(moves.count) moves")

        // IMPORTANT: Stop any existing polling timer from a previous game
        // Otherwise the old timer will keep fetching the old game's data
        if let currentGameID = ogsClient.currentGameID, currentGameID != gameID {
            NSLog("OGSGameVM: 🔄 Switching from game \(currentGameID) to game \(gameID) - stopping old polling")
            stopPolling()
            // Reset state from previous game
            lastMoveCount = 0
            timeControl.reset()
            NSLog("OGSGameVM: 🔄 Reset time control for new game")
        }

        // Extract komi and ruleset from game data
        if let komiValue = gameData["komi"] as? Double {
            komi = String(format: "%.1f", komiValue)
            NSLog("OGSGameVM: 🎮 Komi: \(komi ?? "nil")")
        } else if let komiString = gameData["komi"] as? String {
            komi = komiString
            NSLog("OGSGameVM: 🎮 Komi (string): \(komi ?? "nil")")
        }

        if let rules = gameData["rules"] as? String {
            ruleset = rules
            NSLog("OGSGameVM: 🎮 Rules: \(ruleset ?? "nil")")
        }

        // Check if this is a new move (move count increased)
        if moves.count > lastMoveCount {
            NSLog("OGSGameVM: 🎯 New moves detected! Previous: \(lastMoveCount), Current: \(moves.count)")
            lastMoveCount = moves.count
        } else if lastMoveCount == 0 {
            // First load
            lastMoveCount = moves.count
        }

        // Create a new SGF game from the OGS moves
        let boardSize = userInfo["boardSize"] as? Int ?? 19
        NSLog("OGSGameVM: 🎮 Board size: \(boardSize)")
        var sgfContent = "(;GM[1]FF[4]SZ[\(boardSize)]"

        // Add player names if available
        if let blackPlayerName = userInfo["blackName"] as? String,
           let whitePlayerName = userInfo["whiteName"] as? String {
            sgfContent += "PB[\(blackPlayerName)]PW[\(whitePlayerName)]"
        }

        // Add handicap stones
        let handicap = userInfo["handicap"] as? Int ?? 0
        NSLog("OGSGameVM: 🎮 Handicap value from OGS: \(handicap)")

        if handicap > 0 {
            sgfContent += "HA[\(handicap)]"

            // Standard handicap positions for 19x19 board only
            if boardSize != 19 {
                NSLog("OGSGameVM: ⚠️ Handicap on non-19x19 board (\(boardSize)x\(boardSize)) - positions may be incorrect")
            }

            let handicapPositions: [[String]] = [
                [],  // 0 handicap
                [],  // 1 handicap (not used)
                ["pd", "dp"],  // 2 handicap
                ["pd", "dp", "pp"],  // 3 handicap
                ["pd", "dp", "pp", "dd"],  // 4 handicap
                ["pd", "dp", "pp", "dd", "jj"],  // 5 handicap
                ["pd", "dp", "pp", "dd", "pj", "dj"],  // 6 handicap
                ["pd", "dp", "pp", "dd", "pj", "dj", "jj"],  // 7 handicap
                ["pd", "dp", "pp", "dd", "pj", "dj", "jd", "jp"],  // 8 handicap
                ["pd", "dp", "pp", "dd", "pj", "dj", "jd", "jp", "jj"]  // 9 handicap
            ]

            if handicap < handicapPositions.count {
                let positions = handicapPositions[handicap]
                NSLog("OGSGameVM: 🎮 Adding \(positions.count) handicap stones at positions: \(positions)")
                if !positions.isEmpty {
                    sgfContent += "AB"
                    for pos in positions {
                        sgfContent += "[\(pos)]"
                    }
                    NSLog("OGSGameVM: 🎮 Added AB property to SGF")
                }
            } else {
                NSLog("OGSGameVM: ⚠️ Handicap \(handicap) is out of range")
            }
        } else {
            NSLog("OGSGameVM: 🎮 No handicap stones (handicap = 0)")
        }

        // Add moves
        var currentColor: Stone = handicap > 0 ? .white : .black

        for move in moves {
            guard move.count >= 2,
                  let x = move[0] as? Int,
                  let y = move[1] as? Int else { continue }

            // Convert to SGF notation
            let sgfMove = OGSClient.positionToSGF(x: x, y: y)
            let moveTag = currentColor == .black ? "B" : "W"
            sgfContent += ";\(moveTag)[\(sgfMove)]"

            // Alternate colors
            currentColor = currentColor == .black ? .white : .black
        }

        sgfContent += ")"

        NSLog("OGSGameVM: 📝 Generated SGF (first 400 chars): \(sgfContent.prefix(400))...")

        // Parse and load the SGF
        if let tree = try? SGFParser.parse(text: sgfContent) {
            NSLog("OGSGameVM: ✅ Successfully parsed OGS game, loading...")
            let game = SGFGame.from(tree: tree)
            NSLog("OGSGameVM: 🎮 Game has \(game.setup.count) setup stones: \(game.setup)")
            NSLog("OGSGameVM: 🎮 Game has \(game.moves.count) moves")

            // Post notification for ContentView3D to update stones
            NotificationCenter.default.post(
                name: NSNotification.Name("OGSGameLoaded"),
                object: nil,
                userInfo: [
                    "game": game,
                    "moveCount": moves.count,
                    "handicap": handicap
                ]
            )

            // Determine whose turn it is now
            var currentTurn: Stone = handicap > 0 ? .white : .black
            for _ in 0..<moves.count {
                currentTurn = currentTurn == .black ? .white : .black
            }

            NSLog("OGSGameVM: 🕐 After \(moves.count) moves (handicap: \(handicap)), it's \(currentTurn == .black ? "Black" : "White")'s turn")
            timeControl.switchToPlayer(currentTurn)

            // Always restart polling with the new game ID
            stopPolling()
            startPolling(gameID: gameID)
        } else {
            NSLog("OGSGameVM: ❌ Failed to parse SGF from OGS data")
        }
    }

    /// Handle incoming OGS move notification
    func handleMove(_ notification: Notification) {
        NSLog("OGSGameVM: 🎯 Received OGSMoveReceived notification")
        guard let userInfo = notification.userInfo,
              let x = userInfo["x"] as? Int,
              let y = userInfo["y"] as? Int,
              let isPass = userInfo["isPass"] as? Bool else {
            NSLog("OGSGameVM: ❌ Invalid move data in notification")
            return
        }

        if isPass {
            NSLog("OGSGameVM: 🎯 Opponent passed - reloading game to get updated move list")
        } else {
            NSLog("OGSGameVM: 🎯 Opponent played at (\(x), \(y)) - reloading game to get updated move list")
        }

        // Re-fetch the game data to get all moves including the new one
        if let gameID = ogsClient.currentGameID {
            NSLog("OGSGameVM: 🎯 Re-fetching game \(gameID) to include new move")
            ogsClient.joinGame(gameID: gameID)
        } else {
            NSLog("OGSGameVM: ❌ No current game ID to re-fetch")
        }
    }

    /// Handle incoming OGS player info notification
    func handlePlayerInfo(_ notification: Notification) {
        guard let userInfo = notification.userInfo else {
            NSLog("OGSGameVM: ❌ No userInfo in OGSPlayerInfo notification")
            return
        }

        NSLog("OGSGameVM: 👥 Received OGSPlayerInfo notification")

        let wasInOGSMode = blackName != nil

        blackName = userInfo["blackName"] as? String
        whiteName = userInfo["whiteName"] as? String
        blackRank = userInfo["blackRank"] as? String
        whiteRank = userInfo["whiteRank"] as? String

        NSLog("OGSGameVM: 👥 Updated player info: \(blackName ?? "?") [\(blackRank ?? "?")] vs \(whiteName ?? "?") [\(whiteRank ?? "?")]")

        // When entering OGS game (first time blackName is set), notify
        if !wasInOGSMode && blackName != nil {
            NSLog("OGSGameVM: 🎮 Entering OGS game")
        }
    }

    /// Handle throttling notification from OGS
    func handleThrottling() {
        guard let gameID = ogsClient.currentGameID else {
            NSLog("OGSGameVM: ⚠️ Throttled but no current game ID")
            return
        }

        NSLog("OGSGameVM: ⚠️ Throttled! Stopping polling and backing off for \(backoffDelay)s")
        isThrottled = true
        stopPolling()

        // Wait for backoff delay, then resume with longer interval
        DispatchQueue.main.asyncAfter(deadline: .now() + backoffDelay) { [weak self] in
            guard let self = self else { return }

            NSLog("OGSGameVM: 🔄 Backoff period over, resuming polling...")

            // Double the backoff for next time (exponential backoff), cap at 60s
            self.backoffDelay = min(self.backoffDelay * 2, 60.0)

            // Resume polling with increased interval (at least 2.0s during backoff recovery)
            let newInterval = max(2.0, self.backoffDelay / 2)
            NSLog("OGSGameVM: 🔄 Resuming with interval \(newInterval)s, next backoff would be \(self.backoffDelay)s")

            self.isThrottled = false
            self.startPolling(gameID: gameID, interval: newInterval)

            // After successful polling for a while, reset backoff gradually
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
                guard let self = self else { return }
                if !self.isThrottled && self.backoffDelay > 1.0 {
                    // Gradually reduce backoff if we haven't been throttled
                    self.backoffDelay = max(1.0, self.backoffDelay / 2)
                    NSLog("OGSGameVM: 📉 Reducing backoff delay to \(self.backoffDelay)s after successful polling")
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Start polling OGS for game updates
    private func startPolling(gameID: Int, interval: TimeInterval? = nil) {
        let interval = interval ?? pollingInterval
        NSLog("OGSGameVM: ⏰ Starting OGS polling for game \(gameID) - checking every \(interval) second(s)")

        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            NSLog("OGSGameVM: 🔄 Polling OGS for updates to game \(gameID)...")
            self?.ogsClient.joinGame(gameID: gameID)
        }

        pollingInterval = interval
    }

    /// Stop polling OGS for game updates
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        NSLog("OGSGameVM: ⏰ Stopped OGS polling")
    }
}
