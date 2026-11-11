import AppKit
@main struct HandClockTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory);setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        func press(_ t:Double)->ClockPressEstimate {.init(time:t,method:.handMotion,observedLower:t-0.05,observedUpper:t+0.05,estimatedError:0.02,samples:3,timestampSource:"cameraPresentation")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("hand-clock-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        for kind in LocalClockSettings.Kind.allCases where kind != .none {
            let settings=LocalClockSettings(kind:kind,mainSeconds:100,periodSeconds:20,periods:5,incrementSeconds:3,maximumSeconds:150,stonesPerPeriod:3)
            let c=LocalGameClock();c.audible=false;c.configure(settings,blackToPlay:true);c.ready(at:100)
            let file=root.appendingPathComponent(kind.rawValue+".sgf");c.bind(to:file,signature:kind.rawValue)
            var expected=c.engine
            for (i,t) in [102.0,105,108].enumerated() {check(expected.move(black:i%2==0,at:t),"Reference clock failed")}
            expected.advance(to:110);c.tick(at:110)
            c.recordCatchUp(first:1,last:3,blackToPlay:false,at:110,estimates:[press(102),press(105),press(108)])
            check(c.engine==expected && c.moves.map(\.number)==[1,2,3],"Catch-up did not replay individual presses/increments for \(kind)")
            check(c.moves.map{$0.after.anchor!}==[102,105,108] && c.pressEvidence.allSatisfy(\.applied),"Press timestamps or applied status lost")
            let once=c.engine;c.recordCatchUp(first:1,last:3,blackToPlay:false,at:111,estimates:[press(102),press(105),press(108)])
            check(c.engine==once,"Duplicate catch-up charged clocks again")
            c.pause(at:110)
            let restored=LocalGameClock();restored.audible=false;restored.restore(from:file,signature:kind.rawValue,moveCount:3,blackToPlay:false)
            check(restored.saveError==nil && restored.moves.last?.estimate==press(108) && restored.pressEvidence.count==3,"Restart lost error bars or per-move evidence")
        }
        let partial=LocalGameClock();partial.audible=false;partial.configure(.init(kind:.fischer,mainSeconds:100,incrementSeconds:3),blackToPlay:true);partial.ready(at:100)
        let partialFile=root.appendingPathComponent("missing-press.sgf");partial.bind(to:partialFile,signature:"missing")
        partial.recordCatchUp(first:1,last:3,blackToPlay:false,at:110,estimates:[press(102),nil,press(108)])
        check(partial.moves.isEmpty && partial.pressEvidence.count==3 && partial.pressEvidence.allSatisfy{!$0.applied},"Missing evidence partially replayed clocks or discarded known boundaries")
        check(partial.engine.black.remaining==90 && partial.engine.white.remaining==100,"Missing boundary invented thinking time or bonuses")
        check(partial.requiresReview && !partial.running,"Missing clock evidence silently continued charging one player")
        let frozen=partial.engine;partial.tick(at:200);partial.ready(at:200)
        check(partial.engine==frozen && !partial.running,"Missing-evidence review resumed or lost further periods")
        let restoredPartial=LocalGameClock();restoredPartial.audible=false;restoredPartial.restore(from:partialFile,signature:"missing",moveCount:3,blackToPlay:false)
        check(restoredPartial.requiresReview && !restoredPartial.running && restoredPartial.pressEvidence.count==3,"Restart hid missing-evidence review or lost retained presses")
        let paused=LocalGameClock();paused.audible=false;paused.configure(.init(kind:.absolute,mainSeconds:100),blackToPlay:true);paused.ready(at:100);paused.pause(at:106)
        paused.recordCatchUp(first:1,last:3,blackToPlay:false,at:110,estimates:[press(101),press(102),press(103)])
        check(!paused.running && paused.engine.black.remaining==94 && paused.moves.isEmpty,"Catch-up rewound or restarted a manual pause")
        let expiry=LocalGameClock();expiry.audible=false;expiry.configure(.init(kind:.absolute,mainSeconds:10),blackToPlay:true);expiry.ready(at:100)
        let uncertain=ClockPressEstimate(time:109.9,method:.handMotion,observedLower:109.8,observedUpper:110.2,estimatedError:0.05,samples:3)
        expiry.recordMove(number:1,black:true,at:111,observedAt:109.9,estimate:uncertain)
        check(expiry.requiresReview && !expiry.running && expiry.moves.isEmpty,"Uncertain timeout was silently overturned")
        let modelExpiry=LocalGameClock();modelExpiry.audible=false;modelExpiry.configure(.init(kind:.absolute,mainSeconds:10),blackToPlay:true);modelExpiry.ready(at:100)
        let modelUncertainty=ClockPressEstimate(time:109.95,method:.handMotion,observedLower:109.90,observedUpper:109.98,estimatedError:0.10,samples:3)
        modelExpiry.recordMove(number:1,black:true,at:111,observedAt:modelUncertainty.time,estimate:modelUncertainty)
        check(modelExpiry.requiresReview && !modelExpiry.running,"Physical edge uncertainty outside the sampled bracket silently decided expiry")
        let late=LocalGameClock();late.audible=false;late.configure(.init(kind:.absolute,mainSeconds:10),blackToPlay:true);late.ready(at:100)
        late.recordCatchUp(first:1,last:2,blackToPlay:true,at:115,estimates:[press(102),press(114)])
        check(late.requiresReview && !late.running && late.moves.isEmpty && late.pressEvidence.allSatisfy{!$0.applied},"Catch-up crossing a later player's expiry silently accepted all moves")
        let live=LocalGameClock();live.audible=false;live.configure(.init(kind:.fischer,mainSeconds:100,incrementSeconds:3),blackToPlay:true);live.ready(at:100)
        let liveID=UUID();live.recordLiveMove(id:liveID,black:true,at:105,observedAt:102,estimate:press(102))
        let liveEngine=live.engine;live.finalizeLiveHistory(mapping:[liveID:1],moveCount:1,blackToPlay:false)
        check(live.engine==liveEngine && live.moves.first?.estimate==press(102) && live.pressEvidence.first?.applied==true,"Review finalization lost a live press or charged time twice")
        var history=ClearBoardTiming()
        let positions:[[Occupancy]]=[[.black,.empty,.empty,.empty],[.black,.white,.empty,.empty],[.black,.white,.black,.empty]]
        for (i,position) in positions.enumerated() {
            let t=Double(i+1)
            history.observe(.init(readings:position.enumerated().map{.init(row:$0.offset/2,col:$0.offset%2,occupancy:$0.element,confidence:1,delta:0)},size:2,capturedAt:t,handObstructed:false,clockPressEstimate:press(t-0.01)),now:t)
        }
        check(history.estimate(target:positions[0],changed:[0],after:0)?.time==0.99,"Later frames erased an earlier press during catch-up")
        history.consume(through:0.99)
        check(history.estimate(target:positions[0],changed:[0],after:0)==nil,"A recorded press could be reused")
        check(history.estimate(target:positions[1],changed:[1],after:1)?.time==1.99,"Consuming one press erased later evidence")
        history.reset();check(history.estimate(target:positions[2],changed:[2],after:0)==nil,"Camera reset retained stale clock boundaries")
        let firstPosition=positions[0]
        history.observe(.init(readings:firstPosition.enumerated().map{.init(row:$0.offset/2,col:$0.offset%2,occupancy:$0.element,confidence:1,delta:0)},size:2,capturedAt:10,handObstructed:false),now:10)
        for t in [11.0,12,13] {history.noteHand(at:t)}
        history.observe(.init(readings:positions[1].enumerated().map{.init(row:$0.offset/2,col:$0.offset%2,occupancy:$0.element,confidence:1,delta:0)},size:2,capturedAt:14,handObstructed:false),now:14)
        check(history.estimate(target:firstPosition,changed:[0],after:0)?.time==10,"Continuous hand frames erased a completed earlier move")
        // Real recorder path: three distinct clear views followed by delayed
        // repeated confirmation must retain all three historical press times.
        let r=GameRecorder(storage:root);r.clock.audible=false
        r.start(size:9,clockSettings:.init(kind:.fischer,mainSeconds:100,incrementSeconds:3))
        var values=Array(repeating:Occupancy.empty,count:81),now=ProcessInfo.processInfo.systemUptime
        func feed(_ count:Int) {for _ in 0..<count {now+=0.21;r.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:now-0.01,handObstructed:false),now:now)}}
        feed(8);values[10] = .black;feed(1);let first=now-0.01
        r.noteHandObstruction(now:now+0.05);values[20] = .white;feed(1);let second=now-0.01
        r.noteHandObstruction(now:now+0.05);values[30] = .black;feed(20)
        check(r.moveCount==3,"Recorder did not confirm retained three-move sequence")
        check(r.clock.moves.count==3 && abs(r.clock.moves[0].after.anchor!-first)<1e-6 && abs(r.clock.moves[1].after.anchor!-second)<1e-6,"Recorder lost presses across hand re-entry")
        r.pause()
        checks += try ClockCatchUpIncidentTests.run()
        print("PASS: \(checks) clock catch-up checks: all timed modes, individual presses, increments, persistence, missing evidence, manual pause, timeout uncertainty and actual recorder hand re-entry")
    }
}
