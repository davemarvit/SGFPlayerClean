import Foundation

@main struct AdaptiveTurnTimingTests {
    struct Frame:Decodable {let time:Double;let position:String}
    struct Incident:Decodable {let frames:[Frame]}
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let fixtures=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ProvisionalCornerFlash")
        let incident=try JSONDecoder().decode(Incident.self,from:Data(contentsOf:fixtures.appendingPathComponent("observations.json")))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("adaptive-turn-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("game.sgf")
        try FileManager.default.copyItem(at:fixtures.appendingPathComponent("game.sgf"),to:file)
        let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file);r.resume()
        let base=DeferredMoveHistory.states(r.positions.last!),start=ProcessInfo.processInfo.systemUptime+4
        func feed(_ values:[Occupancy],at t:Double) {
            r.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:t,handObstructed:false),now:t)
            r.clock.tick(at:t)
        }
        for i in 0..<8 {feed(base,at:start-2+Double(i)*0.21)}
        r.clock.configure(.init(kind:.byoyomi,mainSeconds:120,periodSeconds:15,periods:5),blackToPlay:false,baseMove:7)
        r.clock.ready(at:start)
        let origin=start-incident.frames[0].time
        var previous=start
        for f in incident.frames {
            let t=origin+f.time
            while t-previous>0.5 {previous+=0.3;r.noteHandObstruction(now:previous)}
            previous=t
            feed(f.position.map{$0 == "B" ? .black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty},at:t)
            check(r.clock.lastTimedMove<=8,"Recorded corner flash switched the clock for a nonexistent ninth move")
            check(r.clock.running && !r.clock.requiresReview,"Recorded corner flash still paused play")
        }
        check(r.moveCount==8 && r.clock.engine.blackToPlay && r.clock.provisionalMoves.isEmpty,"Real White move did not leave Black to play")
        let firstWhite=origin+incident.frames.first{Array($0.position)[294] == "W"}!.time
        check(r.clock.moves.count==1 && abs(r.clock.moves[0].estimate!.time-firstWhite)<0.001,"Confirmation delay replaced White's first sighting")
        check(abs(r.clock.engine.white.remaining-(120-(firstWhite-start)))<0.001,"White paid for extra confidence checks")
        r.pause()

        let empty=Array(repeating:Occupancy.empty,count:81)
        func view(_ values:[Occupancy],at t:Double,score:Double=1,estimate:ClockPressEstimate?=nil)->BoardObservation {
            .init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:score,delta:0)},size:9,capturedAt:t,handObstructed:false,clockPressEstimate:estimate)
        }
        var stone=empty;stone[10] = .black
        let hand=ClockPressEstimate(time:10,method:.handMotion,observedLower:9.98,observedUpper:10.02,estimatedError:0.02,samples:3)
        var strong=ClearBoardTiming(),ordinary=ClearBoardTiming(),weak=ClearBoardTiming(),uncertainHand=ClearBoardTiming(),supportedWeak=ClearBoardTiming()
        let broad=ClockPressEstimate(time:10,method:.handBracket,observedLower:9,observedUpper:11,estimatedError:1,samples:2)
        for t in [11.0,11.21] {
            strong.observe(view(stone,at:t,estimate:hand),now:t)
            ordinary.observe(view(stone,at:t),now:t)
            weak.observe(view(stone,at:t,score:0.92),now:t)
            supportedWeak.observe(view(stone,at:t,score:0.92,estimate:hand),now:t)
            uncertainHand.observe(view(stone,at:t,estimate:broad),now:t)
        }
        check(strong.observedTurns(base:empty,excluding:[],after:0).first?.estimate==hand,"Strong hand-supported evidence lost its short confirmation path")
        check(ordinary.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Detector score alone got the shortest confirmation")
        check(weak.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Weak stone readings got the shortest confirmation")
        check(supportedWeak.observedTurns(base:empty,excluding:[],after:0).isEmpty,"A lower stone score got the shortest hand-supported confirmation")
        check(uncertainHand.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Wide hand uncertainty got the shortest confirmation")
        uncertainHand.observe(view(stone,at:11.42,estimate:broad),now:11.42)
        check(uncertainHand.observedTurns(base:empty,excluding:[],after:0).first?.estimate==broad,"Hand-supported turn lost its timing interval after the longer check")
        supportedWeak.observe(view(stone,at:11.42,score:0.92,estimate:hand),now:11.42)
        check(supportedWeak.observedTurns(base:empty,excluding:[],after:0).first?.estimate==hand,"Independent hand evidence failed to support a lower-scoring real stone")
        for t in [11.42,11.63] {
            ordinary.observe(view(stone,at:t),now:t)
            weak.observe(view(stone,at:t,score:0.92),now:t)
        }
        check(ordinary.observedTurns(base:empty,excluding:[],after:0).first?.estimate.time==11,"Consistent stone evidence lost its earliest timestamp")
        check(weak.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Weaker evidence did not wait longer than consistent high scores")
        for t in [11.84,12.05] {weak.observe(view(stone,at:t,score:0.92),now:t)}
        check(weak.observedTurns(base:empty,excluding:[],after:0).first?.estimate.time==11,"Sustained weaker evidence could never confirm")

        // An unstable surrounding board needs the longer path even with a
        // high local score and a good hand estimate. Exact aliases are exempt.
        var unstable=ClearBoardTiming(),moving=stone
        for (i,t) in [11.0,11.21,11.42,11.63].enumerated() {
            moving[40] = i%2==0 ? .black:.empty
            unstable.observe(view(moving,at:t,estimate:hand),now:t)
        }
        check(unstable.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Surrounding flicker was treated as strong turn evidence")

        var withdrawn=ClearBoardTiming()
        for t in [1.0,1.21,1.42] {withdrawn.observe(view(stone,at:t),now:t)}
        check(withdrawn.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Three-frame flash pressed the clock")
        check(withdrawn.provisionalEstimate(target:stone,changed:[10],locations:[10],color:.black,aliases:[],after:0)==nil,"Placement path bypassed adaptive confirmation")
        withdrawn.observe(view(empty,at:1.63),now:1.63)
        check(withdrawn.pendingTurn(base:empty,excluding:[],color:.black,after:0)==nil,"Withdrawn candidate retained timeout evidence")
        for t in [2.0,2.21,2.42,2.63] {withdrawn.observe(view(stone,at:t),now:t)}
        check(withdrawn.observedTurns(base:empty,excluding:[],after:0).first?.estimate.time==2,"Reappearing stone reused the discarded flash's timestamp")
        check(withdrawn.provisionalEstimate(target:stone,changed:[10],locations:[10],color:.black,aliases:[],after:0)?.time==2,"Placement confirmation failed to use the new observation run")

        var ambiguous=ClearBoardTiming(),shifted=stone
        for (i,t) in [3.0,3.21,3.42,3.63].enumerated() {
            shifted[10] = i%2==0 ? .black:.empty;shifted[11] = i%2==0 ? .empty:.black
            ambiguous.observe(view(shifted,at:t),now:t)
        }
        check(ambiguous.provisionalEstimate(target:stone,changed:[10],locations:[10,11],color:.black,aliases:[[10,11]],after:0)?.time==3,"Neighboring placement ambiguity prevented certification of one completed turn")
        var flicker=ClearBoardTiming(),unclear=stone
        for t in [4.0,4.21,4.42] {flicker.observe(view(stone,at:t),now:t)}
        unclear[10] = .uncertain;flicker.observe(view(unclear,at:4.63),now:4.63)
        for t in [4.84,5.05,5.26] {flicker.observe(view(stone,at:t),now:t)}
        check(flicker.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Interrupted clear sightings were combined into an early confirmation")
        flicker.observe(view(stone,at:5.47),now:5.47)
        check(flicker.observedTurns(base:empty,excluding:[],after:0).first?.estimate.time==4,"Uncertainty erased the earliest supported observation")
        flicker.observe(view(stone,at:5.68,score:0.88),now:5.68)
        check(flicker.observedTurns(base:empty,excluding:[],after:0).isEmpty,"A weak current reading reused an older certification")
        check(flicker.provisionalEstimate(target:stone,changed:[10],locations:[10],color:.black,aliases:[],after:0)==nil,"Placement path certified stale high-confidence views")
        var wrongColor=stone;wrongColor[10] = .white
        withdrawn.observe(view(wrongColor,at:3),now:3)
        for t in [3.21,3.42,3.63,3.84] {withdrawn.observe(view(stone,at:t),now:t)}
        check(withdrawn.observedTurns(base:empty,excluding:[],after:0).first?.estimate.time==3.21,"Opposite-color evidence reused an earlier timing claim")
        check(withdrawn.provisionalEstimate(target:stone,changed:[10],locations:[10],color:.black,aliases:[],after:0)?.time==3.21,"Placement path failed to retract a contradictory color")
        var oldHand=ClearBoardTiming()
        oldHand.observe(view(stone,at:11,estimate:hand),now:11)
        oldHand.observe(view(empty,at:11.21),now:11.21)
        for t in [12.0,12.21,12.42,12.63] {oldHand.observe(view(stone,at:t,estimate:hand),now:t)}
        check(oldHand.observedTurns(base:empty,excluding:[],after:0).first?.estimate.time==12,"Reappearing stone reused the withdrawn move's hand timestamp")
        check(oldHand.provisionalEstimate(target:stone,changed:[10],locations:[10],color:.black,aliases:[],after:0)?.time==12,"Placement path reused a contradicted hand estimate")
        check(oldHand.estimate(target:stone,changed:[10],after:0)?.time==12,"Confirmed history reused a withdrawn timing claim")
        check(oldHand.pendingTurn(base:empty,excluding:[],color:.black,after:0)?.time==12,"Timeout protection reused a withdrawn timing claim")
        print("PASS: \(checks) adaptive turn confidence and recorded corner-flash checks")
    }
}
