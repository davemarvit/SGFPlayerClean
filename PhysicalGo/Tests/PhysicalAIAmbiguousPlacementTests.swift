// Replays recorded spatial-assignment evidence through the real AI controller.
// No engine, camera, hardware bridge, audio or live game storage is used.
import Foundation

private struct AssignmentRecording: Decodable {
    struct Frame: Decodable {
        let frameID:Int
        let capturedAt:Double
        let handObstructed:Bool
        let lightingBlocked:Bool
        let readings:[IntersectionReading]
        let footprints:[StoneFootprint]
        let placementFits:[StoneFootprint]
        var observation:BoardObservation {
            var o=BoardObservation(readings:readings,size:19,footprints:footprints,placementFits:placementFits)
            o.handObstructed=handObstructed;o.lightingBlocked=lightingBlocked
            return o
        }
    }
    let validFrames:[Frame]
    let ambiguousFrames:[Frame]
}

@MainActor private final class AssignmentScenario {
    final class Clock {var now=100.0}
    let clock=Clock()
    let ai:PhysicalAI
    let folder:URL
    init(root:URL,moves:[Int?],humanBlack:Bool=false,pending:Bool=false,hints:Bool=false) throws {
        folder=root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var settings=PhysicalAISettings();settings.size=19;settings.humanBlack=humanBlack
        var saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:moves.map {.init(point:$0)},pendingPlacement:pending)
        let player=SGFPlayer();player.load(game:PhysicalAI.game(saved));player.seek(to:moves.count)
        var prior=player.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"}
        if pending,let p=moves.last ?? nil {prior[p]="empty"}
        saved.verifiedPosition = .init(cells:prior,cameraContext:"recorded-assignment-grid")
        try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
        let c=clock
        let laser=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,uptime:{c.now})
        ai=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:laser,uptime:{c.now})
        ai.centeringEnabled=hints
        laser.observeCamera(hand:false,valid:true,capturedAt:c.now,now:c.now,context:"recorded-assignment-grid")
        ai.resume()
    }
    func feed(_ input:BoardObservation,step:Double=0.2) {
        clock.now+=step;var o=input;o.capturedAt=clock.now
        ai.consume(o,now:clock.now)
    }
    func replay(_ frames:[AssignmentRecording.Frame]) {
        for (i,f) in frames.enumerated() {
            feed(f.observation,step:i==0 ? 0.2:f.capturedAt-frames[i-1].capturedAt)
        }
    }
    func feed(_ o:BoardObservation,count:Int) {for _ in 0..<count {feed(o)}}
    func clean(_ cells:[String]?=nil)->BoardObservation {
        var o=BoardObservation(readings:(cells ?? ai.cells).enumerated().map {
            .init(row:$0.offset/19,col:$0.offset%19,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)
        },size:19)
        o.handObstructed=false;return o
    }
}

@main struct PhysicalAIAmbiguousPlacementTests {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("assignment-replay-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AIAmbiguousPlacement/observations.json")
        let recording=try JSONDecoder().decode(AssignmentRecording.self,from:Data(contentsOf:fixture))
        var checks=0
        func check(_ result:Bool,_ message:String) {precondition(result,message);checks+=1}
        func replace(_ o:BoardObservation,_ point:Int,_ color:Occupancy,_ confidence:Double)->BoardObservation {
            var result=o
            result.readings[point] = .init(row:point/19,col:point%19,occupancy:color,confidence:confidence,delta:0)
            return result
        }

        // This optional mode demonstrates the actual old failure against an
        // unpatched runtime; normal regression mode requires abstention.
        let reproduce=ProcessInfo.processInfo.environment["PHYSICAL_GO_EXPECT_AMBIGUITY_BUG"]=="1"
        for hints in [false,true] {
            let good=try AssignmentScenario(root:root,moves:[72],hints:hints)
            good.replay(recording.validFrames)
            check(good.ai.snapshot!.moves.map(\.point)==[72,180],"Recorded legitimate White180 at fitted offset .28 must remain accepted")
            good.ai.pause()

            let bad=try AssignmentScenario(root:root,moves:[72,180,300],hints:hints)
            let before=bad.ai.snapshot!.moves.map(\.point),anchor=bad.ai.timing.anchor
            bad.replay(recording.ambiguousFrames)
            if reproduce {
                check(bad.ai.snapshot!.moves.map(\.point)==before+[275],"Baseline must reproduce recorded wrong intersection275")
            } else {
                check(bad.ai.snapshot!.moves.map(\.point)==before,"Between-intersection recording must never append point275")
                check(bad.ai.status.contains("intersection is unclear"),"Spatial ambiguity must explain why play is waiting")
                check(bad.ai.timing.anchor==anchor && bad.ai.pendingPoint==nil,"Ambiguous placement must not switch the clock or create an AI target")
                let persisted=try JSONDecoder().decode(PhysicalAI.Snapshot.self,from:Data(contentsOf:bad.folder.appendingPathComponent("current.json")))
                check(persisted.moves.map(\.point)==before,"Ambiguity must not persist a phantom move")
                bad.feed(bad.clean(),count:4)
                check(bad.ai.phase == .human && bad.ai.snapshot!.moves.map(\.point)==before,"Removing ambiguous stone restores the prior physical position")
            }
            bad.ai.pause()
        }
        if reproduce {print("Recorded baseline reproduced: \(checks) checks passed");return}

        let live=try AssignmentScenario(root:root,moves:[72,180,300])
        live.feed(live.clean(),count:4)
        check(live.ai.phase == .human && live.ai.timing.anchor != nil,"Prior board must establish an actively running human turn")
        let runningAnchor=live.ai.timing.anchor
        live.replay(recording.ambiguousFrames)
        check(live.ai.phase == .human && live.ai.snapshot!.moves.count==3,"Recorded ambiguity must also abstain during an already running human turn")
        check(live.ai.timing.anchor==runningAnchor && live.ai.pendingPoint==nil,"Ambiguity must preserve the running human clock without an AI target")
        live.ai.pause()

        // Synthetic color reversal preserves every measured confidence and
        // geometric fit; it is not a second camera recording. A leading Black
        // pass reverses the logical stone colors at the same coordinates.
        func reverseColors(_ input:BoardObservation)->BoardObservation {
            var output=input
            output.readings=input.readings.map {r in
                .init(row:r.row,col:r.col,occupancy:r.occupancy == .white ? .black:r.occupancy == .black ? .white:r.occupancy,confidence:r.confidence,delta:r.delta)
            }
            return output
        }
        for hints in [false,true] {
            let h=try AssignmentScenario(root:root,moves:[nil,72,180,300],humanBlack:true,hints:hints)
            h.feed(h.clean(),count:4)
            let before=h.ai.snapshot!.moves.map(\.point),anchor=h.ai.timing.anchor
            for (i,f) in recording.ambiguousFrames.enumerated() {
                h.feed(reverseColors(f.observation),step:i==0 ? 0.2:f.capturedAt-recording.ambiguousFrames[i-1].capturedAt)
            }
            check(h.ai.snapshot!.moves.map(\.point)==before && h.ai.status.contains("intersection is unclear"),"Color-reversed recorded geometry must abstain for Black with either hint preference")
            check(h.ai.timing.anchor==anchor && h.ai.pendingPoint==nil,"Black halfway geometry must preserve the clock and avoid an AI target")
            h.feed(h.clean(),count:4)
            check(h.ai.phase == .human && h.ai.snapshot!.moves.map(\.point)==before,"Removing ambiguous Black stone must restore prior position")
            h.ai.pause()
            let good=try AssignmentScenario(root:root,moves:[nil,72],humanBlack:true,hints:hints)
            for (i,f) in recording.validFrames.enumerated() {
                good.feed(reverseColors(f.observation),step:i==0 ? 0.2:f.capturedAt-recording.validFrames[i-1].capturedAt)
            }
            check(good.ai.snapshot!.moves.map(\.point)==[nil,72,180],"Color-reversed legitimate geometry must still accept Black180")
            good.ai.pause()
        }

        // Synthetic variants isolate controller behavior without claiming to
        // reconstruct pixels: confidence boundary, both colors, edge bounds,
        // and uncertainty elsewhere that still may retain verified history.
        for black in [false,true] {
            for hints in [false,true] {
                for point in [0,18,342,360,275] {
                    let history:[Int?]=black ? [nil,72,180,300]:[72,180,300]
                    let h=try AssignmentScenario(root:root,moves:history,humanBlack:black,hints:hints)
                    h.feed(h.clean(),count:4)
                    let anchor=h.ai.timing.anchor
                    var cells=h.ai.cells;cells[point]=black ? "black":"white"
                    let clean=h.clean(cells),neighbor=point%19==18 ? point-1:point+1
                    let blocked=replace(clean,neighbor,.empty,0.79)
                    h.feed(blocked,count:4)
                    check(h.ai.snapshot!.moves.map(\.point)==history,"Low-confidence adjacent expected-empty crossing must block either color with either hint preference, including corners")
                    check(h.ai.timing.anchor==anchor && h.ai.pendingPoint==nil,"Neither hint preference may switch the human clock or create an AI target for ambiguous placement")
                    // Changing an optional display preference while ambiguity
                    // remains cannot authorize a previously rejected move.
                    h.ai.centeringEnabled = !hints
                    h.feed(blocked,count:4)
                    let persisted=try JSONDecoder().decode(PhysicalAI.Snapshot.self,from:Data(contentsOf:h.folder.appendingPathComponent("current.json")))
                    check(persisted.moves.map(\.point)==history && h.ai.timing.anchor==anchor,"Toggling hints during either-color ambiguity must preserve saved history and the running clock")
                    h.ai.centeringEnabled=hints
                    // Two witnesses followed by a blocked observation must start
                    // a new streak, even when the board values then look identical.
                    let threshold=replace(clean,neighbor,.empty,0.8)
                    h.feed(threshold,count:2);h.feed(blocked);h.feed(threshold)
                    check(h.ai.snapshot!.moves.count==history.count,"A blocked neighbor must erase earlier placement witnesses")
                    h.feed(threshold,count:3)
                    check(h.ai.snapshot!.moves.last?.point==point && h.ai.snapshot!.moves.count==history.count+1,"Fresh .8-confidence neighbors must permit normal temporal confirmation")
                    h.ai.pause()
                }
            }
        }
        let distant=try AssignmentScenario(root:root,moves:[72,180,300])
        var distantBoard=distant.ai.cells;distantBoard[275]="white"
        let farUncertain=replace(distant.clean(distantBoard),0,.uncertain,0)
        distant.feed(farUncertain,count:4)
        check(distant.ai.snapshot!.moves.last?.point==275,"Unrelated far-away uncertainty must remain retainable")
        distant.ai.pause()

        // Pending AI stones already exist in game history; their physical
        // confirmation must still require fresh spatial evidence. Cover both
        // standalone placement and placement plus a prompt legal human reply.
        for humanBlack in [false,true] {
            for hints in [false,true] {
                for reply in [false,true] {
                    // Prepend a Black pass to reverse all stone colors while
                    // retaining identical target and neighboring geometry.
                    let history:[Int?]=humanBlack ? [nil,72,180,300]:[72,180,300]
                    let h=try AssignmentScenario(root:root,moves:history,humanBlack:humanBlack,pending:true,hints:hints)
                    let anchor=h.ai.timing.anchor
                    var cells=h.ai.cells;if reply {cells[275]=humanBlack ? "black":"white"}
                    let clean=h.clean(cells),blocked=replace(clean,319,.uncertain,0.7)
                    h.feed(blocked,count:5)
                    check(h.ai.snapshot!.pendingPlacement && h.ai.snapshot!.moves.map(\.point)==history,"Unresolved AI placement of either color must not confirm itself or authorize a reply with either hint preference")
                    let persisted=try JSONDecoder().decode(PhysicalAI.Snapshot.self,from:Data(contentsOf:h.folder.appendingPathComponent("current.json")))
                    check(persisted.pendingPlacement && persisted.moves.map(\.point)==history && h.ai.timing.anchor==anchor,"Ambiguous pending placement must preserve saved pending state, history and clock")
                    h.feed(clean,count:2);h.feed(blocked);h.feed(clean)
                    check(h.ai.snapshot!.pendingPlacement && h.ai.snapshot!.moves.count==history.count,"Pending placement cannot reuse witnesses across an unresolved neighbor")
                    h.feed(clean,count:3)
                    check(!h.ai.snapshot!.pendingPlacement && h.ai.snapshot!.moves.count==history.count+(reply ? 1:0),"Fresh clear placement must complete with or without a prompt reply")
                    h.ai.pause()
                }
            }
        }
        print("Physical AI ambiguous placement: \(checks) checks passed")
    }
}
