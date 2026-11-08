import Foundation
import AppKit
import SwiftUI

@main struct CaptureContinuationTests {
    struct Entry:Decodable {
        let time:Double
        let event:String?
        let frame:Int?
        let position:String?
        let footprints:[StoneFootprint]?
        let placementFits:[StoneFootprint]?
    }
    @MainActor static func main()throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        let root=URL(fileURLWithPath:"PhysicalGo/.build/CaptureStallUI")
        let output=root.appendingPathComponent("Test-\(UUID().uuidString)")
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CaptureContinuation")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let seed=output.appendingPathComponent("Recovered test.sgf")
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("initial.sgf"),to:seed)
        let recorder=GameRecorder(storage:output);try recorder.restoreSavedGame(from:seed)
        let prefix=recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}
        let expected=prefix+[44,47,46,27,26,29,48,49,28,31,32,67,47,87,86,68]
        let entries=try JSONDecoder().decode([Entry].self,from:Data(contentsOf:fixture.appendingPathComponent("observations.json")))
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;if !condition {fatalError(message)}}
        func view(_ signature:String,_ size:Int=19)->BoardObservation {
            BoardObservation(readings:signature.enumerated().map {i,c in
                .init(row:i/size,col:i%size,occupancy:c=="B" ? .black : c=="W" ? .white : c=="?" ? .uncertain : .empty,confidence:1,delta:0)
            },size:size)
        }
        var previous=48
        for entry in entries {
            if let event=entry.event {
                if event=="resumed" {recorder.resume()}
                else if event=="paused" {recorder.pause()}
                else if !event.contains("Checking that the physical board matches") {
                    recorder.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"),preserveOrder:event.contains("Finding the grid"))
                }
            } else if let position=entry.position {
                var observation=view(position)
                observation.footprints=entry.footprints ?? [];observation.placementFits=entry.placementFits ?? []
                recorder.consume(observation,now:entry.time)
                let accepted=recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}
                check(accepted==Array(expected.prefix(accepted.count)),"Actual chronology changed at frame \(entry.frame!)")
                if recorder.moveCount != previous {print("Frame \(entry.frame!): \(recorder.moveCount) saved, \(recorder.pendingMoveCount) pending");previous=recorder.moveCount}
            }
        }
        check(recorder.moveCount==64 && recorder.pendingMoveCount==0,"Actual capture session did not finish: \(recorder.status)")
        check(recorder.interpretationWarnings.isEmpty,"Recovered game retained stale red rings")
        check(recorder.positions[52].grid[2][7] == .white && recorder.positions[53].grid[2][7]==nil,"First capture did not preserve before/after boards")
        check(recorder.positions[56].grid[2][9] == .white && recorder.positions[57].grid[2][9]==nil,"Second capture did not preserve before/after boards")
        check(recorder.positions[61].grid[2][9] == .black,"Later play on the captured point was lost")
        recorder.seek(52);check(recorder.reviewedBoard==recorder.positions[52],"Backward review missed pre-capture position")
        recorder.seek(53);check(recorder.reviewedBoard==recorder.positions[53],"Forward review missed capture")
        recorder.returnToLatest();recorder.pause();try recorder.savePendingCheckpoint()
        let parsed=try SGFGame.from(tree:SGFParser.parse(text:recorder.sgf()))
        check(parsed.moves.count==64,"Recovered SGF is not complete")
        let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:seed)
        check(restored.moveCount==64 && restored.pendingMoveCount==0,"Recovered checkpoint changed after reload")
        try seed.path.write(to:root.appendingPathComponent("recovered-path.txt"),atomically:true,encoding:.utf8)

        // An obstructing hand must not contradict a locally seen white move.
        // A one-frame whole-board tail can be extended only with repeated
        // previous-stone / next-empty sightings, never first-appearance sorting.
        let small=GameRecorder(storage:nil);var values=Array(repeating:Character("."),count:81),time=0.0
        func feed(_ states:[Character],_ count:Int) {for _ in 0..<count {time += 0.21;small.consume(view(String(states),9),now:time)}}
        small.start(size:9);feed(values,5);values[0]="B";feed(values,5)
        values[10]="W";feed(values,1)
        var partial=values;for i in 50..<70 {partial[i]="?"};feed(partial,2)
        var hand=partial;for i in 1...25 {hand[i]="B"};feed(hand,3)
        values[20]="B";feed(values,8)
        check(small.moveCount==3 && small.game.moves.compactMap{$0.1.map{$0.1*9+$0.0}}==[0,10,20],"Broad hand corruption blocked locally witnessed continuation")

        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        try model.openSample(from:fixture)
        let deadline=Date().addingTimeInterval(40)
        while model.observation==nil && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
        check(model.observation != nil,"Final photo analysis timed out")
        let stalled=output.appendingPathComponent("Stalled comparison.sgf")
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("stalled.sgf"),to:stalled)
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("stalled.pending.json"),to:stalled.deletingPathExtension().appendingPathExtension("pending.json"))
        try model.recorder.restoreSavedGame(from:stalled)
        let marks=InterpretationDetectionMarks.make(board:model.recorder.interpretedBoard,observation:model.observation,size:19)
        let untracked=Set(marks.filter{$0.kind == .untracked}.map(\.point))
        check(untracked==[32,47,67,68,86,87],"Unified board did not show the six camera-only stones: \(untracked)")
        check(model.recorder.moveCount==51 && model.recorder.pendingMoveCount==7,"Detection overlay edited the game")
        check(InterpretationDetectionMarks.make(board:model.recorder.interpretedBoard,observation:nil,size:19).isEmpty,"Missing observation invented marks")
        check(InterpretationDetectionMarks.make(board:model.recorder.interpretedBoard,observation:model.observation,size:9).isEmpty,"Wrong grid size drew detection marks")

        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1500,height:1150),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua)
        func snapshot<V:View>(_ content:V,_ name:String,_ size:NSSize)throws {
            let host=NSHostingView(rootView:content);window.setContentSize(size);window.contentView=host;window.orderFront(nil)
            RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
        }
        try snapshot(ExperimentView(model:model),"unified-stalled",NSSize(width:1500,height:1150))
        try model.recorder.restoreSavedGame(from:seed)
        let correctedMarks=InterpretationDetectionMarks.make(board:model.recorder.interpretedBoard,observation:model.observation,size:19)
        check(!correctedMarks.contains{$0.kind == .untracked},"Confirmed moves still have camera-only rings")
        try snapshot(ExperimentView(model:model),"unified-recovered",NSSize(width:1500,height:1150))
        try snapshot(DetectionInspectionView(model:model,recorder:model.recorder),"inspection",NSSize(width:520,height:650))
        try snapshot(CameraCanvas(model:model),"camera-small-coordinates",NSSize(width:1000,height:900))
        window.orderOut(nil)
        print("PASS: \(checks) capture-continuation checks: 64 exact moves, both captures, replay/reload, local order through obstruction and unified native board.")
    }
}
