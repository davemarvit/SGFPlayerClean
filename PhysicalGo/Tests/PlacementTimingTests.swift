import Foundation

@main struct PlacementTimingTests {
    struct Frame:Decodable {
        let time:Double
        let readings:[IntersectionReading]
        let handObstructed:Bool?
        let estimate:ClockPressEstimate?
        let footprints:[StoneFootprint]?
        let placementFits:[StoneFootprint]?
    }
    struct Incident:Decodable {let turnStartedAt:Double;let frames:[Frame]}
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let fixtures=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/PlacementTimingLoss")
        let incident=try JSONDecoder().decode(Incident.self,from:Data(contentsOf:fixtures.appendingPathComponent("observations.json")))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("placement-timing-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("incident.sgf")
        try FileManager.default.copyItem(at:fixtures.appendingPathComponent("game.sgf"),to:file)
        let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file);r.resume()
        check(r.moveCount==71,"Fixture must start after Black71")
        let origin=ProcessInfo.processInfo.systemUptime-incident.turnStartedAt+4
        let base=DeferredMoveHistory.states(r.positions.last!)
        for i in 0..<6 {
            let t=origin+incident.turnStartedAt-1.5+Double(i)*0.21
            r.consume(.init(readings:base.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:t,handObstructed:false),now:t)
        }
        r.clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:1),blackToPlay:false,baseMove:71)
        r.clock.bind(to:file,signature:RecordingIdentity.signature(for:r.game));r.clock.ready(at:origin+incident.turnStartedAt)
        var previous=origin+incident.turnStartedAt
        for (index,f) in incident.frames.enumerated() {
            let t=origin+f.time
            // The compact journal omits obstructed frames. Maintain camera
            // continuity only; these synthetic hand callbacks provide no press.
            while t-previous>0.5 {previous+=0.3;r.noteHandObstruction(now:previous)}
            previous=t
            let estimate=f.estimate.map {e in ClockPressEstimate(time:origin+e.time,method:e.method,
                observedLower:e.observedLower.map{$0+origin},observedUpper:e.observedUpper.map{$0+origin},
                estimatedError:e.estimatedError,samples:e.samples,timestampSource:e.timestampSource,fallbackReason:e.fallbackReason)}
            r.consume(.init(readings:f.readings,size:19,footprints:f.footprints ?? [],placementFits:f.placementFits ?? [],
                            capturedAt:t,handObstructed:f.handObstructed,clockPressEstimate:estimate),now:t)
            r.clock.tick(at:t)
            if index==1 {
                print("INCIDENT",r.moveCount,r.pendingMoveCount,r.clock.provisionalMoves.map(\.number),r.clock.notice,r.status)
                check(r.moveCount==71,"Timing accepted an unresolved SGF placement")
                check(r.clock.provisionalMoves.map(\.number)==[72],"White72 was not timed independently of the spurious Black candidate")
                check(r.clock.engine.blackToPlay && r.clock.engine.white.remaining==15,"White did not receive her overtime reset")
                check(abs(r.clock.provisionalMoves[0].estimate!.time-(origin+901287.9367452504))<0.001,"First observed White press was replaced by recognition time")
                let restored=GameRecorder(storage:root);restored.clock.audible=false;try restored.restoreSavedGame(from:file)
                check(restored.clock.saveError==nil && restored.clock.provisionalMoves.count==1,"Restart lost independent turn evidence")
                check(restored.clock.engine.white==r.clock.engine.white,"Restart changed White's measured clock")
            }
        }
        check(r.clock.engine.expiredBlack==nil,"Recorded incident still declares a false timeout")
        check(r.clock.engine.white.periods==1 && r.clock.engine.white.remaining==15,"Placement ambiguity consumed White's period")
        check(r.clock.needsCorrection && !r.clock.running,"Unobserved intervening press times were invented")
        check(r.clock.provisionalMoves.map(\.number)==[72],"Simultaneous first sightings invented Black73/White74 timestamps")
        r.clock.pause(at:origin+incident.frames.last!.time)

        // Local repeated sightings survive unrelated conflicts and uncertainty.
        var timing=ClearBoardTiming(),values=Array(repeating:Occupancy.empty,count:81)
        values[10] = .black;values[40] = .uncertain
        func observation(_ t:Double,hand:Bool?=false)->BoardObservation {
            .init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:t,handObstructed:hand)
        }
        timing.observe(observation(1),now:1)
        check(timing.observedTurns(base:Array(repeating:.empty,count:81),excluding:[],after:0).isEmpty,"One-frame phantom pressed a clock")
        values[50] = .white;timing.observe(observation(1.3),now:1.3)
        let first=timing.observedTurns(base:Array(repeating:.empty,count:81),excluding:[],after:0)
        check(first.count==1 && first[0].color == .black && first[0].estimate.time==1,"A later stone blocked the earlier turn")
        timing.consume(through:1);timing.observe(observation(1.6),now:1.6)
        let second=timing.observedTurns(base:Array(repeating:.empty,count:81),excluding:[10],after:0)
        check(second.count==1 && second[0].color == .white && second[0].estimate.time==1.3,"Alternating reply lost its first sighting")
        values[50] = .empty;timing.observe(observation(1.9),now:1.9)
        check(timing.pendingTurn(base:Array(repeating:.empty,count:81),excluding:[10],color:.white,after:0)==nil,"Withdrawal retained phantom timing evidence")
        timing.reset();values[10] = .black
        timing.observe(observation(3,hand:nil),now:3);timing.observe(observation(3.3,hand:true),now:3.3)
        check(timing.observedTurns(base:Array(repeating:.empty,count:81),excluding:[],after:0).isEmpty,"Unknown/obstructed hands became clock presses")

        let race=LocalGameClock();race.audible=false
        var reviewAlerts=0,timeouts=0
        race.onAutomaticPause={_ in reviewAlerts+=1};race.onTimeout={timeouts+=1}
        race.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:1),blackToPlay:false);race.ready(at:100)
        race.pendingTurnEvidence = .init(time:114.9,method:.clearFrame)
        race.tick(at:115.1)
        check(race.requiresReview && !race.running && race.engine.expiredBlack==nil,"Timer raced pending on-time evidence into a loss")
        check(race.provisionalMoves.isEmpty && race.engine.white.remaining>0,"An unconfirmed sighting awarded a move or erased the remaining time")
        check(reviewAlerts==1 && timeouts==0,"Uncertain expiry failed to alert the player or announced a loss")
        // Recorded Black87 incident: one verified clear view preceded hand
        // re-entry. Placement review ran after the deadline, before the next
        // timer callback could protect the pending press.
        let reviewRace=LocalGameClock();reviewRace.audible=false
        reviewRace.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:1),blackToPlay:true)
        reviewRace.ready(at:906897.0951851881)
        reviewRace.pendingTurnEvidence = .init(time:906910.05944025,method:.clearFrame)
        reviewRace.recover(toBlack:true,reason:"A placement is visible, but its turn timing is unclear. Review the placement and clocks.",at:906914.9025709167)
        check(reviewRace.engine.expiredBlack==nil,"Placement review raced pending on-time evidence into a loss")
        check(reviewRace.requiresReview && !reviewRace.running,"Unconfirmed placement resumed play without clock review")
        check(abs(reviewRace.engine.black.remaining-2.0357449381)<0.001 && reviewRace.engine.black.periods==1,"Review discarded the last evidenced clock balance")
        check(reviewRace.moves.isEmpty && reviewRace.provisionalMoves.isEmpty,"Review invented a confirmed clock press")
        let lateReview=LocalGameClock();lateReview.audible=false
        lateReview.configure(.init(kind:.absolute,mainSeconds:15),blackToPlay:true);lateReview.ready(at:100)
        lateReview.pendingTurnEvidence = .init(time:116,method:.clearFrame)
        lateReview.recover(toBlack:true,reason:"Late placement needs review",at:117)
        check(lateReview.engine.expiredBlack==true,"A definitely late placement was credited as on time")
        let straddle=LocalGameClock();straddle.audible=false
        straddle.configure(.init(kind:.absolute,mainSeconds:15),blackToPlay:false);straddle.ready(at:100)
        let interval=ClockPressEstimate(time:114.95,method:.handBracket,observedLower:114.8,observedUpper:115.1)
        straddle.recordMove(number:1,black:false,at:115.2,observedAt:interval.time,estimate:interval,provisional:true)
        check(straddle.requiresReview && straddle.engine.expiredBlack==nil,"A boundary overlapping expiry declared a loss while asking for review")
        let batch=LocalGameClock();batch.audible=false
        batch.configure(.init(kind:.absolute,mainSeconds:15),blackToPlay:true);batch.ready(at:100)
        batch.recordCatchUp(first:1,last:2,blackToPlay:true,at:116.2,estimates:[.init(time:101,method:.clearFrame),.init(time:115.95,method:.handBracket,observedLower:115.8,observedUpper:116.1)])
        check(batch.requiresReview && batch.engine.expiredBlack==nil && batch.moves.isEmpty,"A later ambiguous boundary expired the original player during catch-up")
        let late=LocalGameClock();late.audible=false;late.configure(.init(kind:.absolute,mainSeconds:15),blackToPlay:true);late.ready(at:100);late.tick(at:116)
        check(late.engine.expiredBlack==true,"No-move timeout was suppressed")
        print("PASS: \(checks) placement-independent timing checks, including recorded White72 incident")
    }
}
