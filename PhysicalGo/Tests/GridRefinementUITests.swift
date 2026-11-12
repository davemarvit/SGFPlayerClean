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
        let expected=[300,60,307,269,268,249,287,73,71,52,51,53,70,111,66,230,250,192,231,212,154,194,213,294,214,263,317,262,282,186]
        // Legacy classifications repeatedly call White 230 empty after Black
        // 250 appears. Preserve that contradiction for review, not invented
        // chronology. The first 15 moves have independently sufficient evidence.
        check(recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}==Array(expected.prefix(15)),"Accepted prefix changed")
        check(recorder.hasDeferredMoves && recorder.reviewHistory.unresolved==4 && recorder.reviewHistory.retainedMoveCount==7,"Legacy contradictory readings lost review evidence")
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let originalReviews=try encoder.encode(recorder.reviewHistory)
        try recorder.flushStorage()
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
        check(try encoder.encode(model.recorder.reviewHistory)==originalReviews,"Grid callback erased or reordered review history")
        check(model.recorder.sgf()==sgf,"Grid callback changed confirmed SGF")
        check(model.hasReference && model.referenceCalibration==oldReference,"Grid callback lost or relabeled reference pixels")
        let persisted=try archive.load()!
        check(persisted.enabled && persisted.referenceCalibration==oldReference && persisted.calibration==model.calibration,"Reference archive was disabled or mispaired")
        print("Grid refinement retained 15 saved, four review sections and seven ordered later moves; reference preserved")
        // The final captured frames contain a further black move at 43. Replay
        // twelve distinct actual frames with the preserved reference, not a
        // repeated photograph or simulated stone adjustment.
        let expectedFinal=expected+[43]
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
        check(model.recorder.sgf()==sgf,"Fresh photos silently rewrote unresolved chronology")
        let interpreted=model.recorder.interpretedBoard!
        check(interpreted.stones.count==31 && expectedFinal.enumerated().allSatisfy { index,point in
            interpreted.grid[point/19][point%19] == (index.isMultiple(of:2) ? Stone.black:Stone.white)
        },"Fresh reference-backed photos failed to preserve all 31 physical stones")
        check(model.recorder.reviewHistory.sections.prefix(recorder.reviewHistory.sections.count).map(\.id)==recorder.reviewHistory.sections.map(\.id),"Fresh frames discarded earlier review evidence")
        let finalReviews=try encoder.encode(model.recorder.reviewHistory)
        try model.recorder.flushStorage()
        let copy=output.appendingPathComponent("Recovered test.sgf")
        try model.recorder.sgf().write(to:copy,atomically:true,encoding:.utf8)
        try Data(contentsOf:saved.deletingPathExtension().appendingPathExtension("reviews.json")).write(to:copy.deletingPathExtension().appendingPathExtension("reviews.json"))
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
        // Alternate a real, aligned photo with unreadable current pixels. A
        // rejected frame must not flip the display to raw perspective, freeze
        // the previous photo, or become evidence for the saved game.
        let clearPhoto=model.image!,displayGeometry=model.rectifiedGeometry!
        let displaySize=model.rectifiedImage!.width
        let context=CGContext(data:nil,width:clearPhoto.width,height:clearPhoto.height,
            bitsPerComponent:8,bytesPerRow:clearPhoto.width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0)!
        context.setFillColor(gray:0.5,alpha:1)
        context.fill(CGRect(x:0,y:0,width:clearPhoto.width,height:clearPhoto.height))
        let obscured=context.makeImage()!
        let clockBefore=try encoder.encode(model.recorder.clock.engine)
        for cycle in 0..<3 {
            model.receive(obscured)
            wait {model.image === obscured && model.alignmentNeedsRecovery}
            check(model.rectifiedImage?.width==displaySize && model.rectifiedGeometry?.calibration==displayGeometry.calibration,
                  "Rejected alignment changed the displayed board geometry")
            check(model.observation==nil && model.trackedBoardObservation==nil && !model.stable,
                  "Display transform authorized recognition from an unverified frame")
            let displayed=GrayFrame(image:model.rectifiedImage!)!
            check(abs(displayed.sample(.init(x:0.5,y:0.5))!-0.5)<0.03,
                  "Rejected alignment left old camera pixels on screen")
            let clockAfter=try encoder.encode(model.recorder.clock.engine)
            check(model.recorder.sgf()==sgf && clockAfter==clockBefore,
                  "Presentation recovery changed moves or clock balances")
            if cycle==0 {
                try snapshot(CameraCanvas(model:model),"alignment-checking",NSSize(width:1000,height:900))
                model.detectGrid()
                check(model.rectifiedImage != nil && model.rectifiedGeometry?.calibration==displayGeometry.calibration,
                      "Starting a full grid search switched to raw perspective")
                wait {!model.detectingGrid}
                check(model.alignmentNeedsRecovery && model.observation==nil && model.rectifiedImage != nil,
                      "Failed grid search lost presentation or accepted evidence")
            }
            model.receive(clearPhoto)
            wait {model.image === clearPhoto && !model.alignmentNeedsRecovery && model.observation != nil}
            check(model.rectifiedImage?.width==displaySize,"Recovered view changed size")
        }
        model.straightenBoard=false;model.perspectiveViewChanged()
        wait {model.rectifiedImage==nil}
        try snapshot(CameraCanvas(model:model),"camera-perspective",NSSize(width:1000,height:900))
        model.prepareCameraStart()
        check(try encoder.encode(model.recorder.reviewHistory)==finalReviews,"Camera startup lost review history")
        model.size=13;model.boardSizeChanged()
        check(model.recorder.pendingMoveCount==0,"Different board size retained incompatible pending history")
        let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:copy)
        check(restored.moveCount==15 && restored.hasDeferredMoves,"Recovery checkpoint is incomplete")
        check(try encoder.encode(restored.reviewHistory)==finalReviews,"Recovery lost review evidence or ordered later moves")
        window.orderOut(nil)
        print("PASS: \(checks) grid/UI checks: actual 31-move session, real grid callback, preserved reference and review evidence, rotated coordinates and native previews.")
    }
}
