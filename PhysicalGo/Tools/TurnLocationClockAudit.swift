import Foundation

/// Offline executable linked only to the unchanged deterministic clock engine.
/// Input times come from saved clock records, never from location resolution.
@main enum TurnLocationClockAudit {
    struct Turn:Decodable,Equatable {let identity:String;let color:String;let time:Double}
    struct Saved:Decodable {
        let number:Int
        let black:Bool
        let before:LocalClockEngine
        let after:LocalClockEngine
    }
    struct Input:Decodable {
        let name:String
        let original:[Turn]
        let afterCorrection:[Turn]
        let saved:[Saved]
    }
    static func main() throws {
        var results=[[String:Any]]()
        var checkpointsMatch=true
        for argument in CommandLine.arguments.dropFirst() {
            let input=try JSONDecoder().decode(Input.self,from:Data(contentsOf:URL(fileURLWithPath:argument)))
            precondition(input.original==input.afterCorrection,"Correction changed clock ledger")
            precondition(input.original.count==input.saved.count)
            var checkpointDifferences=[Int]()
            for (turn,saved) in zip(input.original,input.saved) {
                var engine=saved.before
                _=engine.move(black:saved.black,at:turn.time)
                if engine != saved.after {checkpointDifferences.append(saved.number)}
            }
            checkpointsMatch = checkpointsMatch && checkpointDifferences.isEmpty
            var modeChecks=0
            for kind in LocalClockSettings.Kind.allCases where kind != .none {
                // Generous balances keep this test about press accounting.
                // Native regression suites separately exercise expiry/intervals.
                let settings=LocalClockSettings(kind:kind,mainSeconds:10000,periodSeconds:1000,
                                               periods:5,incrementSeconds:3,maximumSeconds:20000,
                                               stonesPerPeriod:25,automaticCaptureMinimum:0)
                var reference=LocalClockEngine(settings:settings),deduplicated=reference
                reference.resume(at:input.original[0].time-1)
                deduplicated.resume(at:input.original[0].time-1)
                var used=Set<String>(),presses=0
                for turn in input.original {
                    precondition(reference.move(black:turn.color=="black",at:turn.time))
                    // Redelivery and a later location correction carry the same
                    // immutable turn identity. Only the first may press.
                    for delivery in [turn,turn,turn] where used.insert(delivery.identity).inserted {
                        precondition(deduplicated.move(black:delivery.color=="black",at:delivery.time))
                        presses += 1
                    }
                    precondition(reference==deduplicated)
                }
                precondition(presses==input.original.count)
                modeChecks += 1
            }
            results.append(["game":input.name,"turns":input.original.count,
                            "savedCheckpointDifferences":checkpointDifferences,
                            "timedModesWithIdenticalDeduplicatedAccounting":modeChecks,
                            "scope":"Saved checkpoint replay and duplicate delivery. No physical timing or capture-pause inference."])
        }
        let data=try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
        if !checkpointsMatch {exit(1)}
    }
}
