import Foundation

@main struct ShadowRecognitionTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        let empty=Array(repeating:Occupancy.empty,count:81)
        func view(_ values:[Occupancy],at t:Double,score:Double=1,estimate:ClockPressEstimate?=nil)->BoardObservation {
            let size=Int(Double(values.count).squareRoot())
            return .init(readings:values.enumerated().map{.init(row:$0.offset/size,col:$0.offset%size,occupancy:$0.element,confidence:score,delta:0)},size:size,capturedAt:t,handObstructed:false,clockPressEstimate:estimate)
        }
        var shadow=ShadowEvidence(),burst=empty
        for p in [10,11,12] {burst[p] = .black}
        for p in 30..<40 {burst[p] = .uncertain}
        let raw=view(burst,at:1)
        let mask=shadow.discount(raw,base:empty,protected:[],at:1)
        check(mask==[10,11,12],"Correlated dark burst with broad uncertainty was not discounted")
        check(raw.signature==burst && raw.discountingDarkReadings(mask).signature[10] == .uncertain,"Discounting rewrote raw evidence or declared a shadow empty")
        var isolated=empty;isolated[10] = .black
        for p in 30..<40 {isolated[p] = .uncertain}
        check(shadow.discount(view(isolated,at:1.21),base:empty,protected:[],at:1.21)==[10],"A lingering dark fragment of a shadow cluster regained trust before the view cleared")
        shadow.reset()
        check(shadow.discount(view(isolated,at:1.21),base:empty,protected:[],at:1.21).isEmpty,"A locally strong isolated stone was erased by unrelated uncertainty")
        var clean=empty;for p in [10,11,12] {clean[p] = .black}
        check(shadow.discount(view(clean,at:1.42),base:empty,protected:[],at:1.42).isEmpty,"A clear real catch-up board was mistaken for a dark burst")
        shadow.reset()
        var accumulating=empty
        for p in 30..<40 {accumulating[p] = .uncertain}
        for (i,p) in [10,11,12,13].enumerated() {
            accumulating[p] = .black
            for step in 0..<4 {
                let t=1+Double(i)*0.84+Double(step)*0.21
                check(shadow.discount(view(accumulating,at:t),base:empty,protected:[],at:t).isEmpty,"Sequential local sightings were conflated with a simultaneous shadow cluster")
            }
        }
        shadow.reset()
        var weak=empty;weak[10] = .black;weak[30] = .uncertain;weak[31] = .uncertain
        for t in [10.0,10.21] {check(shadow.discount(view(weak,at:t,score:0.92),base:empty,protected:[],at:t).isEmpty,"A small uncertain region alone declared a shadow")}
        check(shadow.noteHand(at:10.4,protected:[])==[10],"Later hand entry did not discount recent uncertain dark evidence")
        check(shadow.noteHand(at:10.4,protected:[]).isEmpty,"Duplicate hand callbacks repeated retrospective discounting")
        check(shadow.discount(view(weak,at:10.61,score:0.92),base:empty,protected:[],at:10.61)==[10],"Post-entry uncertain dark evidence was fully trusted")
        var stone=empty;stone[10] = .black
        check(shadow.discount(view(stone,at:10.82),base:empty,protected:[],at:10.82).isEmpty,"Stable post-hand evidence could not recover")
        shadow.reset();_=shadow.discount(view(weak,at:1,score:0.92),base:empty,protected:[],at:1)
        check(shadow.noteHand(at:1.4,protected:[10]).isEmpty,"A certified placement was retrospectively retracted")
        shadow.reset();_=shadow.discount(view(weak,at:1,score:0.92),base:empty,protected:[],at:1)
        check(shadow.noteHand(at:2,protected:[]).isEmpty,"Hand evidence reached outside its bounded lookback")

        var timing=ClearBoardTiming()
        for t in [10.0,10.21] {timing.observe(view(weak,at:t,score:0.92),now:t)}
        check(timing.pendingTurn(base:empty,excluding:[],color:.black,after:0)?.time==10,"Fixture lacks initial tentative timing")
        timing.discountDarkReadings([10],since:9.6);timing.noteHand(at:10.4)
        check(timing.pendingTurn(base:empty,excluding:[],color:.black,after:0)==nil,"Discarded shadow retained timeout protection")
        let hand=ClockPressEstimate(time:10.5,method:.handMotion,observedLower:10.49,observedUpper:10.51,estimatedError:0.01,samples:3)
        for t in [10.6,10.81] {timing.observe(view(stone,at:t,estimate:hand),now:t)}
        check(timing.observedTurns(base:empty,excluding:[],after:0).first?.estimate==hand,"Recovered real move was backdated to a possible shadow or charged for confirmation")
        var stale=ClearBoardTiming()
        let oldHand=ClockPressEstimate(time:9.9,method:.handMotion,observedLower:9.89,observedUpper:9.91,estimatedError:0.01,samples:3)
        for t in [10.0,10.21] {stale.observe(view(weak,at:t,score:0.92,estimate:oldHand),now:t)}
        stale.discountDarkReadings([10],since:9.6);stale.noteHand(at:10.4)
        for t in [10.6,10.81,11.02,11.23] {stale.observe(view(stone,at:t,estimate:oldHand),now:t)}
        check(stale.observedTurns(base:empty,excluding:[],after:0).first?.estimate.time==10.6,"An old hand estimate survived retraction of shadow evidence")
        check(stale.estimate(target:stone,changed:[10],after:0)?.time==10.6 && stale.pendingTurn(base:empty,excluding:[],color:.black,after:0)?.time==10.6,"A timing fallback bypassed the shadow boundary")
        // Candidate clocks remain separate: an early dark ghost and a later
        // real stone coexist before hand entry discredits only the ghost.
        var separate=ClearBoardTiming(),mixed=weak
        separate.observe(view(weak,at:1,score:0.92),now:1)
        mixed[20] = .black
        for t in [1.21,1.42] {
            var sight=view(mixed,at:t)
            sight.readings[10] = .init(row:1,col:1,occupancy:.black,confidence:0.92,delta:0)
            separate.observe(sight,now:t)
        }
        separate.discountDarkReadings([10],since:0.8);separate.noteHand(at:1.6)
        var realOnly=empty;realOnly[20] = .black
        for t in [1.84,2.05] {separate.observe(view(realOnly,at:t),now:t)}
        let certified=separate.observedTurns(base:empty,excluding:[],after:0)
        check(certified.count==1 && certified[0].locations==[20],"Coexisting ghost and real stone produced multiple turn presses")
        check(abs(certified[0].estimate.time-1.21)<0.001,"Real candidate inherited the ghost timestamp or lost its own pre-hand sighting")

        let root=FileManager.default.temporaryDirectory.appendingPathComponent("shadow-recognition-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        func signature(_ values:[Occupancy])->String {values.map{$0 == .black ? "B":$0 == .white ? "W":$0 == .empty ? ".":"?"}.joined()}
        var journal=[[String:Any]](),final=empty
        final[10] = .black;final[20] = .white;final[30] = .black
        for (times,values) in [([0.0,0.21,0.42],empty),([1.0,1.21,1.42],stone),([2.0,2.21,2.42,2.63],final)] {
            for t in times {journal.append(["event":"observation","time":100+t,"captureUptime":1000+t,"position":signature(values)])}
        }
        let journalURL=root.appendingPathComponent("recovery.jsonl")
        func writeJournal()throws {
            let lines=try journal.map{String(data:try JSONSerialization.data(withJSONObject:$0,options:.sortedKeys),encoding:.utf8)!}
            try (lines.joined(separator:"\n")+"\n").write(to:journalURL,atomically:true,encoding:.utf8)
        }
        try writeJournal()
        check(try ReviewOrderRecovery.load(url:journalURL,before:empty,after:final,first:.black,through:103).orders.count==1,"Order-recovery fixture did not contain a misleading early appearance")
        journal.insert(["event":"shadow evidence discounted retrospectively","time":101.5,"shadowSinceUptime":1000.7,"shadowThroughUptime":1001.5,"shadowPoints":[10]],at:6)
        try writeJournal()
        check(try ReviewOrderRecovery.load(url:journalURL,before:empty,after:final,first:.black,through:103).orders.count==2,"Reopening order recovery resurrected discounted shadow evidence")
        let recorder=GameRecorder(storage:nil);recorder.clock.audible=false
        var now=ProcessInfo.processInfo.systemUptime+3
        recorder.start(size:9,now:now,clockSettings:.init(kind:.absolute,mainSeconds:120))
        for _ in 0..<6 {now+=0.21;recorder.consume(view(empty,at:now),now:now)}
        var retro=[Int](),rawKept=false
        recorder.onDiagnosticEvent={row in
            if row["event"] as? String == "shadow evidence discounted retrospectively" {retro=row["shadowPoints"] as? [Int] ?? []}
            if let raw=row["position"] as? String,let filtered=row["interpretedPosition"] as? String {rawKept=raw != filtered}
        }
        for _ in 0..<2 {now+=0.21;recorder.consume(view(weak,at:now,score:0.92),now:now)}
        now+=0.21;recorder.noteHandObstruction(now:now,capturedAt:now)
        check(retro==[10] && recorder.clock.pendingTurnEvidence==nil && recorder.moveCount==0,"Recorder did not retract tentative pre-entry shadow evidence")
        recorder.noteHandClear()
        var real=empty;real[20] = .black
        let actualFirst=now+0.21
        for _ in 0..<8 {now+=0.21;recorder.consume(view(real,at:now),now:now)}
        check(recorder.moveCount==1 && recorder.game.moves[0].1?.0==2 && recorder.game.moves[0].1?.1==2,"A pre-entry shadow survived as a recorded move")
        check(recorder.clock.moves.count==1 && abs(recorder.clock.moves[0].estimate!.time-actualFirst)<0.001,"The real move inherited shadow timing or confirmation delay")
        now+=0.21;recorder.consume(view(burst,at:now),now:now)
        check(rawKept,"Raw and interpreted shadow evidence were not journaled separately")
        recorder.pause()

        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/GoClubVisibility")
        func restored(_ name:String)throws->GameRecorder {
            let folder=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            for ext in ["sgf","clock.json","pending.json","reviews.json"] {try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+ext),to:folder.appendingPathComponent("game."+ext))}
            let r=GameRecorder(storage:folder);r.clock.audible=false;try r.restoreSavedGame(from:folder.appendingPathComponent("game.sgf"))
            check(r.confirmClockReview(black:r.clock.engine.black,white:r.clock.engine.white,resume:true),"Temporary continuation could not resume agreed clock times")
            return r
        }
        func feed(_ r:GameRecorder,_ states:[Occupancy],count:Int,score:Double=1,estimate:ClockPressEstimate?=nil) {
            for _ in 0..<count {now+=0.21;r.consume(view(states,at:now,score:score,estimate:estimate),now:now)}
        }
        let fast=try restored("fast"),base=try restored("base").reviewHistory.latest!
        now+=3;feed(fast,base,count:8)
        var board=base
        let prefix=fast.sgf()
        for (i,p) in [180,182,184].enumerated() {
            board[p] = i%2==0 ? .white:.black
            let first=now+0.21
            feed(fast,board,count:4)
            check(fast.reviewHistory.retainedMoveCount==i+1 && fast.clock.running,"Brief clear later move became another review")
            check(fast.clock.liveEvents.count==i+1 && abs(fast.clock.liveEvents.last!.estimate!.time-first)<0.001,"Later turn was charged for confirmation or pressed twice")
        }
        check(fast.reviewHistory.unresolved==1 && fast.sgf()==prefix,"Faster continuation guessed the unresolved original chronology")
        fast.pause();try fast.flushStorage()
        let reopened=GameRecorder(storage:root);reopened.clock.audible=false;try reopened.restoreSavedGame(from:fast.autosaveURL!)
        check(reopened.reviewHistory.retainedMoveCount==3 && reopened.reviewHistory.unresolved==1,"Certified later turns did not survive reopening")

        let cautious=try restored("cautious");now+=3;feed(cautious,base,count:8)
        var next=base;next[180] = .white
        let weakFirst=now+0.21
        feed(cautious,next,count:5,score:0.92)
        check(cautious.reviewHistory.retainedMoveCount==0,"Lower-confidence review continuation bypassed adaptive confirmation")
        feed(cautious,next,count:1,score:0.92)
        check(cautious.reviewHistory.retainedMoveCount==1 && abs(cautious.clock.liveEvents[0].estimate!.time-weakFirst)<0.001,"Longer weak-evidence confirmation changed its supported timestamp")
        cautious.pause()
        let low=try restored("low-score");now+=3;feed(low,base,count:8)
        feed(low,next,count:11,score:0.85)
        check(low.reviewHistory.unresolved==2 && low.reviewHistory.latest==next,"Persistently low confidence left later recognition stuck indefinitely")
        check(low.clock.liveEvents.isEmpty && low.clock.requiresReview && !low.clock.running,"Low-confidence fallback invented a clock press")
        low.pause()
        let supported=try restored("hand-supported");now+=3;feed(supported,base,count:8)
        now+=0.21;supported.noteHandObstruction(now:now,capturedAt:now);supported.noteHandClear()
        let handPress=ClockPressEstimate(time:now,method:.handMotion,observedLower:now-0.01,observedUpper:now+0.01,estimatedError:0.01,samples:3)
        feed(supported,next,count:2,estimate:handPress)
        check(supported.reviewHistory.retainedMoveCount==1 && supported.clock.liveEvents.last?.estimate==handPress,"Review gap disabled high-confidence hand-supported timing")
        supported.pause()

        for (index,settings) in [LocalClockSettings(kind:.absolute,mainSeconds:10),.init(kind:.fischer,mainSeconds:10,incrementSeconds:5,maximumSeconds:20),.init(kind:.byoyomi,mainSeconds:0,periodSeconds:2,periods:3)].enumerated() {
            let r=try restored("clock-\(index)");now+=3;feed(r,base,count:8)
            r.clock.configure(settings,blackToPlay:false,baseMove:10);r.clock.ready(at:now)
            var expected=r.clock.engine
            let press=now+0.21
            feed(r,next,count:4)
            expected.advance(to:press);_=expected.move(black:false,at:press);expected.advance(to:now)
            check(r.clock.engine==expected,"Adaptive review continuation changed clock arithmetic in mode \(index)")
            r.pause()
        }
        let expiry=try restored("expiry");now+=3;feed(expiry,base,count:8)
        expiry.clock.configure(.init(kind:.absolute,mainSeconds:1),blackToPlay:false,baseMove:10);expiry.clock.ready(at:now)
        let start=now;now+=0.8;expiry.consume(view(next,at:now),now:now)
        expiry.clock.tick(at:start+1.1)
        feed(expiry,next,count:3)
        check(expiry.clock.liveEvents.count==1 && expiry.clock.running && !expiry.clock.requiresReview && abs(expiry.clock.engine.white.remaining-0.2)<0.001,"A timely later move expired while confidence accumulated")
        expiry.pause()
        let boundary=try restored("boundary");now+=3;feed(boundary,base,count:8)
        boundary.clock.configure(.init(kind:.absolute,mainSeconds:1),blackToPlay:false,baseMove:10);boundary.clock.ready(at:now)
        let uncertain=ClockPressEstimate(time:now+1,method:.handBracket,observedLower:now+0.9,observedUpper:now+1.1,estimatedError:0.1,samples:2)
        now+=1.1;feed(boundary,next,count:2,estimate:uncertain)
        check(boundary.clock.requiresReview && !boundary.clock.running,"Adaptive later-turn timing silently resolved an expiry-straddling hand interval")
        boundary.pause()

        // Adaptive continuation must not accelerate physical capture removal.
        var position=empty;for p in [1,9,11] {position[p] = .black};position[10] = .white
        let game=DeferredMoveHistory.positionGame(position,size:9,rules:"Japanese",turn:.black)
        let player=SGFPlayer();player.load(game:game);let before=player.board
        check(player.tryPlayMove(color:.black,x:1,y:2)==nil,"Capture fixture is illegal")
        let after=DeferredMoveHistory.states(player.board)
        var history=DeferredMoveHistory();history.size=9
        history.sections=[.init(reviewNumber:1,before:position,after:position,reason:"Earlier unresolved order",firstSeen:0,confirmedAt:0,liveNext:.black)]
        for i in 0..<4 {
            let t=1+Double(i)*0.21
            check(!history.observe(view(after,at:t),base:before,game:game,signature:"test",now:t,allowStart:false,certifiedPoint:19,requiresTurnCertification:true),"Capture removal used the fast single-addition path")
        }
        check(history.observe(view(after,at:1.84),base:before,game:game,signature:"test",now:1.84,allowStart:false,certifiedPoint:19,requiresTurnCertification:true),"Completed legal capture lost its full-view confirmation")
        check(history.sections.last?.moves?.count==1,"Capture was split into invented turns")
        print("PASS: \(checks) shadow quality, retrospective discounting, adaptive review continuation, clock accuracy, expiry and capture isolation checks")
    }
}
