import Foundation

@MainActor enum TentativeHistoryTests {
    static func run()throws->Int {
        var checks=0,time=0.0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        let folder=URL(fileURLWithPath:"PhysicalGo/.build/TentativeHistoryTests-\(UUID().uuidString)")
        let recorder=GameRecorder(storage:folder),empty=[Occupancy](repeating:.empty,count:81)
        func feed(_ r:GameRecorder,_ values:[Occupancy],_ frames:Int) {
            for _ in 0..<frames {time += 0.21;r.consume(BoardObservation(readings:values.enumerated().map{
                .init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)
            },size:9),now:time)}
        }
        recorder.start(size:9);feed(recorder,empty,5)
        let order=[10,20,30,40,50,60,70,12,22,32]
        var view=empty,clear=empty
        view[order[0]] = .black;clear=view;feed(recorder,view,2)
        view[order[0]] = .uncertain
        feed(recorder,view,80) // Beyond the raw observation window.
        check(recorder.moveCount==0 && recorder.pendingMoveCount==1,"Uncertain first stone lost its tentative history or reached the SGF")
        for (index,point) in order.enumerated().dropFirst() {
            view[point]=index%2==0 ? .black : .white;clear[point]=view[point]
            feed(recorder,view,2)
            check(recorder.moveCount==0,"Unresolved first move was skipped in the SGF")
            check(recorder.pendingMoveCount==index+1,"Later move was not retained behind the uncertain first stone")
        }
        feed(recorder,view,300) // A player may adjust the stone a minute later.
        check(recorder.moveCount==0 && recorder.pendingMoveCount==10,"Tentative sequence expired while the stone stayed unclear")
        check(recorder.pendingConfidence.first?.level=="low" && recorder.pendingConfidence.dropFirst().allSatisfy{$0.level=="high"},"Per-move confidence did not distinguish the obscured stone from clear later sightings")
        view[20] = .uncertain;feed(recorder,view,80)
        check(recorder.pendingConfidence[1].level=="high" && recorder.pendingConfidence[1].point==20,"Settled pending assignment became uncertain again after a later obstruction")
        check(recorder.interpretedBoard?.grid[1][1] == .black,"Best-estimate board lost the obscured first stone")
        check(recorder.lastInterpretedPoint==order.last,"Latest interpreted move marker trails the confirmed SGF")
        check(recorder.retainingTentativeMoves && recorder.tentativeNextPlayer == .black,"Tentative activity/turn indicator follows the confirmed prefix instead of the retained game")
        check(recorder.status.contains("tentative") && recorder.status.contains("SGF waits"),"UI did not distinguish retained moves from confirmed SGF")
        let journal=recorder.autosaveURL!.deletingPathExtension().appendingPathExtension("observations.jsonl")
        let rows=try String(contentsOf:journal,encoding:.utf8).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }
        let last=rows.last!
        check((last["tentativeSequences"] as? [[Int]])==[order],"Local journal did not preserve the tentative move order")
        check(Array(last["position"] as! String)[10]=="?","Internal format lost the uncertain intersection")
        check((last["bufferedFrames"] as! Int)<=64 && (last["retainedWitnesses"] as! Int)<=84,"Compact history grew with every old frame")
        check(try SGFGame.from(tree:SGFParser.parse(text:String(contentsOf:recorder.autosaveURL!,encoding:.utf8))).moves.isEmpty,"Unconfirmed moves leaked into autosaved SGF")
        feed(recorder,clear,4)
        check(recorder.moveCount==0,"An old ordering witness counted as fresh confirmation")
        feed(recorder,clear,1)
        check(recorder.game.moves.compactMap{$0.1.map{$0.1*9+$0.0}}==order,"Tidying the stone did not complete the exact retained sequence")
        check(recorder.lastInterpretedPoint==order.last,"Last-move marker disappeared when tentative moves became confirmed")
        check(recorder.pendingMoveCount==0 && recorder.localEvidenceRunCount==0,"Resolved history was not cleared from memory")
        check(try SGFGame.from(tree:SGFParser.parse(text:String(contentsOf:recorder.autosaveURL!,encoding:.utf8))).moves.count==10,"Resolved moves did not reach autosaved SGF")
        for index in 0...10 {recorder.seek(index);check(recorder.reviewedBoard==recorder.positions[index],"Tentative recovery lost review position \(index)")}

        // Clear contradiction and wrong turn cannot be hidden behind uncertainty.
        let wrong=GameRecorder(storage:nil);wrong.start(size:9);feed(wrong,empty,5)
        var first=empty;first[10] = .black;feed(wrong,first,2)
        first[10] = .uncertain;first[30] = .black;feed(wrong,first,90)
        check(wrong.moveCount==0,"A later black replaced an obscured earlier black")
        let accepted=GameRecorder(storage:nil);accepted.start(size:9);feed(accepted,empty,5)
        var base=empty;base[10] = .black;feed(accepted,base,5)
        base[10] = .uncertain;base[20] = .white;feed(accepted,base,2)
        base[30] = .black;feed(accepted,base,80)
        check(accepted.game.moves.first?.1?.0==1 && accepted.game.moves.first?.1?.1==1,"A later uncertain view changed an already confirmed move")
        // History-first recognition retains an accepted stone through uncertainty;
        // fresh evidence for later moves can confirm without re-seeing that stone.
        check(accepted.moveCount==3 && accepted.pendingMoveCount==0 &&
              accepted.game.moves.compactMap{$0.1.map{$0.1*9+$0.0}}==[10,20,30],
              "An obscured accepted stone blocked later confirmed moves or changed their order")
        base[10] = .black;feed(accepted,base,5)
        check(accepted.moveCount==3,"Restoring the accepted stone did not confirm later moves")
        let paused=GameRecorder(storage:nil);paused.start(size:9);feed(paused,empty,5)
        var before=empty;before[10] = .black;feed(paused,before,2)
        before[10] = .uncertain;before[20] = .white;feed(paused,before,2)
        paused.pause();check(paused.pendingMoveCount==2,"Pause discarded compact tentative moves")
        paused.resume();before[10] = .black;feed(paused,before,7)
        check(paused.moveCount==0,"Resume reused old confirmation frames")
        feed(paused,before,1);check(paused.moveCount==2,"Resume could not resolve retained tentative moves")
        let ending=GameRecorder(storage:nil);ending.start(size:9);feed(ending,empty,5)
        var endView=empty;endView[10] = .black;feed(ending,endView,2)
        endView[10] = .uncertain;endView[20] = .white;feed(ending,endView,5)
        ending.finish()
        check(ending.state == .paused && ending.pendingMoveCount==2 && ending.status.contains("Not finished"),"Finish discarded unresolved moves instead of explaining how to settle them")
        ending.resume();endView[10] = .black;feed(ending,endView,8);ending.finish()
        check(ending.state == .finished && ending.moveCount==2,"Resolved game could not finish with its complete history")
        let edited=GameRecorder(storage:nil);edited.start(size:9);feed(edited,empty,5)
        var pending=empty;pending[10] = .black;feed(edited,pending,2);edited.pause()
        edited.manualMove(at:BoardPosition(0,0));edited.resume()
        check(edited.pendingMoveCount==0,"Manual correction retained a hypothesis based on the old SGF")
        print("PASS: \(checks) tentative-history checks: minute-long uncertainty, ten later moves, bounded evidence, internal journal, fresh confirmation, legal chronology, review and SGF.")
        checks += PlacementConfidenceTests.run()
        return checks
    }
}
