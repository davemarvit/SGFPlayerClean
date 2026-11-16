import Foundation
import ImageIO

@main struct GoClubVisibilityTests {
    struct Camera:Decodable {let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double}
    struct Event:Decodable {let event:String;let time:Double;let position:String?;let lightingBlocked:Bool?}
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ ok:Bool,_ text:String) {checks+=1;precondition(ok,text)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/GoClubVisibility")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("go-club-visibility-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        func make(_ name:String,review:Bool=false)throws->GameRecorder {
            let folder=root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            for suffix in review ? ["sgf","clock.json","pending.json","reviews.json"]:["sgf"] {
                try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+suffix),to:folder.appendingPathComponent("game."+suffix))
            }
            let r=GameRecorder(storage:folder);r.clock.audible=false
            try r.restoreSavedGame(from:folder.appendingPathComponent("game.sgf"))
            return r
        }
        func values(_ signature:String)->[Occupancy] {signature.map{$0 == "B" ? .black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty}}
        func feed(_ r:GameRecorder,_ readings:[Occupancy],at t:Double) {
            r.consume(.init(readings:readings.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:t,handObstructed:false),now:t)
        }
        let r=try make("episode");r.attachClock(.init(kind:.absolute,mainSeconds:600));r.resume()
        let base=DeferredMoveHistory.states(r.positions.last!)
        var now=ProcessInfo.processInfo.systemUptime+3
        for _ in 0..<6 {now+=0.21;feed(r,base,at:now)}
        check(r.clock.running && r.moveCount==10,"Replay did not start from the saved ten-move board")
        var alerts=[Double](),clockAtAlert=[LocalClockEngine]()
        r.onDiagnosticEvent={row in
            if row["event"] as? String == "recording warning: prolonged blocked view",let t=row["uptime"] as? Double {
                alerts.append(t);clockAtAlert.append(r.clock.engine)
            }
        }
        let events=try JSONDecoder().decode([Event].self,from:Data(contentsOf:fixture.appendingPathComponent("episode.json")))
        let origin=now+0.21-events[0].time
        var hand=false,last=now,firstHand:Double?
        for event in events {
            let t=origin+event.time
            // The journal records the start/end of each hand interval, not
            // every camera callback. Fill continuity callbacks only; never
            // fabricate a board reading or placement inside that interval.
            if hand {while t-last>0.21 {last+=0.21;r.noteHandObstruction(now:last,capturedAt:last)}}
            if event.event=="hand obstruction began" {
                if firstHand==nil {firstHand=t}
                hand=true;r.noteHandObstruction(now:t,capturedAt:t)
            } else if event.event=="hand obstruction cleared" {hand=false;r.noteHandClear()}
            else if let signature=event.position {feed(r,values(signature),at:t)}
            last=t
        }
        check(alerts.count==1,"Recorded alternating hand/corrupt frames never warned early, or repeated the same warning")
        check(alerts[0]-firstHand!>=5 && alerts[0]-firstHand!<6,"Warning arrived after the recorded visibility gap had already lost several moves")
        check(clockAtAlert[0].running && clockAtAlert[0].blackToPlay,"Advisory visibility warning stopped or switched a clock")
        check(r.moveCount==10 && r.hasDeferredMoves,"Unknown move order was guessed into SGF")
        check(r.clock.requiresReview && !r.clock.running,"Unobserved clock presses bypassed timing review")
        check(!r.spokenRecoveryInstruction().contains("has not had a clear board view"),"Verified clear frames left stale visibility guidance active")
        r.pause()

        // Ordinary hands, redraws, manual pause and a fresh new move keep their
        // existing behavior. All these checks use the actual recorder API.
        let normal=try make("normal");normal.attachClock(.init(kind:.fischer,mainSeconds:600,incrementSeconds:5,maximumSeconds:900));normal.resume()
        var normalAlerts=0
        normal.onDiagnosticEvent={if $0["event"] as? String == "recording warning: prolonged blocked view" {normalAlerts+=1}}
        now=max(last+3,ProcessInfo.processInfo.systemUptime+3)
        func clear(_ count:Int=6) {for _ in 0..<count {now+=0.21;feed(normal,base,at:now)}}
        clear()
        for _ in 0..<3 {
            for _ in 0..<12 {now+=0.21;normal.noteHandObstruction(now:now,capturedAt:now)}
            normal.noteHandClear();clear()
        }
        check(normalAlerts==0 && normal.clock.running,"Routine hands triggered an alert or changed clock continuity")
        now+=0.21;normal.noteHandObstruction(now:now,capturedAt:now)
        for _ in 0..<40 {normal.noteHandObstruction(now:now,capturedAt:now)}
        check(normalAlerts==0,"Duplicate redraws accumulated visibility-loss time")
        normal.noteHandClear();clear()
        normal.pause()
        for _ in 0..<40 {now+=0.21;normal.noteHandObstruction(now:now,capturedAt:now)}
        check(normalAlerts==0 && !normal.clock.running,"Manual pause emitted play guidance or resumed clocks")
        normal.noteHandClear();normal.resume();clear()
        var moved=base;moved[180] = .black
        for _ in 0..<12 {now+=0.21;feed(normal,moved,at:now)}
        check(normal.moveCount==11 && !normal.clock.engine.blackToPlay && !normal.clock.requiresReview,"Visibility feedback broke ordinary move acceptance")
        normal.pause()

        // Strong hand-supported timing can certify a turn before five clear
        // frames. Repeated fast but successfully recognized play is progress.
        let rapid=try make("rapid");rapid.attachClock(.init(kind:.absolute,mainSeconds:600));rapid.resume()
        var rapidAlerts=0,rapidBoard=base
        rapid.onDiagnosticEvent={if $0["event"] as? String == "recording warning: prolonged blocked view" {rapidAlerts+=1}}
        now+=3
        for _ in 0..<6 {now+=0.21;feed(rapid,base,at:now)}
        for (turn,point) in [180,182].enumerated() {
            for _ in 0..<12 {now+=0.21;rapid.noteHandObstruction(now:now,capturedAt:now)}
            rapid.noteHandClear()
            rapidBoard[point] = turn%2==0 ? .black:.white
            let estimate=ClockPressEstimate(time:now,method:.handMotion,observedLower:now-0.02,observedUpper:now+0.02,estimatedError:0.02,samples:3)
            for _ in 0..<2 {
                now+=0.21
                rapid.consume(.init(readings:rapidBoard.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:now,handObstructed:false,clockPressEstimate:estimate),now:now)
            }
            check(rapid.clock.lastTimedMove==11+turn && rapid.clock.running,"Rapid turn \(turn): timed \(rapid.clock.lastTimedMove), saved \(rapid.moveCount), running \(rapid.clock.running), \(rapid.status), \(rapid.clock.notice)")
        }
        check(rapidAlerts==0,"Successfully recognized rapid play accumulated a false visibility warning")
        rapid.pause()

        // Reprocess actual pixels with the original reference and calibration.
        // This is independent of the recorded classifications used above.
        let saved=try make("review",review:true)
        let target=saved.reviewHistory.sections[0].after
        let camera=try JSONDecoder().decode(Camera.self,from:Data(contentsOf:fixture.appendingPathComponent("camera.json")))
        func frame(_ name:String)throws->GrayFrame {
            guard let source=CGImageSourceCreateWithURL(fixture.appendingPathComponent(name) as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(source,0,nil),let frame=GrayFrame(image:image) else {throw NSError(domain:"fixture",code:1)}
            return frame
        }
        let reference=try frame("reference.png")
        for name in ["000001.png","000108.png","000229.png"] {
            let detected=BoardDetector.detect(frame:try frame(name),reference:reference,calibration:camera.calibration,threshold:camera.threshold,referenceCalibration:camera.referenceCalibration)
            check(detected?.signature==target,"Actual final-board photo did not reproduce all fifteen stones")
        }
        check(target.filter{$0.stone != nil}.count==15 && saved.moveCount==10,"Fixture lost the distinction between physical position and saved chronology")
        check(saved.reviewHistory.sections[0].suggestedOrders?.count==12,"Recorded uncertainty was collapsed to a guessed order")
        let sgf=saved.sgf(),clock=saved.clock.engine
        let spoken=saved.spokenRecoveryInstruction()
        check(spoken.contains("5 marked stones are detected") && spoken.contains("move order is uncertain"),"Orange review still implies the visible stones were not detected")
        let presentation=LocalPlayStatus(recorder:saved)
        check(presentation.detail.contains("5 marked stones are detected") && presentation.nextStep.contains("Review 1"),"Clock-review status hides the actual move-order problem")
        check(saved.sgf()==sgf && saved.clock.engine==clock && saved.clock.requiresReview,"Explaining review changed game history or cleared clock protection")
        print("PASS: \(checks) Go-club visibility, chronology, clock isolation and real-photo checks; first alert after \(alerts[0]-firstHand!) seconds")
    }
}
