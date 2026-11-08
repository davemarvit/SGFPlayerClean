import SwiftUI
import AppKit

/// Pure board transition inference, independent of camera, transport, and UI.
/// Captured groups may still be present, partly removed, or fully removed.
/// OGS remains responsible for history-dependent rules such as ko and superko.
enum PhysicalMoveInference {
    /// Camera grid -> the orientation shown to the player and used by OGS.
    static func displayedPoint(row: Int, col: Int, size: Int, quarterTurns: Int) -> Int {
        switch ((quarterTurns % 4)+4)%4 {
        case 1: return col*size + (size-1-row)
        case 2: return (size-1-row)*size + (size-1-col)
        case 3: return (size-1-col)*size + row
        default: return row*size + col
        }
    }
    static func candidate(board: [String], observed: [String], size: Int, color: String) -> Int? {
        guard [9,13,19].contains(size), board.count == size*size, observed.count == board.count,
              ["black","white"].contains(color),
              board.allSatisfy({["empty","black","white"].contains($0)}),
              observed.allSatisfy({["empty","black","white"].contains($0)}) else { return nil }
        let additions = board.indices.filter { board[$0] == "empty" && observed[$0] == color }
        guard additions.count == 1, let point = additions.first else { return nil }
        guard let result=position(after:point,board:board,size:size,color:color) else {return nil}
        let opponent=color == "black" ? "white":"black"
        let captured=Set(board.indices.filter{board[$0]==opponent && result[$0]=="empty"})
        for p in board.indices {
            if captured.contains(p) {
                guard observed[p] == "empty" || observed[p] == opponent else { return nil }
            } else if observed[p] != result[p] { return nil }
        }
        return point
    }
    static func position(after point:Int,board:[String],size:Int,color:String)->[String]? {
        guard [9,13,19].contains(size),board.count==size*size,board.indices.contains(point),
              board[point]=="empty",["black","white"].contains(color) else {return nil}
        let opponent = color == "black" ? "white" : "black"
        var result = board; result[point] = color
        func neighbors(_ p: Int) -> [Int] {
            var values = [Int]()
            if p%size > 0 { values.append(p-1) }
            if p%size+1 < size { values.append(p+1) }
            if p/size > 0 { values.append(p-size) }
            if p/size+1 < size { values.append(p+size) }
            return values
        }
        func group(_ start: Int, grid: [String]) -> (Set<Int>, Bool) {
            var visited: Set<Int> = [start], stack = [start], liberty = false
            while let p = stack.popLast() {
                for q in neighbors(p) {
                    if grid[q] == "empty" { liberty = true }
                    else if grid[q] == grid[start], visited.insert(q).inserted { stack.append(q) }
                }
            }
            return (visited, liberty)
        }
        var captured = Set<Int>()
        for p in neighbors(point) where result[p] == opponent {
            let (stones, liberty) = group(p, grid: result)
            if !liberty { captured.formUnion(stones) }
        }
        for p in captured { result[p] = "empty" }
        guard group(point, grid: result).1 else { return nil }
        return result
    }
}

/// Compact local history for diagnosing recognition versus dispatch delays.
/// No camera images, credentials, account IDs or game IDs are written here.
final class PhysicalOnlineDecisionLog {
    private let url: URL
    private let maximumBytes: Int
    private let queue = DispatchQueue(label:"PhysicalGo.online-decisions",qos:.utility)
    init(url: URL, maximumBytes: Int = 2_000_000) {
        self.url=url; self.maximumBytes=maximumBytes
    }
    func append(_ entry: [String:Any]) {
        queue.async { [self] in
            do {
                var data=try JSONSerialization.data(withJSONObject:entry,options:.sortedKeys);data.append(10)
                let fm=FileManager.default
                try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
                let size=(try? fm.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.intValue ?? 0
                if size>0 && size+data.count>maximumBytes {
                    let previous=url.deletingPathExtension().appendingPathExtension("previous.jsonl")
                    if fm.fileExists(atPath:previous.path) {try fm.removeItem(at:previous)}
                    try fm.moveItem(at:url,to:previous)
                }
                if !fm.fileExists(atPath:url.path) {try Data().write(to:url)}
                let handle=try FileHandle(forWritingTo:url)
                defer {try? handle.close()}
                try handle.seekToEnd();try handle.write(contentsOf:data)
            } catch { /* Diagnostics must never delay or prevent game play. */ }
        }
    }
    func flush() {queue.sync {}}
}

/// Differences are already in the displayed/server orientation.
struct PhysicalBoardMismatch: Equatable {
    let expected: [String]
    let observed: [String]
    var requiresSynchronization = false
    var remove: [Int] { expected.indices.filter { expected[$0] != observed[$0] && observed[$0] != "empty" } }
    var place: [Int] { expected.indices.filter { expected[$0] != observed[$0] && expected[$0] != "empty" } }
    var needsCorrection: Bool { !remove.isEmpty }
    var isReposition: Bool {
        remove.count == 1 && place.count == 1 && remove[0] != place[0] && observed[remove[0]] == expected[place[0]]
    }
    var title: String {
        if requiresSynchronization { return "Synchronize before playing" }
        if isReposition { return "Reposition the \(observed[remove[0]]) stone" }
        if remove.isEmpty { return place.count == 1 ? "Place the marked stone" : "Place the marked stones" }
        if place.isEmpty { return remove.count == 1 ? "Remove the marked stone" : "Remove the marked stones" }
        return "Correct the marked stones"
    }
    var instructions: String {
        if requiresSynchronization { return "Lift the marked stone until the boards match, then place it again." }
        if isReposition { return "Move the stone marked × to the blue ring." }
        if remove.isEmpty { return "Place stones at the blue rings to match the online board." }
        if place.isEmpty { return "Remove the stones marked × from your physical board." }
        return "Remove the stones marked ×, then place the required stones at the blue rings."
    }
}

/// Local, ephemeral bridge. OGS credentials remain in SGF Player.
@MainActor final class PhysicalOnlineBoard: ObservableObject {
    @Published var enabled = false { didSet {
        moveTiming?.close(reason:enabled ? "Connection restarted" : "Physical board disabled")
        reset(); status = "Waiting for SGF Player…"
    } }
    @Published private(set) var status = "Enable Use physical board in SGF Player’s active game."
    @Published private(set) var cameraStatus: String?
    @Published private(set) var placementIssue: PhysicalBoardMismatch?
    @Published private(set) var moveIssue: String?
    @Published private(set) var turnColor: Stone?
    @Published private(set) var isMyTurn = false
    @Published private(set) var cells = [String]()
    @Published private(set) var size = 19
    @Published private(set) var lastPoint: Int?
    let undo: PhysicalUndoController
    var moveInFlight: Bool { sent }
    private var lastRemoteMoveNumber: Int?
    private var remoteUndoSession = ""
    var stoneTrackingIdentity:String {identity.isEmpty ? "":synchronizationContext}
    private var identity = ""
    private var lastSession = ""
    private var lastMyTurn: Bool?
    // An established board match anchors the session, not just one position.
    // After anchoring, unchanged uncertain points retain their historical state.
    private var history=HistoricalMoveEvidence()
    private var submittedPoint:Int?
    private var rejectedPoint:Int?
    private var synchronized = false
    private var synchronizationContext = ""
    private var pending: Int?
    private var pendingClearTimes = [Double]()
    private var confirmationNote = ""
    private var pendingReadings = [String]()
    private var sent = false
    private var sentRequestID: String?
    private var sentAt: Double?
    private var rejected = false
    private var illegalCandidate: Int?
    private var illegalSince = 0.0
    private var illegalFrames = 0
    private var lastObservation = 0.0
    private var unclearSince: Double?
    private var clearSince: Double?
    private let directory: URL
    private let decisionLog: PhysicalOnlineDecisionLog?
    private let moveTiming:PhysicalMoveTiming?
    private var timingContext:PhysicalMoveTiming.Position?
    @Published private(set) var timingNotice:String?
    @Published private(set) var timingStatistics:String?
    @Published private(set) var timingError:String?
    var onEvidenceCapture:(([String:Any])->String?)? {
        didSet {moveTiming?.onEvidenceCapture=onEvidenceCapture}
    }
    var timingDirectory:URL {directory.appendingPathComponent("Move Timing")}
    func flushTiming() {moveTiming?.close(reason:"App closed");moveTiming?.flush()}
    private var tracePosition = ""
    private var mismatchCandidate: PhysicalBoardMismatch?
    private var mismatchSince = 0.0
    private var mismatchFrames = 0
    private var mismatchAnnounced = false
    private let announceCorrection: () -> Void
    private let announceOpponent: () -> Void
    init(directory: URL? = nil, decisionLog: PhysicalOnlineDecisionLog? = nil, moveTiming:PhysicalMoveTiming? = nil, announceOpponent: @escaping () -> Void = { NSSound(named:"Tink")?.play() },
         announceCorrection: @escaping () -> Void = {
             let sound=NSSound(named:"Pop"); sound?.volume=0.35; sound?.play()
         }) {
        self.announceCorrection = announceCorrection
        self.announceOpponent = announceOpponent
        self.directory = directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Physical Go/Online Bridge")
        self.undo = PhysicalUndoController(directory:self.directory)
        self.decisionLog = decisionLog ?? (directory == nil ? PhysicalOnlineDecisionLog(url:self.directory.appendingPathComponent("decisions.jsonl")) : nil)
        self.moveTiming=moveTiming ?? (directory == nil ? PhysicalMoveTiming(directory:self.directory.appendingPathComponent("Move Timing")) : nil)
        self.moveTiming?.onWriteError={ [weak self] error in self?.timingError="Move timing could not be saved: \(error)" }

    }
    private func reset(preservingSynchronization: Bool = false) {
        identity=""; resetPendingMove(); sent=false; lastObservation=0
        sentRequestID=nil;sentAt=nil;rejected=false;moveIssue=nil
        illegalCandidate=nil;illegalFrames=0
        if !preservingSynchronization { synchronized=false; synchronizationContext="";history=HistoricalMoveEvidence() }
        submittedPoint=nil;rejectedPoint=nil
        unclearSince=nil; clearSince=nil; cameraStatus=nil
        clearPlacementIssue(); turnColor=nil; isMyTurn=false
    }
    private func interruptMismatchEvidence() { mismatchCandidate=nil; mismatchFrames=0 }
    private func clearPlacementIssue() {
        interruptMismatchEvidence(); placementIssue=nil; mismatchAnnounced=false
    }
    private func updateMismatch(board: [String], readings: [String], now: Double) {
        let requiresSynchronization = !synchronized && isMyTurn &&
            PhysicalMoveInference.candidate(board:board,observed:readings,size:size,color:turnColor?.rawValue ?? "") != nil
        let issue=PhysicalBoardMismatch(expected:board,observed:readings,requiresSynchronization:requiresSynchronization)
        if mismatchCandidate != issue {
            mismatchCandidate=issue; mismatchSince=now; mismatchFrames=0
        }
        mismatchFrames += 1
        guard mismatchFrames >= 4, now-mismatchSince >= 0.7 else { return }
        placementIssue=issue
        if issue.needsCorrection && !mismatchAnnounced {
            mismatchAnnounced=true; announceCorrection()
        }
    }
    private func resetPendingMove() {
        pending=nil; pendingClearTimes=[]; pendingReadings=[]
    }
    func pauseForCorrection() {
        resetPendingMove(); interruptMismatchEvidence(); clearPlacementIssue()
        moveTiming?.wait("Manual correction",now:ProcessInfo.processInfo.systemUptime)
        illegalCandidate=nil;illegalFrames=0
        status="Checking the corrected board."
    }
    /// Keep a sliding window of fully clear witnesses, never inferred readings.
    /// Small unrelated uncertainty can pause evidence, but cannot supply evidence.
    private func expirePendingEvidence(now: Double) {
        pendingClearTimes.removeAll {now-$0>2.5}
        if pendingClearTimes.isEmpty {resetPendingMove()}
    }
    private func handleUnclear(_ readings: [String]?, board: [String], color: String, now: Double) {
        interruptMismatchEvidence()
        expirePendingEvidence(now:now)
        var retain=false
        confirmationNote="No clear candidate evidence"
        if let readings, let point=pending, synchronized, !sent, isMyTurn,
           pendingReadings.count == readings.count {
            let unknown=readings.indices.filter { readings[$0] == "uncertain" }
            if readings[point] != color {confirmationNote="New stone is not clearly recognized"}
            else if unknown.count>3 {confirmationNote="More than three uncertain intersections"}
            else {
                var completed=readings
                for p in unknown { completed[p]=pendingReadings[p] }
                retain=PhysicalMoveInference.candidate(board:board,observed:completed,size:size,color:color)==point
                confirmationNote=retain ? "Paused for unrelated uncertainty" : "Known readings contradict the candidate"
            }
        }
        if !retain {resetPendingMove()}
        // A corrected stone must stop showing a red correction even when a
        // different intersection is still unclear. Do not assume unknowns match.
        let knownPointsMatch=readings.map { values in
            values.indices.allSatisfy {values[$0] == "uncertain" || values[$0] == board[$0]}
        } ?? false
        if let readings, let issue=placementIssue, knownPointsMatch,
           (issue.remove+issue.place).allSatisfy({readings[$0] == board[$0]}) {
            clearPlacementIssue()
        }
        updateClarity(clear:false,now:now)
        if !synchronized && knownPointsMatch {
            status="Checking the remaining unclear intersections.";return
        }
        if synchronized, isMyTurn, !sent, let readings,
           readings.indices.filter({board[$0] == "empty" && readings[$0] == color}).count == 1 {
            status="Move recognized — checking the rest of the board.";return
        }
        status = sent ? "Move sent. Waiting for the server." : (retain ? "Stone settling…" : (synchronized
            ? (isMyTurn ? "Your turn." : "Waiting for your opponent.")
            : "Match your physical board to the board below."))
    }
    func recordCameraWait(_ reason: String, details:[String:Any]=[:]) {
        guard enabled else {return}
        moveTiming?.wait(reason,now:ProcessInfo.processInfo.systemUptime,details:details)
        timingNotice=moveTiming?.notice
        decisionLog?.append(["event":"camera wait","time":Date().timeIntervalSince1970,
            "uptime":ProcessInfo.processInfo.systemUptime,"reason":reason,"details":details])
    }
    private func recordDecision(_ observation: BoardObservation, now: Double, quarterTurns: Int,
                                previousPoint: Int?, interval: Double?) {
        if let timingContext {
            var values=Array(repeating:"uncertain",count:size*size),seen=Set<Int>()
            for r in observation.readings where (0..<size).contains(r.row) && (0..<size).contains(r.col) {
                let p=PhysicalMoveInference.displayedPoint(row:r.row,col:r.col,size:size,quarterTurns:quarterTurns)
                seen.insert(p);values[p]=r.occupancy.rawValue
            }
            let valid=observation.size==size && seen.count==size*size && observation.readings.count==size*size && !observation.lightingBlocked && observation.readings.allSatisfy{$0.confidence.isFinite}
            var evidence=[Int:PhysicalMoveTiming.Evidence]()
            if valid {
                let expected=(0..<size*size).map {raw in
                    Occupancy(rawValue:timingContext.board[PhysicalMoveInference.displayedPoint(row:raw/size,col:raw%size,size:size,quarterTurns:quarterTurns)])!
                }
                let assignment=observation.assignmentOffsets(confirmedBoard:expected)
                let placement=observation.placementOffsets
                for r in observation.readings {
                    let raw=r.row*size+r.col
                    let p=PhysicalMoveInference.displayedPoint(row:r.row,col:r.col,size:size,quarterTurns:quarterTurns)
                    evidence[p] = .init(confidence:r.confidence,assignmentOffset:assignment[raw],
                        placementOffset:placement[raw],manual:observation.manualPoints.contains(raw))
                }
            }
            moveTiming?.observe(timingContext,readings:valid ? values:nil,clearCandidate:pending,requestID:sentRequestID,
                issue:moveIssue,blocker:confirmationNote.isEmpty ? status:confirmationNote,now:now,
                evidence:evidence,clearWitnesses:pendingClearTimes.count,
                evidenceSpan:pendingClearTimes.first.map{now-$0} ?? 0)
        } else {moveTiming?.wait("No fresh connected game",now:now)}
        timingNotice=moveTiming?.notice
        if timingStatistics != moveTiming?.statisticsText {timingStatistics=moveTiming?.statisticsText}
        guard let decisionLog else {return}
        var entry:[String:Any]=["event":"observation","time":Date().timeIntervalSince1970,"uptime":now,
            "status":status,"confirmation":confirmationNote,"size":size,"quarterTurns":quarterTurns,
            "synchronized":synchronized,"myTurn":isMyTurn,"sent":sent,
            "lightingBlocked":observation.lightingBlocked,"clearWitnesses":pendingClearTimes.count,
            "candidate":pending.map{$0 as Any} ?? NSNull(),"previousCandidate":previousPoint.map{$0 as Any} ?? NSNull(),
            "cameraInterval":interval.map{$0 as Any} ?? NSNull(),
            "evidenceSpan":pendingClearTimes.first.map{now-$0} ?? 0]
        var unknown=[Int](),differences=[[String:Any]]()
        for r in observation.readings where (0..<size).contains(r.row) && (0..<size).contains(r.col) {
            let point=PhysicalMoveInference.displayedPoint(row:r.row,col:r.col,size:size,quarterTurns:quarterTurns)
            if r.occupancy == .uncertain {unknown.append(point)}
            else if cells.count==size*size && cells[point] != r.occupancy.rawValue {
                differences.append(["point":point,"observed":r.occupancy.rawValue,"expected":cells[point]])
            }
        }
        entry["uncertain"]=unknown;entry["differences"]=differences
        entry["manualPoints"]=observation.manualPoints.sorted()
        entry["trackedAssignments"]=Dictionary(uniqueKeysWithValues:observation.trackedAssignments.map{(String($0.key),$0.value)})
        entry["moveIssue"]=moveIssue.map{$0 as Any} ?? NSNull()
        // The private identity includes a token: never write it to disk.
        if tracePosition != identity {
            tracePosition=identity;entry["positionChanged"]=true;entry["board"]=cells
            entry["lastPoint"]=lastPoint.map{$0 as Any} ?? NSNull()
        }
        decisionLog.append(entry)
    }
    /// Presentation hysteresis only. Dispatch eligibility is checked separately;
    /// warning visibility never determines whether a move can be sent.
    private func updateClarity(clear: Bool, now: Double) {
        if clear {
            if clearSince == nil { clearSince=now }
            if now-clearSince! >= 0.6 { unclearSince=nil; cameraStatus=nil }
        } else {
            clearSince=nil
            if unclearSince == nil { unclearSince=now }
            if now-unclearSince! >= 1 { cameraStatus="Waiting for a clear view." }
        }
    }
    func consume(_ observation: BoardObservation, now: Double = ProcessInfo.processInfo.systemUptime, quarterTurns: Int = 0,
                 corrections: ManualBoardCorrections? = nil) {
        guard enabled else { return }
        undo.refresh()
        var observation=observation
        timingContext=nil
        let previousPoint=pending, interval=lastObservation>0 ? now-lastObservation : nil
        confirmationNote=""
        defer {recordDecision(observation,now:now,quarterTurns:quarterTurns,previousPoint:previousPoint,interval:interval)}
        do {
            let data = try Data(contentsOf:directory.appendingPathComponent("state.json"))
            guard let state = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let stamp = state["time"] as? Double, abs(Date().timeIntervalSince1970-stamp)<2,
                  let token=state["token"] as? String, let game=state["game"] as? Int,
                  let version=state["version"] as? Int, let n=state["size"] as? Int,
                  [9,13,19].contains(n), let board=state["cells"] as? [String], board.count==n*n,
                  let color=state["color"] as? String, ["black","white"].contains(color),
                  let myTurn=state["myTurn"] as? Bool,
                  board.allSatisfy({ ["empty","black","white"].contains($0) }) else {
                reset(); status="Waiting for a connected live game in SGF Player."; return
            }
            if undo.awaitingCommand || undo.state?.pending == true {
                resetPendingMove();status="Undo is being reviewed. Leave the stones in place until OGS updates the board."
                return
            }
            guard state["ready"] as? Bool == true else {
                reset();status="Waiting for a connected live game in SGF Player.";return
            }
            if let number=undo.state?.moveNumber {
                let session="\(token)/\(game)"
                if session != remoteUndoSession {lastRemoteMoveNumber=nil;remoteUndoSession=session}
                if let previous=lastRemoteMoveNumber,number<previous {
                    // An accepted takeback must be matched physically before
                    // the old stone can be mistaken for a fresh legal move.
                    synchronized=false;synchronizationContext="";history=HistoricalMoveEvidence()
                }
                lastRemoteMoveNumber=number
            }
            // Include the position itself for compatibility with older publishers
            // whose OGS state_version can remain zero throughout a live game.
            let nextIdentity="\(token)/\(game)/\(version)/\(((quarterTurns % 4)+4)%4)/\(n)/\(color)/\(state["myTurn"] as? Bool == true)/\(state["lastX"] as? Int ?? -1)/\(state["lastY"] as? Int ?? -1)/\(board.joined(separator:","))"
            // Rebind every valid frame, including after an explicit local reset.
            // A move/version change within this context must preserve user facts.
            corrections?.bind(context:"\(token)/\(game)/\(n)/\(color)/\(((quarterTurns % 4)+4)%4)",size:n)
            if nextIdentity != identity {
                let session="\(token)/\(game)"
                let context="\(session)/\(n)/\(color)/\(((quarterTurns % 4)+4)%4)"
                let preserveMatch=synchronized && synchronizationContext == context
                // A revision-only update is not acknowledgment of a sent move.
                // Keep the one-shot dispatch guard until the position/turn changes.
                let preserveSent=sent && preserveMatch && cells == board && lastMyTurn == myTurn
                let oldRequest=sentRequestID,oldSentAt=sentAt,oldIssue=moveIssue
                var nextPoint: Int?
                if let x=state["lastX"] as? Int, let y=state["lastY"] as? Int,
                   (0..<n).contains(x), (0..<n).contains(y) { nextPoint=y*n+x }
                // Turn and board updates can arrive in separate snapshots. Do
                // not announce a new turn while the last move is still our own.
                let lastMoveIsOpponent = nextPoint.map { board[$0] != "empty" && board[$0] != color } ?? true
                let opponentMoved = !identity.isEmpty && lastSession == session && myTurn && lastMoveIsOpponent &&
                    (cells != board || lastPoint != nextPoint || lastMyTurn == false)
                let oldSubmitted=submittedPoint
                if preserveMatch {history.advance(board,submitted:oldSubmitted)}
                reset(preservingSynchronization:preserveMatch)
                if preserveSent {submittedPoint=oldSubmitted}
                synchronizationContext=context; sent=preserveSent
                if preserveSent {sentRequestID=oldRequest;sentAt=oldSentAt;moveIssue=oldIssue}
                identity=nextIdentity; size=n; cells=board; lastPoint=nextPoint
                lastSession=session; lastMyTurn=myTurn
                if opponentMoved { announceOpponent() }
            }
            timingContext = .init(game:game,revision:version,size:n,board:board,color:color,myTurn:myTurn,lastPoint:lastPoint)
            // The live turn is authoritative even while the camera is unclear
            // or the physical stones still need to be matched to the server.
            let ownColor=Stone(rawValue:color)!
            let nextColor=myTurn ? ownColor : ownColor.opponent
            if turnColor != nextColor { turnColor=nextColor }
            if isMyTurn != myTurn { isMyTurn=myTurn }
            if sent,let feedback=state["moveFeedback"] as? [String:Any],
               let requestID=sentRequestID,feedback["id"] as? String == requestID,
               feedback["version"] as? Int == version,feedback["status"] as? String == "rejected" {
                rejectedPoint=submittedPoint;sent=false;rejected=true;resetPendingMove()
                moveIssue=feedback["message"] as? String ?? "The move was rejected. Restore the online position before continuing."
                announceCorrection()
            }
            if sent,let sentAt,now-sentAt>=8,moveIssue == nil {
                moveIssue="OGS has not confirmed this move. Check SGF Player before continuing. The move will not be retried automatically."
                announceCorrection()
            }
            guard observation.size==n, !observation.lightingBlocked,
                  observation.readings.count==n*n else {
                resetPendingMove(); interruptMismatchEvidence()
                if observation.size != n { synchronized=false }
                status="Check camera and board size."; return
            }
            // A delayed or obscured frame cancels settlement, not the previously
            // established board match. The new stone still needs fresh local evidence.
            if lastObservation>0 && now-lastObservation>1 { resetPendingMove(); interruptMismatchEvidence(); confirmationNote="Camera observation gap exceeded one second" }
            lastObservation=now
            if corrections?.isEditing == true {
                resetPendingMove(); interruptMismatchEvidence(); clearPlacementIssue()
                status="Correcting the physical board. Moves paused."
                return
            }
            if let corrections { observation=corrections.apply(to:observation) }
            var readings=Array(repeating:"uncertain",count:n*n)
            var confidences=Array(repeating:0.0,count:n*n)
            var ambiguous=Set<Int>()
            let rawExpected=(0..<n*n).map {raw in
                Occupancy(rawValue:board[PhysicalMoveInference.displayedPoint(row:raw/n,col:raw%n,size:n,quarterTurns:quarterTurns)])!
            }
            let rawAmbiguous=Set(observation.assignmentOffsets(confirmedBoard:rawExpected).filter{$0.value>=0.30}.map(\.key))
            var seen=Set<Int>()
            for reading in observation.readings {
                guard (0..<n).contains(reading.row), (0..<n).contains(reading.col), reading.confidence.isFinite else {
                    handleUnclear(nil,board:board,color:color,now:now); return
                }
                let point=PhysicalMoveInference.displayedPoint(row:reading.row,col:reading.col,size:n,quarterTurns:quarterTurns)
                guard seen.insert(point).inserted else { resetPendingMove(); interruptMismatchEvidence(); return }
                readings[point]=reading.occupancy.rawValue
                confidences[point]=reading.confidence
                if rawAmbiguous.contains(reading.row*n+reading.col) {ambiguous.insert(point)}
            }
            guard seen.count==n*n else {resetPendingMove();return}
            // A known prohibited stone can be explained even when a different
            // intersection is unclear. Unknowns below are used only to draw
            // restoration markers, never as confirmation or move evidence.
            let illegal=state["illegalMoves"] as? [String:String] ?? [:]
            let prohibited=isMyTurn ? readings.indices.first {board[$0]=="empty" && readings[$0]==color && illegal[String($0)] != nil} : nil
            if let point=prohibited {
                resetPendingMove();rejectedPoint=point
                if illegalCandidate != point {illegalCandidate=point;illegalSince=now;illegalFrames=0}
                illegalFrames += 1
                if illegalFrames>=4,now-illegalSince>=0.7 {
                    if moveIssue != illegal[String(point)] {announceCorrection()}
                    moveIssue=illegal[String(point)];rejected=true
                    placementIssue=PhysicalBoardMismatch(expected:board,observed:readings.indices.map{readings[$0]=="uncertain" ? board[$0] : readings[$0]})
                }
                if let moveIssue {status=moveIssue}
                return
            }
            illegalCandidate=nil;illegalFrames=0
            if rejected {
                if readings==board || (rejectedPoint.map{readings[$0]==board[$0] && confidences[$0]>=0.8} ?? false) {
                    rejectedPoint=nil
                    rejected=false;moveIssue=nil;sent=false;sentRequestID=nil;sentAt=nil;clearPlacementIssue()
                } else {
                    updateMismatch(board:board,readings:readings.indices.map{readings[$0]=="uncertain" ? board[$0] : readings[$0]},now:now)
                    status=moveIssue ?? "Restore the online position before continuing."
                    return
                }
            }
            if sent,let moveIssue {status=moveIssue;return}
            if !synchronized {
                if readings.contains("uncertain") {
                    handleUnclear(readings,board:board,color:color,now:now);return
                }
                if readings==board {
                    history.anchor(board);synchronized=true;clearPlacementIssue();resetPendingMove()
                    updateClarity(clear:true,now:now)
                    status=isMyTurn ? "Your turn.":"Waiting for your opponent.";return
                }
                resetPendingMove();updateMismatch(board:board,readings:readings,now:now)
                status="Match your physical board to the board below.";return
            }
            if sent {clearPlacementIssue();status="Move sent. Waiting for the server.";return}
            let evidence=history.observe(readings,confidence:confidences,size:n,color:color,myTurn:isMyTurn,ambiguous:ambiguous)
            let point:Int
            switch evidence {
            case .candidate(let candidate):
                point=candidate;cameraStatus=nil
            case .idle:
                resetPendingMove();clearPlacementIssue();cameraStatus=nil
                status=isMyTurn ? "Your turn.":"Waiting for your opponent."
                confirmationNote="No new move; unchanged uncertain points retain their history";return
            case .placementNeeded,.contradiction:
                resetPendingMove();updateMismatch(board:board,readings:history.comparison,now:now)
                status=evidence == .placementNeeded ? "Place your opponent’s marked stone.":"Check the marked board changes."
                confirmationNote="Positive board change or unplaced opponent move";return
            case .ambiguous:
                resetPendingMove();updateClarity(clear:false,now:now);status="Checking the new stone’s position."
                confirmationNote="Competing, weak, illegal or unverified new-stone evidence";return
            case .obscured:
                resetPendingMove();updateClarity(clear:false,now:now)
                status="Waiting for the board to be visible."
                confirmationNote="Broad obstruction; no move evidence collected";return
            }
            clearPlacementIssue()
            expirePendingEvidence(now:now)
            if pending != point {resetPendingMove();pending=point}
            pendingClearTimes.append(now); pendingReadings=readings
            confirmationNote="Collecting local new-stone evidence"
            guard pendingClearTimes.count>=4, now-pendingClearTimes[0]>=1 else { status="Stone settling…"; return }
            let requestID=UUID().uuidString
            let request:[String:Any] = ["id":requestID,"token":token,"game":game,"version":version,"time":Date().timeIntervalSince1970,"x":point%n,"y":point/n]
            try JSONSerialization.data(withJSONObject:request).write(to:directory.appendingPathComponent("move.json"),options:.atomic)
            history.didSubmit(point,color:color)
            sent=true;submittedPoint=point;sentRequestID=requestID;sentAt=now; confirmationNote="Move request written"; status="Move sent. Waiting for the server."
        } catch { reset(); status="Open SGF Player and enable Use physical board in your game." }
    }
}

struct PhysicalOnlineBoardView: View {
    @ObservedObject var bridge: PhysicalOnlineBoard
    private var starPoints: [BoardPosition] {
        if bridge.size == 19 {
            return [3,9,15].flatMap { row in [3,9,15].map { BoardPosition(row,$0) } }
        }
        guard [9,13].contains(bridge.size) else { return [] }
        let near = bridge.size == 9 ? 2 : 3
        let far = bridge.size-1-near
        return [BoardPosition(near,near),BoardPosition(near,far),
                BoardPosition(far,near),BoardPosition(far,far),
                BoardPosition(bridge.size/2,bridge.size/2)]
    }
    var body: some View {
        GroupBox {
            VStack(alignment:.leading,spacing:10) {
                Text("Online board").font(.headline)
                if bridge.enabled {PhysicalUndoView(controller:bridge.undo,moveInFlight:bridge.moveInFlight)}
                if bridge.enabled { OnlineTurnIndicator(bridge:bridge,textScale:1) }
                if let issue=bridge.moveIssue {
                    Label(issue,systemImage:"exclamationmark.triangle.fill")
                        .font(.title3.weight(.bold)).foregroundStyle(.red)
                        .frame(maxWidth:.infinity,alignment:.leading).padding(12)
                        .background(Color.red.opacity(0.12),in:RoundedRectangle(cornerRadius:8))
                }
                if let issue=bridge.placementIssue {
                    VStack(alignment:.leading,spacing:6) {
                        Label(issue.title,systemImage:issue.needsCorrection ? "exclamationmark.triangle.fill" : "hand.point.down.fill")
                            .font(.title3.weight(.bold))
                        Text(issue.instructions).font(.callout)
                    }
                    .frame(maxWidth:.infinity,alignment:.leading).padding(12)
                    .background((issue.needsCorrection ? Color.red : Color.blue).opacity(0.14),in:RoundedRectangle(cornerRadius:8))
                    .overlay(RoundedRectangle(cornerRadius:8).stroke(issue.needsCorrection ? Color.red : Color.blue,lineWidth:2))
                    .accessibilityElement(children:.combine)
                } else {
                    Text(bridge.status).font(.callout)
                }
                if bridge.enabled {
                    // Reserve the line so the board does not move when it appears.
                    Text(bridge.cameraStatus ?? " ").font(.caption).foregroundStyle(.secondary)
                }
                if bridge.enabled, !bridge.cells.isEmpty {
                    Canvas { context, extent in
                        let step=min(extent.width,extent.height)/CGFloat(bridge.size)
                        let inset=step/2
                        var lines=Path()
                        for i in 0..<bridge.size {
                            let p=inset+CGFloat(i)*step
                            lines.move(to:CGPoint(x:inset,y:p)); lines.addLine(to:CGPoint(x:inset+CGFloat(bridge.size-1)*step,y:p))
                            lines.move(to:CGPoint(x:p,y:inset)); lines.addLine(to:CGPoint(x:p,y:inset+CGFloat(bridge.size-1)*step))
                        }
                        context.stroke(lines,with:.color(.black.opacity(0.6)),lineWidth:1)
                        let starRadius = min(2.5,max(1.6,step*0.13))
                        for point in starPoints {
                            let center=CGPoint(x:inset+CGFloat(point.col)*step,y:inset+CGFloat(point.row)*step)
                            let dot=CGRect(x:center.x-starRadius,y:center.y-starRadius,width:starRadius*2,height:starRadius*2)
                            context.fill(Path(ellipseIn:dot),with:.color(.black.opacity(0.8)))
                        }
                        for i in bridge.cells.indices where bridge.cells[i] != "empty" {
                            let center=CGPoint(x:inset+CGFloat(i%bridge.size)*step,y:inset+CGFloat(i/bridge.size)*step)
                            let rect=CGRect(x:center.x-step*0.46,y:center.y-step*0.46,width:step*0.92,height:step*0.92)
                            context.fill(Path(ellipseIn:rect),with:.color(bridge.cells[i]=="black" ? .black : .white))
                            if bridge.lastPoint==i {
                                context.stroke(Path(ellipseIn:rect.insetBy(dx:step*0.25,dy:step*0.25)),with:.color(.red),lineWidth:2)
                            }
                        }
                        if let issue=bridge.placementIssue {
                            for i in issue.remove {
                                let center=CGPoint(x:inset+CGFloat(i%bridge.size)*step,y:inset+CGFloat(i/bridge.size)*step)
                                let rect=CGRect(x:center.x-step*0.44,y:center.y-step*0.44,width:step*0.88,height:step*0.88)
                                if bridge.cells[i] == "empty" {
                                    context.fill(Path(ellipseIn:rect),with:.color((issue.observed[i] == "black" ? Color.black : Color.white).opacity(0.65)))
                                }
                                var cross=Path()
                                let arm=step*0.27
                                cross.move(to:CGPoint(x:center.x-arm,y:center.y-arm));cross.addLine(to:CGPoint(x:center.x+arm,y:center.y+arm))
                                cross.move(to:CGPoint(x:center.x+arm,y:center.y-arm));cross.addLine(to:CGPoint(x:center.x-arm,y:center.y+arm))
                                context.stroke(cross,with:.color(.white),lineWidth:5)
                                context.stroke(cross,with:.color(.red),lineWidth:2.5)
                            }
                            for i in issue.place {
                                let center=CGPoint(x:inset+CGFloat(i%bridge.size)*step,y:inset+CGFloat(i/bridge.size)*step)
                                let ring=Path(ellipseIn:CGRect(x:center.x-step*0.47,y:center.y-step*0.47,width:step*0.94,height:step*0.94))
                                context.stroke(ring,with:.color(.white),lineWidth:5)
                                context.stroke(ring,with:.color(.blue),style:StrokeStyle(lineWidth:2.5,dash:[4,2]))
                            }
                        }
                    }.aspectRatio(1,contentMode:.fit).background(Color(red:0.78,green:0.60,blue:0.34))
                        .overlay(Rectangle().stroke(bridge.placementIssue?.needsCorrection == true ? Color.red : Color.clear,lineWidth:3))
                    Text("Place the marked stone and remove captures to match this board. Pass and scoring remain in SGF Player.").font(.caption)
                }
            }
        }
    }
}


struct OnlineTurnIndicator: View {
    @ObservedObject var bridge: PhysicalOnlineBoard
    var textScale: Double = 1
    var body: some View {
        HStack(spacing:12) {
            if let color=bridge.turnColor {
                Circle().fill(color == .black ? Color.black : Color.white)
                    .overlay(Circle().stroke(Color.gray,lineWidth:1.5))
                    .frame(width:40*textScale,height:40*textScale).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:3) {
                    Text("\(color.rawValue.capitalized) to play")
                        .font(.system(size:24*textScale,weight:.bold))
                    Text(bridge.isMyTurn ? "Your turn" : "Opponent’s turn")
                        .font(.system(size:15*textScale,weight:.semibold))
                }
            } else {
                Label("Waiting for live game",systemImage:"network")
                    .font(.system(size:21*textScale,weight:.bold))
            }
            Spacer(minLength:0)
        }
        .frame(maxWidth:.infinity,alignment:.leading).padding(12)
        .background(Color.blue.opacity(0.1),in:RoundedRectangle(cornerRadius:10))
        .accessibilityElement(children:.combine)
    }
}
