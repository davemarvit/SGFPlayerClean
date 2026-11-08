import Foundation
import CoreGraphics
import ImageIO

@main struct CrowdedAdjustmentTests {
    struct Frame:Decodable {
        let name:String;let calibration:BoardCalibration;let referenceCalibration:BoardCalibration
        let threshold:Double;let expectedClear:Bool?;let signature:String;let time:Double?
    }
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CrowdedAdjustment")
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:folder.appendingPathComponent("metadata.json")))
        func load(_ url:URL)->GrayFrame {GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!)!}
        let reference=load(folder.appendingPathComponent("reference.png"))
        var checks=0,views=[(Double,BoardObservation)]()
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        for frame in frames {
            let started=Date()
            let view=BoardDetector.detect(frame:load(folder.appendingPathComponent(frame.name+".png")),reference:reference,calibration:frame.calibration,threshold:frame.threshold,referenceCalibration:frame.referenceCalibration)!
            let position=view.signature.map{$0 == .black ? "B" : $0 == .white ? "W" : $0 == .uncertain ? "?" : "."}.joined()
            check(position==frame.signature,"Placement refinement changed occupancy in \(frame.name)")
            if let clear=frame.expectedClear {
                if clear {
                    check(view.placementOffsets[48].map{$0<=0.24+1e-9}==true,"Adjusted stone still lacks a reliable center in \(frame.name)")
                    check(view.placementFits.contains{$0.row*19+$0.col==48 && $0.quality>=0.90},"Crowded fit bypassed its evidence threshold")
                } else {check(view.placementOffsets[48].map{$0>0.24} ?? true,"Displaced stone was incorrectly cleared")}
            }
            if let time=frame.time {
                if let offset=view.placementOffsets[48] {check(offset<=0.24+1e-9,"Reliable crowded fit pointed away from the adjusted center")}
                views.append((time,view))
            }
            print("\(frame.name): offset=\(String(describing:view.placementOffsets[48])) refinement=\(view.placementFits.first{$0.row*19+$0.col==48}?.quality ?? 0) seconds=\(Date().timeIntervalSince(started))")
        }
        let output=URL(fileURLWithPath:"PhysicalGo/.build/CrowdedAdjustment/Replay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let seed=output.appendingPathComponent("Recovered game.sgf")
        try FileManager.default.copyItem(at:folder.appendingPathComponent("initial.sgf"),to:seed)
        try FileManager.default.copyItem(at:folder.appendingPathComponent("initial.pending.json"),to:seed.deletingPathExtension().appendingPathExtension("pending.json"))
        let recorder=GameRecorder(storage:output);try recorder.restoreSavedGame(from:seed)
        let expected=recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}+recorder.pendingConfidence.compactMap(\.point)
        check(recorder.moveCount==30 && recorder.pendingMoveCount==16 && expected.count==46,"Wrong captured starting history")
        check(recorder.interpretationWarnings==[48],"Wrong captured placement warning")
        recorder.resume()
        let start=ProcessInfo.processInfo.systemUptime
        for (index,pair) in views.enumerated() {
            recorder.consume(pair.1,now:start+pair.0-views[0].0)
            if index<7 {check(recorder.moveCount==30,"Adjustment skipped fresh confirmation")}
        }
        check(recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}==expected,"Real adjusted images did not complete the exact 46-move sequence: \(recorder.status)")
        check(recorder.pendingMoveCount==0 && recorder.interpretationWarnings.isEmpty,"Completed sequence retained a red ring")
        recorder.pause()
        let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:seed)
        check(restored.moveCount==46 && restored.pendingMoveCount==0,"Recovered SGF/checkpoint failed round trip")
        try seed.path.write(to:URL(fileURLWithPath:"PhysicalGo/.build/CrowdedAdjustment/recovered-path.txt"),atomically:true,encoding:.utf8)
        print("PASS: \(checks) crowded-placement checks: unchanged occupancy, displaced control, independently verified adjusted center, 24 real consecutive frames, fresh confirmation, and exact 46-move SGF without simulated adjustments.")
    }
}
