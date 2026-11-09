import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import Combine

enum PhysicalPlayMode: String, CaseIterable {
    case local, online
    var title: String { self == .local ? "Local game" : "Online play" }
}

@MainActor final class ExperimentModel: ObservableObject {
    @Published var playMode: PhysicalPlayMode = .local {
        didSet {
            guard oldValue != playMode else { return }
            // Preserve the local game's checkpoints; returning requires an explicit Resume.
            recorder.pause()
            recorder.clock.pause("Local clock paused while switching play mode")
            onlineBoard.enabled = playMode == .online
            if playMode == .online {scoring.stopForOnlinePlay()}
            if playMode == .local { moveEvidenceCapture.stop(reason:"Switched to local game") }
            clearBoardCorrections("Manual corrections cleared because the play mode changed.")
            exportStatus = ""
            if persistViewSettings { settings.set(playMode.rawValue,forKey:"PhysicalGo.playMode") }
        }
    }
    @Published var showDiagnostics = false {
        didSet { if persistViewSettings { settings.set(showDiagnostics,forKey:"PhysicalGo.showDiagnostics") } }
    }
    private var establishedStones=EstablishedStoneTracker()
    @Published private(set) var stoneTrackingReport=EstablishedStoneTracker.Report()
    @Published private(set) var trackedBoardObservation:BoardObservation?
    private var stoneTrackingExpected:[Occupancy] {
        if playMode == .online {return recoveryExpected}
        guard recorder.hasGame,let board=recorder.positions.last,board.size==size else {return []}
        return board.grid.flatMap{$0}.map {stone -> Occupancy in
            if stone == Stone.black {return .black}
            if stone == Stone.white {return .white}
            return .empty
        }
    }
    private var stoneTrackingContext:String {
        "\(revision)/\(playMode.rawValue)/\(viewQuarterTurns)/" +
        (playMode == .online ? onlineBoard.stoneTrackingIdentity : recorder.autosaveURL?.path ?? "local")
    }
    @Published private(set) var latestAlignmentReport = "No camera analysis yet."
    @Published private(set) var exportingSGF = false
    @Published private(set) var exportStatus = ""
    @Published var newGameClock=LocalClockSettings()
    @Published var newGameHandicap=0
    @Published var newGameInfo=SGFGame.Info(date:SGFGame.Info.formattedGameDate(Date()),komi:"6.5",rules:"Japanese")

    @Published var interfaceScale = 1.1 {
        didSet { if persistViewSettings { settings.set(interfaceScale,forKey:"PhysicalGo.interfaceScale") } }
    }
    enum RecordingSounds: String, CaseIterable {
        case adjustments, all, off
        var label: String {
            switch self {
            case .adjustments: return "Adjustments only"
            case .all: return "All feedback"
            case .off: return "Off"
            }
        }
    }
    @Published var soundMode: RecordingSounds = .adjustments {
        didSet {
            if persistViewSettings { settings.set(soundMode.rawValue,forKey:"PhysicalGo.soundMode") }
            configurePlacementChime()
        }
    }
    func resizeText(_ delta:Double) { interfaceScale=min(1.5,max(0.9,((interfaceScale+delta)*100).rounded()/100)) }
    let scoring=PhysicalScoring()
    let onlineBoard = PhysicalOnlineBoard()
    let moveEvidenceCapture = MoveEvidenceCapture()
    let boardCorrections = ManualBoardCorrections()
    @Published var stoneCalibrationSession: StoneCalibrationSession?
    @Published var savingStoneCalibration = false
    @Published var stoneCalibrationError = ""
    @Published var stoneCalibrationFolder: URL?
    @Published var resumableStoneCalibrationFolder = StoneCalibrationArchive.latestIncomplete()
    @Published var stoneAppearanceProfile: StoneAppearanceModel?
    var stoneAppearanceProfileSession: StoneCalibrationSession?
    var stoneCalibrationArchiveRoot = StoneCalibrationArchive.directory
    @Published var inspectingStoneAppearance = false
    @Published private(set) var correctionSnapshot: BoardCorrectionSnapshot?
    @Published private(set) var savingCorrections = false
    @Published var correctionError = ""
    private var correctionSubscription: AnyCancellable?
    private var clockSubscriptions=Set<AnyCancellable>()
    var correctedObservation: BoardObservation? {
        let current=(running && !frozen ? trackedBoardObservation:nil) ?? observation
        return current.map {boardCorrections.apply(to:$0)}
    }

    private(set) var correctionInitialPoint:Int?
    private var correctionRevision:Int?
    private var correctionFrameTime:Double?
    private var correctionReviewTarget:(id:UUID,target:[Occupancy],capture:Bool)?
    struct PhotoReviewAction {
        let title:String
        let capture:Bool
        let photo:CheckedReviewPhoto
    }
    var photoReviewGuidance:String? {
        guard correctionReviewTarget != nil else {return nil}
        if photoReviewAction != nil {return nil}
        guard correctionRevision==revision,let time=correctionFrameTime,
              ProcessInfo.processInfo.systemUptime-time<=60,running,cameraState == .live,!frozen,
              !alignmentNeedsRecovery,!lightingNeedsRecovery else {
            return "Wait for a stable live view, then Retake photo to verify this review."
        }
        return "Check the photo and label any incorrect readings. Photo confirmation becomes available when it matches the capture or restoration being reviewed."
    }
    var photoReviewAction:PhotoReviewAction? {
        guard playMode == .local,recorder.state == .paused,!recorder.reviewing,!recorder.handOverBoard,
              running,cameraState == .live,!frozen,!alignmentNeedsRecovery,!lightingNeedsRecovery,
              correctionRevision==revision,let time=correctionFrameTime,
              let snapshot=correctionSnapshot,!snapshot.observation.lightingBlocked,let original=correctionReviewTarget else {return nil}
        let position=boardCorrections.apply(to:snapshot.observation,preview:true).signature
        let photo=CheckedReviewPhoto(reviewID:original.id,target:original.target,position:position,capturedAt:time)
        let now=ProcessInfo.processInfo.systemUptime
        if original.capture,let plan=recorder.pendingCaptureReview,
           photo.verifies(id:plan.id,target:plan.target,requiredClear:plan.captured.union([plan.point]),now:now) {
            return PhotoReviewAction(title:"Confirm capture from this photo",capture:true,photo:photo)
        }
        if !original.capture,let plan=recorder.pendingBoardRestoration,
           photo.verifies(id:plan.id,target:plan.target,requiredClear:plan.changed,now:now) {
            return PhotoReviewAction(title:"Confirm restoration from this photo",capture:false,photo:photo)
        }
        return nil
    }
    func beginBoardCorrection(at point:Int?=nil) {
        guard !savingCorrections, !boardCorrections.isEditing,
              let image, let observation, let calibration, !alignmentNeedsRecovery else {return}
        if recorder.automaticCaptureStatus != nil,recorder.prepareAutomaticCaptureReview()==nil {return}
        correctionInitialPoint=point
        correctionRevision=revision
        let now=ProcessInfo.processInfo.systemUptime
        correctionFrameTime=lastVerifiedLiveFrameAt.flatMap {now >= $0 && now-$0<1.5 ? $0:nil}
        correctionReviewTarget=nil
        if let plan=recorder.pendingCaptureReview {correctionReviewTarget=(plan.id,plan.target,true)}
        else if let plan=recorder.pendingBoardRestoration {correctionReviewTarget=(plan.id,plan.target,false)}
        correctionSnapshot=BoardCorrectionSnapshot(id:UUID(),capturedAt:Date(),image:image,
            reference:referenceImage,calibration:calibration,referenceCalibration:referenceCalibration,
            observation:observation,threshold:threshold,quarterTurns:viewQuarterTurns,source:sourceName)
        boardCorrections.begin(size:size); correctionError=""
        onlineBoard.pauseForCorrection()
        recorder.suspendVision("Correcting the physical board. Recording paused.",preserveOrder:true)
    }
    func cancelBoardCorrection() {
        guard !savingCorrections else {return}
        boardCorrections.cancel(); correctionSnapshot=nil; correctionError=""
    }
    func finishBoardCorrection(confirmReview:Bool=false) {
        guard !savingCorrections, boardCorrections.isEditing, let snapshot=correctionSnapshot else {return}
        let action=confirmReview ? photoReviewAction:nil
        if confirmReview,action==nil {correctionError="This photo no longer verifies the current review. Retake the photo and check the marked points.";return}
        guard confirmReview || !boardCorrections.edits.isEmpty else {cancelBoardCorrection();return}
        let edits=boardCorrections.edits
        savingCorrections=true; correctionError=""
        // Archive before resolving a review. A disk failure keeps the editor
        // open and dispatch paused rather than silently losing valuable labels.
        DispatchQueue.global(qos:.utility).async {
            let outcome=Result {try CorrectionArchive.save(snapshot,edits:edits)}
            DispatchQueue.main.async { [weak self] in
                guard let self else {return}
                self.savingCorrections=false
                guard self.correctionSnapshot?.id == snapshot.id, self.boardCorrections.isEditing else {return}
                switch outcome {
                case .success:
                    if let action {
                        guard self.photoReviewAction?.photo.reviewID==action.photo.reviewID else {
                            self.correctionError="The camera or review changed while saving. Labels were archived; retake the photo before confirming.";return
                        }
                        let error=action.capture
                            ? self.recorder.confirmCaptureReview(action.photo.reviewID,checkedPhoto:action.photo)
                            : self.recorder.confirmBoardRestoration(action.photo.reviewID,checkedPhoto:action.photo)
                        if let error {self.correctionError=error;return}
                        self.reviewPresentation.close()
                    }
                    self.boardCorrections.commit(); self.correctionSnapshot=nil
                    self.onlineBoard.pauseForCorrection()
                    self.stability.reset(); self.stable=false
                case .failure(let error):
                    self.correctionError="Could not save the correction images: \(error.localizedDescription). Your edits are still here; retry when storage is available."
                }
            }
        }
    }
    func clearBoardCorrections(_ reason:String) {
        boardCorrections.clear(reason:reason); correctionSnapshot=nil
    }
    let recorder: GameRecorder
    let reviewPresentation=ReviewPresentation()
    let diagnostics: DiagnosticRecorder
    private var diagnosticDecisionTicket:DiagnosticRecorder.Ticket?
    private var lastDiagnosticSGF=""
    private var diagnosticAnchorRevision=0
    struct CameraOption: Identifiable { let id: String; let name: String }
    @Published var cameras = [CameraOption]()
    @Published var cameraID = ""
    @Published var cameraStatus = "Choose a camera, or open a photo to begin."
    @Published var running = false
    @Published var cameraState: CameraState = .failed
    @Published var frameCount = 0
    @Published var frozen = false
    @Published var image: CGImage?
    @Published var size = 19
    @Published var corners = [ImagePoint]()
    @Published var calibration: BoardCalibration?
    @Published var alignmentCheck=AlignmentCheck.idle
    @Published var detectingGrid = false
    @Published var showGridOverlay = true
    @Published var showStoneOutlines = true
    @Published var straightenBoard = true
    @Published private(set) var rectifiedImage: CGImage?
    private(set) var rectifiedGeometry: BoardRectifiedGeometry?
    @Published private(set) var rectifiedLongAxisRows = true
    @Published private(set) var viewQuarterTurns = 0
    @Published var automaticViewOrientation = true {
        didSet {
            if persistViewSettings {settings.set(automaticViewOrientation,forKey:"PhysicalGo.automaticViewOrientation")}
            if automaticViewOrientation {orientBoardForPlayer()}
        }
    }
    var orientationLocked:Bool {onlineBoard.enabled || recorder.state != .idle}
    var orientationStatus:String {
        if !automaticViewOrientation {return "View set manually"}
        if orientationLocked {return "View held for this game"}
        return aspectConfident || aspectOverridden ? "Long direction upright · flip for your seat" : "Long direction estimated · confirm or rotate"
    }
    func orientBoardForPlayer() {
        guard calibration != nil, stoneCalibrationSession == nil,
              BoardViewOrientationPolicy.canAdjust(automatic:automaticViewOrientation,online:onlineBoard.enabled,recording:recorder.state != .idle) else {return}
        setViewTurns(BoardViewOrientationPolicy.preferredTurns(current:viewQuarterTurns,longAxisRows:rectifiedLongAxisRows))
    }
    private func setViewTurns(_ turns:Int) {
        let next=BoardOrientation(turns).turns
        guard next != viewQuarterTurns else {return}
        clearBoardCorrections("Manual corrections cleared because the board orientation changed.")
        viewQuarterTurns=next
        if persistViewSettings {settings.set(viewQuarterTurns,forKey:"PhysicalGo.viewQuarterTurns")}
    }
    func flipView() {setViewTurns(viewQuarterTurns+2)}
    @Published var gridStatus = "Grid detection starts automatically when the camera is ready."
    @Published var observation: BoardObservation?
    var visibleObservation: BoardObservation? { observation?.lightingBlocked == true ? nil : observation }
    @Published var stable = false
    @Published var threshold = 0.13
    @Published var labels = [Int: Occupancy]()
    @Published var sampleName = "Board 1 · even light"
    @Published var message = ""
    @Published var hasReference = false
    @Published private(set) var automaticReference = false
    @Published private(set) var automaticReferenceAllowed = true
    private var emptyBoardVerifier = EmptyBoardVerifier()
    @Published var sourceName = "No source"
    @Published private(set) var startupReferenceCaptured = false
    private(set) var referenceImage: CGImage? {
        didSet {if referenceImage !== oldValue {startupReferenceCaptured=false}}
    }
    private var reference: GrayFrame?
    private var trackingAnchor: AutoGridDetector.TrackingAnchor? {didSet {diagnosticAnchorRevision += 1}}
    private(set) var referenceCalibration: BoardCalibration?
    @Published var recoverySpeechEnabled=true {
        didSet {
            if persistViewSettings {settings.set(recoverySpeechEnabled,forKey:"PhysicalGo.recoverySpeech")}
            if !recoverySpeechEnabled {recoverySpeech.stop(reason:"recovery speech muted")}
        }
    }
    private let recoverySpeech=RecoverySpeech()
    private lazy var boardViewFeedback=BoardViewRecoveryFeedback(speech:recoverySpeech)
    private var boardAlignmentGate=BoardAlignmentGate()
    private lazy var clockPauseAnnouncements=ClockPauseAnnouncements(speech:recoverySpeech)
    private var lightingRecovery=LightingRecovery()
    @Published private(set) var lightingNeedsRecovery=false
    @Published private(set) var lightingNeedsHelp=false
    @Published private(set) var lightingAdjusted=false
    /// Shared by live analysis and deterministic recovery tests. Never changes
    /// accepted stones, the empty reference, or a manually paused recording.
    func applyLightingRecovery(_ input:BoardObservation,fresh:Bool,now:Double)->BoardObservation {
        let wasActive=lightingNeedsRecovery,wasHelp=lightingNeedsHelp
        let words=lightingRecovery.update(blocked:input.lightingBlocked,fresh:fresh,now:now,
            speech:recoverySpeechEnabled && running && cameraState == .live && !frozen && !alignmentNeedsRecovery)
        lightingNeedsRecovery=lightingRecovery.active;lightingNeedsHelp=lightingRecovery.needsHelp
        lightingAdjusted=input.lightingAdjusted && !lightingNeedsRecovery
        if wasActive && !lightingNeedsRecovery {recoverySpeech.resolved(.lighting)}
        if let words {recoverySpeech.request(.lighting,text:words,settings:recorder.clock.sounds)}
        if wasActive != lightingNeedsRecovery || wasHelp != lightingNeedsHelp {
            diagnostics.event("lighting recovery",details:["active":lightingNeedsRecovery,"needsHelp":lightingNeedsHelp,
                "adjusted":input.lightingAdjusted,"uptime":now])
        }
        var result=input
        if lightingNeedsRecovery {
            result.lightingBlocked=true
            result.notice=lightingNeedsHelp ? "Improve lighting across the board and reduce glare. Stones can stay in place."
                : "Adjusting to the lighting. Please pause play while the view is checked."
        }
        return result
    }
    private var recoveryPrompt=BoardRecoveryPrompt()
    @Published private(set) var recoveryLikelyObstruction=false
    private func updateRecoverySpeech() {
        if !alignmentNeedsRecovery {recoverySpeech.resolved(.alignment);recoveryLikelyObstruction=false}
        if let words=recoveryPrompt.update(recovering:alignmentNeedsRecovery,
                                           needsHelp:recoveryNeedsFullBoard || recoverySearchExhausted,
                                           enabled:recoverySpeechEnabled && running && cameraState == .live && !frozen,
                                           now:ProcessInfo.processInfo.systemUptime,obstructed:recoveryLikelyObstruction) {
            recoverySpeech.request(.alignment,text:words,settings:recorder.clock.sounds)
        }
    }
    @Published private(set) var alignmentNeedsRecovery = false {didSet {updateRecoverySpeech()}}
    @Published private(set) var recoveryNeedsFullBoard=false {didSet {updateRecoverySpeech()}}
    @Published private(set) var recoveryDetail=""
    var recoveryExpected:[Occupancy] {
        if playMode == .online {
            guard onlineBoard.size==size,onlineBoard.cells.count==size*size else {return []}
            return (0..<size*size).map {raw in
                Occupancy(rawValue:onlineBoard.cells[PhysicalMoveInference.displayedPoint(row:raw/size,col:raw%size,size:size,quarterTurns:viewQuarterTurns)]) ?? .uncertain
            }
        }
        guard recorder.state != .finished,recorder.moveCount>0,
              let board=recorder.positions.last,board.size==size else {return []}
        return board.grid.flatMap {$0}.map {stone -> Occupancy in
            if stone == Stone.black {return .black}
            if stone == Stone.white {return .white}
            return .empty
        }
    }
    @Published private(set) var alignmentRecoveries = 0
    @Published private(set) var recoveryChecks = 0
    @Published private(set) var recoverySearchAttempts = 0
    @Published private(set) var recoverySearchExhausted = false {didSet {updateRecoverySpeech()}}
    private var nextRecoverySearch = 0.0
    private let maximumRecoverySearches = 3
    var gridIndicator: String {
        if awaitingReferenceFrame && !alignmentNeedsRecovery { return "Waiting to verify grid…" }
        guard alignmentNeedsRecovery else {
            return calibration != nil ? "Grid detected" : lookingForGrid ? "Looking for grid…" : "Grid not set"
        }
        if detectingGrid { return "Searching whole view…" }
        if frozen || !running || cameraState != .live { return "Grid recovery paused" }
        if recoverySearchExhausted { return "Grid needs attention" }
        return "Reacquiring grid…"
    }
    private func resetRecoverySearch() {
        recoveryChecks = 0; recoverySearchAttempts = 0; recoverySearchExhausted = false
        recoveryNeedsFullBoard=false;recoveryDetail=""
        nextRecoverySearch = 0
    }
    private var stability = ObservationStability()
    private let camera = CameraCapture()
    private var acceptsFrames = false
    private var needsFreshReference = false
    @Published private(set) var awaitingReferenceFrame = false
    @Published private(set) var referenceStatus = ""
    private let referenceArchive: ReferenceArchive?
    private var referenceCameraID: String?
    private var referenceCameraName = ""

    private let cameraAnalysis = CameraAnalysisPipeline()
    private var processingBusy = false
    @Published private(set) var lastVerifiedLiveFrameAt:Double?
    private var revision = 0 {didSet {
        lastVerifiedLiveFrameAt=nil
        trackedBoardObservation=nil;establishedStones.reset();stoneTrackingReport = .init()
    }}
    private var gridGeneration = 0
    private var automaticGridArmed = true
    private var manualCornerMode = false
    private var nextAutomaticGridAttempt = 0.0
    var lookingForGrid: Bool { detectingGrid || automaticGridArmed }
    var selectingCorners: Bool { calibration == nil && !lookingForGrid }
    // Injectable for synthetic classifier fixtures that deliberately contain no printed grid.
    var tracksCameraMotion = true
    private let automaticGridEnabled: Bool
    private let persistViewSettings: Bool
    private let settings:UserDefaults
    private let discoversCameras:Bool
    private var preferredCameraID:String?
    private var preferredCameraName=""
    private var attemptedLaunchCamera=false
    var orientation: BoardOrientation { BoardOrientation(viewQuarterTurns) }
    @Published private(set) var aspectConfident = false
    @Published private(set) var aspectOverridden = false
    @Published private(set) var aspectStoneCount = 0
    @Published private(set) var aspectGridLineCount = 0
    private var nextAspectCheck = 0.0
    private var pendingStoneAxis:Bool?

    func estimateBoardAspect(orient:Bool = true) {
        guard let calibration,let image else { return }
        let estimate=BoardAspectEstimate.estimate(calibration,width:image.width,height:image.height,frame:GrayFrame(image:image,includeColor:false))
        rectifiedLongAxisRows=estimate.longAxisRows; aspectGridLineCount=estimate.gridLineSamples
        aspectConfident=estimate.confident; aspectOverridden=false; aspectStoneCount=0; nextAspectCheck=0; pendingStoneAxis=nil
        if orient {orientBoardForPlayer()}
    }
    func swapLongSide() {
        rectifiedLongAxisRows.toggle(); aspectOverridden=true; orientBoardForPlayer(); perspectiveViewChanged()
    }
    var displayedCorners: [ImagePoint] { calibration == nil ? corners : orientation.displayedCorners(corners) }
    private let gridQueue = DispatchQueue(label: "PhysicalGo.grid", qos: .userInitiated)
    var cornerPrompt: String {
        let names = ["top-left", "top-right", "bottom-right", "bottom-left"]
        return corners.count < 4 ? "Hover to magnify · Click the \(names[corners.count]) corner intersection" : "Grid aligned"
    }
    init(discoverCameras: Bool = true, automaticGridDetection: Bool = true, restoreViewSettings: Bool = true, referenceArchive: ReferenceArchive? = .standard, recordingStorage: URL? = GameRecorder.recordingsDirectory, settings:UserDefaults = .standard, diagnosticRoot:URL = CaptureFolders.diagnostics) {
        self.settings=settings;discoversCameras=discoverCameras
        self.recorder = GameRecorder(storage:recordingStorage)
        self.diagnostics = DiagnosticRecorder(root:diagnosticRoot)
        self.referenceArchive = referenceArchive
        automaticGridEnabled = automaticGridDetection
        persistViewSettings = restoreViewSettings
        correctionSubscription=boardCorrections.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        if restoreViewSettings {
            if settings.object(forKey:"PhysicalGo.recoverySpeech") != nil {recoverySpeechEnabled=settings.bool(forKey:"PhysicalGo.recoverySpeech")}
            preferredCameraID=settings.string(forKey:"PhysicalGo.lastCameraID")
            preferredCameraName=settings.string(forKey:"PhysicalGo.lastCameraName") ?? ""
            if let value=settings.object(forKey:"PhysicalGo.interfaceScale") as? Double, value.isFinite { interfaceScale=min(1.5,max(0.9,value)) }
            if let raw=settings.string(forKey:"PhysicalGo.soundMode"), let mode=RecordingSounds(rawValue:raw) {
                soundMode = mode
            } else if settings.object(forKey:"PhysicalGo.recordingSounds") != nil && !settings.bool(forKey:"PhysicalGo.recordingSounds") {
                soundMode = .off
            }
        }
        if restoreViewSettings {
            showDiagnostics=settings.bool(forKey:"PhysicalGo.showDiagnostics")
            playMode=PhysicalPlayMode(rawValue:settings.string(forKey:"PhysicalGo.playMode") ?? "") ?? .local
        }
        // Property observers do not run for initial assignments in init.
        onlineBoard.enabled = playMode == .online
        configurePlacementChime()
        onlineBoard.onEvidenceCapture = { [weak self] event in
            self?.moveEvidenceCapture.trigger(event,now:event["uptime"] as? Double ?? ProcessInfo.processInfo.systemUptime)
        }
        recorder.onEvidenceCapture = { [weak self] event in
            guard let self,self.playMode == .local else {return nil}
            var details=event
            details["viewQuarterTurns"]=self.viewQuarterTurns
            for (key,plistKey) in [("appVersion","CFBundleShortVersionString"),("appBuild","CFBundleVersion"),("sourceHash","PhysicalGoSourceHash")] {
                details[key]=Bundle.main.object(forInfoDictionaryKey:plistKey) ?? "development"
            }
            return self.moveEvidenceCapture.trigger(details,now:event["uptime"] as? Double ?? ProcessInfo.processInfo.systemUptime)
        }
        if restoreViewSettings {
            if let data=settings.data(forKey:"PhysicalGo.clockSounds"),let sounds=try? JSONDecoder().decode(LocalClockSounds.self,from:data) {recorder.clock.sounds=sounds}
            if settings.object(forKey:"PhysicalGo.clockAutoPause") != nil {recorder.clock.pauseOnInterruption=settings.bool(forKey:"PhysicalGo.clockAutoPause")}
            if let data=settings.data(forKey:"PhysicalGo.nextClock"),let config=try? JSONDecoder().decode(LocalClockSettings.self,from:data),config.validationError==nil {newGameClock=config}
        }
        if restoreViewSettings {
            if settings.object(forKey:"PhysicalGo.captureUnusualMoves") != nil {
                moveEvidenceCapture.enabled=settings.bool(forKey:"PhysicalGo.captureUnusualMoves")
            }
            let limit=settings.integer(forKey:"PhysicalGo.diagnosticLimitGB")
            if [1,5,10].contains(limit) {diagnostics.limitGB=limit}
        }
        moveEvidenceCapture.$enabled.dropFirst().sink { [weak self] value in
            guard let self,self.persistViewSettings else {return}
            self.settings.set(value,forKey:"PhysicalGo.captureUnusualMoves")
        }.store(in:&clockSubscriptions)
        diagnostics.$limitGB.dropFirst().sink { [weak self] value in
            guard let self,self.persistViewSettings else {return}
            self.settings.set(value,forKey:"PhysicalGo.diagnosticLimitGB")
        }.store(in:&clockSubscriptions)
        recorder.clock.$sounds.dropFirst().sink { [weak self] value in
            guard let self,self.persistViewSettings,let data=try? JSONEncoder().encode(value) else {return}
            self.settings.set(data,forKey:"PhysicalGo.clockSounds")
        }.store(in:&clockSubscriptions)
        recorder.clock.$engine.map(\.running).removeDuplicates().dropFirst().sink { [weak self] running in
            if running {self?.recoverySpeech.cancel(.viewRecovered,reason:"clocks resumed")}
        }.store(in:&clockSubscriptions)
        recorder.clock.$pauseOnInterruption.dropFirst().sink { [weak self] value in
            guard let self,self.persistViewSettings else {return};self.settings.set(value,forKey:"PhysicalGo.clockAutoPause")
        }.store(in:&clockSubscriptions)
        $newGameClock.dropFirst().sink { [weak self] value in
            guard let self,self.persistViewSettings,value.validationError==nil,let data=try? JSONEncoder().encode(value) else {return}
            self.settings.set(data,forKey:"PhysicalGo.nextClock")
        }.store(in:&clockSubscriptions)
        recorder.onMoveAccepted = { [weak self] _,_ in
            guard let self else {return}
            if self.soundMode == .all && !(self.recorder.clock.enabled && self.recorder.clock.sounds.moveBeep) { NSSound(named:"Pop")?.play() }
        }
        recoverySpeech.onSpeechEvent = { [weak self] event,details in self?.recorder.logSpeech(event,details:details) }
        recorder.clock.onSpeechEvent = { [weak self] event,details in
            var fields=details;fields["channel"]="clock"
            self?.recorder.logSpeech(event,details:fields)
        }
        recorder.clock.onAutomaticPause = { [weak self] pause in
            guard let self else {return}
            self.recorder.logAutomaticClockPause(pause)
            self.clockPauseAnnouncements.began(settings:self.recorder.clock.sounds) { [weak self] in
                guard let self else {return false}
                return self.recoverySpeechEnabled && self.recorder.clock.audible && self.recorder.clock.automaticPause != nil && !self.recorder.clock.running
            }
        }
        recorder.clock.onAutomaticPauseCleared = { [weak self] in
            guard let self else {return}
            if self.recorder.clock.running {self.recorder.logAutomaticClockResume()}
            self.clockPauseAnnouncements.cleared(running:self.recorder.clock.running,
                blackToPlay:self.recorder.clock.engine.blackToPlay,
                enabled:self.recoverySpeechEnabled && self.recorder.clock.audible && self.recorder.clock.pendingResumeAnnouncement == nil,settings:self.recorder.clock.sounds)
        }
        recorder.clock.onResumeAnnouncement = { [weak self] words in
            guard let self,self.recoverySpeechEnabled,self.recorder.clock.audible else {return}
            self.recoverySpeech.request(.clockResume,text:words,settings:self.recorder.clock.sounds,priority:true)
        }
        recorder.onGameStarted = { [weak self] in
            guard let self,self.soundMode != .off else {return}
            NSSound(named:"Pop")?.play()
        }
        recorder.onAttention = { [weak self] in self?.playRecordingWarning() }
        recorder.onDiagnosticEvent = { [weak self] entry in
            guard let self,self.diagnostics.isOpen else {return}
            var details=entry;let sgf=self.recorder.sgf()
            if sgf != self.lastDiagnosticSGF {details["sgf"]=sgf;self.lastDiagnosticSGF=sgf}
            self.diagnostics.event("recorder",ticket:self.diagnosticDecisionTicket,details:["decision":details])
        }
        if restoreViewSettings {
            viewQuarterTurns = BoardOrientation(settings.integer(forKey:"PhysicalGo.viewQuarterTurns")).turns
            if settings.object(forKey:"PhysicalGo.automaticViewOrientation") != nil {
                automaticViewOrientation=settings.bool(forKey:"PhysicalGo.automaticViewOrientation")
            }
        }
        rectifiedLongAxisRows = !BoardOrientation(viewQuarterTurns).swapsDimensions
        if restoreViewSettings {
            if settings.object(forKey:"PhysicalGo.straightenBoard") != nil {
                straightenBoard = settings.bool(forKey:"PhysicalGo.straightenBoard")
            }

        }
        automaticGridArmed = automaticGridDetection
        camera.onFrame = { [weak self] image,time in
            guard let self, self.acceptsFrames else { return }
            self.receiveCameraFrame(image,capturedAt:time)
        }
        camera.onStatus = { [weak self] status, state in
            guard let self, self.acceptsFrames else { return }
            self.handleCameraStatus(status, state: state)
        }
        if discoverCameras { refreshCameras() }
        do {
            if let saved = try referenceArchive?.load() {
                if restoreViewSettings && preferredCameraID == nil {
                    preferredCameraID=saved.cameraID;preferredCameraName=saved.cameraName
                }
                if saved.enabled {
                    restoreReference(saved)
                    image=nil;frozen=false;awaitingReferenceFrame=true
                    referenceStatus="Saved reference restored. Waiting for live alignment verification."
                }
            }
            if let preferredCameraID,cameras.contains(where:{$0.id==preferredCameraID}) {cameraID=preferredCameraID}
        } catch { message = "Could not restore reference: \(error.localizedDescription)" }

    }
    var diagnosticRecorderState:[String:Any] {
        ["state":String(describing:recorder.state),"moveCount":recorder.moveCount,"status":recorder.status,
         "nextPlayer":recorder.nextPlayer.rawValue,"needsAttention":recorder.needsAttention,
         "pendingMoves":recorder.pendingMoveCount,"unsavedCandidates":recorder.unsavedStoneCount]
    }
    private var diagnosticContext:[String:Any] {
        ["playMode":playMode.rawValue,"cameraID":cameraID,"source":sourceName,"cameraState":String(describing:cameraState),
         "boardSize":size,"threshold":threshold,"calibration":DiagnosticRecorder.value(calibration),
         "referenceCalibration":DiagnosticRecorder.value(referenceCalibration),"hasReference":hasReference,
         "referenceAutomatic":automaticReference,"viewQuarterTurns":viewQuarterTurns,
         "straightenBoard":straightenBoard,"longAxisRows":rectifiedLongAxisRows,
         "tracksCameraMotion":tracksCameraMotion,"alignmentNeedsRecovery":alignmentNeedsRecovery,
         "revision":revision,"gridGeneration":gridGeneration,"frozen":frozen,
         "cameraFrameNumber":frameCount,"recorder":diagnosticRecorderState,
         "manualCorrections":boardCorrections.values.sorted{$0.key<$1.key}.map {["point":$0.key,"occupancy":$0.value.rawValue] as [String:Any]},
         "editingCorrections":boardCorrections.isEditing]
    }
    func startDiagnostics() {
        var context=diagnosticContext
        context["appVersion"]=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
        context["appBuild"]=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "development"
        context["sourceHash"]=Bundle.main.object(forInfoDictionaryKey:"PhysicalGoSourceHash") as? String ?? "development"
        context["initialSGF"]=recorder.sgf();context["timezone"]=TimeZone.current.identifier
        do {
            try diagnostics.start(context:context);lastDiagnosticSGF=recorder.sgf()
            diagnostics.event("capture started",details:context)
        }catch {message="Could not start diagnostic capture: \(error.localizedDescription)"}
    }
    @discardableResult private func diagnosticFrame(_ image:CGImage,at time:Double = ProcessInfo.processInfo.systemUptime,source:String)->DiagnosticRecorder.Ticket? {
        guard diagnostics.isCapturing else {return nil}
        var context=diagnosticContext;context["delivery"]=source
        return diagnostics.capture(image,at:time,context:context,reference:referenceImage,anchor:trackingAnchor,anchorRevision:diagnosticAnchorRevision)
    }
    private func configurePlacementChime() {
        if soundMode == .adjustments {
            recorder.onPlacementChime = { _ in NSSound(named:"Glass")?.play() }
        } else { recorder.onPlacementChime = nil }
    }
    private func playRecordingWarning() {
        guard soundMode == .all else {return}
        NSSound(named:"Basso")?.play()
        // One alert per problem episode; the recorder bounds reminders. A
        // delayed second failure pulse can overlap a successful confirmation.
    }
    func handleCameraStatus(_ status: String, state: CameraState) {
        diagnostics.event("camera status",details:["message":status,"state":String(describing:state)])
        cameraStatus = status; cameraState = state; running = state.active
        if state == .live,persistViewSettings,let selected=cameras.first(where:{$0.id==cameraID}) {
            preferredCameraID=selected.id;preferredCameraName=selected.name
            settings.set(selected.id,forKey:"PhysicalGo.lastCameraID")
            settings.set(selected.name,forKey:"PhysicalGo.lastCameraName")
        }
        if state != .live {
            boardViewFeedback.reset()
            recoverySpeech.finishCurrent(reason:"camera stream interrupted")
            recorder.suspendVision("Camera interrupted. Recording waits for the board to match the accepted position.",preserveOrder:true)
            emptyBoardVerifier.reset()
            stable = false; stability.reset(); revision += 1
            if detectingGrid {
                cancelGridDetection()
                automaticGridArmed = automaticGridEnabled && calibration == nil && corners.isEmpty
                gridStatus = "Camera interrupted. Wait for a fresh view, then check the grid."
            }
        }
        if state == .recovering || state == .failed {
            needsFreshReference = true
            if !frozen { pauseForFreshFrame() }
        }
        if state == .failed { acceptsFrames = false }
    }
    private func pauseForFreshFrame() {
        observation = nil; labels = [:]; stable = false; stability.reset(); emptyBoardVerifier.reset()
        rectifiedImage = nil; rectifiedGeometry = nil
        revision += 1; needsFreshReference = false; awaitingReferenceFrame = true
        if hasReference { referenceStatus = "Reference preserved. Waiting to check a fresh camera frame." }
        message = "Waiting for a fresh camera frame to verify grid alignment."
    }
    private func disableSavedReference() {
        do { try referenceArchive?.disableAutomaticReuse() }
        catch { message = "Could not update saved reference: \(error.localizedDescription)" }
    }
    private func persistReference() {
        guard let referenceImage, let referenceCalibration, let calibration else { return }
        do {
            try referenceArchive?.save(image:referenceImage,referenceCalibration:referenceCalibration,
                calibration:calibration,cameraID:referenceCameraID,cameraName:referenceCameraName)
            referenceStatus = referenceArchive == nil ? "Reference ready." : "Reference saved on this Mac; reused across camera and app restarts."
        } catch { referenceStatus = "Reference ready for this session, but could not save: \(error.localizedDescription)" }
    }
    private func bindReferenceCamera() {
        referenceCameraID = cameraID.isEmpty ? nil : cameraID
        referenceCameraName = cameras.first(where:{$0.id == cameraID})?.name ?? sourceName
    }
    private func restoreReference(_ saved:ReferenceArchive.Snapshot) {
        size = saved.calibration.size; calibration = saved.calibration; corners = saved.calibration.corners
        referenceImage = saved.image; reference = GrayFrame(image:saved.image); referenceCalibration = saved.referenceCalibration
        referenceCameraID = saved.cameraID; referenceCameraName = saved.cameraName
        if let id = saved.cameraID, cameras.contains(where:{$0.id == id}) { cameraID = id }
        else if saved.cameraID == nil {
            let matches = cameras.filter { $0.name == saved.cameraName }
            if matches.count == 1 { cameraID = matches[0].id; referenceCameraID = cameraID }
        }
        if let frame = reference {
            trackingAnchor = AutoGridDetector.trackingAnchor(frame:frame,calibration:saved.referenceCalibration)
        }
        hasReference = true; automaticReference = false; automaticGridArmed = false; manualCornerMode = false
        alignmentNeedsRecovery = false; resetRecoverySearch(); emptyBoardVerifier.reset()
        sourceName = saved.cameraName
        let aspect = BoardAspectEstimate.estimate(saved.calibration,width:saved.image.width,height:saved.image.height,frame:GrayFrame(image:saved.image,includeColor:false))
        aspectGridLineCount=aspect.gridLineSamples
        rectifiedLongAxisRows = aspect.longAxisRows; aspectConfident = aspect.confident; aspectOverridden = false
        orientBoardForPlayer()
        gridStatus = "Saved grid restored. Live alignment will be checked when the camera starts."
    }
    func openSample() {
        let panel = NSOpenPanel(); panel.title = "Open Physical Go sample folder"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do { try openSample(from:folder) }
        catch { message = "Could not open sample: \(error.localizedDescription)" }
    }
    func openSample(from folder:URL) throws {
        // Decode and validate everything before replacing the current session.
        let sample = try ReferenceArchive.readSample(folder)
        stop(); resetCalibration(); restoreReference(sample.reference)
        image = sample.frame; frozen = true; awaitingReferenceFrame = false; needsFreshReference = false
        if let turns = sample.turns { viewQuarterTurns = BoardOrientation(turns).turns }
        if let value = sample.threshold, value.isFinite { threshold = min(0.35,max(0.05,value)) }
        sampleName = folder.lastPathComponent
        cameraStatus = "Saved sample · \(folder.lastPathComponent)"
        message = "Replaying the saved frame with its original empty reference. Start camera to return to the live board; stones can stay in place."
        estimateBoardAspect(); persistReference(); analyze(sample.frame)
    }
    func refreshCameras() {
        cameras = CameraCapture.devices().map { CameraOption(id: $0.uniqueID, name: $0.localizedName) }
        if !cameras.contains(where: { $0.id == cameraID }) { cameraID = cameras.first?.id ?? "" }
    }
    /// Called once by the app window, not by previews or saved-sample imports.
    /// Injecting activation lets startup selection be tested without opening hardware.
    func startCameraOnLaunch(activate:(()->Void)?=nil) {
        guard !attemptedLaunchCamera else {return}
        attemptedLaunchCamera=true
        guard !running,!frozen else {return}
        if discoversCameras {refreshCameras()}
        if let preferredCameraID {
            if cameras.contains(where:{$0.id==preferredCameraID}) {cameraID=preferredCameraID}
            else {
                let matches=cameras.filter{!preferredCameraName.isEmpty && $0.name==preferredCameraName}
                guard matches.count==1 else {
                    cameraStatus="Last-used camera is unavailable. Connect it, or select another camera and click Start camera."
                    return
                }
                cameraID=matches[0].id
            }
        }
        guard !cameras.isEmpty else {
            cameraStatus="No camera found. Connect a camera, then click Refresh and Start camera."
            return
        }
        if !cameras.contains(where:{$0.id==cameraID}) {cameraID=cameras[0].id}
        if let activate {activate()} else {start()}
    }
    /// Separate from camera activation so restart/restore behavior can be replayed in tests.
    func prepareCameraStart() {
        recorder.suspendVision("Camera restarting. Checking the accepted position before recording continues.",preserveOrder:true)
        if hasReference, let id = referenceCameraID, id == cameraID {
            persistReference(); cancelGridDetection(); automaticGridArmed = false
            pauseForFreshFrame()
        } else {
            resetCalibration(allowAutomatic:true)
        }
        image = nil; frozen = false; acceptsFrames = true
        running = true; cameraState = .starting; frameCount = 0; needsFreshReference = false
        sourceName = cameras.first(where: { $0.id == cameraID })?.name ?? "Camera"
        cameraStatus = "Starting camera…"
    }
    func start() {
        prepareCameraStart(); camera.start(deviceID: cameraID)
    }
    func stop() {
        boardViewFeedback.reset()
        recoverySpeech.stop(reason:"camera stopped")
        moveEvidenceCapture.stop(reason:"Camera stopped")
        diagnostics.event("camera stopped")
        recorder.suspendVision("Camera stopped. The recorded game is preserved.",preserveOrder:true)
        if hasReference { persistReference() }
        acceptsFrames = false; running = false; cameraState = .failed; camera.stop()
        emptyBoardVerifier.reset()
        cameraStatus = "Camera stopped"; stable = false; stability.reset()
        revision += 1; cancelGridDetection(); automaticGridArmed = false
    }
    func toggleFreeze() {
        boardViewFeedback.reset()
        recorder.suspendVision("Frozen or resumed camera. Checking the accepted position before recording continues.",preserveOrder:true)
        frozen.toggle(); emptyBoardVerifier.reset(); revision += 1; labels = [:]; stability.reset(); stable = false
        if frozen { recoverySpeech.stop(reason:"camera frozen");cancelGridDetection(); automaticGridArmed = false }
        else if calibration == nil && corners.isEmpty && !manualCornerMode && automaticGridEnabled {
            automaticGridArmed = true; nextAutomaticGridAttempt = 0
        }
        if frozen { message = "Frame frozen. Click intersections in the detected board to label this sample." }
        else { message = "Live detection resumed." }
        if !frozen && needsFreshReference { pauseForFreshFrame() }
        analyze()
    }
    func resetCalibration(allowAutomatic: Bool = false, preservingRecording:Bool = false) {
        recoverySpeech.resolved(.lighting,reason:"grid reset");lightingRecovery=LightingRecovery()
        lightingNeedsRecovery=false;lightingNeedsHelp=false;lightingAdjusted=false
        clearBoardCorrections("Manual corrections cleared because the grid was reset.")
        aspectStoneCount=0; aspectGridLineCount=0; nextAspectCheck=0; pendingStoneAxis=nil; aspectOverridden=false
        recorder.suspendVision("Grid changed. Recording waits for the accepted position to be verified.",preserveOrder:(allowAutomatic || preservingRecording) && recorder.game.boardSize==size)
        if hasReference { disableSavedReference() }
        awaitingReferenceFrame = false; needsFreshReference = false; referenceStatus = ""
        referenceCameraID = nil; referenceCameraName = ""
        cancelGridDetection()
        automaticGridArmed = allowAutomatic && automaticGridEnabled
        manualCornerMode = !allowAutomatic
        nextAutomaticGridAttempt = 0
        resetRecoverySearch()
        gridStatus = automaticGridArmed ? "Waiting for a clear camera view…" : "Choose Detect grid, or click four corner intersections clockwise from top-left."
        revision += 1; corners = []; calibration = nil
        alignmentNeedsRecovery=false; alignmentRecoveries=0; trackingAnchor=nil; automaticReferenceAllowed=true
        rectifiedImage = nil; rectifiedGeometry = nil
        reference = nil; referenceCalibration = nil; referenceImage = nil; automaticReference=false; emptyBoardVerifier.reset(); hasReference = false
        observation = nil; labels = [:]; stable = false; stability.reset(); message = ""
    }
    private func cancelGridDetection() {
        if detectingGrid {
            gridStatus = "Grid search canceled. Resume the camera or choose Find grid again to retry."
            // A canceled search has no result and must not consume the retry budget.
            if alignmentNeedsRecovery && recoverySearchAttempts > 0 { recoverySearchAttempts -= 1 }
        }
        gridGeneration += 1; detectingGrid = false
    }
    func boardSizeChanged() {
        if calibration?.size == size { return } // Imported sample already supplies matching geometry.
        resetCalibration(allowAutomatic: true)
        if image != nil && automaticGridEnabled { detectGrid(retryAutomatically:running && !frozen) }
    }
    func detectGrid(retryAutomatically: Bool = false, recovering: Bool = false,reportCheck:Bool=false) {
        guard let target = image, !detectingGrid else { return }
        alignmentCheck=reportCheck ? .checking:.idle
        recorder.suspendVision("Finding the grid. The recorded game is preserved.",preserveOrder:true)
        manualCornerMode = false
        if !recovering { resetRecoverySearch() }
        else { recoverySearchAttempts += 1 }
        // Invalidate analysis already in flight so an old alignment cannot overwrite this search.
        revision += 1; stable = false; stability.reset(); emptyBoardVerifier.reset()
        if calibration != nil || !recoveryExpected.isEmpty {
            alignmentNeedsRecovery = true; observation = nil
            rectifiedImage = nil; rectifiedGeometry = nil
        }
        automaticGridArmed = false; gridGeneration += 1
        let token = gridGeneration, boardSize = size
        let previousRecoveries = alignmentRecoveries
        let recoveryPrevious=calibration,expected=recoveryExpected
        let previousLongAxis = rectifiedLongAxisRows, previousManualAspect = aspectOverridden
        let previousStoneCount = aspectStoneCount, hadCalibration = calibration != nil
        let allowReference = automaticReferenceAllowed
        detectingGrid = true
        gridStatus = recovering
            ? "Searching the whole view — attempt \(recoverySearchAttempts) of \(maximumRecoverySearches). Keep the camera steady; stones can stay in place."
            : "Finding the playable grid…"
        let diagnosticTicket=diagnosticFrame(target,source:"grid search input")
        let diagnosticOperation=diagnostics.begin("grid search",ticket:diagnosticTicket,details:diagnosticContext)
        gridQueue.async { [weak self] in
            let result:AutoGridDetector.Result?
            var diagnosticError:String?
            var recovery:AutoGridDetector.RecoveryResult?
            do {
                if recoveryPrevious != nil || !expected.isEmpty {
                    recovery=try AutoGridDetector.recover(image:target,size:boardSize,previous:recoveryPrevious,expected:expected)
                    result=recovery?.result
                } else {result=try AutoGridDetector.detect(image:target,size:boardSize)}
            }
            catch {result=nil;diagnosticError=error.localizedDescription}
            DispatchQueue.main.async {
                guard let self else {return}
                var outcome="grid not found"
                defer {self.diagnostics.end(diagnosticOperation,outcome:outcome,details:["calibration":DiagnosticRecorder.value(result?.calibration),"quality":result?.quality ?? NSNull() as Any,"error":diagnosticError ?? NSNull() as Any,"stoneRecovery":recovery?.reason ?? "not requested","usedStoneLandmarks":recovery?.usedStones ?? false,"needsFullBoard":recovery?.needsFullBoard ?? false,"recorder":self.diagnosticRecorderState])}
                guard self.gridGeneration == token,self.size == boardSize else {outcome="discarded stale grid search";return}
                self.detectingGrid = false
                self.recoveryNeedsFullBoard=recovery?.needsFullBoard ?? (result==nil)
                self.recoveryDetail=recovery?.reason ?? "Keep the whole grid in view and hold the camera steady."
                guard let result else {
                    if reportCheck {self.alignmentCheck = .failed}
                    if recovering {
                        self.recoverySearchExhausted = self.recoverySearchAttempts >= self.maximumRecoverySearches
                        self.nextRecoverySearch = ProcessInfo.processInfo.systemUptime + (self.recoverySearchExhausted ? 30:2)
                        self.gridStatus = self.recoverySearchExhausted
                            ? "The board is not yet verifiable. Automatic checks continue every 30 seconds; you can retry sooner when the view is clear."
                            : "Full-view search \(self.recoverySearchAttempts) of \(self.maximumRecoverySearches) did not verify the grid. Waiting for a fresh view before retrying."
                        return
                    }
                    if retryAutomatically && self.running && !self.frozen {
                        self.automaticGridArmed = true
                        self.nextAutomaticGridAttempt = ProcessInfo.processInfo.systemUptime+2
                        self.gridStatus = "Looking for the grid automatically. Keep the full board in view."
                        return
                    }
                    self.gridStatus = "The full \(boardSize) × \(boardSize) grid was not found in this frame. Retry Detect grid, or choose Manual corners."
                    return
                }
                outcome="grid acquired"
                let savedReference=self.reference, savedReferenceCalibration=self.referenceCalibration, savedReferenceImage=self.referenceImage
                let savedCameraID=self.referenceCameraID, savedCameraName=self.referenceCameraName
                let wasAutomatic=self.automaticReference
                self.resetCalibration(preservingRecording:true)
                self.automaticReferenceAllowed=allowReference
                self.manualCornerMode = false
                self.image = target
                self.calibration = result.calibration; self.corners = result.calibration.corners
                if let savedReference,let savedReferenceCalibration,let savedReferenceImage,
                   savedReferenceCalibration.size==boardSize,savedReference.width==target.width,savedReference.height==target.height {
                    self.reference=savedReference;self.referenceCalibration=savedReferenceCalibration;self.referenceImage=savedReferenceImage
                    self.referenceCameraID=savedCameraID;self.referenceCameraName=savedCameraName
                    self.hasReference=true;self.automaticReference=wasAutomatic
                    self.referenceStatus="Empty reference preserved through grid refinement."
                    self.persistReference()
                }
                self.showGridOverlay = true
                self.gridStatus = "Grid found automatically. Check the cyan lines against the printed grid."
                self.message = self.hasReference ? "Detecting stones with the preserved empty-board reference." : "Detecting stones from the grid and nearby wood. An empty reference is optional."
                if recovering {
                    self.alignmentRecoveries = previousRecoveries + 1
                    self.automaticReferenceAllowed = allowReference
                    self.gridStatus = recovery?.usedStones == true ? "Board recovered using the recorded stones and printed grid.":"Grid recovered automatically with a full-view search. Check the cyan lines against the printed grid."
                    self.message = self.hasReference ? "Grid recovered; the empty reference and pending moves are preserved." : "Detecting from the new view without an empty-board reference."
                }
                self.estimateBoardAspect(orient:false)
                if hadCalibration && (previousManualAspect || (!self.aspectConfident && previousStoneCount>0)) {
                    self.rectifiedLongAxisRows=previousLongAxis; self.aspectOverridden=previousManualAspect
                    self.aspectStoneCount=previousStoneCount; self.aspectConfident=true
                }
                self.orientBoardForPlayer()
                if reportCheck {self.alignmentCheck = .passed}
                self.setTrackingAnchor(); self.analyze()
            }
        }
    }
    func addCorner(_ point: ImagePoint) {
        guard image != nil, corners.count < 4 else { return }
        cancelGridDetection(); automaticGridArmed = false
        manualCornerMode = true
        gridStatus = "Selecting corners manually, clockwise from top-left in the camera image."
        corners.append(point)
        if corners.count == 4 {
            corners = orientation.canonicalCorners(corners)
            calibration = BoardCalibration(size: size, corners: corners)
            if calibration == nil { corners = []; message = "Those corners do not form a valid grid. Click TL, TR, BR, BL in order." }
            else { gridStatus = "Grid aligned. Check the overlay against the printed lines."; message = "Detecting stones from the grid and nearby wood. An empty reference is optional."; estimateBoardAspect(); setTrackingAnchor(); analyze() }
        }
    }
    func rotateView() {
        automaticViewOrientation=false
        setViewTurns(viewQuarterTurns+1)
        if calibration == nil && !corners.isEmpty {
            corners = []
            message = "View rotated. Select the corner intersections in the displayed image."
        }
    }
    func perspectiveViewChanged() {
        if persistViewSettings {
            settings.set(straightenBoard,forKey:"PhysicalGo.straightenBoard")
        }
        revision += 1; rectifiedImage = nil; rectifiedGeometry = nil
        analyze()
    }
    func undoCorner() {
        recorder.suspendVision("Grid changed. Recording waits for alignment.")
        guard !corners.isEmpty else { return }
        disableSavedReference(); referenceStatus = ""; awaitingReferenceFrame = false
        cancelGridDetection(); automaticGridArmed = false
        manualCornerMode = true
        gridStatus = "Selecting corners manually, clockwise from top-left in the camera image."
        if calibration != nil { corners = orientation.displayedCorners(corners) }
        resetRecoverySearch()
        corners.removeLast(); calibration = nil; trackingAnchor=nil; alignmentNeedsRecovery=false; reference = nil; referenceCalibration = nil; referenceImage = nil; automaticReference=false; emptyBoardVerifier.reset()
        rectifiedImage = nil; rectifiedGeometry = nil
        hasReference = false; observation = nil; labels = [:]; stable = false; stability.reset(); revision += 1
    }
    private func setTrackingAnchor() {
        guard let image,let calibration,let frame=GrayFrame(image:image,includeColor:false) else { trackingAnchor=nil; return }
        trackingAnchor=AutoGridDetector.trackingAnchor(frame:frame,calibration:calibration)
    }
    func captureReference() {
        guard !awaitingReferenceFrame, !alignmentNeedsRecovery, (!running || cameraState == .live), calibration != nil, let image, let gray = GrayFrame(image: image) else { return }
        recorder.suspendVision("Reference changed. Checking the accepted position before recording continues.")
        automaticReference=false; emptyBoardVerifier.reset()
        revision += 1; reference = gray; referenceCalibration = calibration; referenceImage = image; hasReference = true
        setTrackingAnchor(); bindReferenceCamera(); persistReference()
        startupReferenceCaptured=true
        labels = [:]; stability.reset(); stable = false
        message = "Empty-board reference captured. Add stones without moving the camera or board."
        analyze()
    }
    func useWithoutReference() {
        recorder.suspendVision("Reference changed. Checking the accepted position before recording continues.")
        disableSavedReference(); referenceStatus = ""
        reference=nil; referenceImage=nil; referenceCalibration=nil; hasReference=false
        automaticReference=false; automaticReferenceAllowed=false; emptyBoardVerifier.reset()
        revision += 1; stability.reset(); stable=false
        message="Detecting without an empty-board reference."
        analyze()
    }
    func receiveCameraFrame(_ image:CGImage,capturedAt:Double) {
        frameCount += 1
        moveEvidenceCapture.offer(image,at:capturedAt,online:onlineBoard.enabled || (playMode == .local && recorder.state == .recording),context:diagnosticContext,
                                  reference:referenceImage,anchor:trackingAnchor,anchorRevision:diagnosticAnchorRevision)
        if frozen {
            if let ticket=diagnosticFrame(image,at:capturedAt,source:"camera") {
                diagnostics.event("frame skipped",ticket:ticket,details:["reason":"View is frozen"])
            }
        } else {receive(image,capturedAt:capturedAt)}
    }
    func receive(_ newImage: CGImage,capturedAt:Double = ProcessInfo.processInfo.systemUptime) {
        let diagnosticTicket=diagnosticFrame(newImage,at:capturedAt,source:running ? "camera" : "photo/test input")
        if let old = image ?? referenceImage, old.width != newImage.width || old.height != newImage.height {
            resetCalibration(allowAutomatic: true); message = "Image dimensions changed. Finding the grid again."
        }
        // Keep the displayed frame and its overlay paired while processing.
        if calibration == nil {
            image = newImage; rectifiedImage = nil; rectifiedGeometry = nil
            if let diagnosticTicket {diagnostics.event("frame skipped",ticket:diagnosticTicket,details:["reason":"Grid not yet established"])}
        }
        else { analyze(newImage,diagnosticTicket:diagnosticTicket,captureUptime:capturedAt) }
        if automaticGridArmed && calibration == nil && corners.isEmpty && !detectingGrid
            && ProcessInfo.processInfo.systemUptime >= nextAutomaticGridAttempt && (!running || frameCount >= 8) {
            detectGrid(retryAutomatically:running && !frozen)
        }
    }
    func analyze(_ supplied: CGImage? = nil,diagnosticTicket suppliedTicket:DiagnosticRecorder.Ticket?=nil,captureUptime:Double?=nil) {
        guard !(awaitingReferenceFrame && supplied == nil), !(running && cameraState != .live), !detectingGrid, !processingBusy, let target = supplied ?? image, let calibration else {
            let reason=processingBusy ? "Analysis busy" : detectingGrid ? "Grid search in progress" : "Camera or grid not ready"
            if supplied != nil {onlineBoard.recordCameraWait(reason)}
            if let captureUptime {moveEvidenceCapture.annotate(["captureUptime":captureUptime,"outcome":reason])}
            if let suppliedTicket {diagnostics.event("frame skipped",ticket:suppliedTicket,details:["reason":reason])}
            return
        }
        let diagnosticTicket=suppliedTicket ?? diagnosticFrame(target,source:"analysis/redraw input")
        let diagnosticOperation=diagnostics.begin("analysis",ticket:diagnosticTicket,details:diagnosticContext)
        processingBusy = true
        let token = revision, threshold = threshold
        let reference = reference, referenceCalibration = referenceCalibration
        let straighten=straightenBoard,longAxisRows=rectifiedLongAxisRows
        let checkStoneAspect = !aspectOverridden && ProcessInfo.processInfo.systemUptime>=nextAspectCheck
        if checkStoneAspect { nextAspectCheck=ProcessInfo.processInfo.systemUptime+2 }
        let previousStoneCount=aspectStoneCount, pendingAxis=pendingStoneAxis
        let trackingAnchor=trackingAnchor,alignmentExpected=recoveryExpected
        let checkAlignment = tracksCameraMotion && (supplied != nil || alignmentNeedsRecovery)
        let newObservation = supplied != nil || observation == nil
        let trackingState=establishedStones,trackingExpected=stoneTrackingExpected,trackingContext=stoneTrackingContext
        let trackingManualPoints=Set(boardCorrections.values.keys)
        let trackingFresh=supplied != nil && running && cameraState == .live && !frozen &&
            stoneCalibrationSession == nil && !boardCorrections.isEditing && !lightingNeedsRecovery
        let trackingTime=captureUptime ?? ProcessInfo.processInfo.systemUptime
        cameraAnalysis.submit(.init(
            target:target,
            calibration:calibration,
            threshold:threshold,
            reference:reference,
            referenceCalibration:referenceCalibration,
            straighten:straighten,
            longAxisRows:longAxisRows,
            checkStoneAspect:checkStoneAspect,
            previousStoneCount:previousStoneCount,
            pendingAxis:pendingAxis,
            trackingAnchor:trackingAnchor,
            alignmentExpected:alignmentExpected,
            checkAlignment:checkAlignment,
            trackingState:trackingState,
            trackingExpected:trackingExpected,
            trackingContext:trackingContext,
            trackingManualPoints:trackingManualPoints,
            trackingFresh:trackingFresh,
            trackingTime:trackingTime,checkHands:self.playMode == .local && self.recorder.clock.enabled && supplied != nil)) { [weak self] analysis in
            let frame=analysis.frame
            let exposureFailure=analysis.exposureFailure
            let alignmentReport=analysis.alignmentReport
            let aligned=analysis.aligned
            let trackedObservation=analysis.trackedObservation
            let trackingResult=analysis.trackingResult
            let stoneAspect=analysis.stoneAspect
            let applyAspect=analysis.applyAspect
            let geometry=analysis.geometry
            let corrected=analysis.corrected
            guard let self else { return }
            var result=analysis.result
            self.processingBusy = false
            if let data=try? JSONSerialization.data(withJSONObject:alignmentReport,options:[.prettyPrinted,.sortedKeys]),
               let report=String(data:data,encoding:.utf8) {self.latestAlignmentReport=report}
            var diagnosticOutcome="analyzed without recording",recorderTime:Double?
            self.diagnosticDecisionTicket=diagnosticTicket
            defer {
                if let captureUptime,self.moveEvidenceCapture.enabled {
                    self.moveEvidenceCapture.annotate(["captureUptime":captureUptime,"outcome":diagnosticOutcome,
                        "alignment":alignmentReport,"calibration":DiagnosticRecorder.value(aligned),
                        "readings":DiagnosticRecorder.value(result?.readings),
                        "footprints":DiagnosticRecorder.value(result?.footprints),
                        "placementFits":DiagnosticRecorder.value(result?.placementFits),
                        "lightingBlocked":result?.lightingBlocked ?? false,
                        "lightingAdjusted":result?.lightingAdjusted ?? false,"lightingField":DiagnosticRecorder.value(result?.lightingField),
                        "stoneTracking":DiagnosticRecorder.value(trackingResult.report),
                        "physicalStoneTracks":DiagnosticRecorder.value(trackingResult.tracks.values.sorted{$0.point<$1.point})])
                }
                self.diagnostics.end(diagnosticOperation,outcome:diagnosticOutcome,details:[
                    "alignment":alignmentReport,
                    "calibration":DiagnosticRecorder.value(aligned),"readings":DiagnosticRecorder.value(result?.readings),
                    "footprints":DiagnosticRecorder.value(result?.footprints),"placementFits":DiagnosticRecorder.value(result?.placementFits),"notice":result?.notice ?? NSNull() as Any,
                    "lightingBlocked":result?.lightingBlocked ?? false,"lightingAdjusted":result?.lightingAdjusted ?? false,
                    "lightingRecovery":self.lightingNeedsRecovery,"exposureFailure":exposureFailure,
                    "lightingField":DiagnosticRecorder.value(result?.lightingField),
                    "stoneTracking":DiagnosticRecorder.value(trackingResult.report),
                    "physicalStoneTracks":DiagnosticRecorder.value(trackingResult.tracks.values.sorted{$0.point<$1.point}),
                    "frameDecoded":frame != nil,"checkAlignment":checkAlignment,"recorderUptime":recorderTime ?? NSNull() as Any,
                    "recorder":self.diagnosticRecorderState])
                self.diagnosticDecisionTicket=nil
            }
            guard self.revision == token else { diagnosticOutcome="discarded stale analysis";self.analyze();return }
            let alignmentTime=captureUptime ?? ProcessInfo.processInfo.systemUptime
            let freshView=supplied != nil && self.running && self.cameraState == .live && !self.frozen
            if freshView,let captureUptime,ProcessInfo.processInfo.systemUptime-captureUptime>1.5 {
                diagnosticOutcome="stale analysis frame discarded";return
            }
            defer {
                self.boardViewFeedback.observe(clear:aligned != nil && analysis.handObstructed != true && result?.lightingBlocked == false && !self.alignmentNeedsRecovery,
                    fresh:freshView,now:alignmentTime,enabled:self.recoverySpeechEnabled && self.recorder.clock.audible,
                    clocksEnabled:self.playMode == .local && self.recorder.clock.enabled,
                    clockRunning:self.recorder.clock.running,settings:self.recorder.clock.sounds)
            }
            if freshView,analysis.handObstructed == false {self.recorder.noteHandClear()}
            if freshView,analysis.handObstructed == true {
                self.recorder.noteHandObstruction()
                self.image=target;self.observation=nil;self.trackedBoardObservation=nil
                self.lastVerifiedLiveFrameAt=nil;self.stable=false;self.stability.reset();self.emptyBoardVerifier.reset()
                diagnosticOutcome="hand over board; waiting for clear frame"
                return
            }
            if freshView,aligned==nil,BoardAlignmentGate.likelyObstruction(alignmentReport) {
                self.recoveryLikelyObstruction=true
            }
            if aligned==nil && !exposureFailure {
                let allowGrace=supplied != nil && self.running && self.cameraState == .live && !self.frozen &&
                    self.playMode == .local && self.recorder.state == .recording && self.recorder.synchronized && !self.alignmentNeedsRecovery
                let hold=self.boardAlignmentGate.shouldHold(report:alignmentReport,now:alignmentTime,allowGrace:allowGrace)
                self.recorder.logAlignmentCheck(alignmentReport,decision:hold ? "hold":"retry without stopping clock",now:alignmentTime)
                if !hold {
                    diagnosticOutcome="marginal alignment; awaiting another fresh check"
                    self.onlineBoard.recordCameraWait("Grid alignment being rechecked",details:alignmentReport)
                    // Keep the last verified interpretation. No move is accepted
                    // or evidence accumulated from this unaligned frame.
                    return
                }
            } else if supplied != nil || exposureFailure {
                // Redrawing an old frame is not a fresh successful check.
                if self.boardAlignmentGate.failures>0 {
                    self.recorder.logAlignmentCheck(alignmentReport,decision:exposureFailure ? "exposure blocked":"alignment recovered",now:alignmentTime)
                }
                self.boardAlignmentGate.reset()
            }
            let trackingCurrent=self.stoneTrackingContext==trackingContext && self.stoneTrackingExpected==trackingExpected
            if trackingCurrent {
                self.establishedStones=trackingResult
                if trackingResult.report.scanned || trackingResult.report.possibleBoardShift || !trackingFresh {
                    self.stoneTrackingReport=trackingResult.report
                }
            }
            if let raw=result {
                result=self.applyLightingRecovery(raw,fresh:supplied != nil && self.running && self.cameraState == .live && !self.frozen,
                    now:captureUptime ?? ProcessInfo.processInfo.systemUptime)
            }
            self.image = target; self.observation = result
            self.trackedBoardObservation=trackingCurrent && result?.lightingBlocked == false ? trackedObservation:result
            if checkStoneAspect {
                self.pendingStoneAxis=stoneAspect?.longAxisRows
                if applyAspect,let stoneAspect {
                    self.rectifiedLongAxisRows=stoneAspect.longAxisRows; self.aspectConfident=true
                    self.aspectStoneCount=stoneAspect.measurements.count
                    self.orientBoardForPlayer()
                }
            }
            self.rectifiedGeometry = corrected == nil ? nil : geometry
            self.rectifiedImage = corrected
            if exposureFailure,let result {
                diagnosticOutcome="unreadable exposure"
                self.lastVerifiedLiveFrameAt=nil;self.stable=false;self.stability.reset();self.emptyBoardVerifier.reset()
                if supplied != nil && self.running && self.cameraState == .live && !self.frozen {
                    self.deliverLiveObservation(result,now:ProcessInfo.processInfo.systemUptime)
                }
                return
            }
            guard let aligned else {
                diagnosticOutcome="grid alignment rejected"
                self.onlineBoard.recordCameraWait("Grid alignment rejected",details:alignmentReport)
                self.lastVerifiedLiveFrameAt=nil
                self.recorder.suspendVision("Grid alignment lost. The recorded game is preserved.",preserveObservations:true)
                self.alignmentNeedsRecovery=true; self.stable=false; self.stability.reset(); self.emptyBoardVerifier.reset()
                if supplied != nil && self.running && self.cameraState == .live && !self.frozen {
                    self.recoveryChecks += 1
                    if self.recoveryChecks >= 3
                        && self.recoveryPrompt.maySearch(now:ProcessInfo.processInfo.systemUptime)
                        && ProcessInfo.processInfo.systemUptime >= self.nextRecoverySearch {
                        if self.recoverySearchExhausted {self.recoverySearchAttempts=0;self.recoverySearchExhausted=false}
                        self.detectGrid(recovering:true)
                    } else if self.recoverySearchAttempts == 0 {
                        self.gridStatus = self.recoveryLikelyObstruction
                            ? "Some stones still match. Waiting for the obstruction to clear; keep the camera and board in place."
                            : "Waiting for a clear, steady view before reassessing alignment."
                    }
                } else if self.recoverySearchAttempts == 0 {
                    self.gridStatus = "Alignment paused. Resume the camera for automatic recovery, or choose Find grid again for this frame."
                }
                return
            }
            let recovered=self.alignmentNeedsRecovery || aligned != calibration
            self.alignmentNeedsRecovery=false
            if supplied != nil && self.awaitingReferenceFrame {
                self.awaitingReferenceFrame = false
                if self.hasReference { self.referenceStatus = "Saved reference reused; alignment checked against the fresh frame." }
                self.gridStatus = "Grid alignment verified against the fresh frame."
            }
            self.resetRecoverySearch()
            if recovered {
                // Tracking has already verified the grid and retained intersection identity.
                // Small valid corrections must not restart move confirmation every frame.
                // Actual alignment loss and full-grid searches suspend the recorder separately.
                self.calibration=aligned; self.corners=aligned.corners
                self.alignmentRecoveries += 1; self.stability.reset(); self.stable=false; self.emptyBoardVerifier.reset()
                self.gridStatus=self.hasReference ? "Grid realigned automatically. The empty-board reference is preserved." : "Grid realigned automatically. Detecting without a reference."
                // Labels belong to the frozen frame's board coordinates, which do not change.
            }
            if reference==nil,let result,let frame {
                let fresh=self.automaticReferenceAllowed && supplied != nil && self.running && self.cameraState == .live && !self.frozen
                if self.emptyBoardVerifier.observe(result,isFresh:fresh,now:ProcessInfo.processInfo.systemUptime) {
                    self.reference=frame; self.referenceImage=target; self.referenceCalibration=aligned
                    self.hasReference=true; self.automaticReference=true
                    self.setTrackingAnchor(); self.bindReferenceCamera(); self.persistReference(); self.emptyBoardVerifier.reset()
                    self.message="Empty board verified. A reference was captured automatically."
                }
            }
            if supplied != nil, self.running, self.cameraState == .live, !self.frozen, let result {
                let now=ProcessInfo.processInfo.systemUptime
                self.lastVerifiedLiveFrameAt=result.lightingBlocked ? nil : now
                recorderTime=now;diagnosticOutcome="delivered to recorder"
                if trackingCurrent && trackingResult.report.possibleBoardShift && self.tracksCameraMotion {
                    diagnosticOutcome="established stones suggest board movement"
                    self.alignmentNeedsRecovery=true
                    self.detectGrid(recovering:true)
                    return
                }
                var delivered=trackingCurrent && self.stoneTrackingContext==trackingContext && !result.lightingBlocked ? (trackedObservation ?? result):result
                delivered.capturedAt=captureUptime;delivered.handObstructed=analysis.handObstructed
                self.deliverLiveObservation(delivered,now:now)
            }
            if let result, newObservation {
                if result.lightingBlocked { self.stability.reset(); self.stable=false }
                else { self.stable = self.stability.update(result) && self.running && self.cameraState == .live && !self.frozen }
            }
        }
    }

    func thresholdChanged() { recorder.suspendVision("Detection settings changed. Checking the accepted position."); emptyBoardVerifier.reset(); revision += 1; stability.reset(); stable = false; analyze() }
    func label(_ index: Int) {
        guard frozen || !running, let observation else { message = "Freeze the frame before labeling."; return }
        labels[index] = (labels[index] ?? observation.readings[index].occupancy).next
    }
    func openPhoto() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let loaded = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560] as CFDictionary) else { return }
        stop(); frozen = true; sourceName = url.lastPathComponent; labels = [:]
        // Same-size photos can share calibration/reference; user must keep viewpoint unchanged.
        if calibration == nil && corners.isEmpty { automaticGridArmed = automaticGridEnabled }
        receive(loaded); cameraStatus = "Photo · \(url.lastPathComponent)"
        message = "Photos can be detected without a reference. Small view changes realign automatically; find the grid again after a larger move."
    }
    var liveBoardReady:Bool {
        guard running,cameraState == .live,!frozen,!detectingGrid,!alignmentNeedsRecovery,
              !awaitingReferenceFrame,calibration?.size==size,visibleObservation?.size==size,
              let lastVerifiedLiveFrameAt else {return false}
        return ProcessInfo.processInfo.systemUptime-lastVerifiedLiveFrameAt<=1
    }
    var validNewGameKomi:Bool {
        let value=(newGameInfo.komi ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        return value.isEmpty || Double(value)?.isFinite == true
    }
    var canStartNewRecording:Bool {validNewGameKomi && newGameClock.validationError==nil && liveBoardReady && recorder.hasVerifiedEmptyBoard(size:size)}
    var canResumeRecording:Bool {liveBoardReady && recorder.state == .paused && size==recorder.game.boardSize}
    var recordingControlReady:Bool {recorder.state == .paused ? canResumeRecording : canStartNewRecording}
    var recordingReadinessTitle:String {
        if recorder.state == .paused {return canResumeRecording ? "Ready to resume recording" : "Not ready to resume recording"}
        if recorder.state == .finished {return canStartNewRecording ? "Ready for a new game" : "New game not ready"}
        return canStartNewRecording ? "Ready to record" : "Not ready to record"
    }
    // Visibility follows the recording mode, never a fluctuating stone classification.
    var showsStartupReferenceControl:Bool {recorder.state == .idle || recorder.state == .finished}
    var canCaptureStartupReference:Bool {
        showsStartupReferenceControl && !startupReferenceCaptured && liveBoardReady
            && stoneCalibrationSession == nil && !boardCorrections.isEditing
    }
    func captureStartupReference() {
        guard canCaptureStartupReference else {return}
        captureReference()
        message="Reference captured. Keep the board empty while readiness is checked."
    }
    var recordingReadiness:String {
        if recorder.awaitingFirstStart {return recorder.status}
        if recorder.state == .finished && canStartNewRecording {return "Empty board verified. Click New game… to begin."}
        return readiness(forNewGame:recorder.state != .paused)
    }
    var newGameReadiness:String { readiness(forNewGame:true) }
    private func readiness(forNewGame:Bool)->String {
        if forNewGame,let error=newGameClock.validationError {return error}
        if forNewGame && !validNewGameKomi {return "Enter a numeric komi in Info or New game before starting."}
        if frozen {return "The camera view is frozen. Resume the camera to check the board."}
        if cameraState == .starting {return "Starting the camera…"}
        if cameraState == .recovering {return "Reconnecting the camera…"}
        if !running || cameraState != .live {return cameraStatus}
        if detectingGrid || calibration == nil {return "Finding the grid… Keep the whole board in view."}
        if alignmentNeedsRecovery {return "Verifying the board alignment…"}
        if let observation, observation.lightingBlocked, let notice=observation.notice {return notice}
        if !liveBoardReady {return "Waiting for a fresh, aligned camera view…"}
        if !forNewGame {
            return canResumeRecording ? "Live grid aligned with the recorded board size." : "Choose the recorded game's board size before resuming."
        }
        if canStartNewRecording {return "Grid aligned and empty board verified."}
        let uncertain=observation?.readings.filter{$0.occupancy == .uncertain}.count ?? 0
        let stones=observation?.readings.filter{$0.occupancy.stone != nil}.count ?? 0
        var reasons=[String]()
        if uncertain>0 {reasons.append("\(uncertain) uncertain \(uncertain == 1 ? "intersection" : "intersections")")}
        if stones>0 {reasons.append("\(stones) possible \(stones == 1 ? "stone" : "stones")")}
        if !reasons.isEmpty {
            if startupReferenceCaptured {
                return "Reference captured. Checking the empty board: \(reasons.joined(separator:" and ")). Keep hands clear; no need to capture again."
            }
            return "Grid aligned. Empty board not verified: \(reasons.joined(separator:" and ")). If the board is empty, use “Board is empty — capture reference”."
        }
        return "Grid aligned. Checking the empty board… Keep hands out of view."
    }
    /// Mode routing is independent of camera acquisition and diagnostic visibility.
    func deliverLiveObservation(_ result:BoardObservation, now:Double) {
        guard stoneCalibrationSession == nil else {return}
        if playMode == .online {
            onlineBoard.consume(result,quarterTurns:viewQuarterTurns,corrections:boardCorrections)
        } else if !boardCorrections.isEditing {
            recorder.consume(boardCorrections.apply(to:result),now:now)
            if canStartNewRecording,hasReference,!startupReferenceCaptured {startupReferenceCaptured=true}
        }
    }
    func startRecording(startPaused:Bool=false) {
        guard playMode == .local, canStartNewRecording else {message=newGameReadiness;return}
        clearBoardCorrections("Manual corrections cleared for the new recording.")
        recorder.start(size:size,info:newGameInfo,handicap:newGameHandicap,clockSettings:newGameClock,startPaused:startPaused)
    }
    func resumeRecording() {
        guard playMode == .local, canResumeRecording else {message=recordingReadiness;return}
        recorder.resume()
    }
    func saveSGFFile() async {
        guard !exportingSGF else { return }
        let mode=playMode
        guard mode == .online || recorder.hasGame else {return}
        if mode == .local && recorder.hasUnfinishedReviews {
            exportStatus="Resolve the red review sections before exporting the complete SGF. Your later moves are preserved.";return
        }
        exportingSGF=true;exportStatus = mode == .online ? "Fetching SGF from SGF Player…" : ""
        defer { exportingSGF=false }
        do {
            let data:Data, filename:String
            if mode == .online {
                let result=try await PhysicalSGFExport.download()
                data=result.data;filename=result.filename
            } else {
                data=Data(recorder.sgf().utf8);filename="Physical Go \(Self.timestamp()).sgf"
            }
            guard mode == playMode else {exportStatus="Export cancelled because the play mode changed.";return}
            let panel=NSSavePanel();panel.title="Save SGF file"
            panel.allowedContentTypes=[UTType(filenameExtension:"sgf") ?? .plainText]
            panel.nameFieldStringValue=filename
            guard panel.runModal() == .OK,let url=panel.url else {exportStatus="";return}
            try data.write(to:url,options:.atomic)
            exportStatus="Saved \(url.lastPathComponent)"
        } catch {exportStatus="Could not save SGF: \(error.localizedDescription)"}
    }
    func saveSample() {
        guard image != nil else { return }
        if running && !frozen { toggleFreeze() }
        let panel = NSSavePanel(); panel.title = "Save experiment sample folder"
        panel.nameFieldStringValue = "Physical Go Sample \(Self.timestamp())"
        try? FileManager.default.createDirectory(at:CaptureFolders.samples,withIntermediateDirectories:true)
        panel.directoryURL=CaptureFolders.samples
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try saveSample(to: folder)
            message = "Saved sample to \(folder.path)"; NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch { message = "Could not save sample: \(error.localizedDescription)" }
    }
    func saveSample(to folder: URL) throws {
        guard let image else { throw SampleError.image }
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw SampleError.exists }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.writePNG(image, to: folder.appendingPathComponent("frame.png"))
        if let referenceImage { try Self.writePNG(referenceImage, to: folder.appendingPathComponent("empty-reference.png")) }
        struct Sample: Encodable {
            let recordingStatus:String; let recordedMoveCount:Int
            let schemaVersion: Int; let name: String; let source: String; let cameraID:String?; let savedAt: Date
            let width: Int; let height: Int; let boardSize: Int
            let displayQuarterTurns: Int
            let perspectiveCorrectedView: Bool; let rectifiedLongAxisRows: Bool
            let calibration: BoardCalibration?; let referenceCalibration: BoardCalibration?; let alignmentNeedsRecovery: Bool; let detectionMode:String; let automaticReference:Bool; let threshold: Double
            let readings: [IntersectionReading]; let stoneFootprints:[StoneFootprint]; let manualLabels: [String: Occupancy]
            let note: String
        }
        let sample = Sample(recordingStatus:recorder.status,recordedMoveCount:recorder.moveCount,schemaVersion: 3, name: sampleName, source: sourceName, cameraID:referenceCameraID ?? (cameraID.isEmpty ? nil : cameraID), savedAt: Date(), width: image.width,
            height: image.height, boardSize: size, displayQuarterTurns:viewQuarterTurns,
            perspectiveCorrectedView:straightenBoard,rectifiedLongAxisRows:rectifiedLongAxisRows,calibration: calibration, referenceCalibration:referenceCalibration,alignmentNeedsRecovery:alignmentNeedsRecovery,detectionMode:hasReference ? "emptyReference" : "localAppearance",automaticReference:automaticReference,threshold: threshold,
            readings: observation?.readings ?? [], stoneFootprints:observation?.footprints ?? [], manualLabels: Dictionary(uniqueKeysWithValues: labels.map { (String($0.key), $0.value) }),
            note: "Experimental observations, not verified moves. Row 0 is top; column 0 is left. Manual label keys are row*boardSize+column. Confidence is a heuristic, not a probability.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sample).write(to: folder.appendingPathComponent("sample.json"), options: .atomic)
        if let sgf = observation?.positionSGF(labels: labels) {
            try sgf.write(to: folder.appendingPathComponent("position.sgf"), atomically: true, encoding: .utf8)
        }
    }
    enum SampleError: LocalizedError { case exists, image
        var errorDescription: String? { self == .exists ? "Choose a new folder name; existing samples are preserved." : "Could not encode the image." }
    }
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw SampleError.image }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw SampleError.image }
    }
    static func timestamp() -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"; return formatter.string(from: Date())
    }
}
