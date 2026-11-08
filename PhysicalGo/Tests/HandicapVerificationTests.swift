import Foundation

@MainActor func runHandicapVerificationTests() throws {
    var checks=0
    func check(_ condition:Bool,_ message:String) {checks += 1;precondition(condition,message)}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("handicap-flicker-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    var now=ProcessInfo.processInfo.systemUptime
    func fresh()->GameRecorder {
        let r=GameRecorder(storage:directory);r.clock.audible=false
        r.start(size:19,handicap:2,clockSettings:.init(),startPaused:true)
        r.resume();return r
    }
    func observation(_ overrides:[Int:Occupancy]=[:])->BoardObservation {
        BoardObservation(readings:(0..<361).map {i in
            IntersectionReading(row:i/19,col:i%19,occupancy:overrides[i] ?? ([72,288].contains(i) ? .black:.empty),confidence:1,delta:0)
        },size:19)
    }
    func feed(_ r:GameRecorder,_ overrides:[Int:Occupancy]=[:],count:Int=1) {
        for _ in 0..<count {now += 0.21;r.consume(observation(overrides),now:now)}
    }
    let flicker=fresh()
    var starts=0;flicker.onGameStarted={starts += 1}
    check(flicker.awaitingFirstStart,"Verification prematurely changed Start to Resume")
    check(LocalPlayPresentation(recorder:flicker,clock:flicker.clock).automaticHold,"Verification lost Pause checking")
    for i in 0..<8 {feed(flicker,[100+i%4:.uncertain]);if flicker.state == .recording {break}}
    check(flicker.state == .recording && !flicker.awaitingFirstStart && starts==1,"Flicker prevented verified first start")
    check(flicker.clock.running && !flicker.clock.engine.blackToPlay,"White clock did not start after verification")
    flicker.pause();flicker.resume();feed(flicker,count:7)
    check(starts==1,"Ordinary resume repeated first-start announcement")
    flicker.pause()
    for (name,overrides) in [("always unknown",[100:Occupancy.uncertain]),("extra black",[100:.black]),("extra white",[100:.white]),("hidden handicap",[72:.uncertain]),("missing handicap",[72:.empty]),("wrong color",[72:.white])] {
        let r=fresh();feed(r,overrides,count:12)
        check(r.state == .verifying && !r.clock.running,"Accepted \(name)")
        feed(r,count:7);check(r.state == .recording,"Did not recover from \(name)");r.pause()
    }
    let contradicted=fresh();feed(contradicted,count:4);feed(contradicted,[100:.white]);feed(contradicted,[100:.uncertain],count:4)
    check(contradicted.state == .verifying,"Used empty evidence from before an extra stone")
    feed(contradicted,count:3);check(contradicted.state == .recording,"Fresh empty evidence did not clear contradiction");contradicted.pause()
    let repeated=fresh()
    for _ in 0..<10 {repeated.consume(observation(),now:now)}
    check(repeated.state == .verifying,"Repeated timestamp verified setup")
    now += 2;feed(repeated,count:2);check(repeated.state == .verifying,"Camera gap retained stability")
    repeated.pause();try repeated.savePendingCheckpoint()
    let restored=GameRecorder(storage:nil);restored.clock.audible=false
    try restored.restoreSavedGame(from:repeated.autosaveURL!)
    check(restored.awaitingFirstStart && !restored.clock.running,"Interrupted first start restored as Resume")
    let blocked=fresh();feed(blocked,count:4)
    var dark=observation();dark.lightingBlocked=true
    now += 0.21;blocked.consume(dark,now:now);feed(blocked,count:2)
    check(blocked.state == .verifying,"Lighting interruption retained verification evidence");blocked.pause()
    let broad=fresh();feed(broad,count:4)
    feed(broad,Dictionary(uniqueKeysWithValues:(100..<150).map {($0,Occupancy.uncertain)}));feed(broad,count:2)
    check(broad.state == .verifying,"Broad obstruction retained verification evidence");broad.pause()
    struct Frame:Decodable {let time:Double;let position:String}
    let path=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/HandicapVerification/observations.json")
    let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:path))
    let replay=fresh();let origin=now;var accepted:Double?
    for frame in frames {
        let overrides=Dictionary(uniqueKeysWithValues:frame.position.enumerated().map {i,c in (i,c == "B" ? Occupancy.black:c == "W" ? .white:c == "?" ? .uncertain:.empty)})
        now=origin+frame.time-frames[0].time
        replay.consume(observation(overrides),now:now)
        if replay.state == .recording {accepted=now-origin;break}
    }
    check(accepted != nil && accepted!<3,"Actual handicap observations still stalled: \(String(describing:accepted))")
    check(replay.moveCount==0 && replay.nextPlayer == .white,"Setup created moves or wrong turn")
    replay.pause()
    print("PASS: \(checks) handicap flicker/start checks; actual saved observations verified in \(String(format:"%.2f",accepted!)) seconds")
}
