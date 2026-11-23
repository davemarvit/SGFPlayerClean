import Foundation

/// One owner for a classified transient's OFF barrier and camera witnesses.
/// Inputs are immutable values; the facade authenticates receipts and performs IO.
struct PhysicalGuidanceRecovery<Session:Equatable,Target:Equatable,Watermark:Equatable> {
    enum Cause:String,CaseIterable {
        case hand="hand_obstructed",evidence="camera_evidence_unavailable"
        case camera="camera_frame_stale",lease="request_lease_expired"
        var recoveredReason:String {
            switch self {
            case .camera:return "fresh_after_camera_delay"
            case .lease:return "fresh_after_lease_expiry"
            default:return "fresh_after_transient"
            }
        }
    }
    struct Scope:Equatable {
        let schema:Int
        let session:Session?
        let context:String?
        let epoch:UUID?
        func sameCameraSession(as other:Self)->Bool {
            session==other.session && context==other.context && epoch==other.epoch
        }
    }
    struct Operation {
        let target:Target?
        let owner:Session?
    }
    struct Receipt {
        let scope:Scope
        let setup:String?
        let offSince:Double?
        let watermark:Watermark?
    }
    struct Observation {
        let scope:Scope
        let target:Target?
        let enabled:Bool
        let cause:Cause?
        /// Nil means no currently authenticated, healthy full-OFF receipt.
        let receipt:Receipt?
        let clearAt:Double?
        let frameAdmissible:Bool
        let now:Double
    }
    struct Verification {
        let enabled:Bool
        let hasTarget:Bool
        let capturedAt:Double
        let clearAt:Double?
        let healthyOFF:Bool
        let frameAdmissible:Bool
        let now:Double
    }
    enum Event {
        case begin(Scope,Operation,setup:String?,cause:Cause,at:Double)
        case retarget(Scope,Operation,cause:Cause?,permitted:Bool,at:Double)
        case observe(Observation)
        case verify(Verification)
        case cancel
    }
    enum Effect:Equatable {
        case none
        case requestOFF
        case scopeChanged
        case recovered(at:Double,cause:Cause)
    }
    private struct Pending {
        let scope:Scope
        var operation:Operation
        let setup:String?
        var cause:Cause
        var began:Double
        var offSince:Double?
        var watermark:Watermark?
        var first:Double?
        var last:Double?
        var count=0
        mutating func resetWitnesses() {first=nil;last=nil;count=0}
        var ready:Bool {count>=3 && first != nil && last != nil && last!-first!>=0.45}
    }
    private var pending:Pending?
    var isPending:Bool {pending != nil}

    @discardableResult mutating func reduce(_ event:Event)->Effect {
        switch event {
        case let .begin(scope,operation,setup,cause,at):
            pending=Pending(scope:scope,operation:operation,setup:setup,cause:cause,began:at)
            return .requestOFF
        case .cancel:
            pending=nil;return .none
        case let .retarget(scope,operation,cause,permitted,at):
            guard var p=pending,permitted,let cause,p.scope.sameCameraSession(as:scope),
                  operation.target==nil || (p.scope.session ?? p.operation.owner).map({$0==operation.owner})==true else {return .none}
            p.operation=operation;p.cause=cause;p.began=at
            p.resetWitnesses();p.offSince=nil;p.watermark=nil;pending=p
            return .requestOFF
        case let .observe(o):
            guard var p=pending else {return .none}
            guard o.enabled,o.scope==p.scope,o.target==p.operation.target else {
                pending=nil;return .scopeChanged
            }
            guard let cause=o.cause else {pending=nil;return .none}
            p.cause=cause
            guard let receipt=o.receipt,receipt.setup==p.setup,
                  p.scope.schema==1 || receipt.scope.sameCameraSession(as:p.scope),
                  let stamp=o.clearAt,stamp>p.began,(0..<0.5).contains(o.now-stamp) else {
                p.resetWitnesses();pending=p;return .none
            }
            if p.offSince != receipt.offSince || p.watermark != receipt.watermark {
                p.resetWitnesses();p.offSince=receipt.offSince;p.watermark=receipt.watermark
            }
            // Frame publication may precede its verdict. Duplicate analysis
            // adds no witness, but must not erase the already counted streak.
            if let last=p.last,stamp<=last {pending=p;return .none}
            guard o.frameAdmissible else {p.resetWitnesses();pending=p;return .none}
            if let last=p.last,stamp-last>0.6 {p.first=nil;p.count=0}
            if p.first==nil {p.first=stamp}
            p.last=stamp;p.count+=1;pending=p
            guard p.ready,p.operation.target==nil else {return .none}
            pending=nil;return .recovered(at:stamp,cause:p.cause)
        case let .verify(v):
            guard let p=pending,v.enabled,v.hasTarget,p.ready,let last=p.last,
                  abs(last-v.capturedAt)<0.000001,(0..<0.5).contains(v.now-v.capturedAt),
                  v.clearAt.map({abs($0-v.capturedAt)<0.000001})==true,
                  v.healthyOFF,v.frameAdmissible else {return .none}
            // Targetful recovery stays OFF until its purpose-specific verifier
            // uses this exact frame. Never publish an intermediate standby.
            pending=nil;return .recovered(at:v.capturedAt,cause:p.cause)
        }
    }
}
