import Foundation
import AppKit
import SwiftUI
import ImageIO

@main struct GridRefinementUITests {
    struct Entry:Decodable {
        let time:Double
        let event:String?
        let position:String?
        let footprints:[StoneFootprint]?
        let placementFits:[StoneFootprint]?
    }
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        let root=URL(fileURLWithPath:"PhysicalGo/.build/GridResetUI")
        let output=root.appendingPathComponent("Test-\(UUID().uuidString)")
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/GridRefinement")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        func wait(_ ready:()->Bool) {
            let deadline=Date().addingTimeInterval(40)
            while !ready() && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
            check(ready(),"Timed out waiting for native async operation")
        }
        // These are the actual observations before the grid-search reset, including
        // hands, displaced stones and a briefly mistaken candidate, in time order.
        let entries=try JSONDecoder().decode([Entry].self,from:Data(contentsOf:fixture.appendingPathComponent("observations.json")))
        let recorder=GameRecorder(storage:output)
        let start=entries.first!.time
        let empty=BoardObservation(readings:(0..<361).map{.init(row:$0/19,col:$0%19,occupancy:.empty,confidence:1,delta:0)},size:19)
        for i in 0..<6 {recorder.consume(empty,now:start-2+Double(i)*0.21)}
        recorder.start(size:19,now:start-0.9)
        for e in entries {
            if let event=e.event {
                if event=="paused" {recorder.pause()}
                else if event=="resumed" {recorder.resume()}
                else if !event.contains("Checking that the physical board matches") {
                    recorder.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"),preserveOrder:event.contains("Finding the grid"))
                }
            } else if let position=e.position {
                let readings=position.enumerated().map {i,c in IntersectionReading(row:i/19,col:i%19,occupancy:c=="B" ? .black : c=="W" ? .white : c=="?" ? .uncertain : .empty,confidence:1,delta:0)}
                recorder.consume(BoardObservation(readings:readings,size:19,footprints:e.footprints ?? [],placementFits:e.placementFits ?? []),now:e.time)
            }
        }
        recorder.pause()
        let pending=[51,53,70,111,66,230,250,192,231,212,154,194,213,294,214,263,317,262,282,186]
        check(recorder.moveCount==10 && recorder.pendingMoveCount==20,"Actual pre-search session changed: \(recorder.status)")
        check(recorder.pendingConfidence.compactMap(\.point)==pending,"Actual chronology reordered")
        check(recorder.interpretationWarnings.contains(51),"Off-center move 11 must retain its ring")
        try recorder.savePendingCheckpoint()
        let saved=recorder.autosaveURL!
        let archive=ReferenceArchive(url:output.appendingPathComponent("reference.plist"))
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:archive,recordingStorage:nil)
        try model.openSample(from:fixture)
        wait {model.observation != nil && model.rectifiedImage != nil}
        try model.recorder.restoreSavedGame(from:saved)
        let oldReference=model.referenceCalibration!
        let sgf=model.recorder.sgf()
        model.detectGrid()
        wait {!model.detectingGrid && model.observation != nil && !model.alignmentNeedsRecovery}
        check(model.calibration != nil,"Actual grid search failed")
        check(model.recorder.pendingConfidence.compactMap(\.point)==pending,"Grid callback erased or reordered pending history")
        check(model.recorder.interpretedBoard?.stones.count==30,"Main interpretation lost physical moves")
        check(model.recorder.interpretationWarnings.contains(51),"Grid callback lost red warnings")
        check(model.recorder.sgf()==sgf,"Grid callback changed confirmed SGF")
        check(model.hasReference && model.referenceCalibration==oldReference,"Grid callback lost or relabeled reference pixels")
        let persisted=try archive.load()!
        check(persisted.enabled && persisted.referenceCalibration==oldReference && persisted.calibration==model.calibration,"Reference archive was disabled or mispaired")
        print("Grid refinement retained 10 saved + 20 pending; reference preserved; warnings \(model.recorder.interpretationWarnings.sorted())")
        // The final captured frames contain a further black move at 43. Replay
        // twelve distinct actual frames with the preserved reference, not a
        // repeated photograph or simulated stone adjustment.
        let expectedPending=pending+[43]
        let reference=GrayFrame(image:persisted.image)!
        model.recorder.resume()
        var time=ProcessInfo.processInfo.systemUptime
        for frameID in 567...578 {
            let url=fixture.appendingPathComponent("stable/\(String(format:"%06d",frameID)).png")
            let source=CGImageSourceCreateWithURL(url as CFURL,nil)!
            let pixels=GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
            let view=BoardDetector.detect(frame:pixels,reference:reference,calibration:model.calibration!,threshold:0.13,referenceCalibration:oldReference)!
            time += 0.21;model.recorder.consume(view,now:time)
        }
        model.recorder.pause()
        check(model.recorder.moveCount==10 && model.recorder.pendingMoveCount==21,"Fresh reference-backed views lost chronology: \(model.recorder.status)")
        check(model.recorder.pendingConfidence.compactMap(\.point)==expectedPending,"Fresh frames reordered the moves")
        check(model.recorder.interpretationWarnings.contains(51),"An off-center stone locked without centering")
        try model.recorder.savePendingCheckpoint()
        let copy=output.appendingPathComponent("Recovered test.sgf")
        try model.recorder.sgf().write(to:copy,atomically:true,encoding:.utf8)
        try Data(contentsOf:saved.deletingPathExtension().appendingPathExtension("pending.json")).write(to:copy.deletingPathExtension().appendingPathExtension("pending.json"))
        try copy.path.write(to:root.appendingPathComponent("recovered-path.txt"),atomically:true,encoding:.utf8)
        try JSONEncoder().encode(model.calibration).write(to:root.appendingPathComponent("refined-calibration.json"))
        // Labels must read in screen order for every supported size and rotation.
        for size in [9,13,19] {for turn in 0..<4 {
            let labels=BoardCoordinates.labels(size:size,orientation:BoardOrientation(turn))
            check(labels.count==4*size,"Missing edge labels")
            check(!labels.contains{$0.text=="I"},"Go coordinates must skip I")
            for i in 0..<size {
                let expected=[ImagePoint(x:Double(i),y:-0.55),ImagePoint(x:Double(i),y:Double(size-1)+0.55),ImagePoint(x:-0.55,y:Double(i)),ImagePoint(x:Double(size-1)+0.55,y:Double(i))]
                for edge in 0..<4 {
                    let l=labels[4*i+edge],last=Double(size-1)
                    let p=BoardOrientation(turn).display(.init(x:l.grid.x/last,y:l.grid.y/last))
                    check(abs(p.x*last-expected[edge].x)<1e-8 && abs(p.y*last-expected[edge].y)<1e-8,"Coordinate rotated away from screen edge")
                    check(l.text==(edge<2 ? String(Array("ABCDEFGHJKLMNOPQRST")[i]) : String(size-i)),"Coordinate text disagrees with screen")
                }
            }
        }}
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1500,height:1150),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua)
        func snapshot<V:View>(_ content:V,_ name:String,_ size:NSSize)throws {
            let host=NSHostingView(rootView:content)
            window.setContentSize(size);window.contentView=host;window.orderFront(nil)
            RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
        }
        try snapshot(ExperimentView(model:model),"full-interface",NSSize(width:1500,height:1150))
        try snapshot(RecordingView(model:model,recorder:model.recorder).padding(16),"recording-panel",NSSize(width:480,height:1150))
        for turn in 0..<4 {
            while model.orientation.turns != turn {model.rotateView()}
            try snapshot(CameraCanvas(model:model),"camera-rotation-\(turn)",NSSize(width:1000,height:900))
        }
        model.straightenBoard=false;model.perspectiveViewChanged()
        wait {model.rectifiedImage==nil}
        try snapshot(CameraCanvas(model:model),"camera-perspective",NSSize(width:1000,height:900))
        model.prepareCameraStart()
        check(model.recorder.pendingMoveCount==21,"Camera startup lost pending history")
        model.size=13;model.boardSizeChanged()
        check(model.recorder.pendingMoveCount==0,"Different board size retained incompatible pending history")
        let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:copy)
        check(restored.moveCount==10 && restored.pendingMoveCount==21,"Recovery checkpoint is incomplete")
        check(restored.pendingConfidence.compactMap(\.point)==expectedPending,"Recovery lost exact move order")
        window.orderOut(nil)
        print("PASS: \(checks) grid/UI checks: actual 31-move session, real grid callback, preserved reference and warnings, rotated coordinates and native previews.")
    }
}
