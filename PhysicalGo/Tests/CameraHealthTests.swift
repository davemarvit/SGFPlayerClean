import Foundation
import ImageIO

@main struct CameraHealthTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            count += 1; if !condition() { fatalError(message) }
        }
        var health = CameraHealth()
        check(health.check(now: 100) == .none, "Idle must never start a camera")
        health.start(now: 100)
        check(health.check(now: 107.9) == .none, "Allow startup time")
        check(health.check(now: 108) == .restart(1), "No first frame triggers recovery")
        check(health.check(now: 108.1) == .none, "No rapid retry loop")
        health.receivedFrame(now: 110)
        check(health.check(now: 114.9) == .none, "Healthy stream gets full timeout")
        check(health.check(now: 115) == .restart(2), "Midstream freeze triggers second retry")
        health.receivedFrame(now: 116)
        check(health.check(now: 121) == .failed, "Retry budget remains bounded even after brief recovery")
        check(health.check(now: 150,force:true) == .none, "Failure cannot spontaneously restart")
        health.start(now: 200)
        check(health.check(now: 200.1,force:true) == .restart(1), "Explicit new session resets retry budget")
        health.stop()
        health.receivedFrame(now: 202)
        check(health.check(now: 300,force:true) == .none, "Stop prevents late frames and notifications from restarting capture")
        health.start(now: 400)
        for t in 401...430 {
            health.receivedFrame(now:Double(t))
            check(health.check(now:Double(t)) == .none, "Fresh frames prevent false watchdog triggers")
        }
        check(health.retries == 0, "A stationary board still supplies frames without recovery")
        check(health.check(now:436) == .restart(1),"First outage after healthy operation failed")
        for t in 437...469 {health.receivedFrame(now:Double(t))}
        check(health.check(now:475) == .restart(1),"Healthy recovery did not replenish retry budget")
        check(health.check(now:484) == .restart(2),"Second uninterrupted outage retry missing")
        check(health.check(now:493) == .failed,"Unhealthy loop was not bounded")
        check(health.wake(now:500) && health.active,"Wake did not recover a requested failed camera")
        health.stop()
        check(!health.wake(now:600) && !health.active,"Wake reopened a camera the user stopped")
        var feed=CameraFeedHealth()
        let sharp=CameraFeedHealth.Sample(fingerprint:1,edgeFraction:0.3,detailEnergy:900)
        for n in 0..<8 {
            let result=feed.observe(.init(fingerprint:UInt64(n),edgeFraction:0.3,detailEnergy:900),at:Double(n)*0.2)
            check(result.usable && result.reconnectReason==nil,"A stationary board with sensor noise looked frozen")
        }
        feed=CameraFeedHealth()
        for n in 0..<8 {check(feed.observe(sharp,at:Double(n)*0.2).reconnectReason==nil,"Brief repeated buffers triggered recovery")}
        check(feed.observe(sharp,at:1.6).reconnectReason?.contains("frozen")==true,"Advancing timestamps hid repeated image data")
        feed=CameraFeedHealth()
        let blur=CameraFeedHealth.Sample(fingerprint:2,edgeFraction:0,detailEnergy:3)
        check(!feed.observe(blur,at:0).usable,"Blurred placeholder reached board recognition")
        check(feed.observe(sharp,at:0.3).reconnectReason==nil,"Transient focus change triggered recovery")
        for n in 0..<4 {check(feed.observe(blur,at:1+Double(n)*0.2).reconnectReason==nil,"Blur debounce ended early")}
        check(feed.observe(blur,at:1.81).reconnectReason?.contains("blurred")==true,"Sustained blur did not reconnect")
        check(feed.observe(sharp,at:5).usable,"Fresh sharp image did not clear suspicion")
        func measure(_ path:String)->CameraFeedHealth.Sample {
            let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:"PhysicalGo/"+path) as CFURL,nil)!
            return CameraFeedHealth.Sample.measure(CGImageSourceCreateImageAtIndex(source,0,nil)!)!
        }
        check(measure("Tests/Fixtures/CameraBlur/frame.png").severelyBlurred,"Recorded phone placeholder was missed")
        for name in ["ResumeAlignment/frame.png","G18RapidPlay/reference.png","G18RapidPlay/after-1.png","G18RapidPlay/middle-11.png"] {
            check(!measure("Tests/Fixtures/"+name).severelyBlurred,"Real board/reference/hand frame mistaken for a blurred feed")
        }
        print("PASS: \(count) camera startup, stall, retry-limit, cancellation and healthy-stream checks.")
    }
}
