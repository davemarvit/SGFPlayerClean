import Foundation

@MainActor private final class CheckingScenario {
    final class Clock {var now=100.0}
    let clock=Clock()
    let ai:PhysicalAI
    let directory:URL
    init(root:URL,moves:[Int?]=[],humanBlack:Bool=true,verified:Bool=false)throws {
        directory=root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var settings=PhysicalAISettings();settings.size=19;settings.humanBlack=humanBlack
        var snapshot=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:moves.map {.init(point:$0)})
        if verified {
            let player=SGFPlayer();player.load(game:PhysicalAI.game(snapshot));player.seek(to:moves.count)
            snapshot.verifiedPosition = .init(cells:player.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"},cameraContext:"checking-grid")
        }
        try JSONEncoder().encode(snapshot).write(to:directory.appendingPathComponent("current.json"))
        let c=clock,laser=PhysicalLaserGuidance(directory:directory.appendingPathComponent("bridge"),automatic:false,uptime:{c.now})
        ai=PhysicalAI(directory:directory,generate:{_,_ in "pass"},laser:laser,uptime:{c.now})
        laser.observeCamera(hand:false,valid:true,capturedAt:c.now,now:c.now,context:"checking-grid")
        ai.resume()
    }
    func observation(_ override:[Int:Occupancy]=[:],weak:Set<Int>=[],hand:Bool=false)->BoardObservation {
        var o=BoardObservation(readings:ai.cells.enumerated().map {i,value in
            .init(row:i/19,col:i%19,occupancy:override[i] ?? Occupancy(rawValue:value)!,confidence:weak.contains(i) ? 0.75:1,delta:0)
        },size:19)
        o.handObstructed=hand;return o
    }
    func feed(_ input:BoardObservation,count:Int=1) {
        for _ in 0..<count {clock.now+=0.2;var o=input;o.capturedAt=clock.now;ai.consume(o,now:clock.now)}
    }
}

@main struct PhysicalAICheckingControllerTests {
    @MainActor static func main()throws {
        var checks=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);checks+=1}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("checking-controller-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let startup=try CheckingScenario(root:root)
        let id=startup.ai.snapshot!.id
        let uncertain=startup.observation([121:.uncertain],weak:[87,121])
        startup.feed(uncertain,count:10)
        check(startup.ai.phase == .checking && startup.ai.checkingHelp==nil,"Transient checking bypassed grace or changed phase")
        startup.feed(uncertain,count:10)
        check(startup.ai.checkingHelp?.reason == .requiredIntersections && startup.ai.checkingHelp?.points==[87,121],"Persistent startup ambiguity stayed silent or lost required points")
        check(startup.ai.snapshot!.moves.isEmpty && startup.ai.timing.anchor==nil,"Help advanced history or started the clock")
        startup.feed(startup.observation(hand:true))
        check(startup.ai.checkingHelp==nil,"Hand pause left stale board diagnosis")
        startup.feed(uncertain,count:2)
        check(startup.ai.checkingHelp==nil,"Fresh withdrawal inherited old presentation timing")
        startup.feed(uncertain,count:16)
        check(startup.ai.checkingHelp != nil,"Persistent post-hand ambiguity never regained explanation")
        startup.ai.pause()
        check(startup.ai.phase == .paused && startup.ai.checkingHelp==nil,"Pause retained stale checking help")
        startup.ai.resume();startup.feed(uncertain,count:18)
        check(startup.ai.checkingHelp != nil,"Resumed checking failed to report persistent uncertainty")
        startup.ai.laser.observeCamera(hand:false,valid:true,capturedAt:startup.clock.now,now:startup.clock.now,context:"replacement-grid")
        startup.feed(uncertain)
        check(startup.ai.checkingHelp==nil,"New camera context reused prior help")
        startup.feed(uncertain,count:17)
        check(startup.ai.checkingHelp != nil,"Replacement context never produced its own explanation")
        startup.feed(startup.observation(),count:4)
        check(startup.ai.phase == .human && startup.ai.checkingHelp==nil,"Delayed valid board did not recover automatically")
        check(startup.ai.snapshot!.id==id && startup.ai.snapshot!.moves.isEmpty && startup.ai.timing.anchor != nil,"Recovery replaced game/history or lost normal clock start")
        startup.ai.pause()

        let placement=try CheckingScenario(root:root,moves:[72,180,300],humanBlack:false,verified:true)
        placement.feed(placement.observation(),count:4)
        let anchor=placement.ai.timing.anchor
        let ambiguous=placement.observation([275:.white],weak:[294])
        let candidate=placement.observation([275:.white])
        for _ in 0..<12 {placement.feed(ambiguous);placement.feed(candidate)}
        check(placement.ai.phase == .human && placement.ai.checkingHelp != nil,"Alternating ambiguous/stable observations hid a long human-placement delay")
        check(placement.ai.snapshot!.moves.count==3 && placement.ai.timing.anchor==anchor,"Placement explanation changed accepted history or clock anchor")
        check(placement.ai.checkingHelp?.emptyGame==false && !(placement.ai.checkingHelp?.recovery.contains("capture an empty reference") ?? true),"Occupied game offered empty-reference recapture")
        placement.feed(candidate,count:4)
        check(placement.ai.snapshot!.moves.count==4 && placement.ai.checkingHelp==nil,"Clear later placement failed to recover or left stale help")
        placement.ai.pause()
        print("PASS: \(checks) checking-controller checks; delayed startup and placement recovery, hands, pause, scope, preserved history/clocks")
    }
}
