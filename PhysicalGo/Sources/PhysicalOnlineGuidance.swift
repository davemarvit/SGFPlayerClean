import Foundation

/// Authoritative online intent only. This producer never commands the pointer,
/// acknowledges a move, or changes server clocks. Camera/lease/hand admission is
/// a separate integration requirement before a consumer may dispatch this intent.
struct PhysicalOnlineGuidance {
    struct Target: Equatable {
        let session: UUID
        /// Local operation generation, not an OGS move number or clock event.
        let generation: Int
        let size: Int
        /// Server/display orientation, not raw camera coordinates.
        let point: Int
        let black: Bool
        let decisionReceivedAtUnix: Double
    }
    private var context = ""
    private var session = UUID()
    private var generation = 0
    private var board = [String]()
    private var lastPoint: Int?
    private var pending: Target?
    private var myTurn = false
    private var publishedAtUnix = 0.0

    mutating func invalidate() { self = Self() }
    mutating func cancel() { pending=nil }

    /// Caller has validated a fresh, ready SGF Player snapshot. Tokens remain
    /// internal context; exported target identity uses a fresh opaque UUID.
    mutating func update(context: String, board next: [String], size: Int,
                         ownColor: String, myTurn: Bool, lastPoint: Int?,
                         previouslySynchronized: Bool, publishedAtUnix: Double,
                         receivedAtUnix: Double) {
        if self.context != context || (!board.isEmpty &&
            (publishedAtUnix<self.publishedAtUnix || receivedAtUnix-self.publishedAtUnix>=2)) {
            invalidate();self.context=context
        }
        defer {
            board=next;self.lastPoint=lastPoint;self.myTurn=myTurn
            self.publishedAtUnix=publishedAtUnix
        }
        guard [9,13,19].contains(size),next.count==size*size,
              ["black","white"].contains(ownColor),
              publishedAtUnix.isFinite, receivedAtUnix.isFinite,
              receivedAtUnix>=publishedAtUnix, receivedAtUnix-publishedAtUnix<2 else {
            pending=nil;return
        }
        if next == board {
            // Board and turn may arrive separately. Retain a proven board-first
            // transition until its turn arrives, but never resurrect a retired one.
            if self.lastPoint != lastPoint { pending=nil }
            return
        }
        pending=nil
        let opponent=ownColor == "black" ? "white":"black"
        guard previouslySynchronized, board.count==next.count,
              let point=lastPoint, next.indices.contains(point), next[point]==opponent,
              PhysicalMoveInference.position(after:point,board:board,size:size,color:opponent)==next else {return}
        generation += 1
        pending=Target(session:session,generation:generation,size:size,point:point,
                       black:opponent=="black",decisionReceivedAtUnix:receivedAtUnix)
    }
    /// A clock tick or camera gap cannot extend the upstream snapshot's lifetime.
    func target(atUnix now:Double) -> Target? {
        guard myTurn,now.isFinite,now>=publishedAtUnix,now-publishedAtUnix<2 else {return nil}
        return pending
    }
    mutating func observe(_ readings:[String], confidence:[Double], ambiguous:Set<Int>) {
        guard let pending,readings.indices.contains(pending.point),confidence.indices.contains(pending.point),
              readings[pending.point] == (pending.black ? "black":"white"),
              confidence[pending.point]>=0.8,!ambiguous.contains(pending.point) else {return}
        self.pending=nil
    }
}
