import Foundation

/// Standalone Foundation-only review; no application, camera, or hardware use.
@main struct PhysicalLatencyTraceTests {
    static var checks=0
    static func check(_ condition:Bool,_ message:String) {
        checks+=1
        if !condition {fatalError(message)}
    }
    static func rows(_ data:[Data])->[[String:Any]] {
        data.map {try! JSONSerialization.jsonObject(with:$0) as! [String:Any]}
    }
    static func main() throws {
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        let blocked=PhysicalLatencyTrace(capacity:2) { _ in
            entered.signal();_ = release.wait(timeout:.now()+2)
        }
        check(blocked.record("first"),"First event should fit")
        check(entered.wait(timeout:.now()+1) == .success,"Writer did not start")
        let began=ProcessInfo.processInfo.systemUptime
        check(blocked.record("second"),"One pending event should fit")
        check(!blocked.record("third"),"Bounded sink must reject excess event")
        check(ProcessInfo.processInfo.systemUptime-began<0.1,"Producer waited for blocked writer")
        check(!blocked.waitForTesting(seconds:0.01),"Blocked writer unexpectedly drained")
        release.signal();release.signal()
        check(blocked.waitForTesting(),"Released writer did not finish")

        var output=[Data]()
        let snapshot=PhysicalLatencyTrace {output.append($0)}
        var fields=["revision":"before"],metrics=["latency":0.25]
        check(snapshot.record("sample",fields:fields,metrics:metrics),"Snapshot rejected")
        fields["revision"]="after";metrics["latency"]=999
        check(snapshot.waitForTesting(),"Snapshot drain failed")
        let row=rows(output)[0]
        check((row["fields"] as? [String:String])?["revision"] == "before","Queued field mutated")
        check((row["metrics"] as? [String:Double])?["latency"] == 0.25,"Queued metric mutated")
        check(row["clockDomain"] as? String == "swift-systemUptime/"+(row["runID"] as! String),"Run/domain provenance missing")

        enum Failure:Error {case injected}
        var attempts=0,persisted=[Data]()
        let failing=PhysicalLatencyTrace {data in
            attempts+=1
            if attempts==1 {throw Failure.injected}
            persisted.append(data)
        }
        check(failing.record("lost"),"First failure offer rejected")
        check(failing.record("survivor"),"Second failure offer rejected")
        check(failing.waitForTesting(),"Failure drain failed")
        check(rows(persisted)[0]["writerFailures"] as? Int == 1,"Writer failure was hidden")

        var valid=[Data]()
        let validating=PhysicalLatencyTrace {valid.append($0)}
        check(!validating.record("bad",metrics:["duration":.infinity]),"Nonfinite metric accepted")
        check(!validating.record("bad",fields:["value":String(repeating:"x",count:513)]),"Oversize field accepted")
        check(validating.record("good"),"Valid event rejected")
        check(validating.waitForTesting(),"Validation drain failed")
        check(rows(valid)[0]["droppedEvents"] as? Int == 2,"Rejected events not accounted")

        // Real rotating-writer path remains confined to a temporary directory.
        // Control characters expand during JSON encoding despite fitting the
        // bounded field input, so oversized encoding must report a failure.
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("latency-review-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        setenv("PHYSICAL_GO_LATENCY_TRACE_DIRECTORY",directory.path,1)
        guard let configured=PhysicalLatencyTrace.shared else {fatalError("Explicit opt-in failed")}
        let escaped=Dictionary(uniqueKeysWithValues:(0..<24).map {(String($0),String(repeating:"\u{1}",count:512))})
        check(configured.record("oversize_encoded",fields:escaped),"Bounded input should reach encoding guard")
        check(configured.record("after_oversize"),"Following event rejected")
        check(configured.waitForTesting(),"Configured drain failed")
        let text=try String(contentsOf:directory.appendingPathComponent("native-latency.jsonl"),encoding:.utf8)
        let lines=text.split(separator:"\n").map {Data($0.utf8)}
        check(lines.count==1,"Oversize encoded row was written")
        check(rows(lines)[0]["writerFailures"] as? Int == 1,"Oversize encoded row was silently lost")
        print("PhysicalLatencyTraceTests: \(checks) checks passed")
    }
}
