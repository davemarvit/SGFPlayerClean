import Foundation
import Combine

struct PhysicalAISettings: Codable, Equatable {
    enum Strength: String, CaseIterable, Codable {
        case quick, standard, deep
        var visits: Int { switch self {case .quick: return 8; case .standard: return 100; case .deep: return 800} }
        var title: String { switch self {case .quick: return "Quick · lighter search"; case .standard: return "Standard"; case .deep: return "Deep · stronger search"} }
    }
    var size = 19
    var humanBlack = true
    var komi = 6.5
    var rules = "Japanese"
    var strength: Strength = .standard
    var humanRank: String? = "5k"
    // Optional so games saved before test mode continue to decode unchanged.
    var fastTestMode: Bool?
    static let ranks = (1...20).reversed().map {"\($0)k"} + (1...9).map {"\($0)d"}
    static func rankLabel(_ value: String)->String {value.replacingOccurrences(of:"k",with:" kyu").replacingOccurrences(of:"d",with:" dan")}
    var opponentDescription: String {fastTestMode == true ? "Fast test mode · quick replies" : humanRank.map {Self.rankLabel($0)+" KGS-style · approximate"} ?? strength.title}
    var valid: Bool {[9,13,19].contains(size) && komi.isFinite && (-50...50).contains(komi) && komi*2 == (komi*2).rounded() && ["Japanese","Chinese"].contains(rules) && (humanRank == nil || Self.ranks.contains(humanRank!))}
}

/// Canonical camera-grid coordinates, before display rotation. A hardware adapter
/// must independently check calibration, freshness and its own interlocks.
struct PhysicalAIGuidanceTarget: Equatable {
    let session: UUID
    let moveNumber: Int
    let size: Int
    let row: Int
    let col: Int
    let black: Bool
}

@MainActor protocol PhysicalAITestBackend: AnyObject {
    var isRunning:Bool {get}
    var reusableConfiguration:Bool {get}
    func move(_ game:SGFGame) async throws -> String
    func stop()
}

@MainActor final class PhysicalAI: ObservableObject {
    enum Phase: String {case idle, checking, human, thinking, placing, paused, finished, failed}
    struct Failure: LocalizedError {let message: String; var errorDescription: String? {message}}
    struct SavedMove: Codable {let point: Int?; var decisionReceivedAtUnix: Double?}
    struct VerifiedPosition: Codable {
        let cells:[String]
        let cameraContext:String
    }
    struct Snapshot: Codable {
        let id: UUID
        var settings: PhysicalAISettings
        var moves: [SavedMove] = []
        var pendingPlacement = false
        // Optional for saves predating the capture-cleanup clock policy.
        var pendingCaptureCleanup: Bool?
        // All legal captures, including one stone; separate from clock policy.
        var captureIndication: PhysicalCaptureGuidance.Saved?
        var ended = false
        var result: String?
        var timing: PhysicalAITiming?
        var verifiedPosition: VerifiedPosition?
        // Recovery must survive relaunch; ordinary manual pauses remain distinct.
        var guidanceInterruption: String?
        // Independent of being paused; survives deliberate camera-only play.
        var laserRecheckReason: String?
        // Explicitly synthetic fixture identity and immutable prior-game backup.
        var practiceTest: PhysicalAIPracticeContext?
    }
    typealias Generate = @MainActor (SGFGame, PhysicalAISettings) async throws -> String
    @Published var draft = PhysicalAISettings()
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status = "Set up a game against KataGo."
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var cells = [String]()
    /// Reference labels follow the physical position before an unplaced AI move.
    /// The logical board already includes that move (and any captures), but it
    /// must not erase the camera's empty-target evidence merely by being chosen.
    private(set) var referenceCells = [String]()
    private(set) var lastCapturePoints = [Int]()
    @Published private(set) var mismatch: PhysicalBoardMismatch?
    @Published private(set) var error: String?
    @Published var centeringEnabled=false {
        didSet {
            if persistSettings {UserDefaults.standard.set(centeringEnabled,forKey:"PhysicalGo.laserCentering")}
            if !centeringEnabled {clearCentering()}
            syncGuidance()
        }
    }
    @Published private(set) var centeringStone:ImagePoint?
    private var captureGuidance=PhysicalCaptureGuidance()
    var captureGuidancePoint:Int? {captureGuidance.placementConfirmed ? captureGuidance.selected:nil}
    var placementGuidancePoint:Int? {captureGuidance.pending && captureGuidance.placementConfirmed ? nil:pendingPoint}
    var remainingCapturedStones:Int {captureGuidance.remainingCount}
    private var centeringTarget:PhysicalLaserGuidance.Target?
    private var centeringWitness:(center:ImagePoint,color:Occupancy,first:Double,last:Double,count:Int)?
    private let persistSettings:Bool
    let laser: PhysicalLaserGuidance
    @Published private(set) var timing=PhysicalAITiming()
    private let uptime: ()->Double
    private let wallTime: ()->Double
    private let directory: URL
    private let practiceStore:PhysicalAIPracticeStore
    private var currentSnapshotData:Data?
    @Published private(set) var practiceError:String?
    private let recognitionTrace: AIRecognitionTrace?
    private let generate: Generate
    private let testWorker: TestWorker
    private var task: Task<Void,Never>?
    private var generation = UUID()
    private var witness: [String]?
    private var witnessStart = 0.0
    private var witnesses = 0
    private var lastFrame: Double?
    private var lastMatch: Double?
    private var verifiedCells: [String]?
    private var verifiedCameraContext: String?
    private var loadFailed = false
    private var illegalMoveTracker=PhysicalIllegalMoveWarning.Tracker()
    private var illegalMoveContext: String?
    private var illegalMovePlayer: SGFPlayer?
    private(set) var illegalMoveWarning: PhysicalIllegalMoveWarning.Candidate?
    var hasGame: Bool {snapshot != nil}
    var fastTestMode: Bool {(snapshot?.ended == false ? snapshot?.settings.fastTestMode:draft.fastTestMode) == true}
    var canChangeTestMode: Bool {!hasGame || [.paused,.finished,.failed].contains(phase)}
    func setFastTestMode(_ enabled:Bool) {
        guard canChangeTestMode else {return}
        testWorker.stop()
        if var s=snapshot,!s.ended {
            s.settings.fastTestMode=enabled
            do {try save(s)} catch {fail(error.localizedDescription);return}
        }
        draft.fastTestMode=enabled
    }
    var size: Int {snapshot?.settings.size ?? draft.size}
    var human: Stone {snapshot?.settings.humanBlack == false ? .white:.black}
    var turn: Stone {(snapshot?.moves.count ?? 0)%2 == 0 ? .black:.white}
    var active: Bool {hasGame && ![.paused,.finished,.failed].contains(phase)}
    var pendingPoint: Int? {snapshot?.pendingPlacement == true ? snapshot?.moves.last?.point:nil}
    var captureCleanupPending: Bool {
        // Also gate legacy flags by the legal capture count: older builds
        // marked single-stone captures for a pause too.
        lastCapturePoints.count>=2 &&
        (snapshot?.pendingCaptureCleanup == true || snapshot?.pendingPlacement == true)
    }
    var clockPausedForCaptureCleanup: Bool {active && captureCleanupPending}
    var guidanceTarget: PhysicalAIGuidanceTarget? {
        guard phase == .placing, (!captureGuidance.pending || !captureGuidance.placementConfirmed), let s=snapshot, let p=pendingPoint else {return nil}
        return .init(session:s.id,moveNumber:s.moves.count,size:size,row:p/size,col:p%size,black:human == .white)
    }
    var canPass: Bool {canPass(at:ProcessInfo.processInfo.systemUptime)}
    func canPass(at now: Double)->Bool {phase == .human && lastMatch.map {(0..<1.5).contains(now-$0)} == true}
    var savedURL: URL? {snapshot.map {directory.appendingPathComponent($0.id.uuidString+".sgf")}}
    init(directory: URL? = nil, generate: Generate? = nil, laser: PhysicalLaserGuidance? = nil, testWorker: TestWorker? = nil,
         practiceStore:PhysicalAIPracticeStore?=nil,
         uptime: @escaping ()->Double = {ProcessInfo.processInfo.systemUptime},
         wallTime: @escaping ()->Double = {Date().timeIntervalSince1970}) {
        self.laser=laser ?? PhysicalLaserGuidance();self.uptime=uptime;self.wallTime=wallTime
        persistSettings=directory == nil
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Physical Go/AI Games")
        self.practiceStore=practiceStore ?? PhysicalAIPracticeStore(directory:self.directory)
        recognitionTrace=directory == nil ? AIRecognitionTrace(url:self.directory.appendingPathComponent("recognition-trace.json")):nil
        let testWorker=testWorker ?? TestWorker();self.testWorker=testWorker
        self.generate=generate ?? {game,settings in
            if settings.fastTestMode == true {return try await testWorker.move(game)}
            return try await Self.kataMove(game,visits:settings.strength.visits,rank:settings.humanRank)
        }
        if persistSettings {centeringEnabled=UserDefaults.standard.bool(forKey:"PhysicalGo.laserCentering")}
        self.laser.onHardFault = { [weak self] event in self?.pauseForGuidanceFault(event) }
        let url=self.directory.appendingPathComponent("current.json")
        if FileManager.default.fileExists(atPath:url.path) {
            do {
                let savedData=try Data(contentsOf:url)
                let saved=try JSONDecoder().decode(Snapshot.self,from:savedData)
                guard saved.settings.valid else {throw Failure(message:"Invalid saved AI game settings.")}
                let player=SGFPlayer();var empty=Self.game(saved);empty.moves=[];player.load(game:empty)
                for move in saved.moves {
                    if let p=move.point, !(0..<saved.settings.size*saved.settings.size).contains(p) {throw Failure(message:"Invalid saved AI move.")}
                    guard !player.lastTwoMovesWerePasses, player.tryPlayMove(color:player.turn,x:move.point.map{$0%saved.settings.size} ?? -1,y:move.point.map{$0/saved.settings.size} ?? -1) == nil else {throw Failure(message:"The saved AI game has invalid history.")}
                }
                currentSnapshotData=savedData
                snapshot=saved;draft=saved.settings;refreshBoard()
                if let reason=saved.laserRecheckReason ?? saved.guidanceInterruption {self.laser.restoreGameFaultRequirement(reason)}
                if let verified=saved.verifiedPosition,verified.cells.count==cells.count,
                   verified.cells.allSatisfy({["empty","black","white"].contains($0)}),!verified.cameraContext.isEmpty {
                    verifiedCells=verified.cells;verifiedCameraContext=verified.cameraContext
                }
                timing=saved.timing?.saved ?? PhysicalAITiming(blackToPlay:player.turn == .black)
                phase=saved.ended ? .finished:.paused
                status=saved.ended ? "Game ended. SGF saved.":saved.guidanceInterruption != nil
                    ? "AI game preserved after a laser interruption. Resolve the issue and recheck the laser before Resume."
                    : "AI game restored. Resume to verify the physical board."
            } catch {self.error="Could not open saved AI game: \(error.localizedDescription)";loadFailed=true;phase = .failed}
        }
    }
    static func game(_ s: Snapshot)->SGFGame {
        var game=SGFGame();game.boardSize=s.settings.size
        game.info = .init(event:"Physical Go AI practice",playerBlack:s.settings.humanBlack ? "Human":"KataGo",playerWhite:s.settings.humanBlack ? "KataGo":"Human",result:s.result,komi:String(s.settings.komi),rules:s.settings.rules)
        game.moves=s.moves.enumerated().map {index,move in (index%2 == 0 ? Stone.black:.white,move.point.map {($0%s.settings.size,$0/s.settings.size)})}
        return game
    }
    static func sgf(_ s: Snapshot)->String {
        let g=game(s)
        var props=["GM":["1"],"FF":["4"],"CA":["UTF-8"],"SZ":[String(g.boardSize)],"RU":[s.settings.rules],"KM":[String(s.settings.komi)],"PB":[g.info.playerBlack!],"PW":[g.info.playerWhite!],"C":["KataGo AI practice; \(s.settings.opponentDescription). Untimed. HumanSL ranks are approximate; search effort is not a calibrated rank."]]
        if let test=s.practiceTest {
            props["EV"]=["Physical Go test position · "+test.position.title]
            props["C"]=[(props["C"]?.first ?? "")+" "+test.position.syntheticDetail+" Subsequent moves use normal physical confirmation."]
        }
        if let result=s.result {props["RE"]=[result]}
        let nodes=[SGFNode(props:props)]+g.moves.map {SGFNode(props:[$0.0 == .black ? "B":"W":[$0.1.map{SGFCoordinates.toSGF(x:$0.0,y:$0.1)} ?? ""]])}
        return SGFWriter.serialize(SGFTree(branches:[.init(sequence:nodes)]))
    }
    private func save(_ value: Snapshot)throws {
        var s=value;s.timing=timing.saved(at:uptime())
        s.laserRecheckReason=laser.gameFaultRecheckReason
        s.verifiedPosition=verifiedCells.flatMap {cells in verifiedCameraContext.map {VerifiedPosition(cells:cells,cameraContext:$0)}}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        // current.json is authoritative. SGF is a derived export and can be retried.
        let data=try JSONEncoder().encode(s)
        try data.write(to:directory.appendingPathComponent("current.json"),options:.atomic)
        currentSnapshotData=data;snapshot=s;refreshBoard()
        try Self.sgf(s).write(to:directory.appendingPathComponent(s.id.uuidString+".sgf"),atomically:true,encoding:.utf8)
    }
    private func refreshBoard() {
        guard let s=snapshot else {return}
        let player=SGFPlayer();player.load(game:Self.game(s));player.seek(to:s.moves.count)
        cells=player.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"}
        if !s.moves.isEmpty {player.seek(to:s.moves.count-1)}
        let before=player.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"}
        lastCapturePoints=cells.indices.filter {before[$0] != "empty" && cells[$0] == "empty"}
        referenceCells=s.pendingPlacement ? before:cells
        if let saved=s.captureIndication,saved.moveNumber==s.moves.count,!s.ended,!lastCapturePoints.isEmpty,
           saved.acceptedAtUnix.isFinite,saved.acceptedAtUnix>0 {
            captureGuidance.configure(identity:.init(session:s.id,moveNumber:s.moves.count),
                prisoners:Dictionary(uniqueKeysWithValues:lastCapturePoints.map {($0,before[$0])}),
                placement:s.pendingPlacement ? s.moves.last?.point.map {($0,cells[$0])}:nil,removed:saved.removed,evidenceAfter:uptime())
        } else {captureGuidance.clear()}
    }
    private var practiceUnresolvedGuidanceReason:String? {
        laser.controllerResetRequired ? "controller_fault":laser.gameFaultRecheckReason
    }
    var canLoadPracticePosition:Bool {
        !loadFailed && !active && snapshot?.practiceTest==nil && (snapshot==nil || [.paused,.finished].contains(phase))
    }
    var canReturnFromPracticePosition:Bool {
        !loadFailed && !active && snapshot?.practiceTest != nil && [.paused,.finished].contains(phase)
    }
    @discardableResult func loadPracticePosition(_ position:PhysicalAIPracticePosition)->Bool {
        guard canLoadPracticePosition else {practiceError="Pause the game before loading a test position. Return from the current test before choosing another.";return false}
        do {
            let id=UUID(),prepared=try practiceStore.prepare(position:position,testID:id,previousGameID:snapshot?.id,
                previousCurrent:currentSnapshotData,draft:draft)
            var settings=PhysicalAISettings();settings.size=19;settings.humanBlack=position.humanBlack
            settings.fastTestMode=true;settings.humanRank=nil;settings.strength = .quick
            let test=Snapshot(id:id,settings:settings,moves:position.moves.map {SavedMove(point:$0)},
                timing:PhysicalAITiming(),guidanceInterruption:practiceUnresolvedGuidanceReason ?? snapshot?.guidanceInterruption ?? snapshot?.laserRecheckReason,
                laserRecheckReason:practiceUnresolvedGuidanceReason ?? snapshot?.laserRecheckReason,practiceTest:prepared.context)
            let data=try JSONEncoder().encode(test)
            try practiceStore.activate(prepared,current:data,sgf:Data(Self.sgf(test).utf8))
            installPracticeSnapshot(test,data:data,draft:settings)
            status="Test position loaded and paused. Match the indicated board, then Resume for normal camera verification."
            return true
        } catch {practiceError="Could not load test position. The current game is unchanged. "+error.localizedDescription;return false}
    }
    @discardableResult func returnFromPracticePosition()->Bool {
        guard canReturnFromPracticePosition,let current=snapshot,let context=current.practiceTest,
              context.testID==current.id,let currentData=currentSnapshotData else {practiceError="Pause the current test before returning to its saved game.";return false}
        do {
            let backup=try practiceStore.readBackup(context)
            var restored=try backup.previousCurrent.map {try JSONDecoder().decode(Snapshot.self,from:$0)}
            guard restored?.id==backup.previousGameID,restored?.practiceTest==nil else {throw Failure(message:"The prior game backup does not match this test.")}
            if restored==nil,laser.gameFaultNeedsRecheck || laser.controllerResetRequired {
                throw Failure(message:"Recheck the laser before returning to an empty setup. The test and fault remain saved.")
            }
            var restoredData=backup.previousCurrent
            if var prior=restored {
                let unresolved=practiceUnresolvedGuidanceReason ?? (laser.gameFaultNeedsRecheck ? current.guidanceInterruption:nil)
                let recheck=unresolved ?? prior.laserRecheckReason
                let interruption=unresolved ?? prior.guidanceInterruption ?? prior.laserRecheckReason
                if recheck != prior.laserRecheckReason || interruption != prior.guidanceInterruption {
                    prior.laserRecheckReason=recheck;prior.guidanceInterruption=interruption
                    restored=prior
                    // Overlay only fault fields; preserve unknown original JSON
                    // metadata as well as the known history and elapsed clocks.
                    var fields=try JSONSerialization.jsonObject(with:backup.previousCurrent!) as! [String:Any]
                    if let recheck {fields["laserRecheckReason"]=recheck} else {fields.removeValue(forKey:"laserRecheckReason")}
                    if let interruption {fields["guidanceInterruption"]=interruption} else {fields.removeValue(forKey:"guidanceInterruption")}
                    restoredData=try JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys])
                }
            }
            try practiceStore.restore(context,expectedCurrent:currentData,replacement:restoredData)
            installPracticeSnapshot(restored,data:restoredData,draft:backup.previousDraft)
            status=restored==nil ? "Test closed. Your previous setup is restored.":restored?.ended==true ? "Finished game restored.":"Saved game restored and paused. Match its board before Resume."
            return true
        } catch {practiceError="Could not return to the saved game. The current test is unchanged. "+error.localizedDescription;return false}
    }
    private func installPracticeSnapshot(_ saved:Snapshot?,data:Data?,draft restoredDraft:PhysicalAISettings) {
        phase = .paused // Prevent reentrant guidance callbacks during cancellation.
        cancel();captureGuidance.clear();verifiedCells=nil;verifiedCameraContext=nil
        snapshot=saved;currentSnapshotData=data;draft=restoredDraft
        timing=saved?.timing?.saved ?? PhysicalAITiming(blackToPlay:(saved?.moves.count ?? 0)%2==0)
        cells=[];referenceCells=[];lastCapturePoints=[];error=nil;practiceError=nil
        if let saved {
            refreshBoard()
            if let reason=saved.laserRecheckReason ?? saved.guidanceInterruption {laser.restoreGameFaultRequirement(reason)}
            phase=saved.ended ? .finished:.paused
        } else {phase = .idle}
        syncGuidance()
    }
    @discardableResult func start()->Bool {
        defer {syncGuidance()}
        guard snapshot?.practiceTest==nil else {status="Return from the test position before starting another game.";return false}
        guard draft.valid,!loadFailed, !hasGame || phase == .finished else {return false}
        cancel();timing=PhysicalAITiming();verifiedCells=nil;verifiedCameraContext=nil;error=nil
        do {try save(Snapshot(id:UUID(),settings:draft));phase = .checking;status="Clear the board. Waiting for a verified empty position.";return true}
        catch {fail(error.localizedDescription);return false}
    }
    private func pauseForGuidanceFault(_ event:PhysicalLaserGuidance.HardFault) {
        guard active,laser.enabled,event.session.source=="ai",var saved=snapshot,
              event.session.session==saved.id,event.session.size==saved.settings.size else {return}
        // Freeze at detection, before process cancellation or file IO can add
        // downtime. Phase changes first prevent reentrant laser ticks pausing twice.
        phase = .paused;timing.pause(at:event.detectedAtUptime)
        saved.guidanceInterruption=event.reason
        cancel()
        do {try save(saved)} catch {fail(error.localizedDescription);return}
        status="AI game paused after a laser interruption. History, placement and clocks are preserved. Resolve the issue, recheck the laser, then Resume."
    }
    func pause() {
        defer {syncGuidance()}
        guard active else {return}
        cancel(preserveIdleTestWorker:true);timing.pause(at:uptime());if let s=snapshot {do {try save(s)} catch {fail(error.localizedDescription);return}};phase = .paused;status="AI game paused. Resume when the board is ready."
    }
    func shutdown() {pause();testWorker.stop()}
    func confirmLaserPhysicallyOff() {
        guard phase == .paused,let saved=snapshot,saved.guidanceInterruption != nil else {return}
        laser.setEnabled(false) // User confirmation is distinct from a driver OFF receipt.
        if laser.confirmPhysicalLaserOff(session:.init(source:"ai",session:saved.id,size:saved.settings.size)) {
            status="Laser power-off confirmed by you. Waiting for a new clear camera frame before Resume; driver OFF remains unconfirmed."
        } else {status="Camera view is unavailable. Keep laser power switched off, restore the camera, then confirm again. The game remains paused."}
    }
    func resume() {
        defer {syncGuidance()}
        guard var s=snapshot,[.paused,.failed].contains(phase),!loadFailed else {return}
        if s.guidanceInterruption != nil,!laser.readyToResumeFaultPausedGame(session:s.id) {
            status="AI game remains paused. Resolve and recheck the laser before Resume, or explicitly continue without laser guidance."
            return
        }
        let preserveIdle = phase == .paused && s.guidanceInterruption == nil
        s.guidanceInterruption=nil
        cancel(preserveIdleTestWorker:preserveIdle);error=nil
        if s.moves.count>=2,s.moves.suffix(2).allSatisfy({$0.point == nil}) {s.ended=true}
        if s.pendingCaptureCleanup == true,lastCapturePoints.count<2 {s.pendingCaptureCleanup=false}
        if !s.ended,s.pendingPlacement,!captureCleanupPending {timing.resume(at:uptime())}
        do {try save(s);phase=s.ended ? .finished:s.pendingPlacement ? .placing:.checking;status=s.ended ? "Both players passed. Game saved; no score has been agreed.":"Match the physical board to the saved position."}
        catch {fail(error.localizedDescription)}
    }
    func finish(resign: Bool = false) {
        defer {syncGuidance()}
        guard var s=snapshot,!s.ended else {return}
        cancel();timing.pause(at:uptime());s.ended=true;s.pendingPlacement=false;s.pendingCaptureCleanup=false;s.captureIndication=nil
        if resign {s.result=human == .black ? "W+R":"B+R"}
        do {try save(s);phase = .finished;status=resign ? "You resigned. SGF saved.":"Game ended. SGF saved without an agreed score."}
        catch {fail(error.localizedDescription)}
    }
    func interruptObservation(reason:String="state_reset",preserveGuidance:Bool=false) {
        clearIllegalMoveWarning()
        if reason != "state_reset" {centeringWitness=nil}
        // Illuminated/buffered frames are deliberately not new capture evidence;
        // retain the selected operation until hand/positive-removal OFF occurs.
        if reason != "waiting_for_dark_laser_evidence" {captureGuidance.invalidate(after:uptime())}
        if active {traceRecognition(reason,details:["witnessesBeforeReset":witnesses])}
        witness=nil;witnesses=0;lastFrame=nil;lastMatch=nil;mismatch=nil
        if !preserveGuidance {laser.resetHandRecoveryEvidence()}
    }
    func noteHandClearanceStall(_ evidence:HandOutlineTracker.StallEvidence,calibration:BoardCalibration) {
        guard let snapshot else {return}
        recognitionTrace?.recordHandStall(evidence,calibration:calibration,session:snapshot.id,
            moveNumber:snapshot.moves.count,atUnix:wallTime())
        traceRecognition("hand_clearance_delayed",details:["seconds":evidence.disagreementSeconds,
            "edge":evidence.result.edge ?? -1,"outlineReason":evidence.result.reason])
    }
    private func traceRecognition(_ reason:String,details:[String:Any]=[:]) {
        var event=details
        event["atUnix"]=wallTime();event["reason"]=reason;event["phase"]=phase.rawValue
        event["moveNumber"]=snapshot?.moves.count;event["session"]=snapshot?.id.uuidString
        recognitionTrace?.record(event)
    }
    private func clearCentering() {centeringStone=nil;centeringTarget=nil;centeringWitness=nil}
    private func cancel(preserveIdleTestWorker:Bool=false) {
        laser.setPlaySession(nil);captureGuidance.invalidate(dropPlacement:true,after:uptime());clearCentering()
        generation=UUID();task?.cancel();task=nil
        if preserveIdleTestWorker && fastTestMode {testWorker.cancelKeepingIdle()} else {testWorker.stop()}
        laser.setTarget(nil);laser.clearAlignmentPreparation();laser.invalidateCamera();interruptObservation()
    }
    private func observeCentering(_ observation:BoardObservation,ambiguous:Set<Int>,stamp:Double,now:Double) {
        guard centeringEnabled,laser.enabled,[.human,.checking].contains(phase),pendingPoint==nil,
              !captureCleanupPending,!captureGuidance.pending,let snapshot,!snapshot.moves.isEmpty else {clearCentering();return}
        // Locate the disk itself, without resolving its intersection. Strong
        // outlines can describe one stone claimed by two neighboring points.
        var candidates=observation.centeringEvidence.filter{$0.shape.quality>=0.94}
        candidates += (observation.footprints+observation.placementFits).compactMap {shape in
            let p=shape.row*size+shape.col
            guard observation.readings.indices.contains(p),ambiguous.contains(p),
                  observation.readings[p].occupancy.stone != nil,observation.readings[p].confidence>=0.9,
                  shape.quality>=0.9 else {return nil}
            return StoneCenteringEvidence(color:observation.readings[p].occupancy,shape:shape)
        }
        candidates=candidates.filter {
            let shape=$0.shape,c=shape.center
            return c.x.isFinite && c.y.isFinite && (0...Double(size-1)).contains(c.x) && (0...Double(size-1)).contains(c.y) &&
                (0.36...0.65).contains(shape.radiusCol) && (0.33...0.65).contains(shape.radiusRow) &&
                max(abs(c.x-c.x.rounded()),abs(c.y-c.y.rounded()))>=0.30
        }.sorted {a,b in
            if let old=centeringStone {
                let da=hypot(a.shape.center.x-old.x,a.shape.center.y-old.y),db=hypot(b.shape.center.x-old.x,b.shape.center.y-old.y)
                if (da<0.25) != (db<0.25) {return da<0.25}
            }
            if abs(a.shape.center.y-b.shape.center.y)>0.18 {return a.shape.center.y<b.shape.center.y}
            if abs(a.shape.center.x-b.shape.center.x)>0.18 {return a.shape.center.x<b.shape.center.x}
            return a.shape.quality>b.shape.quality
        }
        guard let candidate=candidates.first else {clearCentering();return}
        let center=candidate.shape.center
        // A replacement disk is not evidence for the previously selected aim.
        // Cancel immediately, then require fresh same-color stable observations
        // before publishing the measured replacement center. Use the witness
        // tolerance here too, so a small move cannot renew a stale target.
        if let target=centeringTarget,let selected=target.stoneCenter,
           hypot(selected.x-center.x,selected.y-center.y)>=0.12 || target.black != (candidate.color == .black) {
            clearCentering();syncGuidance()
        }
        if let old=centeringWitness,old.color==candidate.color,
           hypot(old.center.x-center.x,old.center.y-center.y)<0.12,
           stamp>old.last,stamp-old.last<=0.6 {
            centeringWitness=(old.center,old.color,old.first,stamp,old.count+1)
        } else {centeringWitness=(center,candidate.color,stamp,stamp,1)}
        guard let witness=centeringWitness,witness.count>=3,stamp-witness.first>=0.45 else {return}
        if centeringStone.map({hypot($0.x-center.x,$0.y-center.y)>0.18}) ?? true {
            centeringStone=center
            // Integer fields identify the containing calibrated cell only.
            // stoneCenter is the actual aim; no intended intersection is chosen.
            centeringTarget = .init(source:"ai",session:snapshot.id,moveNumber:snapshot.moves.count,size:size,
                row:Int(floor(center.y)),col:Int(floor(center.x)),black:candidate.color == .black,
                decisionReceivedAtUnix:wallTime(),purpose:"centering",stoneCenter:center)
            syncGuidance()
        }
        laser.verifyCenteringTarget(capturedAt:stamp,now:now)
    }
    private var currentIllegalMoveContext: String {
        "\(snapshot?.id.uuidString ?? "none")/\(snapshot?.moves.count ?? 0)/\(snapshot?.settings.rules ?? "none")/\(generation)/\(laser.cameraContext ?? "board-only")/\(laser.frames.streamEpoch)"
    }
    private func clearIllegalMoveWarning() {
        illegalMoveTracker.clear();illegalMoveContext=nil;illegalMovePlayer=nil
        if illegalMoveWarning != nil {
            illegalMoveWarning=nil;mismatch=nil
            status="Checking the physical board."
        }
    }
    /// This diagnostic uses raw positive readings and never changes legal-move
    /// acceptance. In particular, suicide does not pass the legal candidate filter.
    private func observeIllegalMove(_ observation:BoardObservation,ambiguous:Set<Int>,stamp:Double,now:Double)->PhysicalIllegalMoveWarning.Candidate? {
        let acceptsAttempt=phase == .human || (phase == .checking && snapshot?.moves.isEmpty == false)
        guard acceptsAttempt,turn==human,pendingPoint==nil,let snapshot,!snapshot.pendingPlacement,
              observation.capturedAt != nil,observation.manualPoints.isEmpty,ambiguous.isEmpty,
              observation.readings.allSatisfy({$0.occupancy != .uncertain && $0.confidence>=0.8}) else {
            clearIllegalMoveWarning();return nil
        }
        let added=observation.readings.filter {cells[$0.row*size+$0.col]=="empty" && $0.occupancy.rawValue==human.rawValue}
        guard added.count==1,let point=added.first.map({$0.row*size+$0.col}),
              captureGuidance.permitsReply(at:point) else {clearIllegalMoveWarning();return nil}
        var raw=Array<String?>(repeating:nil,count:cells.count),confidence=Array(repeating:0.0,count:cells.count)
        for reading in observation.readings {
            let p=reading.row*size+reading.col;raw[p]=reading.occupancy.rawValue;confidence[p]=reading.confidence
        }
        let context=currentIllegalMoveContext;illegalMoveContext=context
        if illegalMovePlayer==nil {illegalMovePlayer=player()}
        guard let diagnosticPlayer=illegalMovePlayer else {return nil}
        // consume's admission above already established clear, calibrated,
        // dark-safe input; this tracker independently requires unique fresh stamps.
        let candidate=illegalMoveTracker.observe(player:diagnosticPlayer,context:context,human:human,
            acceptsHumanAttempt:true,pendingAIPlacement:false,
            evidence:.init(frameID:String(stamp.bitPattern),capturedAt:stamp,cells:raw,confidence:confidence,
                           ambiguous:ambiguous,hand:observation.handObstructed,aligned:true,confirmedDark:true),
            now:now,permitsReply:{[captureGuidance] in captureGuidance.permitsReply(at:$0)})
        if candidate==nil,illegalMoveWarning != nil {illegalMoveWarning=nil;mismatch=nil;status="Checking the physical board."}
        illegalMoveWarning=candidate
        return candidate
    }
    private func fail(_ message: String) {cancel();timing.pause(at:uptime());error=message;phase = .failed;status="AI game paused. Resolve the issue, then Retry."}
    private func player()->SGFPlayer {
        let p=SGFPlayer();if let s=snapshot {p.load(game:Self.game(s));p.seek(to:s.moves.count)};return p
    }
    func consume(_ observation: BoardObservation, now: Double) {
        defer {syncGuidance()}
        guard active else {return}
        let observationGeneration=generation
        if let context=illegalMoveContext,context != currentIllegalMoveContext {clearIllegalMoveWarning()}
        let stamp=observation.capturedAt ?? now
        // Retain only previously observed cells in the same camera/grid context.
        // Fresh positive contradictions still override this history below;
        // new stones and capture removals cannot borrow an unchanged-cell label.
        if let context=verifiedCameraContext,laser.cameraContext != context {
            verifiedCells=nil;verifiedCameraContext=nil
            traceRecognition("verified_context_changed")
        }
        var outcome="observation_rejected",detail=[String:Any]()
        if stamp.isFinite,now.isFinite {detail["capturedAtUptime"]=stamp;detail["ageSeconds"]=now-stamp}
        defer {detail["witnesses"]=witnesses;traceRecognition(outcome,details:detail)}
        if observation.handObstructed == true {laser.suppress("hand_entered_board")}
        if laser.target?.purpose==nil,let point=pendingPoint, now>=stamp,now-stamp<1.5,
           observation.size==size,!observation.lightingBlocked,
           observation.readings.contains(where:{(0..<size).contains($0.row) && (0..<size).contains($0.col) && $0.row*size+$0.col==point && ($0.occupancy == .black || $0.occupancy == .white) && $0.confidence>=0.8}) {
            laser.suppress("stone_seen_at_target")
        }
        if let target=laser.target,target.purpose=="capture",now>=stamp,now-stamp<1.5,
           observation.size==size,!observation.lightingBlocked,
           observation.readings.contains(where:{$0.row==target.row && $0.col==target.col &&
                ($0.occupancy == .empty || ($0.occupancy.stone != nil && $0.occupancy.rawValue != (target.black ? "black":"white"))) && $0.confidence>=0.8}) {
            // A lit-frame suspicion only requests OFF. Dark stable evidence below
            // is still required before removal is accepted or another target wins.
            laser.suppress("capture_evidence_changed")
        }
        guard active,generation==observationGeneration else {return}
        guard laser.acceptsObservation(capturedAt:stamp,now:now) else {outcome="waiting_for_dark_laser_evidence";interruptObservation(reason:outcome);return}
        guard stamp.isFinite,now-stamp>=0,now-stamp<1.5,
              observation.size==size,!observation.lightingBlocked,observation.handObstructed == false,
              observation.readings.count==size*size else {
            outcome=observation.handObstructed != false ? "hand_or_unknown_hand":observation.lightingBlocked ? "lighting_blocked":"invalid_or_stale_frame"
            interruptObservation(reason:outcome);return
        }
        if let lastFrame, stamp<=lastFrame {outcome="duplicate_frame";return}
        if let lastFrame,stamp-lastFrame>0.6 {detail["frameGapSeconds"]=stamp-lastFrame;interruptObservation(reason:"frame_gap")}
        lastFrame=stamp
        var values=Array(repeating:"",count:size*size),seen=Set<Int>(),unknown=0
        let expected=cells.map {Occupancy(rawValue:$0)!}
        var ambiguous=Set(observation.assignmentOffsets(confirmedBoard:expected).filter {$0.value>=0.30}.map(\.key))
        for r in observation.readings {
            guard (0..<size).contains(r.row),(0..<size).contains(r.col),r.confidence.isFinite,
                  seen.insert(r.row*size+r.col).inserted else {interruptObservation();return}
        }
        // Color confidence does not establish a unique intersection. A stone
        // between crossings can produce a strong label at one and an uncertain
        // reading at its neighbor, even when its fitted outline underestimates
        // displacement. Previously verified empty neighbors cannot resolve that
        // new assignment. Established stones may still retain unchanged labels.
        let byPoint=Dictionary(uniqueKeysWithValues:observation.readings.map {($0.row*size+$0.col,$0)})
        var unresolvedNeighbors=[Int:[Int]]()
        for r in observation.readings where r.occupancy.stone != nil && r.confidence>=0.8 {
            let point=r.row*size+r.col
            guard r.occupancy.rawValue != cells[point] || point==pendingPoint else {continue}
            var neighbors=[Int]()
            for row in max(0,r.row-1)...min(size-1,r.row+1) {
                for col in max(0,r.col-1)...min(size-1,r.col+1) {
                    let other=row*size+col
                    guard other != point,cells[other]=="empty",let reading=byPoint[other] else {continue}
                    if reading.occupancy == .uncertain || reading.confidence<0.8 {neighbors.append(other)}
                }
            }
            if !neighbors.isEmpty {unresolvedNeighbors[point]=neighbors;ambiguous.insert(point)}
        }
        detail["ambiguousPoints"]=ambiguous.sorted()
        if !unresolvedNeighbors.isEmpty {
            detail["unresolvedPlacementNeighbors"]=unresolvedNeighbors.map { ["point":$0.key,"neighbors":$0.value] as [String:Any] }
        }
        detail["readingsOfInterest"]=observation.readings.filter {
            $0.occupancy.rawValue != cells[$0.row*size+$0.col] || $0.confidence<0.8 || $0.row*size+$0.col==pendingPoint
        }.prefix(40).map { ["point":$0.row*size+$0.col,"occupancy":$0.occupancy.rawValue,"confidence":$0.confidence] as [String:Any] }
        // The engine supplied this exact pending coordinate. A clear validated
        // view authorizes its placement cue even if stone classification is
        // uncertain here. Positive stone evidence above still latches OFF, and
        // all physical placement/capture confirmation below remains independent.
        let pendingMoveCue=pendingPoint != nil && laser.target?.purpose==nil
        if pendingMoveCue {
            laser.verifyMoveTarget(capturedAt:stamp,now:now)
        } else if laser.target?.purpose==nil {laser.resetHandRecoveryEvidence()}
        guard active,generation==observationGeneration else {return}
        observeCaptures(observation,ambiguous:ambiguous,stamp:stamp,now:now)
        guard active,generation==observationGeneration else {return}
        if let warning=observeIllegalMove(observation,ambiguous:ambiguous,stamp:stamp,now:now) {
            clearCentering()
            outcome="illegal_move";detail["rejection"]=warning.rejection.rawValue;detail["point"]=warning.point
            witness=nil;witnesses=0;lastMatch=nil
            var raw=cells
            for reading in observation.readings {raw[reading.row*size+reading.col]=reading.occupancy.rawValue}
            mismatch = .init(expected:cells,observed:raw)
            status=warning.rejection.rawValue+(warning.restorePoints.isEmpty
                ? " Remove the stone marked ×."
                : " Remove the stone marked × and restore the stones at the blue rings.")
            return
        }
        observeCentering(observation,ambiguous:ambiguous,stamp:stamp,now:now)
        guard active,generation==observationGeneration else {return}
        for r in observation.readings {
            let index=r.row*size+r.col
            if ambiguous.contains(index),r.occupancy.stone != nil,r.confidence>=0.8,
               r.occupancy.rawValue != cells[index] || unresolvedNeighbors[index] != nil {
                // Verified history may retain an obscured unchanged stone;
                // it must not erase a positively seen, unresolved new stone.
                outcome="ambiguous_new_stone";detail["blockingPoint"]=index
                witness=nil;witnesses=0;lastMatch=nil;mismatch=nil
                status="A new stone is visible, but its intersection is unclear. Checking its position."
                // The camera frame is valid. Keep the centering hint's own
                // temporal and hand-clearance evidence while game assignment
                // waits; resetting it here would prevent the hint ever starting.
                return
            }
            if r.occupancy == .uncertain || r.confidence<0.8 || ambiguous.contains(index) {
                unknown+=1
                // Only unchanged, previously verified intersections may retain
                // history. New stones and capture removals need positive evidence.
                guard let verifiedCells,verifiedCells[index]==cells[index],unknown<=max(12,size*size/5) else {
                    outcome="uncertain_required_intersection";detail["blockingPoint"]=index;detail["unknownCount"]=unknown
                    interruptObservation(preserveGuidance:pendingMoveCue);return
                }
                values[index]=cells[index]
            } else {values[index]=r.occupancy.rawValue}
        }
        if values != cells {lastMatch=nil}
        if witness != values {detail["changedWitnessPoints"]=witness.map {old in values.indices.filter{old[$0] != values[$0]}} ?? [];witness=values;witnessStart=stamp;witnesses=0}
        witnesses+=1
        detail["stableSeconds"]=stamp-witnessStart
        guard witnesses>=3,stamp-witnessStart>=0.45 else {outcome="waiting_for_stable_position";return}
        if values == cells {
            outcome="board_confirmed"
            mismatch=nil;lastMatch=now;verifiedCells=cells;verifiedCameraContext=laser.cameraContext
            if phase == .human {status="Your turn · \(human.rawValue.capitalized) to play."}
            if phase == .checking || phase == .placing {
                if var s=snapshot,s.pendingPlacement || captureCleanupPending || s.captureIndication != nil {
                    s.pendingPlacement=false;s.pendingCaptureCleanup=false;s.captureIndication=nil
                    do {try save(s)} catch {fail(error.localizedDescription);return}
                }
                advance(at:now)
            }
            return
        }
        // A fully observed legal human move may already be on the board when
        // resuming a saved game. Startup still requires a verified empty board.
        let resumingHumanMove=phase == .checking && turn == human &&
            snapshot?.moves.isEmpty == false && snapshot?.pendingPlacement == false
        // The player may place the AI stone and reply before an intermediate
        // frame is confirmed. Require fresh positive evidence for the AI stone
        // and an otherwise exact legal human transition; never infer placement
        // solely from the saved game or a retained uncertain reading. Use the
        // same 0.8 threshold as standalone placement confirmation above; an
        // already-present reply must not make an otherwise accepted stone fail.
        let pendingAIPlaced=phase == .placing && turn == human && pendingPoint.map {point in
            !ambiguous.contains(point) && observation.readings.contains {
                $0.row*size+$0.col==point && $0.occupancy.rawValue==cells[point] && $0.confidence>=0.8
            }
        } == true
        if (phase == .human || resumingHumanMove || pendingAIPlaced),
           let p=PhysicalMoveInference.candidate(board:cells,observed:values,size:size,color:human.rawValue),
           captureGuidance.permitsReply(at:p) {
            let trial=player()
            if let rejection=trial.moveRejection(color:human,x:p%size,y:p/size) {
                outcome="illegal_move";detail["rejection"]=rejection.rawValue
                status=rejection.rawValue;mismatch = .init(expected:cells,observed:values);return
            }
            if resumingHumanMove || pendingAIPlaced {verifiedCells=values;verifiedCameraContext=laser.cameraContext}
            outcome="human_move_accepted";detail["point"]=p;detail["combinedAIPlacement"]=pendingAIPlaced
            commit(p,ai:false,at:now)
        } else {
            outcome="position_mismatch";detail["mismatchPoints"]=values.indices.filter{values[$0] != cells[$0]}
            mismatch = .init(expected:cells,observed:values)
            status=phase == .placing ? "Place the AI stone at the blue ring and remove captured stones.":"Match the physical board to the game before continuing."
        }
    }
    func pass(now: Double = ProcessInfo.processInfo.systemUptime) {guard canPass(at:now) else {return};commit(nil,ai:false,at:now)}
    private func commit(_ point: Int?, ai: Bool, at now: Double, receivedAt: Double? = nil) {
        defer {syncGuidance()}
        clearCentering()
        guard var s=snapshot,turn == (ai ? human.opponent:human) else {return}
        let p=player()
        if let point,!(0..<size*size).contains(point) {fail("AI returned an off-board move.");return}
        if let rejection=p.tryPlayMove(color:p.turn,x:point.map{$0%size} ?? -1,y:point.map{$0/size} ?? -1) {fail(rejection.rawValue);return}
        let after=p.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"}
        let capturedCount=cells.indices.filter {cells[$0] != "empty" && after[$0] == "empty"}.count
        timing.move(black:turn == .black,at:now)
        s.moves.append(.init(point:point,decisionReceivedAtUnix:receivedAt));s.pendingPlacement=ai && point != nil;s.ended=p.lastTwoMovesWerePasses
        // Switch at decision receipt as usual, but exclude the whole physical
        // update for captures of two or more stones. A single capture keeps
        // the next player's clock running. Board confirmation in advance() restarts
        // the next player's clock; hand/laser acknowledgements never do.
        s.pendingCaptureCleanup=capturedCount>=2
        s.captureIndication=capturedCount>0 ? .init(moveNumber:s.moves.count,acceptedAtUnix:receivedAt ?? wallTime()):nil
        if s.ended || capturedCount>=2 {timing.pause(at:now)}
        do {try save(s)} catch {fail(error.localizedDescription);return}
        interruptObservation()
        if s.ended {testWorker.stop();phase = .finished;status="Both players passed. Game saved; no score has been agreed."}
        else if ai,point != nil {phase = .placing;status="Place the AI’s \(human.opponent.rawValue) stone at the blue ring, then remove captures."}
        else {phase = .checking;status=ai ? "AI passes. Checking the board before your turn.":"Move saved. Checking the board and capture removal."}
    }
    private func advance(at now: Double) {
        guard let s=snapshot,!s.ended else {return}
        timing.resume(at:now)
        if turn == human {phase = .human;status="Your turn · \(human.rawValue.capitalized) to play.";return}
        phase = .thinking;status=s.settings.fastTestMode == true ? "KataGo test move…":"KataGo is thinking…";let token=UUID();generation=token
        let trace=PhysicalLatencyTrace.shared
        let traceFields=["session":s.id.uuidString,"moveNumber":String(s.moves.count+1),"source":"ai","generation":token.uuidString]
        trace?.record("ai_thinking_requested",fields:traceFields)
        task=Task { [weak self, generate] in
            let began=ProcessInfo.processInfo.systemUptime
            trace?.record("ai_engine_started",fields:traceFields)
            do {
                let move=try await generate(Self.game(s),s.settings)
                trace?.record("ai_engine_returned",fields:traceFields,metrics:["durationSeconds":ProcessInfo.processInfo.systemUptime-began])
                guard let self,!Task.isCancelled,self.generation==token,self.phase == .thinking else {return}
                let received=self.uptime(),receivedWall=self.wallTime()
                trace?.record("ai_decision_received",fields:traceFields.merging(["decisionReceipt":String(receivedWall)],uniquingKeysWith:{$1}))
                if move.lowercased()=="pass" {self.commit(nil,ai:true,at:received,receivedAt:receivedWall);return}
                guard let point=Self.point(move,size:s.settings.size) else {self.fail("KataGo returned an invalid coordinate: \(move)");return}
                self.commit(point,ai:true,at:received,receivedAt:receivedWall)
            } catch {
                guard let self,!Task.isCancelled,self.generation==token else {return}
                self.fail(error.localizedDescription)
            }
        }
    }
    private func observeCaptures(_ observation:BoardObservation,ambiguous:Set<Int>,stamp:Double,now:Double) {
        guard var saved=snapshot,captureGuidance.pending else {return}
        // consume already admitted this observation through game/hand/dark gates.
        // Board-only play still needs cleanup evidence when the laser is disabled;
        // this local cohort is never published as an optical camera binding.
        let context=laser.cameraContext.map {$0+"/"+laser.frames.streamEpoch.uuidString}
            ?? "board-only/"+generation.uuidString
        var positive=[String?](repeating:nil,count:size*size)
        for reading in observation.readings {
            let p=reading.row*size+reading.col
            if !ambiguous.contains(p),reading.confidence>=0.8,reading.occupancy != .uncertain {
                positive[p]=reading.occupancy.rawValue
            }
        }
        let verified=captureGuidance.observe(identity:.init(session:saved.id,moveNumber:saved.moves.count),
            values:positive,stamp:stamp,now:now,context:context)
        if saved.captureIndication?.removed != captureGuidance.removed.sorted() {
            saved.captureIndication?.removed=captureGuidance.removed.sorted()
            do {try save(saved)} catch {fail(error.localizedDescription);return}
        }
        syncGuidance()
        if let verified,let target=laser.target,target.purpose=="capture",target.row*size+target.col==verified {
            laser.verifyCaptureTarget(capturedAt:stamp,now:now)
        }
    }
    private func syncGuidance() {
        laser.setPlaySession(active ? snapshot.map {.init(source:"ai",session:$0.id,size:$0.settings.size)}:nil)
        if let s=snapshot,phase == .thinking {
            laser.prepareAlignment(session:s.id,moveNumber:s.moves.count+1,size:s.settings.size)
        } else if phase != .placing {laser.clearAlignmentPreparation()}
        guard active else {laser.setTarget(nil);return}
        // Placement confirmation selects guidance only. pendingPlacement and all
        // clock transitions still require the existing whole-board path.
        if let target=guidanceTarget,let received=snapshot?.moves.last?.decisionReceivedAtUnix,
           !captureGuidance.pending || !captureGuidance.placementConfirmed {
            laser.setTarget(.init(source:"ai",session:target.session,moveNumber:target.moveNumber,size:target.size,
                row:target.row,col:target.col,black:target.black,decisionReceivedAtUnix:received));return
        }
        if captureGuidance.pending {
            laser.clearAlignmentPreparation()
            if let s=snapshot,let saved=s.captureIndication,let point=captureGuidance.selected,
               captureGuidance.placementConfirmed,let color=captureGuidance.prisoners[point] {
                laser.setTarget(.init(source:"ai",session:s.id,moveNumber:s.moves.count,size:size,
                    row:point/size,col:point%size,black:color=="black",decisionReceivedAtUnix:saved.acceptedAtUnix,purpose:"capture"))
                if active {status="Remove captured stones · \(captureGuidance.remainingCount) remaining."}
            } else {laser.setTarget(nil)}
            return
        }
        laser.setTarget(centeringEnabled && laser.enabled && [.human,.checking].contains(phase) ? centeringTarget:nil)
    }
    static func point(_ coordinate: String,size: Int)->Int? {
        let chars=Array(coordinate.uppercased()),letters=Array("ABCDEFGHJKLMNOPQRST")
        guard let first=chars.first,let col=letters.firstIndex(of:first),col<size,let row=Int(String(chars.dropFirst())),(1...size).contains(row) else {return nil}
        return (size-row)*size+col
    }
    static var humanModelURL: URL? {
        let bundled=Bundle.main.url(forResource:"b18c384nbt-humanv0",withExtension:"bin.gz")
        let source=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/AI/b18c384nbt-humanv0.bin.gz")
        return bundled ?? (FileManager.default.fileExists(atPath:source.path) ? source:nil)
    }
    /// Sample the raw human policy at temperature 1, not the searched best move.
    /// The final element is pass; all other elements are row-major from top-left.
    static func sampledHumanMove(_ policy: [Double],player: SGFPlayer,unit: Double)->String? {
        let n=player.board.size
        guard policy.count==n*n+1,policy.allSatisfy({$0.isFinite && (-1...1).contains($0)}),(0..<1).contains(unit) else {return nil}
        let options=policy.indices.filter {i in policy[i]>0 && player.moveRejection(color:player.turn,x:i==n*n ? -1:i%n,y:i==n*n ? -1:i/n)==nil}
        let total=options.reduce(0.0) {$0+policy[$1]};guard total>0 else {return nil}
        var threshold=unit*total
        for i in options {
            threshold-=policy[i]
            if threshold<0 {return i==n*n ? "pass":"\(Array("ABCDEFGHJKLMNOPQRST")[i%n])\(n-i/n)"}
        }
        return nil
    }
    @MainActor final class TestWorker {
        private var engine:PhysicalAITestBackend?
        private var activeRequest:UUID?
        private let makeEngine:@MainActor ()->PhysicalAITestBackend
        init(makeEngine:@escaping @MainActor ()->PhysicalAITestBackend = {KataBackend()}) {self.makeEngine=makeEngine}
        var isRunning:Bool {engine?.isRunning == true}
        func move(_ game:SGFGame) async throws -> String {
            try Task.checkCancellation()
            guard activeRequest == nil else {throw Failure(message:"A test search is already running.")}
            // Recheck path preferences and launch-time asset metadata before
            // using a retained worker. A paused engine never starts new work.
            if let engine,!engine.reusableConfiguration {stop()}
            if engine == nil {engine=makeEngine()}
            guard let engine else {throw Failure(message:"Test engine is unavailable.")}
            let token=UUID();activeRequest=token
            defer {if activeRequest == token {activeRequest=nil}}
            do {
                let move=try await engine.move(game)
                try Task.checkCancellation()
                guard activeRequest == token else {throw CancellationError()}
                return move
            } catch {
                // An obsolete completion must not stop a replacement worker.
                if activeRequest == token {stop()}
                throw error
            }
        }
        func cancelKeepingIdle() {
            // No metadata IO on Pause. Revalidation happens before next use.
            if activeRequest != nil {stop()}
        }
        func stop() {activeRequest=nil;engine?.stop();engine=nil}

        private final class KataBackend:PhysicalAITestBackend {
            private let engine:KataGoEngine
            private let preferences:[String?]
            init() {preferences=Self.currentPreferences();engine=PhysicalScoring.makeWorker()}
            private static func currentPreferences()->[String?] {
                let defaults=UserDefaults(suiteName:"com.davemarvit.SGFPlayerClean")
                return [defaults?.string(forKey:"customKataGoPath"),defaults?.string(forKey:"customAIModelPath")]
            }
            var isRunning:Bool {engine.isEngineRunning}
            var reusableConfiguration:Bool {
                preferences == Self.currentPreferences() && engine.canReuseCurrentConfiguration()
            }
            func move(_ game:SGFGame) async throws -> String {
                try await PhysicalAI.kataMove(game,visits:PhysicalAISettings.Strength.quick.visits,worker:engine)
            }
            func stop() {engine.stop()}
        }
    }
    static func kataMove(_ game: SGFGame,visits: Int,rank: String? = nil,worker:KataGoEngine? = nil) async throws -> String {
        if let rank,!PhysicalAISettings.ranks.contains(rank) {throw Failure(message:"Unsupported human rank.")}
        if rank != nil && humanModelURL == nil {throw Failure(message:"HumanSL model is missing. Reinstall Physical Go or choose Search effort in Setup.")}
        let engine=worker ?? PhysicalScoring.makeWorker(humanModelURL:rank == nil ? nil:humanModelURL);engine.currentGameId="physical-play-"+UUID().uuidString
        if !engine.isEngineRunning {engine.start()}
        defer {if worker == nil {engine.stop()}}
        if let error=engine.engineStartupError {throw Failure(message:error)}
        let p=SGFPlayer();p.load(game:game);p.seek(to:game.moves.count);let payload=p.getCurrentAIPayload()
        engine.analyzeGame(id:engine.currentGameId,initialStones:payload.initial,moves:payload.moves,size:game.boardSize,maxVisits:rank == nil ? visits:60,settings:p.analysisSettings,humanSLProfile:rank.map {"rank_"+$0})
        let deadline=ProcessInfo.processInfo.systemUptime+90
        while ProcessInfo.processInfo.systemUptime<deadline {
            try await Task.sleep(nanoseconds:worker == nil ? 200_000_000:20_000_000)
            if let error=engine.analysisError ?? engine.engineStartupError {throw Failure(message:error)}
            if let analysis=engine.currentAnalysisData[game.moves.count],analysis.isDuringSearch != true {
                guard let move=AIMovePresentation.ranked(analysis.moveInfos ?? []).first?.move else {throw Failure(message:"KataGo returned no move. Retry the search.")}
                if rank != nil {
                    // The normal engine decides when passing is sensible, as in
                    // KataGo's documented human-play recipe. Its searched moves
                    // never replace the human policy for ordinary stone placement.
                    if move.lowercased()=="pass" {return "pass"}
                    guard var policy=analysis.humanPolicy,policy.count==game.boardSize*game.boardSize+1 else {throw Failure(message:"KataGo did not return a human policy. Check the HumanSL model.")}
                    policy[policy.count-1]=0
                    guard let sampled=Self.sampledHumanMove(policy,player:p,unit:Double.random(in:0..<1)) else {throw Failure(message:"KataGo returned no legal human-style move.")}
                    return sampled
                }
                return move
            }
        }
        throw Failure(message:"KataGo did not respond within 90 seconds. Check its configuration and Retry.")
    }
}
