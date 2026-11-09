import Foundation

/// Time is supplied by the capture adapter, so timeout/retry behavior is testable without hardware.
struct CameraHealth {
    enum Action: Equatable { case none, restart(Int), failed }
    private(set) var active = false
    private(set) var requested = false
    private(set) var retries = 0
    private var deadline: TimeInterval = 0
    private var healthySince:TimeInterval?
    private var lastFrame:TimeInterval?
    mutating func start(now: TimeInterval) { requested=true;active = true; retries = 0; deadline = now + 8;healthySince=nil;lastFrame=nil }
    mutating func receivedFrame(now: TimeInterval) {
        guard active,now.isFinite,lastFrame.map({now>$0}) ?? true else {return}
        if lastFrame.map({now-$0>5}) ?? true {healthySince=now}
        lastFrame=now;deadline=now+5
        if let healthySince,now-healthySince>=30 {retries=0}
    }
    mutating func stop() { active = false;requested=false;healthySince=nil;lastFrame=nil }
    mutating func failed() {active=false;healthySince=nil;lastFrame=nil}
    mutating func wake(now:TimeInterval)->Bool {
        guard requested else {return false}
        start(now:now);return true
    }
    mutating func check(now: TimeInterval, force: Bool = false) -> Action {
        guard active, force || now >= deadline else { return .none }
        guard retries < 2 else { active = false; return .failed }
        healthySince=nil;lastFrame=nil
        retries += 1; deadline = now + 9 // Includes restart delay and startup allowance.
        return .restart(retries)
    }
}

enum CameraState: Equatable {
    case starting, live, recovering, failed
    var active: Bool { self != .failed }
}
