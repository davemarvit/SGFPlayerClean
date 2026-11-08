import Foundation

@MainActor enum ObservationHistoryTests {
    static func run() throws -> Int {
        var checks=0,time=0.0
        func check(_ ok:Bool,_ message:String) { checks += 1;if !ok {fatalError(message)} }
        func observation(_ board:BoardSnapshot,_ overrides:[Int:Occupancy]=[:])->BoardObservation {
            BoardObservation(readings:(0..<board.size*board.size).map { i in
                let stone=board.grid[i/board.size][i%board.size]
                return IntersectionReading(row:i/board.size,col:i%board.size,occupancy:overrides[i] ?? (stone == .black ? .black : stone == .white ? .white : .empty),confidence:1,delta:0)
            },size:board.size)
        }
        func feed(_ r:GameRecorder,_ board:BoardSnapshot,_ frames:Int=1,_ overrides:[Int:Occupancy]=[:]) {
            for _ in 0..<frames {time += 0.21;r.consume(observation(board,overrides),now:time)}
        }
        func recorder()->GameRecorder {
            let r=GameRecorder(storage:nil);r.start(size:9);feed(r,r.positions[0],5);return r
        }
        func sequence(_ r:GameRecorder,_ points:[BoardPosition])->[BoardSnapshot] {
            let engine=SGFPlayer();engine.load(game:r.game);engine.seek(to:r.moveCount)
            return points.map {p in
                check(engine.tryPlayMove(color:engine.turn,x:p.col,y:p.row)==nil,"Invalid history fixture move")
                return engine.board
            }
        }
        let points=[BoardPosition(7,7),BoardPosition(1,1),BoardPosition(6,6),BoardPosition(2,2),BoardPosition(5,5),BoardPosition(3,3)]
        let fast=recorder(),views=sequence(fast,points)
        var callbacks=[Int]();fast.onMoveAccepted={n,_ in callbacks.append(n)}
        for i in views.indices {
            feed(fast,views[i],2)
            if i==2 {check(fast.moveCount>0 && fast.pendingMoveCount>0,"Rapid play did not save a confirmed prefix while later moves were pending")}
        }
        feed(fast,views.last!,5)
        check(fast.moveCount==6 && callbacks==Array(1...6),"Rapid six-move sequence stalled, reordered, or repeated callbacks")
        check(Array(fast.positions.dropFirst())==views,"Rapid sequence lost an intermediate review board")
        let export=SGFGame.from(tree:try SGFParser.parse(text:fast.sgf()))
        check(export.moves.enumerated().allSatisfy{$0.element.1?.0==points[$0.offset].col && $0.element.1?.1==points[$0.offset].row},"Rapid sequence SGF changed coordinates")
        fast.seek(2);check(fast.reviewedBoard==views[1],"Cannot review a rapidly recorded intermediate position")

        let hand=recorder(),handViews=sequence(hand,Array(points.prefix(2)))
        let covered=Dictionary(uniqueKeysWithValues:(20..<45).map{($0,Occupancy.uncertain)})
        feed(hand,handViews[0],3)
        feed(hand,handViews[0],4,covered)
        check(hand.moveCount==0 && hand.pendingMoveCount==1,"Hand either committed or erased a tentative move")
        feed(hand,handViews[1],2)
        check(hand.moveCount==1 && hand.pendingMoveCount==1 && !hand.canPass,"Earlier evidence was discarded when the opponent played")
        check(try SGFGame.from(tree:SGFParser.parse(text:hand.sgf())).moves.count==1,"Unconfirmed tail leaked into SGF")
        feed(hand,handViews[1],3)
        check(hand.moveCount==2 && hand.pendingMoveCount==0,"Unconfirmed tail could not finish")

        let local=recorder(),localViews=sequence(local,Array(points.prefix(2)))
        feed(local,localViews[0],3);local.suspendVision("Brief local alignment loss",preserveObservations:true)
        feed(local,localViews[1])
        check(local.moveCount==0,"Local recovery accepted history after only one fresh frame")
        feed(local,localViews[1]);check(local.moveCount==1,"Verified local recovery discarded earlier chronological evidence")
        feed(local,localViews[1],6);check(local.moveCount==2,"Local recovery lost the opponent's move")

        let reset=recorder(),resetViews=sequence(reset,Array(points.prefix(3)))
        feed(reset,resetViews[0],2);reset.suspendVision("New grid or camera")
        feed(reset,resetViews[2],12)
        check(reset.moveCount==0 && reset.pendingMoveCount==0,"Camera/grid change reused old coordinate evidence")
        let paused=recorder(),pausedViews=sequence(paused,Array(points.prefix(3)))
        feed(paused,pausedViews[0],2);paused.pause();paused.resume();feed(paused,pausedViews[2],12)
        check(paused.moveCount==3,"Pause discarded supported chronology instead of freshly verifying it on resume")

        let expired=recorder(),expiredViews=sequence(expired,Array(points.prefix(3)))
        feed(expired,expiredViews[0],2);feed(expired,expiredViews[0],60,covered)
        feed(expired,expiredViews[2],12)
        check(expired.moveCount==3,"Repeatedly witnessed chronology was lost when the raw frame window expired")
        let ambiguous=recorder(),ambiguousViews=sequence(ambiguous,Array(points.prefix(3)))
        feed(ambiguous,ambiguousViews[2],20)
        check(ambiguous.moveCount==0 && (ambiguous.needsAttention || ambiguous.hasUnfinishedReviews),"Three simultaneous additions invented chronological order")
        let flash=recorder(),flashViews=sequence(flash,Array(points.prefix(3)))
        feed(flash,flashViews[0]);feed(flash,flashViews[2],12)
        check(flash.moveCount==0,"One-frame evidence determined a three-move order")
        let contradiction=recorder(),contradictionViews=sequence(contradiction,Array(points.prefix(3)))
        feed(contradiction,contradictionViews[0],2);feed(contradiction,contradiction.positions[0])
        feed(contradiction,contradictionViews[2],12)
        check(contradiction.moveCount==0,"An observed empty board did not invalidate a vanished candidate")

        // White is directly observed at a one-liberty point, then captured by
        // Black before White reaches the ordinary five-frame confirmation.
        func captureRecorder()->GameRecorder {
            let r=recorder()
            let setup=[BoardPosition(0,1),BoardPosition(8,8),BoardPosition(1,0),BoardPosition(8,7),BoardPosition(2,1)]
            for board in sequence(r,setup) {feed(r,board,5)}
            check(r.moveCount==5,"Rapid-capture fixture setup failed")
            return r
        }
        let capture=captureRecorder(),captureViews=sequence(capture,[BoardPosition(1,1),BoardPosition(1,2)])
        feed(capture,captureViews[0],2);feed(capture,captureViews[1],4)
        check(capture.moveCount==5,"Rapid capture accepted before its capturing move was confirmed")
        feed(capture,captureViews[1])
        check(capture.moveCount==7 && capture.positions[6]==captureViews[0] && capture.positions[7]==captureViews[1],"Rapid capture lost the directly observed short-lived stone")
        let unseen=captureRecorder(),unseenViews=sequence(unseen,[BoardPosition(1,1),BoardPosition(1,2)])
        feed(unseen,unseenViews[1],12)
        check(unseen.moveCount==5,"Inferred an unseen captured move or pass")
        let captureFlash=captureRecorder(),captureFlashViews=sequence(captureFlash,[BoardPosition(1,1),BoardPosition(1,2)])
        feed(captureFlash,captureFlashViews[0]);feed(captureFlash,captureFlashViews[1],12)
        check(captureFlash.moveCount==5,"One-frame ghost became a captured move")

        let hiddenEarlier=recorder(),hiddenViews=sequence(hiddenEarlier,Array(points.prefix(3)))
        feed(hiddenEarlier,hiddenViews[0],2)
        let hiddenPoints=[7*9+7:Occupancy.uncertain,1*9+1:Occupancy.uncertain]
        feed(hiddenEarlier,hiddenViews[2],8,hiddenPoints)
        check(hiddenEarlier.moveCount==0,"A later Black stone replaced an obscured earlier Black stone in the history")
        feed(hiddenEarlier,hiddenViews[2],8)
        check(hiddenEarlier.moveCount==3 && hiddenEarlier.positions[1]==hiddenViews[0],"Earlier hidden chronology was lost once all three stones became visible")
        let hiddenOnly=recorder(),hiddenOnlyViews=sequence(hiddenOnly,Array(points.prefix(3)))
        feed(hiddenOnly,hiddenOnlyViews[0],2)
        feed(hiddenOnly,hiddenOnlyViews[0],4,[7*9+7:.uncertain])
        check(hiddenOnly.moveCount==0 && hiddenOnly.pendingMoveCount==1 && !hiddenOnly.canPass,"An uncertain tentative stone was mistaken for a return to the empty board")
        feed(hiddenOnly,hiddenOnlyViews[2],8)
        check(hiddenOnly.moveCount==3 && hiddenOnly.positions[1]==hiddenOnlyViews[0],"A locally obscured first stone lost its chronology")
        let aged=recorder(),agedViews=sequence(aged,Array(points.prefix(3)))
        feed(aged,agedViews[0],2);feed(aged,agedViews[2],65,hiddenPoints)
        check(aged.moveCount==0,"Expired chronology silently reordered a later same-color stone")
        let repeated=recorder(),repeatedViews=sequence(repeated,Array(points.prefix(2)))
        feed(repeated,repeatedViews[0],3)
        repeated.suspendVision("Local loss",preserveObservations:true)
        for _ in 0..<20 {repeated.consume(observation(repeatedViews[0]),now:time)}
        check(repeated.moveCount==0,"Duplicate timestamps after local interruption confirmed a move")
        feed(repeated,repeatedViews[1],8)
        check(repeated.moveCount==2,"Fresh frames could not recover after ignored duplicates")

        let missing=recorder(),missingViews=sequence(missing,Array(points.prefix(3)))
        feed(missing,missingViews[0],5);feed(missing,missingViews[1],3)
        feed(missing,missingViews[2],12,[7*9+7:.uncertain])
        check(missing.moveCount==3,"Unchanged recorded stone blocked two directly observed moves")
        feed(missing,missingViews[2],8)
        check(missing.moveCount==3,"History could not continue once the recorded stone was visible")
        print("PASS: \(checks) observation-history checks: rapid alternating play, prefix saves, temporary occlusion, local recovery, expiry/reset, ambiguity, SGF/review, and rapid captures.")
        return checks
    }
}
