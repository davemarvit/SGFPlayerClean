import Foundation

@MainActor enum TentativeTailTests {
    static func run()throws->Int {
        var checks=0,time=0.0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        // Exercise ambiguous assignment. A 0.94+ outline now certifies unique
        // coverage at this offset; an offset-only fixture cannot claim that fit.
        func feed(_ recorder:GameRecorder,_ colors:[Occupancy],_ count:Int) {
            for _ in 0..<count {time += 0.21
                let shape=StoneFootprint(row:1,col:1,center:.init(x:1.36,y:1),radiusCol:0.46,radiusRow:0.46,quality:0.90)
                recorder.consume(BoardObservation(readings:colors.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,footprints:colors[10] == .black ? [shape] : []),now:time)
            }
        }
        func setup(_ tailFrames:Int=2)->(GameRecorder,[Occupancy]) {
            let recorder=GameRecorder(storage:nil);var colors=Array(repeating:Occupancy.empty,count:81)
            recorder.start(size:9);feed(recorder,colors,5)
            colors[10] = .black;feed(recorder,colors,3)
            colors[20] = .white;feed(recorder,colors,8)
            colors[30] = .black;feed(recorder,colors,tailFrames)
            check(recorder.moveCount==0 && recorder.pendingConfidence.compactMap(\.point)==[10,20,30],"Wrong tentative setup")
            return (recorder,colors)
        }
        var (replaced,a)=setup();a[30] = .empty;a[40] = .black
        feed(replaced,a,1)
        check(replaced.pendingConfidence.compactMap(\.point)==[10,20,30],"One empty flash withdrew an anchored tail")
        feed(replaced,a,2)
        check(replaced.pendingConfidence.compactMap(\.point)==[10,20,40],"Repeated empty evidence failed to replace a false tentative tail")
        check(replaced.pendingConfidence[0].placementUncertain,"Tail repair cleared an unrelated placement concern")
        check(replaced.pendingConfidence[1].level=="high","Tail repair lost a locked earlier identity")
        var (rest,b)=setup();b[30] = .empty;feed(rest,b,3)
        check(rest.pendingConfidence.compactMap(\.point)==[10,20],"Clearly empty false tail could not return to previous tentative board")
        var (hidden,c)=setup();c[30] = .uncertain;c[40] = .black;feed(hidden,c,12)
        check(hidden.pendingConfidence.compactMap(\.point)==[10,20,30],"Uncertainty erased an earlier tentative stone")
        var (locked,d)=setup(10);d[30] = .empty;d[40] = .black;feed(locked,d,12)
        check(locked.pendingConfidence.compactMap(\.point)==[10,20,30],"A locked move was silently rewritten")
        var (opponent,e)=setup();e[30] = .empty;e[40] = .white;feed(opponent,e,12)
        check(opponent.pendingConfidence.compactMap(\.point)==[10,20,30],"Opposite-color continuation could erase a possibly captured move")
        var (gap,f)=setup();f[30] = .empty;feed(gap,f,1);f[30] = .black;feed(gap,f,1);f[30] = .empty;f[40] = .black;feed(gap,f,1)
        check(gap.pendingConfidence.compactMap(\.point)==[10,20,30],"Empty evidence survived a later positive stone sighting")
        let paired=GameRecorder(storage:nil);var pairedColors=Array(repeating:Occupancy.empty,count:81)
        paired.start(size:9);feed(paired,pairedColors,5)
        pairedColors[10] = .black;feed(paired,pairedColors,3)
        pairedColors[20] = .white;feed(paired,pairedColors,8)
        pairedColors[30] = .black;pairedColors[40] = .white;feed(paired,pairedColors,2)
        check(paired.pendingConfidence.compactMap(\.point)==[10,20,30,40],"Rapid pair not retained")
        pairedColors[40] = .empty;feed(paired,pairedColors,1)
        check(paired.pendingConfidence.compactMap(\.point)==[10,20,30,40],"One empty flash erased the paired tail")
        feed(paired,pairedColors,2)
        check(paired.pendingConfidence.compactMap(\.point)==[10,20,30],"False paired reply trapped the real preceding move")
        check(paired.pendingConfidence[0].placementUncertain,"Pair repair silently cleared the earlier displaced move")
        pairedColors[50] = .white;feed(paired,pairedColors,3)
        check(paired.pendingConfidence.compactMap(\.point)==[10,20,30,50],"Real replacement could not follow a paired false tail")
        var (wrongTurn,wrongColors)=setup(10)
        wrongColors[40] = .black;feed(wrongTurn,wrongColors,6)
        check(wrongTurn.pendingConfidence.compactMap(\.point)==[10,20,30],"Out-of-turn Black was recorded")
        wrongTurn.suspendVision("Finding the grid. The recorded game is preserved.",preserveOrder:true)
        time += 2.0 // Reacquisition and delivery gaps must not erase the known order.
        wrongColors[50] = .white;feed(wrongTurn,wrongColors,6)
        check(wrongTurn.pendingConfidence.compactMap(\.point)==[10,20,30],"Later White was moved before the observed extra Black")
        feed(wrongTurn,wrongColors,80)
        // Long unresolved interruptions now enter the durable review queue.
        // Preserve the known prefix as a proposal without inventing an order
        // for the out-of-turn stone and the later reply.
        let deferred=wrongTurn.reviewHistory.sections.first
        check(wrongTurn.moveCount==0 && wrongTurn.hasDeferredMoves && deferred?.moves==nil &&
              deferred?.suggestedOrders?.contains(where:{$0.compactMap{$0.point.map{$0.row*9+$0.col}} == [10,20,30]})==true &&
              wrongTurn.reviewHistory.latest==wrongColors,
              "Expired chronology lost its known prefix or invented an accepted alternating order")
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/TentativeFalseTail")
        let initialData=try Data(contentsOf:fixture.appendingPathComponent("initial.sgf"))
        let output=URL(fileURLWithPath:"PhysicalGo/.build/G1FalseStone/RecorderRegression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let seed=output.appendingPathComponent("Replay.sgf");try initialData.write(to:seed)
        let actual=GameRecorder(storage:nil);try actual.restoreSavedGame(from:seed)
        let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture.appendingPathComponent("observations.json"))) as! [[String:Any]]
        var sawFalse=false,sawCorrection=false
        for row in rows {
            if let event=row["event"] as? String {
                if event=="resumed" {actual.resume()}
                else if event=="paused" {actual.pause()}
                else {actual.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"),preserveOrder:event.contains("Finding the grid") || event.contains("after a camera interruption"))}
                continue
            }
            let colors=Array(row["position"] as! String).map {c -> Occupancy in c=="B" ? .black : c=="W" ? .white : c=="?" ? .uncertain : .empty}
            let shapes=(row["offsets"] as! [String:Double]).map {key,value -> StoneFootprint in
                let p=Int(key)!;return .init(row:p/19,col:p%19,center:.init(x:Double(p%19)+value,y:Double(p/19)),radiusCol:0.46,radiusRow:0.46,quality:0.90)
            }
            actual.consume(BoardObservation(readings:colors.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,footprints:shapes),now:row["time"] as! Double)
            let frame=row["frame"] as! Int,points=actual.pendingConfidence.compactMap(\.point)
            if frame==1149 {check(points.last==114,"Actual hand-shaped tentative G1 was not exercised");sawFalse=true}
            if frame==1194 {check(points==[49,68,67,100,214],"Actual empty G1 did not yield to the observed real move");sawCorrection=true}
            if frame>=1194 {check(!points.contains(114),"Retracted G1 reappeared")}
        }
        check(sawFalse && sawCorrection,"Fixture skipped the failing and corrected moments")
        check(actual.moveCount==63 && actual.hasDeferredMoves && actual.reviewHistory.unresolved>0 &&
              actual.reviewHistory.sections.first?.suggestedOrders?.contains(where: {
                  $0.compactMap {$0.point.map {$0.row*19+$0.col}} == [49,68,67,100,214]
              })==true, "Changed saved history or lost the retained prefix and unresolved capture review")
        let engine=SGFPlayer();engine.load(game:actual.game);engine.seek(to:actual.moveCount)
        for point in [49,68,67,100,214] {check(engine.tryPlayMove(color:engine.turn,x:point%19,y:point/19)==nil,"Invalid retained order")}
        let beforeCapture=engine.board
        check(engine.tryPlayMove(color:.black,x:232%19,y:232/19)==nil,"Observed capturing move is illegal")
        let removed=(0..<361).filter{beforeCapture.grid[$0/19][$0%19] != nil && engine.board.grid[$0/19][$0%19]==nil}
        check(removed==[212,230,231,249],"Incorrect capture explanation for O3")
        check(try Data(contentsOf:fixture.appendingPathComponent("initial.sgf"))==initialData,"Replay altered its source fixture")
        print("PASS: \(checks) tentative-tail checks: repeated contradiction, preserved prefix and placement warning, uncertain/locked/opposite-color protection, and interrupted empty evidence.")
        return checks
    }
}
