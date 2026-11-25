import Foundation

/// Synthetic status-file conversations only: never constructs an audio backend,
/// acquires a camera, starts the app, or contacts a controller.
@main struct PhysicalFirstLightIdentityTests {
    @MainActor final class Fixture {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("first-light-"+UUID().uuidString)
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
                    age:Double=0,on:Bool=true,confirmed:Bool?=true,mode:String="hardware")throws {
            let request=try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,
                from:Data(contentsOf:directory.appendingPathComponent("request.json")))
            let off=state=="off",dark=state=="holding"
            let mark=PhysicalLaserGuidance.EvidenceAfter(streamEpoch:laser.frames.streamEpoch,frameID:99,timestampSource:"cameraPresentation")
            let value=PhysicalLaserGuidance.DriverStatus(schemaVersion:request.schemaVersion,producer:producer ?? laser.producer,
                sequence:sequence ?? laser.sequence,updatedAtUnix:wall-age,mode:mode,state:state,
                laserOn:on,offSinceUnix:off || !standby && !on ? wall-1:nil,detail:state,
                evidenceAfter:standby && off ? mark:nil,setupId:standby ? "synthetic-setup":nil,
                illuminationConfirmed:confirmed,capabilities:standby ? ["darkMotorStandbyV1"]:nil,
                playSession:request.playSession,cameraContext:request.cameraContext,streamEpoch:request.streamEpoch,
                motorsHeld:standby ? !off:nil,motorBusPowered:standby ? !off:nil,
                beamOffSinceUnix:standby && dark ? wall-1:nil,darkEvidenceAfter:standby && dark ? mark:nil,
                thermal:standby ? .init(policy:"warm_hold",sampleSequence:1,receivedAtUnix:wall,
                    sampleAgeUpperMs:50,baseC:20,tiltC:21,unavailableReason:off ? "power_off":nil):nil)
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
            laser.verifyEmptyTarget(capturedAt:now,now:now)
            let request=try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,
                from:Data(contentsOf:directory.appendingPathComponent("request.json")))
            precondition(request.action=="point" && request.target==target,
                "Fixture must admit the target before testing first-light rejection")
            precondition(request.schemaVersion==(standby ? 2:1),"Wrong fixture wire schema")
        }
        func close() {try? FileManager.default.removeItem(at:directory)}
    }
    @MainActor static func main()throws {
        var checks=0
        func check(_ condition:Bool,_ message:String) {
            precondition(condition,message);checks+=1
        }
        // A delayed first-light acknowledgement cannot revive a cancelled move.
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
            check(f.cues==[next.id],"Replacement did not announce its own first light")
            try f.status(state:"refining");try f.status()
            check(f.cues==[next.id],"Replacement settling replayed first-light cue")
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
            check(f.cues.isEmpty,"Rejected \(rejection) status announced first light")
        }
        // Move identity, rather than intersection or revision, deduplicates
        // re-aiming. A new move at the same intersection still receives a cue.
        do {
            let f=Fixture();defer {f.close()}
            let first=f.target();try f.admit(first);try f.status(state:"approaching")
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
            check(f.cues.isEmpty,"Disabled guidance announced a late first-light receipt")
        }
        // Exercise the installed schema2 holding contract as well as the legacy
        // wire mode above: held darkness is not first light, and cancellation
        // invalidates a point receipt while the motor session remains monitored.
        do {
            let f=Fixture(standby:true);defer {f.close()}
            let first=f.target();try f.admit(first)
            check(f.cues.isEmpty,"Holding/arming announced first light")
            try f.status(state:"approaching")
            check(f.cues==[first.id],"Schema2 confirmed first light was not announced")
            try f.status(state:"refining");try f.status()
            check(f.cues==[first.id],"Schema2 settling replayed move cue")
            let second=f.target(session:first.session,move:2);try f.admit(second)
            let secondSequence=f.laser.sequence
            f.laser.setTarget(nil);try f.status(sequence:secondSequence)
            check(f.cues==[first.id],"Schema2 cancelled target announced late first light")
        }
        print("PASS: \(checks) first-light identity, cancellation and receipt checks; no audio played")
    }
}
