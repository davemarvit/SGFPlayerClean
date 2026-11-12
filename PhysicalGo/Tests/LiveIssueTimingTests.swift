import Foundation

@MainActor enum LiveIssueTimingTests {
    static func run() throws -> Int {
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("issue-timing-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var now=ProcessInfo.processInfo.systemUptime
        func view(_ values:[Occupancy],hand:Bool?)->BoardObservation {
            .init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:now,handObstructed:hand)
        }
        let gap=GameRecorder(storage:root);gap.clock.audible=false
        gap.start(size:9,now:now,clockSettings:.init(kind:.fischer,mainSeconds:100,incrementSeconds:5,maximumSeconds:200))
        var board=Array(repeating:Occupancy.empty,count:81)
        for _ in 0..<7 {now += 0.21;gap.consume(view(board,hand:nil),now:now)}
        let reliable=now,start=gap.clock.engine.anchor!,initial=gap.clock.engine.black.remaining
        board[10] = .black;board[20] = .white;board[30] = .black
        for _ in 0..<8 {now += 0.21;gap.consume(view(board,hand:nil),now:now)}
        check(gap.hasDeferredMoves && gap.clock.requiresReview && !gap.clock.running,"Static board and alternation invented trustworthy timing")
        check(abs(gap.clock.engine.black.remaining-(initial-(reliable-start)))<0.001,"Missing-turn hold charged the unobserved interval")
        check(gap.clock.moves.isEmpty && gap.clock.provisionalMoves.isEmpty,"Missing turns invented increments or presses")
        let stopped=gap.clock.engine
        let presentation=ReviewPresentation(),id=gap.reviewHistory.reviews[0].id
        presentation.open(recorder:gap,id:id,orientation:.init(0));presentation.close()
        check(gap.clock.engine==stopped && gap.clock.requiresReview,"Inspection replaced the missing-timing hold")
        gap.confirmLiveTurn(.white,at:now)
        check(!gap.clock.running && gap.clock.requiresReview,"Turn selection alone erased missing time")
        gap.pause();try gap.flushStorage()
        let reopened=GameRecorder(storage:root);reopened.clock.audible=false
        try reopened.restoreSavedGame(from:gap.autosaveURL!)
        check(reopened.clock.requiresReview && reopened.clock.engine.black==gap.clock.engine.black,"Restart lost the timing hold or balances")

        // Three independently observed turns can be assigned to SGF without
        // another clock review, press, increment, or period reset.
        let known=GameRecorder(storage:root);known.clock.audible=false
        known.start(size:9,now:now,clockSettings:.init(kind:.fischer,mainSeconds:100,incrementSeconds:5,maximumSeconds:200))
        board=Array(repeating:.empty,count:81)
        func feedKnown(_ count:Int) {
            for _ in 0..<count {
                now += 0.21
                let shapes:[StoneFootprint]=board[10] == .black ? [.init(row:1,col:1,center:.init(x:1.49,y:1),radiusCol:0.46,radiusRow:0.46,quality:0.99)]:[]
                known.consume(.init(readings:view(board,hand:false).readings,size:9,footprints:shapes,capturedAt:now,handObstructed:false),now:now)
            }
        }
        feedKnown(7)
        for (point,color) in [(10,Occupancy.black),(50,.white),(70,.black)] {board[point]=color;feedKnown(8)}
        check(known.clock.provisionalMoves.count==3 && !known.clock.requiresReview,"Known timing fixture failed")
        let events=known.clock.provisionalMoves
        var draft=MoveRecoveryDraft(recorder:known,observation:nil)
        // Confirm one complete legal assignment when geometry kept alternatives.
        draft.clear()
        for point in [10,50,70] {_=draft.add(.init(point/9,point%9),checkCameraColor:false)}
        check(known.approveRecovery(draft)==nil,"Timed recovery rejected a retained legal assignment")
        check(!known.clock.requiresReview && !known.clock.running,"Known timed turns unnecessarily required clock correction")
        check(known.clock.moves.count==3 && known.clock.provisionalMoves.isEmpty,"Timed recovery duplicated or dropped a press")
        check(zip(known.clock.moves,events).allSatisfy{$0.before==$1.before && $0.after==$1.after && $0.estimate==$1.estimate},"Assignment changed retained clock balances or boundaries")
        let before=known.clock.engine
        check(known.approveRecovery(draft) != nil && known.clock.engine==before,"Duplicate timed recovery changed clocks")
        try known.flushStorage()
        let saved=GameRecorder(storage:root);saved.clock.audible=false;try saved.restoreSavedGame(from:known.autosaveURL!)
        check(saved.moveCount==3 && saved.clock.moves.count==3 && !saved.clock.requiresReview && !saved.clock.running,"Timed assignment failed restart")
        let expiry=LocalGameClock();expiry.audible=false
        expiry.configure(.init(kind:.absolute,mainSeconds:3),blackToPlay:true);expiry.ready(at:100)
        expiry.pendingUnaccountedInterval=101
        expiry.tick(at:104)
        check(expiry.requiresReview && expiry.engine.expiredBlack==nil && expiry.engine.black.remaining==2,"Unaccounted turns crossed expiry into an automatic loss")
        check(expiry.moves.isEmpty && expiry.provisionalMoves.isEmpty,"Timing-gap protection invented a press")
        return checks
    }
}
