import Foundation
import CoreGraphics
import ImageIO

@main struct PhysicalAILaserTests {
    @MainActor static func main() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("ai-laser-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        var now=100.0,wall=1000.0,checks=0
        func check(_ value: Bool,_ message: String) {if !value {fputs("FAIL: "+message+"\n",stderr)};precondition(value,message);checks+=1}
        var duringClockRead: (()->Void)?
        let laser=PhysicalLaserGuidance(directory:directory.appendingPathComponent("bridge"),automatic:false,wallTime:{let stamp=wall;duringClockRead?();return stamp},uptime:{now})
        func request()->PhysicalLaserGuidance.Request {try! JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:laser.directory.appendingPathComponent("request.json")))}
        func status(_ state: String,sequence: Int? = nil,age: Double = 0,off: Double? = nil,mode: String = "simulation",watermark: PhysicalLaserGuidance.EvidenceAfter? = nil,requiresNew: Bool? = nil)throws {
            let s=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:laser.producer,sequence:sequence ?? laser.sequence,updatedAtUnix:wall-age,mode:mode,state:state,laserOn:state=="marking",offSinceUnix:off,detail:state,evidenceAfter:watermark,requiresNewRevision:requiresNew)
            try JSONEncoder().encode(s).write(to:laser.directory.appendingPathComponent("status.json"),options:.atomic)
        }
        let preparationSession=UUID()
        laser.prepareAlignment(session:preparationSession,moveNumber:1,size:19)
        laser.setEnabled(true)
        laser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"camera/grid")
        let preparationRequest=request()
        check(preparationRequest.action=="off" && preparationRequest.reason=="ai_thinking","thinking alignment must keep beam OFF")
        check(preparationRequest.alignmentPreparation?.session==preparationSession && preparationRequest.target==nil,"thinking metadata or target isolation wrong")
        laser.clearAlignmentPreparation()
        check(request().alignmentPreparation==nil,"clearing preparation did not notify driver")
        // Use a separate disabled bridge for the existing no-IO assertion below.
        try FileManager.default.removeItem(at:laser.directory)
        laser.setEnabled(false)
        let target=PhysicalLaserGuidance.Target(source:"ai",session:UUID(),moveNumber:2,size:19,row:18,col:0,black:false,decisionReceivedAtUnix:wall)
        laser.setTarget(target)
        check(!FileManager.default.fileExists(atPath:laser.directory.path),"disabled bridge performs no IO")
        laser.setEnabled(true)
        laser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"camera/grid")
        check(request().action=="off","no driver means no pointing")
        try status("off",off:wall-1);laser.tick()
        check(request().action=="off","clear camera alone does not prove target empty")
        laser.verifyEmptyTarget(capturedAt:now-0.1,now:now)
        check(request().action=="off","pre-selection empty frame cannot authorize pointing")
        laser.verifyEmptyTarget(capturedAt:now,now:now)
        check(request().action=="point","connected clear board with verified empty target points")
        let revision=laser.sequence
        laser.tick();check(laser.sequence==revision,"heartbeats do not restart targeting")
        check(request().target?.row==18 && request().target?.col==0,"canonical coordinates are unrotated")
        let replacement=PhysicalLaserGuidance.Target(source:"ai",session:target.session,moveNumber:3,size:19,row:17,col:1,black:true,decisionReceivedAtUnix:wall)
        laser.setTarget(replacement)
        check(request().action=="off","replacement cannot reuse old target empty admission")
        try status("off",off:wall-1);laser.tick()
        laser.verifyEmptyTarget(capturedAt:now,now:now)
        check(request().action=="point","replacement points after its own confirmed-dark empty proof")
        try status("marking")
        // Model the driver atomically publishing a newer status just after the
        // app samples wall time. A coherent older snapshot is still fresh.
        duringClockRead={duringClockRead=nil;wall+=0.001;try! status("marking")}
        laser.tick()
        check(!laser.suppressed && request().action=="point","concurrent fresh status publication does not cause false driver loss")
        check(laser.message.contains("marking"),"status label uses the same coherent freshness snapshot")
        check(!laser.acceptsObservation(capturedAt:now,now:now),"lit frame rejected")
        laser.observeCamera(hand:true,valid:true,capturedAt:now,now:now,context:"camera/grid")
        check(laser.suppressed && request().action=="off","hand immediately latches OFF")
        check(!laser.acceptsObservation(capturedAt:now,now:now),"OFF request alone cannot confirm stone")
        laser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"camera/grid")
        check(request().action=="off","clearing hand cannot relight")
        try status("off",sequence:revision,off:wall-1);laser.tick()
        check(!laser.acceptsObservation(capturedAt:now,now:now),"old revision OFF rejected")
        try status("off",off:wall);laser.tick()
        check(!laser.acceptsObservation(capturedAt:now,now:now),"buffered pre-dark frame rejected")
        now+=0.4;wall+=0.4;try status("off",off:wall-0.4);laser.tick()
        check(laser.acceptsObservation(capturedAt:now,now:now),"fresh post-dark observation accepted")
        laser.showAgain();check(request().action=="off","re-show waits for fresh dark empty evidence")
        try status("off",off:wall-1);laser.tick()
        laser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"camera/grid")
        laser.verifyEmptyTarget(capturedAt:now,now:now)
        check(request().action=="point","explicit re-show after verified empty target")
        now+=2;wall+=2;laser.tick()
        check(request().action=="off" && laser.suppressed,"camera/status expiry stops pointing and latches driver loss")
        laser.setTarget(nil);check(request().target==nil,"pause/end removes target")
        laser.setEnabled(false)
        try status("off",off:wall-1);laser.tick()
        check(laser.acceptsObservation(capturedAt:now,now:now),"disabled bridge waits for confirmed dark frame")
        now+=5;wall+=5;laser.tick()
        check(laser.acceptsObservation(capturedAt:now,now:now),"confirmed disabled bridge no longer requires a running driver")

        // Hardware OFF cannot admit a buffered frame without a matching stream watermark.
        laser.setEnabled(true);laser.setTarget(target)
        laser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"camera/grid")
        try status("off",off:wall-1,mode:"hardware");laser.tick()
        laser.verifyEmptyTarget(capturedAt:now,now:now)
        laser.suppress("test_off")
        try status("off",off:wall-1,mode:"hardware");laser.tick()
        check(!laser.acceptsObservation(capturedAt:now,now:now),"hardware OFF without watermark blocked")
        let stamp=CameraFrameTimestamp(capturedAt:now,arrivedAt:now,source:"cameraPresentation",presentationSeconds:12)
        let frame=laser.frames.frame(capturedAt:now,timestamp:stamp,now:now,wall:wall)
        laser.noteFrame(frame)
        var mark=PhysicalLaserGuidance.EvidenceAfter(streamEpoch:frame.streamEpoch,frameID:frame.frameID,timestampSource:"cameraPresentation")
        try status("off",off:wall-1,mode:"hardware",watermark:mark);laser.tick()
        check(!laser.acceptsObservation(capturedAt:now,now:now),"watermark frame itself is too old")
        mark = .init(streamEpoch:frame.streamEpoch,frameID:frame.frameID-1,timestampSource:"cameraPresentation")
        try status("off",off:wall-1,mode:"hardware",watermark:mark);laser.tick()
        check(laser.acceptsObservation(capturedAt:now,now:now),"fresh presentation frame beyond watermark accepted")
        let callback=laser.frames.frame(capturedAt:now,timestamp:nil,now:now,wall:wall)
        laser.noteFrame(callback)
        mark = .init(streamEpoch:callback.streamEpoch,frameID:callback.frameID-1,timestampSource:"callback")
        try status("off",off:wall-0.4,mode:"hardware",watermark:mark);laser.tick()
        check(!laser.acceptsObservation(capturedAt:now,now:now),"callback time is not silently treated as exposure time")
        mark.callbackFlushSeconds=1
        try status("off",off:wall-0.4,mode:"hardware",watermark:mark);laser.tick()
        check(!laser.acceptsObservation(capturedAt:now,now:now),"measured callback flush bound enforced")
        try status("off",off:wall-2,mode:"hardware",watermark:mark);laser.tick()
        check(laser.acceptsObservation(capturedAt:now,now:now),"callback frame requires explicit sufficient flush bound")
        laser.cameraStreamChanged();laser.noteFrame(callback)
        try status("off",off:wall-2,mode:"hardware",watermark:mark);laser.tick()
        check(!laser.acceptsObservation(capturedAt:now,now:now) && laser.suppressed,"reconnect rejects old stream and latches pointing off")
        laser.setEnabled(false)

        // An empty-hand withdrawal may restore only the same pending target,
        // after independent post-OFF empty evidence. No hardware is opened.
        for scenario in ["empty","duplicate","uncertain","gap","stone","fault","epoch","disabled","pause","missing watermark"] {
            let p=PhysicalLaserGuidance(directory:directory.appendingPathComponent("return-"+scenario),automatic:false,wallTime:{wall},uptime:{now})
            p.setEnabled(true);p.setTarget(target)
            func readReturn()->PhysicalLaserGuidance.Request {try! JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:p.directory.appendingPathComponent("request.json")))}
            let handFrame=p.frames.frame(capturedAt:now,timestamp:CameraFrameTimestamp(capturedAt:now,arrivedAt:now,source:"cameraPresentation",presentationSeconds:now),now:now,wall:wall)
            let watermark=PhysicalLaserGuidance.EvidenceAfter(streamEpoch:handFrame.streamEpoch,frameID:handFrame.frameID,timestampSource:"cameraPresentation")
            let offTime=wall
            func returnStatus()throws {
                let s=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:p.producer,sequence:p.sequence,updatedAtUnix:wall,
                    mode:"hardware",state:"off",laserOn:false,offSinceUnix:offTime,detail:"off",
                    evidenceAfter:scenario=="missing watermark" ? nil:watermark)
                try JSONEncoder().encode(s).write(to:p.directory.appendingPathComponent("status.json"),options:.atomic)
                p.tick()
            }
            p.observeCamera(hand:true,valid:true,capturedAt:now,now:now,context:"grid")
            func emptySample(_ advance:Double=0.25)throws {
                now+=advance;wall+=advance
                let frame=p.frames.frame(capturedAt:now,timestamp:CameraFrameTimestamp(capturedAt:now,arrivedAt:now,source:"cameraPresentation",presentationSeconds:now),now:now,wall:wall)
                p.noteFrame(frame);try returnStatus()
                p.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"grid")
                p.verifyEmptyTarget(capturedAt:now,now:now)
            }
            try emptySample(0.4)
            check(readReturn().action=="off","one empty frame cannot relight: "+scenario)
            switch scenario {
            case "empty":
                try emptySample();check(readReturn().action=="off","two empty frames cannot relight")
                try emptySample()
                check(readReturn().action=="point" && readReturn().reason=="empty_after_hand","three fresh dark empty proofs restore target")
                check(readReturn().target==target,"automatic return preserves AI identity and receipt")
            case "duplicate":
                for _ in 0..<4 {try emptySample(0)}
                check(readReturn().action=="off","duplicate capture timestamps do not accumulate witnesses")
            case "uncertain":
                p.resetHandRecoveryEvidence();try emptySample();try emptySample()
                check(readReturn().action=="off","uncertain target interrupts empty streak")
                try emptySample();check(readReturn().action=="point","fresh evidence can recover after uncertainty")
            case "gap":
                try emptySample(0.7);try emptySample()
                check(readReturn().action=="off","camera gap restarts empty streak")
            default:
                if scenario=="stone" {p.suppress("stone_seen_at_target")}
                if scenario=="fault" {p.suppress("driver_interrupted")}
                if scenario=="epoch" {p.cameraStreamChanged()}
                if scenario=="disabled" {p.setEnabled(false)}
                if scenario=="pause" {p.setTarget(nil)}
                p.observeCamera(hand:true,valid:true,capturedAt:now,now:now,context:"grid")
                for _ in 0..<4 {try emptySample()}
                check(readReturn().action=="off","hand cannot override non-hand inhibition: "+scenario)
            }
            p.setEnabled(false)
        }

        // A transient stale-frame stop may restore only a positively empty
        // pending target after the hardware OFF watermark and fresh clear views.
        for recoveryCode in ["camera_frame_stale","request_lease_expired"] {
        for scenario in ["recover","duplicate","gap","slow","stone","fault","epoch","disabled","pause","missing watermark"] + (recoveryCode=="request_lease_expired" ? ["late_status"]:[]) {
            let p=PhysicalLaserGuidance(directory:directory.appendingPathComponent("camera-return-"+recoveryCode+scenario),automatic:false,wallTime:{wall},uptime:{now})
            p.setEnabled(true);p.setTarget(target)
            p.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"grid")
            let before=p.frames.frame(capturedAt:now,timestamp:CameraFrameTimestamp(capturedAt:now,arrivedAt:now,source:"cameraPresentation",presentationSeconds:now),now:now,wall:wall)
            let mark=PhysicalLaserGuidance.EvidenceAfter(streamEpoch:before.streamEpoch,frameID:before.frameID,timestampSource:"cameraPresentation")
            let offTime=wall
            func response(_ blocked:Bool=false,_ code:String?="default")throws {
                let s=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:p.producer,sequence:p.sequence,updatedAtUnix:wall,
                    mode:"hardware",state:"off",laserOn:false,offSinceUnix:offTime,detail:"camera delayed",
                    evidenceAfter:scenario=="missing watermark" ? nil:mark,reasonCode:code=="default" ? recoveryCode:code,requiresNewRevision:blocked)
                try JSONEncoder().encode(s).write(to:p.directory.appendingPathComponent("status.json"),options:.atomic);p.tick()
            }
            func req()->PhysicalLaserGuidance.Request {try! JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:p.directory.appendingPathComponent("request.json")))}
            if scenario=="late_status" {p.suppress("driver_link_lost");try response()}
            else {
                let offRevision=p.sequence
                try response(true)
                check(p.sequence>offRevision && req().action=="off","Expired OFF lease must advance its handshake, never remain stuck on the rejected revision")
                let renewed=p.sequence;p.tick()
                check(p.sequence==renewed,"An old fault acknowledgement must not churn OFF revisions")
            }
            check(p.recoveringCamera && p.message.contains(recoveryCode=="camera_frame_stale" ? "Camera delayed":"heartbeat interrupted") && req().action=="off","stale-frame failure must advertise recovery and request OFF")
            func sample(_ advance:Double=0.25,_ lag:Double=0)throws {
                now+=advance;wall+=advance;let captured=now-lag
                let frame=p.frames.frame(capturedAt:captured,timestamp:CameraFrameTimestamp(capturedAt:captured,arrivedAt:now,source:"cameraPresentation",presentationSeconds:captured),now:now,wall:wall)
                p.noteFrame(frame);try response()
                p.observeCamera(hand:false,valid:true,capturedAt:captured,now:now,context:"grid")
                p.verifyEmptyTarget(capturedAt:captured,now:now)
            }
            try sample(0.4);check(req().action=="off","one fresh frame cannot recover a stale-frame stop")
            switch scenario {
            case "recover","late_status":
                try sample();check(req().action=="off","two fresh frames cannot recover a stale-frame stop")
                try sample();check(req().action=="point" && req().reason==(recoveryCode=="camera_frame_stale" ? "fresh_after_camera_delay":"fresh_after_lease_expiry"),"three dark clear empty frames must restore indication")
                check(req().target==target && !p.recoveringCamera,"camera recovery changed move or decision time")
            case "duplicate":for _ in 0..<4 {try sample(0)};check(req().action=="off","duplicate frames restored laser")
            case "gap":try sample(0.7);try sample();check(req().action=="off","gapped frames restored laser")
            case "slow":for _ in 0..<4 {try sample(0.25,0.55)};check(req().action=="off","slow frames restored laser")
            default:
                if scenario=="stone" {p.suppress("stone_seen_at_target")}
                if scenario=="fault" {try response(true,nil);check(p.interrupted,"hardware fault did not override recovery")}
                if scenario=="epoch" {p.cameraStreamChanged()}
                if scenario=="disabled" {p.setEnabled(false)}
                if scenario=="pause" {p.setTarget(nil)}
                for _ in 0..<4 {try sample()}
                check(req().action=="off","unsafe automatic camera recovery: "+scenario)
            }
            p.setEnabled(false)
        }

        }
        // Publish actual image bytes asynchronously and preserve immutable pairing.
        let broker=PhysicalLaserFrameBroker(directory:directory.appendingPathComponent("frames"))
        let cg=CGContext(data:nil,width:8,height:6,bitsPerComponent:8,bytesPerRow:32,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));cg.fill(CGRect(x:0,y:0,width:8,height:6));let red=cg.makeImage()!
        let first=broker.frame(capturedAt:now,timestamp:stamp,now:now,wall:wall)
        broker.prepare(red,frame:first);broker.flushForTesting()
        check(!FileManager.default.fileExists(atPath:broker.directory.appendingPathComponent("latest.json").path),"pre-encoding cannot publish pixels before frame-specific safety checks")
        broker.offer(red,frame:first,cameraID:"fixture",context:"grid",reference:nil,current:nil,hand:false,aligned:true)
        broker.flushForTesting()
        func manifest()throws->PhysicalLaserFrameBroker.Manifest {try JSONDecoder().decode(PhysicalLaserFrameBroker.Manifest.self,from:Data(contentsOf:broker.directory.appendingPathComponent("latest.json")))}
        let published=try manifest(),file=broker.directory.appendingPathComponent(published.imageFile),bytes=try Data(contentsOf:file)
        let decoded=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(bytes as CFData,nil)!,0,nil)!
        check(published.frame==first && published.width==decoded.width && published.height==decoded.height && published.handObstructed==false,"PNG and per-frame metadata refer to the same unrotated image")
        cg.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1));cg.fill(CGRect(x:0,y:0,width:8,height:6));let blue=cg.makeImage()!
        broker.offer(blue,frame:first,cameraID:"fixture",context:"grid",reference:nil,current:nil,hand:true,aligned:false);broker.flushForTesting()
        check(try Data(contentsOf:file)==bytes,"published frame files are immutable")
        let blocked=broker.frame(capturedAt:now,timestamp:nil,now:now,wall:wall)
        broker.prepare(blue,frame:blocked);broker.flushForTesting()
        check(try manifest().frame==first,"pre-encoding a new frame cannot advance approved metadata")
        broker.offer(blue,frame:blocked,cameraID:"fixture",context:"grid",reference:nil,current:nil,hand:true,aligned:false)
        broker.flushForTesting()
        let blockedBytes=try Data(contentsOf:broker.directory.appendingPathComponent(manifest().imageFile))
        check(try manifest().frame==blocked && manifest().handObstructed==true && !manifest().alignmentValid && blockedBytes != bytes,"prepared pixels retain their own obstructed/invalid verdict and differ from prior frame")
        var latest=first
        for _ in 0..<20 {
            latest=broker.frame(capturedAt:now,timestamp:nil,now:now,wall:wall)
            broker.offer(blue,frame:latest,cameraID:"fixture",context:"grid",reference:nil,current:nil,hand:true,aligned:false)
        }
        broker.flushForTesting()
        check(try manifest().frame==latest && manifest().handObstructed==true,"slow publication coalesces to newest frame with its own evidence")
        let files=try FileManager.default.contentsOfDirectory(at:broker.directory,includingPropertiesForKeys:nil)
        check(files.filter{$0.pathExtension=="png"}.count<=4,"frame retention bounded")
        // A slow encoder must not accumulate a FIFO of obsolete preparation jobs.
        // Hold its first image while fresh frames and their verdicts arrive.
        let encodingStarted=DispatchSemaphore(value:0),releaseEncoding=DispatchSemaphore(value:0)
        var encodes=0
        let congested=PhysicalLaserFrameBroker(directory:directory.appendingPathComponent("congested"),encodeImage:{ _ in
            encodes+=1
            if encodes==1 {encodingStarted.signal();releaseEncoding.wait()}
            return bytes
        })
        let initial=congested.frame(capturedAt:now,timestamp:nil,now:now,wall:wall)
        congested.prepare(red,frame:initial)
        check(encodingStarted.wait(timeout:.now()+2) == .success,"slow encoding begins off the caller thread")
        congested.offer(red,frame:initial,cameraID:"fixture",context:"grid",reference:nil,current:nil,hand:false,aligned:true)
        var newest=initial
        for _ in 0..<30 {
            newest=congested.frame(capturedAt:now,timestamp:nil,now:now,wall:wall)
            congested.prepare(red,frame:newest)
            congested.offer(red,frame:newest,cameraID:"fixture",context:"grid",reference:nil,current:nil,hand:true,aligned:false)
        }
        releaseEncoding.signal();congested.flushForTesting()
        let newestManifest=try JSONDecoder().decode(PhysicalLaserFrameBroker.Manifest.self,from:Data(contentsOf:congested.directory.appendingPathComponent("latest.json")))
        check(encodes<=2,"slow encoder drops obsolete preparation instead of compressing a growing backlog")
        check(newestManifest.frame==newest && newestManifest.handObstructed==true && !newestManifest.alignmentValid,"congested publication keeps the newest frame's own safety verdict")
        let idleBroker=PhysicalLaserFrameBroker(directory:broker.directory)
        idleBroker.resetStream();idleBroker.flushForTesting()
        check(FileManager.default.fileExists(atPath:broker.directory.appendingPathComponent("latest.json").path),"unused broker cannot erase another producer's manifest")
        broker.resetStream();broker.offer(red,frame:first,cameraID:"fixture",context:"grid",reference:nil,current:nil,hand:false,aligned:true);broker.flushForTesting()
        check(!FileManager.default.fileExists(atPath:broker.directory.appendingPathComponent("latest.json").path),"old queued frame cannot republish after reconnect")

        // Real game flow, injected engine and monotonic receipt instant.
        let gameLaser=PhysicalLaserGuidance(directory:directory.appendingPathComponent("game-bridge"),automatic:false,wallTime:{wall},uptime:{now})
        let ai=PhysicalAI(directory:directory.appendingPathComponent("game"),generate:{_,_ in now+=2;wall+=2;return "D4"},laser:gameLaser,uptime:{now},wallTime:{wall})
        ai.draft.size=9;ai.draft.humanBlack=false
        check(ai.start(),"start AI-first game")
        func feed(_ cells: [String],hand: Bool? = false) {
            for _ in 0..<4 {
                now+=0.2;wall+=0.2
                var o=BoardObservation(readings:cells.enumerated().map {.init(row:$0.offset/9,col:$0.offset%9,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:9)
                o.capturedAt=now;o.handObstructed=hand;ai.consume(o,now:now)
            }
        }
        let empty=Array(repeating:"empty",count:81);feed(empty)
        try await Task.sleep(nanoseconds:60_000_000)
        let receipt=now,receiptWall=wall
        check(ai.phase == .placing,"AI decision awaits placement")
        check(ai.snapshot?.moves.last?.decisionReceivedAtUnix==receiptWall,"receipt timestamp saved")
        check(ai.timing.blackToPlay==false && ai.timing.anchor==receipt,"clock switched at decision receipt")
        check(ai.laser.target?.decisionReceivedAtUnix==receiptWall,"pointer receives same clock boundary")
        // Known move coordinates can be indicated through occupancy uncertainty,
        // including after restore. This must never certify physical placement or
        // bypass hand, alignment, freshness or positive-stone suppression.
        for scenario in ["other uncertain","target uncertain","duplicate","occupied","white occupied","hand","unknown hand","invalid alignment","lighting","stale","nonfinite"] {
            let saved=directory.appendingPathComponent("restored-"+scenario)
            try FileManager.default.createDirectory(at:saved,withIntermediateDirectories:true)
            try FileManager.default.copyItem(at:directory.appendingPathComponent("game/current.json"),to:saved.appendingPathComponent("current.json"))
            let pointer=PhysicalLaserGuidance(directory:saved.appendingPathComponent("bridge"),automatic:false,wallTime:{wall},uptime:{now})
            let resumed=PhysicalAI(directory:saved,laser:pointer,uptime:{now},wallTime:{wall})
            resumed.resume();pointer.setEnabled(true)
            now+=0.2;wall+=0.2
            pointer.observeCamera(hand:scenario=="hand" ? true:scenario=="unknown hand" ? nil:false,
                valid:scenario != "invalid alignment",capturedAt:now,now:now,context:"fixture/grid")
            let reply=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:pointer.producer,sequence:pointer.sequence,
                updatedAtUnix:wall,mode:"simulation",state:"off",laserOn:false,offSinceUnix:wall-1,detail:"off")
            try JSONEncoder().encode(reply).write(to:pointer.directory.appendingPathComponent("status.json"),options:.atomic)
            pointer.tick()
            var readings=empty.enumerated().map {IntersectionReading(row:$0.offset/9,col:$0.offset%9,occupancy:.empty,confidence:1,delta:0)}
            let uncertain=scenario=="target uncertain" ? 48:0
            readings[uncertain] = .init(row:uncertain/9,col:uncertain%9,occupancy:.uncertain,confidence:0.2,delta:0)
            if scenario=="duplicate" {readings[80]=readings[0]}
            if scenario=="occupied" || scenario=="white occupied" {readings[48] = .init(row:5,col:3,occupancy:scenario=="occupied" ? .black:.white,confidence:1,delta:0)}
            if scenario=="nonfinite" {readings[48] = .init(row:5,col:3,occupancy:.empty,confidence:.nan,delta:0)}
            var observation=BoardObservation(readings:readings,size:9)
            observation.capturedAt=scenario=="stale" ? now-2:now
            observation.handObstructed=scenario=="hand" ? true:scenario=="unknown hand" ? nil:false
            observation.lightingBlocked=scenario=="lighting"
            resumed.consume(observation,now:now)
            let request=try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:pointer.directory.appendingPathComponent("request.json")))
            check(request.action==(["other uncertain","target uncertain"].contains(scenario) ? "point":"off"),"Restored aim admission: "+scenario)
            check(resumed.phase == .placing && resumed.snapshot?.pendingPlacement == true,"Uncertain restored board cannot complete placement")
            check(resumed.snapshot?.moves.last?.decisionReceivedAtUnix==receiptWall,"Restore aim preserves decision time")
            if scenario=="target uncertain" {
                for recovery in ["hand_entered_board","camera_frame_stale","request_lease_expired"] {
                    pointer.suppress(recovery)
                    let offTime=wall
                    for i in 0..<3 {
                        now+=0.3;wall+=0.3
                        let status=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:pointer.producer,sequence:pointer.sequence,
                            updatedAtUnix:wall,mode:"simulation",state:"off",laserOn:false,offSinceUnix:offTime,detail:"off",
                            reasonCode:recovery=="hand_entered_board" ? nil:recovery,requiresNewRevision:false)
                        try JSONEncoder().encode(status).write(to:pointer.directory.appendingPathComponent("status.json"),options:.atomic)
                        pointer.tick();pointer.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"fixture/grid")
                        observation.capturedAt=now;resumed.consume(observation,now:now)
                        let current=try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:pointer.directory.appendingPathComponent("request.json")))
                        check(current.action==(i==2 ? "point":"off"),"Uncertain pending move recovery must preserve its independent clear-frame streak: "+recovery)
                        check(resumed.phase == .placing && resumed.snapshot?.pendingPlacement == true,"Cue recovery accepted an uncertain physical stone")
                        check(resumed.snapshot?.moves.last?.decisionReceivedAtUnix==receiptWall,"Cue recovery changed the decision clock boundary")
                    }
                }
            }
            pointer.setEnabled(false)
        }
        // Even stone-shaped readings from a laser-lit frame cannot confirm placement.
        gameLaser.setEnabled(true)
        gameLaser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"fixture/grid")
        func gameStatus(_ state: String,off: Double? = nil,hardware:Bool=false,lit:Bool?=nil)throws {
            let reply=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:gameLaser.producer,sequence:gameLaser.sequence,
                updatedAtUnix:wall,mode:hardware ? "hardware":"simulation",state:state,laserOn:lit ?? (state=="adequate"),offSinceUnix:off,detail:state,illuminationConfirmed:hardware ? lit:nil)
            try JSONEncoder().encode(reply).write(to:gameLaser.directory.appendingPathComponent("status.json"),options:.atomic)
        }
        try gameStatus("off",off:wall-1);gameLaser.tick()
        var emptyProof=BoardObservation(readings:empty.enumerated().map {.init(row:$0.offset/9,col:$0.offset%9,occupancy:.empty,confidence:1,delta:0)},size:9)
        emptyProof.capturedAt=now;emptyProof.handObstructed=false
        ai.consume(emptyProof,now:now)
        let admitted=try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:gameLaser.directory.appendingPathComponent("request.json")))
        check(admitted.action=="point","AI publishes point only after post-decision empty proof")
        // PG33's optical samples can illuminate away from the destination.
        // Positive light is a cue receipt, never board-placement acceptance.
        let beforeOpticalHistory=ai.snapshot!.moves.map(\.point),beforeOpticalTiming=ai.timing
        let beforeOpticalMarker=ai.guidanceTarget
        for (state,lit) in [("approaching",true),("approaching",false),("adequate",true)] {
            try gameStatus(state,hardware:true,lit:lit);gameLaser.tick()
            check(ai.phase == .placing && ai.snapshot!.pendingPlacement && ai.guidanceTarget==beforeOpticalMarker,"Optical feedback cannot accept placement or remove virtual marker: \(state)/\(lit)")
            check(ai.snapshot!.moves.map(\.point)==beforeOpticalHistory && ai.timing==beforeOpticalTiming,"Optical feedback cannot commit history or reset clock: \(state)/\(lit)")
        }
        try gameStatus("adequate");gameLaser.tick()
        var litCandidate=empty;litCandidate[48]="black";feed(litCandidate)
        check(ai.phase == .placing && ai.pendingPoint==48,"laser-lit stone-like reading cannot accept a move")
        check(gameLaser.suppressed,"stone-like reading requests darkness for verification")
        gameLaser.setEnabled(false);try gameStatus("off",off:wall-1);gameLaser.tick()
        check(gameLaser.acceptsObservation(capturedAt:now,now:now),"simulator confirmed dark before returning to screen play")
        let pending=gameLaser.target;gameLaser.setTarget(nil);gameLaser.setTarget(pending)
        var wrongColor=empty;wrongColor[48]="white";feed(wrongColor)
        check(gameLaser.suppressed && ai.phase == .placing,"wrong-color stone at target also inhibits pointing")
        now+=5;wall+=5
        feed(empty,hand:true)
        check(ai.phase == .placing && ai.laser.suppressed,"hand extinguishes target without advancing game")
        var wrong=empty;wrong[49]="black";feed(wrong)
        check(ai.phase == .placing && ai.snapshot?.moves.count==1,"wrong stone rejected")
        var correct=empty;correct[48]="black";feed(correct)
        check(ai.phase == .human && ai.laser.target==nil,"correct stone completes physical mirror")
        check(ai.timing.anchor==receipt && ai.timing.elapsed(black:false,at:now)>7,"placement never resets human clock")
        let elapsed=ai.timing.elapsed(black:false,at:now);ai.pause()
        now+=50;wall+=50
        check(ai.timing.elapsed(black:false,at:now)==elapsed,"pause freezes elapsed time")
        let restored=PhysicalAI(directory:directory.appendingPathComponent("game"),uptime:{now},wallTime:{wall})
        check(restored.phase == .paused && restored.timing.anchor==nil && restored.timing.whiteSeconds==elapsed,"restart preserves time without downtime charge")
        // Ordinary two-color game acceptance uses real controller/persistence
        // types and an injected engine. This does not simulate optical success.
        for humanBlack in [true,false] {
            let label=humanBlack ? "human-black":"human-white"
            let folder=directory.appendingPathComponent("ordinary-"+label)
            let pointer=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,wallTime:{wall},uptime:{now})
            var engineCalls=0
            let game=PhysicalAI(directory:folder,generate:{_,_ in engineCalls+=1;now+=2;wall+=2;return "D4"},laser:pointer,uptime:{now},wallTime:{wall})
            game.draft.size=9;game.draft.humanBlack=humanBlack
            check(game.start(),"Ordinary game starts: "+label)
            func sample(_ cells:[String],hand:Bool=false) {
                for _ in 0..<4 {
                    now+=0.2;wall+=0.2
                    var frame=BoardObservation(readings:cells.enumerated().map {.init(row:$0.offset/9,col:$0.offset%9,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:9)
                    frame.capturedAt=now;frame.handObstructed=hand;game.consume(frame,now:now)
                }
            }
            var board=empty;sample(board)
            if humanBlack {
                check(game.phase == .human && engineCalls==0,"Human Black must place before AI search")
                board[0]="black";sample(board)
                check(game.snapshot?.moves.count==1 && game.phase == .checking,"Human move awaits fresh post-placement board evidence")
                sample(board)
            }
            try await Task.sleep(nanoseconds:60_000_000)
            let moveCount=humanBlack ? 2:1
            check(engineCalls==1 && game.phase == .placing && game.snapshot?.moves.count==moveCount,"One authoritative AI answer awaits mirror: "+label+" phase=\(game.phase) calls=\(engineCalls) moves=\(game.snapshot!.moves.count) status=\(game.status)")
            let identity=game.snapshot!.id,decision=game.snapshot!.moves.last!.decisionReceivedAtUnix
            let target=pointer.target,marker=game.guidanceTarget
            check(target?.row==5 && target?.col==3 && target?.black == !humanBlack,"AI target has canonical point and color: "+label)
            check(marker?.session==identity && marker?.moveNumber==moveCount && marker?.row==target?.row && marker?.col==target?.col && marker?.black==target?.black,"Virtual marker agrees with physical target: "+label)
            check(game.timing.blackToPlay==humanBlack && game.timing.anchor==now && decision==wall,"Decision receipt starts human clock: "+label)
            sample(board,hand:true)
            check(game.phase == .placing && game.pendingPoint==48 && game.snapshot!.moves.count==moveCount,"Hand cannot accept pending AI placement: "+label)
            let elapsedBeforePause=game.timing.elapsed(black:humanBlack,at:now)
            game.pause();now+=30;wall+=30
            check(game.phase == .paused && pointer.target==nil && game.guidanceTarget==nil,"Pause revokes physical and virtual targets: "+label)
            check(game.timing.elapsed(black:humanBlack,at:now)==elapsedBeforePause && game.snapshot!.pendingPlacement,"Paused time and pending placement are retained: "+label)
            game.resume()
            check(game.phase == .placing && pointer.target==target && game.guidanceTarget?.session==identity,"Resume restores the same pending move: "+label)
            check(engineCalls==1 && game.snapshot!.moves.last!.decisionReceivedAtUnix==decision,"Resume neither repeats AI search nor changes decision receipt: "+label)
            var wrong=board;wrong[48]=humanBlack ? "black":"white";sample(wrong)
            check(game.phase == .placing && game.snapshot!.moves.count==moveCount,"Opposite-color stone cannot complete AI mirror: "+label)
            board[48]=humanBlack ? "white":"black";sample(board)
            check(game.phase == .human && !game.snapshot!.pendingPlacement && game.pendingPoint==nil,"Correct-color mirror completes placement: "+label)
            check(pointer.target==nil && game.guidanceTarget==nil && game.snapshot!.moves.count==moveCount,"Accepted placement clears both targets without duplicate history: "+label)
            check(game.timing.blackToPlay==humanBlack && game.timing.elapsed(black:humanBlack,at:now)>=elapsedBeforePause,"Physical acceptance retains human turn and accrued time: "+label)
            game.pause()
            let savedTiming=game.timing
            now+=45;wall+=45
            let reopened=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:PhysicalLaserGuidance(directory:folder.appendingPathComponent("reopen-bridge"),automatic:false),uptime:{now},wallTime:{wall})
            check(reopened.phase == .paused && reopened.snapshot!.id==identity && reopened.snapshot!.moves.map(\.point)==game.snapshot!.moves.map(\.point),"Reopen preserves game identity and legal history: "+label)
            check(reopened.timing==savedTiming && reopened.cells==board,"Reopen preserves board and clock without downtime: "+label)
        }
        // Confirmed adequate illumination announces each move once after settling.
        // Unknown output, simulation, retries and old acknowledgements are silent.
        let cue=PhysicalLaserGuidance(directory:directory.appendingPathComponent("cue"),automatic:false,wallTime:{wall},uptime:{now})
        var cues=[String]()
        cue.onTargetIndicated={cues.append($0.id)}
        func cueStatus(_ state:String,mode:String="hardware",sequence:Int?=nil,on:Bool=true,confirmed:Bool=true,centeringCapable:Bool=true)throws {
            let value=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:cue.producer,sequence:sequence ?? cue.sequence,
                updatedAtUnix:wall,mode:mode,state:state,laserOn:on,offSinceUnix:on ? nil:wall-1,detail:state,illuminationConfirmed:confirmed,capabilities:centeringCapable ? ["stoneCenteringWiggle"]:[])
            try JSONEncoder().encode(value).write(to:cue.directory.appendingPathComponent("status.json"),options:.atomic)
            cue.tick()
        }
        func admitCue(_ target:PhysicalLaserGuidance.Target)throws {
            cue.setTarget(target);cue.setEnabled(true)
            cue.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"cue-camera")
            try cueStatus("off",mode:"simulation",on:false)
            cue.verifyEmptyTarget(capturedAt:now,now:now)
        }
        try admitCue(target)
        try cueStatus("adequate",mode:"simulation")
        try cueStatus("approaching",confirmed:false);try cueStatus("refining",confirmed:false)
        check(cues.isEmpty,"simulation or unverified illumination played move cue")
        try cueStatus("adequate",sequence:cue.sequence-1)
        check(cues.isEmpty,"old revision played cue")
        try cueStatus("adequate",on:false)
        check(cues.isEmpty,"dark status played cue")
        try cueStatus("approaching")
        check(cues.isEmpty,"acquisition illumination clicked before optical acceptance")
        try cueStatus("refining")
        check(cues.isEmpty,"refinement illumination clicked before optical acceptance")
        try cueStatus("adequate")
        check(cues==[target.id],"confirmed adequate illumination must click once")
        try cueStatus("adequate")
        check(cues==[target.id],"settling or repeated feedback replayed the click")
        cue.suppress("hand_entered_board");cue.setTarget(nil)
        try admitCue(target);try cueStatus("adequate")
        check(cues.count==1,"pause/retry repeated the move cue")
        try admitCue(replacement);try cueStatus("adequate")
        check(cues==[target.id,replacement.id],"next move did not receive its cue")
        cue.setEnabled(false);try cueStatus("adequate")
        check(cues.count==2,"disabled bridge played cue")
        let hint=PhysicalLaserGuidance.Target(source:"ai",session:target.session,moveNumber:3,size:19,row:9,col:9,
            black:true,decisionReceivedAtUnix:wall,purpose:"centering",stoneCenter:.init(x:9.5,y:9))
        try admitCue(hint)
        func cueRequest()->PhysicalLaserGuidance.Request {try! JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:cue.directory.appendingPathComponent("request.json")))}
        check(cueRequest().action=="off","empty-target proof admitted occupied centering target")
        cue.verifyMoveTarget(capturedAt:now,now:now)
        check(cueRequest().action=="off","Known-move proof must not admit an ambiguous centering hint")
        try cueStatus("off",mode:"simulation",on:false,centeringCapable:false)
        cue.verifyCenteringTarget(capturedAt:now,now:now)
        check(cueRequest().action=="off","legacy driver admitted centering without capability")
        try cueStatus("off",mode:"simulation",on:false)
        cue.verifyCenteringTarget(capturedAt:now,now:now)
        check(cueRequest().action=="point" && cueRequest().target?.purpose=="centering","centering proof did not admit dedicated hint")
        try cueStatus("approaching");try cueStatus("adequate")
        check(cues.count==2,"centering hint played opponent stone click")
        cue.observeCamera(hand:true,valid:true,capturedAt:now,now:now,context:"cue-camera")
        check(cue.suppressed && cueRequest().action=="off","hand did not stop centering")
        cue.setEnabled(false)
        // Even a stalled audio server must not stall main-thread lease renewal.
        let audioStarted=DispatchSemaphore(value:0),audioRelease=DispatchSemaphore(value:0)
        let audio=StonePlacementAudio(playbackForTesting:{_ in audioStarted.signal();_ = audioRelease.wait(timeout:.now()+3)})
        cue.onTargetIndicated={_ in audio.play(volume:0.5)}
        let audioTarget=PhysicalLaserGuidance.Target(source:"ai",session:target.session,moveNumber:4,size:19,row:6,col:5,black:true,decisionReceivedAtUnix:wall)
        try admitCue(audioTarget)
        let audioCallStart=ProcessInfo.processInfo.systemUptime
        try cueStatus("adequate")
        check(ProcessInfo.processInfo.systemUptime-audioCallStart<0.2,"audio work blocked the indication callback")
        try await Task.sleep(nanoseconds:20_000_000)
        check(audioStarted.wait(timeout:.now()) == .success,"injected audio operation never started")
        for _ in 0..<6 {
            now+=0.2;wall+=0.2
            try cueStatus("adequate")
            cue.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"cue-camera")
            check(cueRequest().action=="point" && cueRequest().sentAtUnix==wall,"blocked audio prevented heartbeat renewal")
        }
        audioRelease.signal();cue.setEnabled(false)
        // Exercise the live asynchronous exchange too, not just deterministic
        // synchronous protocol tests. All files are in the temporary sandbox.
        let asyncLaser=PhysicalLaserGuidance(directory:directory.appendingPathComponent("async"),
            wallTime:{wall},uptime:{now})
        func asyncRequest()->PhysicalLaserGuidance.Request? {
            guard let data=try? Data(contentsOf:asyncLaser.directory.appendingPathComponent("request.json")) else {return nil}
            return try? JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:data)
        }
        func until(_ condition:()->Bool) async throws ->Bool {
            for _ in 0..<150 {
                asyncLaser.tick()
                if condition() {return true}
                try await Task.sleep(nanoseconds:20_000_000)
            }
            return false
        }
        asyncLaser.setTarget(target);asyncLaser.setEnabled(true)
        check(try await until {asyncRequest()?.action=="off"},"async initial request remains OFF without driver")
        let asyncStatus=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:asyncLaser.producer,
            sequence:asyncLaser.sequence,updatedAtUnix:wall,mode:"simulation",state:"off",laserOn:false,
            offSinceUnix:wall-1,detail:"off")
        try JSONEncoder().encode(asyncStatus).write(to:asyncLaser.directory.appendingPathComponent("status.json"),options:.atomic)
        check(try await until {asyncLaser.message.contains("Simulation")},"async status reaches native consumer")
        asyncLaser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"async-camera")
        asyncLaser.verifyEmptyTarget(capturedAt:now,now:now)
        check(try await until {asyncRequest()?.action=="point"},"async fresh proof admits point")
        now+=2;wall+=2
        check(try await until {asyncRequest()?.action=="off"},"cached async status cannot remain fresh after expiry")
        check(asyncLaser.suppressed,"async stale status still suppresses guidance")
        asyncLaser.setEnabled(false)
        print("PASS: \(checks) AI laser lifecycle, clock-receipt, dark-frame and protocol checks")
    }
}
