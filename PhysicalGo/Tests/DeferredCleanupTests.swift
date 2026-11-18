import Foundation

/// Standalone native tests and recording replay. No app lifecycle/camera access.
@main enum DeferredCleanupTests {
    typealias State = DeferredStoneState
    typealias Bridge = DeferredCleanupAssociation
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }
    static func fails(_ message: String, _ body: () throws -> Void) {
        do { try body(); fatalError(message) } catch { checks += 1 }
    }
    static func turn(_ n: Int, time: Double? = nil) -> State.Turn {
        let t = time ?? Double(n)*2
        return .init(id: "turn:\(n)", color: n%2 == 1 ? .black : .white, time: t, lower: t,
                     upper: t, certifiedAt: t+0.1, witnesses: ["w:\(n):a","w:\(n):b"],
                     identityReliable: true, timingReliable: true, colorReliable: true, continuous: true)
    }
    static func disk(_ x: Double, _ y: Double = 3, color: State.Color = .black, point: Int? = nil) -> Bridge.Disk {
        .init(color: color, x: x, y: y, rx: 0.42, ry: 0.45, quality: 0.99, points: [point ?? Int(y.rounded())*19+Int(x.rounded())])
    }
    static func anchor(_ id: String, _ d: Bridge.Disk) -> Bridge.Anchor {
        .init(identity: id, disk: d, witnesses: ["pre:0","pre:1","pre:2"], first: 0, last: 0.5)
    }
    static func view(_ t: Double, _ disks: [Bridge.Disk], hand: Bool? = false, epoch: String = "test",
                     gap: Bool = false, captured: Set<String> = [], removed: Set<String> = [], blockers: [Bridge.Blocker] = []) -> Bridge.View {
        .init(id: "view:\(t)", time: t, epoch: epoch, hand: hand, lightingOK: true, gap: gap,
              disks: disks, captured: captured, removed: removed, blockers: blockers)
    }
    static func observeClear(_ bridge: inout Bridge, _ disks: [Bridge.Disk], start: Double = 1,
                             captured: Set<String> = [], removed: Set<String> = [], blockers: [Bridge.Blocker] = []) throws {
        for t in [start,start+0.4,start+0.81] {
            try bridge.observe(view(t, disks, captured: captured, removed: removed, blockers: blockers))
        }
    }
    static func tests(_ folder: URL) throws {
        var bridge = try Bridge(anchors: [anchor("a",disk(3))], epoch: "test")
        try bridge.observe(view(0.7, [], hand: true))
        try observeClear(&bridge, [disk(5)])
        check(bridge.supported["a"] != nil, "Isolated two-intersection cleanup should support a hypothesis")
        check(bridge.supported["a"]!.witnesses.count == 3, "Three independent clear views required")
        try bridge.observe(view(2, [], hand: true))
        check(bridge.supported.isEmpty, "Hand reentry withdraws fresh support")

        // Equal and unequal distances: nearest is not an identity certificate.
        for positions in [[3.5,4.5],[3.1,4.9],[5.0,3.0]] {
            var b = try Bridge(anchors: [anchor("a",disk(3)),anchor("b",disk(5))], epoch: "test")
            try b.observe(view(0.7, [], hand: true))
            try observeClear(&b, positions.map { disk($0) })
            check(b.supported.isEmpty, "Same-color swap/competition must remain unresolved")
            check(b.candidates["a"]!.count == 2 && b.candidates["b"]!.count == 2, "Retain both alternatives")
        }
        var b = try Bridge(anchors: [anchor("a",disk(3)),anchor("b",disk(5))], epoch: "test")
        try b.observe(view(0.7, [], hand: true))
        try observeClear(&b, [disk(4)])
        check(b.supported.isEmpty, "Disappearance is not elimination of another identity")
        try observeClear(&b, [disk(4)], start: 2, captured: ["b"])
        check(b.supported.isEmpty, "Captured stone awaiting removal still competes")
        try observeClear(&b, [disk(4)], start: 3, captured: ["b"], removed: ["b"])
        check(b.supported["a"] != nil && b.supported["b"] == nil, "Verified removal permits fresh reassessment of survivor")
        for competitor in [Bridge.Blocker(identity: "new-turn", color: .black, centers: [.init(x: 5,y: 3)]),
                           .init(identity: "unreliable-neighbor", color: .black, centers: []),
                           .init(identity: "unreliable-neighbor", color: .black, centers: [.init(x: 4,y: 3)])] {
            var b = try Bridge(anchors: [anchor("a",disk(3))], epoch: "test")
            try b.observe(view(0.7, [], hand: true))
            try observeClear(&b, [disk(5)], blockers: [competitor])
            check(b.supported.isEmpty, "New or unreliable same-color competitor cannot be ignored")
            check(b.candidates["a"]!.first!.competitors.contains(competitor.identity), "Retain reason for ambiguity")
        }
        for mode in ["gap","camera","unknown","far","color","duplicate","creep"] {
            var b = try Bridge(anchors: [anchor("a",disk(3))], epoch: "test")
            try b.observe(view(0.7, [], hand: mode == "unknown" ? nil : true))
            if mode == "duplicate" {
                let v = view(1,[disk(5)])
                for _ in 0..<10 { try b.observe(v) }
            } else if mode == "creep" {
                for (i,x) in [3.0,3.1,3.2,3.3,3.4,3.5].enumerated() {
                    try b.observe(view(1+Double(i)*0.3,[disk(x)]))
                }
            } else {
                for t in [1.0,1.4,1.81] {
                    try b.observe(view(t,[disk(mode == "far" ? 8 : 5, color: mode == "color" ? .white : .black)],
                                       epoch: mode == "camera" ? "different" : "test", gap: mode == "gap" && t == 1))
                }
            }
            check(b.supported.isEmpty, "Must abstain for \(mode)")
        }
        let wideAnchors = [1.0,5,9,13].map { anchor("stone:\($0)",disk($0)) }
        var drift = try Bridge(anchors: wideAnchors, epoch: "test", maximumMotion: 0.65)
        try drift.observe(view(0.7, [], hand: true))
        try observeClear(&drift, [1.0,5,9,13].map { disk($0+0.2) })
        check(drift.interrupted == "possible camera/board movement" && drift.supported.isEmpty, "Board drift is not stone cleanup")

        let settings = LocalClockSettings(kind: .fischer, mainSeconds: 1000, incrementSeconds: 3, maximumSeconds: 2000)
        var initial = LocalClockEngine(settings: settings); initial.resume(at: 0)
        var session = try DeferredTurnSession(state: State(), clock: initial, timeline: "test-boot:clock-origin")
        let file = folder.appendingPathComponent("checkpoint.json")
        check(try session.accept(turn(1), candidates: [], savingTo: file), "No location must still accept a certified turn")
        let originalClock = session.clock, originalTurns = session.state.turns
        let p = State.Proposal(revision: session.state.revision, epoch: session.state.epoch, identity: turn(1).id,
                               points: [60,61], center: .init(x: 3.8,y: 3), supported: true)
        check(try session.apply(p, savingTo: file), "Fresh display proposal should apply")
        check(session.state.locations[turn(1).id]!.reviewedIntersection == nil, "Display must not settle history")
        check(session.state.locations[turn(1).id]!.historicalCandidates.isEmpty, "Current physical point is not historical move point")
        fails("A proposed display position leaked into final move export") { _ = try session.state.reviewedSequence() }
        check(session.clock == originalClock && session.state.turns == originalTurns, "Cleanup changed clock or original turn")
        check(try !session.apply(p), "Reject stale background result")
        let beforeHand = State.Proposal(revision: session.state.revision, epoch: session.state.epoch, identity: turn(1).id,
                                       points: [61], center: .init(x: 4,y: 3), supported: true)
        try session.invalidateLocationEvidence([turn(1).id])
        check(try !session.apply(beforeHand), "A later hand must invalidate in-flight background work")
        check(session.state.locations[turn(1).id]!.proposedCenter == nil && session.clock == originalClock,
              "Hand invalidation changed clock or retained stale display")
        session = try DeferredTurnSession.restore(from: file, timeline: "test-boot:clock-origin")
        check(session.clock == originalClock && session.state.turns == originalTurns, "Restore changed original accounting")
        check(session.state.locations[turn(1).id]!.proposedCenter == nil, "Restore cannot assert fresh visibility")
        check(try !session.apply(p), "Reject worker from previous process epoch")
        check(try !session.accept(turn(1), candidates: [61], savingTo: file), "Duplicate certificate must not press again after restore")
        try session.reviewIntersection(identity: turn(1).id, point: 59, savingTo: file)
        check(session.state.locations[turn(1).id]!.reviewedIntersection == 59, "Review correction retained")
        check(session.clock == originalClock && session.state.turns == originalTurns, "Review correction changed original press")
        fails("Conflicting redelivery accepted") { _ = try session.accept(turn(1,time: 2.1), candidates: []) }
        fails("Failed disk save advanced state") {
            _ = try session.accept(turn(2), candidates: [], savingTo: folder.appendingPathComponent("missing/record.json"))
        }
        check(session.clock == originalClock && session.state.turns == originalTurns, "Persistence failure must roll back both ledger and clock")
        check(try session.accept(turn(2), candidates: [60,61], savingTo: file), "Unresolved first stone must not obstruct next turn")
        try session.capture(by: turn(2).id, victims: [turn(1).id], savingTo: file)
        check(session.state.locations[turn(1).id]!.removalVerified == false, "Capture cannot fabricate physical removal")
        let afterCaptureClock = session.clock
        try session.verifyRemoval([turn(1).id], savingTo: file)
        check(session.clock == afterCaptureClock, "Physical removal must not create another turn")
        session = try DeferredTurnSession.restore(from: file, timeline: "test-boot:clock-origin")
        check(session.state.locations[turn(1).id]!.removalVerified, "Capture tombstone lost on restart")
        fails("Cross-reboot monotonic times reused") { _ = try DeferredTurnSession.restore(from: file, timeline: "different-boot") }
        fails("Same-color capture certificate accepted") { try session.capture(by: turn(2).id, victims: [turn(2).id]) }
        var paused = initial; paused.pause(at: 0)
        var pausedSession = try DeferredTurnSession(state: State(), clock: paused, timeline: "paused")
        fails("Paused timing should not silently press") { _ = try pausedSession.accept(turn(1), candidates: []) }
        check(pausedSession.state.turns.isEmpty, "Timing rejection partially mutated turn ledger")
        // Widespread location ambiguity scales per stone; no global position budget.
        var crowded = try State()
        for n in 1...300 { try crowded.accept(turn(n), candidates: Set(0..<361)) }
        check(crowded.turns.count == 300 && crowded.locations.values.allSatisfy { $0.reviewedIntersection == nil }, "Widespread ambiguity stopped turn continuity")
        let restoredCrowded = try State.restore(crowded.checkpoint())
        check(restoredCrowded.turns == crowded.turns, "Large ambiguous ledger failed restore")
        print("PASS: native unit controls (\(checks) assertions before recording replay)")
    }

    struct Saved: Decodable { let number: Int; let black: Bool; let before: LocalClockEngine; let after: LocalClockEngine }
    struct Record: Decodable { let turn: State.Turn; let point: Int; let alternatives: Set<Int>; let captured: Set<String>; let saved: Saved }
    struct Episode: Decodable {
        let id: String; let epoch: String; let anchors: [Bridge.Anchor]; let anchorPoints: [String: Int]
        let views: [Bridge.View]; let availableAt: Double; let startedAt: Double
    }
    struct Game: Decodable { let name: String; let originalSGF: String; let records: [Record]; let episodes: [Episode] }
    struct Reviewed: Decodable { let episode: String; let point: Int }
    struct Input: Decodable { let games: [Game]; let relocation: [Bridge.View]; let reviewed: [Reviewed] }

    static func recordingReplay(_ input: Input, folder: URL, artifacts: URL) throws -> [String: Any] {
        var output: [String: Any] = [:]
        var exports: [[String: String]] = []
        for game in input.games {
            var sweeps: [[String: Any]] = []
            var finalBridges: [String: Bridge] = [:]
            for radius in [0.65,1.25,2.25] {
                var everCount = 0, finalCount = 0, competitors = 0, disagreements = 0, interruptions = 0
                for episode in game.episodes {
                    var bridge = try Bridge(anchors: episode.anchors, epoch: episode.epoch, maximumMotion: radius)
                    var ever: Set<String> = []
                    for v in episode.views {
                        try bridge.observe(v)
                        if v.hand != false { check(bridge.supported.isEmpty, "Fresh association while covered") }
                        for (id,support) in bridge.supported {
                            ever.insert(id)
                            if !support.disk.points.contains(episode.anchorPoints[id]!) { disagreements += 1 }
                        }
                    }
                    everCount += ever.count; finalCount += bridge.supported.count
                    competitors += bridge.candidates.values.filter { $0.count > 1 || $0.contains { !$0.competitors.isEmpty } }.count
                    interruptions += bridge.interrupted == nil ? 0 : 1
                    if radius == 2.25 { finalBridges[episode.id] = bridge }
                }
                sweeps.append(["radius":radius,"everSupportedStoneVisits":everCount,"finalSupportedStoneVisits":finalCount,
                               "finalAmbiguousStoneVisits":competitors,"savedPointDisagreements":disagreements,"interruptedVisits":interruptions])
            }
            var savedDifferences: [Int] = []
            for r in game.records {
                var engine = r.saved.before
                _ = engine.move(black: r.saved.black, at: r.turn.time)
                if engine != r.saved.after { savedDifferences.append(r.saved.number) }
            }
            check(savedDifferences.isEmpty, "Saved clock checkpoints differ")
            var applied = 0, deferred = 0, modeCount = 0
            // Interleave location updates after their actual evidence availability.
            // Full game clock reference has generous balances and no invented
            // capture pauses. Saved before/after checkpoints above cover those.
            enum Event { case turn(Record), location(Episode), hand(Episode) }
            var events = game.records.map { ($0.turn.certifiedAt,0,Event.turn($0)) }
            events += game.episodes.map { ($0.availableAt,1,Event.location($0)) }
            events += game.episodes.map { ($0.startedAt,2,Event.hand($0)) }
            events.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
            for kind in LocalClockSettings.Kind.allCases {
                var clock = LocalClockEngine(settings: .init(kind: kind, mainSeconds: 10000, periodSeconds: 1000,
                    periods: 5, incrementSeconds: 3, maximumSeconds: 20000, stonesPerPeriod: 25, automaticCaptureMinimum: 0))
                clock.resume(at: game.records[0].turn.time-1)
                var reference = clock
                var session = try DeferredTurnSession(state: State(), clock: clock, timeline: "offline:\(game.name)")
                let file = folder.appendingPathComponent("\(game.name)-\(kind.rawValue)-checkpoint.json")
                for (_,_,event) in events {
                    switch event {
                    case .hand(let e):
                        let originalClock = session.clock
                        try session.invalidateLocationEvidence(Set(e.anchors.map(\.identity)))
                        check(session.clock == originalClock, "Hand cleanup invalidation changed the clock")
                    case .turn(let r):
                        // Alternate explicit ambiguity with completely unknown locations.
                        let choices: Set<Int> = r.saved.number%3 == 0 ? [] : r.alternatives
                        check(try session.accept(r.turn, candidates: choices, savingTo: file), "Certified turn rejected by location state")
                        if reference.enabled { check(reference.move(black: r.turn.color == .black, at: r.turn.time), "Reference clock rejected supplied turn") }
                        check(try !session.accept(r.turn, candidates: [r.point]), "Redelivery created a second turn")
                        if !r.captured.isEmpty { try session.capture(by: r.turn.id, victims: r.captured, savingTo: file) }
                        if r.saved.number%17 == 0 {
                            session = try DeferredTurnSession.restore(from: file, timeline: "offline:\(game.name)")
                            check(try !session.accept(r.turn, candidates: []), "Restart duplicated turn")
                        }
                    case .location(let e):
                        let bridge = finalBridges[e.id]!
                        let originalTurns = session.state.turns, originalClock = session.clock
                        for a in e.anchors where session.state.locations[a.identity]?.capturedBy == nil {
                            guard session.state.locations[a.identity] != nil else { continue }
                            let support = bridge.supported[a.identity]
                            let points = Set((bridge.candidates[a.identity] ?? []).flatMap { $0.disk.points })
                            let proposal = State.Proposal(revision: session.state.revision, epoch: session.state.epoch,
                                identity: a.identity, points: points,
                                center: support.map { .init(x: $0.disk.x,y: $0.disk.y) }, supported: support != nil)
                            check(try session.apply(proposal), "Current background result unexpectedly stale")
                            if kind == .absolute { if support == nil { deferred += 1 } else { applied += 1 } }
                        }
                        check(session.state.turns == originalTurns && session.clock == originalClock, "Location worker changed clocks/turns")
                    }
                    check(session.clock == reference, "Unresolved locations changed clock accounting")
                }
                check(session.state.turns == game.records.map(\.turn), "Original identity/order/timestamps changed")
                fails("Unresolved history permitted final export") { _ = try session.state.reviewedSequence() }
                for r in game.records { try session.reviewIntersection(identity: r.turn.id, point: r.point) }
                try session.save(to: file)
                session = try DeferredTurnSession.restore(from: file, timeline: "offline:\(game.name)")
                check(session.clock == reference && session.state.turns == game.records.map(\.turn), "Final review/restore changed clock ledger")
                check(game.records.allSatisfy { session.state.locations[$0.turn.id]!.reviewedIntersection == $0.point }, "Final reviewed intersections lost")
                if kind == .absolute {
                    let sequence = try session.state.reviewedSequence()
                    func letter(_ i: Int) -> String { String(UnicodeScalar(97+i)!) }
                    let sgf = "(;GM[1]FF[4]SZ[19]" + sequence.map { item in
                        ";\(item.turn.color == .black ? "B" : "W")[\(letter(item.point%19))\(letter(item.point/19))]"
                    }.joined() + ")\n"
                    let file = artifacts.appendingPathComponent("\(game.name)-reviewed.sgf")
                    try sgf.write(to: file, atomically: true, encoding: .utf8)
                    exports.append(["original":game.originalSGF,"resolved":file.path])
                }
                modeCount += 1
            }
            output[game.name] = ["turns":game.records.count,"handVisits":game.episodes.count,"radiusSweep":sweeps,
                "displayProposalsApplied":applied,"locationsKeptUnresolved":deferred,"savedClockDifferences":savedDifferences,
                "clockModesIncludingUntimed":modeCount,"ledgerPreserved":true]
        }
        // Larger movement controls reuse actual shapes/timing from the four
        // reviewed visits. Only one isolated old identity and outline is retained;
        // the deliberate translation is NOT an observed real displacement.
        var controls: [[String: Any]] = []
        for reviewed in input.reviewed {
            let episode = input.games.flatMap(\.episodes).first { $0.id == reviewed.episode }!
            let a = episode.anchors.first { episode.anchorPoints[$0.identity] == reviewed.point }!
            for displacement in [1.0,2.0] {
                let delta = a.disk.x < 16 ? displacement : -displacement
                var b = try Bridge(anchors: [a], epoch: episode.epoch)
                var ambiguous = try Bridge(anchors: [a], epoch: episode.epoch)
                var everSupported = false
                for v in episode.views {
                    let moved = v.disks.filter { $0.color == a.disk.color && $0.points.contains(reviewed.point) }.map { d in
                        Bridge.Disk(color: d.color, x: d.x+delta, y: d.y, rx: d.rx, ry: d.ry, quality: d.quality,
                                    points: Set(d.points.map { $0+Int(delta) }))
                    }
                    func modified(_ blockers: [Bridge.Blocker]) -> Bridge.View {
                        .init(id: v.id, time: v.time, epoch: v.epoch, hand: v.hand, lightingOK: v.lightingOK, gap: v.gap,
                              disks: moved, captured: [], removed: [], blockers: blockers)
                    }
                    try b.observe(modified([]))
                    try ambiguous.observe(modified([.init(identity: "injected-same-color-competitor", color: a.disk.color, centers: [])]))
                    check(ambiguous.supported.isEmpty, "Larger movement stole an ambiguous same-color identity")
                    everSupported = everSupported || b.supported[a.identity] != nil
                }
                check(everSupported, "Isolated translated recording outlines did not support larger cleanup")
                controls.append(["sourceEpisode":episode.id,"injectedGridDisplacement":displacement,
                                 "isolatedSupported":everSupported,"sameColorCompetitorRemainsUnresolved":true])
            }
        }
        // Real known relocation data: its missing hand history remains missing.
        // A supplied hypothetical anchor is NOT evidence that it was observed.
        let start = input.relocation.first!.time
        let hypothetical = Bridge.Anchor(identity: "unverified-pending-white", disk: disk(15,0,color:.white),
                                        witnesses: ["supplied:a","supplied:b","supplied:c"], first: start-0.6,last:start-0.1)
        var unknown = try Bridge(anchors: [hypothetical], epoch: "RepositionedPending:own-calibration")
        for v in input.relocation { try unknown.observe(v); check(unknown.supported.isEmpty, "Missing hand evidence manufactured continuity") }
        output["translatedRecordingControls"] = controls
        output["realRelocationObservationsAbstained"] = input.relocation.count
        output["assertions"] = checks
        output["liveRecognitionEnabled"] = false
        output["scope"] = "Supplied native turns/captures. Larger displacements are injected controls; real relocation lacks complete hand evidence. No new physical identity or turn-time accuracy claim."
        try JSONSerialization.data(withJSONObject: exports, options: [.prettyPrinted,.sortedKeys])
            .write(to: artifacts.appendingPathComponent("sgf-pairs.json"), options: .atomic)
        return output
    }
    static func main() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DeferredCleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try tests(temporary)
        if CommandLine.arguments.count == 3 {
            let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let result = try recordingReplay(input, folder: temporary,
                                             artifacts: URL(fileURLWithPath: CommandLine.arguments[2]).deletingLastPathComponent())
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
                .write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        }
        print("PASS: \(checks) assertions; native deferred cleanup/turn persistence tests")
    }
}
