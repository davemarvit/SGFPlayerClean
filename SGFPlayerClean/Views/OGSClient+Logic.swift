//
//  OGSClient+Logic.swift
//  SGFPlayerClean
//
//  Part 3: Logic Extension (v3.73)
//  - v3.73: Fixes Undo Self-ID logic (checks Strings too).
//  - Handles 'latency' to reduce log spam.
//

import Foundation

extension OGSClient {

    internal func handleSocketRawMessage(_ text: String) {
        if text == "3" { return }
        if text.hasPrefix("42") {
            parseEventMessage(String(text.dropFirst(2)))
        }
    }

    internal func parseEventMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 2,
              let eventName = json[0] as? String else { return }

        // Filter noisy events
        if !eventName.contains("clock") && !eventName.contains("latency") {
            print("OGS: ⚡️ Event: [\(eventName)]")
        }

        switch eventName {
        case "authenticate":
            if let payload = json[1] as? [String: Any], let success = payload["success"] as? Bool, success {
                print("OGS: 🔓 Socket Authentication CONFIRMED.")
                self.isSocketAuthenticated = true
                if let pendingID = self.activeGameID {
                    print("OGS: 🔄 Re-sending Join Request for \(pendingID)")
                    self.joinGame(gameID: pendingID)
                }
            }
            
        case "active_game":
            if let gameData = json[1] as? [String: Any] {
                // Keep Komi/Turn updated
                if let k = getDouble(gameData["komi"]) {
                    DispatchQueue.main.async { self.komi = k }
                }
                if let playerToMove = getInt(gameData["player_to_move"]) {
                    DispatchQueue.main.async { self.currentPlayerID = playerToMove }
                }
                if let auth = getString(gameData["auth"]) ?? getString(gameData["game_auth"]) {
                    DispatchQueue.main.async { self.activeGameAuth = auth }
                }
            }
            
        case let name where name.contains("/gamedata"):
            print("OGS: 🕵️‍♂️ Matched gamedata event!")
            DispatchQueue.main.async { self.cancelJoinRetry() }
            if let gameData = json[1] as? [String: Any] { handleGameData(gameData) }
            
        case let name where name.contains("/clock"):
            if let clockData = json[1] as? [String: Any] { handleClock(clockData) }
            
        case let name where name.contains("/move"):
            if let moveData = json[1] as? [String: Any] { handleMove(moveData) }
            
        case let name where name.contains("/latency"):
            // No-op to keep logs clean
            break
            
        // 1. Handle Incoming Undo Request (Robust Parsing)
        case let name where name.contains("/undo_requested"):
            if let payload = json[1] as? [String: Any] {
                let reqMove = getInt(payload["move_number"]) ?? 0
                // Robust ID check: Try Int, then String conversion
                let requesterID = getInt(payload["player_id"]) ?? Int(getString(payload["player_id"]) ?? "-1") ?? -1
                let myID = self.playerID ?? -999
                
                print("OGS: 🧐 Undo Req - Requester: \(requesterID), Me: \(myID)")
                
                // CHECK: Did I send this?
                if requesterID == myID {
                    print("OGS: ↩️ Ignoring my own undo request echo.")
                    return
                }
                
                print("OGS: 📨 Undo Requested by Opponent (Move: \(reqMove))")
                
                // Determine opponent name
                let name = (self.playerColor == .black) ? (self.whitePlayerName ?? "Opponent") : (self.blackPlayerName ?? "Opponent")
                
                DispatchQueue.main.async {
                    self.undoRequestedUsername = name
                    self.undoRequestedMoveNumber = reqMove
                }
            }
            
        // 2. Handle Undo Accepted
        case let name where name.contains("/undo_accepted"):
            print("OGS: ↩️ Undo Accepted. Waiting 1.5s before reload...")
            DispatchQueue.main.async { self.undoRequestedUsername = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let id = self.activeGameID {
                    print("OGS: 🔄 Reloading Game State now.")
                    self.joinGame(gameID: id)
                }
            }
            
        case "seekgraph/global":
            if let items = json[1] as? [[String: Any]] { handleSeekGraph(items) }
            
        case "automatch/start":
             if let data = json[1] as? [String: Any], let gameId = getInt(data["game_id"]) {
                 DispatchQueue.main.async {
                     self.activeGameID = gameId
                     self.joinGame(gameID: gameId)
                 }
             }
            
        default: break
        }
    }

    internal func handleGameData(_ data: [String: Any]) {
        print("OGS: 🏁 PROCESSING GAME DATA")
        
        // 1. IDs & Turn
        if let initialPlayer = getString(data["initial_player"]) {
            let pid = (initialPlayer == "black") ? getInt(data["black_player_id"]) : getInt(data["white_player_id"])
            if let pid = pid { DispatchQueue.main.async { self.currentPlayerID = pid } }
        }
        
        let myID = self.playerID ?? -1
        let blackID = getInt(data["black_player_id"]) ?? -1
        let whiteID = getInt(data["white_player_id"]) ?? -1
        let auth = getString(data["auth"]) ?? getString(data["game_auth"])
        
        // 2. Komi
        var komiVal = getDouble(data["komi"])
        if komiVal == nil, let game = data["game"] as? [String: Any] { komiVal = getDouble(game["komi"]) }
        
        // 3. Player Details
        var bName: String? = nil, wName: String? = nil
        var bRank: Double? = nil, wRank: Double? = nil
        
        if let players = data["players"] as? [String: Any] {
            if let black = players["black"] as? [String: Any] {
                bName = getString(black["username"])
                bRank = getDouble(black["ranking"]) ?? getDouble(black["rank"])
            }
            if let white = players["white"] as? [String: Any] {
                wName = getString(white["username"])
                wRank = getDouble(white["ranking"]) ?? getDouble(white["rank"])
            }
        }
        
        // 4. Time Control
        var staticPeriodTime: Double? = nil
        var staticPeriods: Int? = nil
        
        if let tc = data["time_control"] as? [String: Any] {
            staticPeriodTime = getDouble(tc["period_time"])
            staticPeriods = getInt(tc["periods"])
        } else if let tcp = data["time_control_parameters"] as? [String: Any] {
            staticPeriodTime = getDouble(tcp["period_time"])
            staticPeriods = getInt(tcp["periods"])
        }

        DispatchQueue.main.async {
            self.blackPlayerID = blackID; self.whitePlayerID = whiteID
            self.blackPlayerName = bName; self.whitePlayerName = wName
            self.blackPlayerRank = bRank; self.whitePlayerRank = wRank
            self.komi = komiVal
            self.activeGameAuth = auth
            
            if blackID == myID { self.playerColor = .black }
            else if whiteID == myID { self.playerColor = .white }
            else { self.playerColor = nil }
            
            if let pt = staticPeriodTime {
                self.blackPeriodTime = pt
                self.whitePeriodTime = pt
            }
            if let p = staticPeriods {
                self.blackPeriodsRemaining = p
                self.whitePeriodsRemaining = p
            }
        }
        
        // 5. Clock
        if let clock = data["clock"] as? [String: Any] { handleClock(clock) }
        
        let moves = (data["moves"] as? [[Any]]) ?? []
        NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["moves": moves, "gameData": data])
    }
    
    internal func handleClock(_ data: [String: Any]) {
        DispatchQueue.main.async {
            if let cp = self.getInt(data["current_player"]) {
                if self.currentPlayerID != cp { self.currentPlayerID = cp }
            }
            
            self.clockTimer?.invalidate()
            
            func extractClockInfo(_ key: String) -> (time: Double?, periods: Int?, periodTime: Double?) {
                var t: Double? = nil, p: Int? = nil, pt: Double? = nil
                
                if let val = self.getDouble(data["\(key)_time"]) { t = val }
                
                if let dict = data[key] as? [String: Any] ?? data["\(key)_time"] as? [String: Any] {
                    if let val = self.getDouble(dict["thinking_time"]) { t = val }
                    else if let val = self.getDouble(dict["time_left"]) { t = val }
                    
                    p = self.getInt(dict["periods"])
                    pt = self.getDouble(dict["period_time"])
                }
                return (t, p, pt)
            }
            
            let wInfo = extractClockInfo("white")
            if let t = wInfo.time { self.whiteTimeRemaining = t }
            if let p = wInfo.periods { self.whitePeriodsRemaining = p }
            if let pt = wInfo.periodTime { self.whitePeriodTime = pt }
            
            let bInfo = extractClockInfo("black")
            if let t = bInfo.time { self.blackTimeRemaining = t }
            if let p = bInfo.periods { self.blackPeriodsRemaining = p }
            if let pt = bInfo.periodTime { self.blackPeriodTime = pt }
            
            self.beginClockCountdown()
        }
    }
    
    private func beginClockCountdown() {
        self.clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let curr = self.currentPlayerID else { return }
            
            if curr == self.blackPlayerID, let t = self.blackTimeRemaining, t > 0 {
                self.blackTimeRemaining = t - 1
            } else if curr == self.whitePlayerID, let t = self.whiteTimeRemaining, t > 0 {
                self.whiteTimeRemaining = t - 1
            }
        }
    }
    
    internal func handleMove(_ data: [String: Any]) {
        var x = -1, y = -1
        if let arr = data["move"] as? [Any], arr.count >= 2, let mx = getInt(arr[0]), let my = getInt(arr[1]) { x = mx; y = my }
        else if let s = data["move"] as? String, let c = SGFCoordinates.fromSGF(s) { x = c.0; y = c.1 }
        
        let pid = getInt(data["player_id"]) ?? -1
        NotificationCenter.default.post(name: NSNotification.Name("OGSMoveReceived"), object: nil, userInfo: ["x": x, "y": y, "player_id": pid])
    }
    
    internal func handleSeekGraph(_ items: [[String: Any]]) {
        var toUpsert: [OGSChallenge] = []
        var removeIDs: Set<Int> = []
        
        for item in items {
            if let gameStarted = item["game_started"] as? Bool, gameStarted, let realGameID = getInt(item["game_id"]) {
                let myID = self.playerID ?? -1
                let blackID = getInt((item["black"] as? [String:Any])?["id"]) ?? -1
                let whiteID = getInt((item["white"] as? [String:Any])?["id"]) ?? -1
                
                if myID != -1 && (blackID == myID || whiteID == myID) {
                    print("OGS: 🚀 This is MY game. Switching to Real ID: \(realGameID)")
                    DispatchQueue.main.async {
                        self.activeGameID = realGameID
                        self.joinGame(gameID: realGameID)
                    }
                }
                continue
            }
            if let del = item["delete"] as? Bool, del {
                if let id = getInt(item["challenge_id"]) { removeIDs.insert(id) }
                continue
            }
            guard let id = getInt(item["challenge_id"]), let user = getString(item["username"]) else { continue }
            
            let rank = getDouble(item["rank"]) ?? 0.0
            let w = getInt(item["width"]) ?? 19
            let h = getInt(item["height"]) ?? 19
            var tc = "Unknown"
            if let t = getString(item["time_control"]) { tc = t.capitalized }
            
            let challenger = ChallengerInfo(id: 0, username: user, ranking: rank, professional: false)
            let game = GameInfo(id: 0, name: nil, width: w, height: h, rules: "japanese", ranked: true, handicap: 0, komi: nil, timeControl: tc, timeControlParameters: nil, disableAnalysis: false, pauseOnWeekends: false, black: nil, white: nil, started: nil, blackLost: false, whiteLost: false, annulled: false)
            toUpsert.append(OGSChallenge(id: id, challenger: challenger, game: game, challengerColor: "auto", minRanking: 0, maxRanking: 0, created: nil))
        }
        
        DispatchQueue.main.async {
            if !removeIDs.isEmpty { self.availableGames.removeAll { removeIDs.contains($0.id) } }
            for c in toUpsert {
                if let idx = self.availableGames.firstIndex(where: { $0.id == c.id }) { self.availableGames[idx] = c }
                else { self.availableGames.append(c) }
            }
        }
    }
    
    // MARK: - Helpers
    internal func getInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let d = value as? Double { return Int(d) }
        return nil
    }
    internal func getDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }
    internal func getString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        if let d = value as? Double { return String(d) }
        return nil
    }
}
