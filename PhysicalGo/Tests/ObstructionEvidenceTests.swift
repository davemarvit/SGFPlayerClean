import Foundation

@MainActor enum ObstructionEvidenceTests {
    static func run()->Int {
        var checks=0,time=0.0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        func view(_ values:[Occupancy])->BoardObservation {
            let size=Int(Double(values.count).squareRoot())
            return .init(readings:values.enumerated().map{.init(row:$0.offset/size,col:$0.offset%size,occupancy:$0.element,confidence:1,delta:0)},size:size)
        }
        func feed(_ recorder:GameRecorder,_ values:[Occupancy],_ count:Int) {
            for _ in 0..<count {time += 0.21;recorder.consume(view(values),now:time)}
        }
        let empty=[Occupancy](repeating:.empty,count:81)
        func fresh()->GameRecorder {let r=GameRecorder(storage:nil);r.start(size:9);feed(r,empty,5);return r}
        let phantom=fresh()
        var obstructed=empty;obstructed[10] = .black
        for p in 50..<70 {obstructed[p] = .black}
        feed(phantom,obstructed,4)
        check(phantom.moveCount==0,"Broad obstruction became a move")
        var clear=empty;clear[10] = .uncertain;clear[30] = .black
        feed(phantom,clear,8)
        check(phantom.moveCount==1 && phantom.game.moves.first?.1?.0==3 && phantom.game.moves.first?.1?.1==3,"An obstruction-only phantom blocked the real move")
        check(clear[10] == .uncertain,"Test must leave the phantom unresolved rather than invent empty evidence")
        // Raw chronology must survive the obstruction guard: the second player
        // can play before the first hand is fully withdrawn.
        let rapid=fresh()
        var broad=empty
        for p in 50..<70 {broad[p] = .black}
        broad[10] = .black;feed(rapid,broad,2)
        broad[20] = .white;feed(rapid,broad,2)
        broad[30] = .black;feed(rapid,broad,2)
        check(rapid.moveCount==0 && rapid.localEvidenceRunCount>0,"Obstructed views confirmed moves or discarded raw order")
        var final=empty;final[10] = .black;final[20] = .white;final[30] = .black
        feed(rapid,final,8)
        check(rapid.game.moves.compactMap{$0.1.map{$0.1*9+$0.0}}==[10,20,30],"Settling lost the observed rapid-play order")

        // A mature position may retain two known identities through local
        // uncertainty, while definite absence still blocks.
        func mature()->(GameRecorder,[Occupancy]) {
            let r=GameRecorder(storage:nil);r.start(size:19);r.pause()
            for i in 0..<20 {r.manualMove(at:.init(2+(i/5)*3,2+(i%5)*3))}
            check(r.moveCount==20,"Invalid mature-board fixture")
            r.resume()
            let base=r.positions.last!.grid.flatMap{$0}.map{$0 == .black ? Occupancy.black : $0 == .white ? .white : .empty}
            feed(r,base,5);return (r,base)
        }
        let old=[40,43,46]
        let (retained,base)=mature()
        var local=base;local[old[0]] = .uncertain;local[old[1]] = .uncertain;local[340] = .black
        feed(retained,local,5)
        check(retained.moveCount==21 && retained.positions.last!.grid[2][2] == .black,"Small old-stone occlusions reopened confirmed identities")
        feed(retained,local,5)
        check(retained.moveCount==21 && retained.synchronized && retained.canPass,"Resting confirmed position could not remain synchronized")
        let (missing,missingBase)=mature()
        var absent=missingBase;absent[old[0]] = .empty;absent[340] = .black;feed(missing,absent,12)
        check(missing.moveCount==20,"Definite disappearance of an old stone was ignored")
        absent[341] = .white;feed(missing,absent,2)
        absent[322] = .black;feed(missing,absent,8)
        check(missing.moveCount==20 && missing.pendingConfidence.compactMap(\.point)==[340,341,322],"A recorded-stone disagreement lost later visible chronology or allowed SGF confirmation")
        absent[old[0]]=missingBase[old[0]];feed(missing,absent,10)
        check(missing.moveCount==23 && missing.pendingMoveCount==0 && missing.game.moves.suffix(3).compactMap{$0.1.map{$0.1*19+$0.0}}==[340,341,322],"Restoring the recorded stone failed to confirm the retained legal sequence")
        let (lost,lostBase)=mature()
        var broadLoss=lostBase
        for point in old.prefix(3) {broadLoss[point] = .empty}
        broadLoss[340] = .black;feed(lost,broadLoss,12)
        check(lost.moveCount==20 && lost.pendingMoveCount==0,"Broad disappearance was treated as a local retained identity")
        let (covered,coveredBase)=mature()
        var hidden=coveredBase;for point in old {hidden[point] = .uncertain};hidden[340] = .black;feed(covered,hidden,12)
        check(covered.moveCount==21,"Unreadable older identities blocked a directly observed move")
        let (newUnknown,newBase)=mature()
        var unread=newBase;unread[340] = .uncertain;feed(newUnknown,unread,10)
        check(newUnknown.moveCount==20,"Unknown new stone was inferred from history")
        // Capture evidence: an old black stone at the corner is legally captured
        // by White at B19. History must not stand in for its physical removal.
        let capture=GameRecorder(storage:nil);capture.start(size:19);capture.pause()
        let setup=[0,19,100,102,104,106,108,110,112,114,116]
        for p in setup {capture.manualMove(at:.init(p/19,p%19))}
        check(capture.moveCount==11,"Capture fixture failed")
        capture.resume()
        let captureBase=capture.positions.last!.grid.flatMap{$0}.map{$0 == .black ? Occupancy.black : $0 == .white ? .white : .empty}
        feed(capture,captureBase,5)
        var waiting=captureBase;waiting[1] = .white;waiting[0] = .uncertain;feed(capture,waiting,10)
        check(capture.moveCount==11,"Capture removed an old stone without visible removal")
        waiting[0] = .empty;feed(capture,waiting,8)
        check(capture.moveCount==12 && capture.positions.last!.grid[0][0]==nil,"Verified capture could not finish")
        // On a crowded board, distant uncertain OLD identities need not delay
        // one directly observed move, including unchanged nearby neighbors.
        func crowded()->(GameRecorder,[Occupancy]) {
            let r=GameRecorder(storage:nil);r.start(size:19);r.pause()
            for i in 0..<60 {r.manualMove(at:.init(1+(i/9)*2,1+(i%9)*2))}
            check(r.moveCount==60,"Invalid crowded-board fixture")
            r.resume()
            let board=r.positions.last!.grid.flatMap{$0}.map{$0 == .black ? Occupancy.black:$0 == .white ? .white:.empty}
            feed(r,board,5);return (r,board)
        }
        let (distant,filled)=crowded()
        var remote=filled
        for p in [20,22,24,26] {remote[p] = .uncertain}
        remote[340] = .black;feed(distant,remote,5)
        check(distant.moveCount==61,"Four remote old stones stalled a clear move on a 60-stone board")
        let (nearby,nearBase)=crowded();var near=nearBase
        for p in [20,22,24,26] {near[p] = .uncertain}
        near[21] = .black;feed(nearby,near,8)
        check(nearby.moveCount==61,"Unreadable unchanged neighbors blocked a directly observed noncapture")
        let (wide,wideBase)=crowded();var wider=wideBase
        for p in [20,22,24,26,28,30,32] {wider[p] = .uncertain}
        wider[340] = .black;feed(wide,wider,8)
        check(wide.moveCount==61,"Seven obscured old stones reopened confirmed history")
        print("PASS: \(checks) obstruction/confirmed-history checks: phantom isolation, retained rapid chronology, retained old-stone identities, missing stones, and capture removal.")
        return checks
    }
}
