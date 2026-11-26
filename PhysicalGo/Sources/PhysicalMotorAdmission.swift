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
    /// A causal thermal sample proves monitor liveness, not completion of GA.
    /// The facade supplies this only from current matched dark arming status.
    struct Monitor:Equatable {
        let session:String,generation:Int,epoch:Int,sequence:Int
        let acquiredAfter:Double
        var valid:Bool {
            session.count==8 && session.allSatisfy {"0123456789ABCDEF".contains($0)} &&
            (1...0xffffffff).contains(generation) && (1...0xffffffff).contains(epoch) &&
            (1...9_999_999).contains(sequence) && acquiredAfter.isFinite
        }
        func sameController(_ other:Monitor)->Bool {
            session==other.session && generation==other.generation && epoch==other.epoch
        }
    }
    private var lastMonitor:Monitor?
    private var monitorAdvancedAt:Double?
    private var monitorRejected=false
    private mutating func resetMonitor() {
        lastMonitor=nil;monitorAdvancedAt=nil;monitorRejected=false
    }
    /// No new episode or deadline can be created here. Replayed, regressing or
    /// changed-controller samples never qualify for the provisional grace.
    mutating func observeMonitor(_ sample:Monitor?,now:Double) {
        guard let since=cold.since,let sample,sample.valid,now.isFinite,
              sample.acquiredAfter>=since,sample.acquiredAfter<=now,
              now-sample.acquiredAfter<=0.75,!monitorRejected else {return}
        if let previous=lastMonitor {
            guard sample.sameController(previous),sample.sequence>=previous.sequence else {monitorRejected=true;return}
            if sample.sequence==previous.sequence {return}
            if sample.sequence>previous.sequence {
                // An advancing sequence with an unchanged causal lower bound
                // is not new monitor evidence.
                guard sample.acquiredAfter>previous.acquiredAfter else {monitorRejected=true;return}
                monitorAdvancedAt=now
            }
        }
        lastMonitor=sample
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
            if !mayHaveMotorSession {cold = .waiting(since:now);resetMonitor()}
            power = .possible
        case let .authenticatedArming(now):
            if cold.since==nil {resetMonitor()};cold.beginIfNeeded(now)
        case .authenticatedActive:cold = .idle;resetMonitor()
        case let .authenticatedTransition(now):handoff.beginIfNeeded(now)
        case .authenticatedNonTransition,.playSessionChanged:handoff = .idle
        case .confirmedFullOFF:power = .released;cold = .idle;handoff = .idle;resetMonitor()
        case .releasePossibleSession:power = .released
        }
    }
    func armingTimedOut(now:Double,transientRecovery:Bool,currentMonitor:Monitor?=nil)->Bool {
        guard !transientRecovery,mayHaveMotorSession,let since=cold.since else {return false}
        //12s remains the default.16s is a provisional outer coordination
        // envelope over the firmware's unchanged12s engagement bound. Only
        // live, causally advancing dark monitoring earns it; no timer resets.
        let sameSample = currentMonitor.flatMap {current in lastMonitor.map {
            current.valid && current.sameController($0) && current.sequence==$0.sequence
        }} == true
        let grace = !monitorRejected && sameSample &&
            monitorAdvancedAt.map {now >= $0 && now-$0<=0.75}==true &&
            currentMonitor.map {now >= $0.acquiredAfter && now-$0.acquiredAfter<=0.75}==true
        return now-since >= (grace ? 16:12)
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
