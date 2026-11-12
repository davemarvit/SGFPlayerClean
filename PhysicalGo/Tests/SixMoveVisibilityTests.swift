import Foundation
import AppKit
import SwiftUI

@main struct SixMoveVisibilityTests {
    struct Entry:Decodable {
        let time:Double
        let event:String?
        let position:String?
        let footprints:[StoneFootprint]?
    }
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        let app=NSApplication.shared;app.setActivationPolicy(.accessory)
        let root=URL(fileURLWithPath:"PhysicalGo/.build/SixMoveVisibility")
        let output=root.appendingPathComponent("Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let recorder=GameRecorder(storage:output)
        let entries=try JSONDecoder().decode([Entry].self,from:Data(contentsOf:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/SixMoveVisibility/session.json")))
        var checks=0,last:BoardObservation?
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        for entry in entries {
            if let event=entry.event {
                switch event {
                case "start":recorder.start(size:19,now:entry.time)
                case "paused":recorder.pause()
                case "resumed":recorder.resume()
                case "finished":recorder.finish()
                default:
                    if !event.contains("Checking that the physical board matches") {
                        recorder.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"),preserveOrder:event.contains("Finding the grid"))
                    }
                }
            } else if let position=entry.position {
                let readings=position.enumerated().map { index,char in
                    IntersectionReading(row:index/19,col:index%19,occupancy:char=="B" ? .black : char=="W" ? .white : char=="?" ? .uncertain : .empty,confidence:1,delta:0)
                }
                let view=BoardObservation(readings:readings,size:19,footprints:entry.footprints ?? [])
                recorder.consume(view,now:entry.time);last=view
            }
        }
        let expected=[300,60,307,269,268,249,287,73,250,230,251,71,263]
        check(recorder.moveCount==6 && recorder.pendingMoveCount==7,"Six-move session no longer reproduces")
        check(recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}+recorder.pendingConfidence.compactMap(\.point)==expected,"Lost or reordered an actual move")
        check(recorder.interpretationWarnings==[287],"Expected only move 7 to need adjustment: \(recorder.interpretationWarnings)")
        check(recorder.interpretedBoard?.stones.count==13 && recorder.reviewedBoard?.stones.count==6,"Live and saved positions are not separate")
        check(recorder.lastInterpretedPoint==263,"Last-move dot did not reach move 13")
        check(recorder.tentativeNextPlayer == .white,"Paused pending game displays wrong player")
        check(!recorder.canPass,"Pass could discard the pending sequence")
        try recorder.savePendingCheckpoint()
        let saved=recorder.autosaveURL!
        // Preserve this six-move snapshot before another recorder legitimately
        // advances the same file. Independent stores must not race that path.
        let pendingCopy=try Data(contentsOf:saved.deletingPathExtension().appendingPathExtension("pending.json"))
        try saved.path.write(to:root.appendingPathComponent("restorable-path.txt"),atomically:true,encoding:.utf8)
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        try model.recorder.restoreSavedGame(from:saved)
        model.observation=last
        check(model.recorder.pendingMoveCount==7 && model.recorder.interpretationWarnings==[287],"Restore lost pending confidence")
        check(model.recorder.moveCount==6,"Restoring a checkpoint prematurely wrote SGF")
        model.prepareCameraStart()
        model.handleCameraStatus("Starting camera",state:.starting)
        check(model.recorder.pendingMoveCount==7 && model.recorder.interpretationWarnings==[287],"Camera startup erased restored pending moves")
        model.toggleFreeze();model.toggleFreeze()
        check(model.recorder.pendingMoveCount==7,"Freeze erased restored chronology")
        model.recorder.seek(0)
        check(model.recorder.reviewedBoard?.stones.isEmpty==true && model.recorder.interpretedBoard?.stones.count==13,"Review changed live interpretation")
        model.recorder.seek(6)
        check(model.recorder.reviewedBoard?.stones.count==6 && model.recorder.pendingMoveCount==7,"Review lost pending game")

        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:480),styleMask:[.titled],backing:.buffered,defer:false)
        let host=NSHostingView(rootView:RecordedBoard(recorder:model.recorder,orientation:BoardOrientation(0),showsLivePosition:true,onPoint:{_ in}).frame(width:420,height:420).padding(30))
        window.appearance=NSAppearance(named:.darkAqua)
        window.contentView=host;window.orderFront(nil)
        func image(_ name:String)throws->NSBitmapImageRep {
            RunLoop.main.run(until:Date().addingTimeInterval(0.15));host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
            return bitmap
        }
        func redCount(_ bitmap:NSBitmapImageRep)->Int {
            var count=0
            for y in 0..<bitmap.pixelsHigh {for x in 0..<bitmap.pixelsWide {
                if let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),c.redComponent>0.45,c.redComponent>c.greenComponent*1.8,c.redComponent>c.blueComponent*1.8 {count += 1}
            }}
            return count
        }
        check(redCount(try image("live-pending"))>30,"Main live board did not paint a red ring")
        host.rootView=RecordedBoard(recorder:model.recorder,orientation:BoardOrientation(0),showsLivePosition:false,onPoint:{_ in}).frame(width:420,height:420).padding(30)
        check(redCount(try image("saved-six"))==0,"Saved history unexpectedly contains a pending ring")
        let panel=NSHostingView(rootView:RecordingView(model:model,recorder:model.recorder).frame(width:400).padding(16).background(Color(red:0.18,green:0.18,blue:0.18)))
        window.setContentSize(NSSize(width:432,height:1000));window.contentView=panel
        panel.layoutSubtreeIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        let bitmap=panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
        panel.cacheDisplay(in:panel.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("recording-panel.png"))
        // Simulated physical centering: keep actual final classifications and all
        // other outlines; change only move 7's measured center. No pixels altered.
        var adjusted=last!
        adjusted.footprints=adjusted.footprints.map { shape in
            shape.row*19+shape.col==287 ? StoneFootprint(row:shape.row,col:shape.col,center:.init(x:Double(shape.col),y:Double(shape.row)),radiusCol:shape.radiusCol,radiusRow:shape.radiusRow,quality:shape.quality) : shape
        }
        model.recorder.resume()
        var time=ProcessInfo.processInfo.systemUptime
        for _ in 0..<7 {time += 0.21;model.recorder.consume(adjusted,now:time)}
        check(model.recorder.moveCount==6,"Restored pending moves skipped fresh confirmation")
        time += 0.21;model.recorder.consume(adjusted,now:time)
        check(model.recorder.moveCount==6 && model.recorder.pendingMoveCount==7,"Centering silently erased the still-obscured alternative")
        // The original final reading at neighboring 286 is uncertain. Simulate
        // exposing that vacated point as well; centering alone cannot rule out
        // a second hidden body. This is an explicit synthetic clarity control.
        check(adjusted.signature[286] == .uncertain,"Fixture no longer exercises an obscured alternative")
        var clearReadings=adjusted.readings
        clearReadings[286] = .init(row:286/19,col:286%19,occupancy:.empty,confidence:1,delta:0)
        adjusted=BoardObservation(readings:clearReadings,size:19,footprints:adjusted.footprints,placementFits:adjusted.placementFits)
        for _ in 0..<8 {time += 0.21;model.recorder.consume(adjusted,now:time)}
        check(model.recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}==expected,"Centering move 7 did not save the exact 13 moves: \(model.recorder.status)")
        check(model.recorder.pendingMoveCount==0 && model.recorder.interpretationWarnings.isEmpty,"Resolved rings did not clear")
        for _ in 0..<8 {time += 0.21;model.recorder.consume(last!,now:time)}
        check(model.recorder.moveCount==13 && model.recorder.interpretationWarnings.isEmpty,"Later displacement reopened a locked move")
        model.recorder.pause()
        try model.recorder.flushStorage()
        let completed=GameRecorder(storage:nil);try completed.restoreSavedGame(from:saved)
        check(completed.moveCount==13 && completed.pendingMoveCount==0,"Completed SGF retained obsolete checkpoint")
        // Leave a separate six-saved/seven-pending copy for the user's app update.
        let recovery=output.appendingPathComponent("Recovered test.sgf")
        try recorder.sgf().write(to:recovery,atomically:true,encoding:.utf8)
        try pendingCopy.write(to:recovery.deletingPathExtension().appendingPathExtension("pending.json"))
        try recovery.path.write(to:root.appendingPathComponent("restorable-path.txt"),atomically:true,encoding:.utf8)
        let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:recovery)
        check(restored.moveCount==6 && restored.pendingMoveCount==7 && restored.interpretationWarnings==[287],"Final recovery copy is not intact")
        let bad=output.appendingPathComponent("Mismatched.sgf")
        try completed.sgf().write(to:bad,atomically:true,encoding:.utf8)
        try pendingCopy.write(to:bad.deletingPathExtension().appendingPathExtension("pending.json"))
        do {try GameRecorder(storage:nil).restoreSavedGame(from:bad);check(false,"Mismatched checkpoint accepted")} catch {check(true,"Mismatch rejected")}
        window.orderOut(nil)
        print("PASS: \(checks) actual six-move session checks: 13 interpreted, red-ringed move 7, six saved, native rendering, paused camera startup/review, checkpoint validation, fresh confirmation and exact catch-up after simulated centering.")
    }
}
