import Foundation

@main struct MissingProvisionalReviewTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("missing-provisional-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixtures=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/MissingProvisionalReview")
        func restore(_ name:String)throws->GameRecorder {
            let folder=root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            for suffix in ["sgf","clock.json","pending.json"] {
                try FileManager.default.copyItem(at:fixtures.appendingPathComponent("game."+suffix),to:folder.appendingPathComponent("game."+suffix))
            }
            let recorder=GameRecorder(storage:folder);recorder.clock.audible=false
            try recorder.restoreSavedGame(from:folder.appendingPathComponent("game.sgf"))
            return recorder
        }
        var now=ProcessInfo.processInfo.systemUptime
        func feed(_ recorder:GameRecorder,_ board:[Occupancy],_ count:Int=1,blocked:Bool=false) {
            for _ in 0..<count {
                now+=0.21
                var observation=BoardObservation(readings:board.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:now,handObstructed:false)
                observation.lightingBlocked=blocked
                recorder.consume(observation,now:now);recorder.clock.tick(at:now)
            }
        }
        let incident=try restore("incident")
        check(incident.moveCount==8 && incident.pendingMoveCount==0 && incident.clock.provisionalMoves.map(\.number)==[9],"Fixture lost the orphaned ninth clock press")
        let board=DeferredMoveHistory.states(incident.positions.last!)
        let sgf=incident.sgf(),black=incident.clock.engine.black,white=incident.clock.engine.white
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let measured=try encoder.encode(incident.clock.moves)
        let unreviewed=try restore("unreviewed")
        check(unreviewed.resume() == .clockReview && unreviewed.clock.provisionalMoves.count==1,"Unapproved recovery silently discarded clock evidence")
        var invalid=black;invalid.remaining=0
        check(!incident.confirmClockReview(black:invalid,white:white,resume:true),"Invalid totals accepted")
        check(incident.clock.provisionalMoves.count==1 && !incident.clock.running,"Invalid review changed timing history")
        check(incident.confirmClockReview(black:black,white:white,resume:false),"Agreed totals rejected")
        check(!incident.clock.running && incident.state == .paused && incident.clock.provisionalMoves.count==1,"Save-only correction started clocks or discarded evidence before verification")
        try incident.flushStorage()
        let reopened=GameRecorder(storage:root.appendingPathComponent("incident"));reopened.clock.audible=false
        try reopened.restoreSavedGame(from:incident.autosaveURL!)
        check(!reopened.clock.requiresReview && reopened.resume() == .checking,"Restart lost approved review")
        feed(reopened,board,6,blocked:true)
        var hidden=board;hidden[0] = .uncertain
        feed(reopened,hidden,8)
        check(!reopened.clock.running && reopened.clock.provisionalMoves.count==1 && !reopened.clock.requiresReview,"Hidden corner discarded evidence or reopened review")
        feed(reopened,board,1)
        check(!reopened.clock.running && reopened.clock.provisionalMoves.count==1,"One empty view cleared a provisional press")
        check(reopened.clock.engine.black==black && reopened.clock.engine.white==white,"Waiting for verification changed agreed totals")
        feed(reopened,board,12)
        check(reopened.synchronized && reopened.clock.running && !reopened.clock.requiresReview,"Confirmed times returned to the same missing-provisional review loop")
        check(reopened.clock.engine.blackToPlay && reopened.clock.provisionalMoves.isEmpty && reopened.clock.lastTimedMove==8,"Recovery selected wrong turn or retained phantom move nine")
        check(reopened.clock.engine.white==white && reopened.clock.engine.black.remaining<=black.remaining,"Recovery changed agreed balances")
        let recoveredMeasured=try encoder.encode(reopened.clock.moves)
        check(reopened.sgf()==sgf && recoveredMeasured==measured,"Recovery changed saved game or measured presses")
        reopened.pause();try reopened.flushStorage()
        let verified=GameRecorder(storage:root.appendingPathComponent("incident"));verified.clock.audible=false
        try verified.restoreSavedGame(from:reopened.autosaveURL!)
        check(!verified.clock.requiresReview && verified.clock.provisionalMoves.isEmpty,"Restart resurrected discarded provisional press")
        check(verified.resume() == .checking,"Recovered game could not resume again")
        feed(verified,board,8)
        var played=board;played[180] = .black
        feed(verified,played,16)
        check(!verified.clock.requiresReview && verified.clock.lastTimedMove==9 && !verified.clock.engine.blackToPlay,"Next genuine move was lost, duplicated, or requested old review")
        check(verified.clock.moves.filter{$0.number==9}.count+verified.clock.provisionalMoves.filter{$0.number==9}.count==1,"Next move was charged twice")
        verified.pause()
        // A visible independent provisional stone must keep its original press.
        let present=try restore("present")
        let estimate=present.clock.provisionalMoves[0].estimate
        check(present.confirmClockReview(black:black,white:white,resume:true),"Visible-move review rejected")
        var actual=board;actual[0] = .black
        feed(present,actual,16)
        check(!present.clock.requiresReview && present.clock.lastTimedMove==9,"Visible provisional move was discarded")
        check(present.clock.running && !present.clock.engine.blackToPlay,"Visible retained move resumed the wrong player")
        let retained=(present.clock.moves+present.clock.provisionalMoves).first{$0.number==9}
        check(retained?.estimate?.time==estimate?.time,"Real provisional press lost measured evidence")
        present.pause()
        print("PASS: \(checks) missing provisional clock-review recovery checks")
    }
}
