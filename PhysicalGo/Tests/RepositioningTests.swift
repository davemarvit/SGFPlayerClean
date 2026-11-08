import Foundation

@main struct RepositioningTests {
    struct Saved:Decodable {let history:MoveObservationHistory.Checkpoint}
    struct Frame:Decodable {
        let captureUptime:Double
        let readings:[IntersectionReading]
        let footprints:[StoneFootprint]
        let placementFits:[StoneFootprint]
    }
    @MainActor static func main() throws {
        setbuf(stdout,nil);var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {print("FAIL: "+message);exit(1)}}
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/RepositionedPending")
        let saved=try JSONDecoder().decode(Saved.self,from:Data(contentsOf:folder.appendingPathComponent("recording.pending.json")))
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:folder.appendingPathComponent("observations.json")))
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("reposition-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:temp)}
        let file=temp.appendingPathComponent("recording.sgf")
        try FileManager.default.copyItem(at:folder.appendingPathComponent("recording.sgf"),to:file)
        try FileManager.default.copyItem(at:folder.appendingPathComponent("recording.pending.json"),to:temp.appendingPathComponent("recording.pending.json"))
        let recorder=GameRecorder(storage:temp);recorder.clock.audible=false
        try recorder.restoreSavedGame(from:file)
        let game=recorder.game,base=recorder.positions.last!
        check(recorder.moveCount==25 && recorder.pendingMoveCount==5,"Fixture must reproduce the 25 saved + 5 tentative state")
        let originalMoves=game.moves.map{$0.1!.1*19+$0.1!.0}
        recorder.resume()
        let epoch=ProcessInfo.processInfo.systemUptime
        var revisedAt:Double?,acceptedAt:Double?
        for (i,frame) in frames.enumerated() {
            let now=epoch+frame.captureUptime-frames[0].captureUptime
            recorder.consume(.init(readings:frame.readings,size:19,footprints:frame.footprints,placementFits:frame.placementFits),now:now)
            if recorder.pendingConfidence.compactMap(\.point)==[34,53,71],revisedAt==nil {revisedAt=now}
            if recorder.moveCount==28,acceptedAt==nil {acceptedAt=now}
            if i<6 {check(recorder.moveCount==25,"Adjustment bypassed fresh evidence")}
        }
        check(recorder.moveCount==28 && recorder.pendingMoveCount==0,"Actual clip failed: \(recorder.status); pending \(recorder.pendingConfidence.compactMap(\.point))")
        check(recorder.game.moves.map{$0.1!.1*19+$0.1!.0}==originalMoves+[34,53,71],"Wrong chronology or saved prefix changed")
        check(revisedAt != nil && acceptedAt != nil && acceptedAt!-revisedAt!>=1.4,"Revised sequence skipped fresh confirmation")
        check(recorder.interpretedBoard?.grid[0][15]==nil && recorder.interpretedBoard?.grid[1][15] == .white,"Ghost white stone remains")
        let log=try String(contentsOf:temp.appendingPathComponent("recording.observations.jsonl"),encoding:.utf8)
        check(log.contains("tentative adjustment reconciled") && log.contains("previousTentativeSequences"),"Correction audit missing")
        print("Actual saved classifications: revised after \(revisedAt!-epoch)s, recorded after \(acceptedAt!-epoch)s")

        // Exercise the same retained history directly, with controlled changes to
        // the final camera readings. These are synthetic safety controls, not
        // additional labeled images or recognition-accuracy measurements.
        var clean=(0..<361).map {i -> Occupancy in
            let s=base.grid[i/19][i%19];return s == .black ? .black:s == .white ? .white:.empty
        }
        clean[34] = .white;clean[53] = .black;clean[71] = .white
        func replay(_ values:[Occupancy],checkpoint:MoveObservationHistory.Checkpoint?=nil,confidence:Double=1,frames:Int=20,gap:Double=0.21)->MoveObservationHistory {
            var history=MoveObservationHistory.restore(checkpoint ?? saved.history,game:game,now:1000)!
            for n in 0..<frames {
                let now=1000+Double(n)*gap
                let view=BoardObservation(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:confidence,delta:0)},size:19)
                _=history.noteFrame(now:now)
                history.retainLocalEvidence(values,base:base.grid.flatMap{$0}.map{$0 == .black ? .black:$0 == .white ? .white:.empty},now:now)
                _=history.observe(readings:values,game:game,base:base,now:now,recovering:true,unclearLimit:10,observation:view)
            }
            return history
        }
        check(replay(clean).tentativeSequences==[[34,53,71]],"Clean adjustment not resolved")
        let justRevised=replay(clean,frames:5)
        check(justRevised.tentativeSequences==[[34,53,71]],"Five clear frames did not revise tentative sequence")
        check(justRevised.checkpoint.paths.map(\.moves)==[[34,53,71]],"Immediate pause lost revised chronology")
        check(justRevised.bestCandidate?.locked==[1,2],"Settled surviving assignments lost their protection")
        let restarted=MoveObservationHistory.restore(justRevised.checkpoint,game:game,now:2000)
        check(restarted?.tentativeSequences==[[34,53,71]],"Revised checkpoint did not survive restart")
        var unknown=clean;unknown[15] = .uncertain
        check(replay(unknown).tentativeSequences==[[15,53,71,14,34]],"Occlusion erased history")
        var two=clean;two[15] = .white;two[14] = .black
        check(replay(two).tentativeSequences==[[15,53,71,14,34]],"Two real white stones merged")
        var far=clean;far[34] = .empty;far[120] = .white
        check(replay(far).tentativeSequences==[[15,53,71,14,34]],"Distant stone stole old move")
        var missingOld=clean;missingOld[33] = .empty
        check(replay(missingOld).tentativeSequences==[[15,53,71,14,34]],"Committed disappearance rewritten")
        check(replay(clean,confidence:0.85).tentativeSequences==[[15,53,71,14,34]],"Weak classification rewrote history")
        check(replay(clean,frames:4).tentativeSequences==[[15,53,71,14,34]],"Brief contradiction rewrote history")
        check(replay(clean,gap:1).tentativeSequences==[[15,53,71,14,34]],"Stale observations counted as continuous evidence")
        let p=saved.history.paths[0]
        let locked=MoveObservationHistory.Checkpoint(paths:[.init(moves:p.moves,witnesses:p.witnesses,requiredFrames:p.requiredFrames,requiredSeconds:p.requiredSeconds,locked:p.locked.union([0]),placementConcerns:p.placementConcerns)])
        check(replay(clean,checkpoint:locked).tentativeSequences==[[15,53,71,14,34]],"Settled identity relocated automatically")
        let alternative=MoveObservationHistory.Checkpoint.Path(moves:[71,53,15,14,34],witnesses:p.witnesses,
            requiredFrames:p.requiredFrames,requiredSeconds:p.requiredSeconds,locked:p.locked,placementConcerns:p.placementConcerns)
        let ambiguous=MoveObservationHistory.Checkpoint(paths:[p,alternative])
        check(replay(clean,checkpoint:ambiguous).tentativeSequences.count==2,"Adjustment silently chose between competing historical orders")
        let wrongColor=clean.enumerated().map{$0.offset==34 ? Occupancy.black:$0.element}
        check(replay(wrongColor).tentativeSequences==[[15,53,71,14,34]],"Replacement changed color")
        for color in [Occupancy.black,.white] {
            let shortGame=SGFGame.from(tree:try SGFParser.parse(text:"(;GM[1]SZ[9]PL[\(color == .black ? "B":"W")])"))
            let engine=SGFPlayer();engine.load(game:shortGame)
            let checkpoint=MoveObservationHistory.Checkpoint(paths:[.init(moves:[10],
                witnesses:[.init(time:0,depth:1,unknown:[],complete:false),.init(time:0.21,depth:1,unknown:[],complete:false)],
                requiredFrames:[8],requiredSeconds:[1.4],locked:[],placementConcerns:[])])
            var history=MoveObservationHistory.restore(checkpoint,game:shortGame,now:1000)!
            for n in 0..<6 {
                let values=(0..<81).map{$0==11 ? color:Occupancy.empty}
                let observation=BoardObservation(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9)
                let now=1000+Double(n)*0.21
                _=history.noteFrame(now:now);history.retainLocalEvidence(values,base:Array(repeating:.empty,count:81),now:now)
                _=history.observe(readings:values,game:shortGame,base:engine.board,now:now,recovering:true,unclearLimit:10,observation:observation)
            }
            check(history.tentativeSequences==[[11]],"Single adjusted \(color) stone was not relocated")
        }
        recorder.pause()
        let reopened=GameRecorder(storage:nil);try reopened.restoreSavedGame(from:file)
        check(reopened.moveCount==28 && reopened.pendingMoveCount==0,"Reconciled game failed save/restore")
        print("PASS: \(checks) repositioning checks")
    }
}
