import Foundation
@main struct ProcessingGapTests {
    @MainActor static func main() throws {
        var checks=0
        func check(_ value:Bool,_ text:String) {checks+=1;precondition(value,text)}
        func clock()->LocalGameClock {
            let c=LocalGameClock();c.audible=false
            c.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:1),blackToPlay:true)
            var black=c.engine.black;black.remaining=2.035745
            check(c.correct(black:black,white:c.engine.white,blackToPlay:true,moveCount:88,at:100),"Clock setup failed")
            c.noteCameraObservation(at:100,now:100);c.resume(at:100)
            return c
        }
        let delayed=clock();var losses=0;delayed.onTimeout={losses+=1}
        delayed.tick(at:102.448341)
        check(!delayed.running && delayed.engine.expiredBlack==nil && delayed.engine.black.remaining==2.035745,"Recorded processing stall charged the blind interval")
        check(delayed.observationGapHeld && losses==0,"Processing stall reported a loss instead of a hold")
        let arrival=clock()
        arrival.noteCameraObservation(at:101.82,now:102.448341)
        arrival.interrupt("Checking camera",at:102.448341)
        check(arrival.engine.expiredBlack==nil && arrival.engine.black.remaining==delayed.engine.black.remaining,"Arrival-before-timer ordering changed the balance")
        let healthy=clock()
        for t in [100.4,100.8,101.2,101.6,102.0] {healthy.noteCameraObservation(at:t,now:t);healthy.tick(at:t)}
        healthy.tick(at:102.1)
        check(healthy.running && healthy.engine.expiredBlack==nil,"Timer inferred a loss before a fresh observation crossed the deadline")
        healthy.noteCameraObservation(at:102.2,now:102.2);healthy.tick(at:102.2)
        check(healthy.engine.expiredBlack==true,"Continuous observations suppressed a real timeout")
        let brief=clock();brief.noteCameraObservation(at:101,now:101);brief.tick(at:101)
        check(brief.running && abs(brief.engine.black.remaining-1.035745)<1e-8,"Short processing delay paused or refunded ordinary thinking time")
        brief.pause(at:101);brief.noteCameraObservation(at:105,now:105)
        check(!brief.running && abs(brief.engine.black.remaining-1.035745)<1e-8,"A later camera frame revoked a manual pause")
        let interrupted=clock()
        interrupted.noteCameraObservation(at:100.9,now:100.9)
        interrupted.noteCameraObservation(at:101.8,now:101.8);interrupted.tick(at:101.8)
        interrupted.interrupt("Camera disconnected",at:102.1)
        check(interrupted.engine.expiredBlack==nil && abs(interrupted.engine.black.remaining-0.235745)<1e-8,"Short camera failure near expiry charged unseen time")
        let optOut=clock();optOut.pauseOnInterruption=false;optOut.tick(at:103)
        check(optOut.engine.expiredBlack==true,"Explicit interruption preference was overridden")
        let stale=clock();stale.noteCameraObservation(at:99,now:101);stale.tick(at:102)
        check(!stale.running && stale.engine.black.remaining==2.035745,"Old frame postponed the freshness hold")
        let pending=clock();pending.noteCameraObservation(at:100.8,now:100.8)
        pending.pendingTurnEvidence = .init(time:100.5,method:.clearFrame)
        pending.tick(at:103)
        check(abs(pending.engine.black.remaining-1.535745)<1e-8 && pending.engine.expiredBlack==nil,"Gap erased an earlier possible press")

        let capture=clock()
        capture.pause(at:100)
        capture.noteCameraObservation(at:105,now:105)
        capture.requestResume();capture.ready(at:103.5);capture.tick(at:105)
        check(capture.running && abs(capture.engine.black.remaining-0.535745)<1e-8,"Retrospective capture completion rewound camera freshness")
        capture.pause(at:105)

        let root=FileManager.default.temporaryDirectory.appendingPathComponent("processing-gap-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let r=GameRecorder(storage:root);r.clock.audible=false
        var now=ProcessInfo.processInfo.systemUptime
        r.start(size:9,now:now,clockSettings:.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:1))
        func feed(_ t:Double) {
            r.consume(.init(readings:(0..<81).map{.init(row:$0/9,col:$0%9,occupancy:.empty,confidence:1,delta:0)},size:9,capturedAt:t,handObstructed:false),now:t)
        }
        for _ in 0..<6 {now+=0.21;feed(now)}
        check(r.clock.running,"Recorder clock failed to start")
        r.clock.tick(at:now+2);let protected=r.clock.engine.black
        feed(now+2.1)
        check(!r.clock.running && !r.synchronized && r.clock.engine.black==protected,"Gap resumed against old verification frames")
        now+=2.1
        for _ in 0..<8 {now+=0.21;feed(now)}
        check(r.clock.running && !r.clock.requiresReview && r.clock.engine.black==protected,"Unchanged freshly verified board could not resume the protected balance")
        r.pause()
        checks += try AutomaticHoldAccountingTests.run()
        print("PASS: \(checks) processing-gap, timer-order, timeout, manual-pause and fresh-verification checks")
    }
}

enum AutomaticHoldAccountingTests {
    @MainActor static func run()throws->Int {
        var checks=0
        func check(_ value:Bool,_ text:String) {checks+=1;precondition(value,text)}
        func press(_ time:Double)->ClockPressEstimate {.init(time:time,method:.clearFrame)}
        func clock(_ settings:LocalClockSettings,black:Bool=true)->LocalGameClock {
            let c=LocalGameClock();c.audible=false;c.configure(settings,blackToPlay:black);c.ready(at:100);return c
        }
        for kind in LocalClockSettings.Kind.allCases where kind != .none {
            let settings=LocalClockSettings(kind:kind,mainSeconds:[.byoyomi,.canadian].contains(kind) ? 0:100,
                periodSeconds:20,periods:5,incrementSeconds:3,maximumSeconds:150,stonesPerPeriod:3)
            // Independent chronological oracle: real presses and stopped periods,
            // compared to delayed single-move and atomic catch-up delivery.
            var expected=LocalClockEngine(settings:settings,blackToPlay:true);expected.resume(at:100)
            check(expected.move(black:true,at:102),"Oracle first move")
            expected.pause(at:104);expected.resume(at:109)
            check(expected.move(black:false,at:110),"Oracle second move")
            expected.pause(at:111);expected.resume(at:115)
            check(expected.move(black:true,at:117),"Oracle third move")
            expected.advance(to:119)
            for catchUp in [false,true] {
                let c=clock(settings)
                c.pause("Checking view",at:104,manual:false);c.ready(at:109)
                c.pause("Checking view",at:111,manual:false);c.ready(at:115)
                if catchUp {c.recordCatchUp(first:1,last:3,blackToPlay:false,at:119,estimates:[press(102),press(110),press(117)])}
                else {
                    for (i,time) in [102.0,110,117].enumerated() {
                        c.recordMove(number:i+1,black:i%2==0,at:119,observedAt:time,estimate:press(time))
                    }
                }
                check(c.engine==expected && !c.requiresReview,"Hold accounting mismatch for \(kind), catchUp=\(catchUp)")
                check(c.moves.map{$0.after.anchor!}==[102,110,117] && c.pressEvidence.allSatisfy(\.applied),"Hold discarded physical press times")
                let once=c.engine;c.recordMove(number:3,black:true,at:119,observedAt:117,estimate:press(117))
                check(c.engine==once,"Repeated delayed press awarded a second increment")
                c.pause(at:119)
            }
            let held=clock(settings);held.pause("Checking view",at:104,manual:false)
            held.recordMove(number:1,black:true,at:120,observedAt:102,estimate:press(102))
            var stopped=LocalClockEngine(settings:settings,blackToPlay:true);stopped.resume(at:100)
            _=stopped.move(black:true,at:102);stopped.pause(at:104)
            check(held.engine==stopped && !held.running && !held.requiresReview,"Known press did not preserve an open hold")
            held.ready(at:120);held.tick(at:121);stopped.resume(at:120);stopped.advance(to:121)
            check(held.engine==stopped,"Resuming a reconstructed turn charged hold time")
            held.pause(at:121)

            let capture=clock(settings)
            capture.pause("Checking view",at:101,manual:false);capture.ready(at:105)
            check(capture.beginAutomaticCapture(at:107,now:108),"Capture could not start after an automatic hold")
            let frozen=capture.engine;capture.interrupt("Hand during removal",at:120);capture.tick(at:130)
            check(capture.engine==frozen,"Camera interruption charged capture removal")
            capture.recordMove(number:1,black:true,at:135)
            capture.finishAutomaticCapture(at:130,now:135)
            var captureOracle=LocalClockEngine(settings:settings,blackToPlay:true);captureOracle.resume(at:100)
            captureOracle.pause(at:101);captureOracle.resume(at:105);captureOracle.pause(at:107)
            _=captureOracle.move(black:true,at:135);captureOracle.resume(at:130);captureOracle.advance(to:135)
            check(capture.engine==captureOracle && !capture.requiresReview,"Capture hold changed bonuses or next-player time")
            capture.pause(at:135)
        }
        for black in [true,false] {
            let c=clock(.init(kind:.absolute,mainSeconds:100),black:black)
            c.tick(at:103)
            check((black ? c.engine.black:c.engine.white).remaining==97,"Start failed to charge the initial player")
            c.pause(at:103)
        }
        for scenario in ["inside-open", "inside-closed", "overlapping", "candidate", "manual", "missing", "future"] {
            let c=clock(.init(kind:.fischer,mainSeconds:100,incrementSeconds:3))
            c.pause("Checking view",at:104,manual:scenario == "manual")
            if scenario != "inside-open" {c.resume(at:109)}
            let time:Double = scenario.hasPrefix("inside") ? 106:scenario == "overlapping" ? 103.9:scenario == "future" ? 121:102
            let e:ClockPressEstimate? = scenario == "missing" ? nil:scenario == "overlapping"
                ? .init(time:time,method:.handBracket,observedLower:103.8,observedUpper:104.1)
                : scenario == "candidate" ? .init(time:time,method:.candidate):press(time)
            c.recordMove(number:1,black:true,at:120,observedAt:time,estimate:e)
            check(c.requiresReview && !c.running && c.moves.isEmpty,"\(scenario): unsafe press silently became recognition time")
            check(c.pressEvidence.allSatisfy{!$0.applied},"\(scenario): review marked evidence applied")
        }
        let timeout=clock(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:3,periods:1))
        timeout.pause("Checking view",at:102,manual:false)
        timeout.recordMove(number:1,black:true,at:200,observedAt:101.5,estimate:press(101.5))
        check(timeout.engine.expiredBlack==nil && timeout.engine.black.remaining==3 && timeout.engine.white.remaining==2.5,"Held recognition delay consumed overtime")
        let partial=clock(.init(kind:.fischer,mainSeconds:100,incrementSeconds:3))
        partial.pause("Checking view",at:104,manual:false);partial.ready(at:109)
        partial.recordCatchUp(first:1,last:2,blackToPlay:true,at:120,estimates:[press(102),press(106)])
        check(partial.requiresReview && partial.moves.isEmpty && partial.pressEvidence.allSatisfy{!$0.applied},"Catch-up partially applied a sequence crossing a hold")
        let tentative=clock(.init(kind:.fischer,mainSeconds:100,incrementSeconds:3))
        tentative.pause("Checking view",at:104,manual:false)
        tentative.recordMove(number:1,black:true,at:110,observedAt:106,estimate:press(106),provisional:true)
        check(tentative.baseMove==0 && tentative.provisionalMoves.isEmpty && !tentative.requiresReview && !tentative.running,"Tentative hold evidence advanced persisted history or prematurely forced review")
        tentative.recordMove(number:1,black:true,at:111,observedAt:106,estimate:press(106))
        check(tentative.requiresReview && tentative.baseMove==1 && tentative.moves.isEmpty,"Confirmed unsafe move did not require clock review")
        let exact=clock(.init(kind:.fischer,mainSeconds:100,incrementSeconds:3))
        exact.pause("Checking view",at:104,manual:false)
        exact.recordMove(number:1,black:true,at:104,observedAt:104,estimate:press(104))
        check(exact.moves.first?.after.anchor==104 && exact.engine.black.remaining==99 && !exact.running,"Press at the exact hold boundary lost its anchor or resumed the hold")
        exact.ready(at:109)
        exact.recordMove(number:2,black:false,at:111,observedAt:109,estimate:press(109))
        check(exact.moves.last?.after.anchor==109 && exact.engine.white.remaining==103 && exact.engine.black.remaining==97,"Press at the exact resume boundary charged held time")
        let live=clock(.init(kind:.absolute,mainSeconds:100))
        live.pause("Checking view",at:104,manual:false);live.ready(at:109)
        let id=UUID();live.recordLiveMove(id:id,black:true,at:110,observedAt:102,estimate:press(102))
        check(live.engine.black.remaining==98 && live.engine.white.remaining==97,"Deferred live press charged automatic hold time")
        let prior=live.engine;live.finalizeLiveHistory(mapping:[id:1],moveCount:1,blackToPlay:false)
        check(live.engine==prior && live.pressEvidence.first?.applied==true,"Deferred history finalization pressed the clock again")
        live.pause(at:110)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("hold-review-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let recorder=GameRecorder(storage:root);recorder.clock.audible=false
        var now=ProcessInfo.processInfo.systemUptime+1
        recorder.start(size:9,now:now,clockSettings:.init(kind:.absolute,mainSeconds:100))
        var stones=Array(repeating:Occupancy.empty,count:81)
        func feed() {
            now+=0.21
            recorder.consume(.init(readings:stones.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},
                                   size:9,capturedAt:now,handObstructed:false),now:now)
        }
        for _ in 0..<8 {feed()}
        now+=2;recorder.clock.tick(at:now)
        stones[40] = .black
        for _ in 0..<12 {feed()}
        check(recorder.moveCount==1 && recorder.clock.requiresReview && recorder.clock.moves.isEmpty,"Recorder accepted a move inside a hold without clock review")
        recorder.pause()
        let black=recorder.clock.engine.black,white=recorder.clock.engine.white
        check(recorder.confirmClockReview(black:black,white:white,resume:true),"Could not confirm agreed hold-review balances")
        for _ in 0..<10 {feed()}
        check(recorder.clock.running && !recorder.clock.requiresReview && !recorder.clock.engine.blackToPlay,"Hold review/resume loop failed to release the next player")
        check(recorder.clock.engine.black==black,"Review replayed the uncertain first move or added an increment")
        recorder.pause();try recorder.flushStorage()
        let restored=GameRecorder(storage:root);restored.clock.audible=false
        try restored.restoreSavedGame(from:recorder.autosaveURL!)
        check(!restored.clock.running && !restored.clock.requiresReview && restored.moveCount==1,"Restart lost the explicitly agreed hold review")
        return checks
    }
}
