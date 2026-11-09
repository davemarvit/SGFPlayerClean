import Foundation

/// Debounce absent grid evidence, never accept a stone from an unverified frame.
/// A measured large displacement or an unusable calibration bypasses the grace.
struct BoardAlignmentGate {
    /// Remaining distributed landmarks plus localized missing rails suggest an
    /// obstruction, not a positively measured camera shift. This only changes
    /// recovery timing; it never authorizes use of an unverified frame.
    static func likelyObstruction(_ report:[String:Any])->Bool {
        guard report["rejectionReason"] as? String != "fitted grid moved at least 0.4 intersections",
              let fraction=report["knownStoneFraction"] as? Double,fraction>=0.6,
              let matched=report["knownStoneMatches"] as? Int,matched>=4,
              report["knownStonesDistributed"] as? Bool == true,
              let support=report["initialSupport"] as? [String:Any],
              let borders=support["borderMatches"] as? [Int],borders.count==4 else {return false}
        return borders.contains{$0<3} && borders.filter{$0>=3}.count>=2
    }
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
