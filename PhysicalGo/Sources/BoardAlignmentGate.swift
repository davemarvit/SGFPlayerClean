import Foundation

/// Debounce absent grid evidence, never accept a stone from an unverified frame.
/// A measured large displacement or an unusable calibration bypasses the grace.
struct BoardAlignmentGate {
    private(set) var failures=0
    private var first:Double?
    private var last:Double?
    mutating func reset() {failures=0;first=nil;last=nil}
    mutating func shouldHold(report:[String:Any],now:Double,allowGrace:Bool)->Bool {
        let reason=report["rejectionReason"] as? String ?? ""
        let marginal=["no grid fit; profile error too high","no grid fit; insufficient distributed line support",
                      "tracking correction insufficient; existing profile error too high"].contains(reason)
        guard allowGrace,marginal,now.isFinite else {reset();return true}
        if let last,now<=last {return false}
        if let last,now-last>1.5 {reset()}
        if first==nil {first=now}
        last=now;failures += 1
        let duration=now-first!
        return duration>=0.9 || (failures>=3 && duration>=0.6)
    }
}
