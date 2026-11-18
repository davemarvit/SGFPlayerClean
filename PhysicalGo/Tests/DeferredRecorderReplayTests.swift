import Foundation

/// Offline shadow boundary: actual recorder decisions, never saved acceptances.
/// The recorder remains the sole clock authority. No live hook is installed.
@main struct DeferredRecorderReplayTests {
    struct Frame: Decodable {
        let frameID: Int, capturedAt: Double, processedAt: Double, handObstructed: Bool, lightingBlocked: Bool
        let readings: [IntersectionReading], footprints: [StoneFootprint], placementFits: [StoneFootprint]
        let estimate: ClockPressEstimate?
    }
    struct Sequence: Decodable { let initialSGF: String; let expectedPoints: [Int]; let frames: [Frame] }
    @MainActor static func main() throws {
        let fixture = URL(fileURLWithPath: "PhysicalGo/Tests/Fixtures/RapidReplyShadow/sequence.json")
        let sequence = try JSONDecoder().decode(Sequence.self, from: Data(contentsOf: fixture))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("deferred-recorder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var report: [[String: Any]] = []
        for missing in [false,true] {
            let directory = root.appendingPathComponent(missing ? "missing" : "recorded")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("game.sgf")
            try sequence.initialSGF.write(to: file, atomically: true, encoding: .utf8)
            let recorder = GameRecorder(storage: directory); recorder.clock.audible = false
            try recorder.restoreSavedGame(from: file); recorder.resume()
            let offset = ProcessInfo.processInfo.systemUptime+5-sequence.frames[0].capturedAt
            let start = sequence.frames[0].capturedAt+offset-0.1
            let base = DeferredMoveHistory.states(recorder.positions.last!)
            for i in 0..<8 {
                let t = start-2+Double(i)*0.21
                recorder.consume(.init(readings: base.enumerated().map {
                    .init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)
                }, size:19,capturedAt:t,handObstructed:false),now:t)
            }
            recorder.clock.configure(.init(kind:.absolute,mainSeconds:120),blackToPlay:false,baseMove:7)
            recorder.clock.ready(at:start)
            var state = try DeferredStoneState(first:.white)
            var pauseTransitions = 0, previouslyReview = false
            for f in sequence.frames {
                let now = f.processedAt+offset, stamp = f.capturedAt+offset
                if f.handObstructed { recorder.noteHandObstruction(now:now,capturedAt:stamp) }
                else {
                    recorder.noteHandClear()
                    let estimate = f.estimate.map {
                        ClockPressEstimate(time:$0.time+offset,method:$0.method,
                            observedLower:$0.observedLower.map{$0+offset},observedUpper:$0.observedUpper.map{$0+offset},
                            estimatedError:$0.estimatedError,samples:$0.samples,timestampSource:$0.timestampSource,fallbackReason:$0.fallbackReason)
                    }
                    var readings = f.readings
                    if missing && [355,356].contains(f.frameID) {
                        let old = readings[309]
                        readings[309] = .init(row:old.row,col:old.col,occupancy:.uncertain,confidence:0,delta:old.delta)
                    }
                    recorder.consume(.init(readings:readings,size:19,lightingBlocked:f.lightingBlocked,
                        footprints:f.footprints,placementFits:f.placementFits,capturedAt:stamp,
                        handObstructed:false,clockPressEstimate:estimate),now:now)
                }
                let nativeClock = recorder.clock.engine
                if f.handObstructed { state.invalidateLocationEvidence(Set(state.locations.keys)) }
                // Clock records below are produced during THIS replay. They are
                // accepted native events, not certificates synthesized from pixels.
                for press in recorder.clock.moves + recorder.clock.provisionalMoves where press.number > 7 {
                    guard let e = press.estimate else { continue }
                    let id = "rapid-reply:native-turn:\(press.number)"
                    let prior = state.turns.first { $0.id == id }
                    // Redelivery preserves first certification availability too.
                    let certificate = prior ?? DeferredStoneState.Turn(id:id,color:press.black ? .black:.white,
                        time:e.time,lower:min(e.time,e.observedLower ?? e.time),upper:max(e.time,e.observedUpper ?? e.time),
                        certifiedAt:max(now,max(e.time,e.observedUpper ?? e.time)),
                        witnesses:["native-press:\(press.number)","native-estimate:\(press.number)"],
                        identityReliable:true,timingReliable:true,colorReliable:true,continuous:true)
                    if let prior { precondition(prior.time == e.time && prior.color == (press.black ? .black:.white)) }
                    _ = try state.accept(certificate,candidates:[])
                }
                for id in state.locations.keys {
                    let proposal = DeferredStoneState.Proposal(revision:state.revision,epoch:state.epoch,
                        identity:id,points:[33,34,35],center:nil,supported:false)
                    let applied = try state.apply(proposal)
                    precondition(applied)
                }
                // Persistence and location corrections are unable to press or
                // pause the actual native clock on this offline shadow boundary.
                state = try DeferredStoneState.restore(state.checkpoint())
                precondition(recorder.clock.engine == nativeClock)
                let review = recorder.clock.requiresReview
                if review && !previouslyReview { pauseTransitions += 1 }
                previouslyReview = review
            }
            let expectedTimes = [1265045.9376668755,1265050.6216669178,1265052.620700167]
            let times = state.turns.map { $0.time-offset }
            precondition(state.locations.values.allSatisfy { $0.reviewedIntersection == nil })
            if missing {
                precondition(times.count == 1 && pauseTransitions == 1 && !recorder.clock.running,
                             "Missing turn timing must not be invented to preserve continuity")
            } else {
                precondition(times.count == 3 && zip(times,expectedTimes).allSatisfy { abs($0-$1)<0.000001 })
                precondition(pauseTransitions == 0 && recorder.clock.running)
                precondition(recorder.game.moves.dropFirst(7).compactMap { $0.1.map { $0.1*19+$0.0 } } == sequence.expectedPoints)
            }
            report.append(["scenario":missing ? "injected missing intermediate sightings" : "original rapid reply recording",
                "recognizedTurns":state.turns.count,"allLocationsUnresolved":true,"pressTimes":times,
                "clockRunning":recorder.clock.running,"reviewTransitions":pauseTransitions,
                "savedAcceptanceDecisionsSupplied":false,
                "scope":"Actual unchanged native recorder supplies accepted turns; new ledger is an offline shadow, not recognition feedback."])
            recorder.pause()
        }
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            .write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic)
        print("PASS: native recorder produced three correctly timed turns with all shadow locations unresolved; missing-timing control retained review")
    }
}
