import Foundation

@main struct CandidateHistoryTests {
    struct RecordedFrame:Decodable {
        let frameID:Int,capturedAt:Double,processedAt:Double,handObstructed:Bool,lightingBlocked:Bool
        let readings:[IntersectionReading],footprints:[StoneFootprint],placementFits:[StoneFootprint]
        let estimate:ClockPressEstimate?
    }
    struct RecordedSequence:Decodable {let frames:[RecordedFrame]}
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        var checks=0,comparisons=0,mismatches=0,frames=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        func compare(_ value:Bool,_ message:String) {comparisons+=1;if !value {mismatches+=1;print("MISMATCH: "+message)}}
        let empty=Array(repeating:Occupancy.empty,count:81)
        func view(_ values:[Occupancy],_ t:Double,score:Double=1,hand:ClockPressEstimate?=nil)->BoardObservation {
            let size=Int(Double(values.count).squareRoot())
            return .init(readings:values.enumerated().map{.init(row:$0.offset/size,col:$0.offset%size,occupancy:$0.element,confidence:score,delta:0)},size:size,capturedAt:t,handObstructed:false,clockPressEstimate:hand)
        }
        var board=empty;board[10] = .black
        var timing=ClearBoardTiming()
        timing.observe(view(empty,0.8),now:0.9,observationID:"empty")
        let weak=view(board,1,score:0.85)
        timing.observe(weak.discountingDarkReadings([10]),now:1.3,rawObservation:weak,observationID:"suspect",shadowPoints:[10])
        for t in [1.21,1.42,1.63,1.84] {timing.observe(view(board,t),now:t+0.3,observationID:"clear-\(t)")}
        let history=timing.candidateHistory(locations:[10],color:.black,after:0)!,snapshot=history.snapshot()
        check(snapshot.firstAppearanceAt==1 && snapshot.firstSupportedAt==1.21,"Raw appearance and trusted timing were conflated")
        check(snapshot.firstAppearanceObservationID=="suspect" && snapshot.firstSupportedObservationID=="clear-1.21","Candidate lost its observation identities")
        check(snapshot.lastDefiniteAbsenceAt==0.8 && snapshot.appearanceInterval?.presentBy==1.21,"Appearance bounds were lost")
        check(snapshot.pressEstimate?.time==1.21 && snapshot.confirmation?.capturedAt==1.84,"Confirmation delay replaced the move timestamp")
        check(snapshot.confirmation?.processedAt==2.14,"Capture and processing timestamps were conflated")
        check(snapshot.suspectedShadowSamples==1 && !snapshot.shadowClearanceKnown,"Hand clearance invented shadow clearance")
        check(history.sightings[0].rawScores[10]==0.85 && history.sightings[0].rawPoints==[10] && history.sightings[0].visiblePoints.isEmpty,"Quality interpretation overwrote a raw sighting")
        timing.discountDarkReadings([10],at:1.42)
        check(timing.candidateHistory(locations:[10],color:.black,after:0)?.snapshot().episode==snapshot.episode,"A quality revision changed candidate identity")
        check(timing.candidateHistory(locations:[10],color:.black,after:0)?.pressEstimate?.time==1.21,"Later shadow suspicion deleted earlier support")
        timing.observe(view(empty,2.05),now:2.1)
        for t in [2.26,2.47,2.68,2.89] {timing.observe(view(board,t),now:t+0.1)}
        let replayed=timing.candidateHistory(locations:[10],color:.black,after:0)!.snapshot()
        check(replayed.episode != snapshot.episode && replayed.firstAppearanceAt==2.26 && replayed.lastDefiniteAbsenceAt==2.05,"Removal/replay reused an old candidate episode")
        let previousEpisode=replayed.episode
        timing.reset();timing.observe(view(board,3),now:3.1)
        check(timing.candidateHistory(locations:[10],color:.black,after:0)!.snapshot().episode != previousEpisode,"Reset reused an observation epoch")
        timing.observe(view(board,5),now:5.1)
        check(timing.candidateHistory(locations:[10],color:.black,after:0)?.firstSupportedAt==5,"Camera gap inherited old timing")
        timing.consume(through:5)
        check(timing.candidateHistory(locations:[10],color:.black,after:0)==nil,"Consumed observations could press again")

        var handSupported=ClearBoardTiming()
        handSupported.observe(view(empty,0.8),now:0.9)
        let handExit=ClockPressEstimate(time:1,method:.handBracket,observedLower:0.99,observedUpper:1.01,estimatedError:0.01)
        for t in [1.2,1.41] {handSupported.observe(view(board,t,hand:handExit),now:t+0.2)}
        let handSnapshot=handSupported.candidateHistory(locations:[10],color:.black,after:0)!.snapshot()
        check(handSnapshot.firstSupportedAt==1.2 && handSnapshot.supportedHandExit==handExit && handSnapshot.pressEstimate==handExit,"Hand-exit interval was conflated with the first clear image")
        check(handSnapshot.confirmation?.capturedAt==1.41 && handSnapshot.appearanceInterval?.lastAbsentAt==0.8,"Hand support discarded separate appearance/confirmation bounds")
        check(!handSnapshot.shadowClearanceKnown,"A precise hand exit falsely certified shadow clearance")
        var ordered=ClearBoardTiming()
        for t in [1.0,1.21] {ordered.observe(view(board,t),now:t)}
        var reply=board;reply[20] = .white
        for t in [2.0,2.21,2.42,2.63] {ordered.observe(view(reply,t),now:t)}
        let black=ordered.candidateHistory(locations:[10],color:.black,after:0)!,white=ordered.candidateHistory(locations:[20],color:.white,after:0)!
        check(black.relativeOrder(to:white) == .before && white.relativeOrder(to:black) == .after,"Repeated intermediate evidence failed to separate appearance intervals")
        check(black.firstSupportedAt==1 && white.firstSupportedAt==2,"Candidates inherited a shared turn timestamp")
        var simultaneous=ClearBoardTiming()
        for t in [3.0,3.21,3.42,3.63] {simultaneous.observe(view(reply,t),now:t)}
        let a=simultaneous.candidateHistory(locations:[10],color:.black,after:0)!,b=simultaneous.candidateHistory(locations:[20],color:.white,after:0)!
        check(a.relativeOrder(to:b) == .unresolved && a.snapshot().confirmation != nil && b.snapshot().confirmation != nil,"Certain occupancy guessed an unresolved move order")
        // An ambiguous earlier pair must not erase an independently supported
        // later candidate. It does not authorize committing the earlier SGF order.
        var later=reply;later[30] = .black
        for t in [4.0,4.21,4.42,4.63] {simultaneous.observe(view(later,t),now:t)}
        check(simultaneous.candidateHistory(locations:[30],color:.black,after:0)?.pressEstimate?.time==4,"Earlier order ambiguity erased later local timing")
        let alias=ordered.candidateHistory(locations:[10,11],color:.black,after:0)!.snapshot()
        check(alias.possibleLocations==[10,11] && alias.observedLocation==10 && alias.confirmation != nil,"Location alternatives prevented independent occupancy/timing support")
        for t in [0.0,0.001,0.002] {timing.observe(view(board,t),now:t+0.1)}
        check(timing.candidateHistory(locations:[10],color:.black,after:0)?.pressEstimate==nil,"Out-of-order observations resurrected consumed timing")
        var bounded=ClearBoardTiming()
        for i in 0..<1100 {let t=Double(i)*0.01;bounded.observe(view(board,t),now:t)}
        check(bounded.candidateHistory(locations:[10],color:.black,after:0)!.sightings.count==1000,"Candidate history exceeded retained observations")

        func compareCaches(_ current:ClearBoardTiming,_ old:StageOneTimingOracle,base:[Occupancy],values:[Occupancy],at time:Double,label:String) {
            frames+=1
            for epoch in [0,time-0.5] {
                let lhs=current.observedTurns(base:base,excluding:[],after:epoch),rhs=old.observedTurns(base:base,excluding:[],after:epoch)
                compare(lhs.count==rhs.count,label+" turn count")
                for (x,y) in zip(lhs,rhs) {
                    compare(x.color==y.color && x.locations==y.locations && x.estimate==y.estimate,label+" turn identity/timing")
                    compare(x.confirmation.level.rawValue==y.confirmation.level.rawValue && x.confirmation.clearViews==y.confirmation.clearViews && x.confirmation.span==y.confirmation.span && x.confirmation.minimumScore==y.confirmation.minimumScore,label+" confirmation")
                }
                for color in [Stone.black,.white] {compare(current.pendingTurn(base:base,excluding:[],color:color,after:epoch)==old.pendingTurn(base:base,excluding:[],color:color,after:epoch),label+" pending timing")}
                let target=values.enumerated().map{$0.element == .uncertain ? base[$0.offset]:$0.element}
                let changed=Set(base.indices.filter{base[$0] != target[$0]})
                compare(current.estimate(target:target,changed:changed,after:epoch)==old.estimate(target:target,changed:changed,after:epoch),label+" completed-board timing")
                for p in changed where target[p].stone != nil {
                    let color=target[p].stone!
                    compare(current.provisionalEstimate(target:target,changed:changed,locations:[p],color:color,aliases:[],after:epoch)==old.provisionalEstimate(target:target,changed:changed,locations:[p],color:color,aliases:[],after:epoch),label+" provisional timing")
                }
            }
        }
        // Frozen stage-1 policy and the new histories see exactly the same inputs.
        // Quality revisions and lifecycle changes are mirrored; decisions are not.
        for scenario in ["clear","hand","weak","flicker","withdrawal","color","shadow","aliases","capture","gap","reset","consumed"] {
            var next=ClearBoardTiming(),old=StageOneTimingOracle()
            var base=empty
            if scenario=="capture" {base[11] = .white;base[12] = .white}
            for i in 0..<20 {
                let t=10+Double(i)*0.21+(scenario=="gap" && i>=10 ? 2:0)
                var values=base
                if i>=2 {values[10] = .black}
                if ["flicker","shadow"].contains(scenario) && [5,6].contains(i) {values[10] = .uncertain}
                if scenario=="withdrawal" && i==8 {values[10] = .empty}
                if scenario=="color" && i==8 {values[10] = .white}
                if scenario=="aliases" && i%2==0 && i>=2 {values[10] = .empty;values[11] = .black}
                if scenario=="capture" && i>=4 {values[11] = .empty;values[12] = i<8 ? .uncertain:.empty}
                let hand:ClockPressEstimate?=scenario=="hand" ? .init(time:10.3,method:.handBracket,observedLower:10.25,observedUpper:10.35,estimatedError:0.05):nil
                let observation=view(values,t,score:scenario=="weak" ? 0.92:1,hand:hand)
                next.observe(observation,now:t+0.2,observationID:"\(scenario)-\(i)");old.observe(observation,now:t+0.2)
                if scenario=="shadow" && i==7 {next.discountDarkReadings([10],at:10.42);old.discountDarkReadings([10],at:10.42)}
                if scenario=="reset" && i==9 {next.reset();old.reset()}
                if scenario=="consumed" && i==9 {next.consume(through:t);old.consume(through:t)}
                compareCaches(next,old,base:base,values:values,at:t,label:"\(scenario) frame \(i)")
                if scenario=="aliases" {
                    var target=empty;target[10] = .black
                    compare(next.provisionalEstimate(target:target,changed:[10],locations:[10,11],color:.black,aliases:[[10,11]],after:0)==old.provisionalEstimate(target:target,changed:[10],locations:[10,11],color:.black,aliases:[[10,11]],after:0),"alias grouping")
                }
            }
        }
        let path=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/RapidReplyShadow/sequence.json")
        let recorded=try JSONDecoder().decode(RecordedSequence.self,from:Data(contentsOf:path))
        var next=ClearBoardTiming(),old=StageOneTimingOracle(),shadow=ShadowEvidence()
        // Known seven-move starting position, including White's prior capture.
        var base=Array(repeating:Occupancy.empty,count:361)
        for p in [300,282,262,280] {base[p] = .black}
        for p in [60,72] {base[p] = .white}
        for f in recorded.frames {
            if f.handObstructed {
                for d in shadow.noteHandSamples(at:f.capturedAt,protected:[]) {next.discountDarkReadings(d.points,at:d.capturedAt);old.discountDarkReadings(d.points,at:d.capturedAt)}
                next.noteHand(at:f.capturedAt);old.noteHand(at:f.capturedAt)
            } else {
                let raw=BoardObservation(readings:f.readings,size:19,lightingBlocked:f.lightingBlocked,footprints:f.footprints,placementFits:f.placementFits,capturedAt:f.capturedAt,handObstructed:false,clockPressEstimate:f.estimate)
                let mask=shadow.discount(raw,base:base,protected:[],at:f.capturedAt,processedAt:f.processedAt)
                let observation=raw.discountingDarkReadings(mask)
                next.observe(observation,now:f.processedAt,rawObservation:raw,observationID:"recorded-\(f.frameID)",shadowPoints:mask);old.observe(observation,now:f.processedAt)
                compareCaches(next,old,base:base,values:observation.signature,at:f.capturedAt,label:"recorded \(f.frameID)")
            }
        }
        if let output=ProcessInfo.processInfo.environment["PHYSICAL_GO_CANDIDATE_REPORT"] {
            let report:[String:Any]=["baselineCommit":"feca90c","historyChecks":checks,"comparedFrames":frames,"decisionComparisons":comparisons,"mismatches":mismatches,
                "syntheticScenarios":12,"recordedAnalysisOperations":recorded.frames.count,"scope":"Timing-policy differential comparison; actual game/clock/capture behavior also checked by recorder replay and regression suites."]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
        }
        check(mismatches==0,"Candidate histories changed stage-1 timing decisions")
        print("PASS: \(checks) candidate-history checks; \(comparisons) differential decisions over \(frames) frames; zero mismatches")
    }
}
