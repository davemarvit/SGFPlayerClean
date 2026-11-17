import Foundation

/// Recorded startup regression: unsafe accounting must become explicit review.
/// No app UI, recording files, camera, or persisted clock state are accessed.
@main struct StartupClockReplay {
    @MainActor static func main() throws {
        func make() -> LocalGameClock {
            let clock=LocalGameClock();clock.audible=false
            clock.configure(.init(kind:.byoyomi,mainSeconds:120,periodSeconds:15,periods:5),blackToPlay:true)
            return clock
        }
        let clock=make()
        // Original uptime coordinates from game 3742C9CE. ready() moves freshness
        // to Start; the next delivered frame predates that boundary and is ignored.
        let start=1326263.0938285
        clock.noteCameraObservation(at:1326262.8655001672,now:start)
        clock.ready(at:start)
        clock.noteCameraObservation(at:1326263.0515002501,now:1326264.5176060419)
        clock.noteCameraObservation(at:1326264.46450025,now:1326264.6754035417)
        let held=clock.observationGapHeld && !clock.running
        let estimates=[1326267.3460003128,1326270.3480002712,1326274.6610001877]
        let recognized=[1326271.0435899585,1326275.609585125,1326278.4949239583]
        for index in 0..<3 {
            // Fresh observations between recognition calls prevent another hold;
            // they cannot establish presses inside the unresolved hold.
            if index>0 {
                var time=recognized[index-1]+0.5
                while time<recognized[index] {
                    clock.noteCameraObservation(at:time,now:time);time+=0.5
                }
            }
            clock.noteCameraObservation(at:recognized[index]-0.1,now:recognized[index])
            let estimate=ClockPressEstimate(time:estimates[index],method:.handBracket)
            clock.recordMove(number:index+1,black:index%2==0,at:recognized[index],observedAt:estimate.time,estimate:estimate)
            if index==0 {clock.ready(at:recognized[index])}
        }
        let firstFree=clock.moves.first?.after.black.remaining==120
        let unapplied=clock.pressEvidence.filter{!$0.applied}.map(\.number)
        let hiddenTimingFailure=held && firstFree && unapplied == [1,2,3] && !clock.requiresReview
        let unsafeAccountingPrevented=held && clock.requiresReview && !clock.running && clock.moves.isEmpty && unapplied == [1,2,3]
        // Controls: current Start semantics still charge first Black/White turns
        // when camera continuity is healthy (White represents handicap setup).
        var controls=[String:Bool]()
        for black in [true,false] {
            let c=make()
            c.configure(.init(kind:.byoyomi,mainSeconds:120,periodSeconds:15,periods:5),blackToPlay:black)
            c.noteCameraObservation(at:100,now:100);c.ready(at:100)
            for i in 1...5 {c.noteCameraObservation(at:100+Double(i),now:100+Double(i))}
            let estimate=ClockPressEstimate(time:104,method:.clearFrame)
            c.recordMove(number:1,black:black,at:105,observedAt:104,estimate:estimate)
            let mover=black ? c.engine.black:c.engine.white
            let next=black ? c.engine.white:c.engine.black
            controls[black ? "blackFirstTurnCharged":"whiteFirstTurnCharged"] = abs(mover.remaining-116)<1e-8 && abs(next.remaining-119)<1e-8
            c.pause(at:105)
        }
        let result:[String:Any]=[
            "diagnosticOnly":true,"knownFailureReproduced":hiddenTimingFailure,
            "unsafeAccountingPrevented":unsafeAccountingPrevented,
            "startupGapHeld":held,"firstMoveChargedZero":firstFree,
            "unappliedEstimates":unapplied,"requiresReview":clock.requiresReview,
            "blackRemaining":clock.engine.black.remaining,"whiteRemaining":clock.engine.white.remaining,
            "controls":controls,
            "scope":"Native clock regression using recorded times. Unsafe allocation now requires review; original saved times are not rewritten. Start behavior unchanged."
        ]
        clock.pause(at:recognized.last!)
        print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
        precondition(controls.values.allSatisfy{$0},"Existing Start countdown control failed")
        precondition(unsafeAccountingPrevented,"Startup hold silently assigned unsupported clock times")
    }
}
