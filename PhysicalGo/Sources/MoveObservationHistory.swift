import Foundation

/// Short-lived, uncommitted hypotheses. Only fully matched legal positions supply
/// evidence; obscured frames pause confirmation rather than erase earlier sightings.
@MainActor struct MoveObservationHistory {
    struct Witness:Codable {
        let time:Double
        var depth:Int
        let unknown:Set<Int>
        // Older pending checkpoints omit this optional evidence.
        var clearSingle: Bool?
        var complete=true
        var placementUncertain=Set<Int>()
    }
    struct Candidate {
        var moves:[Int]
        var boards:[BoardSnapshot]
        var witnesses:[Witness]
        var requiredFrames:[Int]
        var requiredSeconds:[Double]
        var locked=Set<Int>()
        var placementConcerns=Set<Int>()
        var locationChoices=[Int:Set<Int>]()
        var playerConfirmed=Set<Int>()
        // Display preference only. All legal alternatives still participate in
        // confirmation; prefer the directly observed location over a remap.
        var locationRemapCount=0
        var firstSeen:Double { witnesses.first?.time ?? .infinity }
    }
    struct Confirmation {
        let moves:[Int]
        let boards:[BoardSnapshot]
    }
    enum Result {
        case tracking(Int)
        case confirmed(Confirmation)
        case blocked(String,settling:Bool)
    }
    private(set) var candidates=[Candidate]()
    private var inputTimes=[Double]()
    private(set) var localEvidence=LocalMoveEvidence()
    var usedLocalEvidence=false
    private var revisionProposal: (moves:[Int], first:Double, last:Double, frames:Int)?
    private(set) var lastReconciliation: (before:[[Int]], after:[Int])?
    private var freshAfter:Double?
    private var expiredChronology=false
    private var expiredPoints=Set<Int>()
    static let lifetime=12.0
    static let maximumFrames=64
    static let maximumMoves=1024
    private static let maximumCandidates=16
    var pendingCount:Int { candidates.map { $0.moves.count }.max() ?? 0 }
    var frameCount:Int { inputTimes.count }
    var retainedWitnessCount:Int {candidates.reduce(0){$0+$1.witnesses.count}}

    mutating func reset() { revisionProposal=nil;lastReconciliation=nil;candidates=[];inputTimes=[];freshAfter=nil;expiredChronology=false;expiredPoints=[];localEvidence.reset();usedLocalEvidence=false }
    /// Keep compact ordering through pause/review, but require a completely fresh
    /// final-position check after resuming. Grid/settings/manual edits discard it.
    func retainedForResume(preserveLocalEvidence:Bool=false)->Self? {
        var copy=self
        copy.revisionProposal=nil;copy.lastReconciliation=nil
        copy.candidates=copy.candidates.filter{Self.hasAnchoredPrefix($0)}
        guard !copy.candidates.isEmpty else {return nil}
        copy.inputTimes=[];copy.freshAfter=nil
        if !preserveLocalEvidence {copy.localEvidence.reset()}
        for i in copy.candidates.indices {
            for j in copy.candidates[i].witnesses.indices {copy.candidates[i].witnesses[j].complete=false}
            copy.candidates[i].requiredFrames=copy.candidates[i].requiredFrames.map{max(8,$0)}
            copy.candidates[i].requiredSeconds=copy.candidates[i].requiredSeconds.map{max(1.4,$0)}
        }
        return copy
    }
    /// Compact pause checkpoint: boards are rebuilt with the rules engine rather
    /// than trusting serialized positions. Restoring always requires fresh views.
    struct Checkpoint:Codable {
        struct Path:Codable {
            let moves:[Int]
            let witnesses:[Witness]
            let requiredFrames:[Int]
            let requiredSeconds:[Double]
            let locked:Set<Int>
            let placementConcerns:Set<Int>
            var locationChoices:[Int:Set<Int>]?=nil
            var playerConfirmed:Set<Int>?=nil
            var locationRemapCount:Int?=nil
        }
        let paths:[Path]
    }
    var checkpoint:Checkpoint {
        Checkpoint(paths:(retainedForResume()?.candidates ?? []).map {
            .init(moves:$0.moves,witnesses:$0.witnesses,requiredFrames:$0.requiredFrames,
                  requiredSeconds:$0.requiredSeconds,locked:$0.locked,placementConcerns:$0.placementConcerns,locationChoices:$0.locationChoices,playerConfirmed:$0.playerConfirmed,locationRemapCount:$0.locationRemapCount)
        })
    }
    static func restore(_ checkpoint:Checkpoint,game:SGFGame,now:Double)->Self? {
        guard !checkpoint.paths.isEmpty,checkpoint.paths.count<=maximumCandidates else {return nil}
        var history=Self()
        let size=game.boardSize
        let latest=checkpoint.paths.flatMap(\.witnesses).map(\.time).max() ?? 0
        for path in checkpoint.paths {
            let count=path.moves.count
            guard (1...maximumMoves).contains(count),path.requiredFrames.count==count,path.requiredSeconds.count==count,
                  path.moves.allSatisfy({(0..<size*size).contains($0)}),
                  path.locked.union(path.placementConcerns).union(path.playerConfirmed ?? []).allSatisfy({(0..<count).contains($0)}),
                  (path.locationChoices ?? [:]).allSatisfy({(0..<count).contains($0.key) && $0.value.count<=9 && $0.value.allSatisfy{(0..<size*size).contains($0)}}),
                  (0...count).contains(path.locationRemapCount ?? 0),
                  path.requiredFrames.allSatisfy({(1...1000).contains($0)}),
                  path.requiredSeconds.allSatisfy({$0.isFinite && $0>=0 && $0<=60}),
                  !path.witnesses.isEmpty,path.witnesses.count<=maximumFrames+maximumMoves*2,
                  path.witnesses.allSatisfy({$0.time.isFinite && (1...count).contains($0.depth) && $0.unknown.union($0.placementUncertain).allSatisfy{(0..<size*size).contains($0)}}) else {return nil}
            let player=SGFPlayer();player.load(game:game);player.seek(to:game.moves.count)
            var boards=[BoardSnapshot]()
            for point in path.moves {
                guard player.tryPlayMove(color:player.turn,x:point%size,y:point/size)==nil else {return nil}
                boards.append(player.board)
            }
            // Preserve intervals used for chronology, but never reuse old views
            // as current visual confirmation (including across a machine reboot).
            let witnesses=path.witnesses.map {
                Witness(time:now-Self.lifetime-1+($0.time-latest),depth:$0.depth,unknown:$0.unknown,
                        complete:false,placementUncertain:$0.placementUncertain)
            }
            history.candidates.append(Candidate(moves:path.moves,boards:boards,witnesses:witnesses,
                requiredFrames:path.requiredFrames,requiredSeconds:path.requiredSeconds,
                locked:path.locked,placementConcerns:path.placementConcerns,locationChoices:path.locationChoices ?? [:],playerConfirmed:path.playerConfirmed ?? [],locationRemapCount:path.locationRemapCount ?? 0))
        }
        return history.retainedForResume()
    }
    func correcting(_ edits:[Int:Int],game:SGFGame)throws->Self {
        guard !edits.isEmpty else {throw RecordingStore.Failure(message:"Choose a location to confirm.")}
        var copy=self,paths=[Candidate]()
        for original in candidates {
            guard edits.keys.allSatisfy({original.moves.indices.contains($0)}),
                  edits.values.allSatisfy({(0..<game.boardSize*game.boardSize).contains($0)}) else {continue}
            var path=original
            for (offset,point) in edits {
                path.moves[offset]=point;path.playerConfirmed.insert(offset);path.locked.insert(offset)
                path.locationChoices[offset,default:[]].formUnion([point,original.moves[offset]])
            }
            let player=SGFPlayer();player.load(game:game);player.seek(to:game.moves.count)
            var boards=[BoardSnapshot]()
            for point in path.moves {
                guard player.tryPlayMove(color:player.turn,x:point%game.boardSize,y:point/game.boardSize)==nil else {break}
                boards.append(player.board)
            }
            if boards.count==path.moves.count {path.boards=boards;paths.append(path)}
        }
        guard !paths.isEmpty else {throw RecordingStore.Failure(message:"These locations conflict with a later move. Adjust the affected placements before confirming.")}
        var seen=Set<[Int]>()
        copy.candidates=paths.filter{seen.insert($0.moves).inserted}
        copy.revisionProposal=nil;copy.lastReconciliation=nil
        return copy
    }
    mutating func interruptLocally() { revisionProposal=nil;freshAfter=inputTimes.last }
    mutating func noteFrame(now:Double)->Bool {
        guard inputTimes.last.map({now>$0}) ?? true else {return false}
        inputTimes.append(now)
        inputTimes.removeAll { now-$0>Self.lifetime }
        if inputTimes.count>Self.maximumFrames { inputTimes.removeFirst(inputTimes.count-Self.maximumFrames) }
        let oldest=inputTimes.first ?? now
        // Raw observations expire, but a repeatedly witnessed move order is a
        // compact game fact. Keep it while an earlier stone is obscured, so later
        // placements can still extend the tentative game. A single flash cannot
        // acquire this durable chronology.
        for candidate in candidates where candidate.firstSeen<oldest && !Self.hasAnchoredPrefix(candidate) {
            expiredChronology=true;expiredPoints.formUnion(candidate.moves)
        }
        candidates.removeAll { $0.firstSeen<oldest && !Self.hasAnchoredPrefix($0) }
        for i in candidates.indices {
            // Retain recent confirmation views and two old ordering witnesses at
            // each depth. Memory is bounded by the tentative move count, not time.
            let old=candidates[i].witnesses.filter{$0.time<oldest}
            var retained=[Witness]()
            for depth in 1...max(1,candidates[i].moves.count) {
                let point=candidates[i].moves[depth-1]
                let useful=old.filter{$0.depth==depth && !$0.unknown.contains(point)}
                if let first=useful.first {retained.append(first)
                    if let second=useful.first(where:{$0.time-first.time>=0.15}) {retained.append(second)}
                }
            }
            candidates[i].witnesses=retained+candidates[i].witnesses.filter{$0.time>=oldest}
        }
        return true
    }
    func canVerifyRest(_ readings:[Occupancy],base:[Occupancy])->Bool {
        let points=expiredPoints.union(candidates.flatMap(\.moves)).union(localEvidence.unresolvedPoints(base:base))
        return points.allSatisfy { readings[$0] != .uncertain }
    }
    mutating func retainLocalEvidence(_ readings:[Occupancy],base:[Occupancy],now:Double) {
        localEvidence.observe(readings,base:base,now:now)
    }
    mutating func rebase(after count:Int) {
        for i in candidates.indices {
            candidates[i].locked=Set(candidates[i].locked.filter{$0>=count}.map{$0-count})
            candidates[i].placementConcerns=Set(candidates[i].placementConcerns.filter{$0>=count}.map{$0-count})
            candidates[i].locationChoices=Dictionary(uniqueKeysWithValues:candidates[i].locationChoices.filter{$0.key>=count}.map{($0.key-count,$0.value)})
            candidates[i].playerConfirmed=Set(candidates[i].playerConfirmed.filter{$0>=count}.map{$0-count})
            candidates[i].moves.removeFirst(count)
            candidates[i].boards.removeFirst(count)
            candidates[i].requiredFrames.removeFirst(count)
            candidates[i].requiredSeconds.removeFirst(count)
            candidates[i].witnesses=candidates[i].witnesses.compactMap { witness in
                guard witness.depth>count else { return nil }
                return Witness(time:witness.time,depth:witness.depth-count,unknown:witness.unknown,complete:witness.complete,placementUncertain:witness.placementUncertain)
            }
        }
        candidates.removeAll { $0.moves.isEmpty }
        if candidates.isEmpty { freshAfter=nil }
    }
    private func states(_ board:BoardSnapshot)->[Occupancy] {
        board.grid.flatMap{$0}.map { $0 == .black ? .black : $0 == .white ? .white : .empty }
    }
    /// An unreadable, unchanged recorded stone retains its identity. A clear
    /// contradiction, new placement, or capture removal still needs fresh evidence.
    /// Camera alignment and broad loss of empty-board visibility are separate gates.
    static func confirmedOcclusions(_ readings:[Occupancy],base:[Occupancy],after:[Occupancy])->Set<Int> {
        guard readings.count==base.count,after.count==base.count else {return []}
        return Set(readings.indices.filter {
            readings[$0] == .uncertain && base[$0].stone != nil && after[$0]==base[$0]
        })
    }
    private static func unchangedDisappearances(_ readings:[Occupancy],base:[Occupancy],after:[Occupancy],moves:[Int])->Set<Int> {
        let changed=Set(moves)
        return Set(readings.indices.filter {
            readings[$0] == .empty && base[$0].stone != nil && after[$0]==base[$0] && !changed.contains($0)
        })
    }
    private func matches(_ readings:[Occupancy],_ board:BoardSnapshot,base:[Occupancy],moves:[Int],allowOccluded:Bool=false)->Bool {
        let after=states(board), changed=Set(moves)
        let retained=Self.confirmedOcclusions(readings,base:base,after:after).subtracting(changed)
        // A small local contradiction must not erase the chronology of later
        // visible moves. Retain hypotheses only; complete witnesses and SGF
        // confirmation still require the recorded stones to agree. A broad
        // disappearance remains a gap, not permission to infer new history.
        let missing=allowOccluded ? Self.unchangedDisappearances(readings,base:base,after:after,moves:moves):[]
        return readings.indices.allSatisfy {
            readings[$0] == after[$0] || (missing.count<=2 && missing.contains($0)) || (readings[$0] == .uncertain && (allowOccluded || retained.contains($0) || (base[$0] == .empty && after[$0] == .empty && !changed.contains($0))))
        }
    }
    private func anchored(_ candidate:Candidate)->Bool {
        guard let last=candidate.moves.last else {return false}
        let times=candidate.witnesses.filter{$0.depth==candidate.moves.count && !$0.unknown.contains(last)}.map(\.time)
        return times.count>=2 && times.last!-times.first!>=0.15
    }
    private static func hasAnchoredPrefix(_ candidate:Candidate)->Bool {
        guard !candidate.moves.isEmpty else {return false}
        for depth in 1...candidate.moves.count {
            let point=candidate.moves[depth-1]
            let times=candidate.witnesses.filter{$0.depth==depth && !$0.unknown.contains(point)}.map(\.time)
            if times.count>=2 && times.last!-times.first!>=0.15 {return true}
        }
        return false
    }
    var awaitingClarity:Bool {candidates.contains { candidate in
        candidate.witnesses.last?.complete == false || candidate.moves.enumerated().contains {
            !candidate.locked.contains($0.offset) && candidate.witnesses.last?.placementUncertain.contains($0.element)==true
        }
    }}
    var tentativeSequences:[[Int]] {candidates.map(\.moves)}
    struct MoveConfidence:Codable {
        let point:Int?
        let level:String
        let clearSightings:Int
        let requiredSightings:Int
        let orderSupported:Bool
        var alternatives:[Int]=[]
        var placementUncertain=false
    }
    /// Evidence levels, not calibrated probabilities. A later move can have
    /// strong sightings while SGF still waits for an unresolved earlier move.
    var bestCandidate:Candidate? {
        candidates.sorted { a,b in
            let at=a.witnesses.last?.time ?? 0,bt=b.witnesses.last?.time ?? 0
            if at != bt {return at>bt}
            if a.locationRemapCount != b.locationRemapCount {return a.locationRemapCount<b.locationRemapCount}
            let av=a.witnesses.filter(\.complete).count,bv=b.witnesses.filter(\.complete).count
            if av != bv {return av>bv}
            if a.moves.count != b.moves.count {return a.moves.count>b.moves.count}
            return a.moves.lexicographicallyPrecedes(b.moves)
        }.first
    }
    var moveConfidence:[MoveConfidence] {
        guard let first=bestCandidate,let latest=inputTimes.last ?? candidates.flatMap({$0.witnesses}).map(\.time).max() else {return []}
        return (0..<pendingCount).map { index in
            guard first.moves.indices.contains(index),candidates.allSatisfy({$0.moves.count>index && $0.moves[index]==first.moves[index]}) else {
                let point=first.moves.indices.contains(index) ? first.moves[index] : nil
                let alternatives=Set(candidates.compactMap{$0.moves.indices.contains(index) ? $0.moves[index] : nil}).subtracting(point.map{[$0]} ?? []).sorted()
                return MoveConfidence(point:point,level:"low",clearSightings:0,requiredSightings:0,orderSupported:false,alternatives:alternatives,placementUncertain:candidates.contains{!($0.locationChoices[index] ?? []).isEmpty})
            }
            let point=first.moves[index],size=first.boards[index].size
            if candidates.allSatisfy({$0.playerConfirmed.contains(index)}) {return MoveConfidence(point:point,level:"high",clearSightings:0,requiredSightings:0,orderSupported:true)}
            var fewest=Int.max,required=0,strong=true,repeated=true
            for candidate in candidates {
                let color=candidate.boards[index].grid[point/size][point%size]
                let views=candidate.witnesses.filter {
                    $0.depth>index && latest-$0.time<=Self.lifetime && !$0.unknown.contains(point) && !$0.placementUncertain.contains(point) &&
                    candidate.boards[$0.depth-1].grid[point/size][point%size]==color
                }
                let span=(views.last?.time ?? 0)-(views.first?.time ?? 0)
                fewest=min(fewest,views.count);required=max(required,candidate.requiredFrames[index])
                strong = strong && (candidate.locked.contains(index) || (views.count>=candidate.requiredFrames[index] && span>=candidate.requiredSeconds[index]))
                repeated = repeated && views.count>=2 && span>=0.15
            }
            return MoveConfidence(point:point,level:strong ? "high" : repeated ? "medium" : "low",
                clearSightings:fewest,requiredSightings:required,orderSupported:true,
                placementUncertain:candidates.contains{!$0.locked.contains(index) && $0.witnesses.last?.placementUncertain.contains(point)==true})
        }
    }

    private static func unresolved(_ witnesses:[Witness])->Int {
        var counts=[Int:Int]()
        for witness in witnesses { for index in witness.unknown { counts[index,default:0] += 1 } }
        return counts.values.filter { witnesses.count-$0<2 }.count
    }

    /// Resolve a small, local adjustment of UNCOMMITTED stones. Historical
    /// sightings establish order, but cannot keep an intersection occupied after
    /// repeated clear contradictions. Never rewrite the saved game or a capture.
    private mutating func reconcileAdjustment(readings:[Occupancy], game:SGFGame,
                                              base:BoardSnapshot, now:Double,
                                              observation:BoardObservation) {
        lastReconciliation=nil
        let expected=states(base),size=base.size
        let additions=Set(readings.indices.filter { expected[$0] == .empty && readings[$0].stone != nil })
        // Competing historical orders require review; resolving one must never
        // erase a settled assignment belonging to another surviving hypothesis.
        guard candidates.count==1, candidates.allSatisfy({(1...8).contains($0.moves.count)}),
              !additions.isEmpty, additions.count<=8,
              expected.indices.allSatisfy({expected[$0] == .empty || readings[$0]==expected[$0]}) else {
            revisionProposal=nil;return
        }
        func nearby(_ a:Int,_ b:Int)->Bool {max(abs(a/size-b/size),abs(a%size-b%size))<=1}
        var solutions=[String:Candidate]()
        for original in candidates {
            // No disappearance in a recorded capture may be reinterpreted as an
            // adjustment, including captures inside the pending sequence.
            var previous=expected,noncapturing=true
            for board in original.boards {
                let after=states(board)
                if previous.indices.contains(where:{previous[$0].stone != nil && previous[$0] != after[$0]}) {noncapturing=false;break}
                previous=after
            }
            guard noncapturing else {continue}
            let missing=original.moves.filter{readings[$0] == .empty}
            guard !missing.isEmpty else {continue}
            let relevant=Set(original.moves).union(additions)
            guard relevant.allSatisfy({readings[$0] != .uncertain && observation.readings[$0].confidence>=0.90}) else {continue}
            var branches=0
            func visit(_ index:Int,_ moves:[Int],_ relocated:[(Int,Int)],_ dropped:[Int]) {
                branches += 1
                guard branches<=512,dropped.count<=2,relocated.count<=1 else {return}
                if index==original.moves.count {
                    guard relocated.count==1,Set(moves)==additions,
                          dropped.allSatisfy({nearby($0,relocated[0].0) || nearby($0,relocated[0].1)}) else {return}
                    let trial=SGFPlayer();trial.load(game:game);trial.seek(to:game.moves.count)
                    var boards=[BoardSnapshot](),before=expected
                    for point in moves {
                        guard readings[point].stone==trial.turn,
                              trial.tryPlayMove(color:trial.turn,x:point%size,y:point/size)==nil else {return}
                        let after=states(trial.board)
                        guard before.indices.allSatisfy({$0==point || before[$0]==after[$0]}) else {return}
                        boards.append(trial.board);before=after
                    }
                    guard matches(readings,trial.board,base:expected,moves:moves) else {return}
                    // Old witnesses described different positions. Preserve only
                    // the uniquely determined order; earn all confirmation anew.
                    solutions[moves.map(String.init).joined(separator:",")]=Candidate(moves:moves,boards:boards,witnesses:[],
                        requiredFrames:Array(repeating:8,count:moves.count),requiredSeconds:Array(repeating:1.4,count:moves.count),
                        locked:Set(original.locked.compactMap{moves.firstIndex(of:original.moves[$0])}))
                    return
                }
                let point=original.moves[index]
                let color=original.boards[index].grid[point/size][point%size]!
                if readings[point].stone==color && !moves.contains(point) {
                    visit(index+1,moves+[point],relocated,dropped)
                    return
                }
                guard !original.locked.contains(index) else {return}
                // A duplicate later hypothesis may refer to the same physical
                // stone already assigned to its earlier appearance.
                if moves.contains(point) {
                    visit(index+1,moves,relocated,dropped+[point]);return
                }
                guard readings[point] == .empty else {return}
                visit(index+1,moves,relocated,dropped+[point])
                if relocated.isEmpty {
                    for target in additions.sorted() where !moves.contains(target) && nearby(point,target) && readings[target].stone==color {
                        // Do not steal a separately witnessed, settled identity.
                        guard !original.moves.enumerated().contains(where:{original.locked.contains($0.offset) && $0.element==target}) else {continue}
                        visit(index+1,moves+[target],relocated+[(point,target)],dropped)
                    }
                }
            }
            visit(0,[],[],[])
            if branches>512 {revisionProposal=nil;return}
        }
        guard solutions.count==1,let revised=solutions.values.first else {revisionProposal=nil;return}
        if let prior=revisionProposal,prior.moves==revised.moves,now-prior.last<=0.6 {
            revisionProposal=(revised.moves,prior.first,now,prior.frames+1)
        } else {revisionProposal=(revised.moves,now,now,1)}
        guard let proposal=revisionProposal,proposal.frames>=5,now-proposal.first>=0.8 else {return}
        lastReconciliation=(candidates.map(\.moves),revised.moves)
        var retained=revised
        // The proposed position itself was observed repeatedly. Retain two
        // ordering witnesses so an immediate pause/restart cannot lose its order,
        // but mark them incomplete: final acceptance still needs fresh views.
        let unseen=Set(readings.indices).subtracting(revised.moves)
        retained.witnesses=[proposal.first,proposal.last].map {
            Witness(time:$0,depth:revised.moves.count,unknown:unseen,complete:false)
        }
        // The caller will append the current frame once; do not duplicate its
        // timestamp when candidate witnesses are merged.
        retained.witnesses.removeAll{$0.time==now}
        candidates=[retained];revisionProposal=nil;freshAfter=now
    }

    mutating func observe(readings:[Occupancy],game:SGFGame,base:BoardSnapshot,
                          now:Double,recovering:Bool,unclearLimit:Int,observation:BoardObservation)->Result {
        let placementOffsets = observation.placementOffsets
        guard !expiredChronology else {
            return .blocked("Earlier unconfirmed moves are too old to order reliably. Pause and review the missed moves.",settling:false)
        }
        reconcileAdjustment(readings:readings,game:game,base:base,now:now,observation:observation)
        let expected=states(base), size=game.boardSize
        let assignmentOffsets = observation.assignmentOffsets(confirmedBoard:expected)
        let choices=observation.placementAlternatives(base:expected)
        func candidateReadings(_ candidate:Candidate)->[Occupancy] {
            var values=readings
            guard let board=candidate.boards.last else {return values}
            for (offset,locations) in candidate.locationChoices where candidate.moves.indices.contains(offset) {
                let target=candidate.moves[offset]
                guard let color=board.grid[target/size][target%size],
                      let source=locations.first(where:{readings[$0].stone==color}),
                      locations.filter({readings[$0].stone != nil}).count==1 else {continue}
                // Geometry quality can jitter below the alternative-location threshold.
                // One visible body still represents the same retained move; do
                // not count it again after an intervening opponent move.
                // Positive centered evidence at the other point may resolve the
                // alternative, and two visible bodies are never merged above.
                if source != target, readings[target] == .empty,
                   let offset=assignmentOffsets[source],offset<=0.24 {continue}
                values[source] = .empty;values[target]=color == .black ? .black:.white
            }
            return values
        }
        let unknown=Set(readings.indices.filter{readings[$0] == .uncertain})
        // Even without a whole-board hypothesis, a previously seen stone under
        // uncertainty may precede today's visible additions. Never silently
        // replace it with a later same-color stone. Clear empty evidence resolves
        // false candidates; uncertainty does not.
        if localEvidence.unresolvedPoints(base:expected).subtracting(candidates.flatMap(\.moves)).contains(where:{readings[$0] == .uncertain}) {
            return .blocked("An earlier candidate stone is obscured. Keeping local evidence until its intersection is clear.",settling:true)
        }
        // Only seed from local evidence after a sufficiently clear whole-board
        // view returns. No noisy frame supplies confirmation witnesses. Restrict
        // this fallback to surviving additions; unseen captures/passes are never
        // invented. Local evidence can also bridge an existing hypothesis when
        // another move arrives before its latest whole-board view repeats. It
        // must extend every retained prefix, never replace an earlier sequence.
        var localContinuation:Candidate?
        do {
            let additions=readings.indices.filter{readings[$0].stone != nil && readings[$0] != expected[$0]}
            if (3...8).contains(additions.count),
               additions.allSatisfy({expected[$0] == .empty}),
               let order=localEvidence.uniqueOrder(additions:additions,readings:readings,blackToPlay:(game.moves.last?.0.opponent ?? game.analysisSettings.initialPlayer) == .black),
               !candidates.contains(where:{$0.moves==order}),
               candidates.allSatisfy({order.starts(with:$0.moves)}) {
                let trial=SGFPlayer();trial.load(game:game);trial.seek(to:game.moves.count)
                var boards=[BoardSnapshot]()
                for point in order {
                    guard trial.tryPlayMove(color:trial.turn,x:point%size,y:point/size)==nil else {break}
                    boards.append(trial.board)
                }
                if boards.count==order.count && matches(readings,trial.board,base:expected,moves:order) {
                    localContinuation=Candidate(moves:order,boards:boards,witnesses:[],
                        requiredFrames:Array(repeating:8,count:order.count),requiredSeconds:Array(repeating:1.4,count:order.count))
                }
            }
        }
        func isClearSingle(_ candidate: Candidate) -> Bool {
            guard !recovering, freshAfter == nil, candidate.moves.count == 1,
                  candidate.requiredFrames == [5], candidate.placementConcerns.isEmpty,
                  let point = candidate.moves.first, let offset = placementOffsets[point],
                  offset <= 0.20, observation.readings[point].confidence >= 0.95,
                  unknown.subtracting(Self.confirmedOcclusions(readings,base:expected,after:states(candidate.boards[0]))).count <= min(9, unclearLimit) else { return false }

            let after = states(candidate.boards[0])
            let retained=Self.confirmedOcclusions(readings,base:expected,after:after)
            return expected.indices.allSatisfy { index in
                if index == point { return expected[index] == .empty && readings[index] == after[index] }
                guard after[index] == expected[index] else { return false } // A capture needs full confirmation.
                if readings[index] == expected[index] || retained.contains(index) { return true }
                let distance = max(abs(index / size - point / size), abs(index % size - point % size))
                return distance > 1 && readings[index] == .uncertain && (expected[index] == .empty || retained.contains(index))
            }
        }
        func witness(_ candidate:inout Candidate)->Witness {
            let raw=readings
            let readings=candidateReadings(candidate)
            candidate.locationRemapCount=candidate.moves.filter{readings[$0].stone != nil && readings[$0] != raw[$0]}.count
            let unknown=Set(readings.indices.filter{readings[$0] == .uncertain})
            var uncertain=Set<Int>()
            for (index,point) in candidate.moves.enumerated() where !candidate.locked.contains(index) {
                if candidate.playerConfirmed.contains(index) {continue}
                if let offset=assignmentOffsets[point],offset>=0.30 {candidate.placementConcerns.insert(index)}
                if let locations=candidate.locationChoices[index],choices.values.contains(where:{$0.intersection(locations).count>1}) {uncertain.insert(point)}
                // Once flagged, require an outline safely inside the cell before
                // fresh sightings can settle the assignment. Absence of an
                // outline and threshold jitter do not erase a placement concern.
                if candidate.placementConcerns.contains(index),assignmentOffsets[point].map({$0>0.24+1e-9}) ?? true {uncertain.insert(point)}
            }
            // Only unresolved intersections count against this candidate. Keep
            // every played point unknown until directly seen, even if it returns
            // to the same color as the base after a capture/replay.
            let retained=Self.confirmedOcclusions(readings,base:expected,after:states(candidate.boards.last!)).subtracting(candidate.moves)
            return Witness(time:now,depth:candidate.moves.count,unknown:unknown.subtracting(retained),clearSingle:isClearSingle(candidate),
                complete:matches(readings,candidate.boards.last!,base:expected,moves:candidate.moves),placementUncertain:uncertain)
        }
        var matched=[Candidate]()
        var reason="A recorded stone is missing or uncertain. Check the physical board before continuing."
        var settling=readings.indices.contains { expected[$0].stone != nil && readings[$0] == .uncertain }
        let root=Candidate(moves:[],boards:[],witnesses:[],requiredFrames:[],requiredSeconds:[])
        // Keep a route past an unconfirmed one-frame tail. Without this, a
        // fleeting extra dark patch can monopolize the next turn while a much
        // earlier placement remains pending. Only previously anchored prefixes
        // may branch; locked assignments and witnessed chronology stay protected.
        let prefixes=candidates.compactMap { candidate -> Candidate? in
            guard candidate.moves.count>1 else {return nil}
            let tailWasAnchored=anchored(candidate)
            if tailWasAnchored {
                let last=candidate.moves.count-1,point=candidate.moves[last]
                // A repeated hand-shaped flash can anchor a tentative tail without
                // confirming it. Let repeated EMPTY observations retract that one
                // unlocked, non-capturing tail. Do not discard an earlier move,
                // a locked identity, an obscured point or an observed capture.
                guard !candidate.locked.contains(last),readings[point] == .empty,
                      localEvidence.repeatedlyEmpty(point) else {return nil}
                let before=states(candidate.boards[last-1]),after=states(candidate.boards[last])
                guard before[point] == .empty,
                      before.indices.allSatisfy({$0==point || before[$0]==after[$0]}) else {return nil}
                let additions=readings.indices.filter{readings[$0].stone != nil && readings[$0] != before[$0]}
                // An opposite-color addition may have captured a real tail. Only
                // consider rest or ONE replacement of the same color here; the
                // usual rules and whole-position check must still accept it.
                guard additions.count<=1,additions.allSatisfy({readings[$0]==after[point]}) else {return nil}
            }
            for depth in stride(from:candidate.moves.count-1,through:1,by:-1) {
                if tailWasAnchored && depth != candidate.moves.count-1 {break}
                var prefix=candidate
                prefix.moves=Array(candidate.moves.prefix(depth));prefix.boards=Array(candidate.boards.prefix(depth))
                prefix.requiredFrames=Array(candidate.requiredFrames.prefix(depth));prefix.requiredSeconds=Array(candidate.requiredSeconds.prefix(depth))
                if tailWasAnchored {
                    // A real move and a false reply may first appear together.
                    // Keep the real prefix's ordering evidence from those paired
                    // views, but do not call them complete views of the shortened
                    // position. A fresh matching frame is still required below.
                    prefix.witnesses=candidate.witnesses.map { witness in
                        var view=witness
                        if view.depth>depth {view.depth=depth;view.complete=false}
                        return view
                    }
                } else {prefix.witnesses=candidate.witnesses.filter{$0.depth<=depth}}
                prefix.locked=Set(candidate.locked.filter{$0<depth});prefix.placementConcerns=Set(candidate.placementConcerns.filter{$0<depth})
                if anchored(prefix) {return prefix}
            }
            return nil
        }
        for source in candidates+prefixes+(localContinuation.map{[$0]} ?? [])+[root] {
            let readings=candidateReadings(source)
            let previous=source.boards.last ?? base
            if !source.moves.isEmpty && matches(readings,previous,base:expected,moves:source.moves,allowOccluded:true) {
                var candidate=source
                let view=witness(&candidate);candidate.witnesses.append(view)
                matched.append(candidate)
                continue
            }
            let previousStates=states(previous)
            let additions=readings.indices.filter { readings[$0].stone != nil && readings[$0] != previousStates[$0] }
            guard (1...2).contains(additions.count), source.moves.count+additions.count<=Self.maximumMoves else {
                if source.moves.isEmpty && additions.count>2 {
                    reason="\(additions.count) unrecorded stones are visible, but their order was not observed clearly. Pause and review the missed moves."
                }
                continue
            }
            let trial=SGFPlayer();trial.load(game:game);trial.seek(to:game.moves.count)
            for index in source.moves { trial.tryPlayMove(color:trial.turn,x:index%size,y:index/size) }
            let ordered=additions.sorted { readings[$0].stone == trial.turn && readings[$1].stone != trial.turn }
            if ordered.count==2 && readings[ordered[0]] == readings[ordered[1]] {
                if source.moves.isEmpty { reason="Two new stones have the same color. Their intervening move is not visible; pause and review the missed moves." }
                continue
            }
            guard readings[ordered[0]].stone == trial.turn else {
                if source.moves.isEmpty { reason="Waiting for \(trial.turn.rawValue)'s move. Check the board or enter a pass if one was played." }
                continue
            }
            // Alternation can order a genuinely simultaneous pair, but cannot
            // reverse an observed out-of-turn placement. Once its evidence has
            // expired, do not interpret that old unmatched stone as a new reply.
            if ordered.count==2 && (ordered.contains(where:{localEvidence.expiredPoints.contains($0)}) ||
                localEvidence.wasPresentBeforeAppearance(ordered[1],ordered[0],readings:readings)) {
                reason="The observed move order conflicts with alternating turns. Pause and review the missed moves."
                continue
            }
            // A quick reply may arrive after only one whole-board sighting of
            // the previous move. Local evidence can establish that order too:
            // the previous stone was repeatedly present while the next point
            // was still repeatedly empty. This also works after captures; it
            // extends the existing legal path instead of rebuilding additions
            // relative to the last saved (possibly pre-capture) position.
            let locallyAnchored=source.moves.last.map { point in
                readings[point] == previousStates[point] &&
                localEvidence.precedes(point,ordered[0],readings:readings)
            } ?? false
            guard source.moves.isEmpty || anchored(source) || locallyAnchored else {continue}
            var candidate=source, legal=true
            for index in ordered {
                if let rejection=trial.tryPlayMove(color:readings[index].stone!,x:index%size,y:index/size) {
                    if source.moves.isEmpty { reason=rejection.rawValue }
                    legal=false;break
                }
                candidate.moves.append(index);candidate.boards.append(trial.board)
                let stronger=recovering || ordered.count==2
                candidate.requiredFrames.append(stronger ? 8 : 5)
                candidate.requiredSeconds.append(stronger ? 1.4 : 0.8)
            }
            guard legal else { continue }
            guard matches(readings,trial.board,base:expected,moves:candidate.moves,allowOccluded:true) else {
                let after=states(trial.board)
                let capturesPending=readings.indices.contains { previousStates[$0].stone != nil && after[$0] == .empty && readings[$0] == previousStates[$0] }
                if source.moves.isEmpty {
                    reason="Waiting for a clear view of the move and any captured stones to be removed. History is unchanged."
                    settling = settling || capturesPending
                }
                continue
            }
            let view=witness(&candidate);candidate.witnesses.append(view)
            matched.append(candidate)
            if locallyAnchored && !anchored(source) {usedLocalEvidence=true}
        }
        for candidate in matched {
            for index in candidate.moves.indices where !candidate.locked.contains(index) && !candidate.playerConfirmed.contains(index) {
                let point=candidate.moves[index]
                guard let alternatives=choices[point],candidate.locationChoices[index]==nil else {continue}
                for target in alternatives {
                    var alternate=candidate;alternate.moves[index]=target
                    let trial=SGFPlayer();trial.load(game:game);trial.seek(to:game.moves.count)
                    var boards=[BoardSnapshot]()
                    for move in alternate.moves {
                        guard trial.tryPlayMove(color:trial.turn,x:move%size,y:move/size)==nil else {break}
                        boards.append(trial.board)
                    }
                    guard boards.count==alternate.moves.count else {continue}
                    alternate.boards=boards;alternate.locationChoices[index]=alternatives
                    let mapped=candidateReadings(alternate)
                    alternate.locationRemapCount=alternate.moves.filter{mapped[$0].stone != nil && mapped[$0] != readings[$0]}.count
                    alternate.placementConcerns.insert(index)
                    alternate.witnesses=alternate.witnesses.map {old in
                        return Witness(time:old.time,depth:old.depth,unknown:old.unknown.subtracting([target]),
                            clearSingle:false,complete:old.complete,placementUncertain:old.placementUncertain.union([target]))
                    }
                    matched.append(alternate)
                }
            }
        }
        // Repeated clear legal positions (including removals) eliminate old
        // geometric alternatives. A single noisy frame cannot decide history.
        for old in candidates where !old.locationChoices.isEmpty && !matched.contains(where:{$0.moves==old.moves}) {
            let decisive=matched.contains {candidate in
                let different=candidate.moves.indices.filter{old.moves.indices.contains($0) && old.moves[$0] != candidate.moves[$0]}
                let views=candidate.witnesses.filter {view in
                    view.complete && view.depth==candidate.moves.count && now-view.time<=0.65 && different.allSatisfy {index in
                        let point=candidate.moves[index]
                        // Captures can decide an old location, but earlier views
                        // of the ambiguous stone cannot count as new evidence.
                        return candidate.boards.last!.grid[point/size][point%size]==nil ||
                            (!view.placementUncertain.contains(point) && !view.unknown.contains(point))
                    }
                }
                return views.count>=3 && (views.last!.time-views.first!.time)>=0.4
            }
            if !decisive {matched.append(old)}
        }
        // An earlier stone disappearing under uncertainty must not let a later
        // same-color stone replace it as the first move. Only confident contrary
        // evidence or a fully observed legal continuation can resolve that order.
        var protectedPrefixes=[[Int]]()
        for candidate in candidates {
            for i in candidate.moves.indices {
                let point=candidate.moves[i]
                let visible=candidate.witnesses.filter{$0.depth>i && !$0.unknown.contains(point)}
                if candidate.locationChoices[i]==nil,readings[point] == .uncertain,
                   candidate.boards.last!.grid[point/size][point%size] != nil,
                   visible.count>=2,visible.last!.time-visible.first!.time>=0.15 {
                    protectedPrefixes.append(Array(candidate.moves.prefix(i+1)))
                }
            }
        }
        // Individually settled assignments survive later uncertainty even while
        // an earlier move holds up SGF export. This never makes a contradictory
        // current frame count as confirmation of the complete position.
        for candidate in candidates {
            for index in candidate.locked {
                matched.removeAll{$0.moves.count<=index || $0.moves[index] != candidate.moves[index]}
            }
        }
        if !protectedPrefixes.isEmpty {
            matched.removeAll { candidate in !protectedPrefixes.allSatisfy { candidate.moves.starts(with:$0) } }
            if matched.isEmpty {
                reason="An earlier unconfirmed stone is obscured. Keeping its place in the move sequence until the board is clear."
                settling=true
            }
        }
        // A frame inconsistent with every legal hypothesis is not evidence of a
        // new history. Keep the short buffer, but never credit it toward a move.
        guard !matched.isEmpty else { return .blocked(reason,settling:settling) }
        var merged=[String:Candidate]()
        for candidate in matched {
            let key=candidate.moves.map(String.init).joined(separator:",")
            if var old=merged[key] {
                var witnesses=Dictionary(uniqueKeysWithValues:old.witnesses.map{($0.time,$0)})
                for witness in candidate.witnesses {
                    if let prior=witnesses[witness.time],prior.depth==witness.depth {
                        var combined=witness
                        combined.placementUncertain.formUnion(prior.placementUncertain)
                        combined.complete = combined.complete && prior.complete
                        witnesses[witness.time]=combined
                    } else if witness.depth>(witnesses[witness.time]?.depth ?? 0) {witnesses[witness.time]=witness}
                }
                if (candidate.witnesses.last?.time ?? 0)>=(old.witnesses.last?.time ?? 0) {old.locationRemapCount=candidate.locationRemapCount}
                old.witnesses=witnesses.values.sorted{$0.time<$1.time}
                old.locked.formUnion(candidate.locked);old.placementConcerns.formUnion(candidate.placementConcerns)
                old.playerConfirmed.formUnion(candidate.playerConfirmed)
                old.locationChoices.merge(candidate.locationChoices){$0.union($1)}
                for i in old.moves.indices {
                    old.requiredFrames[i]=min(old.requiredFrames[i],candidate.requiredFrames[i])
                    old.requiredSeconds[i]=min(old.requiredSeconds[i],candidate.requiredSeconds[i])
                }
                merged[key]=old
            } else { merged[key]=candidate }
        }
        guard merged.count<=Self.maximumCandidates else {
            // Retain the last complete set of hypotheses for direct correction.
            // Exhausting the search budget must never erase timed history.
            expiredPoints.formUnion(merged.values.flatMap(\.moves))
            return .blocked("Too many possible move sequences. Pause and review the missed moves.",settling:false)
        }
        if let localContinuation,matched.contains(where:{$0.moves==localContinuation.moves}) {usedLocalEvidence=true}
        candidates=merged.values.sorted { $0.moves.lexicographicallyPrecedes($1.moves) }
        candidates.removeAll {
            let full=$0.witnesses.filter{$0.complete && now-$0.time<=Self.lifetime}
            return full.count>=5 && Self.unresolved(full)>unclearLimit
        }
        for (index,evidence) in moveConfidence.enumerated() where evidence.orderSupported && evidence.level=="high" {
            for c in candidates.indices where candidates[c].moves.count>index {candidates[c].locked.insert(index)}
        }
        guard let first=candidates.first else {
            return .blocked("Too many intersections remain uncertain during these moves. Keep hands out of view.",settling:true)
        }
        guard !candidates.contains(where:{
            !Self.unchangedDisappearances(readings,base:expected,after:states($0.boards.last!),moves:$0.moves).isEmpty
        }) else {return .tracking(pendingCount)}
        var confirmed=0
        for i in first.moves.indices {
            guard candidates.allSatisfy({$0.moves.count>i && $0.moves[i]==first.moves[i] && supported($0,index:i,base:base)}) else { break }
            confirmed += 1
        }
        if confirmed>0 {
            return .confirmed(Confirmation(moves:Array(first.moves.prefix(confirmed)),boards:Array(first.boards.prefix(confirmed))))
        }
        return .tracking(pendingCount)
    }
    private func supported(_ candidate:Candidate,index:Int,base:BoardSnapshot)->Bool {
        if candidate.playerConfirmed.contains(index) {
            return candidate.witnesses.last.map{$0.complete && $0.time==inputTimes.last} ?? false
        }
        if let freshAfter {
            guard candidate.witnesses.filter({$0.time>freshAfter}).count>=2 else { return false }
        }
        let point=candidate.moves[index],color=candidate.boards[index].grid[point/base.size][point%base.size]
        let capture=(index+1..<candidate.moves.count).first {
            candidate.boards[$0].grid[point/base.size][point%base.size] != color
        }
        let visible=candidate.witnesses.filter { $0.depth>index && !$0.unknown.contains(point) && (capture != nil || candidate.locked.contains(index) || !$0.placementUncertain.contains(point)) && (capture == nil || $0.depth<=capture!) }
        guard let first=visible.first,let last=visible.last else { return false }
        if let capture {
            // A rapidly captured new stone must have been directly seen twice;
            // its capturing move must itself reach full confirmation. Never infer
            // an invisible intermediate stone solely from the final position.
            return visible.count>=2 && last.time-first.time>=0.15 && supported(candidate,index:capture,base:base)
        }
        let recent=visible.filter{$0.complete && (inputTimes.last ?? $0.time)-$0.time<=Self.lifetime}
        guard let first=recent.first,let last=recent.last else {return false}
        if index == 0, candidates.count == 1, candidate.moves.count == 1,
           candidate.requiredFrames == [5], candidate.placementConcerns.isEmpty, freshAfter == nil {
            let lastThree = recent.suffix(3)
            // Intervening rejected/obscured frames also appear in inputTimes.
            if lastThree.count == 3, lastThree.allSatisfy({ $0.clearSingle == true }),
               lastThree.map(\.time).elementsEqual(inputTimes.suffix(3)),
               let start = lastThree.first?.time, (0.4...1.2).contains(last.time - start) {
                return true
            }
        }
        return recent.count>=candidate.requiredFrames[index] && last.time-first.time>=candidate.requiredSeconds[index]
    }
}
