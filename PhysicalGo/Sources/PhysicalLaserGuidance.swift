import Foundation
import Combine
import CoreGraphics

/// Game-to-pointer contract. This never opens a serial device or commands motors.
/// The independently commissioned driver owns optical calibration and interlocks.
@MainActor final class PhysicalLaserGuidance: ObservableObject {
    struct PlaySession: Codable, Equatable {
        let source: String
        let session: UUID
        let size: Int
        var valid: Bool {["ai","online"].contains(source) && [9,13,19].contains(size)}
    }
    struct ThermalStatus: Codable {
        let policy: String
        var sampleSequence: Int?
        var receivedAtUnix: Double?
        var sampleAgeUpperMs: Double?
        var baseC: Double?
        var tiltC: Double?
        var maxBaseC: Double?
        var maxTiltC: Double?
        var baseTrendCPerMinute: Double?
        var tiltTrendCPerMinute: Double?
        var baseCurrentMA: Double?
        var tiltCurrentMA: Double?
        var baseVoltageV: Double?
        var tiltVoltageV: Double?
        var unavailableReason: String?
        func fresh(statusAge: Double, updatedAtUnix: Double) -> Bool {
            guard unavailableReason == nil, ["warm_hold","cooling"].contains(policy),
                  let sampleSequence, sampleSequence >= 0, let receivedAtUnix, receivedAtUnix.isFinite,
                  receivedAtUnix>0,receivedAtUnix<=updatedAtUnix,
                  let age=sampleAgeUpperMs, age.isFinite, age>=0, statusAge>=0,
                  age+0.001 >= (updatedAtUnix-receivedAtUnix)*1000,
                  age+statusAge*1000<=750, let baseC, let tiltC,
                  baseC.isFinite, tiltC.isFinite, (0...255).contains(baseC), (0...255).contains(tiltC) else {return false}
            return true
        }
        func admissible(statusAge: Double, updatedAtUnix: Double) -> Bool {
            fresh(statusAge:statusAge,updatedAtUnix:updatedAtUnix) && baseC!<50 && tiltC!<50
        }
    }
    struct AlignmentPreparation: Codable, Equatable {
        let session: UUID
        let moveNumber: Int
        let size: Int
        let positionConfirmedAtUnix: Double
    }
    struct Target: Codable, Equatable {
        let source: String
        let session: UUID
        let moveNumber: Int
        let size: Int
        let row: Int
        let col: Int
        let black: Bool
        let decisionReceivedAtUnix: Double
        var purpose:String?=nil
        var stoneCenter:ImagePoint?=nil
        var id: String {"\(source)/\(session)/\(moveNumber)"+(purpose.map {"/\($0)/\(row)/\(col)"} ?? "")}
    }
    struct Request: Codable {
        let schemaVersion: Int
        let producer: UUID
        let sequence: Int
        let sentAtUnix: Double
        let expiresAtUnix: Double
        let action: String
        let reason: String
        let target: Target?
        let cameraContext: String?
        var streamEpoch: UUID?
        var alignmentPreparation: AlignmentPreparation?
        var playSession: PlaySession?
        var retainOnly: Bool?
    }
    struct EvidenceAfter: Codable {
        let streamEpoch: UUID
        let frameID: UInt64
        let timestampSource: String
        var callbackFlushSeconds: Double?
    }
    struct DriverStatus: Codable {
        let schemaVersion: Int
        let producer: UUID
        let sequence: Int
        let updatedAtUnix: Double
        let mode: String // hardware or simulation; simulation must never imply light
        let state: String // off, approaching, adequate, refining, spot_not_found, fault
        let laserOn: Bool
        let offSinceUnix: Double?
        let detail: String
        var evidenceAfter: EvidenceAfter?
        var setupId: String?
        var reasonCode: String?
        var requiresNewRevision: Bool?
        var illuminationConfirmed: Bool?
        var capabilities:[String]?
        var playSession: PlaySession?
        var cameraContext: String?
        var streamEpoch: UUID?
        var motorsHeld: Bool?
        var motorBusPowered: Bool?
        var beamOffSinceUnix: Double?
        var darkEvidenceAfter: EvidenceAfter?
        var thermal: ThermalStatus?
    }
    @Published private(set) var enabled=false
    @Published private(set) var message="Laser bridge disabled"
    @Published private(set) var suppressed=false
    @Published private(set) var standbyEnabled=false
    @Published private(set) var motorMessage="Motor holding is off"
    @Published private(set) var temperatureMessage="Temperature unavailable"
    @Published private(set) var standbyAvailable=false
    @Published private(set) var holdingInterrupted=false
    @Published private(set) var controllerResetRequired=false
    private(set) var playSession: PlaySession?
    private(set) var mayHaveMotorSession=false
    private var wireSchema=1
    private var standbyReady=false
    private var closingStandby=false
    private var standbyFault: String?
    private var standbySetup: String?
    private var armingStartedAt: Double?
    private var coldAdmissionConfirmed=false
    private var lastRetainOnly: Bool?
    private var cameraAt: Double?
    private var cameraHand: Bool?
    var recoveringCamera:Bool {enabled && target != nil && suppressed && ["camera_frame_stale","request_lease_expired"].contains(reason)}
    var interrupted:Bool {enabled && target != nil && suppressed && ["driver_interrupted","driver_link_lost"].contains(reason)}
    private(set) var target: Target?
    private(set) var alignmentPreparation: AlignmentPreparation?
    private(set) var sequence=0
    let producer=UUID()
    let directory: URL
    let frames: PhysicalLaserFrameBroker
    private var currentFrame: PhysicalLaserFrameBroker.Frame?
    private var timer: AnyCancellable?
    private var clearAt: Double?
    private var targetEmptyAt: Double?
    private var handEmptyFirst: Double?
    private var handEmptyLast: Double?
    private var handEmptyCount=0
    private var emptyEvidenceAfter=0.0
    private(set) var cameraContext: String?
    private var lastAction="off"
    private var reason="disabled"
    private var blockedMove:(session:UUID,number:Int,reason:String)?
    private var mayHaveIlluminated=false
    private var captureWireSupported:Bool?
    private var driver: DriverStatus?
    var onTargetIndicated: ((Target)->Void)?
    var onRequestPublished: ((Request)->Void)?
    private var indicatedSession: UUID?
    private var indicatedMoves=Set<String>()
    private let wallTime: ()->Double
    private let uptime: ()->Double
    private let automatic: Bool
    init(directory: URL? = nil, automatic: Bool = true,
         wallTime: @escaping ()->Double = {Date().timeIntervalSince1970},
         uptime: @escaping ()->Double = {ProcessInfo.processInfo.systemUptime}) {
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Physical Go/LaserBridge")
        self.frames=PhysicalLaserFrameBroker(directory:self.directory.appendingPathComponent("frames"))
        self.automatic=automatic;self.wallTime=wallTime;self.uptime=uptime
    }
    func setStandbyEnabled(_ value: Bool) {
        guard value != standbyEnabled else {return}
        standbyEnabled=value
        if !value,wireSchema==2 {closingStandby=true}
        targetEmptyAt=nil;emptyEvidenceAfter=uptime();sequence+=1;tick()
    }
    func setPlaySession(_ value: PlaySession?) {
        let value=value?.valid == true ? value:nil
        guard value != playSession else {return}
        if wireSchema==2 {closingStandby=true}
        // A new game revokes the old lease, but is not a hardware-fault retry.
        playSession=value;standbyReady=false
        targetEmptyAt=nil;emptyEvidenceAfter=uptime();sequence+=1;tick()
    }
    func setEnabled(_ value: Bool) {
        resetHandRecoveryEvidence()
        targetEmptyAt=nil;emptyEvidenceAfter=uptime()
        if !value,wireSchema==2 {closingStandby=true}
        enabled=value;sequence+=1;reason=value ? "waiting_for_clear_camera":"disabled"
        if timer == nil,automatic {
            timer=Timer.publish(every:0.2,on:.main,in:.common).autoconnect().sink {[weak self] _ in self?.tick()}
        }
        tick()
    }
    func setTarget(_ value: Target?) {
        guard target != value else {return}
        if suppressed,let old=target,
           !["hand_entered_board","stone_seen_at_target","capture_evidence_changed","camera_frame_stale","request_lease_expired"].contains(reason) {
            blockedMove=(old.session,old.moveNumber,reason)
        }
        if let value,let blocked=blockedMove,(value.session != blocked.session || value.moveNumber != blocked.number) {blockedMove=nil}
        let retainFault=value.map {value in blockedMove.map {$0.session==value.session && $0.number==value.moveNumber} ?? false} ?? false
        let previousReason=blockedMove?.reason ?? reason
        target=value;suppressed=retainFault;sequence+=1
        resetHandRecoveryEvidence()
        targetEmptyAt=nil;emptyEvidenceAfter=uptime()
        reason=retainFault ? previousReason:value == nil ? "no_pending_move":value?.purpose=="centering" ? "centering_requested":value?.purpose=="capture" ? "capture_requested":"move_received"
        tick()
    }
    func prepareAlignment(session: UUID, moveNumber: Int, size: Int) {
        if let p=alignmentPreparation,p.session==session,p.moveNumber==moveNumber,p.size==size {return}
        alignmentPreparation = .init(session:session,moveNumber:moveNumber,size:size,positionConfirmedAtUnix:wallTime())
        sequence+=1;tick()
    }
    func clearAlignmentPreparation() {
        guard alignmentPreparation != nil else {return}
        alignmentPreparation=nil;sequence+=1;tick()
    }
    /// A hand means "stop illuminating", never "stone accepted". Unknown hands
    /// or alignment loss inhibit output too, but only actual hand entry latches.
    func observeCamera(hand: Bool?, valid: Bool, capturedAt: Double, now: Double, context: String) {
        guard capturedAt.isFinite,now>=capturedAt,now-capturedAt<1.5 else {cameraAt=nil;cameraHand=nil;clearAt=nil;resetHandRecoveryEvidence();tick();return}
        if let old=cameraContext,old != context {
            // suppress() publishes immediately: revoke the old scope before
            // that callback can issue an intermediate clear standby request.
            cameraAt=nil;cameraHand=nil;clearAt=nil;targetEmptyAt=nil
            if wireSchema==2 {latchStandby("camera_context_changed")}
            if target != nil {suppress("camera_context_changed")}
        }
        if cameraContext != context {sequence+=1}
        cameraContext=context;cameraAt=valid && hand != nil ? capturedAt:nil;cameraHand=hand
        clearAt=valid && hand == false ? capturedAt:nil
        if clearAt == nil {resetHandRecoveryEvidence()}
        if hand == true {suppress("hand_entered_board")}
        tick()
    }
    /// Called only for a positive, unambiguous EMPTY reading in a validated
    /// observation. Prior-to-decision or illuminated frames cannot authorize aim.
    func verifyEmptyTarget(capturedAt: Double, now: Double) {
        guard target?.purpose==nil else {return}
        verifyTarget(capturedAt:capturedAt,now:now)
    }
    /// An authoritative pending move supplies its coordinate, not a guessed
    /// camera assignment. The caller must reject positively observed stones and
    /// validate the complete camera observation. Uncertain occupancy can keep
    /// the placement cue available; it never confirms a stone or changes play.
    func verifyMoveTarget(capturedAt:Double,now:Double) {
        guard let target,target.purpose==nil,["ai","online"].contains(target.source) else {return}
        verifyTarget(capturedAt:capturedAt,now:now)
    }
    /// Centering intentionally aims at an observed stone. Its caller must
    /// supply repeated, positive outline/assignment evidence, never mere glare.
    func verifyCenteringTarget(capturedAt:Double,now:Double) {
        guard target?.purpose=="centering" else {return}
        verifyTarget(capturedAt:capturedAt,now:now)
    }
    /// Caller has a stable, positive prisoner observation from dark frames.
    func verifyCaptureTarget(capturedAt:Double,now:Double) {
        guard target?.purpose=="capture" else {return}
        verifyTarget(capturedAt:capturedAt,now:now)
    }
    private func verifyTarget(capturedAt:Double,now:Double) {
        let recovering=suppressed && (["hand_entered_board","camera_frame_stale","request_lease_expired"].contains(reason) || (target?.purpose=="capture" && reason=="capture_evidence_changed"))
        guard enabled,target != nil,(!suppressed || recovering),capturedAt>=emptyEvidenceAfter,
              (0..<1.5).contains(now-capturedAt),clearAt.map({abs($0-capturedAt)<0.000001}) == true,
              acceptsObservation(capturedAt:capturedAt,now:now,requireDarkEvidence:recovering) else {resetHandRecoveryEvidence();return}
        if recovering {
            guard let driver,driver.requiresNewRevision != true else {resetHandRecoveryEvidence();return}
            if ["camera_frame_stale","request_lease_expired"].contains(reason),driver.reasonCode != reason || now-capturedAt>=0.5 {
                resetHandRecoveryEvidence();return
            }
            if let last=handEmptyLast {
                if capturedAt<=last {return}
                if capturedAt-last>0.6 {resetHandRecoveryEvidence()}
            }
            if handEmptyFirst == nil {handEmptyFirst=capturedAt}
            handEmptyLast=capturedAt;handEmptyCount+=1
            guard handEmptyCount>=3,capturedAt-handEmptyFirst!>=0.45 else {return}
            let recovered=reason=="request_lease_expired" ? "fresh_after_lease_expiry":reason=="camera_frame_stale" ? "fresh_after_camera_delay":target?.purpose=="centering" ? "centering_after_hand":"empty_after_hand"
            suppressed=false;reason=recovered;sequence+=1
            resetHandRecoveryEvidence()
        }
        targetEmptyAt=capturedAt;tick()
    }
    func resetHandRecoveryEvidence() {handEmptyFirst=nil;handEmptyLast=nil;handEmptyCount=0}
    func invalidateCamera() {cameraAt=nil;cameraHand=nil;clearAt=nil;targetEmptyAt=nil;resetHandRecoveryEvidence();emptyEvidenceAfter=uptime();tick()}
    func cameraStreamChanged() {
        frames.resetStream();currentFrame=nil;cameraAt=nil;cameraHand=nil;clearAt=nil;sequence+=1
        if wireSchema==2 {latchStandby("camera_stream_changed")}
        resetHandRecoveryEvidence()
        targetEmptyAt=nil;emptyEvidenceAfter=uptime()
        if target != nil {suppressed=true;reason="camera_stream_changed"}
        tick()
    }
    func noteFrame(_ frame: PhysicalLaserFrameBroker.Frame?) {
        currentFrame=frame?.streamEpoch == frames.streamEpoch ? frame:nil
    }
    func publishFrame(_ image: CGImage, frame: PhysicalLaserFrameBroker.Frame?, cameraID: String,
                      context: String, reference: BoardCalibration?, current: BoardCalibration?, hand: Bool?, aligned: Bool) {
        guard enabled || mayHaveIlluminated || mayHaveMotorSession,let frame else {return}
        frames.offer(image,frame:frame,cameraID:cameraID,context:context,reference:reference,current:current,hand:hand,aligned:aligned)
    }
    func suppress(_ why: String) {
        guard target != nil else {return}
        resetHandRecoveryEvidence()
        // Recoverable hand/capture observations must not downgrade an existing
        // different latch, including camera/lease faults with stricter recovery.
        if ["hand_entered_board","capture_evidence_changed"].contains(why),suppressed,reason != why {return}
        suppressed=true;reason=why;targetEmptyAt=nil;emptyEvidenceAfter=uptime();tick()
    }
    func showAgain() {
        guard enabled,(target != nil || standbyFault != nil),let clearAt,(0..<1.5).contains(uptime()-clearAt) else {return}
        if controllerResetRequired {
            guard let driver,fullOff(driver,wall:wallTime()),driver.requiresNewRevision != true,
                  driver.reasonCode != "controller_fault" else {return}
            controllerResetRequired=false
        }
        if standbyFault != nil {standbyFault=nil;holdingInterrupted=false;standbyReady=false;closingStandby=wireSchema==2}
        targetEmptyAt=nil;emptyEvidenceAfter=uptime()
        resetHandRecoveryEvidence()
        blockedMove=nil;suppressed=false;reason="explicit_show_again";sequence+=1;tick()
    }
    private func latchStandby(_ why: String) {
        if why=="controller_fault" {standbyFault=why;controllerResetRequired=true}
        else if standbyFault == nil {standbyFault=why}
        holdingInterrupted=true;standbyReady=false
        targetEmptyAt=nil;emptyEvidenceAfter=uptime()
    }
    private func fullOff(_ status: DriverStatus, wall: Double) -> Bool {
        status.producer==producer && status.sequence==sequence && status.schemaVersion==wireSchema &&
        (0..<0.75).contains(wall-status.updatedAtUnix) && ["hardware","simulation"].contains(status.mode) &&
        status.state=="off" && !status.laserOn && status.offSinceUnix.map {$0.isFinite && $0<=status.updatedAtUnix} == true &&
        (status.schemaVersion==1 || (status.mode=="hardware" && status.motorsHeld==false && status.motorBusPowered==false))
    }
    private func matchedStandby(_ status: DriverStatus) -> Bool {
        status.schemaVersion==2 && status.capabilities?.contains("darkMotorStandbyV1")==true &&
        playSession != nil && status.playSession==playSession && cameraContext != nil && status.cameraContext==cameraContext &&
        status.streamEpoch==frames.streamEpoch && standbySetup != nil && status.setupId==standbySetup
    }
    /// Darkness permits recognition; only a genuine full OFF permits shutdown.
    /// Powered darkness also requires a fresh thermal sample and exact session,
    /// camera, setup and optical watermark. A request is never an acknowledgement.
    func acceptsObservation(capturedAt: Double, now: Double,requireDarkEvidence: Bool=false)->Bool {
        guard mayHaveIlluminated || mayHaveMotorSession || requireDarkEvidence else {return true}
        let wall=wallTime()
        guard let driver,driver.producer==producer,driver.sequence==sequence,
              driver.schemaVersion==wireSchema,(0..<0.75).contains(wall-driver.updatedAtUnix),
              !driver.laserOn else {return false}
        let off: Double
        let watermark: EvidenceAfter?
        if fullOff(driver,wall:wall),let since=driver.offSinceUnix {
            off=since;watermark=driver.evidenceAfter
        } else {
            guard matchedStandby(driver),driver.mode=="hardware",driver.requiresNewRevision != true,
                  driver.motorBusPowered==true,
                  (driver.state=="holding" && driver.motorsHeld==true || driver.state=="cooling" && driver.motorsHeld==false),
                  driver.thermal?.admissible(statusAge:wall-driver.updatedAtUnix,updatedAtUnix:driver.updatedAtUnix)==true,
                  let since=driver.beamOffSinceUnix,since.isFinite else {return false}
            off=since;watermark=driver.darkEvidenceAfter
        }
        guard off<=driver.updatedAtUnix,wall-(now-capturedAt)>=off+0.3 else {return false}
        if driver.mode == "hardware" {
            guard let frame=currentFrame,let watermark,
                  frame.streamEpoch==frames.streamEpoch,frame.streamEpoch==watermark.streamEpoch,
                  frame.frameID>watermark.frameID,abs(frame.capturedAtUptime-capturedAt)<0.000001,
                  frame.timestampSource==watermark.timestampSource else {return false}
            let delay: Double
            if frame.timestampSource == "cameraPresentation" {delay=0.3}
            else if frame.timestampSource == "callback",let bound=watermark.callbackFlushSeconds,bound.isFinite,bound>=0.3 {delay=bound}
            else {return false}
            guard frame.capturedAtUnix>=off+delay else {return false}
        } else if driver.mode != "simulation" {return false}
        if !enabled,fullOff(driver,wall:wall) {mayHaveIlluminated=false;mayHaveMotorSession=false}
        return true
    }
    private func updateMotorDisplay(wall: Double) {
        guard let driver,driver.producer==producer,
              (driver.sequence==sequence || holdingInterrupted),
              (0..<0.75).contains(wall-driver.updatedAtUnix) else {
            motorMessage=mayHaveMotorSession ? "Waiting for motor status":"Motor holding is off"
            temperatureMessage="Temperature unavailable";return
        }
        motorMessage=driver.state=="holding" && driver.motorsHeld==true && !driver.laserOn ? "Holding · laser off":
            driver.state=="cooling" && driver.motorsHeld==false && !driver.laserOn ? "Cooling · motors released":
            fullOff(driver,wall:wall) ? "Motors off":driver.motorBusPowered==true ? "Motors active": "Motor status unavailable"
        if holdingInterrupted {motorMessage=controllerResetRequired ? "Controller stopped; reset required":"Motor holding stopped · check the driver before retrying"}
        guard driver.motorBusPowered==true,driver.state != "off",let t=driver.thermal,t.fresh(statusAge:wall-driver.updatedAtUnix,updatedAtUnix:driver.updatedAtUnix),let base=t.baseC,let tilt=t.tiltC else {
            temperatureMessage="Temperature unavailable";return
        }
        func axis(_ name:String,_ current:Double,_ maximum:Double?,_ trend:Double?) -> String {
            var result=String(format:"%@ %.0f°C",name,current)
            if let maximum,maximum.isFinite {result+=String(format:" · max %.0f°C",maximum)}
            if let trend,trend.isFinite {result+=String(format:" · %+.1f°C/min",trend)}
            return result
        }
        temperatureMessage=axis("Base",base,t.maxBaseC,t.baseTrendCPerMinute)+"\n"+axis("Tilt",tilt,t.maxTiltC,t.tiltTrendCPerMinute)
    }
    func tick() {
        guard enabled || mayHaveIlluminated || mayHaveMotorSession || timer != nil else {return}
        // Read one status snapshot before sampling its age. The driver can
        // atomically publish a newer timestamp during our IO; comparing that
        // to an earlier clock sample falsely looks like a future/dropped driver.
        driver=try? JSONDecoder().decode(DriverStatus.self,from:Data(contentsOf:directory.appendingPathComponent("status.json")))
        let now=uptime(),wall=wallTime()
        // Unexpected or uncertain light still contaminates buffered camera
        // frames. Keep optical OFF/flush gating even if we requested only dark
        // holding, and even if this is the previous revision awaiting stop.
        if let d=driver,d.producer==producer,d.mode=="hardware",d.laserOn,
           (0..<0.75).contains(wall-d.updatedAtUnix) {mayHaveIlluminated=true}
        let clear=clearAt.map {(0..<1.5).contains(now-$0)} == true
        let connected=driver.map {$0.schemaVersion==wireSchema && $0.producer==producer && (wireSchema==2 ? $0.mode=="hardware":["hardware","simulation"].contains($0.mode)) && (0..<0.75).contains(wall-$0.updatedAtUnix)} == true
        standbyAvailable=connected && driver?.mode=="hardware" && driver?.capabilities?.contains("darkMotorStandbyV1")==true
        let wantsStandby=enabled && standbyEnabled && playSession != nil
        if wantsStandby,standbyAvailable,driver?.sequence==sequence,driver?.state=="fault" || driver?.requiresNewRevision==true {
            latchStandby(driver?.reasonCode ?? "driver_interrupted")
        }
        if wireSchema==2 {
            if connected,driver?.sequence==sequence,
               driver?.state=="fault" || driver?.requiresNewRevision==true {latchStandby(driver?.reasonCode ?? "driver_interrupted")}
            if mayHaveMotorSession,!connected {latchStandby("driver_link_lost")}
            if mayHaveMotorSession,connected,driver?.sequence==sequence,!standbyAvailable {latchStandby("standby_capability_lost")}
            if mayHaveMotorSession,let began=armingStartedAt,now-began>=12,
               !coldAdmissionConfirmed || driver?.state=="arming" {latchStandby("arming_timeout")}
            if connected,let d=driver,d.sequence==sequence,d.state=="arming",
               d.laserOn || d.illuminationConfirmed==true || d.offSinceUnix != nil || d.evidenceAfter != nil ||
               d.beamOffSinceUnix != nil || d.darkEvidenceAfter != nil {latchStandby("invalid_arming_status")}
            if connected,let d=driver,d.sequence==sequence,
               ["holding","cooling","approaching","adequate","refining","spot_not_found"].contains(d.state) || d.laserOn || d.illuminationConfirmed==true {
                if d.thermal?.admissible(statusAge:wall-d.updatedAtUnix,updatedAtUnix:d.updatedAtUnix) != true {
                    latchStandby("thermal_telemetry_unavailable")
                } else {coldAdmissionConfirmed=true}
            }
            if connected,let d=driver,d.sequence==sequence {
                let activeStates=["arming","holding","cooling","approaching","adequate","refining","spot_not_found"]
                if activeStates.contains(d.state) {
                    if !matchedStandby(d) {latchStandby("standby_context_changed")}
                    if d.state=="holding",d.laserOn || d.motorsHeld != true || d.motorBusPowered != true {latchStandby("invalid_motor_status")}
                    if d.state=="cooling",d.laserOn || d.motorsHeld != false || d.motorBusPowered != true {latchStandby("invalid_motor_status")}
                    if !["arming","holding","cooling"].contains(d.state),d.motorBusPowered != true {latchStandby("invalid_motor_status")}
                } else if d.state=="off" {
                    if !fullOff(d,wall:wall) {latchStandby("invalid_off_status")}
                } else if d.state != "fault" {latchStandby("unknown_driver_state")}
            }
            if let d=driver,fullOff(d,wall:wall) {
                mayHaveMotorSession=false;armingStartedAt=nil;coldAdmissionConfirmed=false
                if closingStandby || !wantsStandby {
                    wireSchema=1;standbyReady=false;closingStandby=false;standbySetup=nil;sequence+=1
                } else if standbyAvailable,d.playSession==playSession,
                          let setup=d.setupId,!setup.isEmpty {
                    standbyReady=true;standbySetup=setup
                }
            }
        }
        let currentFault=connected && driver?.sequence==sequence && (driver?.state == "fault" || driver?.requiresNewRevision == true)
        if target != nil,currentFault {
            let code=driver?.reasonCode ?? ""
            let transient=["camera_frame_stale","request_lease_expired"].contains(code) &&
                (!suppressed || ["hand_entered_board","camera_frame_stale","request_lease_expired","driver_link_lost"].contains(reason))
            suppressed=true;reason=transient ? code:"driver_interrupted"
            resetHandRecoveryEvidence()
            // A lease can expire during an existing OFF/recovery request. With
            // no point→off transition below, that rejected revision would be
            // renewed forever. Advance only the classified transient OFF
            // handshake; fresh confirmed-dark evidence must still rearm it.
            if transient,lastAction=="off" {
                sequence+=1;targetEmptyAt=nil;emptyEvidenceAfter=now
            }
        } else if target != nil,lastAction == "point",!connected {
            suppressed=true;reason="driver_link_lost";resetHandRecoveryEvidence()
        }
        // A missed status is not a diagnosis. A returning driver may explicitly
        // identify lease expiry after confirming OFF; arbitrary faults stay latched.
        if target != nil,suppressed,reason=="driver_link_lost",connected,
           driver?.sequence==sequence,driver?.state=="off",driver?.laserOn==false,
           driver?.requiresNewRevision != true,driver?.reasonCode=="request_lease_expired" {
            reason="request_lease_expired";resetHandRecoveryEvidence()
        }
        // Once marking, the beam itself prevents useful empty classification.
        // Keep that operation until OFF, then require new dark empty evidence.
        let empty=(lastAction=="point" && targetEmptyAt != nil) || targetEmptyAt.map {(0..<1.5).contains(now-$0)} == true
        let capability=target?.purpose=="centering" ? "stoneCenteringWiggle":target?.purpose=="capture" ? "capturedStoneIndication":nil
        let capable=capability.map {driver?.capabilities?.contains($0)==true} ?? true
        if target?.purpose=="capture" {
            if captureWireSupported != capable {sequence+=1;captureWireSupported=capable}
        } else {captureWireSupported=nil}
        var action=enabled && connected && capable && standbyFault==nil && target != nil && !suppressed && clear && empty ? "point":"off"
        var retainOnly: Bool?
        if wireSchema==1,wantsStandby,standbyAvailable {
            action="off"
            if standbyFault==nil,let d=driver,fullOff(d,wall:wall) {
                wireSchema=2;standbyReady=false;sequence+=1
                targetEmptyAt=nil;emptyEvidenceAfter=now
            }
        }
        if wireSchema==2 {
            let cameraFresh=cameraAt.map {(0..<0.7).contains(now-$0)}==true
            let matchedTarget=target.map {$0.source==playSession?.source && $0.session==playSession?.session && $0.size==playSession?.size} ?? true
            let admitted=wantsStandby && !closingStandby && standbyReady && standbyAvailable && standbyFault==nil && cameraFresh && matchedTarget
            if !admitted {action="off"}
            else if action != "point" {
                // A hand may retain an already held pose only. The host also
                // checks its own broker observation and may fall back full OFF.
                action="standby";retainOnly=cameraHand != false
            }
        }
        if retainOnly != lastRetainOnly {sequence+=1;lastRetainOnly=retainOnly}
        if action != lastAction {
            if action != "point" {targetEmptyAt=nil;emptyEvidenceAfter=now}
            sequence+=1;lastAction=action
        }
        if action == "point" {mayHaveIlluminated=true}
        if wireSchema==2,action != "off" {
            if armingStartedAt==nil {armingStartedAt=now}
            mayHaveMotorSession=true
        }
        // Click at first confirmed illumination, before the silent settling.
        // laserOn alone can also mean unknown output, so require the driver's
        // positive acknowledgement rather than announcing during dark arming.
        if action=="point",let target,target.purpose==nil,let driver,connected,
           driver.sequence==sequence,driver.mode=="hardware",driver.laserOn,
           driver.illuminationConfirmed == true,
           ["approaching","adequate","refining"].contains(driver.state),driver.requiresNewRevision != true {
            if indicatedSession != target.session {indicatedSession=target.session;indicatedMoves=[]}
            if indicatedMoves.insert(target.id).inserted {onTargetIndicated?(target)}
        }
        let request=Request(schemaVersion:wireSchema,producer:producer,sequence:sequence,sentAtUnix:wall,expiresAtUnix:wall+0.6,
                            action:action,reason:!clear && enabled ? "camera_unverified":enabled && target==nil && alignmentPreparation != nil ? "ai_thinking":reason,
                            target:(wireSchema==2 && action=="off") || action=="standby" || target?.purpose=="capture" && !capable ? nil:target,cameraContext:cameraContext,streamEpoch:frames.streamEpoch,
                            alignmentPreparation:enabled && !(wireSchema==2 && action=="off") ? alignmentPreparation:nil,
                            playSession:wireSchema==2 ? playSession:nil,retainOnly:retainOnly)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try JSONEncoder().encode(request).write(to:directory.appendingPathComponent("request.json"),options:.atomic)
            onRequestPublished?(request)
            if let driver,driver.schemaVersion==wireSchema,driver.producer==producer,driver.sequence==sequence,
               (0..<0.75).contains(wall-driver.updatedAtUnix) {
                message=(driver.mode == "simulation" ? "Simulation · ":"Laser · ")+driver.detail
            } else {message=enabled ? "Waiting for laser driver · screen marker available":"Laser off requested · waiting for acknowledgement"}
            if recoveringCamera {message=reason=="request_lease_expired"
                ? "Laser heartbeat interrupted · checking fresh clear frames to restore the pending move"
                : "Camera delayed · waiting for fresh clear frames to restore the pending move"}
        } catch {driver=nil;message="Laser bridge unavailable: \(error.localizedDescription)"}
        updateMotorDisplay(wall:wall)
        if !enabled,(!mayHaveIlluminated && !mayHaveMotorSession) || driver.map({fullOff($0,wall:wall)}) == true {
            mayHaveMotorSession=false
            timer?.cancel();timer=nil
        }
        // Continue renewing OFF while awaiting acknowledgement. On app loss the
        // driver must expire the lease independently, even if its own HB runs.
    }
}
