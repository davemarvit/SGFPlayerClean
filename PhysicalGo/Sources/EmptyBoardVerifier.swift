import Foundation

/// An empty-board hypothesis needs positive evidence at every intersection and
/// multiple fresh, steady live frames. UI redraws and frozen photos do not count.
struct EmptyBoardVerifier {
    private var frames=0
    private var started:TimeInterval?
    mutating func reset() { frames=0; started=nil }
    mutating func observe(_ observation:BoardObservation,isFresh:Bool,now:TimeInterval)->Bool {
        guard observation.readings.count==observation.size*observation.size,
              observation.readings.allSatisfy({ $0.occupancy == .empty && $0.confidence>=0.75 }) else { reset(); return false }
        guard isFresh else { return false }
        if started==nil { started=now }
        frames += 1
        return frames>=5 && now-started!>=1
    }
}
