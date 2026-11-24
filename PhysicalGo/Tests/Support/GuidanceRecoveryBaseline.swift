import Foundation

/// Frozen policy oracle adapted from c39e7e0 PhysicalLaserGuidance's transient
/// record, setTarget, advanceTransientRecovery and verifyTarget. Test-only:
/// retain the original guard/order layout independently of the new reducer.
struct GuidanceRecoveryBaseline {
    typealias R=PhysicalGuidanceRecovery<String,String,Int>
    struct State {
        let scope:R.Scope
        var operation:R.Operation
        let setup:String?
        var cause:R.Cause
        var began:Double
        var offSince:Double?
        var watermark:Int?
        var first:Double?
        var last:Double?
        var count=0
    }
    var state:State?
    var isPending:Bool {state != nil}
    mutating func reduce(_ event:R.Event)->R.Effect {
        switch event {
        case let .begin(scope,operation,setup,cause,at):
            state=State(scope:scope,operation:operation,setup:setup,cause:cause,began:at)
            return .requestOFF
        case .cancel:state=nil;return .none
        case let .retarget(scope,operation,cause,permitted,at):
            if var recovery=state,let cause,permitted,
               recovery.scope.session==scope.session,recovery.scope.context==scope.context,recovery.scope.epoch==scope.epoch {
                let owner=recovery.scope.session ?? recovery.operation.owner
                let sameGame=operation.target.map {_ in owner.map {$0==operation.owner} ?? false} ?? true
                if sameGame {
                    recovery.operation=operation;recovery.cause=cause;recovery.began=at
                    recovery.first=nil;recovery.last=nil;recovery.count=0
                    recovery.offSince=nil;recovery.watermark=nil;state=recovery
                    return .requestOFF
                }
            }
            return .none
        case let .observe(o):
            guard var recovery=state else {return .none}
            guard o.enabled,o.scope.schema==recovery.scope.schema,o.scope.session==recovery.scope.session,
                  o.target==recovery.operation.target,o.scope.context==recovery.scope.context,o.scope.epoch==recovery.scope.epoch else {
                state=nil;return .scopeChanged
            }
            guard let cause=o.cause else {state=nil;return .none}
            recovery.cause=cause
            guard let d=o.receipt,d.setup==recovery.setup,
                  recovery.scope.schema==1 || (d.scope.session==recovery.scope.session && d.scope.context==recovery.scope.context && d.scope.epoch==recovery.scope.epoch),
                  let stamp=o.clearAt,stamp>recovery.began,(0..<0.5).contains(o.now-stamp) else {
                recovery.first=nil;recovery.last=nil;recovery.count=0;state=recovery;return .none
            }
            if recovery.offSince != d.offSince || recovery.watermark != d.watermark {
                recovery.first=nil;recovery.last=nil;recovery.count=0
                recovery.offSince=d.offSince;recovery.watermark=d.watermark
            }
            if let last=recovery.last,stamp<=last {state=recovery;return .none}
            guard o.frameAdmissible else {
                recovery.first=nil;recovery.last=nil;recovery.count=0;state=recovery;return .none
            }
            if let last=recovery.last,stamp-last>0.6 {recovery.first=nil;recovery.count=0}
            if recovery.first==nil {recovery.first=stamp}
            recovery.last=stamp;recovery.count+=1
            guard recovery.count>=3,stamp-recovery.first!>=0.45 else {state=recovery;return .none}
            if recovery.operation.target != nil {state=recovery;return .none}
            state=nil;return .recovered(at:stamp,cause:cause)
        case let .verify(v):
            guard let recovery=state,v.enabled,v.hasTarget,recovery.count>=3,
                  let first=recovery.first,let last=recovery.last,last-first>=0.45,
                  abs(last-v.capturedAt)<0.000001,(0..<0.5).contains(v.now-v.capturedAt),
                  v.clearAt.map({abs($0-v.capturedAt)<0.000001})==true,v.healthyOFF,v.frameAdmissible else {return .none}
            state=nil;return .recovered(at:v.capturedAt,cause:recovery.cause)
        }
    }
}
