import Foundation

/// Owns the recording's file formats and write protection. Loading a damaged
/// sidecar makes the session read-only until that same sidecar is repaired.
/// Callers never use diagnostic messages to decide what should be persisted.
@MainActor final class RecordingStore {
    struct PendingCheckpoint: Codable {
        let version: Int
        let signature: String
        let history: MoveObservationHistory.Checkpoint
        var awaitingFirstStart: Bool? = nil
    }
    enum Sidecar: String { case pending = "pending.json", reviews = "reviews.json" }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private(set) var url: URL?
    private var failedReads: [Sidecar: String] = [:]
    private var lastPendingData: Data?
    private var savedSignature: String?
    var isReadBlocked: Bool { !failedReads.isEmpty }

    func bind(to url: URL?, savedSignature: String? = nil) {
        self.savedSignature = savedSignature
        self.url = url
        failedReads = [:]
        lastPendingData = nil
    }
    private func sidecar(_ kind: Sidecar) -> URL? {
        url?.deletingPathExtension().appendingPathExtension(kind.rawValue)
    }
    private func requireWritable() throws {
        if isReadBlocked {
            throw Failure(message: "Repair and reload the saved recording before changing it. The original files have been preserved.")
        }
    }
    func canCheckpoint(signature: String) -> Bool {
        url == nil || savedSignature == signature
    }
    func saveGame(_ text: String, signature: String) throws {
        try requireWritable()
        guard let url else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        savedSignature = signature
    }
    func preserveBeforeUndo(_ text: String) throws {
        try requireWritable()
        guard let url else { return }
        let backup=url.deletingPathExtension().appendingPathExtension("before-undo-\(UUID().uuidString)")
        try text.write(to:backup.appendingPathExtension("sgf"),atomically:true,encoding:.utf8)
        for suffix in ["clock.json","reviews.json","pending.json"] {
            let source=url.deletingPathExtension().appendingPathExtension(suffix)
            if FileManager.default.fileExists(atPath:source.path) {
                try FileManager.default.copyItem(at:source,to:backup.appendingPathExtension(suffix))
            }
        }
    }
    func savePending(_ checkpoint: PendingCheckpoint) throws {
        try requireWritable()
        guard let file = sidecar(.pending) else { return }
        guard canCheckpoint(signature: checkpoint.signature) else {
            throw Failure(message: "Save the accepted game before checkpointing its pending history.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(checkpoint)
        // Repeated paused observations need not rewrite an identical checkpoint.
        if data == lastPendingData, (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { return }
        try data.write(to: file, options: .atomic)
        lastPendingData = data
    }
    func saveReviews(_ history: DeferredMoveHistory) throws {
        try requireWritable()
        guard let file = sidecar(.reviews) else { return }
        try JSONEncoder().encode(history).write(to: file, options: .atomic)
    }
    func loadPending(game: SGFGame, now: Double) throws -> (awaitingStart: Bool, history: MoveObservationHistory?) {
        try read(.pending) { file in
            guard let file else { return (false, nil) }
            let saved = try JSONDecoder().decode(PendingCheckpoint.self, from: Data(contentsOf: file))
            guard saved.version == 1, saved.signature == RecordingIdentity.signature(for: game) else {
                throw Failure(message: "The pending-move checkpoint does not match this SGF. The original checkpoint has been preserved.")
            }
            let awaitingStart = saved.awaitingFirstStart == true && game.moves.isEmpty
            guard !saved.history.paths.isEmpty else { return (awaitingStart, nil) }
            guard let history = MoveObservationHistory.restore(saved.history, game: game, now: now) else {
                throw Failure(message: "The pending-move checkpoint could not be validated. The original checkpoint has been preserved.")
            }
            return (awaitingStart, history)
        }
    }
    func loadReviews(game: SGFGame) throws -> ReviewHistoryCoordinator.Restoration {
        try read(.reviews) { file in
            guard let file else {
                var history = DeferredMoveHistory(); history.size = game.boardSize
                return .init(history: history, recoveredCommit: false)
            }
            let history = try JSONDecoder().decode(DeferredMoveHistory.self, from: Data(contentsOf: file))
            return try ReviewHistoryCoordinator.restore(history, game: game)
        }
    }
    private func read<Value>(_ kind: Sidecar, decode: (URL?) throws -> Value) throws -> Value {
        do {
            let file = sidecar(kind).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            let result = try decode(file)
            failedReads.removeValue(forKey: kind)
            return result
        } catch {
            failedReads[kind] = error.localizedDescription
            throw error
        }
    }
}
