import Foundation

/// Camera sampling policy, independent of capture hardware and UI timers.
/// Clock snapshots are advanced on a copy so crossing five seconds does not
/// depend on the next main-thread clock publication arriving in time.
struct CameraProcessingCadence {
    static func interval(clock:LocalClockEngine?,at now:Double)->Double {
        guard var clock,clock.running,now.isFinite else {return 0.2}
        clock.advance(to:now)
        guard clock.running else {return 0.2}
        let remaining=(clock.blackToPlay ? clock.black:clock.white).remaining
        return remaining<=5+1e-9 ? 0.1:0.2
    }

    private var next:Double?
    private var last:Double?
    private var interval=0.2

    /// Keep a fixed sampling schedule despite camera timestamp jitter. Missed
    /// slots are skipped, never queued for catch-up. A rate change takes effect
    /// relative to the last delivered frame rather than restarting the phase.
    mutating func accept(at now:Double,interval requested:Double)->Bool {
        guard now.isFinite,last.map({now>$0}) ?? true else {return false}
        let requested=requested==0.1 ? 0.1:0.2
        if requested != interval {
            interval=requested;next=last.map{$0+interval}
        }
        guard next.map({now+1e-7 >= $0}) ?? true else {return false}
        let due=next ?? now
        next=due+(floor(max(0,now-due)/interval)+1)*interval
        // Rounding at an exact deadline must not leave another slot due now.
        if next!<=now+1e-7 {next! += interval}
        last=now
        return true
    }
}
