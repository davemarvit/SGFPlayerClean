import Foundation

@main struct PhysicalMotorAdmissionTests {
    typealias Admission=PhysicalMotorAdmission
    // Frozen pre-extraction assignments from installed1f6fb91. The facade's
    // authentication and ordering stay covered by the real guidance suites.
    struct Baseline {
        var possible=false,arming:Double?,transition:Double?
        mutating func apply(_ event:Admission.Event) {
            switch event {
            case let .motorRequest(now):if !possible {arming=now};possible=true
            case let .authenticatedArming(now):if arming==nil {arming=now}
            case .authenticatedActive:arming=nil
            case let .authenticatedTransition(now):if transition==nil {transition=now}
            case .authenticatedNonTransition,.playSessionChanged:transition=nil
            case .confirmedFullOFF:possible=false;arming=nil;transition=nil
            case .releasePossibleSession:possible=false
            }
        }
    }
    static func main() {
        var checks=0
        func check(_ condition:Bool,_ why:String) {precondition(condition,why);checks+=1}
        func event(_ value:Int,_ time:Double)->Admission.Event {
            switch value {
            case 0:return .motorRequest(at:time)
            case 1:return .authenticatedArming(at:time)
            case 2:return .authenticatedActive
            case 3:return .authenticatedTransition(at:time)
            case 4:return .authenticatedNonTransition
            case 5:return .confirmedFullOFF
            case 6:return .playSessionChanged
            default:return .releasePossibleSession
            }
        }
        // Exhaust all four-event orderings, including late arming, handoff,
        // explicit suspension, repeated requests and OFF/release distinctions.
        for sequence in 0..<4096 {
            var legacy=Baseline(),candidate=Admission(),digits=sequence
            for now in [100.0,103.0,112.0,124.0] {
                let e=event(digits%8,now);digits/=8;legacy.apply(e);candidate.reduce(e)
                check(candidate.mayHaveMotorSession==legacy.possible && candidate.armingStartedAt==legacy.arming && candidate.transitionStartedAt==legacy.transition,"Episode parity at sequence \(sequence)")
                for age in [0.0,2.999,3,11.999,12,30] {
                    for transient in [false,true] {
                        let timedOut = !transient && legacy.possible && legacy.arming.map {now+age-$0>=12}==true
                        check(candidate.armingTimedOut(now:now+age,transientRecovery:transient)==timedOut,"Cold deadline parity")
                    }
                    check(candidate.transitionTimedOut(now:now+age)==(legacy.transition.map {now+age-$0>=3}==true),"Handoff deadline parity")
                }
            }
        }
        // Exact conjunction parity for every combination of the ten original
        // admission gates. Explanations must never turn denial into permission.
        for bits in 0..<1024 {
            func bit(_ n:Int)->Bool {bits & (1<<n) != 0}
            let i=Admission.Inputs(requested:bit(0),transientRecovery:bit(1),gameRecheck:bit(2),controllerReset:bit(3),closing:bit(4),ready:bit(5),available:bit(6),fault:bit(7) ? "driver_link_lost":nil,cameraFresh:bit(8),matchedTarget:bit(9))
            let admitted=i.requested && !i.transientRecovery && !i.gameRecheck && !i.controllerReset && !i.closing && i.ready && i.available && i.fault==nil && i.cameraFresh && i.matchedTarget
            check((Admission.blocker(i)==nil)==admitted,"Blocker preserves original admission conjunction")
        }
        let clear=Admission.Inputs(requested:true,transientRecovery:false,gameRecheck:false,controllerReset:false,closing:false,ready:true,available:true,fault:nil,cameraFresh:true,matchedTarget:true)
        check(Admission.blocker(clear)==nil,"Healthy admission has no blocker")
        var r=Admission();r.reduce(.motorRequest(at:100));r.reduce(.authenticatedTransition(at:101))
        r.reduce(.playSessionChanged)
        check(r.armingStartedAt==100 && r.transitionStartedAt==nil && r.mayHaveMotorSession,"Pause/session change does not manufacture motor release or restart cold deadline")
        check(r.armingTimedOut(now:112,transientRecovery:false),"Existing timeout-before-OFF order remains observable")
        r.reduce(.confirmedFullOFF)
        check(!r.mayHaveMotorSession && !r.armingTimedOut(now:200,transientRecovery:false),"Consumed actual OFF resets the old episode")
        r.reduce(.motorRequest(at:200));r.reduce(.authenticatedActive)
        check(r.mayHaveMotorSession && !r.armingTimedOut(now:1000,transientRecovery:false),"Healthy active session no longer carries a cold-admission timer")
        r.reduce(.authenticatedArming(at:1000))
        check(!r.armingTimedOut(now:1011.999,transientRecovery:false) && r.armingTimedOut(now:1012,transientRecovery:false),"Later cold rearming receives exactly its own12s bound")
        print("PASS:4096 episode sequences,1024 gate combinations and scoped deadline/reset cases (\(checks) assertions)")
    }
}
