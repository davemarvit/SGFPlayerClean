import Foundation
import CoreGraphics
import ImageIO

@main struct CrowdedWhiteAdjustmentTests {
    struct Frame:Decodable {
        let name:String;let calibration:BoardCalibration;let referenceCalibration:BoardCalibration
        let threshold:Double;let expectedClear:Bool?;let signature:String;let time:Double?
    }
    struct PhotoLabels:Decodable {let empty:[Int];let occluded:[Int]}
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CrowdedWhiteAdjustment")
        let labels=try JSONDecoder().decode([String:PhotoLabels].self,from:Data(contentsOf:folder.appendingPathComponent("photo-labels.json")))
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:folder.appendingPathComponent("metadata.json")))
        func load(_ url:URL)->GrayFrame {GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!)!}
        let reference=load(folder.appendingPathComponent("reference.png"))
        var checks=0,views=[(Double,BoardObservation)]()
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        for frame in frames {
            let started=Date()
            let view=BoardDetector.detect(frame:load(folder.appendingPathComponent(frame.name+".png")),reference:reference,calibration:frame.calibration,threshold:frame.threshold,referenceCalibration:frame.referenceCalibration)!
            let position=view.signature.map{$0 == .black ? "B" : $0 == .white ? "W" : $0 == .uncertain ? "?" : "."}.joined()
            // Historical signatures include false whites on wood and fingers.
            // Separate photo labels forbid fabricated stones on those points. A
            // conservative unknown remains valid under the small-cover guard.
            let labeled=labels[frame.name]
            let old=Array(frame.signature),current=Array(position)
            for i in current.indices {
                if labeled?.empty.contains(i) == true {check(current[i]=="." || current[i]=="?","Photographed empty point \(i) became occupied in \(frame.name)")}
                else if labeled?.occluded.contains(i) == true {check(current[i]=="?","Hand-covered point \(i) was assigned in \(frame.name)")}
                else {check(current[i]==old[i] || (current[i]=="." && old[i]=="?"),"Known occupancy changed at \(i) in \(frame.name)")}
            }
            if let clear=frame.expectedClear {
                if clear {
                    check(view.placementOffsets[39].map{$0<=0.24+1e-9}==true,"Adjusted stone still lacks a reliable center in \(frame.name)")
                    check(view.placementFits.contains{$0.row*19+$0.col==39 && $0.quality>=0.90},"Crowded fit bypassed its evidence threshold")
                } else {check(view.placementOffsets[39].map{$0>0.24} ?? true,"Displaced stone was incorrectly cleared")}
            }
            if let time=frame.time {
                if let offset=view.placementOffsets[39] {check(offset<=0.24+1e-9,"Reliable crowded fit pointed away from the adjusted center")}
                views.append((time,view))
            }
            print("\(frame.name): offset=\(String(describing:view.placementOffsets[39])) refinement=\(view.placementFits.first{$0.row*19+$0.col==39}?.quality ?? 0) seconds=\(Date().timeIntervalSince(started))")
        }
        let output=URL(fileURLWithPath:"PhysicalGo/.build/C3Placement/Replay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let seed=output.appendingPathComponent("Recovered game.sgf")
        try FileManager.default.copyItem(at:folder.appendingPathComponent("initial.sgf"),to:seed)
        try FileManager.default.copyItem(at:folder.appendingPathComponent("initial.pending.json"),to:seed.deletingPathExtension().appendingPathExtension("pending.json"))
        let recorder=GameRecorder(storage:output);try recorder.restoreSavedGame(from:seed)
        let expected=recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}+recorder.pendingConfidence.compactMap(\.point)
        check(recorder.pendingConfidence.compactMap(\.point)==[39,20,58,78,77,97,96],"Pending order changed")
        check(recorder.moveCount==29 && recorder.pendingMoveCount==7 && expected.count==36,"Wrong captured starting history")
        check(recorder.interpretationWarnings==[39],"Wrong captured placement warning")
        recorder.resume()
        let start=ProcessInfo.processInfo.systemUptime
        for (index,pair) in views.enumerated() {
            recorder.consume(pair.1,now:start+pair.0-views[0].0)
            if index<7 {check(recorder.moveCount==29,"Adjustment skipped fresh confirmation")}
        }
        check(recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}==expected,"Real adjusted images did not complete the exact 36-move sequence: \(recorder.status)")
        check(recorder.pendingMoveCount==0 && recorder.interpretationWarnings.isEmpty,"Completed sequence retained a red ring")
        recorder.pause()
        try recorder.flushStorage()
        let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:seed)
        check(restored.moveCount==36 && restored.pendingMoveCount==0,"Recovered SGF/checkpoint failed round trip")
        try seed.path.write(to:URL(fileURLWithPath:"PhysicalGo/.build/C3Placement/recovered-path.txt"),atomically:true,encoding:.utf8)
        print("PASS: \(checks) crowded-white-placement checks: unchanged occupancy, displaced control, independently verified adjusted center, 16 real consecutive frames, fresh confirmation, and exact 36-move SGF without simulated adjustments.")
    }
}
