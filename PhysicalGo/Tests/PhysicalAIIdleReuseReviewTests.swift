import Foundation
import Darwin

/// Independent adversarial completions. The fake deliberately ignores stop and
/// task cancellation so obsolete callbacks can arrive after replacement starts.
@MainActor enum PhysicalAIIdleReuseReviewTests {
    private final class Backend:PhysicalAITestBackend {
        var isRunning=false
        var reusableConfiguration=true
        var stops=0
        var pending:[CheckedContinuation<String,Error>]=[]
        func move(_ game:SGFGame) async throws -> String {
            isRunning=true
            return try await withCheckedThrowingContinuation {pending.append($0)}
        }
        func stop() {stops+=1;isRunning=false}
        func finish(_ result:Result<String,Error>) {pending.removeFirst().resume(with:result)}
    }
    private struct InjectedFailure:Error {}
    private static func waitFor(_ predicate:()->Bool) async throws {
        for _ in 0..<1000 {
            if predicate() {return}
            try await Task.sleep(nanoseconds:1_000_000)
        }
        preconditionFailure("Fake request did not reach its continuation")
    }
    static func run() async throws -> Int {
        var checks=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);checks+=1}
        func failed(_ result:Result<String,Error>)->Bool {if case .failure=result {return true};return false}
        let game=SGFGame()
        for oldFails in [false,true] {
            let first=Backend(),second=Backend();var created=0
            let worker=PhysicalAI.TestWorker(makeEngine:{created+=1;return created==1 ? first:second})
            let old=Task {try await worker.move(game)}
            try await waitFor {!first.pending.isEmpty}
            worker.stop()
            let replacement=Task {try await worker.move(game)}
            try await waitFor {!second.pending.isEmpty}
            first.finish(oldFails ? .failure(InjectedFailure()):.success("D4"))
            check(failed(await old.result),"Obsolete success or failure must never become a returned move")
            check(worker.isRunning && second.stops==0 && first.stops==1,"Obsolete callback must not stop a replacement request")
            do { _ = try await worker.move(game);preconditionFailure("Concurrent request admitted") }
            catch {checks+=1}
            check(second.stops==0 && second.pending.count==1,"Rejected concurrent request must preserve the active owner")
            second.finish(.success("Q16"))
            check(try await replacement.value=="Q16","Replacement must complete normally after stale callback")
            worker.cancelKeepingIdle()
            check(second.stops==0 && worker.isRunning,"A completed replacement may remain idle")
            worker.stop()
            check(second.stops==1 && !worker.isRunning,"Explicit stop must release retained worker")
        }
        // The backend has delivered a result, but the worker's suspended call
        // has not resumed on this actor. Pause must still see active ownership.
        do {
            let backend=Backend();let worker=PhysicalAI.TestWorker(makeEngine:{backend})
            let request=Task {try await worker.move(game)}
            try await waitFor {!backend.pending.isEmpty}
            backend.finish(.success("D4"))
            worker.cancelKeepingIdle()
            check(backend.stops==1,"Queued completion is still active and must stop on Pause")
            check(failed(await request.result),"Queued completion after Pause must be rejected")
        }
        // A cancellation delivered at the completion boundary cannot turn the
        // cancelled search into a reusable idle success.
        do {
            let backend=Backend();let worker=PhysicalAI.TestWorker(makeEngine:{backend})
            let request=Task {try await worker.move(game)}
            try await waitFor {!backend.pending.isEmpty}
            backend.finish(.success("D4"));request.cancel()
            check(failed(await request.result),"Cancelled completion must not return a move")
            check(backend.stops==1 && !worker.isRunning,"Cancelled completion must release its engine")
        }
        do {
            let first=Backend(),second=Backend();var created=0
            let worker=PhysicalAI.TestWorker(makeEngine:{created+=1;return created==1 ? first:second})
            let initial=Task {try await worker.move(game)}
            try await waitFor {!first.pending.isEmpty};first.finish(.success("D4"));_ = try await initial.value
            first.reusableConfiguration=false
            let next=Task {try await worker.move(game)}
            try await waitFor {!second.pending.isEmpty}
            check(created==2 && first.stops==1,"Changed configuration must replace idle engine before search")
            second.finish(.success("Q16"));_ = try await next.value
            worker.stop()
        }
        checks += try await metadataReview()
        return checks
    }
    private static func metadataReview() async throws -> Int {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("idle-engine-metadata-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let executable=root.appendingPathComponent("fake-engine.sh"),model=root.appendingPathComponent("model.bin")
        let config=root.appendingPathComponent("analysis.cfg"),pidFile=root.appendingPathComponent("pid")
        let quotedPIDPath="'"+pidFile.path.replacingOccurrences(of:"'",with:"'\\''")+"'"
        try Data(("#!/bin/sh\nprintf '%s' \"$$\" > "+quotedPIDPath+"\nwhile IFS= read -r line; do :; done\n").utf8).write(to:executable)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
        try Data("fake model".utf8).write(to:model)
        try Data("first config".utf8).write(to:config)
        let engine=KataGoEngine(executableURL:executable,modelURL:model,configURL:config,
                               cacheDirectory:root.appendingPathComponent("cache"),legacyImportDirectories:[])
        defer {engine.stop()}
        var pid:pid_t?,caught:Error?,initial=false,changed=false
        engine.start()
        do {
            for _ in 0..<1000 {
                if let value=try? String(contentsOf:pidFile,encoding:.utf8),let parsed=Int32(value),parsed>1 {pid=parsed;break}
                try await Task.sleep(nanoseconds:1_000_000)
            }
            guard pid != nil else {throw InjectedFailure()}
            initial=engine.canReuseCurrentConfiguration()
            // Atomic same-path replacement changes the launch-time asset
            // identity even if the model path and engine process stay fixed.
            try Data("other config".utf8).write(to:config,options:.atomic)
            changed = !engine.canReuseCurrentConfiguration()
        } catch {caught=error}
        // Assertions occur only after cleanup; failed checks cannot leave this
        // temporary fake executable running. No KataGo/model or live cache used.
        engine.stop()
        var reaped=pid == nil
        if let pid {
            for _ in 0..<1000 {
                if kill(pid,0) == -1 && errno == ESRCH {reaped=true;break}
                try? await Task.sleep(nanoseconds:1_000_000)
            }
        }
        if let caught {throw caught}
        precondition(reaped,"Temporary fake engine must terminate and be reaped")
        precondition(initial,"Fresh idle engine should match its launch-time assets")
        precondition(changed,"Replacing config at same path must invalidate engine reuse")
        precondition(!engine.canReuseCurrentConfiguration(),"Stopped engine cannot be reused")
        return 4
    }
}
