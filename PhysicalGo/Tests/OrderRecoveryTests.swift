import AppKit

@main struct OrderRecoveryTests {
    @MainActor static func main() async throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let empty=Array(repeating:Occupancy.empty,count:81)
        var final=empty;final[10] = .black;final[20] = .white;final[30] = .black
        var frames=[ReviewOrderRecovery.Frame](),time=0.0
        func append(_ position:[Occupancy],blocked:Bool=false,count:Int=4) {
            for _ in 0..<count {time+=0.25;frames.append(.init(time:time,position:position.map(ReviewOrderRecovery.symbol),lightingBlocked:blocked))}
        }
        append(empty)
        var board=empty
        board[30] = .black;append(board,count:1) // brief early shadow
        board[30] = .empty;append(board)
        board[10] = .black;append(board,blocked:true,count:3);append(board,count:1)
        board[20] = .white;append(board,blocked:true,count:3);append(board,count:1)
        board[30] = .black;append(board)
        let result=ReviewOrderRecovery.recover(before:empty,after:final,first:.black,frames:frames)
        check(result.orders==[[10,20,30]],"Locally supported order lost during a global lighting pause")
        check(result.intervals.count==3,"Missing interval evidence")
        frames=[];time=0;append(empty);append(final)
        check(ReviewOrderRecovery.recover(before:empty,after:final,first:.black,frames:frames).orders.count==2,"Simultaneous additions were guessed")
        frames=[];time=0;append(empty);append(final,blocked:true)
        check(ReviewOrderRecovery.recover(before:empty,after:final,first:.black,frames:frames).orders.isEmpty,"Lighting-only hallucinations established an order")
        check(ReviewOrderRecovery.recover(before:empty,after:final,first:.black,frames:[]).orders.isEmpty,"Missing history guessed")
        var removed=final;removed[10] = .empty
        check(ReviewOrderRecovery.recover(before:final,after:removed,first:.white,frames:frames).orders.isEmpty,"Removal guessed as placement")
        // A sustained early false black reading followed by real empty sightings
        // must not beat the final, later placement of that black stone.
        frames=[];time=0;append(empty)
        board=empty;board[30] = .black;append(board)
        board[30] = .empty;append(board)
        board[10] = .black;append(board);board[20] = .white;append(board);board[30] = .black;append(board)
        check(ReviewOrderRecovery.recover(before:empty,after:final,first:.black,frames:frames).orders==[[10,20,30]],"Early false positive reordered actual moves")

        // Keep a compact version of the actual 22-move incident in the suite.
        let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/OrderRecoveryHistory.json"))) as! [String:Any]
        func states(_ text:String)->[Occupancy] {text.map{$0=="B" ? .black:$0=="W" ? .white:.empty}}
        let historicalFrames=(fixture["frames"] as! [[String:Any]]).map {
            ReviewOrderRecovery.Frame(time:$0["time"] as! Double,position:Array(($0["position"] as! String).utf8),lightingBlocked:$0["lightingBlocked"] as! Bool)
        }
        let historicBefore=states(fixture["before"] as! String),historicAfter=states(fixture["after"] as! String)
        let historical=ReviewOrderRecovery.recover(before:historicBefore,after:historicAfter,first:.white,frames:historicalFrames)
        check(historical.orders==[fixture["expected"] as! [Int]],"Recorded 22-move chronology regression")
        let filtered=ReviewOrderRecovery.recover(before:historicBefore,after:historicAfter,first:.white,frames:historicalFrames.filter{!$0.lightingBlocked})
        check(filtered.orders.count==2,"Historical fixture must reproduce the two-order ambiguity when locally clear evidence is discarded")

        if let path=ProcessInfo.processInfo.environment["PHYSICAL_GO_ORDER_FIXTURE"] {
            let original=URL(fileURLWithPath:path)
            let root=FileManager.default.temporaryDirectory.appendingPathComponent("order-recovery-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:root)}
            let copy=root.appendingPathComponent(original.lastPathComponent)
            for suffix in ["sgf","pending.json","clock.json","reviews.json","observations.jsonl"] {
                try FileManager.default.copyItem(at:original.deletingPathExtension().appendingPathExtension(suffix),to:copy.deletingPathExtension().appendingPathExtension(suffix))
            }
            let recorder=GameRecorder(storage:root);recorder.clock.audible=false
            try recorder.restoreSavedGame(from:copy)
            let section=recorder.reviewHistory.sections.first{!$0.committed && $0.moves==nil}!
            let beforeClock=recorder.clock.engine
            check(recorder.moveCount==41,"Unexpected fixture prefix")
            let recovered=try ReviewOrderRecovery.load(url:copy.deletingPathExtension().appendingPathExtension("observations.jsonl"),before:section.before,after:section.after,first:.white,through:section.recordedAt)
            let expected=[137,293,180,219,218,237,217,200,320,301,319,318,337,317,336,335,302,283,321,263,175,194]
            print("Historical replay: \(recovered.orders.count) orders; \(recovered.message)")
            check(recovered.orders==[expected],"Historical observations failed to establish S15, R14, S14 without user input")
            // Opening a review preserves the user's draft against background work.
            recorder.activeReviewID=section.id
            await recorder.recoverSavedReviewOrder(section.id)
            check(recorder.reviewHistory.unresolved==1,"Background recovery changed an open review")
            recorder.activeReviewID=nil
            await recorder.recoverSavedReviewOrder(section.id)
            check(recorder.reviewHistory.unresolved==0,"Unique legal order was not automatically resolved")
            check(recorder.reviewHistory.sections.last?.recoverySource != nil,"Automatic recovery provenance missing")
            check(recorder.state == .paused && !recorder.clock.running,"Recovery resumed the clock")
            check(recorder.finalizeReviews()==nil,"Recovered game did not finalize")
            check(recorder.moveCount==63 && recorder.nextPlayer == .white,"Wrong recovered count or next player")
            check(DeferredMoveHistory.states(recorder.positions.last!)==section.after,"Recovered game differs from camera snapshot")
            check(recorder.clock.engine.black==beforeClock.black && recorder.clock.engine.white==beforeClock.white,"Recovery changed either player's time")
            check(recorder.clock.engine.blackToPlay==beforeClock.blackToPlay,"Recovery changed the live turn")
            let restored=GameRecorder(storage:root);restored.clock.audible=false;try restored.restoreSavedGame(from:copy)
            check(restored.moveCount==63 && !restored.hasDeferredMoves,"Recovered game failed restart")
            check(restored.recordedMoveCount(for:.black)==32 && restored.recordedMoveCount(for:.white)==31,"Recovered player counts wrong")
            if let output=ProcessInfo.processInfo.environment["PHYSICAL_GO_ORDER_OUTPUT"] {
                let destination=URL(fileURLWithPath:output)
                try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
                for suffix in ["sgf","pending.json","clock.json","reviews.json","observations.jsonl"] {
                    try FileManager.default.copyItem(at:copy.deletingPathExtension().appendingPathExtension(suffix),to:destination.appendingPathComponent(copy.deletingPathExtension().appendingPathExtension(suffix).lastPathComponent))
                }
            }
        }
        print("Order recovery: \(checks) checks passed")
    }
}
