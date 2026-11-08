import Foundation
@main struct OnlineBoardTests {
    @MainActor static func main() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let stateURL=directory.appendingPathComponent("state.json"), moveURL=directory.appendingPathComponent("move.json")
        let saved=try? Data(contentsOf:stateURL)
        defer { if let saved {try? saved.write(to:stateURL)} else {try? FileManager.default.removeItem(at:stateURL)}; try? FileManager.default.removeItem(at:moveURL) }
        try? FileManager.default.removeItem(at:moveURL)
        var board=Array(repeating:"empty",count:81)
        func publish(_ version:Int, turn:Bool=true, stale:Bool=false, game:Int=42) throws {
            let state:[String:Any]=["token":"test","game":game,"version":version,"size":9,"cells":board,"ready":true,"myTurn":turn,"color":"black","time":Date().timeIntervalSince1970-(stale ? 10 : 0)]
            try JSONSerialization.data(withJSONObject:state).write(to:stateURL,options:.atomic)
        }
        func view(_ point:Int?=nil, uncertain:Bool=false, confidence:Double=1)->BoardObservation {
            BoardObservation(readings:(0..<81).map { i in IntersectionReading(row:i/9,col:i%9,occupancy:uncertain && i==80 ? .uncertain : (i==point ? .black : Occupancy(rawValue:board[i])!),confidence:confidence,delta:0)},size:9)
        }
        try publish(1)
        let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{}); bridge.enabled=true
        for i in 0..<6 {bridge.consume(view(0),now:Double(i)*0.3+1)}
        precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Must synchronize first")
        bridge.consume(view(confidence:0.72),now:2.9)
        precondition(bridge.status=="Your turn.","Classified empty intersections must not require an unrelated 0.9 cutoff")
        bridge.consume(view(uncertain:true),now:2.95)
        precondition(bridge.status=="Your turn." && bridge.cameraStatus==nil,"Brief uncertainty must not flicker the turn status")
        bridge.consume(view(),now:3)
        let physicalTrackingSession=bridge.stoneTrackingIdentity
        precondition(!physicalTrackingSession.isEmpty)
        for i in 0..<6 {bridge.consume(view(0),now:Double(i)*0.3+3.1)}
        precondition(FileManager.default.fileExists(atPath:moveURL.path),"Stable move should send")
        try FileManager.default.removeItem(at:moveURL)
        for i in 0..<6 {bridge.consume(view(0),now:Double(i)*0.3+5)}
        precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Never retry automatically")
        board[0]="black"; try publish(2,turn:false)
        bridge.consume(view(),now:7)
        precondition(bridge.stoneTrackingIdentity==physicalTrackingSession,"Ordinary OGS move reset physical geometry context")
        for i in 0..<6 {bridge.consume(view(1),now:Double(i)*0.3+7.1)}
        precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Opponent turn must not send")
        try publish(3,stale:true);bridge.consume(view(),now:10)
        precondition(bridge.status.contains("Waiting"))
        precondition(bridge.stoneTrackingIdentity.isEmpty,"Stale connection retained physical tracking context")
        try publish(4,game:43);bridge.consume(view(),now:11)
        precondition(!bridge.stoneTrackingIdentity.isEmpty && bridge.stoneTrackingIdentity != physicalTrackingSession,"New online game reused physical geometry context")
        try unchangedServerVersionTests(directory:directory)
        try splitUpdateSoundTests(directory:directory)
        try clarityFeedbackTests(directory:directory)
        try placementFeedbackTests(directory:directory)
        try liveTurnTests(directory:directory)
        try m17SynchronizationTests(directory:directory)
        try synchronizationInterruptionTests(directory:directory)
        try intermittentConfirmationTests(directory:directory)
        try recordedDelayTests(directory:directory)
        try recurringDelayTests(directory:directory)
        try decisionLogTests(directory:directory)
        try captureTests(directory:directory)
        try rejectedMoveTests(directory:directory)
        differentialTests()
        try orientationTests(directory:directory)
        print("Online board tests passed: synchronization, stable send, duplicate suppression, opponent turn, stale state")
    }
    @MainActor static func rejectedMoveTests(directory:URL) throws {
        let n=9,koPoint=10,captured=11
        var game=SGFGame();game.boardSize=n;game.info.rules="japanese"
        game.setup=[(.black,1,0),(.black,0,1),(.black,1,2),(.white,1,1),(.white,2,0),(.white,3,1),(.white,2,2)]
        let engine=SGFPlayer();engine.load(game:game)
        precondition(engine.tryPlayMove(color:.black,x:2,y:1)==nil)
        precondition(engine.moveRejection(color:.white,x:1,y:1) == .ko)
        let board=engine.board.grid.flatMap{$0.map{$0?.rawValue ?? "empty"}}
        var recapture=board;recapture[koPoint]="white";recapture[captured]="empty"
        precondition(PhysicalMoveInference.candidate(board:board,observed:recapture,size:n,color:"white")==koPoint)
        let move=directory.appendingPathComponent("move.json")
        try? FileManager.default.removeItem(at:move)
        func publish(_ feedback:[String:Any]=[:]) throws {
            let state:[String:Any]=["token":"ko-test","game":710,"version":1,"size":n,"cells":board,
                "ready":true,"myTurn":true,"color":"white","time":Date().timeIntervalSince1970,
                "illegalMoves":[String(koPoint):SGFPlayer.MoveRejection.ko.rawValue],"moveFeedback":feedback]
            try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"))
        }
        func view(_ cells:[String],uncertain:Bool=false)->BoardObservation {
            BoardObservation(readings:cells.indices.map {i in .init(row:i/n,col:i%n,
                occupancy:uncertain && i==80 ? .uncertain : Occupancy(rawValue:cells[i])!,confidence:1,delta:0)},size:n)
        }
        let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{})
        bridge.enabled=true;try publish();bridge.consume(view(board),now:1)
        for i in 0..<8 {try publish();bridge.consume(view(recapture,uncertain:i%2==0),now:1.1+Double(i)*0.3)}
        precondition(bridge.moveIssue==SGFPlayer.MoveRejection.ko.rawValue,"Ko must be explained despite unrelated uncertainty")
        precondition(!FileManager.default.fileExists(atPath:move.path),"Illegal recapture reached transport")
        precondition(bridge.placementIssue?.remove.contains(koPoint)==true && bridge.placementIssue?.place.contains(captured)==true,"Ko needs removal and restoration markers")
        try publish();bridge.consume(view(board),now:4)
        precondition(bridge.moveIssue==nil,"Restored board must clear ko warning")
        var legal=board;legal[60]="white"
        for i in 0..<6 {try publish();bridge.consume(view(legal),now:4.1+Double(i)*0.3)}
        let request=try JSONSerialization.jsonObject(with:Data(contentsOf:move)) as! [String:Any]
        let id=request["id"] as! String
        try FileManager.default.removeItem(at:move)
        try publish(["id":"old-request","version":1,"status":"rejected","message":"Stale error"])
        bridge.consume(view(legal),now:6)
        precondition(bridge.moveIssue==nil,"Stale feedback affected a different request")
        try publish();bridge.consume(view(legal),now:15)
        precondition(bridge.moveIssue?.contains("not confirmed")==true,"Missing response must not wait silently forever")
        precondition(!FileManager.default.fileExists(atPath:move.path),"Timed-out move retried itself")
        try publish(["id":id,"version":1,"status":"rejected","message":"OGS: test rejection"])
        bridge.consume(view(legal,uncertain:true),now:15.3)
        precondition(bridge.moveIssue=="OGS: test rejection","Server rejection not presented")
        for i in 0..<6 {try publish();bridge.consume(view(legal),now:15.6+Double(i)*0.3)}
        precondition(!FileManager.default.fileExists(atPath:move.path),"Rejected move retried itself")
        try publish();bridge.consume(view(board),now:18)
        precondition(bridge.moveIssue==nil)
        legal=board;legal[61]="white"
        for i in 0..<6 {try publish();bridge.consume(view(legal),now:18.1+Double(i)*0.3)}
        precondition(FileManager.default.fileExists(atPath:move.path),"A legal alternative was blocked after restoration")
        try FileManager.default.removeItem(at:move)
        print("Illegal-move tests passed: ko/history, partial clarity, restoration marks, correlated rejection, timeout, no retries, legal alternative")
    }
    @MainActor static func unchangedServerVersionTests(directory:URL) throws {
        let n=19, blackPoint=3*19+16, whitePoint=16*19+3, nextBlack=3*19+3
        let stateURL=directory.appendingPathComponent("state.json")
        let moveURL=directory.appendingPathComponent("move.json")
        // Exercise both the repaired publisher and legacy snapshots that keep version=0.
        for legacy in [false,true] {
            var revision=PhysicalBoardBridgeRevision()
            var position=PhysicalBoardBridgeRevision.Position(game:92,serverVersion:0,
                size:n,cells:Array(repeating:"empty",count:n*n),moveNumber:0,
                currentPlayerID:1,color:"black",lastX:-1,lastY:-1,ready:true)
            var notifications=0
            let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{notifications += 1},announceCorrection:{})
            bridge.enabled=true
            func publish() throws -> Int {
                let version=revision.update(position)
                let state:[String:Any]=["token":"constant-version-\(legacy)","game":92,
                    "version":legacy ? 0:version,"size":n,"cells":position.cells,
                    "lastX":position.lastX,"lastY":position.lastY,"ready":position.ready,
                    "myTurn":position.currentPlayerID==1,"color":"black","time":Date().timeIntervalSince1970]
                try JSONSerialization.data(withJSONObject:state).write(to:stateURL,options:.atomic)
                return version
            }
            func view(_ cells:[String])->BoardObservation {
                BoardObservation(readings:cells.indices.map {IntersectionReading(row:$0/n,col:$0%n,
                    occupancy:Occupancy(rawValue:cells[$0])!,confidence:1,delta:0)},size:n)
            }
            let initial=try publish()
            bridge.consume(view(position.cells),now:1)
            var physical=position.cells;physical[blackPoint]="black"
            for i in 0..<6 {bridge.consume(view(physical),now:1.1+Double(i)*0.25)}
            precondition(FileManager.default.fileExists(atPath:moveURL.path))
            let first=try JSONSerialization.jsonObject(with:Data(contentsOf:moveURL)) as! [String:Any]
            try FileManager.default.removeItem(at:moveURL)
            position.cells=physical;position.moveNumber=1;position.currentPlayerID=2
            position.lastX=blackPoint%n;position.lastY=blackPoint/n
            let ack=try publish()
            precondition(ack>initial)
            bridge.consume(view(physical),now:2.6)
            precondition(bridge.cells==physical && bridge.lastPoint==blackPoint)
            precondition(bridge.status=="Waiting for your opponent." && notifications==0)
            position.cells[whitePoint]="white";position.moveNumber=2;position.currentPlayerID=1
            position.lastX=whitePoint%n;position.lastY=whitePoint/n
            let opponent=try publish()
            precondition(opponent>ack)
            if !legacy {precondition(first["version"] as? Int != opponent,"Old requests must not match a later turn")}
            // Opponent display must update BEFORE its physical stone is placed,
            // even with an obscured camera reading.
            var obscured=physical;obscured[0]="uncertain"
            bridge.consume(view(obscured),now:2.8)
            precondition(bridge.cells==position.cells && bridge.lastPoint==whitePoint)
            precondition(notifications==1 && !FileManager.default.fileExists(atPath:moveURL.path))
            for i in 0..<4 {
                let heartbeat=try publish();precondition(heartbeat==opponent)
                bridge.consume(view(physical),now:3+Double(i)*0.2)
            }
            precondition(notifications==1,"Repeated snapshots must not repeat the sound")
            precondition(!FileManager.default.fileExists(atPath:moveURL.path))
            physical=position.cells
            bridge.consume(view(physical),now:3.8)
            precondition(bridge.status=="Your turn.")
            physical[nextBlack]="black"
            for i in 0..<6 {bridge.consume(view(physical),now:4+Double(i)*0.25)}
            let next=try JSONSerialization.jsonObject(with:Data(contentsOf:moveURL)) as! [String:Any]
            precondition(next["x"] as? Int==nextBlack%n && next["y"] as? Int==nextBlack/n)
            if !legacy {precondition(next["version"] as? Int==opponent)}
            try FileManager.default.removeItem(at:moveURL)
            for i in 0..<6 {bridge.consume(view(physical),now:5.4+Double(i)*0.25)}
            precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Second move also sends only once")
            // Passes change revision without a stone change. Undo returning to
            // the same turn/board must receive a new revision, never reuse one.
            position.moveNumber=3;position.currentPlayerID=2;position.lastX = -1;position.lastY = -1
            let pass=revision.update(position);precondition(pass>opponent)
            position.moveNumber=2;position.currentPlayerID=1;position.lastX=whitePoint%n;position.lastY=whitePoint/n
            let undo=revision.update(position);precondition(undo>pass)
            precondition(revision.update(position)==undo)
        }
        print("Constant OGS version tests passed: 19x19 first move, opponent display/marker/single sound, second move, heartbeats, pass, undo, stale request rejection")
    }

    @MainActor static func splitUpdateSoundTests(directory:URL) throws {
        for turnFirst in [false,true] {
            var count=0, board=Array(repeating:"empty",count:81)
            board[0]="black"
            let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{count += 1},announceCorrection:{})
            bridge.enabled=true
            func update(turn:Bool,white:Bool,time:Double) throws {
                board[80]=white ? "white":"empty"
                let state:[String:Any]=["token":"split-\(turnFirst)","game":99,"version":0,"size":9,
                    "cells":board,"ready":true,"myTurn":turn,"color":"black",
                    "lastX":white ? 8:0,"lastY":white ? 8:0,"time":Date().timeIntervalSince1970]
                try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
                let observation=BoardObservation(readings:board.indices.map {IntersectionReading(row:$0/9,col:$0%9,
                    occupancy:Occupancy(rawValue:board[$0])!,confidence:1,delta:0)},size:9)
                bridge.consume(observation,now:time)
            }
            try update(turn:false,white:false,time:1)
            try update(turn:turnFirst,white:!turnFirst,time:1.2)
            precondition(count==0,"A partial turn/board update must not announce early")
            try update(turn:true,white:true,time:1.4)
            try update(turn:true,white:true,time:1.6)
            precondition(count==1,"Turn and board arriving separately must announce only once")
        }
        print("Split update tests passed: board-first and turn-first each announce exactly once")
    }

    @MainActor static func clarityFeedbackTests(directory:URL) throws {
        let n=19, moveURL=directory.appendingPathComponent("move.json")
        let empty=Array(repeating:"empty",count:n*n)
        var state:[String:Any]=["token":"clarity","game":123,"version":1,"size":n,"cells":empty,
            "ready":true,"myTurn":true,"color":"black","time":Date().timeIntervalSince1970]
        func publish() throws {
            try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
        }
        func view(stone:Bool=false,uncertain:Bool=false)->BoardObservation {
            BoardObservation(readings:(0..<n*n).map {IntersectionReading(row:$0/n,col:$0%n,
                occupancy:uncertain && $0==0 ? .uncertain : (stone && $0==0 ? .black:.empty),
                confidence:1,delta:0)},size:n)
        }
        try publish()
        let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{})
        bridge.enabled=true
        bridge.consume(view(),now:1)
        bridge.consume(view(uncertain:true),now:1.1)
        precondition(bridge.status=="Your turn." && bridge.cameraStatus==nil)
        bridge.consume(view(),now:1.2);bridge.consume(view(),now:1.9)
        precondition(bridge.cameraStatus==nil,"An isolated unclear frame stays quiet")
        // Mostly clear frames with repeated interruptions must never accumulate
        // enough stable evidence to send, even though the turn text stays steady.
        for i in 0..<20 {
            bridge.consume(view(stone:true,uncertain:i%3==0),now:2+Double(i)*0.2)
            precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Presentation smoothing must not smooth move evidence")
            if i%3==0 {precondition(bridge.status=="Your turn." || bridge.status=="Checking the new stone’s position.")}
        }
        precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Uncertain new stone cannot send")
        bridge.consume(view(uncertain:true),now:5.9)
        bridge.consume(view(),now:6)
        bridge.consume(view(),now:6.4)
        precondition(bridge.status=="Your turn.","A clearly withdrawn candidate returns to no-move state")
        bridge.consume(view(),now:6.7)
        precondition(bridge.cameraStatus==nil && bridge.status=="Your turn.")
        for i in 0..<6 {bridge.consume(view(stone:true),now:6.8+Double(i)*0.25)}
        precondition(FileManager.default.fileExists(atPath:moveURL.path),"Clear stable evidence must still send")
        try FileManager.default.removeItem(at:moveURL)
        bridge.consume(view(stone:true,uncertain:true),now:8.2)
        precondition(bridge.status=="Move sent. Waiting for the server.")
        for i in 0..<8 {bridge.consume(view(stone:true),now:8.3+Double(i)*0.2)}
        precondition(!FileManager.default.fileExists(atPath:moveURL.path))
        state["time"]=Date().timeIntervalSince1970-10;try publish()
        bridge.consume(view(),now:10)
        precondition(bridge.status=="Waiting for a connected live game in SGF Player." && bridge.cameraStatus==nil,
            "Connection loss must bypass camera presentation hysteresis")
        print("Camera feedback tests passed: brief uncertainty, persistent flicker, delayed recovery, immediate move blocking, stable send, no repeat, immediate connection loss")
    }

    @MainActor static func placementFeedbackTests(directory:URL) throws {
        let n=19, target=307, wrong=306, nextBlack=60
        let moveURL=directory.appendingPathComponent("move.json")
        for turns in 0..<4 {
            var expected=Array(repeating:"empty",count:n*n)
            expected[72]="black";expected[target]="white"
            let state:[String:Any]=["token":"placement-\(turns)","game":144,"version":2,
                "size":n,"cells":expected,"ready":true,"myTurn":true,"color":"black",
                "lastX":target%n,"lastY":target/n,"time":Date().timeIntervalSince1970]
            try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
            var alerts=0
            let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{alerts += 1})
            bridge.enabled=true
            func observe(_ cells:[String],_ now:Double,uncertain:Bool=false) {
                let readings=(0..<n*n).map { raw -> IntersectionReading in
                    let displayed=PhysicalMoveInference.displayedPoint(row:raw/n,col:raw%n,size:n,quarterTurns:turns)
                    return IntersectionReading(row:raw/n,col:raw%n,
                        occupancy:uncertain && raw==0 ? .uncertain:Occupancy(rawValue:cells[displayed])!,confidence:1,delta:0)
                }
                bridge.consume(BoardObservation(readings:readings,size:n),now:now,quarterTurns:turns)
            }
            var physical=expected;physical[target]="empty"
            for i in 0..<5 {observe(physical,1+Double(i)*0.25)}
            precondition(bridge.placementIssue?.place==[target] && bridge.placementIssue?.remove==[])
            precondition(alerts==0,"Normal opponent placement must not sound an error")
            physical[wrong]="white"
            observe(physical,2.3);observe(physical,2.55)
            observe(physical,2.65,uncertain:true)
            observe(physical,2.8);observe(physical,3.05);observe(physical,3.3)
            precondition(alerts==0,"Hand interruption must restart mismatch confirmation")
            observe(physical,3.55)
            precondition(bridge.placementIssue?.remove==[wrong] && bridge.placementIssue?.place==[target])
            precondition(bridge.placementIssue?.title=="Reposition the white stone" && alerts==1)
            precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Wrong opponent placement must never submit a move")
            observe(physical,3.7,uncertain:true)
            precondition(bridge.placementIssue?.remove==[wrong],"Confirmed guidance should survive a hand covering the camera")
            for i in 0..<5 {observe(physical,3.9+Double(i)*0.25)}
            precondition(alerts==1,"One correction alert per mismatch episode")
            physical=expected;observe(physical,4.95,uncertain:true)
            precondition(bridge.placementIssue==nil,"Corrected stones must not retain a stale warning because another point is uncertain")
            precondition(bridge.status=="Checking the remaining unclear intersections.")
            precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Unclear board must not synchronize or send")
            observe(physical,5)
            precondition(bridge.placementIssue==nil && bridge.status=="Your turn.")
            physical[nextBlack]="black"
            for i in 0..<6 {
                observe(physical,5.1+Double(i)*0.25)
                precondition(bridge.placementIssue==nil,"A legal own move must not show a correction warning")
            }
            precondition(FileManager.default.fileExists(atPath:moveURL.path) && alerts==1)
            try FileManager.default.removeItem(at:moveURL)
            bridge.enabled=false
            precondition(bridge.placementIssue==nil)
        }
        print("Placement feedback tests passed: stable wrong White placement, source/target markers across four rotations, hand interruption, one alert, correction clears, next legal move sends")
    }

    @MainActor static func liveTurnTests(directory:URL) throws {
        let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{})
        bridge.enabled=true
        let n=19
        let unclear=BoardObservation(readings:(0..<n*n).map {IntersectionReading(row:$0/n,col:$0%n,
            occupancy:.uncertain,confidence:0,delta:0)},size:n)
        var state:[String:Any]=["token":"turn","game":155,"version":0,"size":n,
            "cells":Array(repeating:"empty",count:n*n),"ready":true,"time":Date().timeIntervalSince1970]
        func publish() throws {
            try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
        }
        for own in [Stone.black,Stone.white] {
            for myTurn in [true,false,true] {
                state["color"]=own.rawValue;state["myTurn"]=myTurn;try publish()
                bridge.consume(unclear,now:1)
                precondition(bridge.turnColor==(myTurn ? own:own.opponent) && bridge.isMyTurn==myTurn,
                    "Online turn must come from server/account color, independent of unclear camera or local recorder")
            }
        }
        state["ready"]=false;try publish();bridge.consume(unclear,now:2)
        precondition(bridge.turnColor==nil,"Unavailable live state must not leave a stale turn heading")
        state["ready"]=true;state["color"]="black";state["myTurn"]=false;try publish()
        bridge.consume(unclear,now:2.1)
        precondition(bridge.turnColor == .white && !bridge.isMyTurn)
        state["time"]=Date().timeIntervalSince1970-10;try publish();bridge.consume(unclear,now:2.2)
        precondition(bridge.turnColor==nil)
        state["time"]=Date().timeIntervalSince1970;try publish();bridge.consume(unclear,now:2.3)
        bridge.enabled=false
        precondition(bridge.turnColor==nil)
        print("Live turn tests passed: both account colors, alternating turns, unclear camera, disconnected/stale state and disabled bridge")
    }

    @MainActor static func m17SynchronizationTests(directory:URL) throws {
        let url=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/M17Synchronization.json")
        let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
        let board=fixture["board"] as! [String],n=fixture["size"] as! Int,turns=fixture["quarterTurns"] as! Int
        let opponent=fixture["opponentPoint"] as! Int,point=fixture["candidatePoint"] as! Int
        let frames=fixture["frames"] as! [[String:Any]]
        precondition(board[opponent]=="white" && board[point]=="empty" && point==49)
        var prior=board;prior[opponent]="empty"
        var state:[String:Any]=["token":"m17","game":177,"version":1,"size":n,"cells":prior,
            "ready":true,"myTurn":false,"color":"black","time":Date().timeIntervalSince1970]
        func publish() throws {
            try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
        }
        func observation(_ camera:[String])->BoardObservation {
            BoardObservation(readings:camera.indices.map {IntersectionReading(row:$0/n,col:$0%n,
                occupancy:Occupancy(rawValue:camera[$0])!,confidence:1,delta:0)},size:n)
        }
        var priorCamera=Array(repeating:"empty",count:n*n)
        for raw in priorCamera.indices {priorCamera[raw]=prior[PhysicalMoveInference.displayedPoint(row:raw/n,col:raw%n,size:n,quarterTurns:turns)]}
        let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{})
        bridge.enabled=true;try publish();bridge.consume(observation(priorCamera),now:9,quarterTurns:turns)
        state["version"]=2;state["cells"]=board;state["myTurn"]=true;try publish()
        // Actual camera frames already contain both the opponent's latest stone
        // and M17: no intermediate exact server-board frame is available.
        let moveURL=directory.appendingPathComponent("move.json")
        var sentCount=0
        for frame in frames {
            var camera=Array(repeating:"empty",count:n*n)
            for reading in frame["occupied"] as! [[Any]] {
                camera[(reading[0] as! Int)*n+(reading[1] as! Int)]=reading[2] as! String
            }
            bridge.consume(observation(camera),now:10+(frame["elapsed"] as! Double),quarterTurns:turns)
            if FileManager.default.fileExists(atPath:moveURL.path) {
                let request=try JSONSerialization.jsonObject(with:Data(contentsOf:moveURL)) as! [String:Any]
                precondition(request["x"] as? Int==11 && request["y"] as? Int==2)
                precondition((frame["elapsed"] as! Double)>=1,"Local evidence must still settle")
                sentCount += 1;try FileManager.default.removeItem(at:moveURL)
            }
            precondition(bridge.placementIssue==nil,"A legal M17 move must not be labeled Remove")
        }
        precondition(sentCount==1,"M17 must send once after fresh stable readings")
        // A revision change without a position/turn change is not a move acknowledgment.
        state["version"]=3;try publish()
        var candidateCamera=Array(repeating:"empty",count:n*n)
        var candidateBoard=board;candidateBoard[point]="black"
        for raw in candidateCamera.indices {candidateCamera[raw]=candidateBoard[PhysicalMoveInference.displayedPoint(row:raw/n,col:raw%n,size:n,quarterTurns:turns)]}
        for i in 0..<8 {bridge.consume(observation(candidateCamera),now:40+Double(i)*0.25,quarterTurns:turns)}
        precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Revision-only updates must not resend a pending move")
        print("M17 replay passed: \(frames.count) actual rotated camera observations, interrupted clear view, no intermediate matched position, exactly one correct move")
    }

    @MainActor static func synchronizationInterruptionTests(directory:URL) throws {
        let n=9,board=Array(repeating:"empty",count:81),moveURL=directory.appendingPathComponent("move.json")
        for lighting in [false,true] {
            var state:[String:Any]=["token":"interrupt-\(lighting)","game":188,"version":1,"size":n,
                "cells":board,"ready":true,"myTurn":true,"color":"black","time":Date().timeIntervalSince1970]
            func publish() throws {
                try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
            }
            func view(_ stone:Bool)->BoardObservation {
                BoardObservation(readings:(0..<81).map {IntersectionReading(row:$0/n,col:$0%n,
                    occupancy:stone && $0==10 ? .black:.empty,confidence:1,delta:0)},size:n)
            }
            let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{})
            bridge.enabled=true;try publish();bridge.consume(view(false),now:1)
            bridge.consume(view(true),now:1.1);bridge.consume(view(true),now:1.4)
            if lighting {
                var blocked=view(true);blocked.lightingBlocked=true;bridge.consume(blocked,now:1.5)
            }
            let resumed=lighting ? 1.6:3.0
            bridge.consume(view(true),now:resumed);bridge.consume(view(true),now:resumed+0.3)
            precondition(!FileManager.default.fileExists(atPath:moveURL.path),"A gap or lighting interruption must restart settlement")
            for i in 2..<6 {bridge.consume(view(true),now:resumed+Double(i)*0.3)}
            precondition(FileManager.default.fileExists(atPath:moveURL.path),"Session match must survive a camera interruption")
            try FileManager.default.removeItem(at:moveURL)
            // Unlike a camera interruption, loss of live server state requires
            // an explicit full match again before automatic sending resumes.
            state["time"]=Date().timeIntervalSince1970-10;try publish();bridge.consume(view(true),now:6)
            state["time"]=Date().timeIntervalSince1970;try publish()
            for i in 0..<6 {bridge.consume(view(true),now:6.1+Double(i)*0.3)}
            precondition(!FileManager.default.fileExists(atPath:moveURL.path))
            precondition(bridge.placementIssue?.requiresSynchronization==true)
            precondition(bridge.placementIssue?.title=="Synchronize before playing")
            bridge.consume(view(false),now:8)
            // Changing game must not carry the previous game's match forward.
            state["game"]=189;try publish()
            for i in 0..<6 {bridge.consume(view(true),now:8.1+Double(i)*0.3)}
            precondition(!FileManager.default.fileExists(atPath:moveURL.path))
        }
        print("Synchronization interruption tests passed: camera gaps and lighting preserve session match but restart settlement; reconnect and game changes still require a full match")
    }

    @MainActor static func intermittentConfirmationTests(directory:URL) throws {
        let n=9,point=10,moveURL=directory.appendingPathComponent("move.json")
        for scenario in ["background","three points","candidate","hand","contradiction","one second interruption","long obstruction","never clear"] {
            let state:[String:Any]=["token":scenario,"game":199,"version":1,"size":n,"cells":Array(repeating:"empty",count:81),
                "ready":true,"myTurn":true,"color":"black","time":Date().timeIntervalSince1970]
            try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
            let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{})
            bridge.enabled=true
            func view(stone:Bool=true,unknown:[Int]=[],contradiction:Bool=false)->BoardObservation {
                BoardObservation(readings:(0..<81).map {IntersectionReading(row:$0/n,col:$0%n,
                    occupancy:unknown.contains($0) ? .uncertain : (stone && $0==point ? .black : (contradiction && $0==20 ? .white:.empty)),confidence:1,delta:0)},size:n)
            }
            bridge.consume(view(stone:false),now:1)
            var sent=0
            for i in 0..<(scenario=="long obstruction" ? 20:10) {
                let interrupted=i%2==1
                let unknown:[Int]
                switch scenario {
                case "candidate":unknown=interrupted ? [point]:[]
                case "hand":unknown=interrupted ? Array(30..<60):[]
                case "three points":unknown=interrupted ? [77,78,79]:[]
                case "one second interruption":unknown=(1...5).contains(i) ? [80]:[]
                case "long obstruction":unknown=(1...14).contains(i) ? [80]:[]
                case "never clear":unknown=[80]
                default:unknown=interrupted ? [80]:[]
                }
                bridge.consume(view(unknown:unknown,contradiction:scenario=="contradiction" && interrupted),now:1.1+Double(i)*0.2)
                if FileManager.default.fileExists(atPath:moveURL.path) {
                    precondition(!unknown.contains(point),"Never send an uncertain candidate")
                    precondition(i>=5,"Never shorten the one-second settlement interval")
                    sent += 1;try FileManager.default.removeItem(at:moveURL)
                }
            }
            precondition(sent == (["background","three points","one second interruption","long obstruction","never clear"].contains(scenario) ? 1:0),"Unexpected send count for \(scenario)")
        }
        print("Intermittent confirmation tests passed: remote uncertainty ignored; candidate uncertainty, broad obstruction and positive contradictions remain blocked")
    }

    @MainActor static func recordedDelayTests(directory:URL) throws {
        let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/IntermittentClarity.json"))) as! [String:Any]
        let n=fixture["size"] as! Int,turns=fixture["quarterTurns"] as! Int,point=fixture["candidatePoint"] as! Int
        var board=fixture["board"] as! [String];precondition(board[point]=="black");board[point]="empty"
        let frames=fixture["frames"] as! [[String:Any]]
        let state:[String:Any]=["token":"delay","game":200,"version":1,"size":n,"cells":board,
            "ready":true,"myTurn":true,"color":"black","time":Date().timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
        func view(_ cells:[String])->BoardObservation {
            BoardObservation(readings:cells.indices.map {IntersectionReading(row:$0/n,col:$0%n,
                occupancy:Occupancy(rawValue:cells[$0])!,confidence:1,delta:0)},size:n)
        }
        var baseline=Array(repeating:"empty",count:n*n)
        for raw in baseline.indices {baseline[raw]=board[PhysicalMoveInference.displayedPoint(row:raw/n,col:raw%n,size:n,quarterTurns:turns)]}
        let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{})
        bridge.enabled=true;bridge.consume(view(baseline),now:9,quarterTurns:turns)
        let moveURL=directory.appendingPathComponent("move.json")
        var count=0,newDelay:Double?,oldDelay:Double?,oldStart:Double?,oldFrames=0
        for frame in frames {
            let elapsed=frame["elapsed"] as! Double
            var camera=Array(repeating:"empty",count:n*n)
            for reading in frame["occupied"] as! [[Any]] {camera[(reading[0] as! Int)*n+(reading[1] as! Int)]=reading[2] as! String}
            if camera.contains("uncertain") {oldStart=nil;oldFrames=0}
            else {
                if oldStart==nil {oldStart=elapsed}
                oldFrames += 1
                if oldDelay==nil,oldFrames>=4,elapsed-oldStart!>=1 {oldDelay=elapsed}
            }
            bridge.consume(view(camera),now:10+elapsed,quarterTurns:turns)
            if FileManager.default.fileExists(atPath:moveURL.path) {
                let request=try JSONSerialization.jsonObject(with:Data(contentsOf:moveURL)) as! [String:Any]
                precondition(request["x"] as? Int==point%n && request["y"] as? Int==point/n)
                precondition(elapsed>=1)
                count += 1;newDelay=elapsed;try FileManager.default.removeItem(at:moveURL)
            }
        }
        precondition(count==1 && newDelay != nil && oldDelay != nil)
        precondition(newDelay!>=1 && newDelay!<2 && oldDelay!>7)
        print(String(format:"Recorded delay replay passed: %d frames, old confirmation %.2f seconds, revised confirmation %.2f seconds; exactly one send from local evidence",frames.count,oldDelay!,newDelay!))
    }

    @MainActor static func recurringDelayTests(directory:URL) throws {
        let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/RecurringClarity.json"))) as! [String:Any]
        let n=fixture["size"] as! Int,turns=fixture["quarterTurns"] as! Int,point=fixture["candidatePoint"] as! Int
        var board=fixture["board"] as! [String];board[point]="empty"
        let frames=fixture["frames"] as! [[String:Any]],start=fixture["delayedStart"] as! Int
        let state:[String:Any]=["token":"recurring-delay","game":201,"version":1,"size":n,"cells":board,
            "ready":true,"myTurn":true,"color":"black","time":Date().timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
        func view(_ cells:[String])->BoardObservation {
            BoardObservation(readings:cells.indices.map {IntersectionReading(row:$0/n,col:$0%n,
                occupancy:Occupancy(rawValue:cells[$0])!,confidence:1,delta:0)},size:n)
        }
        var baseline=Array(repeating:"empty",count:n*n)
        for raw in baseline.indices {baseline[raw]=board[PhysicalMoveInference.displayedPoint(row:raw/n,col:raw%n,size:n,quarterTurns:turns)]}
        let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{})
        bridge.enabled=true;bridge.consume(view(baseline),now:9,quarterTurns:turns)
        let moveURL=directory.appendingPathComponent("move.json"),offset=frames[start]["elapsed"] as! Double
        var count=0,newDelay:Double?,oldDelay:Double?,oldStart:Double?,oldLast=0.0,oldCount=0
        var witnesses=[Double]()
        for frame in frames[start...] {
            let elapsed=(frame["elapsed"] as! Double)-offset
            var camera=Array(repeating:"empty",count:n*n)
            for r in frame["occupied"] as! [[Any]] {camera[(r[0] as! Int)*n+(r[1] as! Int)]=r[2] as! String}
            let unknown=camera.filter{$0=="uncertain"}.count
            if unknown>0 {
                if oldStart == nil || unknown>3 || elapsed-oldLast>0.65 || elapsed-oldStart!>2.5 {oldStart=nil;oldCount=0}
            } else {
                if oldStart==nil || elapsed-oldStart!>2.5 {oldStart=elapsed;oldCount=0}
                oldCount += 1;oldLast=elapsed
                if oldDelay==nil,oldCount>=4,elapsed-oldStart!>=1 {oldDelay=elapsed}
                witnesses.append(elapsed)
            }
            bridge.consume(view(camera),now:10+elapsed,quarterTurns:turns)
            if FileManager.default.fileExists(atPath:moveURL.path) {
                let request=try JSONSerialization.jsonObject(with:Data(contentsOf:moveURL)) as! [String:Any]
                precondition(request["x"] as? Int==point%n && request["y"] as? Int==point/n)
                precondition(elapsed>=1,"Local confirmation still requires one second")
                count += 1;newDelay=elapsed;try FileManager.default.removeItem(at:moveURL)
            }
        }
        precondition(count==1 && oldDelay!>7 && newDelay!<5.5 && newDelay!<oldDelay!)
        print(String(format:"Recurring uncertainty replay passed: 0.61 %.2fs, rolling evidence %.2fs; stable local evidence and one send",oldDelay!,newDelay!))
    }

    @MainActor static func decisionLogTests(directory:URL) throws {
        let url=directory.appendingPathComponent("decisions.jsonl")
        let log=PhysicalOnlineDecisionLog(url:url)
        let board=Array(repeating:"empty",count:81),moveURL=directory.appendingPathComponent("move.json")
        let state:[String:Any]=["token":"SECRET-MUST-NOT-APPEAR","game":987654321,"version":1,"size":9,"cells":board,
            "ready":true,"myTurn":true,"color":"black","time":Date().timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
        let timing=PhysicalMoveTiming(directory:directory.appendingPathComponent("Move Timing"))
        let bridge=PhysicalOnlineBoard(directory:directory,decisionLog:log,moveTiming:timing,announceOpponent:{},announceCorrection:{})
        bridge.enabled=true
        func view(_ stone:Bool=false,_ uncertain:Bool=false)->BoardObservation {
            BoardObservation(readings:(0..<81).map {IntersectionReading(row:$0/9,col:$0%9,
                occupancy:uncertain && $0==80 ? .uncertain : (stone && $0==10 ? .black:.empty),confidence:1,delta:0)},size:9)
        }
        bridge.consume(view(),now:1)
        bridge.consume(view(true),now:1.1)
        bridge.consume(view(true,true),now:1.3)
        precondition(bridge.status=="Stone settling…")
        for i in 0..<6 {bridge.consume(view(true),now:1.5+Double(i)*0.25)}
        log.flush();timing.flush()
        let timingFile=try FileManager.default.contentsOfDirectory(at:timing.directory,includingPropertiesForKeys:nil).first!
        let timingText=try String(contentsOf:timingFile,encoding:.utf8)
        precondition(!timingText.contains("SECRET-MUST-NOT-APPEAR"))
        let timingRows=try timingText.split(separator:"\n").map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        for phase in ["camera_candidate_seen","first_clear_candidate","move_request_written"] {
            precondition(timingRows.filter{$0["event"] as? String==phase}.count==1,"Missing or duplicated timing phase: \(phase)")
        }
        let dispatch=timingRows.first{$0["event"] as? String=="move_request_written"}!
        let evidence=dispatch["submissionEvidence"] as! [String:Any]
        let confirmation=dispatch["confirmationEvidence"] as! [String:Any]
        precondition(evidence["confidence"] as? Double==1 && evidence["manualCorrection"] as? Bool==false)
        precondition(evidence["assignmentOffset"] is NSNull)
        precondition(confirmation["minimumConfidence"] as? Double==1)
        precondition((confirmation["scoredWitnesses"] as? Int ?? 0)>=4)
        precondition(confirmation["scoredWitnesses"] as? Int==confirmation["clearWitnesses"] as? Int)
        let text=try String(contentsOf:url,encoding:.utf8)
        precondition(!text.contains("SECRET-MUST-NOT-APPEAR") && !text.contains("987654321"))
        let entries=try text.split(separator:"\n").map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        precondition(entries.count==9 && entries[0]["board"] as? [String]==board)
        precondition(entries[2]["uncertain"] as? [Int]==[80])
        precondition(entries[2]["confirmation"] as? String=="Collecting local new-stone evidence")
        precondition(entries.filter{$0["confirmation"] as? String=="Move request written"}.count==1)
        precondition(FileManager.default.fileExists(atPath:moveURL.path));try FileManager.default.removeItem(at:moveURL)
        // Distinct per-intersection scores catch incorrect raw/display indexing.
        // Manual provenance and geometric evidence must follow the rotated move.
        for turn in 0..<4 {
            let dir=directory.appendingPathComponent("evidence-rotation-\(turn)")
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:state).write(to:dir.appendingPathComponent("state.json"))
            let journal=PhysicalMoveTiming(directory:dir.appendingPathComponent("timings"))
            let rotated=PhysicalOnlineBoard(directory:dir,moveTiming:journal,announceOpponent:{},announceCorrection:{})
            rotated.enabled=true
            rotated.consume(view(),now:1,quarterTurns:turn)
            var stone=BoardObservation(readings:(0..<81).map {IntersectionReading(row:$0/9,col:$0%9,
                occupancy:$0==10 ? .black:.empty,confidence:$0==10 ? 0.91:1,delta:0)},size:9)
            stone.manualPoints=[10]
            stone.footprints=[.init(row:1,col:1,center:.init(x:1.12,y:1.04),radiusCol:0.45,radiusRow:0.45,quality:0.95)]
            for i in 0..<4 {rotated.consume(stone,now:1.2+Double(i)*0.4,quarterTurns:turn)}
            journal.flush()
            let file=try FileManager.default.contentsOfDirectory(at:journal.directory,includingPropertiesForKeys:nil)[0]
            let rows=try String(contentsOf:file,encoding:.utf8).split(separator:"\n").map{
                try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
            }
            let sent=rows.first{$0["event"] as? String=="move_request_written"}!
            precondition(sent["point"] as? Int==PhysicalMoveInference.displayedPoint(row:1,col:1,size:9,quarterTurns:turn))
            let evidence=sent["submissionEvidence"] as! [String:Any]
            precondition(evidence["confidence"] as? Double==0.91 && evidence["manualCorrection"] as? Bool==true)
            precondition(abs((evidence["assignmentOffset"] as! Double)-0.12)<0.00001)
            precondition(rotated.timingStatistics?.contains("1 moves sent") == true)
        }
        let rotation=directory.appendingPathComponent("rotation.jsonl")
        let bounded=PhysicalOnlineDecisionLog(url:rotation,maximumBytes:100)
        for i in 0..<20 {bounded.append(["index":i,"event":"rotation test"])}
        bounded.flush()
        for path in [rotation,rotation.deletingPathExtension().appendingPathExtension("previous.jsonl")] {
            let data=try Data(contentsOf:path);precondition(data.count<=100)
            for line in String(decoding:data,as:UTF8.self).split(separator:"\n") {_ = try JSONSerialization.jsonObject(with:Data(line.utf8))}
        }
        print("Decision history tests passed: uncertainty, evidence, dispatch, credential exclusion and bounded rotation")
    }

    @MainActor static func captureTests(directory:URL) throws {
        let n=9
        func empty()->[String] { Array(repeating:"empty",count:n*n) }
        // Two-stone white group on the upper edge; final liberty is at (2,1).
        var base=empty()
        for p in [1,2] { base[p]="white" }
        for p in [0,3,10] { base[p]="black" }
        let point=11
        for removed in [[],[1],[2],[1,2]] {
            var observed=base; observed[point]="black"
            for p in removed { observed[p]="empty" }
            precondition(PhysicalMoveInference.candidate(board:base,observed:observed,size:n,color:"black")==point,"Capture removal order must not matter")
        }
        var cross=empty()
        for p in [31,39,41,49] {cross[p]="white"}
        for p in [22,30,32,38,42,48,50,58] {cross[p]="black"}
        for mask in 0..<16 {
            var observed=cross; observed[40]="black"
            for (bit,p) in [31,39,41,49].enumerated() where mask & (1<<bit) != 0 {observed[p]="empty"}
            precondition(PhysicalMoveInference.candidate(board:cross,observed:observed,size:n,color:"black")==40,"Multiple captured groups and every removal subset must work")
        }
        var unrelated=base; unrelated[point]="black"; unrelated[0]="empty"
        precondition(PhysicalMoveInference.candidate(board:base,observed:unrelated,size:n,color:"black")==nil,"Unrelated removal must block")
        var extra=base; extra[point]="black"; extra[80]="black"
        precondition(PhysicalMoveInference.candidate(board:base,observed:extra,size:n,color:"black")==nil,"Two additions must block")
        var suicide=empty(); for p in [1,9] {suicide[p]="white"}
        var dead=suicide;dead[0]="black"
        precondition(PhysicalMoveInference.candidate(board:suicide,observed:dead,size:n,color:"black")==nil,"Suicide must block")
        // Black and white, corners and board sizes exercise edge adjacency.
        for size in [9,13,19] {
            for color in ["black","white"] {
                let other=color=="black" ? "white":"black"
                for corner in [0,size-1,size*(size-1),size*size-1] {
                    let horizontal=corner%size==0 ? corner+1:corner-1
                    let vertical=corner/size==0 ? corner+size:corner-size
                    let diagonal=horizontal+(corner/size==0 ? size:-size)
                    var b=Array(repeating:"empty",count:size*size)
                    b[corner]=other;b[horizontal]=color
                    var o=b;o[vertical]=color;o[corner]="empty"
                    precondition(PhysicalMoveInference.candidate(board:b,observed:o,size:size,color:color)==vertical)
                    o[diagonal]=other
                    precondition(PhysicalMoveInference.candidate(board:b,observed:o,size:size,color:color)==nil)
                }
            }
        }
        // End-to-end bridge: remove half the capture while the move settles,
        // then remove the rest. The candidate keeps its stability timer.
        let state:[String:Any]=["token":"capture","game":55,"version":8,"size":n,"cells":base,"ready":true,"myTurn":true,"color":"black","time":Date().timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
        let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{});bridge.enabled=true
        func view(_ b:[String])->BoardObservation {
            BoardObservation(readings:b.indices.map {IntersectionReading(row:$0/n,col:$0%n,occupancy:Occupancy(rawValue:b[$0])!,confidence:1,delta:0)},size:n)
        }
        bridge.consume(view(base),now:1)
        var physical=base;physical[point]="black"
        for i in 0..<6 {
            if i==1 {physical[1]="empty"}; if i==2 {physical[2]="empty"}
            bridge.consume(view(physical),now:1.1+Double(i)*0.25)
            precondition(bridge.placementIssue==nil,"Natural capture removal must not trigger placement warnings")
        }
        let moveURL=directory.appendingPathComponent("move.json")
        let request=try JSONSerialization.jsonObject(with:Data(contentsOf:moveURL)) as! [String:Any]
        precondition(request["x"] as? Int==2 && request["y"] as? Int==1)
        try FileManager.default.removeItem(at:moveURL)
        for i in 0..<5 {bridge.consume(view(physical),now:3+Double(i)*0.25)}
        precondition(!FileManager.default.fileExists(atPath:moveURL.path))
        // Server acknowledgment changes turn and resets synchronization.
        var acknowledged=base;acknowledged[point]="black";acknowledged[1]="empty";acknowledged[2]="empty"
        var ack=state;ack["version"]=9;ack["cells"]=acknowledged;ack["myTurn"]=false
        try JSONSerialization.data(withJSONObject:ack).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
        bridge.consume(view(acknowledged),now:5)
        precondition(bridge.status=="Waiting for your opponent.")
        for i in 0..<6 {bridge.consume(view(physical),now:5.1+Double(i)*0.25)}
        precondition(!FileManager.default.fileExists(atPath:moveURL.path),"Acknowledged capture must not resend")
        // An unclear frame must not itself send; the candidate still needs a full second of evidence.
        ack["version"]=10;ack["myTurn"]=true
        try JSONSerialization.data(withJSONObject:ack).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
        bridge.consume(view(acknowledged),now:7)
        var next=acknowledged;next[80]="black"
        bridge.consume(view(next),now:7.1);bridge.consume(view(next),now:7.4)
        var uncertain=next;uncertain[79]="uncertain"
        bridge.consume(view(uncertain),now:7.5)
        bridge.consume(view(next),now:7.6);bridge.consume(view(next),now:7.9)
        precondition(!FileManager.default.fileExists(atPath:moveURL.path),"One second of candidate evidence is still required")
        for i in 0..<5 {bridge.consume(view(next),now:8.1+Double(i)*0.25)}
        precondition(FileManager.default.fileExists(atPath:moveURL.path),"Clear stable view can resume after uncertainty")
        try FileManager.default.removeItem(at:moveURL)
        print("Capture tests passed: partial/full removals, both colors, all corners, all sizes, suicide, unrelated changes, stable single dispatch")
    }

    @MainActor static func differentialTests() {
        var seed:UInt64=0x51473419
        func random(_ limit:Int)->Int {seed=seed &* 6364136223846793005 &+ 1;return Int((seed>>32)%UInt64(limit))}
        var count=0
        for size in [9,13,19] {
            for _ in 0..<100 {
                let color:Stone=random(2)==0 ? .black:.white
                var setup=[BoardPosition:Stone]()
                for row in 0..<size {for col in 0..<size {
                    let value=random(5)
                    if value<3 {setup[BoardPosition(row,col)]=value==0 ? color:color.opponent}
                }}
                let point=random(size*size);setup.removeValue(forKey:BoardPosition(point/size,point%size))
                let engine=SGFPlayer()
                engine.loadOnline(size:size,setup:setup,nextPlayer:color,stateVersion:1)
                let before=engine.board.grid.flatMap{$0.map{$0?.rawValue ?? "empty"}}
                engine.playMoveOptimistically(color:color,x:point%size,y:point/size)
                let after=engine.board.grid.flatMap{$0.map{$0?.rawValue ?? "empty"}}
                let expected=after[point]==color.rawValue ? point:nil
                precondition(PhysicalMoveInference.candidate(board:before,observed:after,size:size,color:color.rawValue)==expected,"Must agree with shared Go engine")
                if expected != nil {
                    var partial=after
                    for p in before.indices where before[p]==color.opponent.rawValue && after[p]=="empty" {
                        if random(2)==0 {partial[p]=before[p]}
                    }
                    precondition(PhysicalMoveInference.candidate(board:before,observed:partial,size:size,color:color.rawValue)==point)
                }
                count += 1
            }
        }
        print("Differential tests passed: \(count) positions compared with the shared Go engine, including partial removals")
    }

    @MainActor static func orientationTests(directory:URL) throws {
        for n in [9,13,19] {
            for turns in 0..<4 {
                var mapped=Set<Int>()
                for row in 0..<n {for col in 0..<n {
                    let p=PhysicalMoveInference.displayedPoint(row:row,col:col,size:n,quarterTurns:turns)
                    precondition((0..<n*n).contains(p)); mapped.insert(p)
                    let back=PhysicalMoveInference.displayedPoint(row:p/n,col:p%n,size:n,quarterTurns:4-turns)
                    precondition(back==row*n+col)
                }}
                precondition(mapped.count==n*n)
                let board=Array(repeating:"empty",count:n*n)
                let state:[String:Any]=["token":"orientation","game":77,"version":1,"size":n,"cells":board,"ready":true,"myTurn":true,"color":"black","time":Date().timeIntervalSince1970]
                try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
                let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{});bridge.enabled=true
                let rawRow=n-4,rawCol=n-4
                func view(_ occupied:Bool)->BoardObservation {
                    BoardObservation(readings:(0..<n*n).map{IntersectionReading(row:$0/n,col:$0%n,occupancy:occupied && $0==rawRow*n+rawCol ? .black:.empty,confidence:1,delta:0)},size:n)
                }
                bridge.consume(view(false),now:1,quarterTurns:turns)
                for i in 0..<6 {bridge.consume(view(true),now:1.1+Double(i)*0.25,quarterTurns:turns)}
                let url=directory.appendingPathComponent("move.json")
                let request=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
                let expected=PhysicalMoveInference.displayedPoint(row:rawRow,col:rawCol,size:n,quarterTurns:turns)
                precondition(request["x"] as? Int==expected%n && request["y"] as? Int==expected/n)
                if turns==3 {precondition(expected%n==n-4 && expected/n==3,"Upper right in rotated Physical Go must stay upper right online")}
                try FileManager.default.removeItem(at:url)
                var ack=state, acknowledged=board
                acknowledged[expected]="black";ack["cells"]=acknowledged;ack["version"]=2;ack["myTurn"]=false
                try JSONSerialization.data(withJSONObject:ack).write(to:directory.appendingPathComponent("state.json"),options:.atomic)
                bridge.consume(view(true),now:2.7,quarterTurns:turns)
                precondition(bridge.status=="Waiting for your opponent.","Server board must match the rotated camera observation")
                precondition(bridge.cells[expected]=="black")
                // A view rotation must require matching the new orientation first.
                for i in 0..<6 {bridge.consume(view(true),now:3+Double(i)*0.25,quarterTurns:(turns+1)%4)}
                precondition(!FileManager.default.fileExists(atPath:url.path))
            }
        }
        print("Orientation tests passed: every intersection, four rotations, three sizes, rotated requests, rotation resynchronization")
    }

}
