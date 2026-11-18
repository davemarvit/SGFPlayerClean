import Foundation

@main struct RecordingStoneLedgerTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) { checks += 1;precondition(value,message) }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("recording-stones-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let recorder=GameRecorder(storage:root,deferredLocations:true);recorder.clock.audible=false
        var now=ProcessInfo.processInfo.systemUptime,values=Array(repeating:Occupancy.empty,count:81)
        recorder.start(size:9,now:now,clockSettings:.init(kind:.fischer,mainSeconds:1000,incrementSeconds:2,maximumSeconds:2000))
        func feed(_ count:Int,hand:Bool=false) {
            for _ in 0..<count {
                now += 0.21
                recorder.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},
                    size:9,capturedAt:now,handObstructed:hand),now:now)
                recorder.clock.tick(at:now)
            }
        }
        feed(8)
        values[10] = .black;feed(10)
        values[50] = .white;feed(10)
        check(recorder.moveCount==2 && recorder.clock.running,"Initial real turns failed")
        let original=recorder.stoneLedger!.records,originalPresses=recorder.clock.moves
        feed(4,hand:true)
        values[10] = .empty;values[12] = .black;feed(20)
        check(recorder.clock.lastTimedMove==2,"Cleanup created another clock press")
        check(recorder.moveCount==2 && recorder.clock.running,"Cleanup changed SGF or stopped clocks")
        check(recorder.stoneLedger!.records.map(\.id)==original.map(\.id),"Cleanup changed identities")
        check(recorder.stoneLedger!.records[0].locationUnresolved && recorder.deferredLocationPoints.contains(12),"Moved stone lost unresolved markers")
        check(recorder.stoneLedger!.records[0].physicalPoint==12,"Clear isolated cleanup was not retained as a physical hypothesis")
        check(recorder.displayBoard!.grid[1][3] == .black && recorder.displayBoard!.grid[1][1]==nil,"Display duplicated a cleaned-up stone")
        check(recorder.positions.last!.grid[1][1] == .black,"Display changed the legal board")
        check(RecordingClarity.action(at:12,recorder:recorder) == .recordedPlacement(number:1),"Cleanup marker offered to create a missed move")
        // An independent later placement must be accepted while the old stone's
        // historical position remains unresolved. It is not a second cleanup.
        feed(3,hand:true);values[80] = .black;let thirdTime=now+0.21;feed(12)
        print("TRACE new turn",recorder.moveCount,recorder.clock.lastTimedMove,recorder.status,recorder.clock.notice)
        check(recorder.clock.lastTimedMove==3 && recorder.clock.running,"Unresolved cleanup blocked an independent next turn")
        check(abs(recorder.clock.provisionalMoves.last!.estimate!.time-thirdTime)<0.001,"Background cleanup delayed the original press time")
        check(recorder.stoneLedger!.records.prefix(2).map(\.id)==original.map(\.id),"Later move stole older identity")
        check(recorder.clock.moves[0].estimate==originalPresses[0].estimate && recorder.clock.moves[1].after==originalPresses[1].after,"Cleanup modified original clock receipts")
        // All existing clocks and pending identities survive real save/restore.
        recorder.pause();try recorder.flushStorage()
        let saved=recorder.autosaveURL!,savedIDs=recorder.stoneLedger!.records.map(\.id),balance=recorder.clock.engine
        let reopened=GameRecorder(storage:root,deferredLocations:true);reopened.clock.audible=false
        try reopened.restoreSavedGame(from:saved)
        check(reopened.stoneLedger!.records.map(\.id)==savedIDs,"Restart lost stable IDs")
        check(reopened.clock.engine.black==balance.black && reopened.clock.engine.white==balance.white,"Restart changed clocks")
        let pending=reopened.deferredPendingRecords
        check(pending.count==1 && pending[0].number==3,"Restart lost known pending turn")
        let priorPress=reopened.clock.provisionalMoves[0]
        let result=reopened.resolveDeferredLocations([3:80],identities:pending.map(\.id))
        check(result==nil,"Explicit deferred review failed: \(result ?? "")")
        check(reopened.moveCount==3 && reopened.clock.provisionalMoves.isEmpty,"Deferred review did not finalize exactly one existing turn")
        check(reopened.clock.moves.last!.estimate==priorPress.estimate && reopened.clock.moves.last!.after==priorPress.after,"Final location review recharged the clock")
        check(reopened.resolveDeferredLocations([3:79],identities:pending.map(\.id)) != nil,"Stale review applied")
        try reopened.flushStorage()
        let completed=GameRecorder(storage:root,deferredLocations:true);completed.clock.audible=false
        try completed.restoreSavedGame(from:saved)
        check(completed.moveCount==3 && completed.stoneLedger!.records.map(\.id)==savedIDs,"Finalized game lost identities on restart")
        let oldTimes=completed.stoneLedger!.records.map{$0.press?.time}
        let corrected=try HistoricalMoveCorrection(recorder:completed,number:1,destination:BoardPosition(1,3),keepsLaterMoves:true)
        try completed.applyHistoricalCorrection(corrected)
        check(completed.stoneLedger!.records.map(\.id)==savedIDs && completed.stoneLedger!.records.map{$0.press?.time}==oldTimes,
              "Historical coordinate correction changed identity or timestamp")
        reopened.finish()
        check(reopened.state == .finished && RecordingClarity.action(at:12,recorder:reopened) == .recordedPlacement(number:1),
              "Post-game cleanup review offered to add another move")

        // Legacy SGF: pass/setup and missing clocks migrate without fake times.
        let legacy=root.appendingPathComponent("legacy.sgf")
        try "(;AP[PhysicalGo:0.193]FF[4]GM[1]SZ[9]RU[Japanese];B[bb];W[];B[cc])".write(to:legacy,atomically:true,encoding:.utf8)
        let imported=GameRecorder(storage:root,deferredLocations:true);imported.clock.audible=false
        try imported.restoreSavedGame(from:legacy)
        check(imported.stoneLedger!.records.count==3 && imported.stoneLedger!.records[1].pass,"Legacy pass migration failed")
        check(imported.stoneLedger!.records.allSatisfy{$0.press==nil},"Migration invented measured times")
        let beforeUndo=imported.stoneLedger!.records.last!.id
        check(imported.undo()==nil,"Legacy undo failed")
        check(imported.stoneLedger!.archived.contains{$0.id==beforeUndo} && imported.stoneLedger!.records.count==2,"Undo erased identity audit or retained active turn")
        let handicap=GameRecorder(storage:nil,deferredLocations:true);handicap.clock.audible=false
        handicap.start(size:9,now:now,handicap:2,startPaused:true)
        try handicap.savePendingCheckpoint()
        check(handicap.stoneLedger!.records.isEmpty && handicap.stoneLedger!.setupRemaining.count==2,"Handicap stones became turns")

        // Existing provisional sidecar without the new ledger is migrated from
        // native clock receipts, never from candidate-path move guesses.
        let legacyPending=try Data(contentsOf:saved.deletingPathExtension().appendingPathExtension("pending.json"))
        var oldPayload=try JSONSerialization.jsonObject(with:legacyPending) as! [String:Any]
        oldPayload.removeValue(forKey:"stoneLedger")
        let oldURL=root.appendingPathComponent("old-format.sgf")
        for suffix in ["sgf","clock.json","reviews.json"] {
            let source=saved.deletingPathExtension().appendingPathExtension(suffix)
            if FileManager.default.fileExists(atPath:source.path) {try FileManager.default.copyItem(at:source,to:oldURL.deletingPathExtension().appendingPathExtension(suffix))}
        }
        try JSONSerialization.data(withJSONObject:oldPayload).write(to:oldURL.deletingPathExtension().appendingPathExtension("pending.json"))
        let migrated=GameRecorder(storage:root,deferredLocations:true);migrated.clock.audible=false;try migrated.restoreSavedGame(from:oldURL)
        check(migrated.stoneLedger!.records.map{$0.press?.time}==completed.stoneLedger!.records.map{$0.press?.time},"Legacy migration changed measured times")

        var corrupt=try JSONSerialization.jsonObject(with:legacyPending) as! [String:Any]
        var ledger=corrupt["stoneLedger"] as! [String:Any];ledger["version"]=999;corrupt["stoneLedger"]=ledger
        let damaged=saved.deletingPathExtension().appendingPathExtension("pending.json")
        let bytes=try JSONSerialization.data(withJSONObject:corrupt);try bytes.write(to:damaged)
        let rejected=GameRecorder(storage:nil,deferredLocations:true);rejected.clock.audible=false
        do {try rejected.restoreSavedGame(from:saved);preconditionFailure("Corrupt ledger accepted")} catch {checks += 1}
        check(rejected.recoveryReadBlocked,"Corrupt ledger did not protect original files")
        _=rejected.flushForExit()
        check(try Data(contentsOf:damaged)==bytes,"Failure overwrote damaged evidence")

        // Same-color ambiguity is retained, even after sustained clear views.
        var identity=RecordingStoneLedger(size:9)
        try identity.reconcile([.init(number:1,color:.black,pass:false,point:10,candidates:[10],press:nil),
            .init(number:2,color:.white,pass:false,point:70,candidates:[70],press:nil),
            .init(number:3,color:.black,pass:false,point:14,candidates:[14],press:nil)],captures:[:])
        var ambiguous=Array(repeating:Occupancy.empty,count:81);ambiguous[11] = .black;ambiguous[13] = .black;ambiguous[70] = .white
        for i in 0..<10 {
            let excluded=identity.observe(.init(readings:ambiguous.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:Double(i),handObstructed:false),now:Double(i))
            check(excluded.contains(11) && excluded.contains(13),"Ambiguous old stones became new-turn candidates")
        }
        check(identity.records.filter{$0.color == .black}.allSatisfy{$0.locationUnresolved && $0.physicalPoint==nil},"Nearest neighbor resolved an ambiguous same-color identity")
        var unreliable=RecordingStoneLedger(size:9)
        try unreliable.reconcile([.init(number:1,color:.black,pass:false,point:10,candidates:[10],press:nil)],captures:[:])
        var view=Array(repeating:Occupancy.empty,count:81);view[10] = .uncertain;view[11] = .black
        let excluded=unreliable.observe(.init(readings:view.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:$0.element == .uncertain ? 0:1,delta:0)},size:9,capturedAt:100,handObstructed:false),now:100)
        check(!excluded.contains(11),"Unreliable surrounding stone vetoed independent new-stone evidence")
        var debt=RecordingStoneLedger(size:9)
        try debt.reconcile([.init(number:1,color:.black,pass:false,point:10,candidates:[10],press:nil),
            .init(number:2,color:.white,pass:false,point:11,candidates:[11],press:nil)],captures:[1:2])
        var debtView=Array(repeating:Occupancy.empty,count:81);debtView[10] = .black;debtView[11] = .white
        func observeDebt(_ t:Double,hand:Bool=false)->Set<Int> {
            debt.observe(.init(readings:debtView.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:t,handObstructed:hand),now:t)
        }
        check(observeDebt(1).contains(10),"A captured stone awaiting removal became a new move")
        debtView[10] = .empty;_=observeDebt(1.3,hand:true)
        check(debt.records[0].removalVerified != true,"A hand proved physical capture removal")
        _=observeDebt(1.6);_=observeDebt(2.0);_=observeDebt(2.41)
        check(debt.records[0].removalVerified==true,"Sustained clear observations failed to verify removal")
        debtView[10] = .black
        check(!observeDebt(2.6).contains(10),"Verified removal blocked a genuinely new same-color stone")

        // Two old black stones can be accounted for as a group without picking
        // an identity permutation. A later independent black turn still counts.
        let grouped=GameRecorder(storage:nil,deferredLocations:true);grouped.clock.audible=false
        var groupTime=ProcessInfo.processInfo.systemUptime,groupBoard=Array(repeating:Occupancy.empty,count:81)
        grouped.start(size:9,now:groupTime,clockSettings:.init(kind:.fischer,mainSeconds:1000,incrementSeconds:2))
        func groupFeed(_ count:Int,hand:Bool=false) {
            for _ in 0..<count {
                groupTime+=0.21
                grouped.consume(.init(readings:groupBoard.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:groupTime,handObstructed:hand),now:groupTime)
                grouped.clock.tick(at:groupTime)
            }
        }
        groupFeed(8)
        for (p,color) in [(10,Occupancy.black),(50,.white),(12,.black),(60,.white)] {groupBoard[p]=color;groupFeed(10)}
        let groupOriginal=grouped.stoneLedger!.records
        groupFeed(4,hand:true);groupBoard[10] = .empty;groupBoard[12] = .empty;groupBoard[19] = .black;groupBoard[21] = .black;groupFeed(16)
        check(grouped.clock.lastTimedMove==4 && grouped.clock.running,"Same-color cleanup created a move or stopped clocks")
        check(grouped.stoneLedger!.records.filter{$0.color == .black}.allSatisfy{$0.physicalGroup==[19,21] && $0.physicalPoint==nil && $0.locationUnresolved},"Group tracking guessed a same-color identity")
        let groupDisplay=DeferredMoveHistory.states(grouped.displayBoard!)
        check(groupDisplay[10] == .empty && groupDisplay[12] == .empty && groupDisplay[19] == .black && groupDisplay[21] == .black,"Ambiguous cleanup group duplicated display stones")
        groupFeed(3,hand:true);groupBoard[80] = .black;let fifthTime=groupTime+0.21;groupFeed(12)
        check(grouped.clock.lastTimedMove==5 && grouped.clock.running,"Same-color identity ambiguity blocked a separate known turn")
        check(abs(grouped.clock.provisionalMoves.last!.estimate!.time-fifthTime)<0.001,"Group cleanup delayed the next turn's original timestamp")
        check(grouped.stoneLedger!.records.prefix(4).map(\.id)==groupOriginal.map(\.id) && grouped.stoneLedger!.records.prefix(4).map(\.press)==groupOriginal.map(\.press),"Group cleanup reassigned an old identity or clock receipt")
        var restoredGroup=try JSONDecoder().decode(RecordingStoneLedger.self,from:JSONEncoder().encode(grouped.stoneLedger!))
        check(restoredGroup.valid() && restoredGroup.records.filter{$0.physicalGroup != nil}.count==2,"Restart lost unresolved group membership")
        groupBoard[19] = .uncertain;groupBoard[79] = .black
        let incomplete=restoredGroup.observe(.init(readings:groupBoard.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:$0.element == .uncertain ? 0:1,delta:0)},size:9,capturedAt:groupTime+0.21,handObstructed:false),now:groupTime+0.21)
        check(incomplete.contains(79),"One surviving sighting accounted for two hidden group identities")
        grouped.pause()
        print("PASS: \(checks) connected recording identity, cleanup, review, migration and persistence checks")
    }
}
