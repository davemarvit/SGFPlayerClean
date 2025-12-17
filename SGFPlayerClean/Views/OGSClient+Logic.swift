//
//  OGSClient+Logic.swift
//  SGFPlayerClean
//
//  v3.109: Strict Cleanup.
//  - FIX: Handles "game_started" events to remove challenges that have turned into active games.
//  - FIX: Removes challenges by Game ID when Challenge ID is missing in the deletion event.
//  - Prevents "Ghost" challenges that persist after play begins.
//

import Foundation

// MARK: - Intermediate Decodable Model
private struct OGSSocketChallenge: Decodable {
    let challenge_id: Int
    let user_id: Int
    let username: String
    let rank: Double?
    let pro: Int?
    let min_rank: Int?
    let max_rank: Int?
    
    let game_id: Int
    let name: String?
    let width: Int
    let height: Int
    let rules: String?
    let ranked: Bool?
    let handicap: Int?
    let komi: AnyDecodable?
    let challenger_color: String?
    let disable_analysis: Bool?
    let time_control: String?
    let time_control_parameters: TimeControlParams?
    let created: String?
    
    func toDomain() -> OGSChallenge {
        let challenger = ChallengerInfo(id: user_id, username: username, ranking: rank, professional: pro == 1)
        
        var komiStr: String? = nil
        if let k = komi?.value as? Double { komiStr = "\(k)" }
        else if let k = komi?.value as? String { komiStr = k }
        
        let game = GameInfo(
            id: game_id,
            name: name,
            width: width,
            height: height,
            rules: rules ?? "japanese",
            ranked: ranked ?? false,
            handicap: handicap ?? 0,
            komi: komiStr,
            timeControl: time_control,
            timeControlParameters: time_control_parameters,
            disableAnalysis: disable_analysis ?? false,
            started: nil
        )
        
        return OGSChallenge(
            id: challenge_id,
            challenger: challenger,
            game: game,
            challengerColor: challenger_color ?? "automatic",
            minRanking: min_rank ?? 30,
            maxRanking: max_rank ?? 30,
            created: created
        )
    }
}

private struct AnyDecodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) { value = x }
        else if let x = try? container.decode(Double.self) { value = x }
        else if let x = try? container.decode(String.self) { value = x }
        else if let x = try? container.decode(Bool.self) { value = x }
        else if container.decodeNil() { value = NSNull() }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown type") }
    }
}

extension OGSClient {
    
    func handleSocketRawMessage(_ text: String) {
        guard text.hasPrefix("42") else { return }
        let jsonStr = String(text.dropFirst(2))
        guard let data = jsonStr.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 2,
              let eventName = array[0] as? String else { return }
        
        let payload = array[1]
        
        if !eventName.contains("clock") && !eventName.contains("latency") && !eventName.contains("keepalive") {
            logTraffic("⚡️ Event: [\(eventName)]", direction: "⚡️")
        }
        
        // MARK: - Challenge Handlers
        
        if eventName == "seekgraph/global" {
            // print("OGS: 📡 Received SeekGraph Event.")
            if let list = payload as? [[String: Any]] { handleSeekGraphEvent(list) }
            return
        }
        
        if eventName == "challenge/keepalive" { return }
        
        // MARK: - Game Handlers
        
        if eventName.hasSuffix("/gamedata"), let d = payload as? [String: Any] {
            DispatchQueue.main.async { self.processGameData(payload: d) }
        }
        
        if eventName.hasSuffix("/move"), let d = payload as? [String: Any], let m = d["move"] as? [String: Any] {
            DispatchQueue.main.async { self.processMove(m) }
        }
        
        if eventName.hasSuffix("/undo_accepted") {
            DispatchQueue.main.async { NotificationCenter.default.post(name: NSNotification.Name("OGSUndoAccepted"), object: nil) }
        }
        
        if eventName.hasSuffix("/undo_requested"), let d = payload as? [String: Any] {
            if let reqID = d["player_id"] as? Int, reqID != self.playerID, let move = d["move_number"] as? Int {
                DispatchQueue.main.async {
                    self.undoRequestedUsername = "Opponent"
                    self.undoRequestedMoveNumber = move
                }
            }
        }
        
        if eventName.hasSuffix("/clock"), let d = payload as? [String: Any] {
            DispatchQueue.main.async { self.processClock(d) }
        }
    }
    
    // MARK: - Logic
    
    func handleSeekGraphEvent(_ list: [[String: Any]]) {
        DispatchQueue.global(qos: .userInitiated).async {
            
            // Initial dump detection
            let isFullDump = list.count > 10
            
            var gamesToAdd: [OGSChallenge] = []
            var challengeIdsToDelete: [Int] = []
            var gameIdsToDelete: [Int] = [] // Track Game IDs for removal (when started)
            
            for dict in list {
                // 1. Explicit Delete: { "challenge_id": 123, "delete": 1 }
                if let deleteFlag = dict["delete"] as? Int, deleteFlag == 1,
                   let id = dict["challenge_id"] as? Int {
                    challengeIdsToDelete.append(id)
                    continue
                }
                
                // 2. Game Started Event: { "game_started": true, "game_id": 456 }
                // This implies the challenge is over and should be removed.
                if let started = dict["game_started"] as? Bool, started == true,
                   let gid = dict["game_id"] as? Int {
                    gameIdsToDelete.append(gid)
                    // Note: These events usually don't contain challenge_id, so we must match by game_id
                    continue
                }
                
                // 3. New/Updated Challenge
                do {
                    let data = try JSONSerialization.data(withJSONObject: dict, options: [])
                    let socketChallenge = try JSONDecoder().decode(OGSSocketChallenge.self, from: data)
                    gamesToAdd.append(socketChallenge.toDomain())
                } catch {
                    // Ignore parsing errors for non-challenge objects
                }
            }
            
            DispatchQueue.main.async {
                if isFullDump {
                    print("OGS: 🔄 Full Dump Received. Loaded \(gamesToAdd.count) games.")
                    self.availableGames = gamesToAdd
                } else {
                    // --- Delta Update ---
                    
                    // A. Remove by Challenge ID
                    if !challengeIdsToDelete.isEmpty {
                        self.availableGames.removeAll { challengeIdsToDelete.contains($0.id) }
                    }
                    
                    // B. Remove by Game ID (Crucial for "Ghost" games that started)
                    if !gameIdsToDelete.isEmpty {
                        let countBefore = self.availableGames.count
                        self.availableGames.removeAll { gameIdsToDelete.contains($0.game.id) }
                        let countAfter = self.availableGames.count
                        if countBefore != countAfter {
                            print("OGS: 🧹 Removed \(countBefore - countAfter) challenges because games started.")
                        }
                    }
                    
                    // C. Add/Update
                    if !gamesToAdd.isEmpty {
                        var currentList = self.availableGames
                        for game in gamesToAdd {
                            if let idx = currentList.firstIndex(where: { $0.id == game.id }) {
                                currentList[idx] = game
                            } else {
                                currentList.insert(game, at: 0)
                            }
                        }
                        self.availableGames = currentList
                    }
                }
            }
        }
    }
    
    // Legacy delete handler
    func handleSeekGraphDelete(id: Int) {
        DispatchQueue.main.async {
            if let index = self.availableGames.firstIndex(where: { $0.id == id }) {
                self.availableGames.remove(at: index)
                print("OGS: ➖ Deleted challenge \(id)")
            }
        }
    }
    
    private func processGameData(payload: [String: Any]) {
        if let auth = payload["auth"] as? String { self.activeGameAuth = auth }
        if let players = payload["players"] as? [String: Any] {
            if let w = players["white"] as? [String: Any] {
                self.whitePlayerID = w["id"] as? Int
                self.whitePlayerName = w["username"] as? String
                self.whitePlayerRank = w["ranking"] as? Double
            }
            if let b = players["black"] as? [String: Any] {
                self.blackPlayerID = b["id"] as? Int
                self.blackPlayerName = b["username"] as? String
                self.blackPlayerRank = b["ranking"] as? Double
            }
        }
        if let pid = self.playerID {
            if pid == self.blackPlayerID { self.playerColor = .black }
            else if pid == self.whitePlayerID { self.playerColor = .white }
            else { self.playerColor = nil }
        }
        NotificationCenter.default.post(name: NSNotification.Name("OGSGameDataReceived"), object: nil, userInfo: ["gameData": payload, "moves": payload["moves"] ?? []])
    }
    
    private func processMove(_ data: [String: Any]) {
        guard let x = data["x"] as? Int, let y = data["y"] as? Int else { return }
        NotificationCenter.default.post(name: NSNotification.Name("OGSMoveReceived"), object: nil, userInfo: ["x": x, "y": y, "player_id": data["player_id"] ?? -1])
    }
    
    private func processClock(_ data: [String: Any]) {
        if let b = data["black_time"] as? NSNumber { self.blackTimeRemaining = b.doubleValue }
        if let w = data["white_time"] as? NSNumber { self.whiteTimeRemaining = w.doubleValue }
        if let c = data["current_player"] as? Int { self.currentPlayerID = c }
    }
}
