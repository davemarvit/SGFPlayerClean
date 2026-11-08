import Foundation
import CoreGraphics
import ImageIO

@main struct BoardCorrectionTests {
    struct Fixture: Decodable {
        struct Frame:Decodable {
            let frame:Int,image:String,reference:String,calibration:BoardCalibration,reference_calibration:BoardCalibration,threshold:Double
        }
        let cases:[Frame],serverBefore:[String],afterCapture:[String]
    }
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        func check(_ yes:Bool,_ message:String) {if !yes {fatalError(message)}}
        let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CaptureCorrections")
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:root.appendingPathComponent("fixture.json")))
        func image(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let reference=image("reference.png")
        var detected=[BoardObservation]()
        for f in fixture.cases {
            let result=BoardDetector.detect(frame:GrayFrame(image:image(f.image))!,reference:GrayFrame(image:reference)!,calibration:f.calibration,threshold:f.threshold,referenceCalibration:f.reference_calibration)!
            for r in result.readings {
                let point=PhysicalMoveInference.displayedPoint(row:r.row,col:r.col,size:19,quarterTurns:3)
                check(r.occupancy == .uncertain || r.occupancy.rawValue == fixture.afterCapture[point],"Wrong classification in capture frame \(f.frame), point \(point)")
            }
            detected.append(result)
        }
        check(detected.filter{!$0.signature.contains(.uncertain)}.count>=2,"Capture cannot settle")
        let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("BoardCorrectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:tmp,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:tmp)}
        let move=tmp.appendingPathComponent("move.json")
        func publish(_ game:Int=1,turn:Bool=true,stale:Bool=false) throws {
            let state:[String:Any]=["token":"test-only","game":game,"version":1,"size":19,"cells":fixture.serverBefore,"ready":true,"myTurn":turn,"color":"black","time":Date().timeIntervalSince1970-(stale ? 10:0)]
            try JSONSerialization.data(withJSONObject:state).write(to:tmp.appendingPathComponent("state.json"))
        }
        func raw(_ board:[String])->BoardObservation {
            BoardObservation(readings:(0..<361).map {i in
                let displayed=(18-i%19)*19+i/19
                return IntersectionReading(row:i/19,col:i%19,occupancy:Occupancy(rawValue:board[displayed])!,confidence:1,delta:0)
            },size:19)
        }
        let corrections=ManualBoardCorrections()
        let bridge=PhysicalOnlineBoard(directory:tmp,announceOpponent:{},announceCorrection:{});bridge.enabled=true
        try publish();bridge.consume(raw(fixture.serverBefore),now:1,quarterTurns:3,corrections:corrections)
        for i in 0..<8 {try publish();bridge.consume(detected[i%detected.count],now:1.1+Double(i)*0.3,quarterTurns:3,corrections:corrections)}
        let request=try JSONSerialization.jsonObject(with:Data(contentsOf:move)) as! [String:Any]
        check(request["x"] as? Int == 4 && request["y"] as? Int == 16,"Wrong capture coordinate")
        try FileManager.default.removeItem(at:move)
        for i in 0..<6 {try publish();bridge.consume(detected[0],now:4+Double(i)*0.3,quarterTurns:3,corrections:corrections)}
        check(!FileManager.default.fileExists(atPath:move.path),"Duplicate capture request")
        try publish(2);bridge.consume(raw(fixture.serverBefore),now:6,quarterTurns:3,corrections:corrections)
        let empty=5*19+2,black=5*19+4
        let after=raw(fixture.afterCapture)
        let uncertain=BoardObservation(readings:after.readings.map {r in
            [empty,black].contains(r.row*19+r.col) ? IntersectionReading(row:r.row,col:r.col,occupancy:.uncertain,confidence:0,delta:r.delta) : r
        },size:19)
        corrections.begin(size:19);bridge.pauseForCorrection();corrections.set(.empty,at:empty);corrections.set(.black,at:black)
        for i in 0..<8 {try publish(2);bridge.consume(uncertain,now:6.1+Double(i)*0.3,quarterTurns:3,corrections:corrections)}
        check(!FileManager.default.fileExists(atPath:move.path),"Editor sent a move before Done")
        check(corrections.apply(to:uncertain).signature[empty] == .uncertain,"Draft changed live readings")
        let f=fixture.cases[0]
        let snapshot=BoardCorrectionSnapshot(id:UUID(),capturedAt:Date(),image:image(f.image),reference:reference,calibration:f.calibration,referenceCalibration:f.reference_calibration,observation:uncertain,threshold:f.threshold,quarterTurns:3,source:"test camera")
        let saved=try CorrectionArchive.save(snapshot,edits:corrections.edits,root:tmp.appendingPathComponent("archive"))
        let metadata=try JSONSerialization.jsonObject(with:Data(contentsOf:saved.appendingPathComponent("corrections.json"))) as! [String:Any]
        check((metadata["labels"] as! [Any]).count==2,"Unedited points became training labels")
        check((metadata["rawReadings"] as! [[String:Any]])[empty]["occupancy"] as? String == "uncertain","Raw guess overwritten")
        check(FileManager.default.fileExists(atPath:saved.appendingPathComponent("reference.png").path),"Reference missing")
        let archived=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(saved.appendingPathComponent("camera.png") as CFURL,nil)!,0,nil)!
        check(GrayFrame(image:archived)!.pixels == GrayFrame(image:snapshot.image)!.pixels,"Archive changed image pixels")
        corrections.commit();bridge.pauseForCorrection()
        check(uncertain.signature[empty] == .uncertain,"Raw observation mutated")
        check(corrections.apply(to:uncertain).manualPoints == Set([empty,black]),"Manual provenance missing")
        for i in 0..<8 {try publish(2);bridge.consume(uncertain,now:9+Double(i)*0.3,quarterTurns:3,corrections:corrections)}
        check(FileManager.default.fileExists(atPath:move.path),"Corrected capture did not send")
        try FileManager.default.removeItem(at:move)
        try publish(2,turn:false);bridge.consume(uncertain,now:11.5,quarterTurns:3,corrections:corrections)
        check(corrections.values[empty] == .empty && corrections.values[black] == .black,"Ordinary turn update erased user labels")
        var contradictory=fixture.afterCapture;contradictory[309]="white"
        check(corrections.apply(to:raw(contradictory)).signature[empty] == .empty,"Camera replaced authoritative label")
        corrections.begin(size:19);corrections.set(.white,at:empty);corrections.cancel()
        check(corrections.values[empty] == .empty,"Cancel applied edits")
        corrections.begin(size:19);corrections.set(.automatic,at:empty)
        let autoSnapshot=BoardCorrectionSnapshot(id:UUID(),capturedAt:Date(),image:snapshot.image,reference:nil,calibration:f.calibration,referenceCalibration:nil,observation:uncertain,threshold:f.threshold,quarterTurns:3,source:"test")
        let autoSaved=try CorrectionArchive.save(autoSnapshot,edits:corrections.edits,root:tmp.appendingPathComponent("archive"))
        let autoMetadata=try JSONSerialization.jsonObject(with:Data(contentsOf:autoSaved.appendingPathComponent("corrections.json"))) as! [String:Any]
        check((autoMetadata["labels"] as! [Any]).isEmpty,"Automatic action became training truth")
        corrections.commit();check(corrections.values[empty] == nil && corrections.values[black] == .black,"Release failed")
        var blocked=uncertain;blocked.lightingBlocked=true
        check(corrections.apply(to:blocked).lightingBlocked,"Lighting guard bypassed")
        try publish(3);bridge.consume(uncertain,now:13,quarterTurns:3,corrections:corrections)
        check(corrections.values.isEmpty,"Labels leaked to new game")
        corrections.clear(reason:"Local reset")
        try publish(3);bridge.consume(uncertain,now:13.1,quarterTurns:3,corrections:corrections)
        check(corrections.context != nil,"Unchanged server position failed to rebind after local reset")
        corrections.begin(size:19);corrections.set(.black,at:black);corrections.commit()
        try publish(3);bridge.consume(uncertain,now:13.3,quarterTurns:0,corrections:corrections)
        check(corrections.values.isEmpty,"Labels leaked across orientation change")
        corrections.begin(size:19);corrections.set(.empty,at:empty);corrections.commit()
        for i in 0..<6 {try publish(3,stale:true);bridge.consume(uncertain,now:14+Double(i)*0.3,corrections:corrections)}
        check(!FileManager.default.fileExists(atPath:move.path),"Stale state sent a move")
        let file=tmp.appendingPathComponent("not-a-directory");try Data().write(to:file)
        do {_=try CorrectionArchive.save(autoSnapshot,edits:[:],root:file);fatalError("Archive failure swallowed")} catch {}
        print("PASS: photographic capture; manual pause/commit/cancel/release; contradiction; game/orientation isolation; stale/lighting guards; exact-label lossless archive; write failure")
    }
}
