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
    struct HardFault {
        let session: PlaySession
        let requestSequence: Int
        let reason: String
        let detectedAtUptime: Double
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
        var controllerSession: String?
        var controllerGeneration: Int?
        var controllerEpoch: Int?
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
    struct EvidenceAfter: Codable, Equatable {
        let streamEpoch: UUID
        let frameID: UInt64
        let timestampSource: String
        var callbackFlushSeconds: Double?
    }
    /// Immutable actual optical source evidence. Status heartbeats describe
    /// driver liveness; they cannot renew these timestamps or a move's cue.
    struct OpticalEvidence:Codable {
        let policy:String,producer:UUID,requestSequence:Int,target:Target
        let cameraContext:String,streamEpoch:UUID,frameID:UInt64
        let capturedAtUptime:Double,arrivedAtUptime:Double,capturedAtUnix:Double,publishedAtUnix:Double
        let expiresAtUptime:Double,expiresAtUnix:Double
        let controllerSession:String,controllerGeneration:Int
        func current(now:Double,wall:Double,producer:UUID,sequence:Int,target:Target,
                     context:String?,epoch:UUID,thermal:ThermalStatus?,schema:Int)->Bool {
            guard policy=="captured_optical_result_v1",self.producer==producer,
                  requestSequence==sequence,self.target==target,cameraContext==context,
                  streamEpoch==epoch,
                  [capturedAtUptime,arrivedAtUptime,capturedAtUnix,publishedAtUnix,
                   expiresAtUptime,expiresAtUnix,now,wall].allSatisfy({$0.isFinite}),
                  [now-capturedAtUptime,now-arrivedAtUptime,wall-capturedAtUnix,wall-publishedAtUnix]
                    .allSatisfy({(0...0.6).contains($0)}),
                  expiresAtUptime==min(capturedAtUptime,arrivedAtUptime)+0.6,
                  expiresAtUnix==min(capturedAtUnix,publishedAtUnix)+0.6,
                  now<=expiresAtUptime,wall<=expiresAtUnix,
                  controllerSession.count==8,controllerSession.allSatisfy({"0123456789ABCDEF".contains($0)}),
                  (1...0xffffffff).contains(controllerGeneration) else {return false}
            // Schema2 additionally binds the proof to the current monitored
            // controller; state-epoch advances do not rewrite pixel evidence.
            return schema != 2 || (thermal?.controllerSession==controllerSession &&
                                   thermal?.controllerGeneration==controllerGeneration)
        }
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
        var opticalEvidence: OpticalEvidence?
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
    @Published private(set) var gameFaultNeedsRecheck=false
    private(set) var gameFaultRecheckReason:String?
    private var notifiedHardFault: String?
    private struct ManualDarkBarrier {
        let session: PlaySession
        let context: String
        let epoch: UUID
        let frameID: UInt64
        let uptime: Double
        let wall: Double
    }
    private var manualDarkBarrier: ManualDarkBarrier?
    private typealias Recovery=PhysicalGuidanceRecovery<PlaySession,Target,EvidenceAfter>
    private static let transientReasons=Recovery.Cause.allCases.map(\.rawValue)
    private var transientRecovery=Recovery()
    private var recoveryScope:Recovery.Scope {
        .init(schema:wireSchema,session:playSession,context:cameraContext,epoch:frames.streamEpoch)
    }
    private func recoveryOperation(_ target:Target?)->Recovery.Operation {
        .init(target:target,owner:target.map {PlaySession(source:$0.source,session:$0.session,size:$0.size)})
    }
    private(set) var playSession: PlaySession?
    private var motorAdmission=PhysicalMotorAdmission()
    var mayHaveMotorSession:Bool {motorAdmission.mayHaveMotorSession}
    private(set) var admissionBlocker:PhysicalMotorAdmission.Blocker?
    private var lastAdmissionTraceKey:String?
    private var wireSchema=1
    private var awaitingFaultResume=false
    private var standbyReady=false
    private var closingStandby=false
    private var standbyFault: String?
    private var standbySetup: String?
    private var unresolvedLinkLoss: (session:PlaySession,sequence:Int,since:Double)?
    private var lastRetainOnly: Bool?
    private var cameraAt: Double?
    private var cameraHand: Bool?
    var recoveringCamera:Bool {enabled && (transientRecovery.isPending || target != nil && suppressed && ["camera_frame_stale","request_lease_expired"].contains(reason))}
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
    private var lastLatencyDriverKey:String?
    private var reason="disabled"
    private var blockedMove:(session:UUID,number:Int,reason:String)?
    private var mayHaveIlluminated=false
    private var captureWireSupported:Bool?
    private var driver: DriverStatus?
    var onHardFault: ((HardFault)->Void)?
    var onTargetIndicated: ((Target)->Void)?
    var onRequestPublished: ((Request)->Void)?
    private var indicatedSession: UUID?
    private var indicatedMoves=Set<String>()
    private let wallTime: ()->Double
    private let uptime: ()->Double
    private let automatic: Bool
    private lazy var fileExchange:LatestFileExchange<Request> = {
        let directory=self.directory
        return LatestFileExchange(read:{
            let began=ProcessInfo.processInfo.systemUptime
            let data=try? Data(contentsOf:directory.appendingPathComponent("status.json"))
            let duration=ProcessInfo.processInfo.systemUptime-began
            if duration>=0.02 {PhysicalLatencyTrace.shared?.record("bridge_status_read",metrics:["readSeconds":duration])}
            return data
        },write:{request in
            try Self.writeRequest(request,directory:directory)
        },completed:{[weak self] request,error in
            DispatchQueue.main.async {
                guard let self else {return}
                if let error {
                    guard request.sequence==self.sequence else {return}
                    self.driver=nil;self.message="Laser bridge unavailable: \(error.localizedDescription)"
                } else {self.onRequestPublished?(request)}
            }
        })
    }()
    nonisolated private static func writeRequest(_ request:Request,directory:URL)throws {
        let began=ProcessInfo.processInfo.systemUptime
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        // Preserve the main-thread decision's sent/expiry times, even if IO is
        // delayed. The driver independently rejects expired requests.
        try EphemeralAtomicFile.write(JSONEncoder().encode(request),to:directory.appendingPathComponent("request.json"))
        PhysicalLatencyTrace.shared?.record("request_published",fields:[
            "producer":request.producer.uuidString,"sequence":String(request.sequence),
            "action":request.action,"reason":request.reason],metrics:[
                "writeSeconds":ProcessInfo.processInfo.systemUptime-began,
                "decisionAgeSeconds":Date().timeIntervalSince1970-request.sentAtUnix])
    }
    init(directory: URL? = nil, automatic: Bool = true,
         wallTime: @escaping ()->Double = {Date().timeIntervalSince1970},
         uptime: @escaping ()->Double = {ProcessInfo.processInfo.systemUptime}) {
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Physical Go/LaserBridge")
        self.frames=PhysicalLaserFrameBroker(directory:self.directory.appendingPathComponent("frames"))
        self.automatic=automatic;self.wallTime=wallTime;self.uptime=uptime
    }
    /// Saved interruption metadata restores only the native retry requirement.
    /// It is not fresh hardware state, OFF evidence or a new fault notification.
    func restoreGameFaultRequirement(_ reason:String) {
        gameFaultNeedsRecheck=true;gameFaultRecheckReason=reason
        if reason=="controller_fault" {controllerResetRequired=true}
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
        // Explicit game suspension revokes transient proof. It is not a
        // contradictory camera scope or a retry of any retained hard fault.
        if value==nil,transientRecovery.isPending {
            transientRecovery.reduce(.cancel)
            if Self.transientReasons.contains(reason) {suppressed=false;reason="game_suspended"}
        }
        // A new game revokes the old lease, but is not a hardware-fault retry.
        if let value,let barrier=manualDarkBarrier,barrier.session != value {refreshManualDarkBarrier(session:value)}
        playSession=value;standbyReady=false
        if value != nil {awaitingFaultResume=false}
        motorAdmission.reduce(.playSessionChanged);unresolvedLinkLoss=nil
        targetEmptyAt=nil;emptyEvidenceAfter=uptime();sequence+=1;tick()
    }
    func setEnabled(_ value: Bool) {
        transientRecovery.reduce(.cancel)
        if value {manualDarkBarrier=nil}
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
        let retarget=transientRecovery.reduce(.retarget(recoveryScope,recoveryOperation(value),
            cause:Recovery.Cause(rawValue:reason),permitted:!gameFaultNeedsRecheck && !controllerResetRequired && standbyFault==nil,at:uptime()))
        if retarget == .requestOFF {
            target=value;suppressed=value != nil;targetEmptyAt=nil;emptyEvidenceAfter=uptime()
            resetHandRecoveryEvidence();sequence+=1;tick();return
        }
        if suppressed,let old=target,
           !(["hand_entered_board","stone_seen_at_target","capture_evidence_changed"]+Self.transientReasons).contains(reason) {
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
            refreshManualDarkBarrier(context:context);cameraAt=nil;cameraHand=nil;clearAt=nil;targetEmptyAt=nil
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
        if transientRecovery.isPending {
            let effect=transientRecovery.reduce(.verify(.init(enabled:enabled,hasTarget:target != nil,
                capturedAt:capturedAt,clearAt:clearAt,healthyOFF:driver.map {fullOff($0,wall:wallTime())}==true,
                frameAdmissible:enabled && acceptsObservation(capturedAt:capturedAt,now:now,requireDarkEvidence:true),now:now)))
            guard case .recovered=effect else {return}
            finishTransientRecovery(effect)
            targetEmptyAt=capturedAt;tick();return
        }
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
        frames.resetStream();currentFrame=nil;refreshManualDarkBarrier();cameraAt=nil;cameraHand=nil;clearAt=nil;sequence+=1
        if wireSchema==2 {latchStandby("camera_stream_changed")}
        resetHandRecoveryEvidence()
        targetEmptyAt=nil;emptyEvidenceAfter=uptime()
        if target != nil {suppressed=true;reason="camera_stream_changed"}
        tick()
    }
    /// Metadata-only lookup. Never substitute a newer broker frame for the
    /// observation being diagnosed, and never use this accessor for admission.
    func diagnosticFrame(capturedAt:Double)->PhysicalLaserFrameBroker.Frame? {
        guard capturedAt.isFinite,let frame=currentFrame,frame.streamEpoch==frames.streamEpoch,
              abs(frame.capturedAtUptime-capturedAt)<0.000001 else {return nil}
        return frame
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
        guard enabled,(target != nil || standbyFault != nil || gameFaultNeedsRecheck),let clearAt,(0..<1.5).contains(uptime()-clearAt) else {return}
        if controllerResetRequired || gameFaultNeedsRecheck {
            guard let driver,driver.mode=="hardware",fullOff(driver,wall:wallTime()),driver.requiresNewRevision != true,
                  driver.reasonCode != "controller_fault" else {return}
            if gameFaultNeedsRecheck {awaitingFaultResume=true}
            controllerResetRequired=false;gameFaultNeedsRecheck=false;gameFaultRecheckReason=nil
        }
        if standbyFault != nil {standbyFault=nil;holdingInterrupted=false;standbyReady=false;closingStandby=wireSchema==2}
        transientRecovery.reduce(.cancel);targetEmptyAt=nil;emptyEvidenceAfter=uptime()
        resetHandRecoveryEvidence()
        blockedMove=nil;suppressed=false;reason="explicit_show_again";sequence+=1;tick()
    }
    /// Fault-paused games require an explicit native recheck plus a fresh
    /// healthy OFF receipt. This cannot reset firmware or start the game.
    func confirmPhysicalLaserOff(session:PlaySession)->Bool {
        guard !enabled,session.valid,let cameraContext else {return false}
        awaitingFaultResume=false
        manualDarkBarrier = .init(session:session,context:cameraContext,epoch:frames.streamEpoch,
            frameID:currentFrame?.frameID ?? 0,uptime:uptime(),wall:wallTime())
        return true
    }
    private func refreshManualDarkBarrier(session:PlaySession?=nil,context:String?=nil) {
        // The user's physical switch-off remains in force while guidance is
        // disabled. A new game/view must nevertheless earn its own fresh proof.
        guard !enabled,let old=manualDarkBarrier else {return}
        manualDarkBarrier = .init(session:session ?? old.session,context:context ?? cameraContext ?? old.context,
            epoch:frames.streamEpoch,frameID:currentFrame?.frameID ?? 0,uptime:uptime(),wall:wallTime())
    }
    private func manualDarkEvidence(capturedAt:Double,now:Double,session:UUID?=nil)->Bool {
        guard !enabled,let barrier=manualDarkBarrier,session==nil || session==barrier.session.session,
              barrier.context==cameraContext,barrier.epoch==frames.streamEpoch,
              let frame=currentFrame,frame.streamEpoch==barrier.epoch,frame.frameID>barrier.frameID,
              frame.timestampSource=="cameraPresentation",abs(frame.capturedAtUptime-capturedAt)<0.000001,
              (0..<1.5).contains(now-capturedAt),clearAt.map({abs($0-capturedAt)<0.000001})==true,
              frame.capturedAtUptime>=barrier.uptime+0.3,frame.capturedAtUnix>=barrier.wall+0.3 else {return false}
        return true
    }
    func readyToResumeFaultPausedGame(session:UUID)->Bool {
        if !enabled,manualDarkBarrier != nil,let frame=currentFrame {
            return manualDarkEvidence(capturedAt:frame.capturedAtUptime,now:uptime(),session:session)
        }
        guard !gameFaultNeedsRecheck,!controllerResetRequired,!holdingInterrupted,
              let clearAt,(0..<1.5).contains(uptime()-clearAt),let driver,
              driver.mode=="hardware",fullOff(driver,wall:wallTime()),driver.requiresNewRevision != true,
              driver.reasonCode != "controller_fault" else {return false}
        if enabled {return true}
        // Explicit recheck can also be followed by disabling guidance. Resume
        // then verifies the board in darkness without asserting a physical
        // switch-off or authorizing the still-pending placement cue.
        guard let frame=currentFrame,abs(frame.capturedAtUptime-clearAt)<0.000001 else {return false}
        return acceptsObservation(capturedAt:frame.capturedAtUptime,now:uptime(),requireDarkEvidence:true)
    }
    private func currentHardFaultScope(_ d:DriverStatus?,wall:Double)->PlaySession? {
        guard enabled,let d,d.mode=="hardware",d.producer==producer,d.sequence==sequence,
              d.schemaVersion==wireSchema,(0..<0.75).contains(wall-d.updatedAtUnix),
              let session=playSession,session.valid else {return nil}
        if wireSchema==2 {
            // Capability withdrawal may itself be the fault; identity is still
            // mandatory. A malformed or unrelated status cannot pause a game.
            guard d.playSession==session,d.cameraContext==cameraContext,cameraContext != nil,
                  d.streamEpoch==frames.streamEpoch,let standbySetup,d.setupId==standbySetup else {return nil}
        } else {
            // Legacy status has no session echo. The producer/revision binds
            // the native session: setPlaySession always advances the revision.
            if let target,target.session != session.session || target.source != session.source || target.size != session.size {return nil}
            if let p=alignmentPreparation,p.session != session.session || p.size != session.size {return nil}
        }
        return session
    }
    private func latchStandby(_ why: String) {
        transientRecovery.reduce(.cancel)
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
    private func matchedTransition(_ status:DriverStatus)->Bool {
        if matchedStandby(status) {return true}
        // A cold schema2 OFF replacement can report uncertain output before
        // its first confirmed OFF supplies the setup identity. Accept only
        // liveness for the exact current scope; do not adopt this setup, grant
        // motor admission or treat the transition as darkness. The same3s
        // deadline still bounds the wait, including a nullable closing scope.
        if lastAction=="off",!standbyReady,!mayHaveMotorSession,standbySetup==nil,
           status.schemaVersion==2,status.capabilities?.contains("darkMotorStandbyV1")==true,
           status.playSession==playSession,cameraContext != nil,status.cameraContext==cameraContext,
           status.streamEpoch==frames.streamEpoch,status.setupId.map({!$0.isEmpty})==true {return true}
        // Pause revokes the play session before its OFF acknowledgement. The
        // host can report an uncertain, bounded handoff for this nullable scope.
        return closingStandby && lastAction=="off" && playSession==nil && status.playSession==nil &&
            status.schemaVersion==2 && status.capabilities?.contains("darkMotorStandbyV1")==true &&
            cameraContext != nil && status.cameraContext==cameraContext && status.streamEpoch==frames.streamEpoch &&
            standbySetup != nil && status.setupId==standbySetup
    }
    /// Darkness permits recognition; only a genuine full OFF permits shutdown.
    /// Powered darkness also requires a fresh thermal sample and exact session,
    /// camera, setup and optical watermark. A request is never an acknowledgement.
    func acceptsObservation(capturedAt: Double, now: Double,requireDarkEvidence: Bool=false)->Bool {
        if !enabled,manualDarkBarrier != nil {return manualDarkEvidence(capturedAt:capturedAt,now:now)}
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
        if !enabled,fullOff(driver,wall:wall) {mayHaveIlluminated=false;motorAdmission.reduce(.releasePossibleSession)}
        return true
    }
    private func updateMotorDisplay(wall: Double) {
        guard let driver,driver.producer==producer,
              (driver.sequence==sequence || holdingInterrupted),
              (0..<0.75).contains(wall-driver.updatedAtUnix) else {
            motorMessage=mayHaveMotorSession ? "Waiting for motor status":"Motor holding is off"
            temperatureMessage="Temperature unavailable";return
        }
        motorMessage=driver.state=="transitioning" ? "Changing laser mode · waiting for confirmation":
            driver.state=="holding" && driver.motorsHeld==true && !driver.laserOn ? "Holding · laser off":
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
    private func beginTransientRecovery(_ d:DriverStatus?,now:Double,wall:Double) {
        guard enabled,!gameFaultNeedsRecheck,!controllerResetRequired,
              let d,d.producer==producer,d.sequence==sequence,d.schemaVersion==wireSchema,
              ["hardware","simulation"].contains(d.mode),(0..<0.75).contains(wall-d.updatedAtUnix),
              let code=d.reasonCode,Self.transientReasons.contains(code),
              d.state=="fault" || d.requiresNewRevision==true || (d.state=="off" && (reason=="driver_link_lost" || standbyFault=="driver_link_lost")),
              cameraContext != nil,blockedMove==nil,
              standbyFault==nil || standbyFault=="driver_link_lost",
              !suppressed || (["hand_entered_board","capture_evidence_changed","driver_link_lost"]+Self.transientReasons).contains(reason) else {return}
        if wireSchema==2 {guard currentHardFaultScope(d,wall:wall) != nil else {return}}
        guard playSession != nil || target != nil else {return}
        transientRecovery.reduce(.begin(recoveryScope,recoveryOperation(target),setup:d.setupId,
            cause:Recovery.Cause(rawValue:code)!,at:now))
        standbyFault=nil;holdingInterrupted=false;suppressed=target != nil;reason=code
        targetEmptyAt=nil;emptyEvidenceAfter=now;resetHandRecoveryEvidence()
        // A rejected revision cannot be renewed. This one-time OFF revision
        // obtains independent healthy evidence; the host need not echo the cause.
        sequence+=1
    }
    private func advanceTransientRecovery(now:Double,wall:Double) {
        guard transientRecovery.isPending else {return}
        var receipt:Recovery.Receipt?
        if !gameFaultNeedsRecheck,!controllerResetRequired,standbyFault==nil,
           let d=driver,fullOff(d,wall:wall),d.requiresNewRevision != true,
           d.reasonCode==nil || Self.transientReasons.contains(d.reasonCode!) {
            receipt = .init(scope:.init(schema:d.schemaVersion,session:d.playSession,context:d.cameraContext,
                epoch:d.streamEpoch),setup:d.setupId,offSince:d.offSinceUnix,watermark:d.evidenceAfter)
        }
        let effect=transientRecovery.reduce(.observe(.init(scope:recoveryScope,target:target,enabled:enabled,
            cause:Recovery.Cause(rawValue:reason),receipt:receipt,clearAt:clearAt,
            frameAdmissible:enabled && clearAt.map {acceptsObservation(capturedAt:$0,now:now,requireDarkEvidence:true)}==true,now:now)))
        if effect == .scopeChanged {
            suppressed=target != nil;reason="recovery_scope_changed"
            if wireSchema==2 {latchStandby("recovery_scope_changed")}
        } else {finishTransientRecovery(effect)}
    }
    private func finishTransientRecovery(_ effect:Recovery.Effect) {
        guard case let .recovered(stamp,cause)=effect else {return}
        suppressed=false;reason=cause.recoveredReason
        targetEmptyAt=nil;emptyEvidenceAfter=stamp;resetHandRecoveryEvidence()
    }
    func tick() {
        guard enabled || mayHaveIlluminated || mayHaveMotorSession || awaitingFaultResume || timer != nil else {return}
        // Read one status snapshot before sampling its age. The driver can
        // atomically publish a newer timestamp during our IO; comparing that
        // to an earlier clock sample falsely looks like a future/dropped driver.
        let trace=PhysicalLatencyTrace.shared
        let readBegan=trace == nil ? 0:ProcessInfo.processInfo.systemUptime
        // Automatic/live mode never waits for filesystem IO on the camera/UI
        // thread. Deterministic manual ticks retain synchronous IO for offline tests.
        let statusData=automatic ? fileExchange.latest() : (try? Data(contentsOf:directory.appendingPathComponent("status.json")))
        driver=statusData.flatMap {try? JSONDecoder().decode(DriverStatus.self,from:$0)}
        let now=uptime(),wall=wallTime()
        if let trace {
            let d=driver
            let key="\(d?.producer.uuidString ?? "none")/\(d?.sequence ?? -1)/\(d?.state ?? "unavailable")/\(d?.reasonCode ?? "")/\(d?.illuminationConfirmed == true)"
            let duration=ProcessInfo.processInfo.systemUptime-readBegan
            if key != lastLatencyDriverKey || duration>=0.02 {
                trace.record("driver_status_observed",fields:["producer":d?.producer.uuidString ?? producer.uuidString,
                    "sequence":String(d?.sequence ?? -1),"state":d?.state ?? "unavailable",
                    "reason":d?.reasonCode ?? "none","illuminationConfirmed":String(d?.illuminationConfirmed == true)],
                    metrics:["readSeconds":duration,"statusWallAgeSeconds":d.map {wall-$0.updatedAtUnix} ?? -1])
                lastLatencyDriverKey=key
            }
        }
        let faultScope=currentHardFaultScope(driver,wall:wall)
        let statusAtEntry=driver
        var currentHealthFault:String?
        var admissionMonitor:PhysicalMotorAdmission.Monitor?
        var localLinkFault:HardFault?
        func hardHealth(_ code:String) {currentHealthFault=code;latchStandby(code)}
        // Unexpected or uncertain light still contaminates buffered camera
        // frames. Keep optical OFF/flush gating even if we requested only dark
        // holding, and even if this is the previous revision awaiting stop.
        if let d=driver,d.producer==producer,d.mode=="hardware",d.laserOn,
           (0..<0.75).contains(wall-d.updatedAtUnix) {mayHaveIlluminated=true}
        beginTransientRecovery(driver,now:now,wall:wall)
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
            if !transientRecovery.isPending,mayHaveMotorSession,!connected {
                if unresolvedLinkLoss==nil,enabled,let session=playSession,session.valid {
                    unresolvedLinkLoss=(session,sequence,now)
                }
                latchStandby("driver_link_lost")
                suppressed=target != nil;reason="driver_link_lost";resetHandRecoveryEvidence()
            }
            // A returned classified camera/lease fault enters the existing
            // recovery path above. An unexplained OFF or prolonged absence
            // cannot leave the game clock running behind a permanent OFF latch.
            if standbyFault != "driver_link_lost" {unresolvedLinkLoss=nil}
            if let lost=unresolvedLinkLoss,enabled,playSession==lost.session,
               !transientRecovery.isPending,!gameFaultNeedsRecheck,
               now-lost.since>=3 || (faultScope==lost.session && driver.map {fullOff($0,wall:wall)}==true) {
                localLinkFault = .init(session:lost.session,requestSequence:lost.sequence,
                    reason:"driver_link_lost",detectedAtUptime:now)
            }
            if connected,let d=driver,d.sequence==sequence,d.state=="transitioning" {
                if !matchedTransition(d) {latchStandby("standby_context_changed")}
                else if d.illuminationConfirmed != false || !d.laserOn || d.offSinceUnix != nil ||
                        d.evidenceAfter != nil || d.beamOffSinceUnix != nil || d.darkEvidenceAfter != nil {
                    hardHealth("invalid_transition_status")
                } else {
                    motorAdmission.reduce(.authenticatedTransition(at:now))
                    if motorAdmission.transitionTimedOut(now:now) {hardHealth("transition_timeout")}
                }
            } else if connected,let d=driver,d.sequence==sequence,matchedStandby(d),
                      ["off","arming","holding","cooling","approaching","adequate","refining","spot_not_found"].contains(d.state) {
                motorAdmission.reduce(.authenticatedNonTransition)
            }
            if mayHaveMotorSession,connected,driver?.sequence==sequence,!standbyAvailable {hardHealth("standby_capability_lost")}
            if connected,let d=driver,d.sequence==sequence,d.state=="arming" {
                if d.laserOn || d.illuminationConfirmed==true || d.offSinceUnix != nil || d.evidenceAfter != nil ||
                   d.beamOffSinceUnix != nil || d.darkEvidenceAfter != nil {hardHealth("invalid_arming_status")}
                else if !transientRecovery.isPending,matchedStandby(d) {
                    // A hand stop can end the host session between native
                    // samples. A later genuine cold admission gets its own
                    // bounded episode, not the age of the previous warm hold.
                    motorAdmission.reduce(.authenticatedArming(at:now))
                    // Arming never grants light or recognition authority. A
                    // bounded grace requires independent current camera and
                    // same-controller causal monitor liveness, not JSON ticks.
                    if currentHealthFault==nil,standbyFault==nil,!gameFaultNeedsRecheck,enabled,
                       cameraHand==false,cameraAt.map({(0..<0.7).contains(now-$0)})==true,
                       d.motorBusPowered==true,d.illuminationConfirmed==false,let t=d.thermal,
                       t.admissible(statusAge:wall-d.updatedAtUnix,updatedAtUnix:d.updatedAtUnix),
                       let session=t.controllerSession,let generation=t.controllerGeneration,
                       let epoch=t.controllerEpoch,let sample=t.sampleSequence,let age=t.sampleAgeUpperMs {
                        admissionMonitor = .init(session:session,generation:generation,epoch:epoch,sequence:sample,
                            acquiredAfter:now-((wall-d.updatedAtUnix)+age/1000))
                    }
                    motorAdmission.observeMonitor(admissionMonitor,now:now)
                }
            }
            if connected,let d=driver,d.sequence==sequence,
               ["holding","cooling","approaching","adequate","refining","spot_not_found"].contains(d.state) || (d.laserOn && !["fault","transitioning"].contains(d.state)) || (d.illuminationConfirmed==true && d.state != "transitioning") {
                if d.thermal?.admissible(statusAge:wall-d.updatedAtUnix,updatedAtUnix:d.updatedAtUnix) != true {
                    hardHealth("thermal_telemetry_unavailable")
                }
            }
            if connected,let d=driver,d.sequence==sequence {
                let activeStates=["arming","holding","cooling","approaching","adequate","refining","spot_not_found"]
                if activeStates.contains(d.state) {
                    if !matchedStandby(d) {latchStandby("standby_context_changed")}
                    if d.state=="holding",d.laserOn || d.motorsHeld != true || d.motorBusPowered != true {hardHealth("invalid_motor_status")}
                    if d.state=="cooling",d.laserOn || d.motorsHeld != false || d.motorBusPowered != true {hardHealth("invalid_motor_status")}
                    if !["arming","holding","cooling"].contains(d.state),d.motorBusPowered != true {hardHealth("invalid_motor_status")}
                } else if d.state=="off" {
                    if !fullOff(d,wall:wall) {hardHealth("invalid_off_status")}
                } else if !["fault","transitioning"].contains(d.state) {hardHealth("unknown_driver_state")}
                if currentHealthFault==nil,matchedStandby(d),
                   ["holding","cooling","approaching","adequate","refining","spot_not_found"].contains(d.state) {
                    motorAdmission.reduce(.authenticatedActive)
                }
            }
            if let d=driver,fullOff(d,wall:wall) {
                motorAdmission.reduce(.confirmedFullOFF)
                if closingStandby || !wantsStandby {
                    wireSchema=1;standbyReady=false;closingStandby=false;standbySetup=nil;sequence+=1
                } else if standbyAvailable,d.playSession==playSession,
                          let setup=d.setupId,!setup.isEmpty {
                    standbyReady=true;standbySetup=setup
                }
            }
            // Consume an authenticated terminal active/OFF receipt first. A
            // receipt arriving on the deadline ends that episode; it must not
            // be faulted based on bookkeeping from the previous tick.
            if motorAdmission.armingTimedOut(now:now,transientRecovery:transientRecovery.isPending,currentMonitor:admissionMonitor) {
                hardHealth("arming_timeout")
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
        advanceTransientRecovery(now:now,wall:wall)
        // Once marking, the beam itself prevents useful empty classification.
        // Keep that operation until OFF, then require new dark empty evidence.
        let empty=(lastAction=="point" && targetEmptyAt != nil) || targetEmptyAt.map {(0..<1.5).contains(now-$0)} == true
        let capability=target?.purpose=="centering" ? "stoneCenteringWiggle":target?.purpose=="capture" ? "capturedStoneIndication":nil
        let capable=capability.map {driver?.capabilities?.contains($0)==true} ?? true
        if target?.purpose=="capture" {
            if captureWireSupported != capable {sequence+=1;captureWireSupported=capable}
        } else {captureWireSupported=nil}
        var action=enabled && !transientRecovery.isPending && connected && capable && !gameFaultNeedsRecheck && !controllerResetRequired && standbyFault==nil && target != nil && !suppressed && clear && empty ? "point":"off"
        var retainOnly: Bool?
        if wireSchema==1,wantsStandby,standbyAvailable {
            action="off"
            if standbyFault==nil,let d=driver,fullOff(d,wall:wall) {
                wireSchema=2;standbyReady=false;sequence+=1
                targetEmptyAt=nil;emptyEvidenceAfter=now
            }
        }
        admissionBlocker=nil
        if wireSchema==2 {
            let cameraFresh=cameraAt.map {(0..<0.7).contains(now-$0)}==true
            let matchedTarget=target.map {$0.source==playSession?.source && $0.session==playSession?.session && $0.size==playSession?.size} ?? true
            admissionBlocker=PhysicalMotorAdmission.blocker(.init(requested:wantsStandby,
                transientRecovery:transientRecovery.isPending,gameRecheck:gameFaultNeedsRecheck,
                controllerReset:controllerResetRequired,closing:closingStandby,ready:standbyReady,
                available:standbyAvailable,fault:standbyFault,cameraFresh:cameraFresh,matchedTarget:matchedTarget))
            if admissionBlocker != nil {action="off"}
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
            motorAdmission.reduce(.motorRequest(at:now))
        }
        if let trace {
            let key=[String(wireSchema),admissionBlocker?.code ?? "admitted",standbyFault ?? "none",
                String(standbyReady),String(closingStandby),String(mayHaveMotorSession),action,standbySetup ?? "none",
                String(describing:motorAdmission.armingStartedAt),String(describing:motorAdmission.transitionStartedAt)].joined(separator:"/")
            if key != lastAdmissionTraceKey {
                trace.record("motor_admission",fields:["producer":producer.uuidString,"sequence":String(sequence),
                    "schema":String(wireSchema),"action":action,"blocker":admissionBlocker?.code ?? "none",
                    "standbyFault":standbyFault ?? "none","ready":String(standbyReady),"closing":String(closingStandby),
                    "possibleMotorSession":String(mayHaveMotorSession),"setup":standbySetup ?? "none"],
                    metrics:["armingAgeSeconds":motorAdmission.armingStartedAt.map {now-$0} ?? -1,
                             "transitionAgeSeconds":motorAdmission.transitionStartedAt.map {now-$0} ?? -1])
                lastAdmissionTraceKey=key
            }
        }
        // Announce the first optically accepted illuminated indication. Initial
        // acquisition flashes and refinement must not consume this move's cue.
        // laserOn alone can mean unknown output, so retain positive confirmation.
        if action=="point",let target,target.purpose==nil,let driver,connected,
           driver.sequence==sequence,driver.mode=="hardware",driver.laserOn,
           driver.illuminationConfirmed == true,
           driver.state=="adequate",driver.requiresNewRevision != true,
           driver.opticalEvidence?.current(now:now,wall:wall,producer:producer,sequence:sequence,
               target:target,context:cameraContext,epoch:frames.streamEpoch,thermal:driver.thermal,schema:wireSchema)==true {
            if indicatedSession != target.session {indicatedSession=target.session;indicatedMoves=[]}
            if indicatedMoves.insert(target.id).inserted {onTargetIndicated?(target)}
        }
        let request=Request(schemaVersion:wireSchema,producer:producer,sequence:sequence,sentAtUnix:wall,expiresAtUnix:wall+0.6,
                            action:action,reason:!clear && enabled ? "camera_unverified":enabled && target==nil && alignmentPreparation != nil ? "ai_thinking":reason,
                            target:(wireSchema==2 && action=="off") || action=="standby" || target?.purpose=="capture" && !capable ? nil:target,cameraContext:cameraContext,streamEpoch:frames.streamEpoch,
                            alignmentPreparation:enabled && !(wireSchema==2 && action=="off") ? alignmentPreparation:nil,
                            playSession:wireSchema==2 ? playSession:nil,retainOnly:retainOnly)
        do {
            if automatic {fileExchange.submit(request)}
            else {try Self.writeRequest(request,directory:directory);onRequestPublished?(request)}
            if let driver,driver.schemaVersion==wireSchema,driver.producer==producer,driver.sequence==sequence,
               (0..<0.75).contains(wall-driver.updatedAtUnix) {
                message=(driver.mode == "simulation" ? "Simulation · ":"Laser · ")+driver.detail
            } else {message=enabled ? "Waiting for laser driver · screen marker available":"Laser off requested · waiting for acknowledgement"}
            if recoveringCamera {message=reason=="request_lease_expired"
                ? "Laser heartbeat interrupted · checking fresh clear frames to restore the pending move"
                : "Camera delayed · waiting for fresh clear frames to restore the pending move"}
        } catch {driver=nil;message="Laser bridge unavailable: \(error.localizedDescription)"}
        updateMotorDisplay(wall:wall)
        if !enabled,!awaitingFaultResume,(!mayHaveIlluminated && !mayHaveMotorSession) || driver.map({fullOff($0,wall:wall)}) == true {
            motorAdmission.reduce(.releasePossibleSession)
            timer?.cancel();timer=nil
        }
        // Capture provenance before OFF changes the request revision; notify
        // synchronously after submitting OFF. The AI owner pauses before
        // a queued engine result can commit, and sets phase before reentry here.
        var notification=localLinkFault
        if let session=faultScope,let d=statusAtEntry {
            // Host unclassified failures can include normal hand/alignment
            // races. Only explicit hard classification pauses the local game.
            let hardReasons=["controller_fault","laser_transport_fault","laser_setup_fault","laser_optical_fault","laser_operation_fault"]
            let reported=(d.state=="fault" || d.requiresNewRevision==true) && d.reasonCode.map {hardReasons.contains($0)}==true
            if reported || currentHealthFault != nil {
                let code=reported ? (d.reasonCode ?? "driver_interrupted"):currentHealthFault!
                notification = .init(session:session,requestSequence:d.sequence,reason:code,detectedAtUptime:now)
            }
        }
        if let event=notification {
            let identity="\(event.session.source)/\(event.session.session)/\(event.requestSequence)/\(event.reason)"
            if notifiedHardFault != identity {
                notifiedHardFault=identity;gameFaultNeedsRecheck=true;gameFaultRecheckReason=event.reason;manualDarkBarrier=nil
                if event.reason=="controller_fault" {controllerResetRequired=true}
                onHardFault?(event)
            }
        }
        // Continue renewing OFF while awaiting acknowledgement. On app loss the
        // driver must expire the lease independently, even if its own HB runs.
    }
}
