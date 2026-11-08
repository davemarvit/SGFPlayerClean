import Foundation

@main struct StallSessionTests {
    struct Entry:Decodable {
        let time:Double
        let event:String?
        let frame:Int?
        let position:String?
        let footprints:[StoneFootprint]?
    }
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/Move25Stall")
        let output=URL(fileURLWithPath:"PhysicalGo/.build/Move25Stall/Replay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let seed=output.appendingPathComponent("Recovered test.sgf")
        try FileManager.default.copyItem(at:folder.appendingPathComponent("initial.sgf"),to:seed)
        try FileManager.default.copyItem(at:folder.appendingPathComponent("initial.pending.json"),to:seed.deletingPathExtension().appendingPathExtension("pending.json"))
        let entries=try JSONDecoder().decode([Entry].self,from:Data(contentsOf:folder.appendingPathComponent("session.json")))
        let recorder=GameRecorder(storage:output);try recorder.restoreSavedGame(from:seed)
        let start=ProcessInfo.processInfo.systemUptime
        let expected=[300,60,307,269,268,249,287,73,250,230,251,71,263,186,294,66,154,174,155,175,78,59,138,43,49,68,69,50,67,87,48,51,85,65,86]
        var checks=0,last:BoardObservation?,lastTime=start
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        var previous="",reports=[[String:Any]]()
        for entry in entries {
            let time=start+entry.time-entries[0].time
            if let event=entry.event {
                switch event {
                case "paused":recorder.pause()
                case "resumed":recorder.resume()
                case "finished":recorder.finish()
                default:if !event.contains("Checking that the physical board matches") {
                    recorder.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"),preserveOrder:event.contains("Finding the grid"))
                }
                }
            } else if let position=entry.position {
                let view=BoardObservation(readings:position.enumerated().map { i,c in
                    .init(row:i/19,col:i%19,occupancy:c=="B" ? .black : c=="W" ? .white : c=="?" ? .uncertain : .empty,confidence:1,delta:0)
                },size:19,footprints:entry.footprints ?? [])
                recorder.consume(view,now:time);last=view;lastTime=time
                let accepted=recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}
                check(accepted==Array(expected.prefix(accepted.count)),"Wrong accepted sequence at frame \(entry.frame!)")
                let key="\(recorder.moveCount)+\(recorder.pendingMoveCount)"
                if key != previous {
                    print("Frame \(entry.frame!) saved+pending \(key): \(recorder.status)");previous=key
                }
                reports.append(["frame":entry.frame!,"saved":recorder.moveCount,"pending":recorder.pendingMoveCount,"status":recorder.status,"sequence":recorder.pendingConfidence.compactMap(\.point),"warnings":recorder.interpretationWarnings.sorted()])
            }
        }
        try recorder.savePendingCheckpoint()
        try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("frames.json"))
        let full=recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}+recorder.pendingConfidence.compactMap(\.point)
        check(full==expected,"Lost or reordered actual moves")
        check(recorder.moveCount==30 && recorder.pendingMoveCount==5,"Expected 30 saved and five retained behind move 31")
        check(recorder.interpretationWarnings==[48],"Only the off-center black move 31 should need adjustment")
        check(last!.signature[66] == .uncertain,"The actual accepted white-stone occlusion was not exercised")
        let simulated=output.appendingPathComponent("Simulated adjustment.sgf")
        try FileManager.default.copyItem(at:seed,to:simulated)
        try FileManager.default.copyItem(at:seed.deletingPathExtension().appendingPathExtension("pending.json"),to:simulated.deletingPathExtension().appendingPathExtension("pending.json"))
        let verify=GameRecorder(storage:nil);try verify.restoreSavedGame(from:simulated);verify.resume()
        var adjusted=last!
        adjusted.footprints=adjusted.footprints.map {shape in
            shape.row*19+shape.col==48 ? StoneFootprint(row:shape.row,col:shape.col,center:.init(x:Double(shape.col),y:Double(shape.row)),radiusCol:shape.radiusCol,radiusRow:shape.radiusRow,quality:shape.quality) : shape
        }
        var validationTime=max(ProcessInfo.processInfo.systemUptime,lastTime)+1
        for _ in 0..<7 {validationTime += 0.21;verify.consume(adjusted,now:validationTime)}
        check(verify.moveCount==30,"Restored moves skipped fresh confirmation")
        validationTime += 0.21;verify.consume(adjusted,now:validationTime)
        check(verify.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}==expected && verify.pendingMoveCount==0,"Simulated centering did not save all 35: \(verify.status)")
        check(verify.positions.last!.grid[3][9] == .white,"Confirmed white move 16 was lost through local uncertainty")
        let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:seed)
        check(restored.moveCount==30 && restored.pendingMoveCount==5 && restored.interpretationWarnings==[48],"Recovery copy was changed by the adjustment simulation")
        print("PASS: \(checks) actual-session checks; all 35 moves retained, 30 saved, move 31 marked, and all 35 saved after simulated adjustment.")
        print("FINAL \(recorder.moveCount) saved, \(recorder.pendingMoveCount) pending, warnings \(recorder.interpretationWarnings.sorted())\n\(full)\n\(recorder.status)\nOutput: \(output.path)")
        try output.path.write(to:URL(fileURLWithPath:"PhysicalGo/.build/Move25Stall/latest-replay.txt"),atomically:true,encoding:.utf8)
    }
}
