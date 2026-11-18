import Foundation

/// Production identity/location sidecar. Clock receipts are copied from the ONE
/// native clock owner, never replayed or synthesized by this ledger. Legacy games
/// without a measured press keep nil timing, including setup stones and passes.
struct RecordingStoneLedger: Codable {
    struct Press: Codable, Equatable {
        let time: Double?
        let estimate: ClockPressEstimate?
        let before: LocalClockEngine
        let after: LocalClockEngine
    }
    struct Record: Codable, Identifiable {
        let id: UUID
        let number: Int
        let color: Stone
        var pass: Bool
        var press: Press?
        var historicalPoint: Int?
        var candidates: Set<Int>
        var capturedBy: Int?
        var locationUnresolved: Bool
        var physicalPoint: Int? = nil
        // The group is accounted for without choosing which same-color ID is
        // at which point. Every member retains the whole unresolved group.
        var physicalGroup: Set<Int>? = nil
        var removalVerified: Bool? = nil
    }
    struct Input {
        let number: Int
        let color: Stone
        let pass: Bool
        let point: Int?
        let candidates: Set<Int>
        let press: Press?
    }
    var version = 1
    let size: Int
    private(set) var records: [Record] = []
    private(set) var archived: [Record] = []
    private(set) var setupRemaining: [Int: Stone] = [:]
    // Runtime observation evidence is deliberately not in the durable schema.
    private var clearRuns: [UUID: ClearRun] = [:]
    private var establishedInThisRun: Set<UUID> = []
    private var groupRuns: [String: ClearRun] = [:]
    private struct ClearRun { let point: Int; let first: Double; var last: Double; var count: Int }
    private enum CodingKeys: String, CodingKey { case version, size, records, archived, setupRemaining }
    init(size: Int) { self.size = size }
    var markerPoints: Set<Int> {
        records.filter { $0.locationUnresolved && $0.capturedBy == nil && !$0.pass }
            .reduce(into: []) { $0.formUnion($1.candidates) }
    }
    func valid() -> Bool {
        guard version == 1, [9,13,19].contains(size),
              Set((records+archived).map(\.id)).count == records.count+archived.count,
              setupRemaining.keys.allSatisfy({ (0..<size*size).contains($0) }) else { return false }
        return records.enumerated().allSatisfy { i,r in
            r.number == i+1 && r.candidates.allSatisfy { (0..<size*size).contains($0) } &&
            (r.historicalPoint.map { (0..<size*size).contains($0) } ?? true) &&
            (r.physicalPoint.map { (0..<size*size).contains($0) } ?? true) &&
            (r.physicalGroup.map { !$0.isEmpty && $0.allSatisfy{(0..<size*size).contains($0)} } ?? true) &&
            (r.press?.time.map(\.isFinite) ?? true) && (r.press?.estimate?.valid ?? true) &&
            (!r.pass || r.historicalPoint == nil) && (r.capturedBy.map { $0 > r.number && $0 <= records.count } ?? true)
        }
    }
    enum Failure: LocalizedError {
        case invalid, changedPress(Int)
        var errorDescription: String? {
            switch self {
            case .invalid: return "Saved stone identities do not match this recording. The original files were preserved."
            case .changedPress(let n): return "The original time for move \(n) conflicts with the clock record. Review the recording before continuing."
            }
        }
    }
    /// Reconcile committed moves and independently accepted provisional presses.
    /// Undo/order edits archive old identities. Coordinate corrections retain IDs
    /// and receipts. A native receipt can fill unknown legacy timing, never replace
    /// an existing measured timestamp. No call into the clock is possible here.
    mutating func reconcile(_ inputs: [Input], captures: [Int: Int], setup: [Int: Stone] = [:]) throws {
        guard inputs.enumerated().allSatisfy({ $0.element.number == $0.offset+1 }) else { throw Failure.invalid }
        var next = self
        next.setupRemaining = setup
        let committed=inputs.prefix{$0.point != nil || $0.pass}.count
        var changedOrder = false
        for (i,input) in inputs.enumerated() {
            if i < next.records.count && (next.records[i].color != input.color ||
                (next.records[i].pass != input.pass && input.point != nil)) { changedOrder = true }
            if changedOrder { next.archived += next.records.suffix(from:i); next.records.removeSubrange(i...); changedOrder = false }
            if i == next.records.count {
                next.records.append(.init(id:UUID(),number:input.number,color:input.color,pass:input.pass,
                    press:input.press,historicalPoint:input.point,candidates:input.candidates,
                    capturedBy:captures[input.number],locationUnresolved:input.point == nil && input.candidates.count != 1 && !input.pass))
            } else {
                if let old = next.records[i].press, let new = input.press,
                   old.time != new.time || old.estimate != new.estimate { throw Failure.changedPress(input.number) }
                if next.records[i].press == nil { next.records[i].press = input.press }
                next.records[i].pass = input.pass
                next.records[i].historicalPoint = input.point
                next.records[i].candidates.formUnion(input.candidates)
                let capturedBy=captures[input.number] ?? next.records[i].capturedBy.flatMap { $0>committed && $0<=inputs.count ? $0 : nil }
                if capturedBy != next.records[i].capturedBy {next.records[i].removalVerified=nil}
                next.records[i].capturedBy = capturedBy
                if input.pass || captures[input.number] != nil { next.records[i].locationUnresolved = false }
            }
        }
        if next.records.count > inputs.count {
            next.archived += next.records.suffix(from:inputs.count)
            next.records.removeSubrange(inputs.count...)
        }
        guard next.valid() else { throw Failure.invalid }
        self = next
    }
    mutating func interrupt() {
        clearRuns.removeAll()
        groupRuns.removeAll()
    }
    /// User-reviewed intersections update location state only. The enclosing
    /// recorder saves this copy together with its corrected pending history.
    mutating func confirmLocations(_ points: [Int: Int]) throws {
        for (number,point) in points {
            guard records.indices.contains(number-1),(0..<size*size).contains(point),
                  !records[number-1].pass else {throw Failure.invalid}
            records[number-1].candidates=[point]
            records[number-1].physicalPoint=nil
            records[number-1].physicalGroup=nil
            records[number-1].locationUnresolved=false
            clearRuns[records[number-1].id]=nil
        }
    }
    /// Existing identities that could explain a fresh same-color outline are
    /// excluded from turn detection. Missing stones are NOT captures. Distance
    /// bounds may help display work; they never prove a distant outline is new.
    mutating func observe(_ observation: BoardObservation, now: Double) -> Set<Int> {
        guard observation.size == size, observation.readings.count == size*size,
              observation.handObstructed == false, !observation.lightingBlocked else { interrupt(); return [] }
        let stamp = observation.capturedAt ?? now
        var excluded: Set<Int> = []
        func currentPoints(_ r:Record)->Set<Int> {r.physicalGroup ?? r.physicalPoint.map{[$0]} ?? r.historicalPoint.map{[$0]} ?? r.candidates}
        let active=records.filter{!$0.pass && $0.capturedBy == nil}
        let missing=active.filter {r in !currentPoints(r).contains {observation.readings[$0].occupancy.stone==r.color} }
        for i in records.indices where records[i].capturedBy != nil && records[i].removalVerified != true {
            let record=records[i],points=currentPoints(record)
            for p in points where observation.readings[p].occupancy.stone==record.color {excluded.insert(p)}
            if !points.isEmpty,points.allSatisfy({observation.readings[$0].occupancy != .uncertain &&
                observation.readings[$0].occupancy.stone != record.color && observation.readings[$0].confidence>=0.98}) {
                var run=clearRuns[record.id]
                if run==nil || stamp-run!.last>0.75 || stamp<=run!.last {run = .init(point:-1,first:stamp,last:stamp,count:0)}
                run!.last=stamp;run!.count += 1;clearRuns[record.id]=run
                if run!.count>=3 && stamp-run!.first>=0.8 {records[i].removalVerified=true}
            } else {clearRuns[record.id]=nil}
        }
        for (p,color) in setupRemaining {
            if observation.readings[p].occupancy.stone == color { excluded.insert(p) }
            else {
                excluded.formUnion(observation.readings.enumerated().compactMap { $0.element.occupancy.stone == color ? $0.offset : nil })
            }
        }
        for i in records.indices where !records[i].pass && records[i].capturedBy == nil {
            let record = records[i]
            let known = currentPoints(record)
            if let group=record.physicalGroup {
                records[i].locationUnresolved=true
                if group.allSatisfy({observation.readings[$0].occupancy.stone==record.color && observation.readings[$0].confidence>=0.9}) {
                    excluded.formUnion(group)
                } else {
                    // A partially hidden/moved group cannot let two identities
                    // claim its one surviving sighting as independent proof.
                    excluded.formUnion(known)
                    excluded.formUnion(observation.readings.indices.filter{observation.readings[$0].occupancy.stone==record.color})
                }
                continue
            }
            let visible = known.filter { observation.readings[$0].occupancy.stone == record.color && observation.readings[$0].confidence >= 0.9 }
            if visible.count == 1, let p = visible.first {
                var run = clearRuns[record.id]
                if run == nil || run!.point != p || stamp-run!.last > 0.75 || stamp <= run!.last {
                    run = .init(point:p,first:stamp,last:stamp,count:0)
                }
                run!.last = stamp; run!.count += 1; clearRuns[record.id] = run
                if run!.count >= 3 && stamp-run!.first >= 0.8 {establishedInThisRun.insert(record.id)}
                if run!.count >= 3 && stamp-run!.first >= 0.8 && record.historicalPoint == p {
                    records[i].locationUnresolved = false
                }
                // Exactly one sighting of the existing token accounts for it.
                excluded.insert(p)
            } else {
                records[i].locationUnresolved = true
                let alternatives = Set(observation.readings.enumerated().compactMap { p,r in
                    r.occupancy.stone == record.color ? p : nil
                })
                // Keep plausible local display alternatives; an unknown distant
                // displacement still blocks a false new turn of the same color.
                let nearby = alternatives.filter { p in known.contains { q in
                    hypot(Double(p%size-q%size),Double(p/size-q/size)) <= 2.25
                } }
                records[i].candidates.formUnion(nearby)
                let definitelyEmpty=known.allSatisfy{observation.readings[$0].occupancy == .empty && observation.readings[$0].confidence>=0.98}
                if !definitelyEmpty {
                    // An unreliable surrounding stone is not evidence it moved.
                    // Only a recently established identity can compete locally;
                    // historical uncertainty must not veto every fresh turn.
                    excluded.formUnion(known)
                    if establishedInThisRun.contains(record.id) {excluded.formUnion(nearby)}
                    clearRuns[record.id]=nil
                    continue
                }
                let occupiedByOthers=active.filter{$0.id != record.id}.reduce(into:Set(setupRemaining.keys)) {$0.formUnion(currentPoints($1))}
                let available=nearby.subtracting(occupiedByOthers).filter{observation.readings[$0].confidence>=0.98}
                // A sustained one-to-one cleanup hypothesis can account for an
                // old stone on later turns. It remains marked and cannot change
                // the historical move or authorize a capture. Competing same-
                // color identities and unclear old locations never qualify.
                if missing.filter({$0.color==record.color}).count==1,available.count==1,let p=available.first,
                   known.allSatisfy({observation.readings[$0].occupancy == .empty && observation.readings[$0].confidence>=0.98}),
                   !setupRemaining.contains(where:{$0.value==record.color && observation.readings[$0.key].occupancy.stone != record.color}) {
                    var run=clearRuns[record.id]
                    if run==nil || run!.point != p || stamp-run!.last>0.75 || stamp<=run!.last {run = .init(point:p,first:stamp,last:stamp,count:0)}
                    run!.last=stamp;run!.count += 1;clearRuns[record.id]=run
                    if run!.count>=3 && stamp-run!.first>=0.8 {records[i].physicalPoint=p}
                } else {clearRuns[record.id]=nil}
                excluded.formUnion(alternatives)
                excluded.formUnion(known)
            }
        }
        var seenGroups=Set<String>()
        for color in [Stone.black,.white] {
            let members=missing.filter{$0.color==color}
            guard members.count>=2,
                  members.allSatisfy({!currentPoints($0).isEmpty && currentPoints($0).allSatisfy{observation.readings[$0].occupancy == .empty && observation.readings[$0].confidence>=0.98}}),
                  !setupRemaining.contains(where:{$0.value==color && observation.readings[$0.key].occupancy.stone != color}) else {continue}
            let ids=Set(members.map(\.id))
            // Include capture-removal debt as competition; a captured stone
            // still physically present cannot be reassigned to a live identity.
            let otherPoints=records.filter{!ids.contains($0.id) && !$0.pass && ($0.capturedBy==nil || $0.removalVerified != true)}
                .reduce(into:Set(setupRemaining.keys)) {$0.formUnion(currentPoints($1))}
            let options=members.map {member in Set(observation.readings.indices.filter {p in
                !otherPoints.contains(p) && observation.readings[p].occupancy.stone==color && observation.readings[p].confidence>=0.98 &&
                currentPoints(member).contains{hypot(Double(p%size-$0%size),Double(p/size-$0/size))<=2.25}
            })}
            let points=options.reduce(into:Set<Int>()){$0.formUnion($1)}
            guard points.count==members.count else {continue}
            // Bipartite matching checks that all identities can be accounted
            // for. It does not select or save an identity assignment/tree.
            var owners=[Int:Int]()
            func match(_ member:Int,_ visited:inout Set<Int>)->Bool {
                for point in options[member].sorted() where visited.insert(point).inserted {
                    if owners[point]==nil || match(owners[point]!,&visited) {owners[point]=member;return true}
                }
                return false
            }
            guard members.indices.allSatisfy({i in var visited=Set<Int>();return match(i,&visited)}) else {continue}
            let key=members.map{$0.id.uuidString}.sorted().joined(separator:",")+":"+points.sorted().map(String.init).joined(separator:",")
            seenGroups.insert(key)
            var run=groupRuns[key]
            if run==nil || stamp-run!.last>0.75 || stamp<=run!.last {run = .init(point:-1,first:stamp,last:stamp,count:0)}
            run!.last=stamp;run!.count += 1;groupRuns[key]=run
            if run!.count>=3 && stamp-run!.first>=0.8 {
                for i in records.indices where ids.contains(records[i].id) {
                    records[i].physicalGroup=points;records[i].physicalPoint=nil
                    records[i].candidates.formUnion(points);records[i].locationUnresolved=true
                }
            }
        }
        groupRuns=groupRuns.filter{seenGroups.contains($0.key)}
        return excluded
    }
}
