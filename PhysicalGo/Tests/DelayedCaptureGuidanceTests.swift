import Foundation

@MainActor enum DelayedCaptureGuidanceTests {
    static func run() throws -> Int {
        var checks=0
        func check(_ ok:Bool,_ reason:String) {checks += 1;precondition(ok,reason)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/DelayedSingleCapture")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("delayed-capture-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        for suffix in ["sgf","clock.json","pending.json"] {
            try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+suffix),to:root.appendingPathComponent("game."+suffix))
        }
        struct RecordedView:Decodable {let position:String;let readingConfidence:[Double]}
        let recorded=try JSONDecoder().decode(RecordedView.self,from:Data(contentsOf:fixture.appendingPathComponent("last-observation.json")))
        let values=recorded.position.map{$0 == "B" ? Occupancy.black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty}
        var now=ProcessInfo.processInfo.systemUptime
        func view(_ board:[Occupancy],hand:Bool=false,confidence:[Double]?=nil,stamp:Double?=nil)->BoardObservation {
            .init(readings:board.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:confidence?[$0.offset] ?? 1,delta:0)},size:19,capturedAt:stamp ?? now,handObstructed:hand)
        }
        func feed(_ r:GameRecorder,_ board:[Occupancy],count:Int=6,hand:Bool=false) {
            for _ in 0..<count {
                now += 0.21
                if hand {r.noteHandObstruction(now:now,capturedAt:now)} else {r.noteHandClear()}
                r.consume(view(board,hand:hand),now:now);r.clock.tick(at:now)
            }
        }
        func receipts(_ r:GameRecorder)throws->Data {
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            return try encoder.encode((r.clock.moves+r.clock.provisionalMoves).sorted{$0.number<$1.number})
        }
        // The actual saved game must recover guidance after an app restart,
        // despite 35 later retained turns and a genuine two-location ambiguity.
        let r=GameRecorder(storage:root,deferredLocations:true);r.clock.audible=false
        try r.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
        let original=try receipts(r),engine=r.clock.engine,sgf=r.sgf()
        check(r.moveCount==23 && r.clock.lastTimedMove==58,"Recorded incident lost its original extent")
        now += 0.21;r.consume(view(values,confidence:recorded.readingConfidence),now:now)
        check(r.captureProgressPlan?.captured == [73] && r.captureProgressPlan?.point==92,"Restart did not recover White 24's outstanding prisoner")
        for rotation in 0..<4 {
            let orientation=BoardOrientation(rotation)
            let message=RecordingClarity.explanation(recorder:r,observation:nil,orientation:orientation) ?? ""
            check(message.contains("Remove the captured black stone") && message.contains(BoardCoordinates.name(point:73,size:19,orientation:orientation)),"Capture message lost removal or displayed coordinates")
            check(!message.contains("locations are still being checked"),"Generic location message hid capture removal")
        }
        check(RecordingClarity.action(at:73,recorder:r) == .captureProgress,"Prisoner did not open capture inspection")
        check(try receipts(r)==original && r.clock.engine==engine && r.sgf()==sgf,"Read-only guidance changed actual move times or balances")
        check(r.deferredPendingRecords.first(where:{$0.number==35})?.candidates.count==2,"Guidance resolved a genuine ambiguity")
        let pending=r.clock.provisionalMoves
        check(AutomaticCapture.pendingGuidance(game:r.game,moves:pending,readings:values)?.captured == [73],"Later observed stones prevented capture projection")
        var ambiguous=pending;ambiguous[0].observedLocations=[92,93]
        check(AutomaticCapture.pendingGuidance(game:r.game,moves:ambiguous,readings:values)==nil,"Ambiguous capturing move invented a certain removal")
        var reused=pending;reused[1].observedLocations=[73]
        var reusedBoard=values;reusedBoard[187] = .empty
        check(AutomaticCapture.pendingGuidance(game:r.game,moves:reused,readings:reusedBoard)==nil,"Later occupation was mistaken for the original prisoner")
        var unexpected=values;unexpected[0] = .black
        check(AutomaticCapture.pendingGuidance(game:r.game,moves:pending,readings:unexpected)==nil,"Unaccounted-for stone was silently erased")
        var clear=values;clear[73] = .empty
        feed(r,clear,count:1)
        check(r.captureProgressPlan != nil,"One empty reading falsely finished removal")
        feed(r,values,count:1,hand:true)
        now += 3
        feed(r,clear,count:4)
        check(r.captureProgressPlan != nil,"Hand or camera gap counted toward sustained clearance")
        feed(r,clear,count:1)
        check(r.captureProgressPlan==nil,"Sustained clear removal retained a stale instruction")
        check(try receipts(r)==original && r.clock.engine==engine,"Clearing guidance changed original saved clock receipts")

        // Synthetic continuous observations follow the recorded opening. They
        // verify live timing separately from restoring an already paused game.
        let live=GameRecorder(storage:nil,deferredLocations:true);live.clock.audible=false
        live.start(size:19,now:now,clockSettings:.init(kind:.fischer,mainSeconds:1800,incrementSeconds:5,maximumSeconds:3600,automaticCaptureMinimum:2))
        let player=SGFPlayer();player.load(game:r.game)
        feed(live,DeferredMoveHistory.states(player.board),count:8)
        for _ in 0..<23 {player.stepForward();feed(live,DeferredMoveHistory.states(player.board),count:8)}
        check(live.moveCount==23 && live.clock.running && !live.clock.requiresReview,"Continuous opening failed to establish known timing")
        var board=DeferredMoveHistory.states(player.board);board[92] = .white
        feed(live,board,count:8)
        check(live.clock.lastTimedMove==24 && live.clock.running && !live.clock.requiresReview,"Single capture stopped the clock or lost its turn")
        for (p,color) in [(187,Occupancy.black),(205,.white)] {board[p]=color;feed(live,board,count:8)}
        check(live.clock.lastTimedMove==26 && live.clock.running && !live.clock.requiresReview,"Later play stopped while a prisoner remained")
        check(live.captureProgressPlan?.captured == [73],"Later turns erased the removal message")
        let runningMessage=live.captureRemovalInstruction(orientation:.init(0)) ?? ""
        check(runningMessage.contains("Play and clocks can continue"),"Running capture guidance suggested stopping play")
        let beforeRemoval=try receipts(live)
        feed(live,board,count:2,hand:true);board[73] = .empty;feed(live,board,count:12)
        check(live.clock.lastTimedMove==26 && live.clock.running && !live.clock.requiresReview,"Removing a prisoner created a turn or stopped clocks")
        check(live.moveCount==26 && live.captureProgressPlan==nil,"Delayed removal did not finalize the retained sequence")
        check(try receipts(live)==beforeRemoval,"Delayed removal changed a timestamp, balance, increment, or original turn")
        live.pause()
        checks += try RetainedTurnResumeTests.run()
        print("PASS: \(checks) delayed single-capture guidance checks (recorded state plus synthetic continuity)")
        return checks
    }
}

@MainActor private enum RetainedTurnResumeTests {
    struct Frame:Decodable {
        let position:String,readingConfidence:[Double],captureUptime:Double,uptime:Double
        let handObstructed:Bool?,lightingBlocked:Bool
        var values:[Occupancy] {position.map{$0 == "B" ? .black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty}}
    }
    static func run()throws->Int {
        var checks=0
        func check(_ yes:Bool,_ why:String) {checks+=1;precondition(yes,why)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/DelayedSingleCapture")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("resume-capture-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        for suffix in ["sgf","clock.json","pending.json"] {
            try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+suffix),to:root.appendingPathComponent("game."+suffix))
        }
        let r=GameRecorder(storage:root,deferredLocations:true);r.clock.audible=false
        try r.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:fixture.appendingPathComponent("resume-observations.json")))
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        func receipts(_ count:Int)throws->Data {try encoder.encode((r.clock.moves+r.clock.provisionalMoves).filter{$0.number<=count}.sorted{$0.number<$1.number})}
        let original=try receipts(58),base=DeferredMoveHistory.states(r.positions.last!)
        let values=frames.first!.values
        let capture=AutomaticCapture.pendingGuidance(game:r.game,moves:r.clock.provisionalMoves,readings:values)!
        let pending=r.clock.provisionalMoves
        check(RetainedTurnPosition.match(base:base,moves:pending,capture:capture,readings:values) != nil,"Actual retained physical position does not match")
        for kind in ["missing","extra","ambiguous","wrongColor","obscured"] {
            var bad=values
            if kind=="missing" {bad[187] = .empty}
            if kind=="extra" {bad[0] = .black}
            if kind=="ambiguous" {bad[80] = .black}
            if kind=="wrongColor" {bad[187] = .white}
            if kind=="obscured" {bad[73] = .uncertain}
            check(RetainedTurnPosition.match(base:base,moves:pending,capture:capture,readings:bad)==nil,"\(kind) position allowed automatic resume")
        }
        var untimed=pending;untimed[3].estimate=nil;untimed[3].reviewed=nil
        check(RetainedTurnPosition.match(base:base,moves:untimed,capture:capture,readings:values)==nil,"Missing timing evidence allowed resume")
        let later=pending.indices.last{pending[$0].black && pending[$0].observedLocations?.count==1}!
        var overlap=pending,overlapBoard=values
        overlapBoard[overlap[later].observedLocations![0]] = .empty
        overlapBoard[80] = .black;overlap[later].observedLocations=[80]
        check(RetainedTurnPosition.match(base:base,moves:overlap,capture:capture,readings:overlapBoard) != nil,"Later occupation of an earlier candidate increased ambiguity")
        overlap[later].observedLocations=[61,80]
        check(RetainedTurnPosition.match(base:base,moves:overlap,capture:capture,readings:overlapBoard) != nil,"Known same-color identities required arbitrary location resolution")
        var now=ProcessInfo.processInfo.systemUptime+2
        func view(_ values:[Occupancy],stamp:Double,hand:Bool=false)->BoardObservation {
            .init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:stamp,handObstructed:hand)
        }
        for _ in 0..<8 {now+=0.21;r.consume(view(values,stamp:now),now:now)}
        check(!r.clock.running && r.state == .paused,"Verification resumed a manually paused game")
        _=r.resume()
        // Repeated callbacks from one image cannot restart either clock.
        let repeated=now+0.21
        for i in 0..<5 {r.consume(view(values,stamp:repeated),now:repeated+Double(i)*0.1)}
        check(!r.clock.running,"Repeated camera timestamp resumed the clock")
        r.noteHandObstruction(now:repeated+0.5,capturedAt:repeated+0.5)
        r.noteHandClear()
        let offset=now+2-frames[0].captureUptime
        var firstResume:Int?
        for (index,frame) in frames.enumerated() {
            let stamp=frame.captureUptime+offset;now=frame.uptime+offset
            if frame.handObstructed == true {r.noteHandObstruction(now:now,capturedAt:stamp)} else {r.noteHandClear()}
            r.consume(.init(readings:frame.values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:frame.readingConfidence[$0.offset],delta:0)},size:19,lightingBlocked:frame.lightingBlocked,capturedAt:stamp,handObstructed:frame.handObstructed),now:now)
            r.clock.tick(at:now)
            if r.clock.running && firstResume==nil {firstResume=index}
            check(try receipts(58)==original,"Actual resume replay altered an original press")
        }
        print("TRACE actual resume",firstResume as Any,r.clock.running,r.clock.requiresReview,r.clock.lastTimedMove,r.clock.notice,r.status)
        check(firstResume != nil && firstResume!<20 && r.clock.running && !r.clock.requiresReview,"Reopened actual game failed to resume its retained timed position")
        check(r.clock.lastTimedMove==60,"The two actual post-resume placements were not timed")
        check(r.clock.provisionalMoves.first(where:{$0.number==59})?.observedLocations == [189] &&
              r.clock.provisionalMoves.first(where:{$0.number==60})?.observedLocations == [356],"Actual test placements were assigned to different intersections")
        for turns in 0..<4 {
            let o=BoardOrientation(turns),speech=r.spokenRecoveryInstruction(orientation:o),status=LocalPlayStatus(recorder:r,orientation:o)
            check(speech.contains("Remove the captured black stone") && !speech.contains("centered") && !speech.contains("pause play"),"Speech still requests misplaced-stone cleanup")
            check(status.title=="Remove captured stones" && status.nextStep.contains(BoardCoordinates.name(point:73,size:19,orientation:o)),"Main status still hides capture removal")
        }
        func feed(_ board:[Occupancy],count:Int=8) {
            for _ in 0..<count {now+=0.21;r.noteHandClear();r.consume(view(board,stamp:now),now:now);r.clock.tick(at:now)}
        }
        var board=frames.last!.values;board[0] = .black;feed(board);board[360] = .white;feed(board)
        check(r.clock.running && r.clock.lastTimedMove==62 && !r.clock.requiresReview,"Two new moves after actual resume were not independently timed")
        check(try receipts(58)==original,"Later play rewrote earlier timestamps")
        let beforeRemoval=try receipts(62)
        board[73] = .empty;feed(board,count:12)
        check(r.clock.running && r.clock.lastTimedMove==62 && !r.clock.requiresReview,"Prisoner removal stopped clocks or created another move")
        check(try receipts(62)==beforeRemoval,"Prisoner removal changed a recorded turn")
        check(r.spokenRecoveryInstruction().contains("Play and clocks can continue") && !r.spokenRecoveryInstruction().contains("centered"),"Completed removal restored a false misplaced-stones warning")
        r.pause()
        // Reopening the actual failed attempt must distinguish its two untimed
        // additions from the original 58 retained turns, never guess new presses.
        let lateRoot=root.appendingPathComponent("late");try FileManager.default.createDirectory(at:lateRoot,withIntermediateDirectories:true)
        for suffix in ["sgf","clock.json","pending.json"] {
            try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+suffix),to:lateRoot.appendingPathComponent("game."+suffix))
        }
        let late=GameRecorder(storage:lateRoot,deferredLocations:true);late.clock.audible=false
        try late.restoreSavedGame(from:lateRoot.appendingPathComponent("game.sgf"));_=late.resume()
        for _ in 0..<8 {now+=0.21;late.consume(view(frames.last!.values,stamp:now),now:now)}
        check(!late.clock.running && late.clock.lastTimedMove==58,"Already present untimed stones invented clock presses")
        check(late.additionalUntimedPoints==[189,356],"Failed-attempt additions were confused with retained placements")
        check(late.spokenRecoveryInstruction().contains("no recorded clock presses") && !late.spokenRecoveryInstruction().contains("centered"),"Untimed additions still received misplaced-stone advice")
        check(LocalPlayStatus(recorder:late).title=="Check unrecorded turns","Main status hid the actual timing problem")
        late.pause()
        print("PASS: \(checks) actual reopen/resume, spoken capture guidance and subsequent-play checks")
        return checks
    }
}
