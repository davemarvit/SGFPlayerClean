import Foundation

enum ClockCatchUpIncidentTests {
    struct Frame:Decodable {let time:Double;let position:[Occupancy];let handObstructed:Bool?;let estimate:ClockPressEstimate?}
    struct Incident:Decodable {let turnStartedAt:Double;let recognizedAt:Double;let black67Press:Double;let targets:[[Occupancy]];let changed:[[Int]];let frames:[Frame]}
    @MainActor static func run()throws->Int {
        let incident=try JSONDecoder().decode(Incident.self,from:Data(contentsOf:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ClockCatchUpLoss/observations.json")))
        var history=ClearBoardTiming(),checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        for f in incident.frames {
            if f.handObstructed==true {history.noteHand(at:f.time)}
            else {history.observe(.init(readings:f.position.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:f.time,handObstructed:f.handObstructed,clockPressEstimate:f.estimate),now:f.time+0.3)}
        }
        let first=history.estimate(target:incident.targets[0],changed:Set(incident.changed[0]),after:incident.turnStartedAt)
        let second=history.estimate(target:incident.targets[1],changed:Set(incident.changed[1]),after:(first?.time ?? incident.turnStartedAt)+1e-6)
        check(first != nil && abs(first!.time-849474.4617102919)<1e-6,"Recorded camera continuity lost Black65's verified press")
        check(second != nil && abs(second!.time-849477.5611202295)<1e-6,"Recorded camera continuity lost White66's verified press")
        let clock=LocalGameClock();clock.audible=false
        clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:2),blackToPlay:true,baseMove:64);clock.ready(at:incident.turnStartedAt)
        clock.tick(at:incident.recognizedAt)
        clock.recordCatchUp(first:65,last:66,blackToPlay:true,at:incident.recognizedAt,estimates:[first,second])
        check(clock.moves.map(\.number)==[65,66] && clock.pressEvidence.allSatisfy(\.applied),"Recovered moves lost individual clock presses")
        clock.tick(at:incident.black67Press)
        clock.recordMove(number:67,black:true,at:incident.black67Press,observedAt:incident.black67Press,estimate:.init(time:incident.black67Press,method:.clearFrame))
        check(clock.engine.black.periods==2 && clock.engine.white.periods==2 && !clock.needsCorrection,"Recorded incident incorrectly deducted a byoyomi period")
        clock.pause(at:incident.black67Press)
        // An unavailable hand detector establishes continuity, never clearance.
        var unknown=ClearBoardTiming()
        let frame=incident.frames.first!
        unknown.observe(.init(readings:frame.position.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:1,handObstructed:nil),now:1)
        check(unknown.estimate(target:incident.targets[0],changed:[282],after:0)==nil,"Unknown hand state fabricated a clock press")
        var conflict=history,changed=incident.targets[1];changed[282] = .empty
        conflict.observe(.init(readings:changed.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:incident.frames.last!.time+0.2,handObstructed:false),now:incident.frames.last!.time+0.2)
        check(conflict.estimate(target:incident.targets[0],changed:[282],after:0)==nil,"A definite stone withdrawal reused an earlier press")
        history.noteHand(at:incident.frames.last!.time+2)
        check(history.estimate(target:incident.targets[0],changed:[282],after:0)==nil,"A real camera gap retained stale evidence")
        print("PASS: \(checks) recorded Black65–67 clock regression checks")
        return checks
    }
}
