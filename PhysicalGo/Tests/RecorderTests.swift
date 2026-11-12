import Foundation

@main struct RecorderTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        try runConfirmationTimingReplay()
        if ProcessInfo.processInfo.environment["PHYSICAL_GO_TIMING_ONLY"] == "1" {
            _ = ObstructionEvidenceTests.run();return
        }
        try runHandicapTests()
        var checks=0
        func check(_ condition:Bool,_ message:String) { checks += 1; if !condition { fatalError(message) } }
        var time=0.0
        func observation(_ board:BoardSnapshot,overrides:[Int:Occupancy]=[:])->BoardObservation {
            BoardObservation(readings:(0..<board.size*board.size).map { i in
                let stone=board.grid[i/board.size][i%board.size]
                return IntersectionReading(row:i/board.size,col:i%board.size,occupancy:overrides[i] ?? (stone == .black ? .black : stone == .white ? .white : .empty),confidence:1,delta:0)
            },size:board.size)
        }
        func feed(_ recorder:GameRecorder,_ board:BoardSnapshot,overrides:[Int:Occupancy]=[:],frames:Int=5) {
            for _ in 0..<frames { time += 0.21; recorder.consume(observation(board,overrides:overrides),now:time) }
        }
        func nextBoard(_ recorder:GameRecorder,_ p:BoardPosition)->BoardSnapshot {
            let engine=SGFPlayer(); engine.load(game:recorder.game); engine.seek(to:recorder.moveCount)
            check(engine.tryPlayMove(color:engine.turn,x:p.col,y:p.row)==nil,"Invalid test move")
            return engine.board
        }
        // A clean single move must earn three consecutive strong views. One
        // obscured neighbor breaks the streak even though it is an empty point.
        do {
            let fast = GameRecorder(storage:nil)
            fast.start(size:9)
            feed(fast,fast.positions[0])
            let board = nextBoard(fast,BoardPosition(4,4))
            func frame(obscured: Bool = false) {
                var view = observation(board,overrides:obscured ? [41:.uncertain] : [:])
                view.footprints = [.init(row:4,col:4,center:.init(x:4,y:4),
                                         radiusCol:0.46,radiusRow:0.46,quality:1)]
                time += 0.21
                fast.consume(view,now:time)
            }
            frame(); frame(obscured:true); frame()
            check(fast.moveCount == 0,"Interrupted sightings triggered early confirmation")
            frame()
            check(fast.moveCount == 0,"Only two consecutive clear views were enough")
            // Start another fresh recorder to distinguish the short rule from
            // ordinary confirmation on the fifth frame of the interrupted run.
            let single = GameRecorder(storage:nil)
            single.start(size:9); feed(single,single.positions[0])
            var clear = observation(board)
            clear.footprints = [.init(row:4,col:4,center:.init(x:4,y:4),
                                      radiusCol:0.46,radiusRow:0.46,quality:1)]
            for _ in 0..<2 { time += 0.21; single.consume(clear,now:time) }
            check(single.moveCount == 0,"Clean move accepted on two views")
            time += 0.21; single.consume(clear,now:time)
            check(single.moveCount == 1,"Clean centered move did not confirm on the third clear view")
        }
        do {
            let startup=GameRecorder(storage:nil)
            let grid=BoardSnapshot(size:9,grid:Array(repeating:Array(repeating:nil,count:9),count:9),stones:[:])
            for i in 0..<6 {feed(startup,grid,overrides:[i:.uncertain],frames:1)}
            check(startup.hasVerifiedEmptyBoard(size:9,now:time),"Moving shadows prevented verified empty start")
            feed(startup,grid,overrides:[40:.black],frames:1)
            check(!startup.hasVerifiedEmptyBoard(size:9,now:time),"Visible stone did not revoke readiness")
            for _ in 0..<10 {feed(startup,grid,overrides:[40:.uncertain],frames:1)}
            check(!startup.hasVerifiedEmptyBoard(size:9,now:time),"Persistently hidden point was assumed empty")
            feed(startup,grid,frames:5)
            check(startup.hasVerifiedEmptyBoard(size:9,now:time),"Positive empty observations did not resolve the hidden point")
            startup.suspendVision("Frozen")
            check(!startup.hasVerifiedEmptyBoard(size:9,now:time),"Frozen camera retained new-game readiness")
        }
        let r=GameRecorder(storage:nil); r.start(size:9)
        let empty=r.positions[0]
        feed(r,empty,overrides:[0:.black]); check(r.state == .verifying,"Started from occupied board")
        feed(r,empty,overrides:[0:.uncertain]); check(r.state == .verifying,"Assumed uncertain starting point empty")
        feed(r,empty); check(r.state == .recording,"Empty start did not arm recording")
        let first=nextBoard(r,BoardPosition(0,1))
        feed(r,first,frames:2); check(r.moveCount==0,"Accepted a flicker")
        feed(r,empty); check(r.moveCount==0,"Empty redraw appended a move")
        feed(r,first,frames:4); check(r.moveCount==0,"Accepted before five frames")
        // Repeated timestamps must not advance a pending move.
        for _ in 0..<10 { r.consume(observation(first),now:time) }
        check(r.moveCount==0,"Duplicate observations advanced stability")
        feed(r,first,frames:1); check(r.moveCount==1,"Stable Black move not recorded")
        feed(r,first,overrides:[80:.black]); check(r.moveCount==1,"Wrong turn accepted")
        feed(r,first,overrides:[1:.empty]); check(r.moveCount==1,"Missing old stone rewrote history")
        let second=nextBoard(r,BoardPosition(1,1))
        feed(r,second,overrides:[2:.uncertain]); check(r.moveCount==2,"Unclear empty neighbor blocked a clear move")
        feed(r,second); check(r.moveCount==2,"Stable White move not recorded")
        let moves=[BoardPosition(1,0),BoardPosition(8,8),BoardPosition(2,1),BoardPosition(8,7)]
        for p in moves { feed(r,nextBoard(r,p)) }
        check(r.moveCount==6,"Alternating sequence not recorded")
        let capture=nextBoard(r,BoardPosition(1,2))
        feed(r,capture,overrides:[10:.white]); check(r.moveCount==6,"Capture accepted before stone removal")
        feed(r,capture); check(r.moveCount==7 && r.positions.last!.grid[1][1]==nil,"Capture did not update history")
        // Back/forward review is non-destructive and freezes recording.
        r.seek(2); check(r.state == .paused && r.reviewedBoard!.stones.count==2,"Review did not pause at move 2")
        let eighth=nextBoard(r,BoardPosition(7,7))
        feed(r,eighth); check(r.moveCount==7 && r.reviewIndex==2,"Live input altered reviewed history")
        r.seek(7); check(r.reviewedBoard==capture,"Forward review lost captures")
        r.resume(); feed(r,eighth); check(r.moveCount==7,"Resume skipped accepted-position validation")
        feed(r,capture); feed(r,eighth); check(r.moveCount==8,"Resume could not continue after synchronization")
        r.undo(); check(r.moveCount==7 && r.state == .paused,"Undo failed")
        r.undo(); check(r.moveCount==6 && r.positions.last!.grid[1][1] == .white,"Undo did not restore captured stone")
        r.manualMove(at:BoardPosition(1,2)); check(r.moveCount==7,"Manual correction failed")
        let corrected=r.sgf(); check(corrected.contains("Entered manually."),"Manual correction omitted from SGF")
        r.resume(); feed(r,r.positions.last!); r.pass(); check(r.moveCount==8,"Pass missing")
        r.pass(); check(r.moveCount==9 && r.state == .finished,"Two passes did not finish")
        let parsed=SGFGame.from(tree:try SGFParser.parse(text:r.sgf()))
        check(parsed.moves.count==9 && parsed.moves[7].1==nil && parsed.moves[8].1==nil,"SGF lost passes")
        let replay=SGFPlayer(); replay.load(game:parsed); replay.seek(to:parsed.moves.count)
        check(replay.board==r.positions.last!,"SGF round trip changed final position")
        check(parsed.info.result==nil && parsed.info.komi==nil,"Invented a result or komi")
        // History retains unchanged recorded identities; definite contradictions still block.
        let uncertain=GameRecorder(storage:nil); uncertain.start(size:9); feed(uncertain,empty)
        feed(uncertain,empty,overrides:[80:.uncertain])
        feed(uncertain,first,overrides:[80:.uncertain]); check(uncertain.moveCount==1,"Persistent empty uncertainty blocked an otherwise verified move")
        feed(uncertain,nextBoard(uncertain,BoardPosition(1,1)),overrides:[1:.uncertain,80:.uncertain])
        check(uncertain.moveCount==2,"Uncertain established stone blocked a clear legal reply")
        uncertain.suspendVision("Camera moved")
        let acceptedSecond=uncertain.positions.last!
        feed(uncertain,acceptedSecond,overrides:[1:.empty,40:.black]); check(uncertain.moveCount==2,"Camera displacement appended a spurious stone")
        feed(uncertain,acceptedSecond)
        check(uncertain.moveCount==2,"Camera recovery could not resume")
        // Long frame gap needs resynchronization; pending partial evidence cannot carry over.
        let third=nextBoard(uncertain,BoardPosition(2,2)); feed(uncertain,third,frames:3)
        time += 3; feed(uncertain,third); check(uncertain.moveCount==2,"Long camera gap carried pending move")
        feed(uncertain,uncertain.positions.last!); feed(uncertain,third); check(uncertain.moveCount==3,"Could not resume after gap")
        // A pair needs stronger confirmation; wrong-sized frames cannot carry evidence.
        let multiple=GameRecorder(storage:nil); multiple.start(size:9); feed(multiple,empty)
        feed(multiple,empty,overrides:[0:.black,1:.white]); check(multiple.moveCount==0,"Accepted a pair before stronger confirmation")
        let other=GameRecorder(storage:nil); other.start(size:13)
        feed(multiple,other.positions[0]); feed(multiple,first); check(multiple.moveCount==0,"Size change bypassed synchronization")
        // Actual ko shape built from legal alternating moves, then attempted recapture.
        let ko=GameRecorder(storage:nil); ko.start(size:9); feed(ko,empty)
        for p in [BoardPosition(0,1),BoardPosition(1,1),BoardPosition(1,0),BoardPosition(0,2),BoardPosition(2,1),BoardPosition(2,2),BoardPosition(8,8),BoardPosition(1,3),BoardPosition(1,2)] {
            feed(ko,nextBoard(ko,p))
        }
        check(ko.moveCount==9,"Ko setup failed")
        feed(ko,ko.positions.last!,overrides:[10:.white,11:.empty]); check(ko.moveCount==9 && ko.status.contains("Ko"),"Illegal ko recapture accepted")
        ko.pause(); ko.manualMove(at:BoardPosition(1,1)); check(ko.moveCount==9 && ko.status.contains("Ko"),"Manual input bypassed ko")
        ko.manualMove(at:BoardPosition(0,0)); check(ko.moveCount==9,"Manual input allowed suicide")
        // Autosave is parseable and review/export always contains the full game.
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("PhysicalGoRecorderTests-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let saved=GameRecorder(storage:dir); saved.start(size:9); feed(saved,empty); feed(saved,first)
        let url=saved.autosaveURL!; saved.seek(0)
        try saved.flushStorage()
        check(try SGFGame.from(tree:SGFParser.parse(text:String(contentsOf:url,encoding:.utf8))).moves.count==1,"Autosave missing move")
        check(try SGFGame.from(tree:SGFParser.parse(text:saved.sgf())).moves.count==1,"Review cursor truncated export")
        saved.undo(); check(try FileManager.default.contentsOfDirectory(atPath:dir.path).filter{$0.hasSuffix(".sgf")}.count==2,"Undo failed to preserve backup")
        saved.start(size:9); check(saved.autosaveURL != url && FileManager.default.fileExists(atPath:url.path),"New game replaced old file")
        // A verified empty live view before Start should not require the user to wait twice.
        let ready=GameRecorder(storage:nil)
        feed(ready,empty)
        ready.start(size:9,now:time)
        check(ready.state == .recording && ready.status.contains("Ready"),"Ignored recently verified empty board")
        feed(ready,first)
        check(ready.moveCount==1,"First move immediately after Start was lost")
        let stale=GameRecorder(storage:nil); feed(stale,empty); stale.start(size:9,now:time+2)
        check(stale.state == .verifying,"Reused stale empty-board evidence")
        let blocked=GameRecorder(storage:nil); feed(blocked,empty,overrides:[0:.uncertain]); blocked.start(size:9,now:time)
        feed(blocked,empty,overrides:[0:.uncertain])
        check(blocked.state == .verifying && blocked.status.contains("1 uncertain"),"Uncertain startup was accepted or had no useful explanation")
        feed(blocked,first)
        check(blocked.moveCount==0 && blocked.activityLabel.contains("Not recording yet") && blocked.status.contains("1 possible stone"),"Occupied unverified startup was silently recorded")
        let interrupted=GameRecorder(storage:nil); feed(interrupted,empty); interrupted.suspendVision("Camera stopped"); interrupted.start(size:9,now:time)
        check(interrupted.state == .verifying,"Reused pre-interruption empty view")
        let wrongSize=GameRecorder(storage:nil); feed(wrongSize,empty); wrongSize.start(size:13,now:time)
        check(wrongSize.state == .verifying,"Empty preview for a different board size was reused")
        let duringMove=GameRecorder(storage:nil); duringMove.start(size:9); feed(duringMove,empty)
        duringMove.suspendVision("Hand briefly obscured grid")
        feed(duringMove,first,frames:5)
        check(duringMove.moveCount==0,"Recovery accepted a move without stronger verification")
        feed(duringMove,first,frames:3)
        check(duringMove.moveCount==1 && duringMove.synchronized,"One legal move after occlusion deadlocked recovery")
        duringMove.suspendVision("Camera moved again")
        feed(duringMove,first,overrides:[70:.white,71:.white],frames:10)
        check(duringMove.moveCount==1,"Recovery guessed the order of multiple moves")
        duringMove.suspendVision("Camera moved")
        feed(duringMove,nextBoard(duringMove,BoardPosition(1,1)),overrides:[1:.empty],frames:10)
        check(duringMove.moveCount==1,"Recovery discarded an established stone")
        // Empty-point uncertainty may fluctuate without restarting confirmation.
        let noisy=GameRecorder(storage:nil); noisy.start(size:9); feed(noisy,empty)
        for i in 0..<5 { feed(noisy,first,overrides:i%2 == 0 ? [70:.uncertain,71:.uncertain] : [:],frames:1) }
        check(noisy.moveCount==1,"Unrelated empty-point flicker starved move acceptance")
        noisy.suspendVision("Grid lost")
        let noisySecond=nextBoard(noisy,BoardPosition(1,1))
        for i in 0..<8 { feed(noisy,noisySecond,overrides:i%2 == 0 ? [70:.uncertain,71:.uncertain] : [70:.uncertain],frames:1) }
        check(noisy.moveCount==2,"Recovery could not tolerate two unresolved empty points")
        let opaque=GameRecorder(storage:nil); opaque.start(size:9); feed(opaque,empty)
        let occluded=Dictionary(uniqueKeysWithValues:(20..<40).map{($0,Occupancy.uncertain)})
        feed(opaque,first,overrides:occluded,frames:12)
        check(opaque.moveCount==0,"Large occlusion was ignored")
        let uncertainMove=GameRecorder(storage:nil); uncertainMove.start(size:9); feed(uncertainMove,empty)
        feed(uncertainMove,first,overrides:[1:.uncertain],frames:12)
        check(uncertainMove.moveCount==0,"An uncertain candidate was treated as a move")
        let alarm=GameRecorder(storage:nil); alarm.start(size:9); feed(alarm,empty)
        var alarms=0,acks=0
        alarm.onAttention={alarms += 1}; alarm.onMoveAccepted={_,_ in acks += 1}
        feed(alarm,first,overrides:[70:.black],frames:20)
        check(alarm.needsAttention && alarm.attentionMessage != nil && alarms==1,"Persistent multi-move blockage had no alert")
        alarm.acknowledgeAttention(); feed(alarm,first,overrides:[70:.black],frames:20)
        check(alarms==1 && alarm.attentionMessage==nil,"Blockage warning repeated continuously")
        feed(alarm,first)
        check(alarm.moveCount==1 && !alarm.needsAttention && acks==1,"Accepted move did not clear blockage and acknowledge")
        let traceURL=url.deletingPathExtension().appendingPathExtension("observations.jsonl")
        let entries=try String(contentsOf:traceURL,encoding:.utf8).split(separator:"\n").map { try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any] }
        check(entries.contains{ $0["event"] as? String == "accepted move" },"Missing accepted-move diagnostic event")
        check(entries.contains{ ($0["position"] as? String)?.count == 81 && $0["pendingFrames"] != nil },"Missing timestamped observation diagnostics")
        // Replay the actual first Black/White session, including its hand occlusions.
        let sessionURL=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures/RecordingSettling/observations.jsonl")
        let session=try String(contentsOf:sessionURL,encoding:.utf8).split(separator:"\n").map { try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any] }
        let replaySession=GameRecorder(storage:nil); replaySession.start(size:19)
        var sessionAlerts=0
        replaySession.onAttention={sessionAlerts += 1}
        for entry in session {
            guard entry["event"] as? String == "observation",let signature=entry["position"] as? String,let stamp=entry["uptime"] as? Double else { continue }
            let states=Array(signature)
            let observed=BoardObservation(readings:states.enumerated().map { i,c in IntersectionReading(row:i/19,col:i%19,occupancy:c == "B" ? .black : c == "W" ? .white : c == "?" ? .uncertain : .empty,confidence:1,delta:0) },size:19)
            replaySession.consume(observed,now:stamp)
        }
        check(replaySession.moveCount==2 && sessionAlerts==0,"Actual hand/settling sequence raised a false alarm or lost a move")
        check(replaySession.game.moves[0].1?.0==15 && replaySession.game.moves[1].1?.0==3,"Session replay changed recorded coordinates")
        let slowHand=GameRecorder(storage:nil); slowHand.start(size:9); feed(slowHand,empty)
        var handAlerts=0; slowHand.onAttention={handAlerts += 1}
        feed(slowHand,first,overrides:occluded,frames:25)
        check(handAlerts==1,"Visible move left unsaved during a five-second obstruction had no bounded warning")
        feed(slowHand,first,frames:3) // Valid candidate frames, not yet a committed move.
        feed(slowHand,first,overrides:[70:.white],frames:1)
        check(handAlerts==1,"One-frame conflict produced another warning")
        feed(slowHand,first); check(slowHand.moveCount==1,"Settling warning changes prevented acceptance")
        let prolonged=GameRecorder(storage:nil); prolonged.start(size:9); feed(prolonged,empty)
        feed(prolonged,first,overrides:occluded,frames:52)
        check(prolonged.needsAttention,"A continuously obscured board never raised attention")
        let restoreFile=dir.appendingPathComponent("restore.sgf")
        try r.sgf().write(to:restoreFile,atomically:true,encoding:.utf8)
        let restored=GameRecorder(storage:nil)
        try restored.restoreSavedGame(from:restoreFile)
        check(restored.state == .finished && restored.moveCount==9 && restored.positions.last==r.positions.last,"Finished-game restore lost moves, capture, or passes")
        restored.seek(6); check(restored.reviewedBoard?.grid[1][1] == .white,"Restored history cannot rewind a capture")
        let fullTree=try SGFParser.parse(text:r.sgf())
        let partial=SGFWriter.serialize(SGFTree(branches:[.init(sequence:Array(fullTree.branches[0].sequence.dropLast(2)))]))
        let partialFile=dir.appendingPathComponent("partial.sgf")
        try partial.write(to:partialFile,atomically:true,encoding:.utf8)
        let journal=partialFile.deletingPathExtension().appendingPathExtension("observations.jsonl")
        try "{\"event\":\"sentinel\"}\n".write(to:journal,atomically:true,encoding:.utf8)
        let continued=GameRecorder(storage:nil);try continued.restoreSavedGame(from:partialFile)
        check(continued.state == .paused && continued.moveCount==7,"Restore should pause rather than assume the camera is aligned")
        check(try String(contentsOf:journal,encoding:.utf8).hasPrefix("{\"event\":\"sentinel\"}"),"Restoring truncated the previous diagnostic log")
        continued.resume();feed(continued,continued.positions.last!);feed(continued,nextBoard(continued,BoardPosition(7,7)))
        check(continued.moveCount==8 && continued.sgf().contains("Entered manually."),"Continuation after restore lost history or manual-entry annotations")
        let invalidFile=dir.appendingPathComponent("invalid.sgf")
        try "(;AP[PhysicalGo:0.22]SZ[9]RU[Japanese];W[aa])".write(to:invalidFile,atomically:true,encoding:.utf8)
        do { try continued.restoreSavedGame(from:invalidFile);fatalError("Restored an illegal first move") }
        catch GameRecorder.RestoreError.invalidMove { }
        check(continued.moveCount==8,"Invalid restore damaged the current recording")
        // Catch up a pair in turn order, independent of intersection scan order.
        let pair=GameRecorder(storage:dir); pair.start(size:9); feed(pair,empty)
        var pairCallbacks=[Int](); pair.onMoveAccepted={number,_ in pairCallbacks.append(number)}
        let pairView:[Int:Occupancy]=[70:.black,2:.white]
        feed(pair,empty,overrides:pairView,frames:7)
        check(pair.moveCount==0,"Pair accepted before eight stable frames")
        feed(pair,empty,overrides:pairView,frames:1)
        check(pair.moveCount==2 && pair.nextPlayer == .black && pairCallbacks==[1,2],"Unique pair did not commit in turn order")
        check(pair.positions[1].grid[7][7] == .black && pair.positions[1].grid[0][2]==nil,"Pair lost the intermediate board")
        check(pair.positions[2].grid[0][2] == .white,"Pair lost White's move")
        try pair.flushStorage()
        check(try SGFGame.from(tree:SGFParser.parse(text:String(contentsOf:pair.autosaveURL!,encoding:.utf8))).moves.count==2,"Pair autosave incomplete")
        pair.seek(1); check(pair.reviewedBoard==pair.positions[1],"Cannot review individual recovered moves")
        pair.resume(); feed(pair,pair.positions.last!)
        feed(pair,pair.positions.last!,overrides:[30:.black,31:.white,32:.black],frames:20)
        check(pair.moveCount==2 && pair.reviewHistory.unresolved==1 && pair.reviewHistory.reviews[0].moves==nil,"Guessed which Black move came first in a three-stone addition")
        feed(pair,pair.positions.last!,overrides:[30:.black,31:.white],frames:8)
        check(pair.moveCount==2 && pair.reviewHistory.unresolved==2,"A later removal erased the earlier ambiguous observation")
        pair.pause()
        let pairReviews=pair.reviewHistory.reviews
        var pairDraft=MoveRecoveryDraft(game:pair.contextForReview(pairReviews[0].id)!.game,observation:nil)
        check(pairDraft.add(BoardPosition(3,3),checkCameraColor:false)==nil && pairDraft.add(BoardPosition(3,4),checkCameraColor:false)==nil,"Could not enter corrected pair")
        check(pair.resolveReview(pairReviews[0].id,draft:pairDraft,overrideCamera:true)==nil,"Could not correct the false third stone")
        let removalDraft=MoveRecoveryDraft(game:pair.contextForReview(pairReviews[1].id)!.game,observation:nil)
        check(pair.resolveReview(pairReviews[1].id,draft:removalDraft,overrideCamera:false)==nil && pair.moveCount==4 && !pair.hasDeferredMoves,"Reviewed pair did not clear the earlier ambiguity")
        let whiteFirst=GameRecorder(storage:nil); whiteFirst.start(size:9);feed(whiteFirst,empty);feed(whiteFirst,first)
        whiteFirst.suspendVision("Camera interrupted")
        feed(whiteFirst,first,overrides:[2:.black,70:.white],frames:8)
        check(whiteFirst.moveCount==3 && whiteFirst.game.moves[1].0 == .white && whiteFirst.positions[2].grid[7][7] == .white,"Recovery ignored White-to-play order")
        let flickeringPair=GameRecorder(storage:nil); flickeringPair.start(size:9);feed(flickeringPair,empty)
        feed(flickeringPair,empty,overrides:pairView,frames:7)
        feed(flickeringPair,empty,overrides:[70:.black,3:.white],frames:1)
        feed(flickeringPair,empty,overrides:pairView,frames:7)
        check(flickeringPair.moveCount==0,"Pair confirmation carried across a changed second move")
        feed(flickeringPair,empty,overrides:pairView,frames:1)
        check(flickeringPair.moveCount==2,"Stable pair never recovered after a flicker")
        let capturePair=GameRecorder(storage:nil);capturePair.start(size:9);feed(capturePair,empty)
        for p in [BoardPosition(0,1),BoardPosition(1,1),BoardPosition(1,0),BoardPosition(8,8),BoardPosition(2,1),BoardPosition(8,7)] {feed(capturePair,nextBoard(capturePair,p))}
        let captureTrial=SGFPlayer();captureTrial.load(game:capturePair.game);captureTrial.seek(to:6)
        check(captureTrial.tryPlayMove(color:.black,x:2,y:1)==nil,"Pair capture setup failed")
        let intermediateCapture=captureTrial.board
        check(captureTrial.tryPlayMove(color:.white,x:7,y:7)==nil,"Pair capture followup invalid")
        feed(capturePair,captureTrial.board,overrides:[10:.uncertain],frames:10)
        check(capturePair.moveCount==6,"Pair ignored uncertain captured stone")
        feed(capturePair,captureTrial.board,overrides:[10:.white],frames:10)
        check(capturePair.moveCount==6,"Pair accepted before captured stone removal")
        feed(capturePair,captureTrial.board,frames:8)
        check(capturePair.moveCount==8 && capturePair.positions[7]==intermediateCapture,"Pair lost capture or intermediate history")
        // White's second move at aa is suicide; neither move may be appended.
        let illegalPair=GameRecorder(storage:nil);illegalPair.start(size:9);feed(illegalPair,empty)
        for p in [BoardPosition(0,1),BoardPosition(8,8),BoardPosition(1,0),BoardPosition(8,7)] {feed(illegalPair,nextBoard(illegalPair,p))}
        feed(illegalPair,illegalPair.positions.last!,overrides:[40:.black,0:.white],frames:12)
        check(illegalPair.moveCount==4,"Illegal second move partially committed a pair")
        let emptyFlicker=GameRecorder(storage:nil);emptyFlicker.start(size:9);feed(emptyFlicker,empty)
        for frame in 0..<8 {
            var readings=pairView
            for index in (20+frame)..<(24+frame) {readings[index] = .uncertain}
            feed(emptyFlicker,empty,overrides:readings,frames:1)
        }
        check(emptyFlicker.moveCount==2,"Clearly reobserved empty points accumulated into a false pair blockage")
        let unseen=GameRecorder(storage:nil);unseen.start(size:9);feed(unseen,empty)
        for frame in 0..<8 {
            var readings=pairView
            // Five points remain unresolved (four uncertain on each frame),
            // with too little clear evidence to count any of them as resolved.
            for index in 20..<25 where index != 20+frame%5 { readings[index] = .uncertain }
            feed(unseen,empty,overrides:readings,frames:1)
        }
        check(unseen.moveCount==0,"Pair ignored too many unresolved empty points")
        let pairFixture=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures/TwoMoveCatchup")
        let catchupFile=dir.appendingPathComponent("catchup.sgf")
        try FileManager.default.copyItem(at:pairFixture.appendingPathComponent("before.sgf"),to:catchupFile)
        let actualPair=GameRecorder(storage:nil);try actualPair.restoreSavedGame(from:catchupFile);actualPair.resume()
        let skippedFile=dir.appendingPathComponent("skipped-first-move.sgf")
        try FileManager.default.copyItem(at:pairFixture.appendingPathComponent("before.sgf"),to:skippedFile)
        let skippedFirst=GameRecorder(storage:nil);try skippedFirst.restoreSavedGame(from:skippedFile);skippedFirst.resume()
        let acceptedBefore=skippedFirst.positions.last!.grid.flatMap{$0}
        var pairAppeared=false
        let catchupRows=try String(contentsOf:pairFixture.appendingPathComponent("observations.jsonl"),encoding:.utf8).split(separator:"\n")
        for row in catchupRows {
            let entry=try JSONSerialization.jsonObject(with:Data(row.utf8)) as! [String:Any]
            let states=Array(entry["position"] as! String)
            let observed=BoardObservation(readings:states.enumerated().map {i,c in IntersectionReading(row:i/19,col:i%19,occupancy:c == "B" ? .black : c == "W" ? .white : c == "?" ? .uncertain : .empty,confidence:1,delta:0)},size:19)
            actualPair.consume(observed,now:entry["uptime"] as! Double)
            let newStones=states.indices.filter{acceptedBefore[$0]==nil && (states[$0]=="B" || states[$0]=="W")}
            if newStones==[4*19+15,4*19+17] { pairAppeared=true }
            if pairAppeared { skippedFirst.consume(observed,now:entry["uptime"] as! Double) }
        }
        check(actualPair.moveCount==21,"Actual diagnostic replay did not recover the pair and later Black move")
        check(actualPair.game.moves[18].1?.0==17 && actualPair.game.moves[18].1?.1==4 && actualPair.game.moves[19].1?.0==15 && actualPair.game.moves[19].1?.1==4 && actualPair.game.moves[20].1?.0==16 && actualPair.game.moves[20].1?.1==3,"Actual recovery changed the observed move order")
        check(actualPair.positions.count==22,"Actual recovery omitted intermediate review positions")
        let recoveryOutput=pairFixture.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/recording-catchup-recovered.sgf")
        try actualPair.sgf().write(to:recoveryOutput,atomically:true,encoding:.utf8)
        try FileManager.default.copyItem(at:catchupFile.deletingPathExtension().appendingPathExtension("observations.jsonl"),to:dir.appendingPathComponent("verified-recovery-trace.jsonl"))
        try Data(contentsOf:dir.appendingPathComponent("verified-recovery-trace.jsonl")).write(to:recoveryOutput.deletingPathExtension().appendingPathExtension("observations.jsonl"),options:.atomic)
        check(skippedFirst.moveCount==21,"Real pair observations did not recover when the first single-move view was skipped")
        let skippedTrace=try String(contentsOf:skippedFile.deletingPathExtension().appendingPathExtension("observations.jsonl"),encoding:.utf8)
        check(skippedTrace.contains("accepted two-move catch-up"),"Real replay never exercised pair recovery")
        print("Actual diagnostic replay recovered moves 19–21, including with the first single-move view skipped.")
        checks += try TentativeTailTests.run()
        checks += ObstructionEvidenceTests.run()
        checks += try TentativeHistoryTests.run()
        checks += try RapidPlayTests.run()
        checks += try LocalMoveEvidenceTests.run()
        checks += try ObservationHistoryTests.run()
        checks += try RecordingWarningTests.run()
        print("PASS: \(checks) recorder checks: stable transitions, turn order, capture removal, review, undo, manual correction, passes, ko/suicide, uncertain evidence, camera recovery, SGF round trip and autosave.")
    }
}


/// Optional replay of each recorded move from its accepted prefix. Raw journals
/// lack outlines/confidence, so this measures the ordinary history path only.
@MainActor private func runConfirmationTimingReplay() throws {
    guard let source=ProcessInfo.processInfo.environment["PHYSICAL_GO_TIMING_REPLAY"] else {return}
    let url=URL(fileURLWithPath:source),tree=try SGFParser.parse(text:String(contentsOf:url))
    let events=try String(contentsOf:url.deletingPathExtension().appendingPathExtension("observations.jsonl")).split(separator:"\n").map {
        try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
    }
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("confirmation-replay-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    for number in 97...105 {
        var frames=events.filter {$0["event"] as? String == "observation" && $0["state"] as? String == "recording" && $0["moveCount"] as? Int == number-1}
        guard let last=frames.last?["time"] as? Double else {continue}
        if let next=events.first(where:{$0["event"] as? String == "observation" && ($0["time"] as? Double ?? 0)>last}) {frames.append(next)}
        guard let begin=frames.first?["uptime"] as? Double else {continue}
        let offset=ProcessInfo.processInfo.systemUptime+10-begin
        let file=root.appendingPathComponent("move-\(number).sgf")
        try SGFWriter.serialize(SGFTree(branches:[.init(sequence:Array(tree.mainLineNodes.prefix(number)))])).write(to:file,atomically:true,encoding:.utf8)
        let recorder=GameRecorder(storage:nil);recorder.clock.audible=false
        try recorder.restoreSavedGame(from:file);recorder.resume()
        let base=recorder.positions.last!
        for i in 0..<8 {
            recorder.consume(.init(readings:(0..<361).map {p in .init(row:p/19,col:p%19,occupancy:base.grid[p/19][p%19] == .black ? .black:base.grid[p/19][p%19] == .white ? .white:.empty,confidence:1,delta:0)},size:19),now:offset+begin-3+Double(i)*0.21)
        }
        var first:Double?,accepted:Double?
        let move=SGFGame.from(tree:tree).moves[number-1].1!,point=move.1*19+move.0
        for entry in frames {
            guard let text=entry["position"] as? String,let time=entry["uptime"] as? Double else {continue}
            let cells=Array(text)
            if cells[point] == (number%2==1 ? "B":"W"),first==nil {first=time}
            recorder.consume(.init(readings:cells.enumerated().map {p,c in .init(row:p/19,col:p%19,occupancy:c == "B" ? .black:c == "W" ? .white:c == "?" ? .uncertain:.empty,confidence:1,delta:0)},size:19,lightingBlocked:entry["lightingBlocked"] as? Bool ?? false),now:offset+time)
            if recorder.moveCount==number {accepted=time;break}
        }
        if accepted != nil {
            precondition(recorder.game.moves.last!.1!.0==move.0 && recorder.game.moves.last!.1!.1==move.1,"Replay accepted the wrong intersection")
        }
        print("TIMING REPLAY move \(number): \(accepted.flatMap {end in first.map {String(format:"%.3f",end-$0)}} ?? "not accepted") seconds from first raw sighting")
    }
}
