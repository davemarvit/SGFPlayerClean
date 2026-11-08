import Foundation

/// Time is supplied by the capture adapter, so timeout/retry behavior is testable without hardware.
struct CameraHealth {
    enum Action: Equatable { case none, restart(Int), failed }
    private(set) var active = false
    private(set) var retries = 0
    private var deadline: TimeInterval = 0
    mutating func start(now: TimeInterval) { active = true; retries = 0; deadline = now + 8 }
    mutating func receivedFrame(now: TimeInterval) { if active { deadline = now + 5 } }
    mutating func stop() { active = false }
    mutating func check(now: TimeInterval, force: Bool = false) -> Action {
        guard active, force || now >= deadline else { return .none }
        guard retries < 2 else { active = false; return .failed }
        retries += 1; deadline = now + 9 // Includes restart delay and startup allowance.
        return .restart(retries)
    }
}

enum CameraState: Equatable {
    case starting, live, recovering, failed
    var active: Bool { self != .failed }
}
