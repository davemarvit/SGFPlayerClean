import AppKit

@main struct RecordingStorageFlowTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("storage-flow-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var now=ProcessInfo.processInfo.systemUptime
        let empty=[Occupancy](repeating:.empty,count:81)
        func feed(_ r:GameRecorder,_ colors:[Occupancy],count:Int=7) {
            for _ in 0..<count {
                now += 0.21
                r.consume(.init(readings:colors.enumerated().map {
                    .init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)
                },size:9),now:now)
            }
        }
        let writer=RecordingStorage(),entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        try writer.submit("slow disk") {entered.signal();release.wait()}
        check(entered.wait(timeout:.now()+2) == .success,"Blocked writer did not start")
        DispatchQueue.global().asyncAfter(deadline:.now()+3) {release.signal()}
        let r=GameRecorder(storage:root,storageWriter:writer);r.clock.audible=false
        let start=ProcessInfo.processInfo.systemUptime
        r.start(size:9,now:now,clockSettings:.init(kind:.absolute,mainSeconds:60),startPaused:true)
        check(r.playFlow == .paused,"Saved setup should start paused")
        check(r.resume() == .checking && r.playFlow == .checking && !r.clock.running,"Resume started clocks before verification")
        feed(r,empty)
        check(r.clock.running && r.playFlow == .playing,"Recorder-owned resume did not release manual pause")
        var colors=empty;colors[10] = .black;feed(r,colors)
        check(r.moveCount==1 && !r.clock.engine.blackToPlay,"Blocked storage prevented turn processing")
        check(ProcessInfo.processInfo.systemUptime-start<1,"Live processing waited for storage")
        var heartbeat=false;DispatchQueue.main.async {heartbeat=true}
        RunLoop.main.run(until:Date().addingTimeInterval(0.02))
        check(heartbeat,"Slow disk blocked the main run loop")
        r.pause();release.signal();try r.flushStorage();r.flushDiagnostics()
        let saved=try String(contentsOf:r.autosaveURL!,encoding:.utf8)
        check(saved.contains("B[bb]"),"Ordered storage lost the accepted move")
        let restored=GameRecorder(storage:root);restored.clock.audible=false
        try restored.restoreSavedGame(from:r.autosaveURL!)
        check(restored.moveCount==1 && !restored.clock.engine.blackToPlay && restored.playFlow == .paused,"Durable SGF and clock do not agree")
        check(restored.resume() == .checking,"Restored session cannot request resume")
        restored.pause();feed(restored,colors)
        check(restored.playFlow == .paused && !restored.clock.running,"Camera verification revoked explicit pause")
        check(restored.resume() == .checking,"Repeated resume was not accepted")
        feed(restored,colors)
        check(restored.clock.running,"Verified restored board did not resume")
        restored.suspendVision("Camera unavailable",preserveOrder:true)
        check(restored.playFlow == .checking && !restored.clock.running,"Camera interruption needs checking, not another Resume")
        feed(restored,colors)
        check(restored.clock.running,"Automatic checking did not return to play")
        restored.clock.recover(toBlack:false,reason:"Missing turn boundary",at:now)
        restored.pause()
        check(restored.resume() == .clockReview && restored.state == .paused,"Resume bypassed timing review")
        let b=restored.clock.engine.black,w=restored.clock.engine.white
        check(restored.confirmClockReview(black:b,white:w,resume:true),"Clock confirmation was rejected")
        check(restored.playFlow == .checking && !restored.clock.running,"Clock confirmation skipped fresh verification")
        feed(restored,colors)
        check(restored.playFlow == .playing && restored.clock.running,"Clock review returned to a resume loop")
        restored.pause();try restored.flushStorage()

        // An asynchronous failure stops dependent writes, reaches the UI, blocks
        // resume, and can be retried without changing the in-memory game.
        let bad=RecordingStorage(),badRecorder=GameRecorder(storage:root,storageWriter:bad)
        badRecorder.clock.audible=false;badRecorder.start(size:9,now:now,clockSettings:.init(kind:.absolute,mainSeconds:60))
        feed(badRecorder,empty)
        check(badRecorder.clock.running,"Failure test never started the clock")
        try badRecorder.flushStorage()
        let original=badRecorder.autosaveURL!
        try bad.submit("injected failure") {throw RecordingStorage.Failure(message:"disk unavailable")}
        // Wait for the failure to reach the main actor without blocking it.
        let end=Date().addingTimeInterval(3)
        while badRecorder.saveError==nil && Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
        check(badRecorder.state == .paused && !badRecorder.clock.running && badRecorder.playFlow == .storageBlocked && badRecorder.resume() == .unavailable,"Failed storage permitted resume")
        var wroteDependent=false
        do {try bad.submit("dependent sidecar") {wroteDependent=true};check(false,"Failed writer accepted dependent data")} catch {}
        check(!wroteDependent,"Dependent sidecar passed a failed write")
        badRecorder.retryRecordingSave()
        check(badRecorder.saveError==nil && badRecorder.autosaveURL==original,"Retry lost the session or retained stale error")
        check(badRecorder.resume() == .checking,"Successful retry did not release storage gate")
        badRecorder.pause();try badRecorder.flushStorage()

        // A sidecar already admitted before a disk failure must also be skipped.
        // Retrying and failing again with the same message must not deliver the
        // first attempt's delayed error notification into the new attempt.
        let orderedFailure=RecordingStorage(),enteredFailure=DispatchSemaphore(value:0),releaseFailure=DispatchSemaphore(value:0)
        var notifications=[UUID](),savedSidecar=false
        orderedFailure.onFailure={notifications.append($0.id)}
        try orderedFailure.submit("game") {
            enteredFailure.signal();releaseFailure.wait()
            throw RecordingStorage.Failure(message:"same disk error")
        }
        check(enteredFailure.wait(timeout:.now()+2) == .success,"Failure blocker did not start")
        try orderedFailure.submit("dependent pending history") {savedSidecar=true}
        releaseFailure.signal()
        do {try orderedFailure.flush();check(false,"Failed game write was hidden")} catch {}
        check(!savedSidecar,"Already queued sidecar passed failed game revision")
        orderedFailure.retry()
        try orderedFailure.submit("game") {throw RecordingStorage.Failure(message:"same disk error")}
        do {try orderedFailure.flush();check(false,"Second failure was hidden")} catch {}
        let currentFailure=orderedFailure.currentFailure!.id
        RunLoop.main.run(until:Date().addingTimeInterval(0.02))
        check(notifications==[currentFailure],"A stale error callback crossed the retry boundary")

        let snapshots=RecordingStorage(),enteredSnapshots=DispatchSemaphore(value:0),releaseSnapshots=DispatchSemaphore(value:0)
        var order=[Int]()
        try snapshots.submit("blocked") {enteredSnapshots.signal();releaseSnapshots.wait()}
        check(enteredSnapshots.wait(timeout:.now()+2) == .success,"Snapshot blocker did not start")
        for value in 0..<1000 {try snapshots.submit("pending snapshot",coalescingKey:"pending") {order.append(value)}}
        try snapshots.submit("clock boundary") {order.append(-1)}
        try snapshots.submit("next pending snapshot",coalescingKey:"pending") {order.append(1000)}
        releaseSnapshots.signal();try snapshots.flush()
        check(order==[999,-1,1000],"Snapshot coalescing lost latest state or crossed a dependent write")

        let small=RecordingStorage(capacity:2),enteredSmall=DispatchSemaphore(value:0),releaseSmall=DispatchSemaphore(value:0)
        try small.submit("blocked") {enteredSmall.signal();releaseSmall.wait()}
        check(enteredSmall.wait(timeout:.now()+2) == .success,"Small writer did not start")
        try small.submit("queued") {}
        do {try small.submit("overflow") {};check(false,"Storage queue grew without a bound")} catch {}
        releaseSmall.signal()
        do {try small.flush();check(false,"Overflow was hidden at durability boundary")} catch {}
        small.retry();try small.submit("recovered") {};try small.flush()
        check(small.error==nil,"Bounded writer cannot recover")
        r.flushDiagnostics();restored.flushDiagnostics();badRecorder.flushDiagnostics()
        print("PASS: \(checks) background storage and pause/resume flow checks")
    }
}
