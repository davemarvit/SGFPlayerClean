import Foundation

/// Screen-only diagnostic output cannot accept a move or change clocks.
/// The caller supplies raw, positive observations; retained history is not evidence.
enum PhysicalIllegalMoveWarning {
    struct Candidate: Equatable {
        let point: Int
        let color: Stone
        let rejection: SGFPlayer.MoveRejection
        let restorePoints: [Int]
    }

    struct Evidence {
        let frameID: String
        let capturedAt: Double
        let cells: [String?]
        let confidence: [Double]
        let ambiguous: Set<Int>
        let hand: Bool?
        let aligned: Bool
        let confirmedDark: Bool
    }

    /// `context` identifies the exact game/history/rules revision. It must change
    /// after resume, undo, rule/camera/stream change or replacement game.
    struct Tracker {
        private var context: String?
        private var candidate: Candidate?
        private var first = 0.0
        private var last = 0.0
        private var lastFrame: String?
        private var count = 0

        mutating func clear() {
            context=nil;candidate=nil;lastFrame=nil;count=0
        }

        mutating func observe(player: SGFPlayer, context: String,
                              human: Stone, acceptsHumanAttempt: Bool,
                              pendingAIPlacement: Bool, evidence: Evidence, now: Double,
                              permitsReply: (Int)->Bool) -> Candidate? {
            guard acceptsHumanAttempt,!pendingAIPlacement,!context.isEmpty,
                  player.currentIndex==player.maxIndex,player.turn==human,
                  evidence.capturedAt.isFinite,now.isFinite,now>=evidence.capturedAt,
                  now-evidence.capturedAt<0.7,evidence.hand==false,evidence.aligned,
                  evidence.confirmedDark,!evidence.frameID.isEmpty,
                  let next=Self.classify(player:player,human:human,evidence:evidence,permitsReply:permitsReply)
            else {clear();return nil}
            guard lastFrame != evidence.frameID else {return nil}
            let same = self.context==context && candidate==next && evidence.capturedAt>last && evidence.capturedAt-last<=0.6
            if same {count+=1}
            else {self.context=context;candidate=next;first=evidence.capturedAt;count=1}
            last=evidence.capturedAt;lastFrame=evidence.frameID
            return count>=3 && last-first>=0.45 ? next:nil
        }

        private static func classify(player: SGFPlayer,human: Stone,evidence: Evidence,
                                     permitsReply: (Int)->Bool) -> Candidate? {
            let size=player.board.size
            guard [9,13,19].contains(size),player.analysisSettings.playRules != nil,
                  evidence.cells.count==size*size,evidence.confidence.count==size*size,
                  evidence.ambiguous.isEmpty else {return nil}
            var observed=[String]()
            for i in evidence.cells.indices {
                guard let cell=evidence.cells[i],["empty","black","white"].contains(cell),
                      evidence.confidence[i].isFinite,evidence.confidence[i]>=0.8 else {return nil}
                observed.append(cell)
            }
            let before=player.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"}
            let additions=before.indices.filter{before[$0]=="empty" && observed[$0]==human.rawValue}
            guard additions.count==1,let point=additions.first,evidence.confidence[point]>=0.9,
                  permitsReply(point),let reason=player.moveRejection(color:human,x:point%size,y:point/size),
                  [.suicide,.ko,.superko].contains(reason) else {return nil}

            // Simulate on a private engine to identify affected groups using the
            // same placement code as replay/legality. Never mutate live history.
            let trial=SGFPlayer();trial.restoreSnapshot(player.createSnapshot())
            trial.playMoveOptimistically(color:human,x:point%size,y:point/size)
            let after=trial.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"}
            var restore=[Int]()
            for i in before.indices {
                if i==point {continue} // the illegal stone itself must be present
                if before[i]==human.opponent.rawValue && after[i]=="empty" {
                    guard observed[i]==before[i] || observed[i]=="empty" else {return nil}
                    if observed[i]=="empty" {restore.append(i)}
                } else {
                    // For self-capture diagnostics, require pre-existing own
                    // stones to remain. Partial self-removal needs synchronization.
                    guard observed[i]==before[i] else {return nil}
                }
            }
            return .init(point:point,color:human,rejection:reason,restorePoints:restore)
        }
    }
}
