import Foundation

/// Saved-input sequence benchmark: never feeds recorded acceptance decisions
/// back into the recorder. Camera and callback clocks remain distinct.
@main struct ObservationReplayTests {
    struct Frame:Decodable {
        let frameID:Int,capturedAt:Double,processedAt:Double,handObstructed:Bool,lightingBlocked:Bool
        let readings:[IntersectionReading],footprints:[StoneFootprint],placementFits:[StoneFootprint]
        let estimate:ClockPressEstimate?
    }
    struct Sequence:Decodable {let initialSGF:String,expectedPoints:[Int],frames:[Frame]}
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/RapidReplyShadow/sequence.json")
        let sequence=try JSONDecoder().decode(Sequence.self,from:Data(contentsOf:fixture))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("observation-replay-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        try preservationChecks(root:root)
        var reports=[[String:Any]](),failures=[String]()
        for (kind,missingEvidence,nearExpiry) in [(LocalClockSettings.Kind.absolute,false,false),(.fischer,false,false),(.byoyomi,false,false),(.byoyomi,false,true),(.absolute,true,false)] {
            let folder=root.appendingPathComponent(kind.rawValue+(missingEvidence ? "-missing":nearExpiry ? "-overtime":""))
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let file=folder.appendingPathComponent("game.sgf")
            try sequence.initialSGF.write(to:file,atomically:true,encoding:.utf8)
            let r=GameRecorder(storage:folder);r.clock.audible=false
            try r.restoreSavedGame(from:file);r.resume()
            let offset=ProcessInfo.processInfo.systemUptime+5-sequence.frames[0].capturedAt
            let start=sequence.frames[0].capturedAt+offset-0.1
            let base=DeferredMoveHistory.states(r.positions.last!)
            for i in 0..<8 {
                let t=start-2+Double(i)*0.21
                r.consume(.init(readings:base.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:t,handObstructed:false),now:t)
            }
            r.clock.configure(.init(kind:kind,mainSeconds:120,periodSeconds:15,periods:5,incrementSeconds:3),blackToPlay:false,baseMove:7)
            if nearExpiry {
                var black=r.clock.engine.black,white=r.clock.engine.white
                black.remaining=72.54911352090363
                white.remaining=0.797221687156707+1265045.9376668755+offset-start
                precondition(r.clock.correct(black:black,white:white,blackToPlay:false,moveCount:7,at:start))
                r.clock.resume(at:start)
            } else {r.clock.ready(at:start)}
            var preservedRows=0
            r.onDiagnosticEvent={row in
                guard row["event"] as? String == "observation",let fact=r.observationEvidence.observations.last else {return}
                if row["observationID"] as? String != fact.id ||
                    row["readingConfidence"] as? [Double] != fact.raw.readings.map(\.confidence) ||
                    row["readingDelta"] as? [Double] != fact.raw.readings.map(\.delta) {
                    failures.append("Raw journal quality/identity differed from preserved observation")
                }
                preservedRows+=1
            }
            var pauses=0,wasReview=false,states=[[String:Any]]()
            var reference=r.clock.engine
            reference.resume(at:start)
            // Independent timing oracle: White hand exit, first clean Black
            // sighting, next White hand exit. Confirmation must not add time.
            let expectedTimes=[1265045.9376668755,1265050.6216669178,1265052.620700167]
            for (i,time) in expectedTimes.enumerated() {precondition(reference.move(black:i==1,at:time+offset))}
            for f in sequence.frames {
                let now=f.processedAt+offset,stamp=f.capturedAt+offset
                if f.handObstructed {r.noteHandObstruction(now:now,capturedAt:stamp)}
                else {
                    r.noteHandClear()
                    let estimate=f.estimate.map{ClockPressEstimate(time:$0.time+offset,method:$0.method,
                        observedLower:$0.observedLower.map{$0+offset},observedUpper:$0.observedUpper.map{$0+offset},
                        estimatedError:$0.estimatedError,samples:$0.samples,timestampSource:$0.timestampSource,fallbackReason:$0.fallbackReason)}
                    var readings=f.readings
                    if missingEvidence && [355,356].contains(f.frameID) {
                        let old=readings[309]
                        readings[309] = .init(row:old.row,col:old.col,occupancy:.uncertain,confidence:0,delta:old.delta)
                    }
                    r.consume(.init(readings:readings,size:19,lightingBlocked:f.lightingBlocked,footprints:f.footprints,
                        placementFits:f.placementFits,capturedAt:stamp,handObstructed:false,clockPressEstimate:estimate),now:now)
                }
                if f.frameID==358 && !missingEvidence {
                    for stamp in [1265050.6216669178,1265050.8077002084] {
                        guard let fact=r.observationEvidence.observations.first(where:{$0.capturedAt==stamp+offset}) else {preconditionFailure("Missing raw intermediate observation")}
                        if fact.raw.signature[309] != .black || r.observationEvidence.interpreted(fact).signature[309] != .black {failures.append("Hand entry invalidated an independent clean sighting")}
                    }
                }
                r.clock.tick(at:now)
                if r.clock.requiresReview && !wasReview {pauses+=1};wasReview=r.clock.requiresReview
                states.append(["frame":f.frameID,"moves":r.moveCount,"timed":r.clock.lastTimedMove,"review":r.clock.requiresReview])
            }
            if preservedRows != sequence.frames.filter({!$0.handObstructed}).count {failures.append("Replay failed to journal all delivered observations")}
            r.onDiagnosticEvent=nil
            let points=r.game.moves.dropFirst(7).compactMap{$0.1.map{$0.1*19+$0.0}}
            let times=r.clock.moves.compactMap{$0.estimate?.time}.map{$0-offset}
            reports.append(["scenario":missingEvidence ? "counterfactual missing intermediate sightings":"recorded rapid reply","clock":kind.rawValue,"nearOvertime":nearExpiry,"observations":sequence.frames.count,
                "savedPoints":points,"reviewTransitions":pauses,"falsePauses":missingEvidence ? 0:pauses,"expectedReview":missingEvidence,"orderMatches":points==sequence.expectedPoints,"pressTimes":times,"running":r.clock.running,"states":states])
            if points != sequence.expectedPoints {failures.append("\(kind): wrong move sequence \(points)")}
            if missingEvidence {
                if pauses != 1 || r.clock.running || times.count != 1 {failures.append("Missing timing evidence did not retain review guard")}
            } else {
                if pauses != 0 || !r.clock.running {failures.append("\(kind): false clock pause")}
                if times.count != 3 || zip(times,expectedTimes).contains(where:{abs($0-$1)>0.000001}) {failures.append("\(kind): incorrect press timestamps")}
                reference.advance(to:sequence.frames.last!.processedAt+offset)
                reports[reports.count-1]["maximumPressTimestampErrorSeconds"]=times.count==3 ? zip(times,expectedTimes).map{abs($0-$1)}.max()! : -1
                reports[reports.count-1]["blackBalanceErrorSeconds"]=abs(reference.black.remaining-r.clock.engine.black.remaining)
                reports[reports.count-1]["whiteBalanceErrorSeconds"]=abs(reference.white.remaining-r.clock.engine.white.remaining)
                if abs(reference.black.remaining-r.clock.engine.black.remaining)>0.000001 ||
                    abs(reference.white.remaining-r.clock.engine.white.remaining)>0.000001 ||
                    reference.black.overtime != r.clock.engine.black.overtime || reference.white.overtime != r.clock.engine.white.overtime ||
                    reference.black.periods != r.clock.engine.black.periods || reference.white.periods != r.clock.engine.white.periods ||
                    reference.blackToPlay != r.clock.engine.blackToPlay {failures.append("\(kind): clock arithmetic differs from independent presses")}
            }
            // Move seven had already captured this White stone. Observation
            // preservation must never restore it or invent another removal.
            if r.positions.last!.grid[14][15] != nil || r.clock.automaticCapturePaused {failures.append("Captured stone or capture pause resurrected")}

            print("REPLAY \(kind): moves=\(points), pauses=\(pauses), times=\(times)")
            r.pause()
        }
        if let output=ProcessInfo.processInfo.environment["PHYSICAL_GO_REPLAY_REPORT"] {
            try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
        }
        precondition(failures.isEmpty,failures.joined(separator:"; "))
        print("PASS: recorded rapid-reply benchmark across absolute, Fischer and byoyomi clocks")
    }
    @MainActor static func preservationChecks(root:URL)throws {
        let base=Array(repeating:Occupancy.empty,count:81)
        var stone=base;stone[10] = .black
        func view(_ t:Double,_ weak:Bool=false)->BoardObservation {
            var values=stone
            if weak {values[30] = .uncertain;values[31] = .uncertain}
            return .init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:weak ? 0.85:1,delta:0)},size:9,capturedAt:t,handObstructed:false)
        }
        var evidence=ObservationEvidence(),shadow=ShadowEvidence(),local=LocalMoveEvidence(),timing=ClearBoardTiming()
        for (t,weak) in [(1.0,false),(1.21,false),(1.42,true)] {
            let raw=view(t,weak)
            _=evidence.append(raw,processedAt:t+10)
            _=shadow.discount(raw,base:base,protected:[],at:t,processedAt:t+10)
            local.observe(raw.signature,base:base,now:t+10)
            timing.observe(raw,now:t+0.1)
        }
        let discounts=shadow.noteHandSamples(at:1.6,protected:[])
        precondition(discounts.count==1 && discounts[0].capturedAt==1.42 && discounts[0].processedAt==11.42)
        for d in discounts {
            evidence.discount(capturedAt:d.capturedAt,points:d.points,reason:"hand entry",now:11.6)
            local.discountDarkReadings(d.points,at:d.processedAt)
            timing.discountDarkReadings(d.points,at:d.capturedAt)
        }
        precondition(evidence.observations.allSatisfy{$0.raw.signature[10] == .black},"Raw observations were rewritten")
        precondition(evidence.observations.map{evidence.interpreted($0).signature[10]} == [.black,.black,.uncertain],"Revision escaped its specific sample")
        precondition(local.points[10].last?.count==2 && local.unresolvedPoints(base:base).contains(10),"Selective revision destroyed independent local chronology")
        precondition(timing.pendingTurn(base:base,excluding:[],color:.black,after:0)==nil,"Newest suspect reading still protected a timeout")
        for t in [2.0,2.21,2.42,2.63] {timing.observe(view(t),now:t+0.1)}
        precondition(timing.observedTurns(base:base,excluding:[],after:0).first?.estimate.time==1,"Later weak reading erased independent earlier timing")
        var shortened=LocalMoveEvidence.Run(value:.black,first:1,last:1,count:1,recentTimes:[1])
        shortened.append(1.1);shortened.append(1.21);shortened.remove(1)
        precondition(shortened.established==nil && shortened.first==1.1,"Removing first sighting retained an invalid confirmation span")
        var longRun=LocalMoveEvidence.Run(value:.black,first:1,last:1,count:1,recentTimes:[1])
        for i in 1..<100 {longRun.append(1+Double(i)*0.01)}
        for t in longRun.recentTimes {longRun.remove(t)}
        precondition(longRun.count<=2 && longRun.last<1.36,"Retraction retained an unobserved compressed-run endpoint")
        let saved=evidence.observations[0]
        for i in 0..<1000 {_=evidence.append(view(2+Double(i)*0.001),processedAt:12+Double(i)*0.001)}
        precondition(evidence.observations.count==ObservationEvidence.maximumObservations && evidence.revisions.isEmpty)
        _=evidence.append(view(100),processedAt:110)
        precondition(evidence.observations.count==1 && saved.raw.signature[10] == .black,"Retention changed a raw value")

        // Reopening a journal applies exact revisions, preserving clean frames
        // in the same legacy time window. Old coarse archives remain supported
        // by ShadowRecognitionTests.
        func signature(_ values:[Occupancy])->String {values.map{$0 == .black ? "B":$0 == .white ? "W":$0 == .uncertain ? "?":"."}.joined()}
        var final=stone;final[20] = .white;final[30] = .black
        var rows=[[String:Any]]()
        for (times,values) in [([0.0,0.21,0.42],base),([1.0,1.21,1.42,1.63],stone),([2.0,2.21,2.42,2.63],final)] {
            for t in times {rows.append(["event":"observation","time":100+t,"captureUptime":1000+t,"observationID":"sample-\(t)","position":signature(values)])}
        }
        rows.insert(["event":"shadow evidence discounted retrospectively","time":101.8,
            "shadowPoints":[10],"shadowSinceUptime":1000.8,"shadowThroughUptime":1001.8,
            "shadowSamples":[["captureUptime":1001.63,"observationID":"sample-1.63","points":[10]]]],at:7)
        let journal=root.appendingPathComponent("exact-sample.jsonl")
        let lines=try rows.map{String(data:try JSONSerialization.data(withJSONObject:$0),encoding:.utf8)!}
        try (lines.joined(separator:"\n")+"\n").write(to:journal,atomically:true,encoding:.utf8)
        let recovered=try ReviewOrderRecovery.load(url:journal,before:base,after:final,first:.black,through:103)
        precondition(recovered.orders.count==1,"Journal recovery erased clean chronology")
        print("PASS: immutable observations, sample-specific revisions, separate clocks, bounded retention and journal recovery")
    }

}
