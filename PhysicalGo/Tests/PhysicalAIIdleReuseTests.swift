import Foundation
import AppKit

@main struct PhysicalAIIdleReuseTests {
    @MainActor final class Backend:PhysicalAITestBackend {
        var isRunning=false
        var configurationValid=true
        var reusableConfiguration:Bool {isRunning && configurationValid}
        var moves=0,stops=0
        var suspended=false
        var pending:CheckedContinuation<String,Error>?
        func move(_ game:SGFGame) async throws -> String {
            moves+=1;isRunning=true
            if suspended {return try await withCheckedThrowingContinuation {pending=$0}}
            return "D4"
        }
        func stop() {stops+=1;isRunning=false}
        func complete(_ value:String="D4") {let p=pending;pending=nil;p?.resume(returning:value)}
    }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ result:Bool,_ message:String) {precondition(result,message);checks+=1}
        func settled(_ predicate:()->Bool) async {
            for _ in 0..<1000 {if predicate() {return};await Task.yield()}
            preconditionFailure("Async fake did not reach expected state")
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("physical-ai-idle-reuse-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let backend=Backend();var made=0
        var traceEvents=[(String,[String:String],[String:Double],Double)]()
        let worker=PhysicalAI.TestWorker(makeEngine:{made+=1;return backend},
            trace:{traceEvents.append(($0,$1,$2,$3))})
        var game=SGFGame();game.boardSize=9
        _ = try await worker.move(game)
        worker.cancelKeepingIdle();worker.cancelKeepingIdle()
        check(worker.isRunning && backend.stops==0,"Idle pause must retain completed worker")
        _ = try await worker.move(game)
        check(made==1 && backend.moves==2,"Warm resume must reuse same worker")
        backend.configurationValid=false
        _ = try await worker.move(game)
        check(made==2 && backend.stops==1,"Changed configuration must replace worker before search")
        worker.stop();check(!worker.isRunning,"Explicit shutdown releases worker")
        check(traceEvents.map {$0.0} == ["ai_test_worker_started","ai_test_worker_returned",
            "ai_test_worker_started","ai_test_worker_returned","ai_test_worker_started","ai_test_worker_returned"],
            "Worker diagnostics pair each completed request")
        check(traceEvents[0].1["workerStart"] == "new" && traceEvents[0].1["afterIdleRetention"] == "false",
            "First backend is explicitly new")
        check(traceEvents[2].1["workerStart"] == "reused" && traceEvents[2].1["afterIdleRetention"] == "true",
            "Completed idle backend is explicitly reused after retention")
        check(traceEvents[0].1["workerID"] == traceEvents[2].1["workerID"],"Reuse preserves diagnostic worker identity")
        check(traceEvents[0].1["workerRequest"] != traceEvents[2].1["workerRequest"],"Each search has a unique diagnostic identity")
        check(traceEvents[4].1["workerStart"] == "new" && traceEvents[4].1["afterIdleRetention"] == "false",
            "Configuration replacement reports new startup without stale retention")
        check(traceEvents[4].1["workerID"] != traceEvents[2].1["workerID"],"Replacement changes diagnostic worker identity")
        check(traceEvents[1].1 == traceEvents[0].1 && traceEvents[1].2["durationSeconds"]! >= 0,
            "Return retains exact request identity and monotonic duration")

        var time=100.0
        let liveBackend=Backend();var liveMade=0
        let liveWorker=PhysicalAI.TestWorker(makeEngine:{liveMade+=1;return liveBackend})
        let ai=PhysicalAI(directory:root.appendingPathComponent("idle"),laser:PhysicalLaserGuidance(directory:root.appendingPathComponent("laser-idle"),automatic:false),testWorker:liveWorker,uptime:{time},wallTime:{1000+time})
        ai.draft.size=9;ai.draft.humanBlack=false;ai.setFastTestMode(true)
        check(ai.start(),"Test game starts")
        func feed(_ ai:PhysicalAI,_ cells:[String]) {
            for _ in 0..<4 {
                time+=0.2
                var observation=BoardObservation(readings:cells.enumerated().map {i,c in
                    IntersectionReading(row:i/9,col:i%9,occupancy:Occupancy(rawValue:c)!,confidence:1,delta:0)},size:9)
                observation.capturedAt=time;observation.handObstructed=false
                ai.consume(observation,now:time)
            }
        }
        feed(ai,Array(repeating:"empty",count:81));await settled {ai.phase == .placing}
        let identity=ai.snapshot!.id,history=ai.snapshot!.moves.map(\.point),receipt=ai.snapshot!.moves.last!.decisionReceivedAtUnix
        ai.pause();let pausedClock=ai.snapshot!.timing
        check(ai.phase == .paused && liveWorker.isRunning,"Ordinary paused test game keeps idle process")
        time+=30;ai.resume()
        check(ai.snapshot!.id==identity && ai.snapshot!.moves.map(\.point)==history,"Resume preserves game identity/history")
        check(ai.snapshot!.moves.last!.decisionReceivedAtUnix==receipt,"Resume preserves original decision receipt")
        check(ai.snapshot!.timing==pausedClock,"Resume does not charge paused time")
        check(liveMade==1 && liveBackend.moves==1,"Resume itself never starts a search")
        ai.pause();ai.setFastTestMode(false)
        check(!liveWorker.isRunning && liveBackend.stops==1,"Changing mode while paused releases model")
        check(ai.snapshot!.moves.map(\.point)==history,"Mode change preserves history")
        ai.setFastTestMode(true);ai.resume();ai.shutdown()
        check(ai.phase == .paused && !liveWorker.isRunning,"Shutdown stops even from pause")

        // Reusing an idle process must not permit stale search results after pause.
        var engines=[Backend(),Backend()];engines.forEach {$0.suspended=true}
        var index=0
        var cancellationTrace=[(String,[String:String])]()
        let searchingWorker=PhysicalAI.TestWorker(makeEngine:{defer {index+=1};return engines[index]},
            trace:{event,fields,_,_ in cancellationTrace.append((event,fields))})
        let searching=PhysicalAI(directory:root.appendingPathComponent("cancel"),laser:PhysicalLaserGuidance(directory:root.appendingPathComponent("laser-cancel"),automatic:false),testWorker:searchingWorker,uptime:{time})
        searching.draft.size=9;searching.draft.humanBlack=false;searching.setFastTestMode(true)
        check(searching.start(),"Cancellation game starts")
        feed(searching,Array(repeating:"empty",count:81));await settled {engines[0].pending != nil}
        searching.pause();check(engines[0].stops==1,"Pause during search stops engine")
        searching.resume();feed(searching,Array(repeating:"empty",count:81));await settled {engines[1].pending != nil}
        engines[0].complete("A9");for _ in 0..<10 {await Task.yield()}
        check(searching.snapshot!.moves.isEmpty && searching.phase == .thinking,"Late cancelled decision cannot enter history")
        check(engines[1].stops==0,"Stale completion cannot stop replacement")
        engines[1].complete("D4");await settled {searching.phase == .placing}
        check(searching.snapshot!.moves.count==1 && searching.snapshot!.moves[0].point==48,"Only current request commits")
        let starts=cancellationTrace.filter {$0.0 == "ai_test_worker_started"}
        let failed=cancellationTrace.filter {$0.0 == "ai_test_worker_failed"}
        let returned=cancellationTrace.filter {$0.0 == "ai_test_worker_returned"}
        check(starts.count==2 && starts.allSatisfy {$0.1["workerStart"] == "new"},
            "Cancelled active search and replacement each report new workers")
        check(failed.count==1 && failed.first?.1["workerRequest"] == starts.first?.1["workerRequest"],
            "Obsolete cancellation is traced as failed under its own request")
        check(returned.count==1 && returned.first?.1["workerRequest"] == starts.last?.1["workerRequest"],
            "Only replacement completion enters successful timing samples")
        searching.finish()
        check(!searchingWorker.isRunning && searching.phase == .finished,"End game releases idle engine")
        checks += try await PhysicalAIIdleReuseReviewTests.run()
        print("PASS: \(checks) deterministic fast-test idle reuse checks")
    }
}
