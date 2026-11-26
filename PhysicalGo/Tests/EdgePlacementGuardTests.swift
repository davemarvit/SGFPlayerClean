import Foundation

/// Boundary-contract tests with injected recognition/pose results. These do not
/// measure Vision recall or establish physical hand clearance from photographs.
@main struct EdgePlacementGuardTests {
    @MainActor static func main() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("edge-placement-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        var now=100.0,wall=1000.0,checks=0
        func check(_ value:Bool,_ message:String) {
            checks+=1
            if !value {fputs("FAIL: "+message+"\n",stderr)}
            precondition(value,message)
        }
        let targets=[("A1",18,0),("T1",18,18),("A19",0,0),("T19",0,18),
                     ("K1",18,9),("K19",0,9),("A10",9,0),("T10",9,18)]
        for (coordinate,row,col) in targets {
            let folder=root.appendingPathComponent(coordinate)
            let pointer=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,
                wallTime:{wall},uptime:{now})
            var engineCalls=0
            let game=PhysicalAI(directory:folder,generate:{_,_ in engineCalls+=1;return coordinate},laser:pointer,
                uptime:{now},wallTime:{wall})
            game.draft.size=19;game.draft.humanBlack=true
            check(game.start(),"Start "+coordinate)
            var board=Array(repeating:"empty",count:361)
            func observe(hand:Bool?=false) {
                now+=0.2;wall+=0.2
                var observation=BoardObservation(readings:board.enumerated().map {
                    .init(row:$0.offset/19,col:$0.offset%19,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)
                },size:19)
                observation.capturedAt=now;observation.handObstructed=hand
                game.consume(observation,now:now)
            }
            for _ in 0..<4 {observe()}
            check(game.phase == .human,"Initial empty board "+coordinate)
            board[180]="black"
            for _ in 0..<8 {observe()}
            for _ in 0..<100 where game.phase != .placing {try await Task.sleep(nanoseconds:1_000_000)}
            check(engineCalls==1 && game.phase == .placing && game.pendingPoint==row*19+col,
                  "Authoritative White edge/corner target "+coordinate)
            check(game.snapshot?.moves.count==2 && game.snapshot?.pendingPlacement==true,"Pending history "+coordinate)
            let identity=game.snapshot!.id,decision=game.snapshot!.moves.last!.decisionReceivedAtUnix
            let anchor=game.timing.anchor
            pointer.setEnabled(true)
            func request()throws->PhysicalLaserGuidance.Request {
                try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,
                    from:Data(contentsOf:pointer.directory.appendingPathComponent("request.json")))
            }
            func status(lit:Bool)throws {
                let value=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:pointer.producer,
                    sequence:pointer.sequence,updatedAtUnix:wall,mode:"simulation",state:lit ? "marking":"off",
                    laserOn:lit,offSinceUnix:lit ? nil:wall-1,detail:"edge contract simulation")
                try JSONEncoder().encode(value).write(to:pointer.directory.appendingPathComponent("status.json"),options:.atomic)
                pointer.tick()
            }
            pointer.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"edge/grid")
            try status(lit:false)
            pointer.verifyEmptyTarget(capturedAt:now,now:now)
            check(try request().action=="point","Clear empty edge target admitted "+coordinate)
            try status(lit:true)
            // No hand-true event occurs anywhere in this game. A target-local
            // positive stone reading must still turn the beam off immediately.
            board[row*19+col]="white"
            observe()
            let stopped=try request()
            check(pointer.suppressed && stopped.action=="off","Stone stops beam without hand event "+coordinate)
            check(game.phase == .placing && game.snapshot!.pendingPlacement,"Lit stone is not placement proof "+coordinate)
            check(game.snapshot!.id==identity && game.snapshot!.moves.count==2 && game.timing.anchor==anchor &&
                  game.snapshot!.moves.last!.decisionReceivedAtUnix==decision,"Lit stop preserves history/clock boundary "+coordinate)
            pointer.setEnabled(false)
            try status(lit:false)
            check(pointer.acceptsObservation(capturedAt:now,now:now),"Matching simulated OFF admits dark evidence "+coordinate)
            for _ in 0..<4 {observe()}
            check(game.phase == .human && !game.snapshot!.pendingPlacement && game.pendingPoint==nil,
                  "Dark stable White placement needs no hand episode "+coordinate)
            check(game.snapshot!.moves.count==2 && game.snapshot!.id==identity,"Placement never appends another move "+coordinate)
            game.pause()
        }

        // A single joint just inside the outer-line guard is sufficient even
        // while the other joints remain outside. Sparse poses remain unknown.
        for edge in 0..<4 {
            func rotate(_ x:Double,_ y:Double)->(Double,Double) {
                switch edge {case 1:return (18-y,x);case 2:return (18-x,18-y);case 3:return (y,18-x);default:return(x,y)}
            }
            for lateral in [0.0,9.0,18.0] {
                let joints=(0..<8).map {i -> HandMotionPose.Point in
                    let p=rotate(lateral,i==0 ? -0.60:-1.0)
                    return .init(id:"j\(i)",x:p.0,y:p.1,confidence:0.9)
                }
                let shallow=HandMotionPose(hands:[joints])
                check(shallow.obstructed(size:19)==true,"Shallow entry detected at edge\(edge), lateral\(lateral)")
                check(HandMotionPose(hands:[[joints[0]]],reliable:false).obstructed(size:19)==nil,
                      "Partial pose is unknown, never clear")
                let pointer=PhysicalLaserGuidance(directory:root.appendingPathComponent("shallow-\(edge)-\(lateral)"),
                    automatic:false,wallTime:{wall},uptime:{now})
                pointer.setEnabled(true)
                pointer.setTarget(.init(source:"ai",session:UUID(),moveNumber:2,size:19,row:0,col:0,black:false,decisionReceivedAtUnix:wall))
                func readRequest()throws->PhysicalLaserGuidance.Request {
                    try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,
                        from:Data(contentsOf:pointer.directory.appendingPathComponent("request.json")))
                }
                func writeStatus(lit:Bool)throws {
                    let value=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:pointer.producer,
                        sequence:pointer.sequence,updatedAtUnix:wall,mode:"simulation",state:lit ? "marking":"off",
                        laserOn:lit,offSinceUnix:lit ? nil:wall-1,detail:"shallow contract simulation")
                    try JSONEncoder().encode(value).write(to:pointer.directory.appendingPathComponent("status.json"),options:.atomic)
                    pointer.tick()
                }
                pointer.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"edge/grid")
                try writeStatus(lit:false)
                pointer.verifyEmptyTarget(capturedAt:now,now:now)
                check(try readRequest().action=="point","Shallow-entry control begins pointing")
                try writeStatus(lit:true)
                // An unavailable/sparse pose must already inhibit light. A
                // subsequent positive shallow pose additionally latches stop.
                pointer.observeCamera(hand:nil,valid:true,capturedAt:now,now:now,context:"edge/grid")
                check(try readRequest().action=="off","Unknown visibility inhibits an active indication")
                pointer.observeCamera(hand:shallow.obstructed(size:19),valid:true,capturedAt:now,now:now,context:"edge/grid")
                let request=try readRequest()
                check(pointer.suppressed && request.action=="off","Shallow pose inhibits indication")
                pointer.setEnabled(false)
            }
        }
        print("PASS: \(checks) edge/corner placement and shallow-pose contract checks; Vision recall not simulated")
    }
}
