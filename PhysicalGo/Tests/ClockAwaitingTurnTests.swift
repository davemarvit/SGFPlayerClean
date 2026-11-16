import Foundation

@main struct ClockAwaitingTurnTests {
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("clock-awaiting-turn-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixtures=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ClockAwaitingTurn")
        for suffix in ["sgf","clock.json","pending.json"] {
            try FileManager.default.copyItem(at:fixtures.appendingPathComponent("game."+suffix),to:root.appendingPathComponent("game."+suffix))
        }
        let recorder=GameRecorder(storage:root);recorder.clock.audible=false
        try recorder.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
        check(recorder.moveCount==7 && recorder.clock.awaitingTurn && !recorder.clock.needsCorrection,"Fixture lost the recorded stale turn gate")
        check(recorder.clock.requiresReview && recorder.playFlow == .clockReview,"Unknown turn was presented as a resumable clock")
        check(recorder.resume() == .clockReview && !recorder.clock.running,"Resume silently entered an impossible board-check loop")
        let black=recorder.clock.engine.black,white=recorder.clock.engine.white
        var invalid=black;invalid.remaining=0
        check(!recorder.confirmClockReview(black:invalid,white:white,resume:true) && recorder.clock.awaitingTurn,"Invalid review cleared the turn gate")
        check(recorder.confirmClockReview(black:black,white:white,resume:false),"Agreed clock review was rejected")
        check(!recorder.clock.awaitingTurn && !recorder.clock.requiresReview && !recorder.clock.running,"Confirmed next player left clocks stuck or started before verification")
        check(recorder.clock.engine.black==black && recorder.clock.engine.white==white && !recorder.clock.engine.blackToPlay,"Clock review altered agreed time or selected the wrong player")
        try recorder.flushStorage()
        let reopened=GameRecorder(storage:root);reopened.clock.audible=false
        try reopened.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
        check(!reopened.clock.awaitingTurn && !reopened.clock.requiresReview && !reopened.clock.running,"Restart resurrected the stale gate or started the clock")
        check(reopened.resume() == .checking,"Reviewed game failed to enter board verification")
        let board=DeferredMoveHistory.states(reopened.positions.last!)
        var now=ProcessInfo.processInfo.systemUptime
        func feed(_ values:[Occupancy],count:Int=1) {
            for _ in 0..<count {
                now+=0.21
                reopened.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:now,handObstructed:false),now:now)
                reopened.clock.tick(at:now)
            }
        }
        feed(Array(repeating:.uncertain,count:361),count:3)
        check(!reopened.clock.running,"Unverified board started a corrected clock")
        feed(board,count:10)
        check(reopened.synchronized && reopened.clock.running && !reopened.clock.engine.blackToPlay,"Recorded seven-move game remained stuck after board verification")
        check(reopened.clock.engine.black==black && reopened.clock.engine.white.remaining<white.remaining,"Corrected game charged the wrong player")
        reopened.pause()
        for nextBlack in [true,false] {
            let clock=LocalGameClock();clock.audible=false
            clock.configure(.init(kind:.byoyomi,mainSeconds:120,periodSeconds:15,periods:5),blackToPlay:nextBlack)
            clock.ready(at:100);clock.holdForUnobservedTurns(lastReliableAt:102,next:nil,at:103)
            let held=clock.engine
            check(clock.awaitingTurn && clock.requiresReview && !clock.running,"Unknown turn failed to hold for review")
            check(clock.correct(black:held.black,white:held.white,blackToPlay:nextBlack,moveCount:6,at:104),"Known next player was rejected")
            clock.ready(at:105)
            check(!clock.running && !clock.awaitingTurn,"Save-only correction resumed without a request")
            clock.requestResume();clock.ready(at:106);clock.tick(at:107)
            check(clock.running && clock.engine.blackToPlay==nextBlack,"Confirmed next player could not resume")
            check(nextBlack ? clock.engine.white==held.white : clock.engine.black==held.black,"Resumed clock charged the inactive player")
            clock.pause(at:107)
        }
        // New-game configuration must discard every old review and turn gate.
        recorder.start(size:19,clockSettings:.init(kind:.byoyomi,mainSeconds:120,periodSeconds:15,periods:5),startPaused:true)
        check(recorder.moveCount==0 && recorder.awaitingFirstStart && !recorder.clock.requiresReview && !recorder.clock.awaitingTurn,"New game inherited old timing gates")
        check(!recorder.clock.running && recorder.clock.engine.black.remaining==120 && recorder.clock.engine.white.remaining==120,"New-game setup started early or inherited old balances")
        print("PASS: \(checks) recorded clock-resume and new-game checks")
    }
}
