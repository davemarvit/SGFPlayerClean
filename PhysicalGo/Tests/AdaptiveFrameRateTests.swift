import Foundation

@main struct AdaptiveFrameRateTests {
    static func main() {
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;precondition(condition,message)}
        func rate(_ clock:LocalClockEngine?,_ time:Double)->Double {1/CameraProcessingCadence.interval(clock:clock,at:time)}
        for kind in LocalClockSettings.Kind.allCases where kind != .none {
            var clock=LocalClockEngine(settings:.init(kind:kind,mainSeconds:20,periodSeconds:15,periods:3,incrementSeconds:10,stonesPerPeriod:2))
            check(rate(clock,0)==5,"Paused \(kind) requested urgent processing")
            clock.resume(at:100)
            let length=kind == .simple ? 15.0:20.0
            check(rate(clock,100+length-5.001)==5,"\(kind) boosted before the last five seconds")
            check(rate(clock,100+length-5)==10,"\(kind) did not boost at exactly five seconds")
            check(rate(clock,100+length-0.01)==10,"\(kind) dropped the boost before the boundary")
            let original=clock
            _=rate(clock,100+length-1)
            check(clock==original,"Sampling advanced the actual clock")
            if [.byoyomi,.canadian].contains(kind) {
                check(rate(clock,120)==5,"\(kind) did not leave urgent mode on entering overtime")
                check(rate(clock,130)==10,"\(kind) overtime deadline was missed")
                if kind == .byoyomi {
                    check(rate(clock,135)==5,"Next byoyomi period stayed urgent")
                    check(rate(clock,145)==10,"Next byoyomi period did not boost")
                    check(rate(clock,165)==5,"Expired byoyomi clock stayed urgent")
                } else {check(rate(clock,135)==5,"Expired Canadian block stayed urgent")}
            } else {check(rate(clock,100+length)==5,"Expired \(kind) stayed urgent")}
            let moveAt=100+length-1
            check(clock.move(black:true,at:moveAt),"Could not switch players in \(kind)")
            check(rate(clock,moveAt)==5,"Rate followed the previous player in \(kind)")
            clock.pause(at:moveAt)
            check(rate(clock,moveAt+100)==5,"Paused clock snapshot continued ticking")
        }
        var short=LocalClockEngine(settings:.init(kind:.byoyomi,mainSeconds:0,periodSeconds:5,periods:3))
        short.resume(at:0)
        check(rate(short,0)==10 && rate(short,5)==10,"Short byoyomi periods should remain urgent throughout")
        check(rate(nil,0)==5 && rate(LocalClockEngine(),0)==5,"Disabled/local-clock-free capture should use normal cadence")
        check(rate(short,.nan)==5,"Nonfinite time entered urgent mode")

        // A slightly jittered 30 fps source should yield the requested cadence,
        // not lose one whole source frame after each sampling deadline.
        for interval in [0.2,0.1] {
            var cadence=CameraProcessingCadence(),accepted=[Double]()
            for i in 0..<300 {
                let t=Double(i)/30+(i%2==0 ? 0.001:0)
                if cadence.accept(at:t,interval:interval) {accepted.append(t)}
            }
            check(accepted.count==Int(10/interval),"Jitter reduced the requested \(1/interval) fps rate: \(accepted.count)")
            check(zip(accepted,accepted.dropFirst()).allSatisfy{$1>$0},"Cadence delivered duplicate times")
        }
        var cadence=CameraProcessingCadence()
        check(cadence.accept(at:0,interval:0.2),"First frame was withheld")
        check(!cadence.accept(at:0.09,interval:0.1),"Boost created an immediate duplicate frame")
        check(cadence.accept(at:0.1,interval:0.1),"Boost waited for the old 5 fps deadline")
        check(!cadence.accept(at:0.2,interval:0.2),"Normal mode retained the urgent schedule")
        check(cadence.accept(at:0.3,interval:0.2),"Normal cadence did not resume")
        check(!cadence.accept(at:0.3,interval:0.2),"Duplicate source timestamp accepted")
        check(!cadence.accept(at:0.2,interval:0.2),"Backward timestamp accepted")
        check(!cadence.accept(at:.infinity,interval:0.1),"Nonfinite timestamp accepted")
        check(cadence.accept(at:20.31,interval:0.1),"Late frame was lost")
        check(!cadence.accept(at:20.32,interval:0.1),"Missed frames were replayed as a catch-up burst")
        print("PASS: \(checks) adaptive camera cadence and clock-boundary checks")
    }
}
