import Foundation

/// Deployment foundation, deliberately not connected to GameRecorder. Only the
/// turn authority may append a turn. Location work has no clock command API.
struct DeferredStoneState {
    enum Color: String, Codable { case black, white
        var opponent: Self { self == .black ? .white : .black }
    }
    struct Turn: Codable, Equatable {
        let id: String
        let color: Color
        let time: Double
        let lower: Double
        let upper: Double
        let certifiedAt: Double
        let witnesses: Set<String>
        // These are assertions from the independent turn authority, not scores
        // inferred from an outline or from a provisional board.
        let identityReliable: Bool
        let timingReliable: Bool
        let colorReliable: Bool
        let continuous: Bool
        var valid: Bool {
            !id.isEmpty && [time, lower, upper, certifiedAt].allSatisfy(\.isFinite) &&
            lower <= time && time <= upper && upper <= certifiedAt &&
            witnesses.count >= 2 && !witnesses.contains("") && identityReliable &&
            timingReliable && colorReliable && continuous
        }
    }
    struct Position: Codable, Equatable { let x: Double; let y: Double }
    struct Location: Codable, Equatable {
        // Historical move intersection and current physical position are distinct.
        var historicalCandidates: Set<Int>
        var reviewedIntersection: Int?
        var physicalCandidates: Set<Int>
        var proposedCenter: Position?
        var status = "unresolved"
        var capturedBy: String?
        var removalVerified = false
    }
    struct Proposal: Equatable {
        let revision: Int
        let epoch: String
        let identity: String
        let points: Set<Int>
        let center: Position?
        let supported: Bool
    }
    enum Failure: Error { case invalidTurn, conflictingDuplicate, invalidLocation, invalidCapture, invalidCheckpoint, unresolvedHistory }
    private struct Checkpoint: Codable {
        let version: Int
        let size: Int
        let first: Color
        let turns: [Turn]
        let locations: [String: Location]
    }
    let size: Int
    let first: Color
    // Process-local epoch invalidates background work after save/restore.
    private(set) var epoch = UUID().uuidString
    private(set) var revision = 0
    private(set) var turns: [Turn] = []
    private(set) var locations: [String: Location] = [:]
    init(size: Int = 19, first: Color = .black) throws {
        guard (2...25).contains(size) else { throw Failure.invalidLocation }
        self.size = size; self.first = first
    }
    private func valid(_ points: Set<Int>) -> Bool {
        points.allSatisfy { (0..<size*size).contains($0) }
    }
    /// Empty alternatives mean unknown location; they never reject a valid turn.
    /// A repeated certificate is a no-op even if later location guesses differ.
    @discardableResult mutating func accept(_ turn: Turn, candidates: Set<Int>) throws -> Bool {
        if let old = turns.first(where: { $0.id == turn.id }) {
            guard old == turn else { throw Failure.conflictingDuplicate }
            return false
        }
        guard turn.valid, turn.color == (turns.last?.color.opponent ?? first),
              turns.last.map({ turn.lower > $0.upper && turn.certifiedAt >= $0.certifiedAt }) ?? true,
              turns.allSatisfy({ $0.witnesses.isDisjoint(with: turn.witnesses) }) else { throw Failure.invalidTurn }
        guard valid(candidates) else { throw Failure.invalidLocation }
        turns.append(turn)
        locations[turn.id] = Location(historicalCandidates: candidates, physicalCandidates: candidates)
        revision += 1
        return true
    }
    /// Background work can alter a proposed display only. It cannot settle SGF,
    /// change turn identity/time, remove stones, or press/pause a clock.
    @discardableResult mutating func apply(_ proposal: Proposal) throws -> Bool {
        guard proposal.epoch == epoch, proposal.revision == revision,
              var location = locations[proposal.identity], location.capturedBy == nil else { return false }
        guard valid(proposal.points), proposal.center.map({ $0.x.isFinite && $0.y.isFinite &&
            (-0.5...Double(size)-0.5).contains($0.x) && (-0.5...Double(size)-0.5).contains($0.y) }) ?? true,
            !proposal.supported || (!proposal.points.isEmpty && proposal.center != nil) else { throw Failure.invalidLocation }
        // Preserve alternatives through missing/contradictory views.
        location.physicalCandidates.formUnion(proposal.points)
        location.proposedCenter = proposal.supported ? proposal.center : nil
        location.status = proposal.supported ? "proposed association; history unresolved" : "unresolved"
        locations[proposal.identity] = location
        revision += 1
        return true
    }
    /// Call synchronously when a hand/new observation/camera change invalidates
    /// the snapshot used by a background worker. Old results cannot arrive later
    /// and resurrect a display claim made before that observation.
    mutating func invalidateLocationEvidence(_ identities: Set<String>) {
        for id in identities where locations[id] != nil {
            locations[id]!.proposedCenter = nil
            locations[id]!.status = locations[id]!.removalVerified ? "removed" : "unresolved"
        }
        revision += 1
    }
    mutating func reviewIntersection(identity: String, point: Int) throws {
        guard var location = locations[identity], valid([point]) else { throw Failure.invalidLocation }
        location.historicalCandidates.insert(point)
        location.reviewedIntersection = point
        locations[identity] = location
        revision += 1
    }
    /// Captures come from native Go rules/review, never from an ambiguous display.
    /// Retain the physical identity until a separate removal certificate arrives.
    mutating func capture(by turnID: String, victims: Set<String>) throws {
        guard let n = turns.firstIndex(where: { $0.id == turnID }), victims.allSatisfy({ id in
            guard let i = turns.firstIndex(where: { $0.id == id }), let l = locations[id] else { return false }
            return i < n && turns[i].color != turns[n].color && (l.capturedBy == nil || l.capturedBy == turnID)
        }) else { throw Failure.invalidCapture }
        for id in victims { locations[id]!.capturedBy = turnID; locations[id]!.proposedCenter = nil; locations[id]!.status = "captured; removal unresolved" }
        revision += 1
    }
    mutating func verifyRemoval(_ identities: Set<String>) throws {
        guard identities.allSatisfy({ locations[$0]?.capturedBy != nil }) else { throw Failure.invalidCapture }
        for id in identities { locations[id]!.removalVerified = true; locations[id]!.status = "removed" }
        revision += 1
    }
    /// Export input, never a legality assertion. The existing Go rules engine
    /// must replay this sequence before an SGF is finalized. Provisional display
    /// centers are deliberately inaccessible through this method.
    func reviewedSequence() throws -> [(turn: Turn, point: Int)] {
        try turns.map { turn in
            guard let point = locations[turn.id]?.reviewedIntersection else { throw Failure.unresolvedHistory }
            return (turn,point)
        }
    }
    func checkpoint() throws -> Data {
        try JSONEncoder().encode(Checkpoint(version: 1, size: size, first: first, turns: turns, locations: locations))
    }
    static func restore(_ data: Data) throws -> Self {
        let c = try JSONDecoder().decode(Checkpoint.self, from: data)
        guard c.version == 1, Set(c.locations.keys) == Set(c.turns.map(\.id)) else { throw Failure.invalidCheckpoint }
        var result = try Self(size: c.size, first: c.first)
        for t in c.turns {
            guard try result.accept(t, candidates: c.locations[t.id]!.historicalCandidates) else { throw Failure.invalidCheckpoint }
        }
        for (id, location) in c.locations {
            guard result.valid(location.physicalCandidates),
                  location.reviewedIntersection.map({ result.valid([$0]) && location.historicalCandidates.contains($0) }) ?? true,
                  !location.removalVerified || location.capturedBy != nil else { throw Failure.invalidCheckpoint }
            if let capture = location.capturedBy { try result.capture(by: capture, victims: [id]) }
        }
        result.locations = c.locations
        // A restarted process has not observed fresh clear stones. Keep candidate
        // history, but never revive an old fresh display claim or worker result.
        for id in result.locations.keys {
            result.locations[id]!.proposedCenter = nil
            result.locations[id]!.status = result.locations[id]!.removalVerified ? "removed" : "unresolved after restore"
        }
        return result
    }
}

/// Offline/deployment adapter: ledger and clock are committed in ONE atomic file.
/// Location updates never call LocalClockEngine. Not used by the live recorder.
struct DeferredTurnSession {
    enum Failure: Error { case clockRejected, differentTimeline, invalidCheckpoint }
    private struct Checkpoint: Codable {
        let version: Int
        let timeline: String
        let initialClock: LocalClockEngine
        let clock: LocalClockEngine
        let state: Data
    }
    let timeline: String
    let initialClock: LocalClockEngine
    private(set) var clock: LocalClockEngine
    private(set) var state: DeferredStoneState
    init(state: DeferredStoneState, clock: LocalClockEngine, timeline: String) throws {
        guard !timeline.isEmpty, state.turns.isEmpty, clock.blackToPlay == (state.first == .black),
              clock.settings.validationError == nil else { throw Failure.invalidCheckpoint }
        self.state = state; self.clock = clock; self.initialClock = clock; self.timeline = timeline
    }
    @discardableResult mutating func accept(_ turn: DeferredStoneState.Turn, candidates: Set<Int>, savingTo url: URL? = nil) throws -> Bool {
        var next = self
        guard try next.state.accept(turn, candidates: candidates) else { return false }
        if next.clock.enabled {
            // The existing engine supports explicit pauses. This adapter cannot
            // backdate across a pause or an already advanced clock anchor.
            guard next.clock.running, let anchor = next.clock.anchor, turn.time >= anchor,
                  next.clock.move(black: turn.color == .black, at: turn.time) else { throw Failure.clockRejected }
        }
        if let url { try next.save(to: url) }
        self = next
        return true
    }
    @discardableResult mutating func apply(_ proposal: DeferredStoneState.Proposal, savingTo url: URL? = nil) throws -> Bool {
        var next = self
        guard try next.state.apply(proposal) else { return false }
        if let url { try next.save(to: url) }
        self = next
        return true
    }
    mutating func invalidateLocationEvidence(_ identities: Set<String>, savingTo url: URL? = nil) throws {
        var next = self
        next.state.invalidateLocationEvidence(identities)
        if let url { try next.save(to: url) }
        self = next
    }
    mutating func reviewIntersection(identity: String, point: Int, savingTo url: URL? = nil) throws {
        var next = self
        try next.state.reviewIntersection(identity: identity, point: point)
        if let url { try next.save(to: url) }
        self = next
    }
    mutating func capture(by turnID: String, victims: Set<String>, savingTo url: URL? = nil) throws {
        var next = self
        try next.state.capture(by: turnID, victims: victims)
        if let url { try next.save(to: url) }
        self = next
    }
    mutating func verifyRemoval(_ identities: Set<String>, savingTo url: URL? = nil) throws {
        var next = self
        try next.state.verifyRemoval(identities)
        if let url { try next.save(to: url) }
        self = next
    }
    func save(to url: URL) throws {
        let payload = Checkpoint(version: 1, timeline: timeline, initialClock: initialClock, clock: clock, state: try state.checkpoint())
        try JSONEncoder().encode(payload).write(to: url, options: .atomic)
    }
    static func restore(from url: URL, timeline: String) throws -> Self {
        let c = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: url))
        guard c.version == 1 else { throw Failure.invalidCheckpoint }
        // Caller owns clock origin/boot identity; no assumption that saved
        // monotonic times survive a reboot, camera gap, or changed timing basis.
        guard c.timeline == timeline else { throw Failure.differentTimeline }
        let restored = try DeferredStoneState.restore(c.state)
        var result = try Self(state: DeferredStoneState(size: restored.size, first: restored.first), clock: c.initialClock, timeline: timeline)
        for t in restored.turns { try result.accept(t, candidates: restored.locations[t.id]!.historicalCandidates) }
        guard result.clock == c.clock else { throw Failure.invalidCheckpoint }
        result.state = restored
        return result
    }
}
