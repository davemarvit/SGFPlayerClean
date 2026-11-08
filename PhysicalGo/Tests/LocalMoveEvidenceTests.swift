import Foundation

@MainActor enum LocalMoveEvidenceTests {
    static func run() throws ->Int {
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        let empty=[Occupancy](repeating:.empty,count:81)
        let a=10,b=20,c=30
        var values=empty, buffer=LocalMoveEvidence(),now=0.0
        func send(_ states:[Occupancy],_ count:Int=1) {
            for _ in 0..<count {now += 0.21;buffer.observe(states,base:empty,now:now)}
        }
        values[a] = .black
        send(values,2)
        let compressed=buffer.runCount
        send(values,20)
        check(buffer.runCount==compressed && buffer.sampleCount==81*22,"Repeated local readings were not compressed with repetition counts")
        let samples=buffer.sampleCount
        buffer.observe(values,base:empty,now:now)
        check(buffer.sampleCount==samples,"Duplicate timestamp contributed local evidence")
        values[b] = .white;send(values,2)
        values[c] = .black;send(values,2)
        check(buffer.uniqueOrder(additions:[c,b,a],readings:values,blackToPlay:true)==[a,b,c],"Repeated early stone / later empty evidence lost chronology")
        buffer.reset();now=0
        send(values,8)
        check(buffer.uniqueOrder(additions:[a,b,c],readings:values,blackToPlay:true)==nil,"Simultaneous stones invented an order")
        buffer.reset();now=0
        var early=empty;early[a] = .black
        send(early);send(values,8)
        check(buffer.uniqueOrder(additions:[a,b,c],readings:values,blackToPlay:true)==nil,"Single-frame stone ordered three moves")
        buffer.reset();now=0
        send(early,2);send(empty);send(values,8)
        check(buffer.uniqueOrder(additions:[a,b,c],readings:values,blackToPlay:true)==nil,"Contradicted early sighting still ordered the sequence")
        buffer.reset();now=0
        // Unknown at the later point is NOT evidence that it was empty.
        early[b] = .uncertain;early[c] = .uncertain;send(early,4);send(values,8)
        check(buffer.uniqueOrder(additions:[a,b,c],readings:values,blackToPlay:true)==nil,"Unknown location was treated as empty for ordering")
        buffer.reset();now=0
        early[b] = .empty;early[c] = .empty;send(early,2)
        var hidden=early;hidden[a] = .uncertain;send(hidden,65);send(values,8)
        check(buffer.uniqueOrder(additions:[a,b,c],readings:values,blackToPlay:true)==nil && buffer.expiredPoints.contains(a),"Expired evidence silently reordered moves")
        for i in 0..<200 {now += 0.001;buffer.observe(i%2==0 ? values : empty,base:empty,now:now)}
        check(buffer.points.allSatisfy{$0.count<=LocalMoveEvidence.maximumRunsPerPoint},"Rapid changes exceeded evidence storage limit")
        buffer.reset();check(buffer.runCount==0 && buffer.expiredPoints.isEmpty,"Reset retained temporary evidence")
        // A hand's contradicted color error must not poison a real move at the
        // same point later, when the old episode leaves the retention window.
        buffer.reset();now=0
        var oldGhost=empty;oldGhost[c] = .black
        send(oldGhost,2);send(empty,62)
        check(!buffer.expiredPoints.contains(c),"Disproved old ghost still expired the coordinate")
        var fresh=empty;fresh[a] = .black;send(fresh,2)
        fresh[b] = .white;send(fresh,2);fresh[c] = .black;send(fresh,2)
        check(buffer.uniqueOrder(additions:[a,b,c],readings:fresh,blackToPlay:true)==[a,b,c],"Old false stone poisoned a new uniquely ordered sequence")


        func observation(_ states:[Occupancy],size:Int)->BoardObservation {
            BoardObservation(readings:states.enumerated().map{i,v in IntersectionReading(row:i/size,col:i%size,occupancy:v,confidence:1,delta:0)},size:size)
        }
        var time=0.0
        func recorder()->GameRecorder {
            let r=GameRecorder(storage:nil);r.start(size:9)
            for _ in 0..<5 {time += 0.21;r.consume(observation(empty,size:9),now:time)}
            return r
        }
        func feed(_ r:GameRecorder,_ states:[Occupancy],_ count:Int) {
            for _ in 0..<count {time += 0.21;r.consume(observation(states,size:9),now:time)}
        }
        // No whole-board witness exists for the intermediate positions. An
        // isolated ghost elsewhere must not become a move or erase the evidence.
        let r=recorder()
        var noisy=empty;noisy[a] = .black
        for i in 50..<70 {noisy[i] = .uncertain}
        feed(r,noisy,2);noisy[40] = .white;feed(r,noisy,1);noisy[40] = .empty
        noisy[b] = .white;feed(r,noisy,2);noisy[c] = .black;feed(r,noisy,3)
        check(r.moveCount==0 && r.localEvidenceRunCount>0,"Noisy local evidence committed before a clear final view")
        feed(r,values,7);check(r.moveCount==0,"Local sequence bypassed fresh final-position confirmation")
        feed(r,values,1)
        check(r.moveCount==3 && r.game.moves.compactMap{$0.1.map{$0.1*9+$0.0}}==[a,b,c],"Local evidence did not recover the legal sequence or saved a ghost")
        check(r.localEvidenceRunCount==0 && r.pendingMoveCount==0,"Caught-up recorder retained resolved evidence")
        check(r.positions.count==4 && r.positions[1].grid[1][1] == .black && r.positions[1].grid[2][2]==nil,"Recovered review positions skipped an intermediate board")
        r.seek(1);check(r.reviewedBoard==r.positions[1],"Recovered moves cannot be reviewed")
        check(try SGFGame.from(tree:SGFParser.parse(text:r.sgf())).moves.count==3,"Recovered SGF is not parseable")

        // Keep an existing full-position prefix, then bridge later moves whose
        // intermediate boards were obscured elsewhere. Eight fresh final views
        // are still required; neither a one-frame position nor turn order suffices.
        let bridge=recorder()
        var prefix=empty;prefix[a] = .black;feed(bridge,prefix,2)
        var partial=prefix
        for i in 50..<70 {partial[i] = .uncertain}
        partial[b] = .white;feed(bridge,partial,2)
        partial[c] = .black;feed(bridge,partial,2)
        partial[40] = .white;feed(bridge,partial,2)
        var complete=values;complete[40] = .white
        feed(bridge,complete,7)
        check(bridge.moveCount==0,"Local continuation bypassed eight fresh confirmation views")
        feed(bridge,complete,1)
        check(bridge.game.moves.compactMap{$0.1.map{$0.1*9+$0.0}}==[a,b,c,40],"Existing prefix prevented a uniquely witnessed local continuation")
        check(bridge.localEvidenceRunCount==0 && bridge.pendingMoveCount==0,"Bridge retained evidence after catching up")

        // Missing accepted stones, illegal placements, new camera coordinates,
        // pause/review and expiry must not be bypassed by the new fallback.
        let reset=recorder();var n=noisy;n[b] = .empty;n[c] = .empty
        feed(reset,n,2);reset.suspendVision("New grid")
        feed(reset,values,12);check(reset.moveCount==0,"New grid reused per-point chronology")
        let paused=recorder();feed(paused,n,2);paused.pause();paused.resume()
        feed(paused,values,12);check(paused.moveCount==0,"Pause retained per-point chronology")
        let missing=recorder();var original=empty;original[0] = .black;feed(missing,original,5)
        var whiteFirst=original;whiteFirst[a] = .white
        for i in 50..<70 {whiteFirst[i] = .uncertain}
        feed(missing,whiteFirst,2);whiteFirst[b] = .black;feed(missing,whiteFirst,2);whiteFirst[c] = .white;feed(missing,whiteFirst,2)
        var final=original;final[a] = .white;final[b] = .black;final[c] = .white;final[0] = .uncertain
        feed(missing,final,10);check(missing.moveCount==4,"An obscured recorded stone blocked a locally witnessed legal sequence")
        final[0] = .black;feed(missing,final,8);check(missing.moveCount==4,"Visible recorded stone could not complete a locally ordered sequence")

        let hiddenFirst=recorder()
        feed(hiddenFirst,n,2)
        var obscured=values;obscured[a] = .uncertain;obscured[b] = .uncertain
        feed(hiddenFirst,obscured,8)
        check(hiddenFirst.moveCount==0,"Later Black replaced an earlier locally observed but obscured Black")
        feed(hiddenFirst,values,8)
        check(hiddenFirst.moveCount==3 && hiddenFirst.game.moves.first?.1?.0==a%9,"Clearing the earlier stone lost its local chronology")

        // A unique temporal order cannot authorize suicide. White's final point
        // is surrounded by already accepted Black stones with outside liberties.
        let illegal=recorder();illegal.pause()
        for point in [1,80,9,79,19,78,11] {illegal.manualMove(at:BoardPosition(point/9,point%9))}
        check(illegal.moveCount==7,"Illegal-sequence fixture setup failed")
        illegal.resume()
        let baseline=illegal.positions.last!.grid.flatMap{$0}.map{$0 == .black ? Occupancy.black : $0 == .white ? .white : .empty}
        feed(illegal,baseline,5)
        var suicide=baseline;suicide[10] = .white
        for i in 50..<70 {suicide[i] = .uncertain}
        feed(illegal,suicide,2);suicide[30] = .black;feed(illegal,suicide,2);suicide[40] = .white;feed(illegal,suicide,2)
        for i in 50..<70 {suicide[i] = baseline[i]}
        feed(illegal,suicide,10)
        check(illegal.moveCount==7,"Local chronology bypassed legal-move validation")

        let fixture=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures/LocalEvidenceStall/observations.jsonl")
        let rows=try String(contentsOf:fixture,encoding:.utf8).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }.filter{$0["event"] as? String == "observation"}
        let first=rows[0]["uptime"] as! Double
        let replay=GameRecorder(storage:nil),blank=[Occupancy](repeating:.empty,count:361)
        for offset in stride(from:1.05,through:0.21,by:-0.21) {replay.consume(observation(blank,size:19),now:first-offset)}
        replay.start(size:19,now:first-0.01)
        check(replay.state == .recording,"Replay did not reproduce pre-recording empty-board verification")
        var recoveredAt:Double?,beforeNoisy=0
        for row in rows {
            let now=row["uptime"] as! Double
            if row["state"] as? String == "paused" {replay.pause()}
            let states=(row["position"] as! String).map{$0 == "B" ? Occupancy.black : $0 == "W" ? .white : $0 == "?" ? .uncertain : .empty}
            replay.consume(observation(states,size:19),now:now)
            if now-first<36.5 {beforeNoisy=max(beforeNoisy,replay.moveCount)}
            if replay.moveCount==5 && recoveredAt==nil {recoveredAt=now-first}
        }
        check(beforeNoisy==2,"Actual noisy frames invented moves before the board cleared")
        check(replay.moveCount==5,"Latest stalled session did not recover exactly five moves")
        check(replay.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}==[300,60,287,289,308],"Actual replay chose an unsupported move order")
        check(recoveredAt != nil && recoveredAt!<40,"Actual recovery failed to finish promptly after the clear final view")
        check(replay.localEvidenceRunCount==0 && !replay.needsAttention,"Actual recovery retained temporary evidence or warning state")
        // Remove intermediate evidence: identical final position must remain
        // ambiguous. Swap the two Black locations: order must follow evidence,
        // never row/column sorting or an expectation hard-coded to this sample.
        func alteredReplay(maskEarly:Bool,swapBlack:Bool)->GameRecorder {
            let r=GameRecorder(storage:nil)
            for offset in stride(from:1.05,through:0.21,by:-0.21) {r.consume(observation(blank,size:19),now:first-offset)}
            r.start(size:19,now:first-0.01)
            for row in rows where row["state"] as? String != "paused" {
                let now=row["uptime"] as! Double
                var states=(row["position"] as! String).map{$0 == "B" ? Occupancy.black : $0 == "W" ? .white : $0 == "?" ? .uncertain : .empty}
                if maskEarly && now-first<36.8 {for point in [287,289,308] {states[point] = .uncertain}}
                if swapBlack {states.swapAt(287,308)}
                r.consume(observation(states,size:19),now:now)
            }
            return r
        }
        check(alteredReplay(maskEarly:true,swapBlack:false).moveCount==2,"Replay without intermediate evidence guessed the same final three-stone order")
        check(alteredReplay(maskEarly:false,swapBlack:true).game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}==[300,60,308,289,287],"Replay order followed coordinates rather than evidence")
        let output=fixture.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/LocalEvidenceReplay.sgf")
        try replay.sgf().write(to:output,atomically:true,encoding:.utf8)
        print("Latest stalled-session replay: 2 → \(replay.moveCount) saved moves at \(String(format: "%.1f",recoveredAt ?? -1)) s; sequence B[pp] W[dd] B[cp] W[ep] B[eq].")
        print("PASS: \(checks) local-evidence checks: compression, bounded retention, ambiguity, contradictions, expiry, final confirmation, review, reset, and actual-session replay.")
        return checks
    }
}
