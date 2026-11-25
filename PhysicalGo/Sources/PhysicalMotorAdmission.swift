import Foundation

/// Pure bookkeeping for one possible motor session. Receipt authentication,
/// hardware commands and game-clock authority remain in the guidance facade.
/// Cold admission and warm handoff are independent deadlines, not a lease.
struct PhysicalMotorAdmission {
    private enum Power {case released,possible}
    private enum Deadline {
        case idle,waiting(since:Double)
        var since:Double? {if case let .waiting(since)=self {return since};return nil}
        mutating func beginIfNeeded(_ now:Double) {if since==nil {self = .waiting(since:now)}}
    }
    private var power=Power.released
    private var cold=Deadline.idle
    private var handoff=Deadline.idle
    var mayHaveMotorSession:Bool {power == .possible}
    var armingStartedAt:Double? {cold.since}
    var transitionStartedAt:Double? {handoff.since}

    enum Event {
        case motorRequest(at:Double)
        case authenticatedArming(at:Double)
        case authenticatedActive
        case authenticatedTransition(at:Double)
        case authenticatedNonTransition
        case confirmedFullOFF
        case playSessionChanged
        /// Matches existing disabled-camera/shutdown bookkeeping. It asserts
        /// no new receipt and deliberately does not reset unrelated deadlines.
        case releasePossibleSession
    }
    mutating func reduce(_ event:Event) {
        switch event {
        case let .motorRequest(now):
            if !mayHaveMotorSession {cold = .waiting(since:now)}
            power = .possible
        case let .authenticatedArming(now):cold.beginIfNeeded(now)
        case .authenticatedActive:cold = .idle
        case let .authenticatedTransition(now):handoff.beginIfNeeded(now)
        case .authenticatedNonTransition,.playSessionChanged:handoff = .idle
        case .confirmedFullOFF:power = .released;cold = .idle;handoff = .idle
        case .releasePossibleSession:power = .released
        }
    }
    func armingTimedOut(now:Double,transientRecovery:Bool)->Bool {
        !transientRecovery && mayHaveMotorSession && cold.since.map {now-$0>=12}==true
    }
    func transitionTimedOut(now:Double)->Bool {handoff.since.map {now-$0>=3}==true}

    /// Ordered reasons for the existing schema-2 admission conjunction. This
    /// is a diagnostic of current inputs, never a second source of authority.
    enum Blocker:Equatable {
        case notRequested,transientRecovery,gameRecheck,controllerReset,closing
        case awaitingFullOFF,statusUnavailable,standbyFault(String),cameraStale,targetScope
        var code:String {
            switch self {
            case .notRequested:return "not_requested"
            case .transientRecovery:return "transient_recovery"
            case .gameRecheck:return "game_recheck"
            case .controllerReset:return "controller_reset"
            case .closing:return "closing_standby"
            case .awaitingFullOFF:return "awaiting_full_off"
            case .statusUnavailable:return "standby_status_unavailable"
            case let .standbyFault(reason):return "standby_fault:"+reason
            case .cameraStale:return "camera_stale"
            case .targetScope:return "target_scope_changed"
            }
        }
    }
    struct Inputs {
        let requested:Bool,transientRecovery:Bool,gameRecheck:Bool,controllerReset:Bool
        let closing:Bool,ready:Bool,available:Bool
        let fault:String?
        let cameraFresh:Bool,matchedTarget:Bool
    }
    static func blocker(_ i:Inputs)->Blocker? {
        if !i.requested {return .notRequested}
        if i.transientRecovery {return .transientRecovery}
        if i.gameRecheck {return .gameRecheck}
        if i.controllerReset {return .controllerReset}
        if i.closing {return .closing}
        if !i.ready {return .awaitingFullOFF}
        if !i.available {return .statusUnavailable}
        if let fault=i.fault {return .standbyFault(fault)}
        if !i.cameraFresh {return .cameraStale}
        if !i.matchedTarget {return .targetScope}
        return nil
    }
}
