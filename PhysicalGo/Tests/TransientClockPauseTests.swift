import Foundation

@main struct TransientClockPauseTests {
    struct Frame:Decodable {let time:Double;let position:String}
    struct Incident:Decodable {let frames:[Frame]}
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let fixtures=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/TransientClockPause")
        let incident=try JSONDecoder().decode(Incident.self,from:Data(contentsOf:fixtures.appendingPathComponent("observations.json")))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("transient-clock-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("incident.sgf")
        try FileManager.default.copyItem(at:fixtures.appendingPathComponent("game.sgf"),to:file)
        let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file);r.resume()
        let origin=ProcessInfo.processInfo.systemUptime+4-incident.frames[0].time
        let base=DeferredMoveHistory.states(r.positions.last!)
        func feed(_ values:[Occupancy],at t:Double) {
            r.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:t,handObstructed:false),now:t)
            r.clock.tick(at:t)
        }
        for i in 0..<8 {feed(base,at:origin+incident.frames[0].time-2+Double(i)*0.21)}
        r.clock.configure(.init(kind:.byoyomi,mainSeconds:120,periodSeconds:15,periods:5),blackToPlay:false,baseMove:3)
        let start=origin+incident.frames[0].time
        r.clock.ready(at:start)
        var pauses=0,previous=start
        r.clock.onAutomaticPause={_ in pauses+=1}
        for f in incident.frames {
            let t=origin+f.time
            // Compact diagnostics omit intervening camera/hand callbacks.
            // Supply continuity only, never a synthetic stone or clock press.
            while t-previous>0.5 {previous+=0.3;r.noteHandObstruction(now:previous)}
            previous=t
            feed(f.position.map{$0 == "B" ? .black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty},at:t)
            check(r.clock.running && !r.clock.needsCorrection,"Transient recorded stone readings latched a clock pause at \(f.time): \(r.clock.notice)")
        }
        check(pauses==0,"False alarm emitted an automatic pause")
        check(r.moveCount==4 && r.game.moves.last?.1?.0==16 && r.game.moves.last?.1?.1==3,"Replay did not retain the real White fourth move")
        check(r.clock.moves.map(\.number)==[4] && r.clock.engine.blackToPlay,"False stones invented turns or lost White's press")
        let firstWhite=incident.frames.first{Array($0.position)[73] == "W"}!.time+origin
        check(abs(r.clock.moves[0].estimate!.time-firstWhite)<0.001,"Recognition delay replaced White's first retained observation time")
        check(abs(r.clock.engine.white.remaining-(120-(firstWhite-start)))<0.001,"White was charged recognition delay")
        r.pause()
        // Distinguish retractable camera noise from a stable missed-turn board.
        for scenario in ["retracted", "interrupted", "persistent", "simultaneous", "expiry"] {
            let recorder=GameRecorder(storage:nil);recorder.clock.audible=false
            var now=ProcessInfo.processInfo.systemUptime+4
            var values=Array(repeating:Occupancy.empty,count:81)
            recorder.start(size:9,now:now,clockSettings:.init(kind:.absolute,mainSeconds:60))
            func advance(_ count:Int) {
                for _ in 0..<count {
                    now+=0.21
                    recorder.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:now,handObstructed:false),now:now)
                    recorder.clock.tick(at:now)
                }
            }
            advance(8)
            let established=recorder.clock.engine
            values[10] = scenario == "simultaneous" ? .black:.white
            values[30] = .white
            if scenario == "persistent" {values[50] = .white}
            advance(2)
            check(recorder.clock.running && !recorder.clock.needsCorrection,"\(scenario): two suspect frames paused prematurely")
            check(recorder.clock.moves.isEmpty && recorder.clock.provisionalMoves.isEmpty,"\(scenario): conflicting sightings invented a press")
            if scenario == "retracted" || scenario == "interrupted" {
                if scenario == "interrupted" {
                    advance(2)
                    now+=0.21;recorder.noteHandObstruction(now:now)
                    advance(1)
                    check(recorder.clock.running && !recorder.clock.requiresReview,"Hand re-entry failed to reset suspect-board confirmation")
                }
                values=Array(repeating:.empty,count:81);advance(6)
                check(recorder.clock.pendingUnaccountedInterval==nil,"Retracted stones retained a false timing gap")
                values[60] = .black;let firstSeen=now+0.21;advance(8)
                check(recorder.moveCount==1 && recorder.clock.running && !recorder.clock.requiresReview,"A recovered view still required clock review")
                check(recorder.clock.moves.count==1 && recorder.clock.moves[0].estimate?.time==firstSeen,"Real move lost its observed press after the false alarm")
            } else if scenario == "expiry" {
                var timeouts=0;recorder.clock.onTimeout={timeouts+=1}
                // Keep camera continuity fresh up to the deadline without
                // adding confirmation of the suspect stone identities.
                let deadline=established.anchor!+established.black.remaining+0.01
                var stamp=now
                while stamp<deadline {stamp=min(deadline,stamp+0.3);recorder.clock.noteCameraObservation(at:stamp,now:stamp)}
                recorder.clock.tick(at:deadline)
                check(recorder.clock.requiresReview && !recorder.clock.running,"Unaccounted turns were charged through expiry")
                check(timeouts==0 && recorder.clock.engine.expiredBlack==nil,"Unresolved timing falsely declared a timeout")
            } else {
                advance(70)
                check(recorder.clock.requiresReview && !recorder.clock.running,"\(scenario): stable missing-turn evidence failed to stop clocks")
                check(recorder.clock.moves.isEmpty && recorder.clock.provisionalMoves.isEmpty,"\(scenario): missing press times were invented")
                let held=recorder.clock.engine
                recorder.clock.tick(at:now+10);recorder.clock.ready(at:now+10)
                check(recorder.clock.engine==held && !recorder.clock.running,"\(scenario): genuine timing review resumed itself")
            }
            recorder.pause()
        }
        // Nov 15: B19 flickered while its older adjustment marker remained.
        // A one-frame return to the saved position discarded the candidate,
        // but previously left its two-second clock-review timer running.
        struct FlickerFrame:Decodable {let time:Double;let position:String;let capturedAt:Double;let scores:[String:Double]}
        struct FlickerIncident:Decodable {let frames:[FlickerFrame]}
        let flicker=try JSONDecoder().decode(FlickerIncident.self,from:Data(contentsOf:fixtures.appendingPathComponent("FlickeringB19.json")))
        let flickerFile=root.appendingPathComponent("flicker.sgf")
        try "(;AP[PhysicalGo:0.186]GM[1]FF[4]SZ[19]KM[6.5];B[pp];W[po];B[qo];W[dd])".write(to:flickerFile,atomically:true,encoding:.utf8)
        let f=GameRecorder(storage:nil);f.clock.audible=false;try f.restoreSavedGame(from:flickerFile)
        let beginning=1263346.8038865833,shift=ProcessInfo.processInfo.systemUptime+4-beginning
        let saved=DeferredMoveHistory.states(f.positions.last!)
        func flickerFeed(_ values:[Occupancy],at time:Double,captured:Double?=nil,scores:[String:Double]=[:]) {
            f.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:scores[String($0.offset)] ?? 1,delta:0)},size:19,capturedAt:captured ?? time,handObstructed:false),now:time)
            f.clock.tick(at:time)
        }
        // Reconstruct the adjustment marker explicitly recorded at replay start.
        // These paused setup samples are synthetic, not extra camera evidence.
        var marked=saved;marked[323] = .black
        for i in 0..<5 {flickerFeed(marked,at:shift+beginning-4+Double(i)*0.21)}
        check(f.adjustmentIssues[323] != nil,"Could not reconstruct logged B19 adjustment marker")
        f.resume()
        var baseline=saved;baseline[323] = .uncertain
        for i in 0..<8 {flickerFeed(baseline,at:shift+beginning-2+Double(i)*0.21)}
        f.clock.configure(.init(kind:.absolute,mainSeconds:120),blackToPlay:true,baseMove:4)
        f.clock.ready(at:shift+beginning)
        var flickerPauses=0,flickerPrevious=shift+beginning
        f.clock.onAutomaticPause={_ in flickerPauses+=1}
        for frame in flicker.frames {
            let t=shift+frame.time
            // The journal omits intermediate hand callbacks; retain continuity
            // across the actual next placement without inventing a clock press.
            while t-flickerPrevious>0.5 {flickerPrevious+=0.3;f.noteHandObstruction(now:flickerPrevious)}
            flickerPrevious=t
            flickerFeed(frame.position.map{$0 == "B" ? .black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty},at:t,captured:shift+frame.capturedAt,scores:frame.scores)
            check(f.clock.running && !f.clock.requiresReview,"B19 flickers inherited an obsolete timing hold at \(frame.time)")
        }
        check(flickerPauses==0,"B19 false alarm emitted an automatic pause")
        check(f.moveCount==5 && f.game.moves.last?.1?.0==15 && f.game.moves.last?.1?.1==13,"Real F4 reply was lost or B19 was saved")
        check(f.clock.moves.map(\.number)==[5] && !f.clock.engine.blackToPlay,"Phantom B19 invented a clock press")
        let firstF4=flicker.frames.first{Array($0.position)[262] == "B"}!.capturedAt+shift
        check(abs(f.clock.moves[0].estimate!.time-firstF4)<0.001,"Real F4 inherited the false candidate's timestamp")
        check(abs(f.clock.engine.black.remaining-(120-(firstF4-(shift+beginning))))<0.001,"F4 recognition delay changed Black's charged time")
        f.pause()
        print("PASS: \(checks) recorded transient-clock-pause checks")
    }
}
