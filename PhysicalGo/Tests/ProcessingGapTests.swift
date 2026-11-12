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
        print("PASS: \(checks) processing-gap, timer-order, timeout, manual-pause and fresh-verification checks")
    }
}
