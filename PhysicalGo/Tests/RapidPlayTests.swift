import Foundation

@MainActor enum RapidPlayTests {
    static func run() throws ->Int {
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;if !value {fatalError(message)}}
        func observation(_ values:[Occupancy],size:Int)->BoardObservation {
            BoardObservation(readings:values.enumerated().map {i,v in
                IntersectionReading(row:i/size,col:i%size,occupancy:v,confidence:1,delta:0)
            },size:size)
        }
        let empty=[Occupancy](repeating:.empty,count:81)
        var evidence=LocalMoveEvidence(),noise=empty
        for row in 0...2 {for col in 0...2 {noise[row*9+col] = .black}}
        evidence.observe(noise,base:empty,now:1)
        evidence.observe(noise,base:empty,now:1.21)
        var clear=empty;clear[10] = .uncertain
        evidence.observe(clear,base:empty,now:1.42)
        check(!evidence.unresolvedPoints(base:empty).contains(10),"A patch inside a broad dark region became a protected hidden stone")
        check(evidence.runCount>0,"Weak sightings were discarded instead of retained for later evaluation")
        evidence.reset();var isolated=empty;isolated[10] = .black
        evidence.observe(isolated,base:empty,now:2)
        evidence.observe(isolated,base:empty,now:2.21)
        evidence.observe(clear,base:empty,now:2.42)
        check(evidence.unresolvedPoints(base:empty).contains(10),"A repeatedly observed isolated stone lost protection when obscured")
        evidence.observe(empty,base:empty,now:2.63)
        check(evidence.unresolvedPoints(base:empty).isEmpty,"Contradictory emptiness did not resolve protected evidence")

        let ghost=GameRecorder(storage:nil);ghost.start(size:9)
        var time=0.0
        func feed(_ values:[Occupancy],_ count:Int) {for _ in 0..<count {time += 0.21;ghost.consume(observation(values,size:9),now:time)}}
        feed(empty,5);feed(noise,2)
        clear[70] = .black;feed(clear,6)
        check(ghost.moveCount==1 && ghost.game.moves.first?.1?.0==70%9,"Weak obscured patch blocked a clear legal move elsewhere")

        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/RapidPlayStall")
        let rows=try String(contentsOf:folder.appendingPathComponent("observations.jsonl"),encoding:.utf8).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }
        let first=rows.first(where:{$0["event"] as? String == "observation"})!["uptime"] as! Double
        let r=GameRecorder(storage:nil),blank=[Occupancy](repeating:.empty,count:361)
        for offset in stride(from:1.05,through:0.21,by:-0.21) {r.consume(observation(blank,size:19),now:first-offset)}
        r.start(size:19,now:first-0.01)
        var commits=[(Double,Int)]()
        let output=URL(fileURLWithPath:"PhysicalGo/.build/RapidPlayReplay.sgf")
        for row in rows {
            let event=row["event"] as! String
            if event.hasPrefix("vision interrupted:") {
                r.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"));continue
            }
            guard event=="observation",let signature=row["position"] as? String,let now=row["uptime"] as? Double else {continue}
            if row["state"] as? String == "paused" {r.pause()}
            let values=signature.map{$0 == "B" ? Occupancy.black : $0 == "W" ? .white : $0 == "?" ? .uncertain : .empty}
            let before=r.moveCount
            r.consume(observation(values,size:19),now:now)
            if r.moveCount != before {commits.append((now-first,r.moveCount))}
        }
        print("Rapid-play replay commits:",commits,"final status:",r.status)
        try r.sgf().write(to:output,atomically:true,encoding:.utf8)
        let expected=[300,60,307,269,268,249,287,73,250,230,251]
        let actual=r.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}
        check(actual==expected,"Rapid-play replay failed to recover the supported prefix or invented/reordered a move: \(actual)")
        check(r.moveCount==11 && r.hasDeferredMoves && r.reviewHistory.unresolved==1 && r.reviewHistory.retainedMoveCount==0,
              "Unordered later moves were guessed or discarded instead of retained for review")
        print("PASS: \(checks) rapid-play checks: weak vs isolated candidates, hidden-point protection, and replay with real grid interruptions.")
        return checks
    }
}
