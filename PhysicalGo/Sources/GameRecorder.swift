import Foundation
import Combine

/// Fixed handicap setup uses setup stones, never numbered moves.
enum LocalGameSetup {
    static let rules = ["Japanese", "Chinese", "AGA", "Korean", "New Zealand", "Tromp-Taylor"]
    static func stones(size:Int,handicap:Int)->[(Stone,Int,Int)] {
        guard [9,13,19].contains(size),(2...9).contains(handicap) else {return []}
        let low=size == 9 ? 2:3, high=size-1-low, middle=size/2
        var points=[(high,low),(low,high)]
        if handicap>=3 {points.append((high,high))}
        if handicap>=4 {points.append((low,low))}
        if handicap>=6 {points += [(low,middle),(high,middle)]}
        if handicap>=8 {points += [(middle,low),(middle,high)]}
        if [5,7,9].contains(handicap) {points.append((middle,middle))}
        return points.map {(.black,$0.0,$0.1)}
    }
}

/// A user-reviewed proposal, isolated from the recording and its pending history.
@MainActor struct MoveRecoveryDraft:Identifiable {
    let id=UUID()
    let baseRecord:String
    let baseGame:SGFGame
    let observation:BoardObservation?
    let snapshotHeldAt=Date().timeIntervalSince1970
    private(set) var moves:[BoardPosition?]=[]
    init(recorder:GameRecorder,observation:BoardObservation?) {
        baseRecord=recorder.sgf();baseGame=recorder.game;self.observation=observation
    }
    var trial:SGFPlayer {
        let player=SGFPlayer();player.load(game:baseGame);player.seek(to:baseGame.moves.count)
        for point in moves {player.tryPlayMove(color:player.turn,x:point?.col ?? -1,y:point?.row ?? -1)}
        return player
    }
    init(game:SGFGame,observation:BoardObservation?) {
        baseRecord="section";baseGame=game;self.observation=observation
    }
    var nextPlayer:Stone {trial.turn}
    var board:BoardSnapshot {trial.board}
    mutating func add(_ point:BoardPosition?,checkCameraColor:Bool=true)->String? {
        let player=trial
        if player.lastTwoMovesWerePasses {return "Two passes end the game. Undo the last selection to continue."}
        if let rejection=player.moveRejection(color:player.turn,x:point?.col ?? -1,y:point?.row ?? -1) {return rejection.rawValue}
        if checkCameraColor,let point,let observation,observation.size==baseGame.boardSize,
           let reading=observation.readings.first(where:{$0.row==point.row && $0.col==point.col}),
           let color=reading.occupancy.stone,color != player.turn {
            return "\(player.turn.rawValue.capitalized) is next, but the camera sees \(color.rawValue) here. Choose the next stone, or override the camera color below."
        }
        moves.append(point);return nil
    }
    mutating func undo() {if !moves.isEmpty {moves.removeLast()}}
    mutating func clear() {moves=[]}
}

/// Accepted history is independent of camera observations and the review cursor.
/// Only fresh, stable, legal transitions can extend it automatically.
/// Short observation history preserves tentative chronology until moves are confirmed.
@MainActor final class GameRecorder: ObservableObject {
    enum State { case idle, verifying, recording, paused, finished }
    @Published private(set) var state: State = .idle
    @Published private(set) var status = "Start with an empty board. Black plays first."
    @Published private(set) var reviewIndex = 0
    @Published private(set) var positions = [BoardSnapshot]()
    @Published private(set) var game = SGFGame()
    @Published private(set) var saveError: String?
    @Published private(set) var autosaveURL: URL?
    private let storage: URL?
    private let recordingStore = RecordingStore()
    @Published private(set) var pendingSaveError: String?
    var recoveryReadBlocked: Bool { recordingStore.isReadBlocked }
    private let player = SGFPlayer()
    let clock=LocalGameClock()
    @Published private(set) var synchronized = false
    @Published private(set) var verificationFrames = 0
    private var emptyViewSize = 0
    private var emptyViews: [(time: Double, unknown: Set<Int>)] = []
    private var emptyViewLast:Double?
    private var emptyViewVerified = false
    private var handicapViews: [(time:Double, readings:[Occupancy])] = []
    private var boardReadyForPass = false
    @Published private(set) var needsAttention = false
    @Published private(set) var attentionMessage:String?
    @Published private(set) var unclearPointCount=0
    @Published private(set) var reviewCameraPosition:[Occupancy]?
    @Published private(set) var reviewCameraRevision=0
    private var reviewCameraWitnesses:[(time:Double,position:[Occupancy])]=[]
    private func noteReviewCamera(_ observation:BoardObservation,now:Double) {
        guard hasDeferredMoves,!observation.lightingBlocked,observation.size==game.boardSize,
              observation.readings.count==game.boardSize*game.boardSize,
              reviewCameraWitnesses.last.map({now>$0.time}) ?? true else {return}
        if let last=reviewCameraWitnesses.last,now-last.time>0.5 {reviewCameraWitnesses=[]}
        let position=observation.signature
        reviewCameraWitnesses.append((now,position));reviewCameraWitnesses.removeAll{now-$0.time>2}
        if reviewCameraWitnesses.count>120 {reviewCameraWitnesses.removeFirst(reviewCameraWitnesses.count-120)}
        if reviewCameraPosition != position {reviewCameraPosition=position}
        reviewCameraRevision += 1
    }
    func accidentalWithdrawalPlan(_ id:UUID)->AccidentalStoneWithdrawal? {
        guard let context=contextForReview(id),context.turnKnown else {return nil}
        return AccidentalStoneWithdrawal.make(history:reviewHistory,id:id,context:context.game)
    }
    func accidentalRemovalVerified(_ plan:AccidentalStoneWithdrawal,now:Double=ProcessInfo.processInfo.systemUptime)->Bool {
        guard let last=reviewCameraWitnesses.last,now>=last.time,now-last.time<1.5 else {return false}
        let matching=reviewCameraWitnesses.reversed().prefix {view in
            plan.verificationPoints.allSatisfy{view.position[$0]==plan.target[$0]}
        }
        return matching.count>=5 && last.time-(matching.last?.time ?? last.time)>=0.8
    }
    @Published private(set) var adjustmentIssues:[Int:BoardAdjustmentMonitor.Kind]=[:]
    private var adjustmentMonitor=BoardAdjustmentMonitor()
    private func resetAdjustmentGuidance() {adjustmentMonitor=BoardAdjustmentMonitor();adjustmentIssues=[:]}
    private func updateAdjustmentGuidance(_ observation:BoardObservation,now:Double) {
        guard hasGame,state != .finished,!awaitingFirstStart,!observation.lightingBlocked,
              observation.size==game.boardSize,observation.readings.count==game.boardSize*game.boardSize,
              let base=positions.last,let after=interpretedBoard else {return}
        func states(_ board:BoardSnapshot)->[Occupancy] {board.grid.flatMap{$0}.map { stone -> Occupancy in
            if stone == .black {return .black};if stone == .white {return .white};return .empty
        }}
        let before=states(base),expected=states(after),readings=observation.signature
        var issues=BoardAdjustmentMonitor.evidence(readings:readings,base:before,after:expected)
        let offsets=observation.assignmentOffsets(confirmedBoard:before)
        // Only positive placement evidence asks the player to center a stone.
        for p in expected.indices where expected[p].stone != nil {
            if let offset=offsets[p],offset>=0.30 {issues[p] = .placement}
        }
        for evidence in pendingConfidence where evidence.placementUncertain {
            if let point=evidence.point {issues[point] = .placement}
        }
        let clear=Set(readings.indices.filter {readings[$0] != .uncertain && readings[$0]==expected[$0] && issues[$0]==nil})
        adjustmentMonitor.update(issues:issues,clear:clear,now:now)
        if adjustmentIssues != adjustmentMonitor.visible {adjustmentIssues=adjustmentMonitor.visible}
    }
    @Published private(set) var pausedProblem:String?
    var recordingProblemTitle:String {
        unclearPointCount>unclearLimit ? "Camera cannot read the board reliably"
            : pendingMoveCount>0 ? "Move confirmation is delayed":"The next move could not be verified"
    }
    @Published private(set) var diagnosticError:String?
    var onGameStarted:(()->Void)?
    @Published private(set) var awaitingFirstStart=false
    private var announceFirstStart=false
    var onMoveAccepted:((Int,Stone)->Void)?
    var onAttention:(()->Void)?
    var onPlacementChime: (([PlacementChimeMonitor.Issue]) -> Void)? {
        didSet { placementChimes.interrupt() }
    }
    private var placementChimes = PlacementChimeMonitor()
    var onDiagnosticEvent:(([String:Any])->Void)?
    var onEvidenceCapture:(([String:Any])->String?)?
    private var timingNeedsFreshEpoch=true
    private var timingEpoch=Double.infinity
    private var reviewTriggers=Set<String>()
    private var reviewStarts=[String:Double]()
    private let timingRun=UUID().uuidString

    private enum BlockKind { case conflict, settling }
    private var blockedKind:BlockKind?
    private var viewContinuity=CameraViewContinuity()
    private var blockedSince:Double?
    private var pendingUnknownCounts = [Int:Int]()
    private var traceHandle:FileHandle?
    private var observationNumber=0
    private var unclearLimit:Int { max(2,Int(Double(game.boardSize*game.boardSize)*0.05)) }

    private var pendingKey = ""
    private var pendingCount = 0
    private var pendingSince = 0.0
    private var lastTime: Double?
    private var manualMoves = Set<Int>()
    private var warningMonitor=RecordingWarningMonitor()
    @Published private(set) var unsavedStoneCount=0
    private func resetWarningMonitor() {warningMonitor.reset();unsavedStoneCount=0}
    private var observationHistory=MoveObservationHistory()
    private var pausedTentativeHistory:MoveObservationHistory?
    @Published private(set) var reviewHistory=DeferredMoveHistory()
    @Published private(set) var reviewSaveError:String?
    private var unresolvedSince:Double?
    private var reviewLoadFailed=false
    private var recoveredReviewCommit=false
    var activeReviewID:UUID?
    var hasDeferredMoves:Bool {reviewHistory.active}
    var hasUnfinishedReviews:Bool {hasDeferredMoves || reviewSaveError != nil || pendingSaveError != nil || recoveryReadBlocked}
    var liveNextPlayer:Stone? {hasDeferredMoves ? reviewHistory.nextColor : nextPlayer}
    var needsTurnConfirmation:Bool {hasDeferredMoves && liveNextPlayer == nil && state != .finished}
    var canScorePosition:Bool {!recoveryReadBlocked && hasGame && !awaitingFirstStart && state != .verifying && !reviewing && !reviewLoadFailed && (hasDeferredMoves || pendingMoveCount==0)}
    var scoringGame:SGFGame {
        guard let board=reviewHistory.latest else {return game}
        var live=DeferredMoveHistory.positionGame(board,size:game.boardSize,rules:game.info.rules,turn:liveNextPlayer ?? .black)
        live.info=game.info;live.handicap=game.handicap;return live
    }
    var scoringPositionKey:String {
        // Only Go inputs belong in the cache identity. Names, clocks and a
        // resignation result must not invalidate an already analyzed position.
        let position=scoringGame
        let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        let settings=(try? encoder.encode(position.analysisSettings)).flatMap {String(data:$0,encoding:.utf8)} ?? ""
        let setup=position.setup.map {"\($0.0.rawValue):\($0.1),\($0.2)"}.sorted().joined(separator:";")
        let moves=position.moves.map {"\($0.0.rawValue):"+($0.1.map {"\($0.0),\($0.1)"} ?? "pass")}.joined(separator:";")
        return [autosaveURL?.path ?? "",String(position.boardSize),String(position.handicap),settings,setup,moves].joined(separator:"/")
    }
    var knownPrisoners:(black:Int,white:Int) {
        var black=player.capturesByBlack,white=player.capturesByWhite
        for section in reviewHistory.sections where !section.committed && section.reviewNumber == nil {
            for i in section.before.indices where section.before[i] != section.after[i] {
                if section.before[i] == .white && section.after[i] == .empty {black += 1}
                if section.before[i] == .black && section.after[i] == .empty {white += 1}
            }
        }
        return (black,white)
    }
    @Published private(set) var pendingMoveCount=0
    @Published private(set) var retainingTentativeMoves=false
    var pendingConfidence:[MoveObservationHistory.MoveConfidence] {(pausedTentativeHistory ?? observationHistory).moveConfidence}
    /// Display proposal only; never used to confirm or export moves.
    var interpretedBoard:BoardSnapshot? {
        if let latest=reviewHistory.latest {return DeferredMoveHistory.board(latest,size:game.boardSize)}
        return (pausedTentativeHistory ?? observationHistory).bestCandidate?.boards.last ?? positions.last
    }
    var interpretationWarnings:Set<Int> {
        Set(pendingConfidence.filter{$0.level != "high"}.compactMap(\.point))
    }
    var lastInterpretedPoint:Int? {
        if hasDeferredMoves {
            return reviewHistory.sections.last(where:{!$0.committed})?.moves?.last?.point.map{$0.row*game.boardSize+$0.col}
        }
        if let point=(pausedTentativeHistory ?? observationHistory).bestCandidate?.moves.last {return point}
        return game.moves.last?.1.map{$0.1*game.boardSize+$0.0}
    }
    var tentativeNextPlayer:Stone? {
        if hasDeferredMoves {return reviewHistory.nextColor}
        guard pendingMoveCount>0 else {return nil}
        let parities=Set((pausedTentativeHistory ?? observationHistory).tentativeSequences.map{$0.count%2})
        guard parities.count==1 else {return nil}
        return parities.first==0 ? nextPlayer : nextPlayer.opponent
    }
    private func resetObservationHistory() { observationHistory.reset();pausedTentativeHistory=nil;pendingMoveCount=0;retainingTentativeMoves=false }
    var localEvidenceRunCount:Int { observationHistory.localEvidence.runCount }
    var localEvidenceSampleCount:Int { observationHistory.localEvidence.sampleCount }
    var hasGame: Bool { state != .idle }
    var moveCount: Int { game.moves.count }
    /// Count plays (including passes), not stones remaining after captures.
    /// Deferred moves leave this journal when committed, so finalization never
    /// counts them twice. Unknown sequences are flagged by the clock label.
    func recordedMoveCount(for color:Stone)->Int {
        game.moves.filter{$0.0==color}.count + reviewHistory.sections.filter{!$0.committed}.reduce(0) {
            $0 + ($1.moves?.filter{$0.color==color}.count ?? 0)
        }
    }
    var moveCountsNeedReview:Bool {hasUnfinishedReviews || pendingMoveCount>0}
    var nextPlayer: Stone { player.turn }
    var reviewing: Bool { reviewIndex != moveCount }
    var reviewedBoard: BoardSnapshot? { positions.indices.contains(reviewIndex) ? positions[reviewIndex] : nil }
    var canEdit: Bool { !recoveryReadBlocked && !awaitingFirstStart && state == .paused && !reviewing && !hasDeferredMoves }
    var canPass: Bool {
        guard !recoveryReadBlocked, !awaitingFirstStart else {return false}
        if hasDeferredMoves {return reviewHistory.nextColor != nil && !reviewing && (state == .recording || state == .paused)}
        return pendingMoveCount==0 && !reviewing && (state == .paused || (state == .recording && synchronized && boardReadyForPass))
    }
    nonisolated static var recordingsDirectory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Physical Go/Recordings",isDirectory:true)
    }
    init(storage:URL? = GameRecorder.recordingsDirectory) { self.storage = storage }

    func hasVerifiedEmptyBoard(size:Int,now:Double = ProcessInfo.processInfo.systemUptime)->Bool {
        emptyViewVerified && emptyViewSize==size && emptyViewLast.map {now >= $0 && now-$0<=1} == true
    }
    func start(size:Int, now:Double = ProcessInfo.processInfo.systemUptime,info:SGFGame.Info?=nil,handicap:Int=0,clockSettings:LocalClockSettings = .init(kind:.none),startPaused:Bool=false) {
        guard !recoveryReadBlocked,clockSettings.validationError==nil,[9,13,19].contains(size), handicap == 0 || (2...9).contains(handicap),
              info?.rules == nil || LocalGameSetup.rules.contains(info!.rules!) else { return }
        // Each new session has a separate file. Never overwrite the previous game.
        if hasGame,saveSession() != nil {return}
        let ready=handicap == 0 && hasVerifiedEmptyBoard(size:size,now:now)
        timingNeedsFreshEpoch=true;reviewTriggers=[];reviewStarts=[:]
        placementChimes = PlacementChimeMonitor()
        var fresh=SGFGame(); fresh.boardSize=size; fresh.initialPlayer = handicap>0 ? .white:.black
        fresh.handicap=handicap;fresh.setup=LocalGameSetup.stones(size:size,handicap:handicap)
        fresh.info=info ?? SGFGame.Info(date:SGFGame.Info.formattedGameDate(Date()),rules:"Japanese")
        if fresh.info.rules == nil {fresh.info.rules="Japanese"}
        clock.configure(clockSettings,blackToPlay:fresh.initialPlayer != .white)
        reviewHistory=DeferredMoveHistory();reviewHistory.size=size;reviewSaveError=nil;unresolvedSince=nil;reviewLoadFailed=false;recoveredReviewCommit=false
        resetAdjustmentGuidance()
        game=fresh; player.load(game:fresh); positions=[player.board]; reviewIndex=0; manualMoves=[]
        autosaveURL=storage?.appendingPathComponent("Physical Go \(UUID().uuidString).sgf")
        recordingStore.bind(to: autosaveURL); pendingSaveError=nil
        awaitingFirstStart=startPaused;announceFirstStart=false
        state = startPaused ? .paused : ready ? .recording : .verifying; synchronized=ready; boardReadyForPass=ready
        clearBlock(); resetPending(); handicapViews=[]; viewContinuity.reset(); resetObservationHistory(); resetWarningMonitor(); lastTime=nil; verificationFrames=ready ? 5 : 0
        status=ready ? "Ready · Black to play. Moves are saved as the camera confirms them."
            : handicap>0 ? "Place the \(handicap) black handicap stones shown on the setup board. Wait for verification before White plays." : "Not recording yet. Clear the board and wait for Ready before playing Black."
        if startPaused {
            clock.pause("Setup saved · press Start when both players are ready",at:now)
            status="Game setup saved. Press Start when both players are ready; clocks and recording have not started."
        } else if ready {clock.ready(at:now)}
        persist(); beginTrace()
        trace(event:"start")
    }
    private func initialPositionReady(at now:Double) {
        defer {checkpointPendingMoves()}
        awaitingFirstStart=false
        clock.ready(at:now)
        if announceFirstStart {announceFirstStart=false;onGameStarted?();trace(event:"game started",now:now)}
    }
    enum RestoreError:LocalizedError {
        case unsupported,invalidMove(Int)
        var errorDescription:String? {
            switch self {
            case .unsupported:return "Open a Physical Go recording with a supported starting position and one move sequence."
            case .invalidMove(let number):return "The saved record contains an illegal move at move \(number)."
            }
        }
    }
    /// Restore accepted history for review/update without deriving moves from a photo.
    func restoreSavedGame(from url:URL)throws {
        let tree=try SGFParser.parse(text:String(contentsOf:url,encoding:.utf8))
        let loaded=SGFGame.from(tree:tree)
        guard tree.branches.count==1,tree.mainLineNodes.first?.props["AP"]?.first?.hasPrefix("PhysicalGo:")==true,
              [9,13,19].contains(loaded.boardSize),loaded.analysisSettings.playRules != nil,
              (loaded.handicap == 0 && loaded.setup.isEmpty && loaded.initialPlayer != .white) ||
              ((2...9).contains(loaded.handicap) && loaded.initialPlayer == .white &&
               loaded.setup.map {"\($0.0.rawValue):\($0.1),\($0.2)"}.sorted() == LocalGameSetup.stones(size:loaded.boardSize,handicap:loaded.handicap).map {"\($0.0.rawValue):\($0.1),\($0.2)"}.sorted()) else { throw RestoreError.unsupported }
        var initial=loaded;initial.moves=[];initial.sourceTree=nil
        let validation=SGFPlayer();validation.load(game:initial)
        var restored=[validation.board]
        for (index,move) in loaded.moves.enumerated() {
            guard validation.tryPlayMove(color:move.0,x:move.1?.0 ?? -1,y:move.1?.1 ?? -1)==nil else { throw RestoreError.invalidMove(index+1) }
            restored.append(validation.board)
        }
        if hasGame,let error=saveSession() {
            throw NSError(domain:"PhysicalGo",code:1,userInfo:[NSLocalizedDescriptionKey:error])
        }
        awaitingFirstStart=false;announceFirstStart=false
        placementChimes = PlacementChimeMonitor()
        resetAdjustmentGuidance()
        game=loaded;positions=restored;reviewIndex=loaded.moves.count;manualMoves=[]
        var number=0
        for node in tree.mainLineNodes where node.props["B"] != nil || node.props["W"] != nil {
            number += 1
            if node.props["C"]?.contains("Entered manually.")==true { manualMoves.insert(number) }
        }
        player.load(game:loaded);player.seek(to:moveCount)
        resetObservationHistory()
        autosaveURL=url
        recordingStore.bind(to: url,savedSignature:checkpointSignature); pendingSaveError=nil
        reviewHistory=DeferredMoveHistory();reviewHistory.size=game.boardSize
        reviewSaveError=nil;reviewLoadFailed=false;recoveredReviewCommit=false
        state=player.lastTwoMovesWerePasses ? .finished : .paused
        clearBlock();resetWarningMonitor();suspendVision("",checkpoint:false)
        status="Restored \(moveCount) recorded moves. Review them, or resume recording when the live board is ready."
        clock.restore(from:url,signature:checkpointSignature,moveCount:moveCount,blackToPlay:nextPlayer == .black)
        try restoreChronology()
        beginTrace(append:true);trace(event:"restored saved game")
    }
    private func restoreChronology()throws {
        try restoreReviewHistory()
        if hasDeferredMoves || recoveredReviewCommit {
            resetObservationHistory()
            try savePendingCheckpoint()
            if recoveredReviewCommit {
                let mapping=Dictionary(uniqueKeysWithValues:reviewHistory.sections.compactMap {s -> (UUID,Int)? in
                    guard s.committed,s.moves?.count==1,let start=s.savedStart else {return nil}
                    return (s.id,start+1)
                })
                clock.finalizeLiveHistory(mapping:mapping,moveCount:moveCount,blackToPlay:nextPlayer == .black)
                persist();saveReviewHistory()
            }
        } else {try restorePendingCheckpoint()}
    }
    private var checkpointSignature:String {RecordingIdentity.signature(for:game)}
    private func signature(for game:SGFGame)->String {RecordingIdentity.signature(for:game)}
    /// A separate internal file; pending moves never enter SGF prematurely.
    func savePendingCheckpoint()throws {
        let history=pausedTentativeHistory ?? observationHistory
        do {
            try recordingStore.savePending(.init(version:1,signature:checkpointSignature,
                history:history.checkpoint,awaitingFirstStart:awaitingFirstStart))
            pendingSaveError=nil
        } catch {
            pendingSaveError="Could not save pending moves: \(error.localizedDescription). Keep the app open and retry saving."
            throw error
        }
    }
    private func checkpointPendingMoves() {
        guard hasGame,!recoveryReadBlocked,saveError==nil,recordingStore.canCheckpoint(signature:checkpointSignature) else {return}
        do {try savePendingCheckpoint()}
        catch { /* savePendingCheckpoint publishes the error for retry. */ }
    }
    private func restorePendingCheckpoint()throws {
        guard autosaveURL != nil,state != .finished else {return}
        do {
            let saved=try recordingStore.loadPending(game:game,now:ProcessInfo.processInfo.systemUptime)
            awaitingFirstStart=saved.awaitingStart;pendingSaveError=nil
            if awaitingFirstStart {status="Game setup saved. Press Start when both players are ready."}
            guard let retained=saved.history else {return}
            pausedTentativeHistory=retained;pendingMoveCount=retained.pendingCount
            status="Restored \(moveCount) saved and \(pendingMoveCount) pending moves. Red rings mark pending confirmation; Resume rechecks the physical board."
        } catch {pendingSaveError=error.localizedDescription;throw error}
    }
    /// Flush game, pending chronology and clocks before leaving the session.
    /// A failed load has made no edits: leave its original files untouched.
    @discardableResult func flushForExit()->Bool {
        guard hasGame,!recoveryReadBlocked else {return true}
        pause();clock.pause("Recording closed · clocks paused")
        return saveSession()==nil
    }
    func retryRecordingSave() {
        if recoveryReadBlocked {retryReviewSave();return}
        _=saveSession()
    }
    /// Use one save boundary for shutdown, session replacement and retries.
    private func saveSession()->String? {
        persist()
        if !reviewHistory.sections.isEmpty {saveReviewHistory()}
        checkpointPendingMoves()
        // A failed clock load leaves the clock disabled and its file untouched.
        // Only an enabled clock can have unsaved changes that block leaving.
        return saveError ?? pendingSaveError ?? reviewSaveError ?? (clock.enabled ? clock.saveError:nil)
    }
    private func resetPending() { pendingKey=""; pendingCount=0; pendingSince=0; pendingUnknownCounts=[:] }
    private func stable(_ key:String, now:Double)->Bool {
        if pendingKey != key { pendingKey=key; pendingCount=1; pendingSince=now; pendingUnknownCounts=[:]; return false }
        pendingCount += 1
        return pendingCount >= 5 && now-pendingSince >= 0.8
    }
    func suspendVision(_ reason:String, preserveObservations:Bool=false, preserveOrder:Bool=false,checkpoint:Bool=true) {
        // Restoration must validate sidecars before any checkpoint can replace them.
        defer {if checkpoint {checkpointPendingMoves()}}
        viewContinuity.reset()
        reviewHistory.interrupt();unresolvedSince=nil
        reviewCameraWitnesses=[];reviewCameraPosition=nil;reviewCameraRevision += 1
        if reason.isEmpty {clock.pause("Recording paused")} else {clock.interrupt(reason)}
        timingNeedsFreshEpoch=true;reviewStarts=[:]
        placementChimes.interrupt()
        retainingTentativeMoves=false
        if preserveOrder {
            // The retained path already assumes logical grid coordinates stay
            // the same through reacquisition. Keep its bounded local chronology
            // too, including stones that could not yet extend that path.
            let retained=(pausedTentativeHistory ?? observationHistory).retainedForResume(preserveLocalEvidence:true)
            resetObservationHistory();resetWarningMonitor();clearBlock()
            if state == .paused {pausedTentativeHistory=retained}
            else if let retained {observationHistory=retained}
            pendingMoveCount=retained?.pendingCount ?? 0
        } else if preserveObservations {
            // Alignment checks continue while paused. Preserve its retained
            // history as well as an actively recording observation queue.
            observationHistory.interruptLocally()
        } else {resetObservationHistory();resetWarningMonitor();clearBlock()}
        emptyViewVerified=false; emptyViews.removeAll(); handicapViews=[]; emptyViewLast=nil; verificationFrames=0
        synchronized=false; boardReadyForPass=false; resetPending(); lastTime=nil
        if state == .recording || state == .verifying { status=reason; trace(event:"vision interrupted: \(reason)") }
    }
    func pause() {
        defer {checkpointPendingMoves()}
        guard state == .recording || state == .verifying else { return }
        let retained=observationHistory.retainedForResume()
        let problem=needsAttention ? status:nil
        state = .paused; resetWarningMonitor(); suspendVision("",preserveOrder:true);clock.pause("Clock and recording paused")
        pausedProblem=problem
        pausedTentativeHistory=retained;pendingMoveCount=retained?.pendingCount ?? 0
        status=awaitingFirstStart ? "Game setup saved. Press Start when both players are ready." : retained == nil ? "Paused. Review the moves, or correct a missed move at the latest position."
            : "Paused. \(pendingMoveCount) tentative moves are retained; Resume will recheck the physical board."
        trace(event:"paused")
    }
    func resume() {
        guard !recoveryReadBlocked,state == .paused else { return }
        defer {checkpointPendingMoves()}
        if awaitingFirstStart {
            announceFirstStart=true;clock.requestResume()
        }
        pausedProblem=nil
        if hasDeferredMoves {
            state = .recording;suspendVision("Recording later moves; earlier sections still need review.")
            clock.requestResume()
            status="Recording later moves · \(reviewHistory.unresolved) sections can be reviewed after play."
            trace(event:"resumed after review gap");return
        }
        let retained=pausedTentativeHistory
        resetWarningMonitor();reviewIndex=moveCount
        state = retained != nil ? .recording : positions.count == 1 && moveCount == 0 ? .verifying : .recording
        suspendVision("Checking that the physical board matches the recorded position before continuing.",preserveOrder:retained != nil)
        if let retained {observationHistory=retained;pendingMoveCount=retained.pendingCount}
        trace(event:"resumed")
    }
    /// Explicit player confirmation clears the timing-review gate. Recording
    /// resumes through normal board verification; this does not start a clock
    /// against an unverified camera position.
    @discardableResult func confirmClockReview(black:LocalClockEngine.Side,white:LocalClockEngine.Side,resume:Bool,turn:Stone?=nil)->Bool {
        guard !recoveryReadBlocked,state == .paused,let next=hasDeferredMoves ? (turn ?? liveNextPlayer):nextPlayer,
              clock.correct(black:black,white:white,blackToPlay:next == .black,moveCount:moveCount) else {return false}
        if hasDeferredMoves {reviewHistory.turnOverride=next;saveReviewHistory();clock.followLiveTurn(next,at:ProcessInfo.processInfo.systemUptime)}
        if resume {clock.requestResume();self.resume()}
        return true
    }
    func confirmLiveTurn(_ color:Stone,at now:Double=ProcessInfo.processInfo.systemUptime) {
        guard !recoveryReadBlocked,hasDeferredMoves,state != .finished else {return}
        reviewHistory.turnOverride=color;saveReviewHistory()
        clock.followLiveTurn(color,at:now,resumeIfReady:state == .recording)
        trace(event:"live turn confirmed",now:now,extra:["nextPlayer":color.rawValue])
    }
    func noteScoredPosition(_ board:BoardSnapshot) {
        guard hasDeferredMoves else {return}
        reviewHistory.scoredPosition=DeferredMoveHistory.states(board);saveReviewHistory()
    }
    func updateInfo(_ info:SGFGame.Info) {
        guard hasGame,!recoveryReadBlocked else {return}
        let rules=game.info.rules
        game.info=info;game.info.rules=rules
        persist()
        trace(event:"game info updated")
    }
    func finish() {
        guard !recoveryReadBlocked else {return}
        if hasDeferredMoves {
            pause();clock.finish();state = .finished;reviewHistory.endRequested=true;saveReviewHistory()
            status="Game ended. Scoring is available; resolve the red reviews before exporting the complete SGF."
            return
        }
        guard hasGame else { return }
        let unresolved=max(pendingMoveCount,unsavedStoneCount)
        if unresolved>0 {
            pause()
            status="Not finished: \(unresolved) moves still need verification. Check the interpretation board and adjust red-ringed stones. Resume recording to verify them, then choose End game again. Pending history is retained."
            trace(event:"finish needs unresolved moves")
            return
        }
        awaitingFirstStart=false;announceFirstStart=false
        clock.finish()
        state = .finished; resetPending(); resetObservationHistory(); resetWarningMonitor(); status="Recording finished. Review or save the game; no result has been inferred."; persist();trace(event:"finished")
    }
    func seek(_ index:Int) {
        guard hasGame else { return }
        pause(); reviewIndex=max(0,min(index,moveCount))
    }
    func returnToLatest() { seek(moveCount) }
    private func clearBlock() { blockedSince=nil; blockedKind=nil; needsAttention=false; attentionMessage=nil }
    func acknowledgeAttention() { attentionMessage=nil }
    private func reject(_ message:String,kind:BlockKind = .conflict) {
        resetPending(); verificationFrames=0; boardReadyForPass=false; status=message
        guard state == .recording, let now=lastTime else { return }
        if blockedSince == nil || blockedKind != kind { blockedSince=now; blockedKind=kind }
        let delay = kind == .settling ? 10.0 : 3.0
        if now-blockedSince!>=delay && !needsAttention {
            needsAttention=true
            attentionMessage=kind == .settling
                ? "Observations are being retained. Move order is still being checked; unresolved sequences can be reviewed later."
                : "Please stop playing. Last saved: move \(moveCount). \(message)"
            warningMonitor.noteSound(now:now)
            trace(event:"recording warning: persistent blockage",now:now)
            onAttention?()
        }
    }
    private func stableEvidence(_ key:String,unknown:Set<Int>,now:Double)->Bool {
        let ready=stable(key,now:now)
        for index in unknown { pendingUnknownCounts[index,default:0] += 1 }
        // Empty points seen clearly at least twice in this same candidate window
        // are resolved. A moving fringe of empty-point flicker must not accumulate
        // forever; every occupied/captured point is still checked on every frame.
        let unresolved=pendingUnknownCounts.values.filter { pendingCount-$0<2 }.count
        if ready && unresolved>unclearLimit {
            reject("Too many intersections became uncertain during this move. Keep hands out of view.",kind:.settling)
            return false
        }
        // Clear evidence breaks a continuous blockage even while the move is
        // still accumulating confirmation frames. Do not carry a hand's earlier
        // obscuration time into a later one-frame glitch.
        blockedSince=nil; blockedKind=nil
        return ready
    }
    private func beginTrace(append:Bool=false) {
        try? traceHandle?.close(); traceHandle=nil; diagnosticError=nil; observationNumber=0
        guard let url=autosaveURL?.deletingPathExtension().appendingPathExtension("observations.jsonl") else { return }
        do {
            if !append || !FileManager.default.fileExists(atPath:url.path) { try Data().write(to:url,options:.atomic) }
            traceHandle=try FileHandle(forWritingTo:url)
            if append { try traceHandle?.seekToEnd() }
        }
        catch { diagnosticError="Could not save recording diagnostics: \(error.localizedDescription)" }
    }
    func logAutomaticClockPause(_ pause:LocalGameClock.AutomaticPause) {
        guard hasGame else {return}
        trace(event:"clock automatically paused",extra:["pauseReason":pause.reason,"pauseStartedAt":pause.recordedAt.timeIntervalSince1970])
    }
    func logAlignmentCheck(_ report:[String:Any],decision:String,now:Double) {
        guard hasGame else {return}
        trace(event:"grid alignment check",now:now,extra:["alignment":report,"alignmentDecision":decision])
    }
    func logAutomaticClockResume() {
        guard hasGame else {return}
        trace(event:"clock automatically resumed",extra:["playerToPlay":clock.engine.blackToPlay ? "Black":"White"])
    }
    func logSpeech(_ event:String,details:[String:Any]) {
        guard hasGame else {return}
        trace(event:"speech "+event,extra:details)
    }
    private func trace(event:String,observation:BoardObservation?=nil,now:Double?=nil,extra:[String:Any]=[:]) {
        let history=pausedTentativeHistory ?? observationHistory
        var entry:[String:Any] = ["event":event,"time":Date().timeIntervalSince1970,"state":String(describing:state),
            "moveCount":moveCount,"synchronized":synchronized,"pendingFrames":pendingCount,"status":status,"unconfirmedMoves":pendingMoveCount,"bufferedFrames":observationHistory.frameCount,"unsavedStoneCandidates":unsavedStoneCount,"needsAttention":needsAttention,"unclearPointCount":unclearPointCount,"adjustmentPoints":adjustmentIssues.keys.sorted(),"recordingProblem":needsAttention ? recordingProblemTitle:"","localEvidenceRuns":localEvidenceRunCount,"localEvidenceSamples":localEvidenceSampleCount,"usedLocalEvidence":observationHistory.usedLocalEvidence,
            "tentativeSequences":history.tentativeSequences,"awaitingClarity":history.awaitingClarity,
            "retainedWitnesses":history.retainedWitnessCount,
            "localCandidatePoints":history.localEvidence.unresolvedPoints(base:player.board.grid.flatMap{$0}.map{$0 == .black ? .black : $0 == .white ? .white : .empty}).sorted(),
            "tentativeConfidence":history.moveConfidence.map{["point":$0.point as Any? ?? NSNull(),"level":$0.level,"clearSightings":$0.clearSightings,"requiredSightings":$0.requiredSightings,"orderSupported":$0.orderSupported,"alternatives":$0.alternatives,"placementUncertain":$0.placementUncertain]}]
        if let now { entry["uptime"]=now }
        if let observation {
            entry["lightingBlocked"]=observation.lightingBlocked
            if let notice=observation.notice { entry["detectionNotice"]=notice }
            observationNumber += 1; entry["observation"]=observationNumber; entry["size"]=observation.size
            entry["trackedAssignments"]=Dictionary(uniqueKeysWithValues:observation.trackedAssignments.map{(String($0.key),$0.value)})
            entry["position"]=observation.signature.map { $0 == .black ? "B" : $0 == .white ? "W" : $0 == .empty ? "." : "?" }.joined()
        }
        entry.merge(extra) {_,new in new}
        if clock.enabled {
            entry["clock"]=["running":clock.running,"blackSeconds":clock.engine.black.remaining,"whiteSeconds":clock.engine.white.remaining,
                "blackToPlay":clock.engine.blackToPlay,"blackPeriods":clock.engine.black.periods,"whitePeriods":clock.engine.white.periods,
                "needsCorrection":clock.needsCorrection,"notice":clock.notice,"automaticPauseReason":clock.automaticPause?.reason ?? ""]
        }
        if event == "observation",state == .recording,let now,let path=observationHistory.bestCandidate {
            for (offset,evidence) in pendingConfidence.enumerated() {
                guard let point=evidence.point,path.moves.indices.contains(offset),path.moves[offset]==point,
                      let first=path.witnesses.first(where:{$0.depth>offset && !$0.unknown.contains(point)}) else {continue}
                let candidateKey="\(moveCount+offset+1)/\(point)"
                if reviewStarts[candidateKey] == nil {reviewStarts[candidateKey]=first.time>=timingEpoch ? first.time:now}
                let elapsed=now-reviewStarts[candidateKey]!
                let reason=elapsed>=5 ? "slow move" : elapsed>=2 && (evidence.level != "high" || evidence.placementUncertain) ? "uncertain move" : nil
                guard let reason else {continue}
                let key="\(moveCount+offset+1)/\(point)/\(reason)"
                guard reviewTriggers.insert(key).inserted else {continue}
                var review:[String:Any]=["event":"local move review","reason":reason,"uptime":now,"time":Date().timeIntervalSince1970,
                    "game":autosaveURL?.lastPathComponent ?? timingRun,"mode":"local","point":point,"size":game.boardSize,
                    "moveNumber":moveCount+offset+1,"elapsedSeconds":elapsed,"confidenceLevel":evidence.level,
                    "placementUncertain":evidence.placementUncertain,"labelsAreGroundTruth":false]
                if let folder=onEvidenceCapture?(review) {review["evidenceCaptureFolder"]=folder}
                var reviews=entry["moveReviews"] as? [[String:Any]] ?? [];reviews.append(review);entry["moveReviews"]=reviews
            }
        }
        for value in entry["moveTimings"] as? [[String:Any]] ?? [] {
            guard let seconds=value["seconds"] as? Double,seconds>=5,
                  let number=value["moveNumber"] as? Int,let point=value["point"] as? Int,
                  reviewTriggers.insert("\(number)/\(point)/slow move").inserted else {continue}
            var review:[String:Any]=["event":"local move review","reason":"slow move","uptime":now ?? ProcessInfo.processInfo.systemUptime,
                "time":Date().timeIntervalSince1970,"game":autosaveURL?.lastPathComponent ?? timingRun,"mode":"local",
                "size":game.boardSize,"point":point,"moveNumber":number,"elapsedSeconds":seconds,"labelsAreGroundTruth":false]
            if let folder=onEvidenceCapture?(review) {review["evidenceCaptureFolder"]=folder}
            var reviews=entry["moveReviews"] as? [[String:Any]] ?? [];reviews.append(review);entry["moveReviews"]=reviews
        }
        if event.hasPrefix("recording warning:"),state == .recording,reviewTriggers.insert("warning/\(moveCount)").inserted {
            var review:[String:Any]=["event":"local move review","reason":"Unrecorded stones warning","uptime":now ?? ProcessInfo.processInfo.systemUptime,
                "time":Date().timeIntervalSince1970,"game":autosaveURL?.lastPathComponent ?? timingRun,"mode":"local",
                "size":game.boardSize,"moveNumber":moveCount+1,"labelsAreGroundTruth":false]
            if let folder=onEvidenceCapture?(review) {review["evidenceCaptureFolder"]=folder}
            entry["moveReviews"]=[review]
        }
        onDiagnosticEvent?(entry)
        guard let traceHandle else {return}
        do {
            var data=try JSONSerialization.data(withJSONObject:entry,options:[.sortedKeys]); data.append(10)
            try traceHandle.write(contentsOf:data)
        } catch { diagnosticError="Could not save recording diagnostics: \(error.localizedDescription)" }
    }

    private func observeEmptyView(_ observation:BoardObservation, now:Double) {
        if let last=emptyViewLast, now<=last { return }
        emptyViewVerified = false
        let readings = observation.readings
        let unknown = Set(readings.indices.filter { readings[$0].occupancy == .uncertain })
        guard [9,13,19].contains(observation.size), readings.count == observation.size * observation.size,
              unknown.count <= max(2,readings.count/20),
              readings.enumerated().allSatisfy({ $0.element.row == $0.offset/observation.size &&
                  $0.element.col == $0.offset%observation.size && $0.element.occupancy.stone == nil }) else {
            emptyViews.removeAll(); emptyViewLast = now; return
        }
        if emptyViewSize != observation.size { emptyViews.removeAll() }
        emptyViewSize = observation.size
        emptyViewLast = now
        emptyViews.removeAll { now-$0.time > 1.5 }
        emptyViews.append((now,unknown))
        guard emptyViews.count >= 5, let first=emptyViews.first, now-first.time >= 0.8 else {return}
        // Shadows can flicker at different points in successive frames. Every
        // point still needs repeated positive empty readings, including a recent one.
        let questionable = emptyViews.reduce(into:Set<Int>()) { $0.formUnion($1.unknown) }
        emptyViewVerified = questionable.allSatisfy { point in
            let clear = emptyViews.filter { !$0.unknown.contains(point) }
            return clear.count >= 3 && clear.last.map { now-$0.time <= 0.8 } == true
        }
    }
    /// Like empty-board setup, assemble fresh positive evidence across frames.
    /// Unknown is never evidence of empty. A concrete contradiction invalidates
    /// that point's earlier evidence; every handicap stone must stay visible.
    private func handicapSetupVerified(_ readings:[Occupancy],expected:[Occupancy],now:Double)->Bool {
        guard readings.filter({$0 == .uncertain}).count <= max(2,readings.count/20),
              readings.indices.allSatisfy({expected[$0] != .black || readings[$0] == .black}) else {
            handicapViews=[];return false
        }
        handicapViews.removeAll {now-$0.time > 1.5}
        handicapViews.append((now,readings))
        guard handicapViews.count>=5,let first=handicapViews.first,now-first.time>=0.8 else {return false}
        return readings.indices.allSatisfy {point in
            if expected[point] == .black {return true}
            guard readings[point].stone == nil else {return false}
            let contradiction=handicapViews.lastIndex {$0.readings[point].stone != nil}
            let eligible=handicapViews.dropFirst(contradiction.map {$0+1} ?? 0)
            let clear=eligible.filter {$0.readings[point] == .empty}
            return clear.count>=3 && clear.last.map {now-$0.time<=0.8} == true
        }
    }
    var activityLabel:String {
        switch state {
        case .idle:return "Recording not started"
        case .verifying:return game.handicap>0 ? "Not recording yet · Verify handicap stones" : "Not recording yet · Waiting for empty board"
        case .recording:if hasDeferredMoves {return "Recording later moves · \(reviewHistory.unresolved) reviews needed"};if retainingTentativeMoves {return "Recording · \(moveCount) confirmed · \(pendingMoveCount) tentative"};if needsAttention { return "Recording blocked · \(moveCount) moves recorded" }; return synchronized ? "Recording · \(moveCount) moves recorded" : "Checking board · \(moveCount) moves recorded"
        case .paused:return "Paused · \(moveCount) saved · \(pendingMoveCount) pending"
        case .finished:return "Recording finished · \(moveCount) moves recorded"
        }
    }


    func consume(_ observation:BoardObservation, now:Double) {
        guard !recoveryReadBlocked else {return}
        // Let this fresh frame clear a resolved contradiction before deciding
        // whether the same frame confirms a move. Each timestamp is counted once.
        updateAdjustmentGuidance(observation,now:now)
        defer {
            checkpointPendingMoves()
            noteReviewCamera(observation,now:now)
            if hasGame { trace(event:"observation",observation:observation,now:now) }
        }
        if timingNeedsFreshEpoch {timingEpoch=now;timingNeedsFreshEpoch=false}
        if observation.lightingBlocked {
            let reason = observation.notice ?? "Waiting for a readable board."
            if lastTime != nil || emptyViewLast != nil || ((state == .recording || state == .verifying) && status != reason) {
                suspendVision(reason,preserveObservations:true)
            }
            return
        }
        observeEmptyView(observation,now:now)
        guard state == .verifying || state == .recording else { return }
        retainingTentativeMoves=false
        guard observation.size == game.boardSize, observation.readings.count == game.boardSize*game.boardSize,
              observation.readings.enumerated().allSatisfy({ $0.element.row == $0.offset/game.boardSize && $0.element.col == $0.offset%game.boardSize }) else {
            suspendVision("Board size or grid changed. Restore the recorded board before continuing."); return
        }
        if let lastTime {
            guard now > lastTime else { return } // Repeated redraws cannot make a move stable.
            if now-lastTime > 1.5 { suspendVision("Checking the board after a camera interruption.",preserveOrder:true) }
        }
        lastTime=now
        let readings=observation.signature
        unclearPointCount=readings.filter{$0 == .uncertain}.count
        // Evaluate after acceptance so a move saved in this frame never gets a
        // failure sound. This runs even when global uncertainty blocks the move.
        defer {
            if state == .recording && !hasDeferredMoves {
                updateRecordingWarning(readings,now:now)
                updatePlacementChime(observation, readings:readings, now:now)
            }
        }
        if state == .verifying {
            if game.handicap>0 {
                let expected=positions[0].grid.flatMap {$0}.map {$0 == .black ? Occupancy.black:Occupancy.empty}
                let misplaced=readings.indices.filter {readings[$0].stone != nil && readings[$0] != expected[$0]}
                let missing=readings.indices.filter {expected[$0] == .black && readings[$0] != .black}
                if handicapSetupVerified(readings,expected:expected,now:now) {
                    state = .recording;synchronized=true;boardReadyForPass=true;verificationFrames=5;resetPending()
                    initialPositionReady(at:now)
                    status="Handicap verified · White to play. Moves are saved as the camera confirms them."
                    trace(event:"handicap verified",now:now)
                } else if !misplaced.isEmpty {
                    status="An extra or wrong-colored stone is visible. Match the black stones on the setup board; wait before White plays."
                } else if !missing.isEmpty {
                    status="Waiting for a clear view of all \(game.handicap) black handicap stones. Place them as shown and move your hands away."
                } else {
                    status="All \(game.handicap) handicap stones are in place. Checking the empty intersections; keep hands clear. White’s clock starts after verification."
                }
                return
            }
            if hasVerifiedEmptyBoard(size:game.boardSize,now:now) {
                state = .recording; synchronized=true; boardReadyForPass=true; verificationFrames=5; resetPending()
                initialPositionReady(at:now)
                status="Ready · Black to play. Moves are saved as the camera confirms them."
            } else {
                verificationFrames = min(5,emptyViews.count)
                let stones = readings.filter{$0.stone != nil}.count
                let unknown = readings.filter{$0 == .uncertain}.count
                if stones > 0 {
                    status = "Clear the board before Black’s first move. \(stones) possible \(stones == 1 ? "stone" : "stones") visible."
                } else if unknown > 0 {
                    status = "Checking the empty board: \(unknown) uncertain \(unknown == 1 ? "intersection" : "intersections"). Keep hands out of view."
                } else {status = "Checking the empty board. Keep your hands out of view and wait for Ready."}
            }
            return
        }
        if hasDeferredMoves {
            let changed=retainDeferred(observation,now:now,allowStart:false)
            if !changed,!synchronized,observation.signature==reviewHistory.latest,stable("live sync",now:now) {
                synchronized=true;resetPending()
                clock.followLiveTurn(liveNextPlayer,at:now,resumeIfReady:true)
            }
            status="Recording later moves · \(reviewHistory.unresolved) sections to review after play · \(reviewHistory.retainedMoveCount) ordered moves retained."
            return
        }
        let expected=player.board.grid.flatMap { $0 }.map { $0 == .black ? Occupancy.black : $0 == .white ? .white : .empty }
        guard observationHistory.noteFrame(now:now) else {return}
        let rawUnknown=Set(readings.indices.filter{readings[$0] == .uncertain})
        let retainedOld=MoveObservationHistory.confirmedOcclusions(readings,base:expected,after:expected)
        let unknown=rawUnknown.subtracting(retainedOld)
        // Broad obstruction can turn old white stones into false dark/empty
        // readings. Treat that frame as a chronology gap. Keep locally useful
        // views with only a few additions even if another region is obscured.
        // Diagnostic images/classifications remain unchanged in either case.
        let additions=readings.indices.filter{readings[$0].stone != nil && readings[$0] != expected[$0]}.count
        let broadlyObscured=unknown.count>unclearLimit && additions>8
        let localReadings=broadlyObscured ? Array(repeating:Occupancy.uncertain,count:readings.count) : readings
        observationHistory.retainLocalEvidence(localReadings,base:expected,now:now)
        pendingMoveCount=observationHistory.pendingCount
        let sustainedViewLoss=viewContinuity.observe(unverified:unknown.count,total:readings.count,now:now)
        // Recorded stone identities survive unreadable frames. New placements,
        // possible captures and clear contradictions are checked by legal candidates.
        // Broad uncertainty over previously empty space still suspends confirmation.
        guard unknown.count<=unclearLimit else {
            reviewHistory.interrupt()
            reject("Checking \(unknown.count) unclear intersections. Observations are retained while move order is resolved.",kind:.settling)
            // Partial uncertainty and unresolved move order are not a lost camera
            // view. Only a separate, sustained broad loss may stop the clock.
            if sustainedViewLoss,clock.running {
                trace(event:"sustained unreadable view",observation:observation,now:now,
                      extra:["unverifiedIntersections":unknown.count,"viewLossSeconds":viewContinuity.duration(at:now),
                             "viewLossFrames":viewContinuity.samples,"moveOrderIsNotPauseCause":true])
                synchronized=false
                clock.interrupt("Much of the board has been unreadable for 10 seconds. Clear the view so move timing can continue.",at:now)
            }
            return
        }
        let retained=MoveObservationHistory.confirmedOcclusions(readings,base:expected,after:expected)
        let matchesRest=observationHistory.canVerifyRest(readings,base:expected) && readings.indices.allSatisfy { readings[$0] == expected[$0] || (readings[$0] == .uncertain && (expected[$0] == .empty || retained.contains($0))) }
        func unresolvedContradiction(after:[Occupancy])->Bool {
            adjustmentIssues.contains {point,kind in
                kind == .conflict && expected[point].stone != nil && after[point]==expected[point]
            }
        }
        if matchesRest && unresolvedContradiction(after:expected) {
            reject("A marked recorded stone disagreed with the camera. Waiting for consistent agreement at that intersection.",kind:.conflict)
            return
        }
        if matchesRest { resetObservationHistory();unresolvedSince=nil;reviewHistory.interrupt() }
        if !synchronized && matchesRest {
            if stableEvidence("sync",unknown:unknown,now:now) {
                synchronized=true; boardReadyForPass=true; clearBlock(); resetPending(); status="Recording · \(nextPlayer.rawValue.capitalized) to play."
                clock.ready(at:now)
            }
            return
        }
        if matchesRest {
            clock.ready(at:now)
            if stableEvidence("rest",unknown:unknown,now:now) { boardReadyForPass=true; clearBlock() }
            status="Recording · \(nextPlayer.rawValue.capitalized) to play."; return
        }
        boardReadyForPass=false
        let result=observationHistory.observe(readings:readings,game:game,base:player.board,now:now,
                                             recovering:!synchronized,unclearLimit:unclearLimit,observation:observation)
        if let revision=observationHistory.lastReconciliation {
            pendingMoveCount=observationHistory.pendingCount
            trace(event:"tentative adjustment reconciled",observation:observation,now:now,
                  extra:["previousTentativeSequences":revision.before,"revisedTentativeSequence":revision.after,
                         "labelsAreGroundTruth":false])
        }
        switch result {
        case .tracking(let count):
            // One retained chronology remains useful while placement needs
            // clarity. Competing orders that cannot settle get a review section.
            if observationHistory.tentativeSequences.count>1 {
                if unresolvedSince == nil {unresolvedSince=now}
                if now-(unresolvedSince ?? now)>12,retainDeferred(observation,now:now,allowStart:true) {return}
            } else {unresolvedSince=nil;reviewHistory.interrupt()}
            pendingMoveCount=count
            retainingTentativeMoves=observationHistory.awaitingClarity
            blockedSince=nil;blockedKind=nil
            status=observationHistory.awaitingClarity
                ? "Retaining \(count) tentative moves. An earlier stone is unclear; later moves are still tracked. SGF waits for confirmation."
                : "Tracking \(count) unconfirmed \(count == 1 ? "move" : "moves"). Earlier observations are retained while play continues."
        case .confirmed(let confirmation):
            let proposed=confirmation.boards.last!.grid.flatMap{$0}.map {stone -> Occupancy in
                if stone == .black {return .black};if stone == .white {return .white};return .empty
            }
            if unresolvedContradiction(after:proposed) {
                reject("A marked recorded stone disagreed with the camera. Waiting for consistent agreement before saving the new move.",kind:.conflict)
                return
            }
            unresolvedSince=nil;reviewHistory.interrupt()
            synchronized=true
            appendVerifiedSequence(confirmation.moves,boards:confirmation.boards,now:now)
            let accepted=player.board.grid.flatMap{$0}.map{$0 == .black ? Occupancy.black : $0 == .white ? .white : .empty}
            if observationHistory.pendingCount==0 && observationHistory.canVerifyRest(readings,base:accepted) &&
                readings.indices.allSatisfy({readings[$0]==accepted[$0] || (readings[$0] == .uncertain && accepted[$0] == .empty)}) {
                resetObservationHistory()
            }
        case .blocked(let message,let settling):
            if unresolvedSince == nil {unresolvedSince=now}
            if ((!settling && additions>=3 && observationHistory.pendingCount==0) || now-(unresolvedSince ?? now)>12),retainDeferred(observation,now:now,allowStart:true) {return}
            pendingMoveCount=observationHistory.pendingCount
            reject(message,kind:settling ? .settling : .conflict)
        }
    }
    private func updatePlacementChime(_ observation: BoardObservation, readings: [Occupancy], now: Double) {
        guard let onPlacementChime else { return }
        let flagged = pendingConfidence.enumerated().filter { $0.element.orderSupported && $0.element.placementUncertain }
        guard !flagged.isEmpty,
              let currentBoard = observationHistory.bestCandidate?.boards.last else {
            placementChimes.interrupt()
            return
        }
        let base = player.board.grid.flatMap { $0 }.map { $0 == .black ? Occupancy.black : $0 == .white ? .white : .empty }
        let offsets = observation.assignmentOffsets(confirmedBoard:base)
        var visible = Set<PlacementChimeMonitor.Issue>(), displaced = visible
        for (index, flag) in flagged {
            guard let p=flag.point, let color=readings[p].stone,
                  currentBoard.grid[p/game.boardSize][p%game.boardSize] == color,
                  color == (index.isMultiple(of:2) ? nextPlayer : nextPlayer.opponent) else { continue }
            let issue = PlacementChimeMonitor.Issue(move:moveCount+index+1, point:p)
            visible.insert(issue)
            if let offset=offsets[p], offset>0.24+1e-9 { displaced.insert(issue) }
        }
        let due = placementChimes.update(visible:visible, displaced:displaced, now:now)
        if !due.isEmpty {
            trace(event:"placement chime",now:now)
            onPlacementChime(due)
        }
    }
    private func updateRecordingWarning(_ readings:[Occupancy],now:Double) {
        var accounted=player.board.grid.flatMap{$0}.map{$0 == .black ? Occupancy.black : $0 == .white ? .white : .empty}
        var knownPlacementWarnings=Set<Int>(),trackedMoves=Set<Int>()
        // Confirmation into SGF may wait on an earlier placement. A later
        // locked stone in the sole retained path has already been accounted for.
        if observationHistory.candidates.count==1, let path=observationHistory.candidates.first,
           let board=path.boards.last {
            trackedMoves=Set(path.moves)
            var seen=Set<Int>()
            for index in path.moves.indices.reversed() {
                let point=path.moves[index]
                // A capture and replay at the same point creates a new identity.
                guard seen.insert(point).inserted, let color=board.grid[point/game.boardSize][point%game.boardSize] else {continue}
                if path.locked.contains(index) {
                    accounted[point] = color == .black ? .black : .white
                } else if path.placementConcerns.contains(index), readings[point].stone == color || readings[point] == .uncertain {
                    knownPlacementWarnings.insert(point)
                }
            }
        }
        let signal=warningMonitor.update(readings:readings,accepted:accounted,now:now,blocked:needsAttention,
                                         knownPlacementWarnings:knownPlacementWarnings,trackedMoves:trackedMoves,coalesceEpisode:needsAttention)
        unsavedStoneCount=warningMonitor.outstandingCount
        if signal != nil || warningMonitor.hasWarnedOutstanding {
            needsAttention=true
        }
        guard let signal else {return}
        attentionMessage=retainingTentativeMoves
            ? "Board confirmation is incomplete. \(pendingMoveCount) tentative moves are retained locally; SGF waits for confirmation."
            : "Stop playing and check the board. Last saved: move \(moveCount). Detected stones have not been saved."
        trace(event:"recording warning: \(signal.rawValue)",now:now)
        onAttention?()
    }
    /// Confirm only the supported common prefix. Keep later tentative moves in
    /// memory, and preserve every intermediate board for ordinary SGF review.
    private func appendVerifiedSequence(_ indices:[Int],boards:[BoardSnapshot],now:Double) {
        // Use retained recognition evidence; do not infer a physical placement instant.
        // Pauses, restored checkpoints and alignment interruptions have a fresh epoch.
        let matching=observationHistory.candidates.filter {Array($0.moves.prefix(indices.count))==indices}
        let timings:[[String:Any]]=indices.enumerated().map {offset,point in
            let starts=matching.compactMap {candidate in
                candidate.witnesses.first(where:{$0.depth>offset && !$0.unknown.contains(point)})?.time
            }
            let first=starts.min()
            var value:[String:Any]=["moveNumber":moveCount+offset+1,"point":point,"size":game.boardSize,
                "color":boards[offset].grid[point/game.boardSize][point%game.boardSize]?.rawValue ?? "",
                "timingScope":"first retained candidate to recorded","run":timingRun]
            if let first,first>=timingEpoch,now>=first {value["seconds"]=now-first}
            else {value["unavailableReason"]="No uninterrupted candidate timing (pause, recovery or missing evidence)."}
            return value
        }
        let firstNumber=moveCount+1
        var color=nextPlayer, colors=[Stone]()
        for index in indices {
            colors.append(color)
            game.moves.append((color,(index%game.boardSize,index/game.boardSize)))
            color=color == .black ? .white : .black
        }
        player.load(game:game);player.seek(to:moveCount)
        positions.append(contentsOf:boards);reviewIndex=moveCount
        warningMonitor.recorded(indices)
        observationHistory.rebase(after:indices.count);pendingMoveCount=observationHistory.pendingCount
        boardReadyForPass=pendingMoveCount==0
        clearBlock();resetPending()
        status=pendingMoveCount>0
            ? "Recorded through move \(moveCount) · Tracking \(pendingMoveCount) later unconfirmed moves."
            : "Recorded move \(moveCount) · \(nextPlayer.rawValue.capitalized) to play."
        if indices.count==1 {
            clock.recordMove(number:moveCount,black:colors[0] == .black,at:now,observedAt:(timings[0]["seconds"] as? Double).map {now-$0})
        } else {
            clock.recordCatchUp(first:firstNumber,last:moveCount,blackToPlay:nextPlayer == .black,at:now)
        }
        clock.ready(at:now) // May resume an automatic view hold; never a manual pause/review.
        persist()
        trace(event:indices.count==1 ? "accepted move" : indices.count==2 ? "accepted two-move catch-up" : "accepted observed sequence",now:now,extra:["moveTimings":timings])
        for (offset,color) in colors.enumerated() { onMoveAccepted?(firstNumber+offset,color) }
    }
    private func append(position:BoardPosition?,manual:Bool) {
        let color=nextPlayer
        guard player.tryPlayMove(color:color,x:position?.col ?? -1,y:position?.row ?? -1) == nil else { return }
        resetObservationHistory()
        game.moves.append((color,position.map { ($0.col,$0.row) }))
        if manual { manualMoves.insert(moveCount) }
        positions.append(player.board); reviewIndex=moveCount; boardReadyForPass=true; clearBlock(); resetPending()
        status="Recorded move \(moveCount) · \(nextPlayer.rawValue.capitalized) to play."
        clock.recordMove(number:moveCount,black:color == .black,at:ProcessInfo.processInfo.systemUptime,manualCorrection:position != nil && manual)
        if player.lastTwoMovesWerePasses { finish() } else { persist() }
        trace(event:manual ? "manual move" : "accepted move"); onMoveAccepted?(moveCount,color)
    }
    func pass() {
        guard canPass else {return}
        if hasDeferredMoves,let color=reviewHistory.nextColor,let board=reviewHistory.latest {
            let now=ProcessInfo.processInfo.systemUptime
            let precedingWasPass=ReviewHistoryCoordinator.precedingWasPass(reviewHistory,game:game)
            reviewHistory.sections.append(.init(before:board,after:board,moves:[.init(color:color,point:nil)],manual:true,
                                                reason:"Pass entered by player",firstSeen:now,confirmedAt:now,liveNext:color.opponent))
            reviewHistory.turnOverride=nil
            clock.recordLiveMove(id:reviewHistory.sections.last!.id,black:color == .black,at:now,observedAt:now)
            reviewHistory.interrupt();saveReviewHistory();trace(event:"pass retained after gap")
            if precedingWasPass {finish()}
            return
        }
        resetObservationHistory();append(position:nil,manual:true)
    }
    func manualMove(at position:BoardPosition) {
        guard canEdit else { return }
        if let rejection=player.moveRejection(color:nextPlayer,x:position.col,y:position.row) { status=rejection.rawValue; return }
        resetObservationHistory();append(position:position,manual:true); synchronized=false
        status="Move entered manually. Check the physical board, then Resume recording."
    }
    /// Validate the entire proposal before saving any of it. A rejected or stale
    /// proposal leaves accepted and tentative history untouched.
    @discardableResult func approveRecovery(_ draft:MoveRecoveryDraft,allowDeferred:Bool=false,manualMoveNumbers:Set<Int>?=nil)->String? {
        guard (canEdit || (allowDeferred && [.paused,.finished].contains(state) && !reviewing)) else {return "Pause recording and return to the latest move before approving."}
        guard draft.baseRecord==sgf() else {return "The saved game changed. Cancel and start the sequence again."}
        guard !draft.moves.isEmpty else {return "Select at least one missed move."}
        let trial=SGFPlayer();trial.load(game:game);trial.seek(to:moveCount)
        var updated=game,boards=[BoardSnapshot]()
        for (offset,point) in draft.moves.enumerated() {
            guard !trial.lastTwoMovesWerePasses else {return "The sequence continues after two passes."}
            let color=trial.turn
            if let rejection=trial.tryPlayMove(color:color,x:point?.col ?? -1,y:point?.row ?? -1) {
                return "Selection \(offset+1): \(rejection.rawValue)"
            }
            updated.moves.append((color,point.map{($0.col,$0.row)}));boards.append(trial.board)
        }
        let oldGame=game,oldPositions=positions,oldManual=manualMoves,oldIndex=reviewIndex
        let first=moveCount+1
        game=updated;positions.append(contentsOf:boards);reviewIndex=moveCount
        manualMoves.formUnion(manualMoveNumbers ?? Set(first...moveCount))
        persist(checkpoint:false)
        if let error=saveError {
            game=oldGame;positions=oldPositions;manualMoves=oldManual;reviewIndex=oldIndex
            return error
        }
        player.load(game:game);player.seek(to:moveCount)
        resetObservationHistory();resetWarningMonitor();resetPending();clearBlock()
        synchronized=false;boardReadyForPass=false;timingNeedsFreshEpoch=true
        if !allowDeferred {clock.recover(toBlack:nextPlayer == .black,reason:"Missed moves entered manually. Check both clocks before resuming.",at:ProcessInfo.processInfo.systemUptime)}
        checkpointPendingMoves()
        status="Saved \(draft.moves.count) recovered moves. Check the board before resuming."
        let selected=game.moves.suffix(draft.moves.count).enumerated().map { offset,move -> [String:Any] in
            ["moveNumber":first+offset,"color":move.0.rawValue,"point":move.1.map{$0.1*game.boardSize+$0.0} as Any? ?? NSNull()]
        }
        let automatic=allowDeferred && manualMoveNumbers?.isEmpty==true
        var evidence:[String:Any]=["reason":automatic ? "saved observation sequence recovery":"manual sequence recovery","size":game.boardSize,"selectedMoves":selected,
            "orderSource":automatic ? "repeated local sightings":"reviewed sequence",
            "timingUnavailableReason":"Historical order recovery does not reconstruct clock presses."]
        evidence["game"]=autosaveURL?.lastPathComponent ?? "local"
        evidence["snapshotHeldAt"]=draft.snapshotHeldAt
        evidence["cameraClipScope"]="Around approval; the frozen interpretation may be older. This is a history recovery, not a training label for every intersection."
        if let observation=draft.observation {evidence["observedPosition"]=observation.signature.map(\.rawValue)}
        if let clip=onEvidenceCapture?(evidence) {evidence["evidenceCapture"]=clip}
        trace(event:"manual sequence approved",extra:evidence)
        if trial.lastTwoMovesWerePasses {finish()}
        return nil
    }
    func undo() {
        guard !hasDeferredMoves else {status="Resolve the review sections before undoing saved moves.";return}
        guard !recoveryReadBlocked,hasGame,moveCount>0 else { return }
        // Preserve the previous record before a correction changes the autosave.
        do {try recordingStore.preserveBeforeUndo(sgf())}
        catch {saveError="Could not preserve the game before undo: \(error.localizedDescription)";return}
        placementChimes = PlacementChimeMonitor()
        manualMoves.remove(moveCount); game.moves.removeLast(); positions.removeLast(); reviewIndex=moveCount
        resetWarningMonitor()
        player.load(game:game); player.seek(to:moveCount); state = .paused; suspendVision("")
        clock.undo(to:moveCount,blackToPlay:nextPlayer == .black)
        status="Last move undone. Restore the physical board to this position, then Resume recording."; persist();trace(event:"undo")
    }
    func attachClock(_ settings:LocalClockSettings) {
        guard !recoveryReadBlocked,state == .paused,pendingMoveCount==0,!clock.enabled,settings.validationError==nil,settings.kind != .none else {return}
        clock.configure(settings,blackToPlay:nextPlayer == .black,baseMove:moveCount)
        persist();trace(event:"local clock attached")
    }
    func sgf()->String {
        var props=["GM":["1"],"FF":["4"],"CA":["UTF-8"],"SZ":[String(game.boardSize)],"RU":[game.info.rules ?? "Japanese"],"PL":[game.initialPlayer == .white ? "W":"B"],"AP":["PhysicalGo:0.121"],
            "C":["Physical Go camera recording. Review move history before sharing."]]
        for (tag,value) in [("DT",game.info.date),("PB",game.info.playerBlack),("PW",game.info.playerWhite),
            ("BR",game.info.blackRank),("WR",game.info.whiteRank),("KM",game.info.komi),("RE",game.info.result),("EV",game.info.event)] {
            if let value,!value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {props[tag]=[value]}
        }
        if game.handicap>0 {props["HA"]=[String(game.handicap)]}
        for stone in [Stone.black,.white] {
            let points=game.setup.filter {$0.0 == stone}.map {SGFCoordinates.toSGF(x:$0.1,y:$0.2)}
            if !points.isEmpty {props[stone == .black ? "AB":"AW"]=points}
        }
        props.merge(clock.engine.settings.sgfProperties) {_,new in new}
        if clock.enabled && clock.baseMove>0 {props["C",default:[]].append("Clock started or corrected after move \(clock.baseMove). Earlier times are not inferred.")}
        var nodes=[SGFNode(props:props)]
        for (i,move) in game.moves.enumerated() {
            var node=[move.0 == .black ? "B" : "W":[move.1.map{SGFCoordinates.toSGF(x:$0.0,y:$0.1)} ?? ""]]
            node.merge(clock.sgfMoveProperties(i+1)) {_,new in new}
            if manualMoves.contains(i+1) { node["C"]=["Entered manually."] }
            nodes.append(SGFNode(props:node))
        }
        return SGFWriter.serialize(SGFTree(branches:[.init(sequence:nodes)]))
    }
    private func persist(checkpoint:Bool=true) {
        guard let autosaveURL else { return }
        do {
            try recordingStore.saveGame(sgf(),signature:checkpointSignature); saveError=nil
            clock.bind(to:autosaveURL,signature:checkpointSignature)
            if checkpoint {checkpointPendingMoves()}
        } catch { saveError="Game is in memory but autosave failed: \(error.localizedDescription)" }
    }
}


extension GameRecorder {
    private func saveReviewHistory() {
        do {try recordingStore.saveReviews(reviewHistory);reviewSaveError=nil}
        catch {reviewSaveError="Review history could not be saved: \(error.localizedDescription). Keep the app open and retry saving."}
    }
    func retryReviewSave() {
        if recoveryReadBlocked {
            do {
                try restoreChronology()
            } catch { /* The corresponding load error remains visible; no writes. */ }
        } else {saveReviewHistory()}
    }
    private func restoreReviewHistory()throws {
        do {
            let restored=try recordingStore.loadReviews(game:game)
            reviewHistory=restored.history;recoveredReviewCommit=restored.recoveredCommit
            reviewSaveError=nil;reviewLoadFailed=false
            if reviewHistory.active {
                resetObservationHistory();clock.pause("Saved live clock restored · paused")
                if reviewHistory.endRequested {state = .finished}
                status="Restored \(reviewHistory.unresolved) reviews and \(reviewHistory.retainedMoveCount) later ordered moves. Resume recording to keep tracking."
            }
        } catch {reviewLoadFailed=true;reviewSaveError="Could not restore review history: \(error.localizedDescription)";throw error}
    }
    @discardableResult private func retainDeferred(_ observation:BoardObservation,now:Double,allowStart:Bool)->Bool {
        let wasActive=hasDeferredMoves
        let proposals=observationHistory.tentativeSequences
        guard reviewHistory.observe(observation,base:player.board,game:game,signature:checkpointSignature,now:now,allowStart:allowStart) else {return false}
        if !wasActive {
            reviewHistory.sections[reviewHistory.sections.count-1].suggestedOrders=proposals.map {points in
                points.enumerated().map {offset,point in DeferredMoveHistory.Move(color:offset%2==0 ? nextPlayer:nextPlayer.opponent,point:BoardPosition(point/game.boardSize,point%game.boardSize))}
            }
            resetObservationHistory();resetWarningMonitor();clearBlock();resetPending()
            synchronized=false;boardReadyForPass=false
        }
        if let section=reviewHistory.sections.last {
            synchronized=true
            if wasActive,let move=section.moves?.first,section.moves?.count==1 {
                clock.recordLiveMove(id:section.id,black:move.color == .black,at:now,observedAt:section.firstSeen)
            } else {clock.followLiveTurn(reviewHistory.nextColor,at:now,resumeIfReady:true)}
        }
        if let section=reviewHistory.sections.last,let number=section.reviewNumber {
            let event:[String:Any]=["game":autosaveURL?.lastPathComponent ?? "local","reason":"unresolved move-order section","reviewNumber":number,"reviewID":section.id.uuidString,"uptime":now,"labelsAreGroundTruth":false]
            reviewHistory.sections[reviewHistory.sections.count-1].evidenceFolder=onEvidenceCapture?(event)
        }
        saveReviewHistory()
        status="Recording continues · \(reviewHistory.unresolved) sections can be reviewed after play."
        trace(event:"review history extended",now:now,extra:["reviewCount":reviewHistory.reviews.count,"unresolvedReviews":reviewHistory.unresolved,"laterOrderedMoves":reviewHistory.retainedMoveCount])
        if let section=reviewHistory.sections.last,section.moves==nil {
            Task {await recoverSavedReviewOrder(section.id)}
        }
        return true
    }
    /// Recover without pausing live play or inventing historical clock presses.
    /// A unique legal sequence is retained automatically; ambiguity stays a review.
    func recoverSavedReviewOrder(_ id:UUID) async {
        guard let url=autosaveURL,
              let section=reviewHistory.sections.first(where:{$0.id==id}),!section.committed,section.moves==nil,
              let context=contextForReview(id),context.turnKnown else {return}
        let trial=SGFPlayer();trial.load(game:context.game);trial.seek(to:context.game.moves.count)
        let first=trial.turn,signature=checkpointSignature
        do {
            let result=try await Task.detached(priority:.utility) {
                try ReviewOrderRecovery.load(url:url.deletingPathExtension().appendingPathExtension("observations.jsonl"),
                    before:section.before,after:section.after,first:first,through:section.recordedAt)
            }.value
            guard autosaveURL==url,checkpointSignature==signature,activeReviewID != id,
                  let index=reviewHistory.sections.firstIndex(where:{$0.id==id}),
                  reviewHistory.sections[index].moves==nil,!reviewHistory.sections[index].committed,
                  let current=contextForReview(id),current.turnKnown,
                  self.signature(for:current.game)==self.signature(for:context.game) else {return}
            var orders=[[DeferredMoveHistory.Move]]()
            for points in result.orders {
                trial.load(game:current.game);trial.seek(to:current.game.moves.count)
                var moves=[DeferredMoveHistory.Move]()
                for point in points {
                    let color=trial.turn
                    guard trial.tryPlayMove(color:color,x:point%game.boardSize,y:point/game.boardSize)==nil else {break}
                    moves.append(.init(color:color,point:BoardPosition(point/game.boardSize,point%game.boardSize)))
                }
                if moves.count==points.count,DeferredMoveHistory.states(trial.board)==section.after {orders.append(moves)}
            }
            reviewHistory.sections[index].suggestedOrders=orders
            if orders.count==1 {
                reviewHistory.sections[index].moves=orders[0]
                reviewHistory.sections[index].resolvedAfter=section.after
                reviewHistory.sections[index].resolvedAt=Date().timeIntervalSince1970
                reviewHistory.sections[index].recoverySource="repeated local sightings v1"
                reviewHistory.sections[index].reason="Recovered automatically from repeated sightings; checked against the Go rules and saved camera position."
                status="Recovered \(orders[0].count) moves from saved observations. \(reviewHistory.unresolved) sections still need review."
            }
            saveReviewHistory()
            trace(event:"saved observation order recovery",extra:["reviewID":id.uuidString,"legalOrders":orders.count,
                "automaticallyResolved":orders.count==1,"message":result.message,
                "placementIntervals":result.intervals.map{["point":$0.point,"emptyThrough":$0.emptyThrough,"presentBy":$0.presentBy] as [String:Any]}])
        } catch {trace(event:"saved observation recovery unavailable",extra:["reviewID":id.uuidString,"error":error.localizedDescription])}
    }
    /// Earlier resolved sections supply full ko history. When an earlier gap is
    /// unresolved, review uses a frozen position and full validation is deferred.
    func contextForReview(_ id:UUID)->(game:SGFGame,turnKnown:Bool)? {
        guard let index=reviewHistory.sections.firstIndex(where:{$0.id==id}) else {return nil}
        let section=reviewHistory.sections[index]
        if section.committed,let start=section.savedStart {
            var prefix=game;prefix.moves=Array(game.moves.prefix(start));return (prefix,true)
        }
        var prefix=game
        let trial=SGFPlayer();trial.load(game:prefix);trial.seek(to:prefix.moves.count)
        for earlier in reviewHistory.sections.prefix(index) where !earlier.committed {
            guard let moves=earlier.moves else {
                let previous=reviewHistory.sections.prefix(index).last?.moves?.last?.color.opponent ?? .black
                return (DeferredMoveHistory.positionGame(section.before,size:game.boardSize,rules:game.info.rules,turn:previous),false)
            }
            for move in moves {
                guard trial.tryPlayMove(color:move.color,x:move.point?.col ?? -1,y:move.point?.row ?? -1)==nil else {
                    return (DeferredMoveHistory.positionGame(section.before,size:game.boardSize,rules:game.info.rules,turn:moves.last?.color.opponent ?? .black),false)
                }
                prefix.moves.append((move.color,move.point.map{($0.col,$0.row)}))
            }
        }
        return (prefix,true)
    }
    func canWithdrawAccidentalMoves(_ id:UUID)->Bool {accidentalWithdrawalPlan(id) != nil}
    /// Resolve the addition and its later removal as one explicit cleanup,
    /// preserving every independently legal later move and all source snapshots.
    @discardableResult func withdrawAccidentalMoves(_ id:UUID,removedByPlayer:Bool,
                                                   now:Double=ProcessInfo.processInfo.systemUptime)->String? {
        guard state == .paused,!reviewing,removedByPlayer,let plan=accidentalWithdrawalPlan(id) else {
            return "Choose the accidental stones to undo. Later moves must remain legal before this cleanup can be saved."
        }
        guard accidentalRemovalVerified(plan,now:now) else {
            return "The camera is still checking the cleanup. Remove only the marked extra stones and keep your hands clear."
        }
        let previous=reviewHistory
        for i in reviewHistory.sections.indices where plan.sectionIDs.contains(reviewHistory.sections[i].id) {
            let sectionID=reviewHistory.sections[i].id
            reviewHistory.sections[i].moves=plan.moves[sectionID]
            reviewHistory.sections[i].resolvedAfter=plan.results[sectionID]
            reviewHistory.sections[i].resolvedAt=Date().timeIntervalSince1970
            reviewHistory.sections[i].recoverySource="Player removed accidental out-of-turn stones; related removals resolved together and later legal moves preserved."
        }
        saveReviewHistory()
        if let error=reviewSaveError {reviewHistory=previous;return error}
        trace(event:"accidental stones withdrawn",extra:["reviewIDs":plan.sectionIDs.map(\.uuidString),
            "removedPoints":plan.removedPoints.sorted(),"keptLaterMoves":plan.keptMoves.count])
        if reviewHistory.unresolved==0 {return finalizeReviews()}
        status="Accidental stones removed from the record. Later moves are preserved; \(reviewHistory.unresolved) reviews remain."
        return nil
    }
    @discardableResult func resolveReview(_ id:UUID,draft:MoveRecoveryDraft,overrideCamera:Bool,resolutionReason:String?=nil)->String? {
        guard [.paused,.finished].contains(state),!reviewing,
              let index=reviewHistory.sections.firstIndex(where:{$0.id==id}),!reviewHistory.sections[index].committed else {return "Pause recording before resolving this section."}
        let approvalStarted=ProcessInfo.processInfo.systemUptime
        trace(event:"section approval started",extra:["reviewID":id.uuidString])
        let after=DeferredMoveHistory.states(draft.board)
        guard after==reviewHistory.sections[index].after || overrideCamera else {
            return "Your sequence and the saved camera snapshot differ. Compare the pink-marked intersections below; correct the sequence or confirm that the camera snapshot is wrong."
        }
        let trial=SGFPlayer();trial.load(game:draft.baseGame);trial.seek(to:draft.baseGame.moves.count)
        var moves=[DeferredMoveHistory.Move]()
        for point in draft.moves {
            let color=trial.turn
            if let error=trial.tryPlayMove(color:color,x:point?.col ?? -1,y:point?.row ?? -1) {return error.rawValue}
            moves.append(.init(color:color,point:point))
        }
        reviewHistory.sections[index].moves=moves
        reviewHistory.sections[index].recoverySource=resolutionReason
        reviewHistory.sections[index].resolvedAfter=after
        reviewHistory.sections[index].resolvedAt=Date().timeIntervalSince1970
        saveReviewHistory()
        if let reviewSaveError {return reviewSaveError}
        trace(event:"review section resolved",extra:["review":reviewHistory.sections[index].reviewNumber ?? 0,"approvalSeconds":ProcessInfo.processInfo.systemUptime-approvalStarted,"selectedMoves":moves.map{["color":$0.color.rawValue,"point":$0.point.map{$0.row*game.boardSize+$0.col} as Any? ?? NSNull()]}])
        if reviewHistory.unresolved==0 {return finalizeReviews()}
        status="Review saved. \(reviewHistory.unresolved) sections still need review. Later moves remain preserved."
        return nil
    }
    @discardableResult func finalizeReviews()->String? {
        guard [.paused,.finished].contains(state),hasDeferredMoves,reviewHistory.unresolved==0 else {return "Resolve every red review section first."}
        if let reviewSaveError {return reviewSaveError}
        guard reviewHistory.anchorSignature==checkpointSignature else {return "The saved game changed; the review history has been preserved separately."}
        var draft=MoveRecoveryDraft(recorder:self,observation:nil)
        let trial=SGFPlayer();trial.load(game:game);trial.seek(to:moveCount)
        var manual=Set<Int>(),number=moveCount
        for i in reviewHistory.sections.indices where !reviewHistory.sections[i].committed {
            let section=reviewHistory.sections[i]
            for move in section.moves ?? [] {
                let error=trial.tryPlayMove(color:move.color,x:move.point?.col ?? -1,y:move.point?.row ?? -1)
                if let error {
                    let reason="The complete sequence needs another look here: \(error.rawValue)"
                    reviewHistory.requireReview(at:i,reason:reason);saveReviewHistory();return reason
                }
                _=draft.add(move.point,checkCameraColor:false);number += 1
                if (section.reviewNumber != nil && section.recoverySource==nil) || section.manual == true {manual.insert(number)}
            }
            if DeferredMoveHistory.states(trial.board) != (section.resolvedAfter ?? section.after) {
                let reason="Earlier corrections change the position here. Review this section against the corrected history."
                reviewHistory.requireReview(at:i,reason:reason);saveReviewHistory();return reason
            }
        }
        // A false camera event may be resolved as no moves at all.
        if !draft.moves.isEmpty,let error=approveRecovery(draft,allowDeferred:true,manualMoveNumbers:manual) {return error}
        let scoreChanged=reviewHistory.scoredPosition.map{$0 != DeferredMoveHistory.states(player.board)} ?? false
        if scoreChanged {game.info.result=nil}
        var start=reviewHistory.baseMove ?? moveCount
        var clockMapping=[UUID:Int]()
        for i in reviewHistory.sections.indices where !reviewHistory.sections[i].committed {
            if reviewHistory.sections[i].moves?.count==1 {clockMapping[reviewHistory.sections[i].id]=start+1}
            reviewHistory.sections[i].savedStart=start;start += reviewHistory.sections[i].moves?.count ?? 0
            reviewHistory.sections[i].committed=true
        }
        clock.finalizeLiveHistory(mapping:clockMapping,moveCount:moveCount,blackToPlay:nextPlayer == .black)
        let ending=reviewHistory.endRequested || player.lastTwoMovesWerePasses
        reviewHistory.anchorSignature=nil;reviewHistory.baseMove=nil;reviewHistory.endRequested=false;reviewHistory.turnOverride=nil
        persist()
        saveReviewHistory();resetObservationHistory();resetWarningMonitor()
        status="All reviews resolved. \(moveCount) moves saved; SGF is ready to export."
        trace(event:"review queue finalized",extra:["reviewHistory":((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(reviewHistory))) ?? NSNull())])
        if ending {finish()}
        if scoreChanged {status="Reviews resolved. The corrected board differs from the scored board; score the game again before saving the result."}
        return reviewSaveError
    }
}

/// Clock continuity is independent of move-confirmation delays. A readable
/// region still supplies chronology even when the complete position is unclear.
struct CameraViewContinuity {
    private var began:Double?
    private var last:Double?
    private(set) var samples=0
    mutating func reset() {began=nil;last=nil;samples=0}
    func duration(at now:Double)->Double {began.map {max(0,now-$0)} ?? 0}
    mutating func observe(unverified:Int,total:Int,now:Double)->Bool {
        guard now.isFinite,total>0,unverified>=0,unverified<=total else {reset();return false}
        if let last,now<=last {return false}
        if let last,now-last>1.5 {reset()}
        last=now
        guard unverified>max(2,total/3) else {began=nil;samples=0;return false}
        if began==nil {began=now}
        samples += 1
        return samples>=5 && duration(at:now)>=10
    }
}
