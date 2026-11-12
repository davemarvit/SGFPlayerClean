import Foundation
import AppKit
import SwiftUI
import ImageIO

@main struct CenteredStoneTests {
    struct Metadata:Decodable {
        let calibration:BoardCalibration
        let referenceCalibration:BoardCalibration
        let threshold:Double
        let readings:[IntersectionReading]
    }
    @MainActor static func main()throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CenteredStall")
        let root=URL(fileURLWithPath:"PhysicalGo/.build/CenteredStall")
        let output=root.appendingPathComponent("Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var checks=0,original:BoardObservation?,corrected:BoardObservation?
        func check(_ condition:Bool,_ message:String) {checks += 1;if !condition {fatalError(message)}}
        func pixels(_ url:URL)->GrayFrame {GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!)!}
        for name in ["145","166","245"] {
            let folder=fixture.appendingPathComponent(name)
            let m=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
            let observation=BoardDetector.detect(frame:pixels(folder.appendingPathComponent("frame.png")),reference:pixels(folder.appendingPathComponent("empty-reference.png")),calibration:m.calibration,threshold:m.threshold,referenceCalibration:m.referenceCalibration)!
            let changed=Set(observation.readings.indices.filter{observation.readings[$0].occupancy != m.readings[$0].occupancy})
            check(observation.signature[24] == .white,"Shaded white stone is still missing in \(name)")
            // Saved classifications are historical output, not labels for empty
            // wood. Permit formerly uncertain wood to become positively empty,
            // while preserving every known stone and forbidding new stones.
            check(observation.readings.indices.allSatisfy {i in
                i==24 || observation.signature[i]==m.readings[i].occupancy ||
                    (m.readings[i].occupancy == .uncertain && observation.signature[i] == .empty)
            },"Known occupancy changed in \(name): \(changed)")
            if name=="166" {check(m.readings[24].occupancy == .white,"Successful control no longer contains the White stone")}
            else {check(m.readings[24].occupancy == .empty,"Failing sample no longer exercises false emptiness")}
            if name=="245" {original=BoardObservation(readings:m.readings,size:19);corrected=observation}
            print("Frame \(name): white stone 24 recognized; changed points \(changed.sorted())")
        }
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        try model.openSample(from:fixture.appendingPathComponent("245"))
        func waitForView() {
            let deadline=Date().addingTimeInterval(40)
            while model.observation==nil && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
            check(model.observation != nil,"Native analysis timed out")
        }
        waitForView()
        let stalled=output.appendingPathComponent("Stalled comparison.sgf")
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("stalled.sgf"),to:stalled)
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("stalled.pending.json"),to:stalled.deletingPathExtension().appendingPathExtension("pending.json"))
        try model.recorder.restoreSavedGame(from:stalled)
        check(model.recorder.moveCount==65 && model.recorder.pendingMoveCount==4,"Wrong stalled game")
        check(model.recorder.pendingConfidence.allSatisfy{!$0.placementUncertain},"This case should not claim bad placement")
        var verificationTime=ProcessInfo.processInfo.systemUptime
        func verify(_ observation:BoardObservation) {
            for _ in 0..<10 {verificationTime += 0.21;model.recorder.consume(observation,now:verificationTime)}
        }
        verify(original!)
        let oldMessage=RecordingClarity.explanation(recorder:model.recorder,observation:original,orientation:BoardOrientation(3))!
        check(model.recorder.adjustmentIssues[24] != nil && oldMessage.contains("Recorded stones are retained"),"Persistent disagreement did not mark the recorded stone: \(oldMessage)")
        check(!model.recorder.adjustmentIssues.values.contains(.placement),"Pending confirmation incorrectly became a placement warning")
        verify(corrected!)
        let fixedMessage=RecordingClarity.explanation(recorder:model.recorder,observation:corrected,orientation:BoardOrientation(3))!
        check(model.recorder.adjustmentIssues[24]==nil && !model.recorder.adjustmentIssues.values.contains(.placement),"Centered pending moves incorrectly request adjustment: \(fixedMessage)")
        check(model.recorder.positions.last!.grid[1][10] != nil && corrected!.assignmentOffsets[29]!>=0.30 && model.recorder.adjustmentIssues[29]==nil,"An unchanged recorded stone was asked to center itself again")
        check(!fixedMessage.contains("B6"),"Resolved camera disagreement remains displayed")

        // Keep a real spatial warning distinct from a pending confirmation.
        let placement=GameRecorder(storage:nil);placement.start(size:9)
        var values=Array(repeating:Occupancy.empty,count:81),time=0.0
        func feed(_ count:Int,_ shapes:[StoneFootprint]=[]) {
            for _ in 0..<count {
                time += 0.21
                placement.consume(BoardObservation(readings:values.enumerated().map {i,v in .init(row:i/9,col:i%9,occupancy:v,confidence:1,delta:0)},size:9,footprints:shapes),now:time)
            }
        }
        feed(5);values[10] = .black
        feed(8,[StoneFootprint(row:1,col:1,center:.init(x:1.36,y:1),radiusCol:0.42,radiusRow:0.42,quality:1)])
        check(placement.adjustmentIssues[10] == .placement && RecordingClarity.explanation(recorder:placement,observation:nil,orientation:BoardOrientation(0))?.contains("intersection is ambiguous")==true,"Genuine displacement lost its actionable message")

        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1500,height:1150),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua)
        func snapshot(_ name:String)throws {
            let host=NSHostingView(rootView:ExperimentView(model:model));window.contentView=host;window.orderFront(nil)
            RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
        }
        verify(original!);model.observation=original;try snapshot("clarity-before")
        verify(corrected!);model.observation=corrected;try snapshot("clarity-corrected")
        try model.openSample(from:fixture.appendingPathComponent("final"));waitForView()
        let recovered=output.appendingPathComponent("Recovered test.sgf")
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("recovered.sgf"),to:recovered)
        try model.recorder.restoreSavedGame(from:recovered)
        let expected=Array(model.recorder.game.moves.prefix(64)).compactMap{$0.1.map{$0.1*19+$0.0}}+[108,109,90,128,106,105,85,107,125,127,89,88,126]
        check(model.recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}==expected && expected.count==77,"Pixel replay's sequence differs from observed move progression")
        check(model.recorder.moveCount==77 && model.recorder.pendingMoveCount==0,"Recovery is incomplete")
        check(model.recorder.interpretationWarnings.isEmpty,"Completed recovery still marks pending stones")
        check(RecordingClarity.explanation(recorder:model.recorder,observation:model.observation,orientation:model.orientation)==nil,"Completed game still shows a blocking message")
        check(model.observation?.signature[24] == .white,"Final live frame still loses the older white stone")
        check(model.recorder.positions[65].grid[5][13] == .black && model.recorder.positions[66].grid[5][14] == .white,"Recovered review positions are wrong")
        model.recorder.seek(65);check(model.recorder.reviewIndex==65,"Review cannot step back")
        model.recorder.returnToLatest();model.recorder.pause()
        try model.recorder.sgf().write(to:recovered,atomically:true,encoding:.utf8);try model.recorder.savePendingCheckpoint()
        try recovered.path.write(to:root.appendingPathComponent("recovered-path.txt"),atomically:true,encoding:.utf8)
        try snapshot("recovered-77")
        window.orderOut(nil)
        print("PASS: \(checks) shaded-white/clarity checks: raw failures and control, unchanged other intersections, pending-vs-placement explanations, 77-move recovery and native previews.")
    }
}
