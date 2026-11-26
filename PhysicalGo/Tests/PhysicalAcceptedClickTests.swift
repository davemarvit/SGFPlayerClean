import Foundation

/// Synthetic status-file conversations only: never constructs an audio backend,
/// acquires a camera, starts the app, or contacts a controller.
@main struct PhysicalAcceptedClickTests {
    @MainActor final class Fixture {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("accepted-click-"+UUID().uuidString)
        let wall=1000.0,now=100.0
        let standby:Bool
        var cues=[String]()
        init(standby:Bool=false) {self.standby=standby}
        lazy var laser:PhysicalLaserGuidance = {
            let value=PhysicalLaserGuidance(directory:directory,automatic:false,wallTime:{1000},uptime:{100})
            value.onTargetIndicated={ [weak self] in self?.cues.append($0.id) }
            return value
        }()
        func target(session:UUID=UUID(),move:Int=1)->PhysicalLaserGuidance.Target {
            .init(source:"ai",session:session,moveNumber:move,size:19,row:9,col:9,black:true,decisionReceivedAtUnix:wall)
        }
        func status(state:String="adequate",sequence:Int?=nil,producer:UUID?=nil,
                    age:Double=0,on:Bool=true,confirmed:Bool?=true,mode:String="hardware",wrongSession:Bool=false,proofAge:Double=0,omitProof:Bool=false,wrongProofTarget:Bool=false,proofOverride:[String:Any]=[:])throws {
            let request=try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,
                from:Data(contentsOf:directory.appendingPathComponent("request.json")))
            let off=state=="off",dark=state=="holding"
            let mark=PhysicalLaserGuidance.EvidenceAfter(streamEpoch:laser.frames.streamEpoch,frameID:99,timestampSource:"cameraPresentation")
            var value=PhysicalLaserGuidance.DriverStatus(schemaVersion:request.schemaVersion,producer:producer ?? laser.producer,
                sequence:sequence ?? laser.sequence,updatedAtUnix:wall-age,mode:mode,state:state,
                laserOn:on,offSinceUnix:off || !standby && !on ? wall-1:nil,detail:state,
                evidenceAfter:standby && off ? mark:nil,setupId:standby ? "synthetic-setup":nil,
                illuminationConfirmed:confirmed,capabilities:["stoneCenteringWiggle","capturedStoneIndication"]+(standby ? ["darkMotorStandbyV1"]:[]),
                playSession:wrongSession ? .init(source:"ai",session:UUID(),size:19):request.playSession,cameraContext:request.cameraContext,streamEpoch:request.streamEpoch,
                motorsHeld:standby ? !off:nil,motorBusPowered:standby ? !off:nil,
                beamOffSinceUnix:standby && dark ? wall-1:nil,darkEvidenceAfter:standby && dark ? mark:nil,
                thermal:standby ? .init(policy:"warm_hold",sampleSequence:1,receivedAtUnix:wall,
                    sampleAgeUpperMs:50,baseC:20,tiltC:21,unavailableReason:off ? "power_off":nil):nil)
            value.thermal?.controllerSession="ABCDEF01";value.thermal?.controllerGeneration=1
            if !omitProof,let target=request.target {
                var proofTarget=target
                if wrongProofTarget {proofTarget=PhysicalLaserGuidance.Target(source:target.source,session:target.session,
                    moveNumber:target.moveNumber,size:target.size,row:target.row,col:target.col+1,
                    black:target.black,decisionReceivedAtUnix:target.decisionReceivedAtUnix)}
                value.opticalEvidence = .init(policy:"captured_optical_result_v1",producer:laser.producer,
                    requestSequence:request.sequence,target:proofTarget,cameraContext:request.cameraContext!,
                    streamEpoch:request.streamEpoch!,frameID:100,capturedAtUptime:now-proofAge,
                    arrivedAtUptime:now-proofAge,capturedAtUnix:wall-proofAge,publishedAtUnix:wall-proofAge,
                    expiresAtUptime:now-proofAge+0.6,expiresAtUnix:wall-proofAge+0.6,
                    controllerSession:"ABCDEF01",controllerGeneration:1)
            }
            if !proofOverride.isEmpty {
                var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any]
                var proof=json["opticalEvidence"] as! [String:Any]
                for (key,value) in proofOverride {proof[key]=value}
                json["opticalEvidence"]=proof
                value=try JSONDecoder().decode(PhysicalLaserGuidance.DriverStatus.self,from:JSONSerialization.data(withJSONObject:json))
            }
            try JSONEncoder().encode(value).write(to:directory.appendingPathComponent("status.json"),options:.atomic)
            laser.tick()
        }
        func admit(_ target:PhysicalLaserGuidance.Target)throws {
            if standby {
                laser.setPlaySession(.init(source:target.source,session:target.session,size:target.size))
                laser.setStandbyEnabled(true)
            }
            laser.setTarget(target);laser.setEnabled(true)
            laser.noteFrame(.init(streamEpoch:laser.frames.streamEpoch,frameID:100,capturedAtUptime:now,
                arrivedAtUptime:now,capturedAtUnix:wall,timestampSource:"cameraPresentation",presentationSeconds:now))
            laser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"synthetic-camera")
            if standby {
                for _ in 0..<3 {try status(state:"off",on:false,confirmed:false)}
                try status(state:"holding",on:false,confirmed:false)
            } else {try status(state:"off",on:false,confirmed:false,mode:"simulation")}
            if target.purpose=="centering" {laser.verifyCenteringTarget(capturedAt:now,now:now)}
            else if target.purpose=="capture" {laser.verifyCaptureTarget(capturedAt:now,now:now)}
            else {laser.verifyEmptyTarget(capturedAt:now,now:now)}
            let request=try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,
                from:Data(contentsOf:directory.appendingPathComponent("request.json")))
            precondition(request.action=="point" && request.target==target,
                "Fixture must admit the target before testing accepted-target rejection")
            precondition(request.schemaVersion==(standby ? 2:1),"Wrong fixture wire schema")
        }
        func close() {try? FileManager.default.removeItem(at:directory)}
    }
    @MainActor static func main()throws {
        var checks=0
        func check(_ condition:Bool,_ message:String) {
            precondition(condition,message);checks+=1
        }
        do {
            let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/TemporalEvidence/adequate-heartbeat-stale.json")
            let status=try JSONDecoder().decode(PhysicalLaserGuidance.DriverStatus.self,from:Data(contentsOf:url))
            let proof=status.opticalEvidence!
            check(status.updatedAtUnix==1001.1 && proof.expiresAtUnix==1000.6,"Paired actual Python heartbeat fixture must retain old source deadline")
            check(!proof.current(now:1001.1,wall:1001.1,producer:status.producer,sequence:status.sequence,
                target:proof.target,context:status.cameraContext,epoch:status.streamEpoch!,thermal:status.thermal,schema:2),
                "Actual Python heartbeat cannot rejuvenate optical source proof")
        }
        // Real status JSON decoding must use the source age, not refreshed
        // driver liveness. Historical adequate does not darken or fault.
        for rejection in ["expired","future","missing","wrong-target"] {
            let f=Fixture(standby:true);defer {f.close()}
            let target=f.target();try f.admit(target)
            try f.status(proofAge:rejection=="expired" ? 0.601:rejection=="future" ? -0.001:0,
                         omitProof:rejection=="missing",wrongProofTarget:rejection=="wrong-target")
            check(f.cues.isEmpty,"Invalid source proof announced a fresh cue: \(rejection)")
            check(!f.laser.holdingInterrupted,"Historical optical expiry must not manufacture a controller fault")
            try f.status(proofAge:0.1)
            check(f.cues==[target.id],"Expired result must not consume a later genuine fresh cue")
        }
        let proofOverrides:[[String:Any]] = [
            ["capturedAtUptime":99.399,"expiresAtUptime":99.999],
            ["arrivedAtUptime":99.399,"expiresAtUptime":99.999],
            ["capturedAtUnix":999.399,"expiresAtUnix":999.999],
            ["publishedAtUnix":999.399,"expiresAtUnix":999.999],
            ["requestSequence":-1],["cameraContext":"another-camera"],
            ["streamEpoch":UUID().uuidString],["controllerSession":"ABCDEF02"],
            ["controllerGeneration":2],["expiresAtUnix":1001.0]
        ]
        for override in proofOverrides {
            let f=Fixture(standby:true);defer {f.close()}
            try f.admit(f.target());try f.status(proofOverride:override)
            check(f.cues.isEmpty,"Actual JSON decode admitted changed source age/scope/deadline: \(override)")
            check(!f.laser.holdingInterrupted,"Optical source rejection must not create controller fault")
        }
        // A delayed accepted-target acknowledgement cannot revive a cancelled move.
        do {
            let f=Fixture();defer {f.close()}
            let first=f.target();try f.admit(first)
            let oldSequence=f.laser.sequence
            f.laser.setTarget(nil)
            try f.status(sequence:oldSequence)
            try f.status() // Even a forged current revision has no active target.
            check(f.cues.isEmpty,"Cancelled move announced late illumination")
        }
        // Supersession invalidates the old revision even if it arrives after
        // fresh dark evidence has admitted the replacement.
        do {
            let f=Fixture();defer {f.close()}
            let first=f.target();try f.admit(first)
            let oldSequence=f.laser.sequence
            let next=f.target(session:first.session,move:2);try f.admit(next)
            try f.status(sequence:oldSequence)
            check(f.cues.isEmpty,"Superseded target's light announced replacement")
            try f.status(state:"approaching")
            check(f.cues.isEmpty,"Acquisition flash announced replacement before optical acceptance")
            try f.status(state:"refining")
            check(f.cues.isEmpty,"Refining light announced replacement before optical acceptance")
            try f.status()
            check(f.cues==[next.id],"Adequate confirmed replacement did not receive cue")
            try f.status()
            check(f.cues==[next.id],"Replacement settling replayed accepted-target cue")
        }
        // Revisions are scoped to the producing process and a fresh timestamp.
        // Use independent fixtures: rejected transport evidence may latch a
        // recovery requirement, which is separate from audio identity.
        for rejection in ["producer","stale","future","unconfirmed","dark","transition","simulation"] {
            let f=Fixture();defer {f.close()}
            try f.admit(f.target())
            switch rejection {
            case "producer":try f.status(producer:UUID())
            case "stale":try f.status(age:0.751)
            case "future":try f.status(age: -0.001)
            case "unconfirmed":try f.status(confirmed:nil)
            case "dark":try f.status(on:false)
            case "transition":try f.status(state:"transitioning",confirmed:false)
            default:try f.status(mode:"simulation")
            }
            check(f.cues.isEmpty,"Rejected \(rejection) status announced accepted indication")
        }
        // Move identity, rather than intersection or revision, deduplicates
        // re-aiming. A new move at the same intersection still receives a cue.
        do {
            let f=Fixture();defer {f.close()}
            let first=f.target();try f.admit(first);try f.status()
            f.laser.suppress("hand_entered_board");f.laser.setTarget(nil)
            try f.admit(first);try f.status()
            check(f.cues==[first.id],"Hand recovery/re-aim replayed the same move cue")
            let next=f.target(session:first.session,move:2);try f.admit(next);try f.status()
            check(f.cues==[first.id,next.id],"New move at same intersection was incorrectly deduplicated")
            let newGame=f.target(move:1);try f.admit(newGame);try f.status()
            check(f.cues==[first.id,next.id,newGame.id],"New session's first move was incorrectly deduplicated")
        }
        // Disabling before the first receipt must remain silent even when the
        // controller reports that the old point request illuminated.
        do {
            let f=Fixture();defer {f.close()}
            try f.admit(f.target());let oldSequence=f.laser.sequence
            f.laser.setEnabled(false);try f.status(sequence:oldSequence)
            check(f.cues.isEmpty,"Disabled guidance announced a late accepted-target receipt")
        }
        // Exercise the installed schema2 holding contract as well as the legacy
        // wire mode above: held darkness is not accepted indication, and cancellation
        // invalidates a point receipt while the motor session remains monitored.
        do {
            let f=Fixture(standby:true);defer {f.close()}
            let first=f.target();try f.admit(first)
            check(f.cues.isEmpty,"Holding/arming announced accepted indication")
            try f.status(state:"approaching")
            check(f.cues.isEmpty,"Schema2 acquisition light announced before optical acceptance")
            try f.status(state:"refining")
            check(f.cues.isEmpty,"Schema2 refining light announced before optical acceptance")
            try f.status()
            check(f.cues==[first.id],"Schema2 adequate confirmed indication did not receive cue")
            try f.status()
            check(f.cues==[first.id],"Schema2 settling replayed move cue")
            let second=f.target(session:first.session,move:2);try f.admit(second)
            let secondSequence=f.laser.sequence
            f.laser.setTarget(nil);try f.status(sequence:secondSequence)
            check(f.cues==[first.id],"Schema2 cancelled target announced late accepted indication")
        }
        // A current sequence cannot borrow another game session's optical proof.
        do {
            let f=Fixture(standby:true);defer {f.close()}
            try f.admit(f.target());try f.status(wrongSession:true)
            check(f.cues.isEmpty,"Wrong-session adequate receipt played accepted-target cue")
        }
        // These intents have dedicated evidence/capability gates but must never
        // consume or play the ordinary opponent-move cue.
        for purpose in ["centering","capture"] {
            let f=Fixture(standby:true);defer {f.close()}
            var special=f.target();special.purpose=purpose
            if purpose=="centering" {special.stoneCenter = .init(x:9.25,y:9)}
            try f.admit(special);try f.status()
            check(f.cues.isEmpty,"\(purpose) adequate receipt played opponent-move cue")
        }
        // An unsuccessful acquisition does not consume the move's eventual cue.
        do {
            let f=Fixture(standby:true);defer {f.close()}
            let first=f.target();try f.admit(first);try f.status(state:"approaching")
            f.laser.suppress("hand_entered_board");f.laser.setTarget(nil)
            try f.admit(first);try f.status()
            check(f.cues==[first.id],"Retry after unaccepted acquisition lost the move cue")
            f.laser.showAgain();try f.admit(first);try f.status()
            check(f.cues==[first.id],"Explicit retry after acceptance repeated the move cue")
        }
        print("PASS: \(checks) accepted-target identity, cancellation and receipt checks; no audio played")
    }
}
