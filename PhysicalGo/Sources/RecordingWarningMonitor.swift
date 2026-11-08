import Foundation

/// Advisory only: detecting an unsaved stone must never alter accepted move history.
/// A few sightings and a grace period separate ordinary confirmation from a stall.
struct RecordingWarningMonitor {
    struct Candidate {
        var color:Occupancy
        var firstSeen:Double
        var lastSeen:Double
        var consecutive=1
        var clearFrames=0
        var stable=false
        var warned=false
    }
    enum Signal:String {case unsavedStone="new unsaved stone",reminder="recording still blocked"}
    static let grace=5.0
    static let trackedGrace=10.0
    static let repeatInterval=8.0
    static let minimumSoundInterval=2.0
    private var candidates=[Int:Candidate]()
    private var lastFrame:Double?
    private var lastSound:Double?
    var hasWarnedOutstanding:Bool {candidates.values.contains{$0.warned}}
    var outstandingCount:Int {candidates.values.filter{$0.stable}.count}

    mutating func reset() {candidates=[:];lastFrame=nil;lastSound=nil}
    mutating func recorded(_ indices:[Int]) {
        for index in indices {candidates[index]=nil}
    }
    mutating func noteSound(now:Double) {lastSound=now}
    mutating func update(readings:[Occupancy],accepted:[Occupancy],now:Double,blocked:Bool,knownPlacementWarnings:Set<Int>=[],trackedMoves:Set<Int>=[],coalesceEpisode:Bool=false)->Signal? {
        guard readings.count==accepted.count,lastFrame.map({now>$0}) ?? true else {return nil}
        let gap=lastFrame.map{now-$0>1.5} ?? false
        lastFrame=now
        for index in readings.indices {
            let value=readings[index]
            if value.stone != nil && value==accepted[index] {
                candidates[index]=nil
                continue
            }
            if value == .empty {
                if var candidate=candidates[index] {
                    candidate.consecutive=0;candidate.clearFrames += 1
                    if candidate.clearFrames>=5 {candidates[index]=nil} else {candidates[index]=candidate}
                }
                continue
            }
            if value == .uncertain {
                if var candidate=candidates[index] {candidate.consecutive=0;candidate.clearFrames=0;candidates[index]=candidate}
                continue
            }
            if var candidate=candidates[index] {
                if candidate.color != value || gap || now-candidate.lastSeen>1.5 {
                    candidate.color=value;candidate.consecutive=1;candidate.firstSeen=now
                } else {candidate.consecutive += 1}
                candidate.lastSeen=now;candidate.clearFrames=0
                if candidate.consecutive>=3 {candidate.stable=true}
                candidates[index]=candidate
            } else {
                candidates[index]=Candidate(color:value,firstSeen:now,lastSeen:now)
            }
        }
        let overdue=candidates.filter { point,candidate in
            candidate.stable && candidate.consecutive>=3 && !candidate.warned &&
                now-candidate.firstSeen >= (trackedMoves.contains(point) ? Self.trackedGrace:Self.grace)
        }.map(\.key)
        let interval=coalesceEpisode ? 30.0:Self.minimumSoundInterval
        let canSound=lastSound.map{now-$0>=interval} ?? true
        if !overdue.isEmpty && canSound {
            // Coalesce stones arriving within one callback. The cooldown prevents
            // a hand-shaped cluster or color flicker from producing a sound storm.
            for index in overdue {candidates[index]?.warned=true}
            lastSound=now
            return .unsavedStone
        }
        // Keep the first alert and visible placement warning. Repeat it only
        // when another stable stone is outside the known placement issues.
        let needsReminder = knownPlacementWarnings.isEmpty || candidates.contains {
            $0.value.stable && !knownPlacementWarnings.contains($0.key)
        }
        if blocked,needsReminder,let lastSound,now-lastSound >= (coalesceEpisode ? 30.0:Self.repeatInterval) {
            self.lastSound=now
            return .reminder
        }
        return nil
    }
}


/// One advisory chime for a persistent placement issue. Only new geometric
/// sightings advance it. Pauses discard partial evidence, but not prior chimes.
struct PlacementChimeMonitor {
    struct Issue: Hashable {
        let move: Int
        let point: Int
    }
    private struct Sightings {
        let first: Double
        var last: Double
        var count: Int
    }
    private var sightings = [Issue: Sightings]()
    private var announced = Set<Issue>()
    private var lastChime: Double?

    mutating func interrupt() { sightings.removeAll() }

    mutating func update(visible: Set<Issue>, displaced: Set<Issue>, now: Double) -> [Issue] {
        sightings = sightings.filter { visible.contains($0.key) && now-$0.value.last <= 1.5 }
        var due = [Issue]()
        for issue in displaced where visible.contains(issue) && !announced.contains(issue) {
            var view = sightings[issue] ?? Sightings(first:now, last:now, count:0)
            guard view.count == 0 || now > view.last else { continue }
            view.last = now
            view.count += 1
            sightings[issue] = view
            if view.count >= 3 && now-view.first >= 2.5 { due.append(issue) }
        }
        guard !due.isEmpty, lastChime.map({ now-$0 >= 2.5 }) ?? true else { return [] }
        lastChime = now
        announced.formUnion(due)
        for issue in due { sightings.removeValue(forKey:issue) }
        return due.sorted { $0.move < $1.move }
    }
}
