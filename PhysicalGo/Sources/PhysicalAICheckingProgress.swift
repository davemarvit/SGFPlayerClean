import Foundation

/// Presentation only. It neither certifies a board nor resets recognition,
/// history, clocks, calibration, or the controller's confirmation witnesses.
struct PhysicalAICheckingProgress {
    enum Reason:String {case requiredIntersections,ambiguousPlacement,stablePosition,positionMismatch}
    struct Help:Equatable {
        let reason:Reason
        let points:[Int]
        let totalPoints:Int
        let emptyGame:Bool
        func explanation(coordinate:(Int)->String)->String {
            var locations=points.map(coordinate).joined(separator:", ")
            if totalPoints>points.count {locations += " and \(totalPoints-points.count) more"}
            switch reason {
            case .requiredIntersections:
                return locations.isEmpty ? "The camera cannot yet confirm the required intersections.":"The camera cannot yet confirm \(locations)."
            case .ambiguousPlacement:
                return locations.isEmpty ? "A stone is visible, but its intersection is still unclear.":"A stone is visible, but its intersection is still unclear near \(locations)."
            case .stablePosition:
                return "The camera sees the board, but the readings have not stayed consistent long enough to continue."
            case .positionMismatch:
                return "The observed board still differs from the saved position. Check the marked places and removals."
            }
        }
        var recovery:String {
            emptyGame
                ? "Keep the board empty and hands clear. Use Camera & setup to check the view, grid and lighting. If needed, capture an empty reference only after every stone has been removed."
                : "Leave the stones in place and keep hands clear. Use Camera & setup to inspect the view, grid and lighting. For a board with stones, the existing Occupied reference controls preserve the empty reference."
        }
    }
    private var scope:String?
    private var started:Double?
    private var lastCapture:Double?
    private var freshFrames=0
    private var lastPresentation:Double?
    private(set) var help:Help?
    private(set) var followsAmbiguousPlacement=false
    mutating func reset() {self=Self()}
    mutating func observe(scope:String,reason:Reason,points:[Int],size:Int,emptyGame:Bool,
                          capturedAt:Double,now:Double)->Help? {
        guard now.isFinite,capturedAt.isFinite,now>=capturedAt,now-capturedAt<1.5,size>0 else {reset();return nil}
        if self.scope != scope {reset();self.scope=scope}
        guard lastCapture.map({capturedAt>$0}) ?? true else {return help}
        if let lastCapture,capturedAt-lastCapture>1.5 {reset();self.scope=scope}
        if reason == .ambiguousPlacement {followsAmbiguousPlacement=true}
        if started==nil {started=now}
        lastCapture=capturedAt;freshFrames+=1
        guard freshFrames>=3,now-started!>=3 else {return help}
        guard lastPresentation.map({now-$0>=1}) ?? true else {return help}
        let unique=Set(points.filter{(0..<size*size).contains($0)}).sorted()
        help=Help(reason:reason,points:Array(unique.prefix(8)),totalPoints:unique.count,emptyGame:emptyGame)
        lastPresentation=now
        return help
    }
}
