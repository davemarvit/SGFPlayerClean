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
        checks += try ClearedLocationMarkerTests.run()
        checks += try AutomaticLocationResolutionTests.run()
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

@MainActor private enum ClearedLocationMarkerTests {
    static func run() throws -> Int {
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ClearedLocationMarkers")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("cleared-markers-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        for suffix in ["sgf","clock.json","pending.json"] {
            try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+suffix),to:root.appendingPathComponent("game."+suffix))
        }
        struct Frame:Decodable {
            let position:String,readingConfidence:[Double],captureUptime:Double,uptime:Double
            let handObstructed:Bool?,lightingBlocked:Bool?
        }
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:fixture.appendingPathComponent("observations.json")))
        let r=GameRecorder(storage:root,deferredLocations:true);r.clock.audible=false
        try r.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        func receipts()throws->Data {try encoder.encode((r.clock.moves+r.clock.provisionalMoves).sorted{$0.number<$1.number})}
        let original=try receipts(),engine=r.clock.engine,sgf=r.sgf(),identities=r.stoneLedger!.records.map(\.id)
        check(r.clock.lastTimedMove==68 && r.moveCount==23,"Wrong cleared-marker recording extent")
        let offset=ProcessInfo.processInfo.systemUptime+2-frames[0].captureUptime
        for f in frames {
            let stamp=f.captureUptime+offset,now=f.uptime+offset
            if f.handObstructed == true {r.noteHandObstruction(now:now,capturedAt:stamp)} else {r.noteHandClear()}
            let values=f.position.map{$0 == "B" ? Occupancy.black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty}
            r.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:f.readingConfidence[$0.offset],delta:0)},size:19,lightingBlocked:f.lightingBlocked ?? false,capturedAt:stamp,handObstructed:f.handObstructed),now:now)
            check(try receipts()==original && r.clock.engine==engine,"Background verification changed original timing")
        }
        let unresolved=r.stoneLedger!.records.filter{$0.locationUnresolved && $0.capturedBy==nil}
        print("TRACE cleared markers",unresolved.map(\.number),r.adjustmentIssues,r.pendingConfidence.filter(\.placementUncertain).count)
        check(unresolved.isEmpty,"Sustained unique original location remained unresolved")
        check(r.stoneLedger!.records[34].resolvedPoint==61 && r.stoneLedger!.records[34].candidates==[61],"Q15 did not resolve the P15/Q15 alternatives")
        check(r.pendingConfidence.filter(\.placementUncertain).isEmpty,"SGF backlog was labeled location uncertainty")
        check(r.stoneLedger!.records[6].capturedBy==24 && r.stoneLedger!.records[6].removalVerified==true,"Known captured stone retained removal debt")
        check(r.displayBoard!.grid[73/19][73%19]==nil && !r.adjustmentIssues.keys.contains(73),"Removed prisoner retained a board marker")
        check(Set(r.adjustmentIssues.keys)==[36,51,112],"Cleared pending locations or unmatched detections were marked incorrectly")
        check([36,51,112].allSatisfy{p in !r.stoneLedger!.records.contains{$0.candidates.contains(p)}},"Expected camera-only detections belong to retained moves")
        check(r.deferredLocationPoints.isEmpty,"The empty P15 alternative retained its ring")
        check(r.sgf()==sgf && r.stoneLedger!.records.map(\.id)==identities && !r.clock.running,"Background verification changed saved moves or resumed a paused clock")
        try r.flushStorage()
        let reopened=GameRecorder(storage:root,deferredLocations:true);reopened.clock.audible=false
        try reopened.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
        check(reopened.stoneLedger!.records[6].capturedBy==24 && reopened.stoneLedger!.records[6].removalVerified==true,"Restart lost proven capture removal")
        check(reopened.stoneLedger!.records.filter{$0.locationUnresolved && $0.capturedBy==nil}.isEmpty,"Restart resurrected cleared location flags")
        check(RecordingClarity.checkPoints(recorder:r,observation:nil)==[36,51,112],"Cleared markers remained or genuine unmatched detections disappeared")
        for locations in [[92,93],[73]] {
            let blocked=root.appendingPathComponent("blocked-\(locations.count)")
            try FileManager.default.createDirectory(at:blocked,withIntermediateDirectories:true)
            for suffix in ["sgf","clock.json","pending.json"] {
                try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+suffix),to:blocked.appendingPathComponent("game."+suffix))
            }
            let file=blocked.appendingPathComponent("game.clock.json")
            var object=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
            var moves=object["provisionalMoves"] as! [[String:Any]]
            moves[0]["observedLocations"]=locations;object["provisionalMoves"]=moves
            try JSONSerialization.data(withJSONObject:object).write(to:file)
            let uncertain=GameRecorder(storage:blocked,deferredLocations:true);uncertain.clock.audible=false
            try uncertain.restoreSavedGame(from:blocked.appendingPathComponent("game.sgf"))
            check(uncertain.stoneLedger!.records[6].capturedBy==nil,"Ambiguous or illegal capturing move authorized removal")
            if locations==[73] {
                let originalEngine=uncertain.clock.engine
                for f in frames {
                    let stamp=f.captureUptime+offset,now=f.uptime+offset
                    let values=f.position.map{$0 == "B" ? Occupancy.black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty}
                    uncertain.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:f.readingConfidence[$0.offset],delta:0)},size:19,capturedAt:stamp,handObstructed:f.handObstructed),now:now)
                }
                check(uncertain.stoneLedger!.records[34].resolvedPoint==nil && uncertain.clock.engine==originalEngine,"Location resolution crossed an illegal earlier move or changed clocks")
            }
        }

        // Synthetic edge cases isolate confidence, hand/gap resets and identity
        // ambiguity. They are not claimed as additional recorded observations.
        let input=RecordingStoneLedger.Input(number:1,color:.black,pass:false,point:nil,candidates:[10],press:nil)
        var ledger=RecordingStoneLedger(size:9);try ledger.reconcile([input],captures:[:])
        func view(_ time:Double,confidence:Double=0.82,hand:Bool=false,point:Int=10)->BoardObservation {
            var values=Array(repeating:Occupancy.empty,count:81);values[point] = .black
            return .init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:$0.offset==point ? confidence:1,delta:0)},size:9,capturedAt:time,handObstructed:hand)
        }
        func observe(_ time:Double,confidence:Double=0.82,hand:Bool=false,point:Int=10) {
            _=ledger.observe(view(time,confidence:confidence,hand:hand,point:point),now:time,originalLocations:[1:[10]])
        }
        observe(0,confidence:0.6)
        for i in 1...7 {observe(Double(i)*0.21)}
        check(ledger.records[0].locationUnresolved,"Brief weak sightings cleared an uncertainty flag")
        observe(1.6,hand:true)
        for i in 0..<7 {observe(1.8+Double(i)*0.21)}
        check(ledger.records[0].locationUnresolved,"Hand interruption did not reset confidence")
        observe(4)
        for i in 1..<7 {observe(4+Double(i)*0.21)}
        check(ledger.records[0].locationUnresolved,"Camera gap did not reset confidence")
        observe(5.47);observe(5.68)
        check(!ledger.records[0].locationUnresolved && ledger.records[0].candidates==[10],"Sustained original location failed to clear its flag")
        observe(6,confidence:0.7)
        check(ledger.records[0].locationUnresolved,"Fresh unreliable evidence was hidden")
        try ledger.reconcile([.init(number:1,color:.black,pass:false,point:nil,candidates:[10,11],press:nil)],captures:[:])
        for i in 0..<12 {observe(7+Double(i)*0.21)}
        check(ledger.records[0].locationUnresolved && ledger.records[0].candidates==[10,11],"Moderate confidence erased a historical alternative")
        for i in 0..<12 {observe(10+Double(i)*0.21,point:12)}
        check(ledger.records[0].locationUnresolved,"A different intersection silently resolved historical identity")
        var debt=RecordingStoneLedger(size:9)
        try debt.reconcile([.init(number:1,color:.black,pass:false,point:10,candidates:[10],press:nil),
            .init(number:2,color:.white,pass:false,point:11,candidates:[11],press:nil)],captures:[1:2])
        func removed(_ time:Double,occupancy:Occupancy = .empty,confidence:Double=0.93,hand:Bool=false) {
            var values=Array(repeating:Occupancy.empty,count:81);values[10]=occupancy;values[11] = .white
            _=debt.observe(.init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:$0.offset==10 ? confidence:1,delta:0)},size:9,capturedAt:time,handObstructed:hand),now:time)
        }
        for i in 0..<6 {removed(Double(i)*0.21,occupancy:.white)}
        check(debt.records[0].removalVerified != true,"Opposite-color reading proved an empty captured point")
        for i in 0..<6 {removed(2+Double(i)*0.21,confidence:0.85)}
        check(debt.records[0].removalVerified != true,"Weak empty readings released capture debt")
        removed(4);removed(4.4);removed(4.6,hand:true);removed(4.8)
        check(debt.records[0].removalVerified != true,"Hand interruption verified prisoner removal")
        removed(6);removed(6.4)
        check(debt.records[0].removalVerified != true,"Camera gap verified prisoner removal")
        removed(6.81)
        check(debt.records[0].removalVerified==true,"Sustained clear empty readings did not release capture debt")
        let newStone=debt.observe(view(7,confidence:1),now:7)
        check(!newStone.contains(10),"A new stone at a cleared capture point was consumed as old removal debt")
        print("PASS: \(checks) recorded cleared-marker and confidence-boundary checks")
        return checks
    }
}

@MainActor private enum AutomaticLocationResolutionTests {
    static func run() throws -> Int {
        var checks=0
        func check(_ value:Bool,_ why:String) {checks+=1;precondition(value,why)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ClearedLocationMarkers")
        let object=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture.appendingPathComponent("game.pending.json"))) as! [String:Any]
        let saved=try JSONDecoder().decode(RecordingStoneLedger.self,from:JSONSerialization.data(withJSONObject:object["stoneLedger"]!))
        // Synthetic continuous clear views of the recorded 68-turn position
        // isolate location resolution while a real recorder clock is running.
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("live-resolution-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        for suffix in ["sgf","clock.json","pending.json"] {
            try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+suffix),to:root.appendingPathComponent("game."+suffix))
        }
        let live=GameRecorder(storage:root,deferredLocations:true);live.clock.audible=false
        try live.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let beforePresses=try encoder.encode(live.clock.moves+live.clock.provisionalMoves),beforeSGF=live.sgf()
        let frames=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture.appendingPathComponent("observations.json"))) as! [[String:Any]]
        var board=(frames.last!["position"] as! String).map{$0 == "B" ? Occupancy.black:$0 == "W" ? .white:.empty}
        for p in [36,51,112] {board[p] = .empty}
        var liveTime=ProcessInfo.processInfo.systemUptime+1
        func liveFeed(_ count:Int) {
            for _ in 0..<count {
                liveTime+=0.21
                live.consume(.init(readings:board.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:liveTime,handObstructed:false),now:liveTime)
                live.clock.tick(at:liveTime)
            }
        }
        _=live.resume();liveFeed(6)
        check(live.clock.running && live.stoneLedger!.records[34].resolvedPoint==nil,"Location confirmation happened before sustained evidence or blocked resume")
        let beforeEngine=live.clock.engine,beforeTime=liveTime
        liveFeed(16)
        check(live.clock.running && live.stoneLedger!.records[34].resolvedPoint==61,"Automatic location resolution stopped the live clock")
        check(abs(live.clock.engine.black.remaining-(beforeEngine.black.remaining-(liveTime-beforeTime)))<0.001 && live.clock.engine.white==beforeEngine.white,"Location confirmation charged a turn again")
        check(try encoder.encode(live.clock.moves+live.clock.provisionalMoves)==beforePresses && live.sgf()==beforeSGF,"Location confirmation created a turn or changed a receipt")
        live.pause()
        let receipt=saved.records[34].press!
        let input=RecordingStoneLedger.Input(number:1,color:.black,pass:false,point:nil,candidates:[10,11],press:receipt)
        var ledger=RecordingStoneLedger(size:9);try ledger.reconcile([input],captures:[:])
        var now=0.0
        func feed(_ count:Int,alternative:Occupancy = .empty,hand:Bool=false,offset:Double=0.02,repeated:Bool=false,selected:Int=10) {
            for _ in 0..<count {
                if !repeated {now+=0.21}
                var board=Array(repeating:Occupancy.empty,count:81);board[selected] = .black
                if selected==10 {board[11]=alternative}
                let shape=StoneFootprint(row:selected/9,col:selected%9,center:.init(x:Double(selected%9)+offset,y:Double(selected/9)),radiusCol:0.44,radiusRow:0.44,quality:1)
                _=ledger.observe(.init(readings:board.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,footprints:[shape],capturedAt:now,handObstructed:hand),now:now,originalLocations:[1:[10,11]])
            }
        }
        feed(20,alternative:.uncertain)
        check(ledger.locationProposals.isEmpty,"An obscured alternative was treated as empty")
        feed(20,alternative:.black)
        check(ledger.locationProposals.isEmpty,"Two same-color stones were resolved as one identity")
        feed(20,offset:0.48)
        check(ledger.locationProposals.isEmpty,"An off-center stone resolved its ambiguous intersection")
        feed(11)
        check(ledger.locationProposals.isEmpty,"A short clear glimpse resolved location")
        feed(1,hand:true);feed(11)
        check(ledger.locationProposals.isEmpty,"Hand occlusion did not interrupt location confirmation")
        now+=2;feed(11)
        check(ledger.locationProposals.isEmpty,"A camera gap did not interrupt location confirmation")
        feed(20,repeated:true)
        check(ledger.locationProposals.isEmpty,"Repeated timestamps counted as independent confirmation")
        feed(12)
        check(ledger.locationProposals==[1:10],"Centering on an original candidate failed to resolve it")
        try ledger.resolveOriginalLocations([1:10],at:now)
        check(ledger.records[0].press==receipt && ledger.records[0].resolvedPoint==10 && !ledger.records[0].locationUnresolved,"Resolution changed timing or kept its red marker")
        try ledger.reconcile([input],captures:[:])
        ledger=try JSONDecoder().decode(RecordingStoneLedger.self,from:JSONEncoder().encode(ledger))
        check(ledger.records[0].candidates==[10] && ledger.records[0].resolvedPoint==10 && ledger.records[0].press==receipt,"Reopening resurrected the discarded alternative or changed the original press")
        feed(15,selected:11)
        check(ledger.records[0].resolvedPoint==10 && ledger.records[0].locationUnresolved && ledger.records[0].press==receipt,"Later cleanup rewrote the resolved original move")

        // Replay actual observations through physical identity exclusion. The
        // first run reproduces the old missing capture fact; the second supplies
        // the legally established White 24 capture. Neither invents clock times.
        let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture.appendingPathComponent("missing-turn-sequence.json"))) as! [[String:Any]]
        for captureKnown in [false,true] {
            var ledger=RecordingStoneLedger(size:19),count=58,appeared=Set<Int>()
            func sync()throws {try ledger.reconcile(saved.records.prefix(count).map{.init(number:$0.number,color:$0.color,pass:$0.pass,point:$0.historicalPoint,candidates:$0.candidates,press:$0.press)},captures:captureKnown ? [7:24]:[:])}
            try sync()
            for row in rows {
                if row["event"] as? String == "observed turn clock press" {count=row["number"] as! Int;try sync();continue}
                if row["event"] as? String == "hand obstruction began" {ledger.interrupt();continue}
                let values=(row["position"] as! String).map{$0 == "B" ? Occupancy.black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty}
                let scores=row["readingConfidence"] as! [Double],stamp=row["captureUptime"] as! Double
                let excluded=ledger.observe(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:scores[$0.offset],delta:0)},size:19,capturedAt:stamp,handObstructed:row["handObstructed"] as? Bool),now:row["uptime"] as! Double)
                for p in [112,36,51] where values[p].stone != nil && appeared.insert(p).inserted {
                    check(excluded.contains(p)==(!captureKnown && p==112),"Recorded missed-turn exclusion did not match the diagnosed capture-removal cause")
                }
            }
            check(appeared==[112,36,51],"Recorded unmatched-stone sequence was not fully replayed")
            if captureKnown {check(ledger.records[6].removalVerified==true,"Recorded prisoner removal did not release its identity")}
        }
        print("PASS: \(checks) automatic location resolution and recorded unmatched-stone checks")
        return checks
    }
}
