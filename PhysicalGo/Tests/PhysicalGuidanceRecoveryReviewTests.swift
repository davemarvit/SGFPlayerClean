import Foundation

/// Independent event-sequence checks for the extracted policy. No app, IO,
/// wall clock, hardware receipt fabrication in the production adapter, or motors.
@main struct PhysicalGuidanceRecoveryReviewTests {
    typealias R=PhysicalGuidanceRecovery<String,String,String>
    static let epoch=UUID(uuidString:"11111111-1111-1111-1111-111111111111")!
    static let scope=R.Scope(schema:2,session:"game",context:"camera",epoch:epoch)
    static var checks=0
    static func check(_ condition:Bool,_ message:String) {
        checks+=1
        guard condition else {fatalError("FAIL: "+message)}
    }
    struct Rig {
        var state=R()
        var target:String?="point"
        init(target:String?="point",cause:R.Cause = .hand) {
            self.target=target
            let effect=state.reduce(.begin(scope,.init(target:target,owner:target == nil ? nil:"game"),setup:"setup",cause:cause,at:0))
            check(effect == .requestOFF,"begin requests a new OFF barrier")
        }
        mutating func observe(_ stamp:Double,now:Double?=nil,admitted:Bool=true,
                              receipt:Bool=true,setup:String="setup",off:Double=0,
                              watermark:String="one",cause:R.Cause? = .hand,
                              observedScope:R.Scope=scope,frame:Bool=true)->R.Effect {
            state.reduce(.observe(.init(scope:observedScope,target:target,enabled:admitted,cause:cause,
                receipt:receipt ? .init(scope:observedScope,setup:setup,offSince:off,watermark:watermark):nil,
                clearAt:stamp,frameAdmissible:frame,now:now ?? stamp+0.125)))
        }
        mutating func ready() {
            _=observe(0.25);_=observe(0.5);_=observe(0.75)
        }
        mutating func verify(_ stamp:Double=0.75,now:Double?=nil,clear:Double?=0.75,
                             healthy:Bool=true,frame:Bool=true)->R.Effect {
            state.reduce(.verify(.init(enabled:true,hasTarget:target != nil,capturedAt:stamp,
                clearAt:clear,healthyOFF:healthy,frameAdmissible:frame,now:now ?? stamp+0.125)))
        }
    }
    static func main() {
        for cause in R.Cause.allCases {
            var r=Rig(cause:cause)
            for stamp in [0.25,0.5,0.75] {
                check(r.observe(stamp,cause:cause) == .none,"targetful recovery stays OFF after witnesses")
            }
            check(r.state.isPending,"targetful proof waits for purpose-specific verifier")
            check(r.verify() == .recovered(at:0.75,cause:cause),"typed cause survives successful verification")
            check(!r.state.isPending,"successful verification consumes proof")
            check(r.verify() == .none,"proof cannot be consumed twice")
        }
        do {
            var r=Rig(target:nil)
            check(r.observe(0.25) == .none,"targetless first witness")
            check(r.observe(0.5) == .none,"targetless second witness")
            check(r.observe(0.75) == .recovered(at:0.75,cause:.hand),"targetless third witness recovers directly")
            check(!r.state.isPending,"targetless completion clears proof")
        }
        do {
            var r=Rig();r.ready()
            check(r.verify(0.5,clear:0.5) == .none,"earlier frame cannot consume later proof")
            check(r.verify(clear:nil) == .none,"missing camera verdict cannot consume proof")
            check(r.verify(clear:0.5) == .none,"different camera verdict cannot consume proof")
            check(r.verify(healthy:false) == .none,"unconfirmed OFF cannot consume proof")
            check(r.verify(frame:false) == .none,"unflushed frame cannot consume proof")
            check(r.verify(now:1.25) == .none,"exactly 500ms old verification is expired")
            check(r.verify(now:0.5) == .none,"future frame cannot consume proof")
            check(r.verify(now:Double.nan) == .none,"nonfinite clock cannot consume proof")
            check(r.verify() == .recovered(at:0.75,cause:.hand),"failed verification preserves eligible proof")
        }
        do {
            var r=Rig()
            _=r.observe(0.25);_=r.observe(0.5)
            _=r.observe(0.5,frame:false)
            _=r.observe(0.75)
            check(r.verify() == .recovered(at:0.75,cause:.hand),"duplicate verdict with newer queued frame preserves witnesses")
        }
        for change in ["time","watermark"] {
            var r=Rig();_=r.observe(0.25);_=r.observe(0.5)
            _=r.observe(0.5,off:change == "time" ? 0.125:0,watermark:change == "watermark" ? "two":"one",frame:false)
            _=r.observe(0.75,off:change == "time" ? 0.125:0,watermark:change == "watermark" ? "two":"one")
            check(r.verify() == .none,"changed OFF \(change) resets before duplicate shortcut")
        }
        for invalid in ["missing-receipt","wrong-setup","expired","future","nonfinite","unflushed"] {
            var r=Rig();_=r.observe(0.25);_=r.observe(0.5)
            _=r.observe(0.625,now:invalid == "expired" ? 1.125:invalid == "future" ? 0.5:invalid == "nonfinite" ? .nan:0.75,
                        receipt:invalid != "missing-receipt",setup:invalid == "wrong-setup" ? "other":"setup",frame:invalid != "unflushed")
            _=r.observe(0.75)
            check(r.verify() == .none,"\(invalid) resets previous witnesses")
            check(r.state.isPending,"\(invalid) retains recoverable operation")
            _=r.observe(1.0);_=r.observe(1.25)
            check(r.verify(1.25,clear:1.25) == .recovered(at:1.25,cause:.hand),"\(invalid) can recover from new evidence")
        }
        do {
            var r=Rig();_=r.observe(0.25);_=r.observe(0.5);_=r.observe(1.125)
            check(r.verify(1.125,clear:1.125) == .none,"gap over 600ms breaks witness continuity")
            _=r.observe(1.375);_=r.observe(1.625)
            check(r.verify(1.625,clear:1.625) == .recovered(at:1.625,cause:.hand),"new continuous witness series succeeds")
        }
        do {
            var r=Rig();_=r.observe(0.25);_=r.observe(0.375);_=r.observe(0.5)
            check(r.verify(0.5,clear:0.5) == .none,"three frames spanning less than450ms are insufficient")
            _=r.observe(0.75)
            check(r.verify() == .recovered(at:0.75,cause:.hand),"additional distinct observation earns required span")
        }
        do {
            var r=Rig();r.ready()
            let retarget=r.state.reduce(.retarget(scope,.init(target:"next",owner:"game"),cause:.hand,permitted:true,at:1))
            check(retarget == .requestOFF,"same-game new target requires new OFF")
            r.target="next"
            check(r.verify() == .none,"old proof cannot authorize new target")
            _=r.observe(1.25);_=r.observe(1.5);_=r.observe(1.75)
            check(r.verify(1.75,clear:1.75) == .recovered(at:1.75,cause:.hand),"retarget earns fresh witnesses")
        }
        do {
            var r=Rig();r.ready()
            check(r.state.reduce(.retarget(scope,.init(target:"foreign",owner:"other-game"),cause:.hand,permitted:true,at:1)) == .none,"foreign target cannot be admitted under current session owner")
            r.target="foreign"
            check(r.observe(1.25) == .scopeChanged,"unaccepted target change invalidates old recovery")
            check(!r.state.isPending,"scope violation clears transient proof")
        }
        do {
            var r=Rig();r.ready()
            check(r.state.reduce(.retarget(scope,.init(target:"next",owner:"game"),cause:.hand,permitted:false,at:1)) == .none,"hard policy gate refuses retarget")
            _=r.state.reduce(.cancel)
            check(!r.state.isPending && r.verify() == .none,"cancel makes prior evidence inert")
            check(r.observe(2) == .none,"late observation cannot restart cancelled recovery")
        }
        for changed in [R.Scope(schema:1,session:"game",context:"camera",epoch:epoch),
                        R.Scope(schema:2,session:"other-game",context:"camera",epoch:epoch),
                        R.Scope(schema:2,session:"game",context:"other-camera",epoch:epoch),
                        R.Scope(schema:2,session:"game",context:"camera",epoch:UUID())] {
            var r=Rig();r.ready()
            check(r.observe(1,observedScope:changed) == .scopeChanged,"schema/session/camera/epoch change invalidates proof")
        }
        do {
            var r=Rig();r.ready()
            check(r.observe(1,cause:nil) == .none && !r.state.isPending,"superseding nontransient disposition discards transient state")
        }
        print("PASS: \(checks) independent transient recovery checks")
    }
}
