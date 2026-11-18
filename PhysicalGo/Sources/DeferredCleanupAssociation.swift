import Foundation

/// Bounded per-stone associations, not a tree of games. A plausible edge is not
/// permission to merge identities or to finalize a historical intersection.
struct DeferredCleanupAssociation {
    struct Disk: Codable, Equatable {
        let color: DeferredStoneState.Color
        let x: Double
        let y: Double
        let rx: Double
        let ry: Double
        let quality: Double
        let points: Set<Int>
        func distance(_ other: Self) -> Double { hypot(x-other.x, y-other.y) }
        var valid: Bool { [x,y,rx,ry,quality].allSatisfy(\.isFinite) && quality >= 0.9 && quality <= 1 && (0.30...0.65).contains(rx) && (0.30...0.65).contains(ry) }
    }
    struct Anchor: Codable {
        let identity: String
        let disk: Disk
        let witnesses: Set<String>
        let first: Double
        let last: Double
    }
    struct Blocker: Codable {
        let identity: String
        let color: DeferredStoneState.Color
        // Empty means whereabouts unknown, not absent. Includes unreliable
        // neighbors, new turns, and captured stones awaiting actual removal.
        let centers: [DeferredStoneState.Position]
    }
    struct View: Codable {
        let id: String
        let time: Double
        let epoch: String
        let hand: Bool?
        let lightingOK: Bool
        let gap: Bool
        let disks: [Disk]
        let captured: Set<String>
        let removed: Set<String>
        let blockers: [Blocker]
    }
    struct Candidate: Codable { let disk: Disk; let competitors: Set<String> }
    struct Support: Codable { let disk: Disk; let witnesses: [String]; let first: Double; let at: Double }
    private struct Run { let disk: Disk; let first: Double; var witnesses: [String] }
    enum Failure: Error { case invalidAnchors, invalidObservation }
    let anchors: [Anchor]
    let epoch: String
    let maximumMotion: Double
    private(set) var candidates: [String: [Candidate]] = [:]
    private(set) var supported: [String: Support] = [:]
    private(set) var interrupted: String?
    private(set) var retired: Set<String> = []
    private var removed: Set<String> = []
    private var runs: [String: Run] = [:]
    private var seen: Set<String>
    private var last: Double
    private var handSeen = false
    init(anchors: [Anchor], epoch: String, maximumMotion: Double = 2.25) throws {
        guard !epoch.isEmpty, maximumMotion.isFinite, maximumMotion > 0, maximumMotion <= 3,
              !anchors.isEmpty, anchors.count <= 625, Set(anchors.map(\.identity)).count == anchors.count,
              anchors.allSatisfy({ !$0.identity.isEmpty && $0.disk.valid && $0.witnesses.count >= 3 &&
                  !$0.witnesses.contains("") && $0.first.isFinite && $0.last.isFinite && $0.last-$0.first >= 0.4 }) else { throw Failure.invalidAnchors }
        self.anchors = anchors; self.epoch = epoch; self.maximumMotion = maximumMotion
        seen = anchors.reduce(into: Set<String>()) { $0.formUnion($1.witnesses) }
        last = anchors.map(\.last).max()!
    }
    mutating func observe(_ view: View) throws {
        if seen.contains(view.id) { return }
        guard !view.id.isEmpty, view.time.isFinite, view.time > last,
              view.blockers.allSatisfy({ !$0.identity.isEmpty && $0.centers.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) }) else { throw Failure.invalidObservation }
        // Bounded background work. Exhaustion only defers association; it has no
        // connection to the independent turn ledger or clock.
        if seen.count >= 512 || view.disks.count > 1250 || view.blockers.count > 1250 {
            interrupted = "association work limit"; supported.removeAll(); runs.removeAll(); return
        }
        let gap = view.gap || view.time-last > 0.75
        last = view.time; seen.insert(view.id)
        retired.formUnion(view.captured)
        // An absence reading alone cannot remove a captured stone's competing
        // physical explanation. Only externally verified removal can do this.
        removed.formUnion(view.removed.intersection(retired))
        if gap || view.epoch != epoch { interrupted = gap ? "missing recording evidence" : "camera/setup changed" }
        if view.hand != false || !view.lightingOK || interrupted != nil {
            handSeen = handSeen || view.hand == true
            supported.removeAll(); runs.removeAll()
            return
        }
        guard handSeen else { return }
        let disks = view.disks.filter(\.valid)
        var owners: [Int: Set<String>] = [:]
        var edges: [String: [Int]] = [:]
        // Keep every original anchor in the competition, even when its physical
        // removal is delayed. Captured anchors can block but cannot be supported.
        for a in anchors where !removed.contains(a.identity) {
            for (i,d) in disks.enumerated() where a.disk.color == d.color && a.disk.distance(d) <= maximumMotion &&
                abs(a.disk.rx-d.rx) <= 0.12 && abs(a.disk.ry-d.ry) <= 0.12 {
                owners[i, default: []].insert(a.identity)
                if !retired.contains(a.identity) { edges[a.identity, default: []].append(i) }
            }
        }
        for b in view.blockers where !removed.contains(b.identity) {
            for (i,d) in disks.enumerated() where b.color == d.color &&
                (b.centers.isEmpty || b.centers.contains(where: { hypot($0.x-d.x, $0.y-d.y) <= maximumMotion })) {
                owners[i, default: []].insert(b.identity)
            }
        }
        candidates = Dictionary(uniqueKeysWithValues: anchors.filter { !retired.contains($0.identity) }.map { a in
            (a.identity, (edges[a.identity] ?? []).map { Candidate(disk: disks[$0], competitors: (owners[$0] ?? []).subtracting([a.identity])) })
        })
        let matches = edges.compactMap { id, indices -> (String, Disk)? in
            guard indices.count == 1, owners[indices[0]] == [id] else { return nil }
            return (id, disks[indices[0]])
        }
        // Avoid interpreting camera/board drift as simultaneous cleanup.
        let motions = matches.map { id,d -> (Double,Double) in
            let old = anchors.first { $0.identity == id }!.disk
            return (d.x-old.x, d.y-old.y)
        }
        if motions.count >= 4 {
            let dx = motions.map(\.0).sorted()[motions.count/2], dy = motions.map(\.1).sorted()[motions.count/2]
            if hypot(dx,dy) > 0.12 && Double(motions.filter { hypot($0.0-dx,$0.1-dy) < 0.09 }.count)/Double(motions.count) >= 0.7 {
                interrupted = "possible camera/board movement"; supported.removeAll(); runs.removeAll(); return
            }
        }
        let matched = Set(matches.map(\.0))
        runs = runs.filter { matched.contains($0.key) }
        supported = supported.filter { matched.contains($0.key) }
        for (id,disk) in matches {
            var run = runs[id] ?? Run(disk: disk, first: view.time, witnesses: [])
            if run.disk.distance(disk) > 0.12 {
                run = Run(disk: disk, first: view.time, witnesses: []); supported[id] = nil
            }
            run.witnesses.append(view.id)
            run.witnesses = Array(run.witnesses.suffix(8))
            runs[id] = run
            if run.witnesses.count >= 3 && view.time-run.first >= 0.8 {
                supported[id] = Support(disk: disk, witnesses: run.witnesses, first: run.first, at: view.time)
            }
        }
    }
}
