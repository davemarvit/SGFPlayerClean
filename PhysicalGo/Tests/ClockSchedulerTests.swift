import AppKit
import Combine

/// Exercise actual scheduled callbacks, rather than calling tick manually.
@main struct ClockSchedulerTests {
    @MainActor static func main() {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        func pump(_ seconds:Double) {RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
        let clock=LocalGameClock();clock.audible=false
        clock.configure(.init(kind:.absolute,mainSeconds:60),blackToPlay:true)
        var stamps=[Double]()
        let subscription=clock.$engine.sink {_ in stamps.append(ProcessInfo.processInfo.systemUptime)}
        clock.resume();stamps=[];pump(0.65)
        check(stamps.count>=3,"Scheduled clock did not publish while running")

        // A blocked UI must coalesce callbacks and debit real elapsed time once.
        let before=clock.engine.black.remaining,start=clock.engine.anchor!
        Thread.sleep(forTimeInterval:0.35);pump(0.25)
        let elapsed=clock.engine.anchor!-start
        check(elapsed>=0.5,"Scheduled callback never caught up after UI work")
        check(abs(before-clock.engine.black.remaining-elapsed)<0.000001,"Delayed callback lost or double-charged elapsed time")

        clock.pause();let paused=clock.engine.black.remaining
        stamps=[];pump(0.35)
        check(stamps.isEmpty && clock.engine.black.remaining==paused,"Cancelled scheduler published or charged during manual pause")
        clock.resume();clock.resume();stamps=[];pump(0.65)
        check(stamps.count>=3 && stamps.count<=8,"Repeated resume lost or duplicated the scheduler")
        clock.configure(.init(kind:.absolute,mainSeconds:60),blackToPlay:false)
        stamps=[];pump(0.35)
        check(stamps.isEmpty && !clock.running,"Reconfiguration left the old scheduler running")
        clock.resume();pump(0.35)
        check(clock.engine.white.remaining<60 && clock.engine.black.remaining==60,"Reconfigured scheduler charged the wrong player")
        let captureAt=ProcessInfo.processInfo.systemUptime
        check(clock.beginAutomaticCapture(at:captureAt,now:captureAt),"Could not enter capture hold")
        let captureBalance=clock.engine.white.remaining
        stamps=[];pump(0.35)
        check(stamps.isEmpty && clock.engine.white.remaining==captureBalance,"Capture hold left the scheduler charging time")
        let clearedAt=ProcessInfo.processInfo.systemUptime
        clock.finishAutomaticCapture(at:clearedAt,now:clearedAt);stamps=[];pump(0.35)
        check(clock.running && stamps.count>=2 && clock.engine.white.remaining<captureBalance,"Capture completion did not rearm the scheduler")
        clock.pause()

        clock.configure(.init(kind:.absolute,mainSeconds:1),blackToPlay:true)
        var timeouts=0;clock.onTimeout={timeouts+=1}
        clock.resume();pump(1.35)
        check(clock.engine.expiredBlack==true && timeouts==1,"Scheduled expiry did not stop exactly once")
        stamps=[];pump(0.35)
        check(stamps.isEmpty && timeouts==1,"Expiry left scheduled callbacks active")
        subscription.cancel()

        // A real timer must still obey the camera-gap guard, not bill unseen time.
        clock.configure(.init(kind:.absolute,mainSeconds:60),blackToPlay:true)
        let now=ProcessInfo.processInfo.systemUptime
        clock.noteCameraObservation(at:now,now:now);clock.resume(at:now)
        pump(1.8)
        check(!clock.running && clock.observationGapHeld,"Scheduled camera-gap protection did not hold clocks")
        check(clock.engine.black.remaining==60,"Camera gap charged beyond the last verified observation")
        print("Clock scheduler tests passed (\(checks) checks)")
    }
}
