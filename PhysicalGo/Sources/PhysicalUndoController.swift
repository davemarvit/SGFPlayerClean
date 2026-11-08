import Foundation
import Combine

/// Controls the existing SGF Player/OGS takeback API, never the local board.
@MainActor final class PhysicalUndoController: ObservableObject {
    struct Context: Equatable { let token: String; let game: Int; let version: Int }
    @Published private(set) var state: PhysicalUndoState?
    @Published private(set) var message: String?
    @Published private(set) var awaitingCommand = false
    private let directory: URL
    private var token = ""
    private var game = -1
    private var version = -1
    private var pending: PhysicalUndoRequest?
    var context: Context? { state == nil ? nil : Context(token: token, game: game, version: version) }
    init(directory: URL) { self.directory = directory }
    func refresh(now: Double = Date().timeIntervalSince1970) {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stamp = value["time"] as? Double, stamp.isFinite, abs(now - stamp) < 2,
              let nextToken = value["token"] as? String, let nextGame = value["game"] as? Int,
              let nextVersion = value["version"] as? Int, let undo = value["undo"],
              let undoData = try? JSONSerialization.data(withJSONObject: undo),
              let next = try? JSONDecoder().decode(PhysicalUndoState.self, from: undoData) else {
            state = nil; return
        }
        if token != nextToken || game != nextGame {
            pending = nil; awaitingCommand = false; message = nil
        }
        token = nextToken; game = nextGame; version = nextVersion
        if state != next { state = next }
        if let pending {
            if let data = try? Data(contentsOf: directory.appendingPathComponent("undo-result.json")),
               let reply = try? JSONDecoder().decode(PhysicalUndoReply.self, from: data), reply.id == pending.id {
                message = reply.message; self.pending = nil; awaitingCommand = false
            } else if now - pending.time >= 5 {
                message = "SGF Player has not acknowledged the undo action. Check its game controls before trying again."
                self.pending = nil; awaitingCommand = false
            }
        }
    }
    @discardableResult func send(_ action: PhysicalUndoRequest.Action, expectedContext: Context? = nil, now: Double = Date().timeIntervalSince1970) -> Bool {
        guard !awaitingCommand else { return false }
        refresh(now: now)
        if let expectedContext, expectedContext != context {
            message = "The online position changed while undo was being confirmed. Review the current board and try again."
            return false
        }
        guard let state else { message = "Connect an updated SGF Player to use online undo here."; return false }
        let move = action == .request ? state.moveNumber : (state.requestedMove ?? state.moveNumber)
        guard state.permits(action, move: move) else { message = "The online undo state changed. Check the current game before continuing."; return false }
        let request = PhysicalUndoRequest(id: UUID(), token: token, game: game, version: version, time: now, action: action, move: move)
        do {
            try JSONEncoder().encode(request).write(to: directory.appendingPathComponent("undo.json"), options: .atomic)
            pending = request; awaitingCommand = true; message = "Sending undo action to SGF Player…"
            return true
        } catch { message = "Could not send undo action: \(error.localizedDescription)"; return false }
    }
}
