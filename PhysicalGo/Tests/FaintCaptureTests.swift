import Foundation
import ImageIO

@main struct FaintCaptureTests {
    struct Anchor:Decodable {let calibration:BoardCalibration;let fittedGrid:BoardCalibration;let width:Int;let height:Int}
    struct Meta:Decodable {let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double;let anchor:Anchor}
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/FaintCaptureQ3")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:fixture.appendingPathComponent("metadata.json")))
        func load(_ file:String)->GrayFrame {
            GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(fixture.appendingPathComponent(file) as CFURL,nil)!,0,nil)!)!
        }
        let reference=load("../FaintBoardO2/reference.png")
        let anchor=AutoGridDetector.TrackingAnchor(calibration:meta.anchor.calibration,fittedGrid:meta.anchor.fittedGrid,
            frame:GrayFrame(width:meta.anchor.width,height:meta.anchor.height,pixels:Array(try Data(contentsOf:fixture.appendingPathComponent("anchor.gray")))))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("faint-capture-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("game.sgf")
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("before.sgf"),to:file)
        let recorder=GameRecorder(storage:root);recorder.clock.audible=false
        try recorder.restoreSavedGame(from:file)
        recorder.attachClock(.init(kind:.absolute,mainSeconds:300,automaticCaptureMinimum:2))
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;if !value {print("FAIL: \(message)");fatalError(message)}}
        var now=ProcessInfo.processInfo.systemUptime
        let base=DeferredMoveHistory.states(recorder.positions.last!)
        var expected=base;expected[287] = .white
        recorder.resume()
        for _ in 0..<5 {
            now+=0.21
            recorder.consume(.init(readings:base.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:now),now:now)
        }
        check(recorder.clock.running,"Fixture failed to resume White's turn")
        let first=now
        for name in ["000002.png","000003.png","000005.png","000064.png"] {
            let frame=load(name)
            check(AutoGridDetector.track(frame:frame,from:meta.calibration,anchor:anchor,expected:base) != nil,"Faint outer rail rejected in \(name)")
            var observed=BoardDetector.detect(frame:frame,reference:reference,calibration:meta.calibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            for (index,state) in expected.enumerated() {
                check(state == .empty ? observed.readings[index].occupancy.stone==nil:observed.readings[index].occupancy==state,"Wrong point \(index) in \(name)")
            }
            now+=0.21;observed.capturedAt=now
            // Recorded hand-pose and outline checks are clear in these frames.
            observed.handObstructed=false
            recorder.consume(observed,now:now)
        }
        check(recorder.clock.automaticCapturePaused && !recorder.clock.running,"Recorded Q3 photos failed to stop clocks for capture")
        check(recorder.moveCount==13 && recorder.automaticCaptureRemainingPoints==[267,268],"Capture saved early or selected wrong prisoners")
        check(now-first<1,"Photo capture setup exceeded one second")
        recorder.pause();try recorder.flushStorage()
        for name in ["../FaintBoardO2/000010.png","../FaintBoardO2/reference.png"] {
            let grid=name.hasSuffix("reference.png") ? meta.referenceCalibration:meta.calibration
            let absent=BoardDetector.detect(frame:load(name),reference:reference,calibration:grid,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            check(absent.readings[287].occupancy == .empty,"Invented Q3 before placement")
        }
        print("PASS: \(checks) faint Q3 photo, alignment, absence and capture-hold checks")
    }
}
