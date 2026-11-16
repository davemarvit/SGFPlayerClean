import Foundation

// Frozen stage-1 timing policy from feca90c / c7b0b5e. Test-only differential oracle.
// Deliberately independent of CandidateMoveHistory; do not refactor with production.
struct StageOneTimingOracle {
    private struct View {
        let time:Double
        let rawPosition:[Occupancy]
        let confidence:[Double]
        let estimate:ClockPressEstimate
        let aliases:[Int:Set<Int>]
        var discounted=Set<Int>()
        private(set) var position:[Occupancy]
        mutating func discount(_ points:Set<Int>) {
            discounted.formUnion(points)
            for p in points where rawPosition.indices.contains(p) && rawPosition[p] == .black {position[p] = .uncertain}
        }
    }
    private var views=[View]()
    private var consumedUntil = -Double.infinity
    private var lastActivity:Double?
    mutating func reset() {views=[];consumedUntil = -Double.infinity;lastActivity=nil}
    mutating func noteHand(at time:Double) {
        guard time.isFinite else {return}
        if let lastActivity,time-lastActivity>1.5 {reset()}
        lastActivity=max(lastActivity ?? time,time)
    }
    mutating func consume(through time:Double) {
        consumedUntil=max(consumedUntil,time);views.removeAll{$0.time<=consumedUntil}
    }
    mutating func discountDarkReadings(_ points:Set<Int>,since:Double) {
        for i in views.indices where views[i].time>=since {views[i].discount(points)}
    }
    mutating func discountDarkReadings(_ points:Set<Int>,at time:Double) {
        guard let i=views.firstIndex(where:{$0.time==time}) else {return}
        views[i].discount(points)
    }
    /// Discounted evidence cannot date a placement. It also cannot contradict
    /// an independent earlier clear sighting of that same placement.
    private func boundary(_ points:Set<Int>,after contradiction:Double)->Double {
        let firstClear=views.first {view in
            view.time>contradiction && points.contains{view.position.indices.contains($0) && view.position[$0].stone != nil}
        }?.time ?? .infinity
        let suspect=views.last {view in
            view.time<firstClear && !view.discounted.isDisjoint(with:points)
        }?.time ?? -.infinity
        return max(contradiction,suspect)
    }
    mutating func observe(_ observation:BoardObservation,now:Double) {
        guard let stamp=observation.capturedAt,
              stamp.isFinite,stamp<=now,now-stamp<1.5,!observation.lightingBlocked else {return}
        // Fresh frames establish camera continuity even while the hand detector
        // is uncertain. They must not erase previously verified clock presses,
        // but cannot supply a new press until visual clearance is known.
        if let lastActivity,stamp-lastActivity>1.5 {reset()}
        lastActivity=max(lastActivity ?? stamp,stamp)
        guard observation.handObstructed == false,views.last.map({stamp>$0.time}) ?? true else {return}
        views.removeAll {stamp-$0.time>120}
        let estimate=observation.clockPressEstimate.flatMap{$0.valid && $0.time<=stamp ? $0:nil}
            ?? ClockPressEstimate(time:stamp,method:.clearFrame)
        views.append(.init(time:stamp,rawPosition:observation.signature,confidence:observation.readings.map(\.confidence),estimate:estimate,
                           aliases:observation.placementAlternatives(base:Array(repeating:.empty,count:observation.readings.count)),position:observation.signature))
        if views.count>1000 {views.removeFirst(views.count-1000)}
    }
    func estimate(target:[Occupancy],changed:Set<Int>,after epoch:Double)->ClockPressEstimate? {
        // A definite withdrawal invalidates the earlier placement at that point.
        // Changes elsewhere do not erase an intermediate move during catch-up.
        let contradicted=views.last {view in
            changed.contains {p in target.indices.contains(p) && view.position.indices.contains(p) &&
                view.position[p] != .uncertain && view.position[p] != target[p]}
        }?.time ?? -Double.infinity
        let boundary=boundary(changed,after:contradicted)
        return views.first {view in
            view.time>boundary &&
            view.estimate.time>=epoch && view.estimate.time>consumedUntil &&
            ReviewBoardVerification.matches(view.position,target:target,requiredClear:changed)
        }.map{supportedEstimate($0,after:boundary)}
    }
    /// Turn identity can be certain before the exact intersection. Require a
    /// single visible stone, repeated clear frames, and agreement elsewhere.
    func provisionalEstimate(target:[Occupancy],changed:Set<Int>,locations:Set<Int>,color:Stone,
                             aliases:[Set<Int>],after epoch:Double)->ClockPressEstimate? {
        func matches(_ view:View)->Bool {
            guard view.position.count==target.count,view.estimate.time>=epoch,view.estimate.time>consumedUntil else {return false}
            let present=locations.filter{view.position[$0].stone != nil}
            guard present.count==1,let point=present.first,view.position[point].stone==color,view.confidence[point]>=0.9 else {return false}
            var values=view.position
            for group in aliases {
                let actual=group.filter{values[$0].stone != nil},expected=group.filter{target[$0].stone != nil}
                guard actual.count==1,expected.count==1,let a=actual.first,let b=expected.first,values[a]==target[b] else {continue}
                for p in group {values[p] = .empty};values[b]=target[b]
            }
            return ReviewBoardVerification.matches(values,target:target,requiredClear:changed)
        }
        // A definite absence retracts an earlier flash; later real play needs
        // its own boundary. Hand frames alone do not retract placement evidence.
        let contradicted=views.last{view in
            locations.allSatisfy{view.position.indices.contains($0) && view.position[$0] == .empty} ||
                locations.contains{view.position.indices.contains($0) && view.position[$0].stone==color.opponent}
        }?.time ?? -.infinity
        let boundary=boundary(locations,after:contradicted)
        let eligible=views.filter{$0.time>boundary && matches($0)}
        guard let first=eligible.first,
              confirmation(eligible,locations:locations,ignoring:Set(aliases.flatMap{$0}),after:boundary) != nil else {return nil}
        return supportedEstimate(first,after:boundary)
    }
    func firstMatch(target:[Occupancy],changed:Set<Int>,after epoch:Double)->Double? {
        estimate(target:target,changed:changed,after:epoch)?.time
    }

    struct ObservedTurn {
        let color:Stone
        let locations:Set<Int>
        let estimate:ClockPressEstimate
        let confirmation:Confirmation
    }
    struct Confirmation {
        enum Level:String {case strong,handSupported,consistent,cautious}
        let level:Level
        let clearViews:Int
        let span:Double
        let minimumScore:Double
    }
    /// Detector scores are heuristic, not probabilities. A high score alone
    /// cannot make a short-lived corner/shadow reading press the clock. Both
    /// provisional paths use the same turn-level evidence policy; the returned
    /// press still dates to the first supported sighting, not confirmation.
    private func supportedEstimate(_ view:View,after contradiction:Double)->ClockPressEstimate {
        guard view.estimate.time>contradiction else {
            return .init(time:view.time,method:.clearFrame,timestampSource:view.estimate.timestampSource,
                         fallbackReason:"Earlier hand estimate predates a contradictory stone reading")
        }
        return view.estimate
    }
    private func confirmation(_ eligible:[View],locations:Set<Int>,ignoring:Set<Int>,after contradiction:Double)->Confirmation? {
        guard let first=eligible.first,let newest=views.last,eligible.last?.time==newest.time else {return nil}
        // Uncertainty interrupts confirmation, but does not erase the earlier
        // timestamp. Definite absence/opposite colour is retracted by callers.
        let unclear=views.last {view in
            view.time>=first.time && locations.filter{view.position[$0].stone != nil}.count != 1
        }?.time ?? -.infinity
        let run=eligible.filter{$0.time>unclear}
        guard let start=run.first,let last=run.last else {return nil}
        let scores=run.flatMap {view in locations.compactMap {p in view.position[p].stone != nil ? view.confidence[p]:nil}}
        guard let score=scores.min(),score.isFinite,score>=0.9 else {return nil}
        let ignored=ignoring.union(locations)
        var previous=start.position
        let stable=run.allSatisfy {view in
            guard view.position.filter({$0 == .uncertain}).count<=max(2,view.position.count/20) else {return false}
            let changes=view.position.indices.filter {p in
                !ignored.contains(p) && view.position[p] != .uncertain && previous[p] != .uncertain && view.position[p] != previous[p]
            }
            // A later reply must not invalidate a completed earlier turn.
            // Flickering/removing stones, colour changes, and bursts of new
            // stones elsewhere lower confidence in the whole observation.
            guard changes.count<=1,changes.allSatisfy({previous[$0] == .empty && view.position[$0].stone != nil}) else {return false}
            for p in previous.indices where view.position[p] != .uncertain {previous[p]=view.position[p]}
            return true
        }
        let estimate=supportedEstimate(first,after:contradiction)
        let hand=estimate.method == .handMotion || estimate.method == .handBracket
        let handInterval=hand && estimate.observedLower != nil && estimate.observedUpper != nil
        let preciseHand=handInterval && estimate.latestPlausibleTime-estimate.earliestPlausibleTime<=0.6
        let level:Confirmation.Level
        let count:Int,seconds:Double
        if score>=0.97 && stable && preciseHand {
            level = .strong;count=2;seconds=0.2
        } else if stable && handInterval {
            level = .handSupported;count=2;seconds=0.4
        } else if score>=0.97 && stable && !hand {
            level = .consistent;count=4;seconds=0.6
        } else {
            level = .cautious;count=6;seconds=1.0
        }
        let span=last.time-start.time
        guard run.count>=count,span>=seconds else {return nil}
        return .init(level:level,clearViews:run.count,span:span,minimumScore:score)
    }
    func pendingTurn(base:[Occupancy],excluding:Set<Int>,color:Stone,after epoch:Double)->ClockPressEstimate? {
        guard let newest=views.last,newest.position.count==base.count else {return nil}
        let points=base.indices.filter{base[$0] == .empty && !excluding.contains($0) && newest.position[$0].stone==color && newest.confidence[$0]>=0.9}
        return points.compactMap {p -> ClockPressEstimate? in
            let contradicted=views.last{$0.position[p] != .uncertain && $0.position[p].stone != color}?.time ?? -.infinity
            let boundary=boundary([p],after:contradicted)
            return views.first {view in
                view.time>boundary && view.estimate.time>=epoch && view.estimate.time>consumedUntil &&
                    view.position[p].stone==color && view.confidence[p]>=0.9
            }.map{supportedEstimate($0,after:boundary)}
        }.min{$0.time<$1.time}
    }
    /// Physical turn evidence is local. An unrelated uncertain intersection or
    /// an incorrect candidate path must not make the player keep paying time.
    /// Colours alternate; the SGF resolver alone decides legal intersections.
    func observedTurns(base:[Occupancy],excluding:Set<Int>,after epoch:Double)->[ObservedTurn] {
        guard let newest=views.last,newest.position.count==base.count else {return []}
        var groups=[Set<Int>]()
        for p in base.indices where base[p] == .empty && newest.position[p].stone != nil && !excluding.contains(p) {
            var group:Set<Int>=[p]
            for view in views {
                for locations in view.aliases.values where locations.contains(p) {group.formUnion(locations)}
            }
            group=group.filter{base.indices.contains($0) && base[$0] == .empty}
            guard group.isDisjoint(with:excluding),group.allSatisfy({base.indices.contains($0) && base[$0] == .empty}) else {continue}
            if let i=groups.firstIndex(where:{!$0.isDisjoint(with:group)}) {groups[i].formUnion(group)} else {groups.append(group)}
        }
        return groups.compactMap {locations in
            let present=locations.filter{newest.position[$0].stone != nil}
            guard present.count==1,let point=present.first,let color=newest.position[point].stone else {return nil}
            // Withdrawal or a contradictory colour starts a new observation.
            let contradicted=views.last {view in
                locations.allSatisfy{view.position[$0] == .empty} ||
                    locations.contains{view.position[$0].stone==color.opponent}
            }?.time ?? -.infinity
            let boundary=boundary(locations,after:contradicted)
            let eligible=views.filter {view in
                guard view.time>boundary,view.estimate.time>=epoch,view.estimate.time>consumedUntil else {return false}
                let occupied=locations.filter{view.position[$0].stone != nil}
                return occupied.count==1 && occupied.contains{view.position[$0].stone==color && view.confidence[$0]>=0.9}
            }
            guard let first=eligible.first,let confirmation=confirmation(eligible,locations:locations,ignoring:excluding,after:boundary) else {return nil}
            return ObservedTurn(color:color,locations:locations,estimate:supportedEstimate(first,after:boundary),confirmation:confirmation)
        }.sorted{$0.estimate.time<$1.estimate.time}
    }
}
