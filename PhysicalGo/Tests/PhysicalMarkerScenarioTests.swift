// Combined marker/controller/held-dark contract tests. No devices or camera.
import Foundation

@MainActor private final class MarkerScenario {
    let folder: URL
    let laser: PhysicalLaserGuidance
    let ai: PhysicalAI
    final class Clock {var now=100.0;var wall=1000.0;var frameID=10}
    let clock: Clock
    var cues=0
    init(root:URL,name:String,moves:[Int?],humanBlack:Bool,capture:Bool=false) throws {
        folder=root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var settings=PhysicalAISettings();settings.size=9;settings.humanBlack=humanBlack
        let saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,
            moves:moves.map {.init(point:$0,decisionReceivedAtUnix:999)},
            pendingPlacement:capture,pendingCaptureCleanup:capture,
            captureIndication:capture ? .init(moveNumber:moves.count,acceptedAtUnix:999):nil,
            timing:PhysicalAITiming(blackToPlay:humanBlack))
        try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
        let c=Clock();clock=c
        laser=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,
            wallTime:{c.wall},uptime:{c.now})
        ai=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:laser,
            uptime:{c.now},wallTime:{c.wall})
        laser.onTargetIndicated={[weak self] _ in self?.cues+=1}
        ai.resume();laser.setStandbyEnabled(true);laser.setEnabled(true)
        camera(hand:false)
        try acknowledgeDark()
    }
    func request() throws -> PhysicalLaserGuidance.Request {
        try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,
            from:Data(contentsOf:laser.directory.appendingPathComponent("request.json")))
    }
    func camera(hand:Bool) {
        clock.now+=0.25;clock.wall+=0.25;clock.frameID+=1
        laser.noteFrame(.init(streamEpoch:laser.frames.streamEpoch,frameID:UInt64(clock.frameID),
            capturedAtUptime:clock.now,arrivedAtUptime:clock.now,capturedAtUnix:clock.wall,
            timestampSource:"cameraPresentation",presentationSeconds:clock.now))
        laser.observeCamera(hand:hand,valid:true,capturedAt:clock.now,now:clock.now,context:"marker-grid")
    }
    func receipt(lit:Bool=false) throws {
        let r=try request(),off=r.action=="off"
        let state=off ? "off":lit ? "adequate":"holding"
        let mark=PhysicalLaserGuidance.EvidenceAfter(streamEpoch:laser.frames.streamEpoch,
            frameID:UInt64(clock.frameID-1),timestampSource:"cameraPresentation")
        var s=PhysicalLaserGuidance.DriverStatus(schemaVersion:r.schemaVersion,producer:r.producer,
            sequence:r.sequence,updatedAtUnix:clock.wall,mode:"hardware",state:state,
            laserOn:lit && !off,offSinceUnix:off ? clock.wall-1:nil,detail:state,
            evidenceAfter:off ? mark:nil,setupId:"marker-setup",illuminationConfirmed:lit && !off,
            capabilities:["darkMotorStandbyV1","stoneCenteringWiggle","capturedStoneIndication"],
            playSession:r.playSession,cameraContext:r.cameraContext,streamEpoch:r.streamEpoch,
            motorsHeld:!off,motorBusPowered:!off,beamOffSinceUnix:off || lit ? nil:clock.wall-1,
            darkEvidenceAfter:off || lit ? nil:mark,
            thermal:.init(policy:"warm_hold",sampleSequence:clock.frameID,receivedAtUnix:clock.wall,
                sampleAgeUpperMs:50,baseC:20,tiltC:21,maxBaseC:20,maxTiltC:21,
                unavailableReason:off ? "power_off":nil))
        s.thermal?.controllerSession="ABCDEF01";s.thermal?.controllerGeneration=1
        if let target=r.target,let context=r.cameraContext,let epoch=r.streamEpoch {
            s.opticalEvidence = .init(policy:"captured_optical_result_v1",producer:r.producer,
                requestSequence:r.sequence,target:target,cameraContext:context,streamEpoch:epoch,
                frameID:UInt64(clock.frameID),capturedAtUptime:clock.now,arrivedAtUptime:clock.now,
                capturedAtUnix:clock.wall,publishedAtUnix:clock.wall,expiresAtUptime:clock.now+0.6,
                expiresAtUnix:clock.wall+0.6,controllerSession:"ABCDEF01",controllerGeneration:1)
        }
        try JSONEncoder().encode(s).write(to:laser.directory.appendingPathComponent("status.json"),options:.atomic)
        laser.tick()
    }
    // Model each real full-OFF or warm-dark barrier. New app revisions get their
    // own receipt; no old receipt is relabeled to authorize a replacement target.
    func acknowledgeDark() throws {
        for _ in 0..<6 {
            let before=try request();try receipt()
            let after=try request()
            if before.sequence==after.sequence && before.schemaVersion==after.schemaVersion {return}
        }
        preconditionFailure("Dark handshakes did not settle")
    }
    func feed(_ cells:[String],hand:Bool=false,count:Int=1,dark:Bool=true,
              centers:[StoneCenteringEvidence]=[]) throws {
        for _ in 0..<count {
            camera(hand:hand)
            if dark {try acknowledgeDark()}
            var observation=BoardObservation(readings:cells.enumerated().map {
                .init(row:$0.offset/9,col:$0.offset%9,occupancy:Occupancy(rawValue:$0.element)!,confidence:$0.element=="uncertain" ? 0:1,delta:0)
            },size:9)
            observation.capturedAt=clock.now;observation.handObstructed=hand
            observation.centeringEvidence=centers
            ai.consume(observation,now:clock.now)
        }
    }
}

@main struct PhysicalMarkerScenarioTests {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("marker-scenarios-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        var checks=0
        func check(_ value:Bool,_ reason:String) {precondition(value,reason);checks+=1}

        // Color-swapped legal histories: an initial black pass makes the same
        // corner capture belong to White without inventing an edited board.
        for capturingBlack in [true,false] {
            let moves:[Int?]=capturingBlack ? [1,0,10,9,18]:[nil,1,0,10,9,18]
            let h=try MarkerScenario(root:root,name:capturingBlack ? "white-prisoners":"black-prisoners",
                moves:moves,humanBlack:!capturingBlack,capture:true)
            let prisoner=capturingBlack ? "white":"black",played=capturingBlack ? "black":"white"
            var physical=h.ai.cells;physical[0]=prisoner;physical[9]=prisoner;physical[18]="empty"
            h.ai.centeringEnabled=true
            let irrelevant=StoneCenteringEvidence(color:.black,shape:.init(row:4,col:4,
                center:.init(x:4.5,y:4),radiusCol:0.5,radiusRow:0.5,quality:0.98))
            try h.feed(physical,count:4,centers:[irrelevant])
            check(h.ai.laser.target?.purpose==nil && h.ai.guidanceTarget?.row==2,"AI destination precedes prisoner and centering markers")
            check(h.ai.centeringStone==nil && h.ai.remainingCapturedStones==2,"Capture context suppresses unrelated centering")
            check(try h.request().schemaVersion==2,"Combined capture test actually uses monitored schema2")
            try h.receipt(lit:true)
            check(h.cues==1,"Only ordinary AI destination announces the move")

            physical[18]=played
            try h.feed(physical,hand:true)
            check(try h.request().action=="standby" && h.request().retainOnly==true,"Hand extinguishes indication into retain-only standby")
            try h.feed(physical,count:5)
            check(h.ai.captureGuidancePoint==0 && h.ai.laser.target?.purpose=="capture","Held-dark placement evidence switches to a legal prisoner")
            check(h.ai.laser.target?.black == !capturingBlack,"Capture marker preserves actual prisoner color")
            check(h.ai.snapshot!.pendingPlacement && h.ai.snapshot!.moves.count==moves.count,"Marker selection cannot finish the game transition")
            check(h.ai.clockPausedForCaptureCleanup && h.ai.timing.anchor==nil,"Multiple-prisoner clock remains paused")
            try h.acknowledgeDark();try h.receipt(lit:true)
            check(h.cues==1,"Capture illumination is silent")

            // A positive raw disappearance under illumination can request
            // darkness, but cannot enter the removal ledger by itself.
            var suspected=physical;suspected[0]="empty"
            try h.feed(suspected,dark:false)
            check(h.ai.remainingCapturedStones==2 && h.ai.snapshot!.captureIndication!.removed.isEmpty,"Lit disappearance alone never removes a prisoner")
            try h.feed(physical,hand:true)
            try h.feed(physical,count:5)
            check(h.ai.remainingCapturedStones==2 && h.ai.captureGuidancePoint==0,"A hand visit without removal retains the same legal prisoner")

            physical[9]="empty" // deliberately remove the non-indicated stone first
            try h.feed(physical,hand:true);try h.feed(physical,count:5)
            check(h.ai.remainingCapturedStones==1 && h.ai.captureGuidancePoint==0,"Out-of-order cleanup selects the actual remainder")
            check(h.ai.snapshot!.captureIndication!.removed==[9],"Only positively empty prisoner is persisted")
            check(h.ai.timing.anchor==nil && h.ai.snapshot!.moves.count==moves.count,"Partial cleanup neither resumes clock nor creates a reply")

            var uncertain=physical;uncertain[0]="uncertain"
            try h.feed(uncertain,hand:true)
            try h.feed(uncertain,count:4)
            check(h.ai.remainingCapturedStones==1,"Unknown final prisoner is not considered removed")
            check(try h.request().action != "point","Unknown prisoner occupancy cannot authorize a capture beam")
            try h.feed(h.ai.cells,hand:true);try h.feed(h.ai.cells,count:5)
            check(h.ai.snapshot!.captureIndication==nil && !h.ai.snapshot!.pendingPlacement,"Full held-dark board agreement closes capture")
            check(h.ai.phase == .human && h.ai.timing.anchor != nil,"Complete cleanup restores the existing next-player clock")
            check(h.cues==1,"Capture cleanup never repeats the AI arrival cue")
            h.ai.pause()
        }

        let hint=try MarkerScenario(root:root,name:"two-ambiguous-disks",moves:[0,80],humanBlack:true)
        try hint.feed(hint.ai.cells,count:4)
        hint.ai.centeringEnabled=true
        let originalMoves=hint.ai.snapshot!.moves.count,originalAnchor=hint.ai.timing.anchor
        var uncertain=hint.ai.cells
        for p in [30,31,50,51] {uncertain[p]="uncertain"}
        let first=StoneCenteringEvidence(color:.black,shape:.init(row:3,col:3,
            center:.init(x:3.5,y:3),radiusCol:0.5,radiusRow:0.5,quality:0.98))
        let second=StoneCenteringEvidence(color:.white,shape:.init(row:5,col:5,
            center:.init(x:5.5,y:5),radiusCol:0.5,radiusRow:0.5,quality:0.98))
        try hint.feed(uncertain,count:5,centers:[first,second])
        check(hint.ai.centeringStone==first.shape.center && hint.laser.target?.black==true,"Two disks select one measured center deterministically")
        try hint.feed(uncertain,count:4,centers:[second,first])
        check(hint.laser.target?.stoneCenter==first.shape.center,"Reordered detections do not bounce the marker between disks")
        check(hint.ai.snapshot!.moves.count==originalMoves && hint.ai.timing.anchor==originalAnchor,"Ambiguous disks neither invent a move nor reset the clock")
        try hint.acknowledgeDark();try hint.receipt(lit:true)
        check(hint.cues==0,"Centering illumination never announces an AI move")
        try hint.feed(uncertain,hand:true,centers:[first,second])
        check(try hint.request().action=="standby" && hint.request().retainOnly==true,"Hand over ambiguous disk retains darkness only")
        var oneRemaining=hint.ai.cells;oneRemaining[50]="uncertain";oneRemaining[51]="uncertain"
        try hint.feed(oneRemaining,count:5,centers:[second])
        check(hint.laser.target?.stoneCenter==second.shape.center && hint.laser.target?.black==false,"Removing first disk transfers guidance to measured white disk")
        try hint.feed(hint.ai.cells,hand:true);try hint.feed(hint.ai.cells,count:5)
        check(hint.ai.centeringStone==nil && hint.laser.target==nil,"Removing ambiguous disks clears hints without a ghost target")
        check(hint.ai.snapshot!.moves.count==originalMoves && hint.cues==0,"Centering/removal never changes history or announces a move")
        hint.ai.pause()

        // Export optional throwaway physical setups using the real save/SGF
        // serializers. Nothing here reads or writes the live app's game folder.
        let exports=ProcessInfo.processInfo.environment["PHYSICAL_GO_MARKER_FIXTURES"].map {URL(fileURLWithPath:$0,isDirectory:true)}
        if let exports {try FileManager.default.createDirectory(at:exports,withIntermediateDirectories:true)}
        let letters=Array("ABCDEFGHJKLMNOPQRST")
        func coordinate(_ point:Int)->String {"\(letters[point%19])\(19-point/19)"}
        for multi in [false,true] {
            for capturingBlack in [true,false] {
                let name="\(multi ? "two":"one")-\(capturingBlack ? "white":"black")-prisoners"
                let base:[Int?]=multi ? [1,0,20,19,38]:[19,0,360,2,1]
                let moves:[Int?]=capturingBlack ? base:[nil]+base
                var settings=PhysicalAISettings();settings.size=19;settings.humanBlack = !capturingBlack;settings.fastTestMode=true
                let receiptTime=Date().timeIntervalSince1970
                let snapshot=PhysicalAI.Snapshot(id:UUID(),settings:settings,
                    moves:moves.map {.init(point:$0,decisionReceivedAtUnix:receiptTime)},
                    pendingPlacement:true,pendingCaptureCleanup:multi,
                    captureIndication:.init(moveNumber:moves.count,acceptedAtUnix:receiptTime),
                    timing:PhysicalAITiming(blackToPlay:!capturingBlack))
                let engine=SGFPlayer();engine.load(game:PhysicalAI.game(snapshot))
                for (index,point) in moves.enumerated() {
                    engine.seek(to:index)
                    if let point {check(engine.moveRejection(color:index%2==0 ? .black:.white,x:point%19,y:point/19)==nil,"Physical fixture contains only legal moves: \(name)")}
                }
                engine.seek(to:moves.count-1)
                let before=engine.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"}
                engine.seek(to:moves.count)
                let after=engine.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"}
                let prisoners=before.indices.filter{before[$0] != "empty" && after[$0]=="empty"}
                check(prisoners==(multi ? [0,19]:[0]),"Physical fixture captures exactly prescribed prisoners: \(name)")
                let data=try JSONEncoder().encode(snapshot)
                let gameFolder=root.appendingPathComponent(name)
                try FileManager.default.createDirectory(at:gameFolder,withIntermediateDirectories:true)
                try data.write(to:gameFolder.appendingPathComponent("current.json"))
                let fixtureLaser=PhysicalLaserGuidance(directory:gameFolder.appendingPathComponent("bridge"),automatic:false)
                let controller=PhysicalAI(directory:gameFolder,generate:{_,_ in "pass"},laser:fixtureLaser)
                check(controller.phase == .paused,"Physical capture fixture loads paused")
                controller.resume()
                check(controller.phase == .placing && (controller.timing.anchor==nil)==multi,"Single and multiple fixture clocks follow existing cleanup policy")
                controller.pause()
                if let exports {
                    let destination=exports.appendingPathComponent(name,isDirectory:true)
                    try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
                    try data.write(to:destination.appendingPathComponent("fixture.json"))
                    try PhysicalAI.sgf(snapshot).write(to:destination.appendingPathComponent("fixture.sgf"),atomically:true,encoding:.utf8)
                    func stones(_ board:[String])->[[String:String]] {
                        board.indices.filter{board[$0] != "empty"}.map{["coordinate":coordinate($0),"color":board[$0]]}
                    }
                    let manifest:[String:Any]=[
                        "name":name,"testOnly":true,"boardSize":19,"gameId":snapshot.id.uuidString,
                        "humanColor":capturingBlack ? "white":"black","aiColor":capturingBlack ? "black":"white",
                        "setupBeforeCapture":stones(before),"expectedAfterCleanup":stones(after),
                        "aiDestination":coordinate(moves.last!!),"prisoners":prisoners.map(coordinate),
                        "prisonerColor":capturingBlack ? "white":"black",
                        "clockPolicy":multi ? "Next-player clock remains paused until placement and every prisoner removal are confirmed.":"Next-player clock runs during AI placement and single-prisoner cleanup.",
                        "loading":"Back up the current game and clocks. Load this separate fixture paused, verify the listed physical setup, then Resume. It indicates an already selected legal AI move; no AI randomness or physical confirmation is bypassed.",
                        "moves":moves.enumerated().map {"\($0.offset%2==0 ? "B":"W"):\($0.element.map(coordinate) ?? "pass")"},
                        "source":"PhysicalMarkerScenarioTests; actual PhysicalAI save and SGF serializers; legal sequence replay checked"
                    ]
                    try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:destination.appendingPathComponent("setup.json"))
                }
            }
        }
        print("PASS \(checks) combined marker/held-dark/controller scenarios (real app types; no hardware)")
    }
}
