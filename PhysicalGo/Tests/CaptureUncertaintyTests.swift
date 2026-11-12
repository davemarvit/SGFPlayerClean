import Foundation

enum CaptureUncertaintyTests {
    struct Frame:Decodable {let time:Double;let position:String}
    struct Fixture:Decodable {
        let baseMove:Int;let capturePoint:Int;let captured:Set<Int>
        let firstPartialTime:Double;let firstCompleteTime:Double;let frames:[Frame]
    }
    @MainActor static func run() throws -> Int {
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;precondition(ok,message)}
        func near(_ a:Double,_ b:Double)->Bool {abs(a-b)<0.00001}
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CaptureUncertainty")
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:folder.appendingPathComponent("observations.json")))
        let sgf=try String(contentsOf:folder.appendingPathComponent("before.sgf"),encoding:.utf8)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("capture-uncertainty-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        func decode(_ text:String)->[Occupancy] {
            text.map {switch $0 {case ".":return .empty;case "B":return .black;case "W":return .white;case "?":return .uncertain;default:preconditionFailure("Invalid fixture")}}
        }
        var now=ProcessInfo.processInfo.systemUptime
        func observation(_ values:[Occupancy],confidence:Double=1)->BoardObservation {
            .init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:confidence,delta:0)},size:19,capturedAt:now,handObstructed:false)
        }
        func feed(_ r:GameRecorder,_ values:[Occupancy],count:Int=1,confidence:Double=1) {
            for _ in 0..<count {
                now += 0.21;r.consume(observation(values,confidence:confidence),now:now)
                r.clock.tick(at:now)
            }
        }
        func make(verify:Bool=true)throws->GameRecorder {
            let file=root.appendingPathComponent(UUID().uuidString+".sgf")
            try sgf.write(to:file,atomically:true,encoding:.utf8)
            let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file)
            r.attachClock(.init(kind:.absolute,mainSeconds:300,automaticCaptureMinimum:2));r.resume()
            if verify {feed(r,DeferredMoveHistory.states(r.positions.last!),count:5)}
            return r
        }
        // Replay the captured classifications and cadence, without smoothing
        // the alternating uncertainty which caused the original failure.
        let recorded=try make(verify:false),epoch=now
        var baseline:LocalClockEngine?,pauseTime:Double?,held:LocalClockEngine?
        var announcements=[String]();recorded.clock.onResumeAnnouncement={announcements.append($0)}
        for frame in fixture.frames {
            let next=epoch+frame.time
            if next-now>1.5 {
                while next-now>0.4 {now += 0.4;recorded.noteHandObstruction(now:now)}
            }
            now=next;recorded.consume(observation(decode(frame.position)),now:now)
            recorded.clock.tick(at:now)
            if baseline==nil && recorded.clock.running {baseline=recorded.clock.engine}
            if recorded.clock.automaticCapturePaused {
                if pauseTime==nil {pauseTime=now;held=recorded.clock.engine}
                check(recorded.clock.engine.black==held!.black && recorded.clock.engine.white==held!.white,"Recorded removal charged time during hold")
                check(recorded.moveCount==fixture.baseMove,"Recorded removal saved the move before prisoners were verified")
            }
        }
        check(pauseTime != nil,"Recorded six-stone capture never paused: unrelated uncertainty erased its evidence")
        check(pauseTime!<epoch+fixture.firstCompleteTime,"Capture pause waited until all prisoners were gone")
        check(recorded.moveCount==fixture.baseMove+1 && recorded.nextPlayer == .black && !recorded.hasDeferredMoves,"Recorded capture was lost, duplicated or sent to chronology review")
        check(recorded.clock.running && !recorded.clock.automaticCapturePaused,"Recorded capture did not restart the opponent clock")
        check(near(recorded.clock.engine.white.remaining,baseline!.white.remaining-(epoch+fixture.firstPartialTime-baseline!.anchor!)),"Recorded pause did not rewind to the first partial-capture view")
        check(near(recorded.clock.engine.black.remaining,300-(now-epoch-fixture.firstCompleteTime)),"Recorded completion did not charge verification delay to Black")
        check(announcements==["Capture complete. Clocks resumed. Black to play."],"Recorded capture completion announcement missing or duplicated")
        recorded.pause()

        let game=SGFGame.from(tree:try SGFParser.parse(text:sgf))
        let clean=decode(fixture.frames.first{ $0.time>fixture.firstPartialTime && !$0.position.contains("?") }!.position)
        let plan=AutomaticCapture.find(game:game,readings:clean,minimum:2)!
        check(plan.point==fixture.capturePoint && plan.captured==fixture.captured,"Recorded fixture has the wrong legal capture")
        let outsideEmpty=plan.before.indices.first{plan.before[$0] == .empty && $0 != plan.point}!
        let outsideStone=plan.before.indices.first{plan.before[$0].stone != nil && !plan.captured.contains($0)}!
        var uncertain=clean;uncertain[outsideEmpty] = .uncertain;uncertain[outsideStone] = .uncertain
        let tolerant=AutomaticCapture.find(game:game,readings:uncertain,minimum:2)
        check(tolerant != nil && plan.matchesRemoval(uncertain),"Unchanged uncertain points rejected a visible capture")
        check(tolerant?.source==clean,"Persisted capture plan lost the unchanged legal position")
        check(uncertain[outsideEmpty] == .uncertain && uncertain[outsideStone] == .uncertain,"Capture matching changed camera evidence")

        // A single initial glimpse must survive hand re-entry and confirm from
        // completed views with unrelated uncertainty, preserving both boundaries.
        let quick=try make(),quickStart=quick.clock.engine
        feed(quick,uncertain);let first=now
        for _ in 0..<5 {now += 0.4;quick.noteHandObstruction(now:now)}
        var final=plan.target;final[outsideEmpty] = .uncertain
        let firstFinal=now+0.21;feed(quick,final,count:6)
        check(quick.moveCount==fixture.baseMove+1 && quick.clock.running,"Uncertain final views lost the initial partial capture")
        check(near(quick.clock.engine.white.remaining,quickStart.white.remaining-(first-quickStart.anchor!)),"Uncertain final views lost the original pause time")
        check(near(quick.clock.engine.black.remaining,300-(now-firstFinal)),"Uncertain final views lost the first completion time")
        quick.pause()

        var conflicts=[(String,[Occupancy])]()
        for name in ["extra stone","missing stone","wrong color","bumped stone","capture withdrawn","uncertain capturing stone","uncertain prisoner","replacement prisoner","broad obstruction"] {
            var values=uncertain
            switch name {
            case "extra stone":values[outsideEmpty] = .black
            case "missing stone":values[outsideStone] = .empty
            case "wrong color":values[outsideStone] = plan.before[outsideStone] == .black ? .white:.black
            case "bumped stone":values[outsideStone] = .empty;values[outsideEmpty] = plan.before[outsideStone]
            case "capture withdrawn":values[plan.point] = .empty
            case "uncertain capturing stone":values[plan.point] = .uncertain
            case "uncertain prisoner":values[plan.captured.first!] = .uncertain
            case "replacement prisoner":values[plan.captured.first!] = .white
            default:for i in values.indices where i != plan.point && !plan.captured.contains(i) {values[i] = .uncertain}
            }
            conflicts.append((name,values))
        }
        for (name,values) in conflicts {
            check(AutomaticCapture.find(game:game,readings:values,minimum:2)==nil && !plan.matchesRemoval(values),"\(name) was treated as harmless uncertainty")
            let r=try make();feed(r,uncertain);feed(r,values)
            check(!r.clock.automaticCapturePaused && r.moveCount==fixture.baseMove,"\(name) confirmed a tentative capture")
            let fresh=now+0.21,start=r.clock.engine;feed(r,uncertain,count:3)
            check(r.clock.automaticCapturePaused,"Capture did not recover after \(name) was corrected")
            check(near(r.clock.engine.white.remaining,start.white.remaining-(fresh-start.anchor!)),"\(name) reused invalidated capture timing")
            r.pause()
        }
        let low=try make();feed(low,uncertain,count:4,confidence:0.8)
        check(!low.clock.automaticCapturePaused,"Low-confidence capturing stone paused clocks");low.pause()

        // A capture candidate whose board still needs checking must not lose
        // on time while an unrelated extra stone invalidates its capture plan.
        let nearExpiry=try make()
        var white=nearExpiry.clock.engine.white;white.remaining=0.3
        check(nearExpiry.clock.correct(black:nearExpiry.clock.engine.black,white:white,blackToPlay:false,moveCount:fixture.baseMove,at:now),"Near-expiry capture setup failed")
        nearExpiry.clock.resume(at:now)
        feed(nearExpiry,uncertain)
        feed(nearExpiry,conflicts.first{$0.0=="extra stone"}!.1)
        check(nearExpiry.clock.requiresReview && !nearExpiry.clock.running,"Conflicting capture ran through the deadline")
        check(nearExpiry.clock.engine.expiredBlack==nil && nearExpiry.clock.engine.white.remaining>0,"Capture ambiguity turned a possible on-time press into a loss")
        nearExpiry.pause()

        // Established holds also reject conflicts and unclear capture points;
        // they may resume only after fresh, consistent completed-board views.
        for (name,values) in conflicts {
            let r=try make();feed(r,uncertain,count:3);let stopped=r.clock.engine
            var badFinal=plan.target
            for i in values.indices where values[i] != uncertain[i] {badFinal[i]=values[i]}
            feed(r,badFinal,count:6)
            check(r.clock.automaticCapturePaused && !r.clock.running && r.moveCount==fixture.baseMove,"\(name) allowed completion of an established capture")
            check(r.clock.engine.black==stopped.black && r.clock.engine.white==stopped.white,"\(name) resumed charging during capture hold")
            feed(r,final,count:5)
            check(r.clock.running && r.moveCount==fixture.baseMove+1,"Corrected \(name) failed fresh completion verification")
            r.pause()
        }
        // Persist/reopen and manual-review escape use the expected intermediate
        // position, while camera readings remain uncertain and require freshness.
        let pending=try make();feed(pending,uncertain,count:3)
        try pending.flushStorage()
        let reopened=GameRecorder(storage:root);reopened.clock.audible=false;try reopened.restoreSavedGame(from:pending.autosaveURL!)
        check(reopened.clock.automaticCapturePaused && reopened.automaticCaptureStatus != nil && !reopened.clock.running,"Uncertainty broke restoration of a capture hold")
        check(reopened.prepareAutomaticCaptureReview() != nil && reopened.pendingCaptureReview != nil,"Uncertainty broke the manual capture-review escape")
        pending.pause()
        print("PASS: \(checks) recorded capture uncertainty and conflicting-board checks")
        return checks
    }
}
