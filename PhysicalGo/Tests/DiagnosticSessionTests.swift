import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main struct DiagnosticSessionTests {
    struct Point:Decodable {let row:Int;let col:Int;let occupancy:Occupancy}
    struct Frame:Decodable {let frameID:Int;let expectedMoveCount:Int}
    struct Metadata:Decodable {
        let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double
        let expectedMoves:[Point];let frames:[Frame]
    }
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;if !condition {fatalError(message)}}
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/DiagnosticRapidPlay")
        let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:folder.appendingPathComponent("metadata.json")))
        func image(_ name:String)->CGImage {
            CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil)!,0,nil)!
        }
        let reference=GrayFrame(image:image("empty-reference.png"))!,context=CIContext()
        var maximumUncertain=0
        // Actual darkening/brightening around a crowded group previously lost
        // real stones and manufactured whites on exposed wood. Check pixels at
        // the original calibration and nearby brightness/calibration variations.
        for fixture in meta.frames {
            let source=CIImage(cgImage:image(String(format:"%06d.png",fixture.frameID)))
            let expected=Dictionary(uniqueKeysWithValues:meta.expectedMoves.prefix(fixture.expectedMoveCount).map{($0.row*19+$0.col,$0.occupancy)})
            for brightness in [-0.005,0,0.005] {for offset in [-0.5,0,0.5] {
                let adjusted=context.createCGImage(source.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:source.extent)!
                let cal=BoardCalibration(size:19,corners:meta.calibration.corners.map{.init(x:$0.x+offset/1919,y:$0.y-offset/1079)})!
                let observation=BoardDetector.detect(frame:GrayFrame(image:adjusted)!,reference:reference,calibration:cal,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
                check(expected.allSatisfy{observation.signature[$0.key]==$0.value},"Lost real stone in frame \(fixture.frameID), brightness \(brightness), offset \(offset)")
                check(observation.signature.enumerated().allSatisfy{$0.element.stone==nil || expected[$0.offset]==$0.element},"Invented stone in frame \(fixture.frameID)")
                let uncertain=observation.signature.filter{$0 == .uncertain}.count
                maximumUncertain=max(maximumUncertain,uncertain)
                check(uncertain<=18,"Clear-frame uncertainty exceeded the recorder's 19×19 acceptance limit")
            }}
        }
        print("Actual pixel regressions: all stones retained, no invented stones; maximum uncertain empty points across perturbations:",maximumUncertain)
        let rows=try String(contentsOf:folder.appendingPathComponent("observations.jsonl"),encoding:.utf8).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }
        let first=rows.first{$0["uptime"] != nil}!["uptime"] as! Double
        func observation(_ states:[Occupancy])->BoardObservation {
            BoardObservation(readings:states.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19)
        }
        func replay(saved:Bool=false,hideChronology:Bool=false,swapBlack:Bool=false)->GameRecorder {
            let recorder=GameRecorder(storage:nil),empty=observation(Array(repeating:.empty,count:361))
            for i in 0..<6 {recorder.consume(empty,now:first-2+Double(i)*0.21)}
            recorder.start(size:19,now:first-0.9)
            for row in rows {
                if let event=row["event"] as? String {
                    if event=="paused" {recorder.pause()}
                    else if event=="resumed" {recorder.resume()}
                    else {recorder.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"))}
                    continue
                }
                var states=(row[saved ? "saved" : "corrected"] as! String).map{$0 == "B" ? Occupancy.black : $0 == "W" ? .white : $0 == "?" ? .uncertain : .empty}
                if hideChronology && (row["frameID"] as! Int) < 380 {for i in [53,70,111,66] {states[i] = .uncertain}}
                if swapBlack {states.swapAt(53,111)}
                recorder.consume(observation(states),now:row["uptime"] as! Double)
            }
            return recorder
        }
        func points(_ r:GameRecorder)->[Int] {r.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}}
        let expected=meta.expectedMoves.map{$0.row*19+$0.col}
        let baseline=replay(saved:true)
        check(points(baseline)==Array(expected.prefix(11)),"Saved detections changed the safely confirmed eleven-move prefix")
        let corrected=replay()
        check(points(corrected)==expected,"Corrected diagnostic replay did not recover exactly the 18 observed moves: \(points(corrected))")
        check(corrected.pendingMoveCount==0 && corrected.localEvidenceRunCount==0,"Caught-up session retained temporary evidence")
        check(corrected.positions.count==19,"Review lost intermediate positions")
        for index in 0...18 {
            corrected.seek(index)
            check(corrected.reviewedBoard==corrected.positions[index],"Review failed at move \(index)")
        }
        let game=SGFGame.from(tree:try SGFParser.parse(text:corrected.sgf()))
        let player=SGFPlayer();player.load(game:game);player.seek(to:18)
        check(player.board==corrected.positions.last!,"Recovered SGF differs from the review board")
        let masked=replay(hideChronology:true)
        check(masked.moveCount<18 && points(masked)==Array(expected.prefix(masked.moveCount)),"Missing chronology invented an order")
        let swapped=replay(swapBlack:true),permuted=expected.map{$0==53 ? 111 : $0==111 ? 53 : $0}
        check(points(swapped)==permuted,"Recovery followed fixed coordinates instead of the observed order")
        print("PASS: \(checks) diagnostic-session checks: real pixel regressions, saved-detection stall, complete 18-move recovery, missing/swapped chronology, review and SGF.")
    }
}
