import Foundation

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
        print("PASS: \(count) camera startup, stall, retry-limit, cancellation and healthy-stream checks.")
    }
}
