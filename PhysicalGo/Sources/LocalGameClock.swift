import Foundation
import Combine

@MainActor final class LocalGameClock:ObservableObject {
    struct Move:Codable {
        var number:Int
        var black:Bool
        var before:LocalClockEngine
        var after:LocalClockEngine
        var estimate:ClockPressEstimate?=nil
        /// Physical identity evidence, independent of the eventual SGF point.
        var observedLocations:[Int]?=nil
        /// Agreed balances cover this turn; no camera timestamp or increment was invented.
        var reviewed:Bool?=nil
    }
    struct AutomaticPause:Codable,Equatable {
        let reason:String
        let recordedAt:Date
    }
    private struct Saved:Codable {
        var version=1
        var signature:String
        var engine:LocalClockEngine
        var moves:[Move]
        var baseMove:Int
        var needsCorrection:Bool
        var liveEvents:[LivePress]?
        var liveReviewActive:Bool?
        var awaitingTurn:Bool?
        var timingNote:String?
        var automaticPause:AutomaticPause?
        var resumeAnnouncement:String?
        var capturePosition:[Occupancy]?
        var pressEvidence:[PressEvidence]?=nil
        var provisionalMoves:[Move]?=nil
        var provisionalCaptureStart:ClockPressEstimate?=nil
        var reviewedMissingProvisional:[Int]?=nil
    }
    struct PressEvidence:Codable {let number:Int;let estimate:ClockPressEstimate?;var applied:Bool}
    private(set) var pressEvidence=[PressEvidence]()
    var latestPressEstimate:ClockPressEstimate? {provisionalMoves.last?.estimate ?? moves.last?.estimate}
    struct LivePress:Codable {
        let id:UUID
        let black:Bool
        let before:LocalClockEngine
        let after:LocalClockEngine
        var estimate:ClockPressEstimate?=nil
    }
    @Published private(set) var engine=LocalClockEngine()
    @Published private(set) var notice="Clock starts when the board is ready."
    @Published private(set) var needsCorrection=false
    @Published private(set) var liveReviewActive=false
    @Published private(set) var awaitingTurn=false
    @Published private(set) var timingNote:String?
    private(set) var liveEvents:[LivePress]=[]
    @Published var pauseOnInterruption=true
    @Published var sounds=LocalClockSounds() {didSet {audio.stop(reason:"sound settings changed")}}
    @Published private(set) var saveError:String?
    var audible=true
    var onTimeout:(()->Void)?
    var onByoyomiPeriodChange:((ByoyomiPeriodChange)->Void)?
    private var lastPeriodNotices=[String]()
    private func reportPeriodChanges(from previous:LocalClockEngine,at now:Double,cause:String,press:ClockPressEstimate?=nil) {
        guard let onByoyomiPeriodChange else {return}
        for change in ByoyomiPeriodChange.changes(from:previous,to:engine,at:now,cause:cause,press:press) {
            // Nested pause/recovery calls can report the same transition.
            let key="\(now):\(change.black):\(change.before):\(change.after)"
            guard !lastPeriodNotices.contains(key) else {continue}
            lastPeriodNotices.append(key);lastPeriodNotices=Array(lastPeriodNotices.suffix(16))
            onByoyomiPeriodChange(change)
        }
    }
    @Published private(set) var automaticPause:AutomaticPause?
    var onAutomaticPause:((AutomaticPause)->Void)?
    var onAutomaticPauseCleared:(()->Void)?
    var onResumeAnnouncement:((String)->Void)?
    private(set) var pendingResumeAnnouncement:String?
    private let audio=LocalClockAudio()
    let storageWriter: RecordingStorage
    init(storageWriter: RecordingStorage = RecordingStorage()) {
        self.storageWriter=storageWriter
        storageWriter.onFailure = { [weak self] failure in
            guard let self else {return}
            self.saveError=failure.message
            if self.running {self.pause("Saving needs attention · clocks paused")}
        }
    }
    func flushStorage() throws { try storageWriter.flush() }
    var onSpeechEvent:SpeechEventHandler? {didSet {audio.onSpeechEvent=onSpeechEvent}}
    private var timer:DispatchSourceTimer?
    private var manuallyPaused=false
    @Published private(set) var automaticCapturePaused=false
    private(set) var automaticCapturePosition:[Occupancy]?
    private(set) var provisionalCaptureStart:ClockPressEstimate?
    var provisionalCapturePaused:Bool {automaticCapturePaused && provisionalCaptureStart != nil}
    private(set) var moves=[Move]()
    @Published private(set) var provisionalMoves=[Move]()
    /// Explicitly agreed totals may supersede orphaned presses, but only after
    /// the recorder positively verifies the saved board in fresh clear frames.
    private var reviewedMissingProvisional:[Int]?
    var canResolveMissingProvisional:Bool {
        !running && !requiresReview && !provisionalMoves.isEmpty &&
            reviewedMissingProvisional == provisionalMoves.map(\.number)
    }
    var lastTimedMove:Int {max(baseMove,moves.last?.number ?? 0,provisionalMoves.last?.number ?? 0)}
    var provisionalNextPlayer:Stone? {provisionalMoves.last.map{$0.black ? .white:.black}}
    private(set) var baseMove=0
    private var file:URL?
    private var signature=""
    private var lastSaved=0.0
    // Retain the turn's starting balances across automatic holds. Replay skips
    // their stopped intervals; a move inside a hold cannot establish thinking time.
    private var turnBaseline:LocalClockEngine?
    private struct TimingHold {let start:Double;var end:Double?}
    private var timingHolds=[TimingHold]()
    private func discardTimingBaseline() {turnBaseline=nil;timingHolds=[]}
    private func advanceAccounting(_ value:inout LocalClockEngine,to now:Double,beforePress:Bool=false) {
        for hold in timingHolds {
            guard let anchor=value.anchor else {return}
            if let end=hold.end,end<=anchor {continue}
            // A press exactly at the stop boundary occurs before suspension;
            // retain its running anchor, then apply the hold after the press.
            if hold.start>now || (beforePress && hold.start==now) {break}
            value.pause(at:max(anchor,hold.start))
            guard let end=hold.end,end<=now else {return}
            value.resume(at:end)
        }
        value.advance(to:now)
    }
    private func usablePress(_ time:Double,estimate:ClockPressEstimate?,black:Bool,now:Double)->Bool {
        guard !manuallyPaused,let baseline=turnBaseline,let start=baseline.anchor,
              time.isFinite,now.isFinite,time>=start,time<=now,baseline.blackToPlay==black else {return false}
        if let estimate,(!estimate.valid || abs(estimate.time-time)>1e-6) {return false}
        let lower=max(start,estimate?.earliestPlausibleTime ?? time)
        let upper=min(now,estimate?.latestPlausibleTime ?? time)
        for hold in timingHolds {
            if upper>hold.start && lower<(hold.end ?? .infinity) {return false}
            // Backdating across a hold requires an actual measured press, not
            // merely the first candidate that eventually became a saved move.
            if time<=hold.start && (estimate == nil || estimate?.method == .candidate) {return false}
        }
        return true
    }
    private func keepBaseline(_ value:LocalClockEngine) {
        turnBaseline=value.running ? value:nil
        if let anchor=value.anchor {timingHolds.removeAll{$0.end.map{$0<=anchor} ?? false}}
    }
    /// A fresh possible press prevents the timer racing visual confirmation.
    /// It cannot award an increment or decide a move; ambiguous expiry is reviewed.
    var pendingTurnEvidence:ClockPressEstimate?
    /// Start of an observed interval containing unaccounted turns, not a press.
    var pendingUnaccountedInterval:Double?
    // Enabled by real camera observations, not by stand-alone/manual clocks.
    private var lastObservationAt:Double?
    private(set) var observationGapHeld=false
    func noteCameraObservation(at stamp:Double,now:Double) {
        guard stamp.isFinite,now.isFinite,stamp<=now,now-stamp<1.5,
              lastObservationAt.map({stamp>$0}) ?? true else {return}
        _=protectObservationGap(at:now)
        lastObservationAt=stamp
    }
    func takeObservationGapHold()->Bool {
        let held=observationGapHeld;observationGapHeld=false;return held
    }
    /// Stop at the last verified observation, never charge an unseen interval.
    /// The timer also calls this, so callback ordering cannot decide a timeout.
    @discardableResult private func protectObservationGap(at now:Double,interruption:String?=nil)->Bool {
        guard pauseOnInterruption,running,let last=lastObservationAt,
              interruption != nil ? now>last:now-last>1.5,
              let baseline=turnBaseline,let start=baseline.anchor else {return false}
        let stopAt=max(start,min(last,pendingTurnEvidence?.earliestPlausibleTime ?? last))
        engine=baseline
        pause("Clock paused · "+(interruption ?? "Board processing fell behind. Checking a fresh view before continuing."),at:stopAt,manual:false)
        observationGapHeld=true
        return true
    }
    deinit {timer?.cancel()}
    var enabled:Bool {engine.enabled}
    var running:Bool {engine.running}
    // Deferred live history has its own next-player picker. A stale turn gate
    // outside that workflow needs clock review instead of endless verification.
    var requiresReview:Bool {needsCorrection || (awaitingTurn && !liveReviewActive) || engine.expiredBlack != nil}
    func configure(_ settings:LocalClockSettings,blackToPlay:Bool,baseMove:Int=0) {
        guard settings.validationError==nil else {return}
        timer?.cancel();timer=nil;audio.stop(reason:"clock configured")
        audio.resetAnnouncements()
        engine=LocalClockEngine(settings:settings,blackToPlay:blackToPlay);moves=[];self.baseMove=baseMove
        automaticCapturePaused=false;automaticCapturePosition=nil;provisionalCaptureStart=nil
        needsCorrection=false;manuallyPaused=false;notice="Clock starts when the board is ready."
        liveReviewActive=false;awaitingTurn=false;timingNote=nil;liveEvents=[]
        pendingResumeAnnouncement=nil;pressEvidence=[];provisionalMoves=[];lastPeriodNotices=[];reviewedMissingProvisional=nil
        clearAutomaticPause()
        file=nil;signature="";saveError=nil;discardTimingBaseline();pendingTurnEvidence=nil
        lastObservationAt=nil;observationGapHeld=false
    }
    func bind(to sgf:URL?,signature:String) {
        file=sgf?.deletingPathExtension().appendingPathExtension("clock.json");self.signature=signature
        save()
    }
    func ready(at now:Double) {
        guard storageWriter.error==nil,enabled,!running,!automaticCapturePaused,!manuallyPaused,!needsCorrection,!awaitingTurn,engine.expiredBlack==nil else {return}
        pendingTurnEvidence=nil
        if let lastObservationAt {self.lastObservationAt=max(lastObservationAt,now)}
        observationGapHeld=false
        if canResolveMissingProvisional,let next=provisionalNextPlayer {
            // Verification found the retained stones after all. Their turns are
            // covered by the approved totals; never press or award them again.
            engine.blackToPlay=next == .black
            for index in provisionalMoves.indices {provisionalMoves[index].reviewed=true}
        }
        reviewedMissingProvisional=nil
        if let last=timingHolds.indices.last,timingHolds[last].end==nil {timingHolds[last].end=max(timingHolds[last].start,now)}
        engine.resume(at:now);clearAutomaticPause()
        if turnBaseline==nil {turnBaseline=engine}
        notice="\(engine.blackToPlay ? "Black":"White") to play"
        let announcement=pendingResumeAnnouncement;pendingResumeAnnouncement=nil
        if announcement == nil && audible {audio.beganTurn(engine,settings:sounds)}
        armTimer();save()
        if let announcement {onResumeAnnouncement?("\(announcement) Clocks resumed. \(engine.blackToPlay ? "Black":"White") to play.")}
    }
    // A displayed timeout can precede delayed recognition. Retained accounting
    // must prove the capture started in a running segment before expiry.
    var canBeginAutomaticCapture:Bool {
        enabled && !automaticCapturePaused && automaticPause==nil && !manuallyPaused && !needsCorrection && !awaitingTurn && turnBaseline?.running == true
    }
    /// Rewind this retained turn, excluding holds; removal time is free to both sides.
    @discardableResult func beginAutomaticCapture(at observed:Double,now:Double,position:[Occupancy]?=nil,provisional:Bool=false)->Bool {
        let diagnosticPrevious=engine
        defer {reportPeriodChanges(from:diagnosticPrevious,at:now,cause:"capture pause")}
        guard canBeginAutomaticCapture,
              let baseline=turnBaseline,let start=baseline.anchor,observed.isFinite,
              observed>=start,observed<=now,usablePress(observed,estimate:.init(time:observed,method:.clearFrame),black:baseline.blackToPlay,now:now) else {return false}
        var paused=baseline;advanceAccounting(&paused,to:observed);paused.pause(at:observed)
        guard paused.expiredBlack==nil else {return false}
        engine=paused
        automaticCapturePaused=true;automaticCapturePosition=position;provisionalCaptureStart=provisional ? .init(time:observed,method:.clearFrame):nil;discardTimingBaseline()
        timer?.cancel();timer=nil;audio.stop(reason:"Removing captured stones")
        notice="Both clocks paused while captured stones are removed.";save()
        return true
    }
    func finishAutomaticCapture(at cleared:Double,now:Double) {
        guard automaticCapturePaused else {return}
        automaticCapturePaused=false;automaticCapturePosition=nil;provisionalCaptureStart=nil
        queueResumeAnnouncement("Capture complete.")
        ready(at:cleared);tick(at:now)
    }
    func releaseAutomaticCapture() {
        automaticCapturePaused=false;automaticCapturePosition=nil;provisionalCaptureStart=nil;save()
    }
    func abandonAutomaticCapture(blackToPlay:Bool,at now:Double) {
        automaticCapturePaused=false;automaticCapturePosition=nil;provisionalCaptureStart=nil
        recover(toBlack:blackToPlay,reason:"The expected capture was not completed. Check both clock times before resuming.",at:now)
    }
    func queueResumeAnnouncement(_ message:String) {
        guard enabled,!running else {return}
        pendingResumeAnnouncement=message;save()
    }
    func requestResume() {
        guard !requiresReview else {return}
        manuallyPaused=false
        if enabled,!running {notice="Checking board · clocks stopped"}
    }
    func resume(at now:Double=ProcessInfo.processInfo.systemUptime) {
        guard !needsCorrection else {return}
        manuallyPaused=false;ready(at:now)
    }
    func pause(_ reason:String="Clock paused",at now:Double=ProcessInfo.processInfo.systemUptime,manual:Bool=true) {
        let diagnosticPrevious=engine
        defer {reportPeriodChanges(from:diagnosticPrevious,at:now,cause:"pause")}
        guard enabled else {return}
        pendingTurnEvidence=nil;pendingUnaccountedInterval=nil
        let wasRunning=running
        advanceAccounting(&engine,to:now);engine.pause(at:now)
        if manual {discardTimingBaseline()}
        else if wasRunning,turnBaseline != nil {timingHolds.append(.init(start:now))}
        // Later camera interruptions must not revoke an explicit user pause.
        if manual {manuallyPaused=true} else if wasRunning {manuallyPaused=false}
        let beganAutomaticPause = wasRunning && !manual && automaticPause==nil
        if beganAutomaticPause {
            let prefix="Clock paused · "
            automaticPause=AutomaticPause(reason:reason.hasPrefix(prefix) ? String(reason.dropFirst(prefix.count)):reason,recordedAt:Date())
        }
        notice=engine.expiredBlack.map {"\($0 ? "Black":"White") time expired. Review and enter the agreed result in Info."} ?? reason
        audio.stop(reason:reason);timer?.cancel();timer=nil;save()
        if beganAutomaticPause,let automaticPause {onAutomaticPause?(automaticPause)}
    }
    func interrupt(_ reason:String,at now:Double=ProcessInfo.processInfo.systemUptime) {
        if awaitingTurn {return}
        if protectObservationGap(at:now,interruption:reason) {return}
        if pauseOnInterruption {pause("Clock paused · "+reason,at:now,manual:false)}
        else if enabled {notice="Clock still running · "+reason}
    }
    private func clearAutomaticPause() {
        guard automaticPause != nil else {return}
        automaticPause=nil;onAutomaticPauseCleared?()
    }
    func finish(at now:Double=ProcessInfo.processInfo.systemUptime) {
        pendingResumeAnnouncement=nil
        pause("Game ended · clocks stopped",at:now);clearAutomaticPause();save()
    }
    func tick(at now:Double) {
        let diagnosticPrevious=engine
        defer {reportPeriodChanges(from:diagnosticPrevious,at:now,cause:"timer")}
        guard running else {return}
        if protectObservationGap(at:now) {return}
        if pauseOnInterruption,let last=lastObservationAt,last<now {
            var trial=engine;trial.advance(to:now)
            var observed=engine;observed.advance(to:last)
            // Await a fresh observation before declaring an expiry beyond the
            // latest evidence. A continued stall takes the protective hold above.
            if trial.expiredBlack != nil && observed.expiredBlack==nil {return}
        }
        if let boundary=pendingUnaccountedInterval {
            var trial=engine;trial.advance(to:now)
            if trial.expiredBlack != nil {
                holdForUnobservedTurns(lastReliableAt:boundary,next:nil,at:now)
                return
            }
        }
        if let evidence=pendingTurnEvidence,evidence.valid,let start=turnBaseline?.anchor,evidence.time>=start {
            var trial=engine;trial.advance(to:now)
            if trial.expiredBlack != nil {
                holdForTimingReview(evidence,at:now,reason:"A possible on-time move is still being verified. Check the turn and clocks; no timeout is inferred.")
                return
            }
        }
        let previous=engine
        engine.advance(to:now)
        if audible {audio.update(previous:previous,current:engine,settings:sounds)}
        if engine.expiredBlack != nil {
            notice="\(engine.expiredBlack == true ? "Black":"White") time expired. Review and enter the agreed result in Info."
            timer?.cancel();timer=nil;save();onTimeout?()
        } else if now-lastSaved>=1 {lastSaved=now;save()}
    }
    func recordMove(number:Int,black:Bool,at now:Double,observedAt:Double?=nil,manualCorrection:Bool=false,estimate:ClockPressEstimate?=nil,provisional:Bool=false,observedLocations:[Int]?=nil) {
        let diagnosticPrevious=engine
        defer {reportPeriodChanges(from:diagnosticPrevious,at:now,cause:"move recognition",press:estimate)}
        guard enabled else {return}
        if !provisional,let i=provisionalMoves.firstIndex(where:{$0.number==number}) {
            guard provisionalMoves[i].black==black else {recover(toBlack:!black,reason:"The corrected move color conflicts with its observed clock press. Review the clocks.",at:now);return}
            var press=provisionalMoves.remove(at:i)
            if reviewedMissingProvisional != nil {
                // The fresh board proved this was a real turn. Keep its measured
                // evidence, use agreed totals, and resume the verified next side.
                press.reviewed=true
                engine.blackToPlay=provisionalMoves.last.map{!$0.black} ?? !black
                reviewedMissingProvisional=nil
            }
            moves.append(press);moves.sort{$0.number<$1.number}
            // Agreed balances are a correction boundary, not an undoable
            // measured press. Earlier thinking time cannot be reconstructed.
            if press.reviewed == true {baseMove=max(baseMove,number)}
            if let estimate=press.estimate {pressEvidence.removeAll{$0.number==number};pressEvidence.append(.init(number:number,estimate:estimate,applied:true))}
            if provisionalMoves.isEmpty {liveReviewActive=false}
            save();return
        }
        if provisionalMoves.contains(where:{$0.number==number}) {return}
        if provisional && (manuallyPaused || needsCorrection || awaitingTurn) {return}
        if provisional && !provisionalCapturePaused {
            guard !manuallyPaused,!needsCorrection,!awaitingTurn,!automaticCapturePaused,
                  let baseline=turnBaseline,let start=baseline.anchor,baseline.blackToPlay==black,
                  let estimate,estimate.valid,estimate.method != .candidate,estimate.time>=start else {return}
        }
        let invalidEstimate=estimate.map{!$0.valid} ?? false
        let estimate=estimate.flatMap{$0.valid ? $0:nil}
        if moves.contains(where:{$0.number==number}) {return}
        if needsCorrection {
            if !provisional,let estimate {
                pressEvidence.removeAll{$0.number==number};pressEvidence.append(.init(number:number,estimate:estimate,applied:false))
            }
            engine.blackToPlay = !black;save();return
        }
        if manualCorrection {recover(toBlack:!black,reason:"Move entered manually. Check both clocks before resuming.",at:now);return}
        guard number==lastTimedMove+1,!needsCorrection else {
            recover(toBlack:!black,reason:"Move timing needs review. Check both clocks before resuming.",at:now);return
        }
        if !provisional,let estimate,estimate.valid {
            pressEvidence.removeAll{$0.number==number};pressEvidence.append(.init(number:number,estimate:estimate,applied:false))
        }
        let displayedBeforeRecognition=engine
        var boundary=now
        if invalidEstimate || (!automaticCapturePaused && !usablePress(observedAt ?? now,estimate:estimate,black:black,now:now)) {
            // An unconfirmed candidate cannot advance the saved clock history
            // or force review. Keep its observation evidence in the recorder;
            // require timing review if it is subsequently accepted as a move.
            if provisional {return}
            baseMove=number
            recover(toBlack:!black,reason:"Move timing crosses a clock hold or has no retained turn boundary. Check both times before resuming.",at:now)
            return
        }
        if let observedAt,observedAt.isFinite,observedAt<=now,
           let baseline=turnBaseline,let start=baseline.anchor,observedAt>=start,baseline.blackToPlay==black {
            // Verification can arrive after the visible timeout. Retained evidence
            // in a running segment can establish an earlier, on-time move.
            if let estimate {
                let upper=min(now,estimate.latestPlausibleTime)
                var earliest=baseline;advanceAccounting(&earliest,to:max(start,estimate.earliestPlausibleTime))
                var latest=baseline;advanceAccounting(&latest,to:upper)
                if earliest.expiredBlack==nil && latest.expiredBlack != nil {
                    if provisional {liveReviewActive=true} else {baseMove=number}
                    holdForTimingReview(estimate,at:now,toBlack:!black,reason:"Hand-clear uncertainty overlaps time expiry. Review both clocks before continuing.")
                    return
                }
            }
            engine=baseline;boundary=observedAt
        }
        advanceAccounting(&engine,to:boundary,beforePress:true)
        let before=engine
        if engine.move(black:black,at:boundary) {
            pendingTurnEvidence=nil
            let pressed=engine
            keepBaseline(engine)
            let press=Move(number:number,black:black,before:before,after:pressed,estimate:estimate,observedLocations:observedLocations)
            if provisional {provisionalMoves.append(press);liveReviewActive=true}
            else {moves.append(press)}
            if let i=pressEvidence.firstIndex(where:{$0.number==number}) {pressEvidence[i].applied = abs(boundary-(estimate?.time ?? boundary))<1e-8}
            advanceAccounting(&engine,to:now)
            notice=running ? "\(engine.blackToPlay ? "Black":"White") to play":"Clock paused"
            if now-boundary>0.05 {notice += " · recognition delay accounted for"}
            if let expired=engine.expiredBlack {notice="\(expired ? "Black":"White") time expired. Review the clocks and result."}
            if audible {audio.moved(engine,settings:sounds,previous:displayedBeforeRecognition)}
            if running {armTimer()}
        } else {
            pause("Move recognized after time expired. Review the clocks and result.",at:now)
            onTimeout?()
        }
        save()
    }
    /// Replay a verified sequence only with complete clock-press evidence.
    /// Missing boundaries require review: continuing would charge one player
    /// for multiple turns and omit overtime resets or increments.
    func recordCatchUp(first:Int,last:Int,blackToPlay:Bool,at now:Double,estimates:[ClockPressEstimate?]=[]) {
        let diagnosticPrevious=engine
        defer {reportPeriodChanges(from:diagnosticPrevious,at:now,cause:"recognition catch-up")}
        guard enabled,last>=first else {return}
        for number in first...last where provisionalMoves.contains(where:{$0.number==number}) {
            let black=(last-number)%2==0 ? !blackToPlay:blackToPlay
            recordMove(number:number,black:black,at:now)
        }
        let recorded=max(moves.last?.number ?? 0,baseMove)
        let skip=max(0,recorded-first+1)
        let estimates=Array(estimates.dropFirst(skip)).map{$0.flatMap{$0.valid ? $0:nil}}
        let first=max(first,recorded+1)
        guard last>recorded else {return}
        if skip>0,first==last {
            recordMove(number:last,black:!blackToPlay,at:now,observedAt:estimates.first.flatMap{$0?.time},estimate:estimates.first ?? nil);return
        }
        guard first==recorded+1 else {
            recover(toBlack:blackToPlay,reason:"Clock history does not match the confirmed game. Check both times before resuming.",at:now);return
        }
        if estimates.count==last-first+1 {
            pressEvidence.removeAll{(first...last).contains($0.number)}
            pressEvidence += estimates.enumerated().map{.init(number:first+$0.offset,estimate:$0.element,applied:false)}
            if replayPresses(first:first,last:last,blackToPlay:blackToPlay,at:now,estimates:estimates) {return}
        }
        baseMove=last
        timingNote="Moves \(first)–\(last) are saved, but their individual clock presses could not all be verified. Displayed times need review."
        recover(toBlack:blackToPlay,reason:"Clock timing could not be verified for the recovered moves. Check both clock times before resuming.",at:now)
    }

    /// Validate every press and replay into a copy before publishing any balance.
    /// No partial increments, overwritten pause, or invented missing boundary.
    private func replayPresses(first:Int,last:Int,blackToPlay:Bool,at now:Double,estimates:[ClockPressEstimate?])->Bool {
        guard !manuallyPaused,!needsCorrection,!awaitingTurn,!automaticCapturePaused,
              let baseline=turnBaseline,let start=baseline.anchor,baseline.running,now.isFinite else {return false}
        let expectedFirst=(last-first+1)%2==0 ? blackToPlay:!blackToPlay
        guard baseline.blackToPlay==expectedFirst else {return false}
        var trial=baseline,checkpoints=[Move](),previous=start
        for (offset,value) in estimates.enumerated() {
            guard let estimate=value,estimate.valid,estimate.method != .candidate,
                  estimate.time>=start,estimate.time<=now,(offset==0 ? estimate.time>=previous:estimate.time>previous) else {return false}
            // The alternating trial has its own current player, while the
            // retained baseline still names the sequence's first mover.
            guard usablePress(estimate.time,estimate:estimate,black:baseline.blackToPlay,now:now) else {return false}
            do {
                let upper=min(now,estimate.latestPlausibleTime)
                var latest=trial;advanceAccounting(&latest,to:upper)
                var point=trial;advanceAccounting(&point,to:max(previous,estimate.earliestPlausibleTime))
                if point.expiredBlack==nil && latest.expiredBlack != nil {
                    baseMove=last
                    // No partial replay has been published. Freeze at the
                    // first known press instead of expiring the original side
                    // while the later turn's boundary still needs review.
                    holdForTimingReview(estimates.compactMap{$0}.first!,at:now,toBlack:blackToPlay,
                        reason:"Hand-clear uncertainty overlaps time expiry. Review both clocks before continuing.")
                    return true
                }
            }
            let black=trial.blackToPlay
            advanceAccounting(&trial,to:estimate.time,beforePress:true);let before=trial
            guard trial.move(black:black,at:estimate.time) else {
                baseMove=last
                recover(toBlack:blackToPlay,reason:"A retained clock press is after time expiry. Review both clocks before continuing.",at:now)
                return true
            }
            checkpoints.append(.init(number:first+offset,black:black,before:before,after:trial,estimate:estimate))
            previous=estimate.time
        }
        guard trial.blackToPlay==blackToPlay else {return false}
        let displayed=engine
        moves += checkpoints;keepBaseline(trial);advanceAccounting(&trial,to:now);engine=trial
        for i in pressEvidence.indices where (first...last).contains(pressEvidence[i].number) {pressEvidence[i].applied=true}
        timingNote="Moves \(first)–\(last): individual virtual clock presses restored from retained camera evidence. Error estimates are available with each press."
        notice=engine.expiredBlack == nil ? "\(blackToPlay ? "Black":"White") to play · recognition delay accounted for":"Time expired. Review the clocks and result."
        if audible {audio.moved(engine,settings:sounds,previous:displayed)}
        if running {armTimer()};save();return true
    }
    /// A static later board cannot establish intervening presses. Stop at the
    /// last supported view of the established position, not at recognition time.
    func holdForUnobservedTurns(lastReliableAt:Double?,next:Stone?,at now:Double) {
        guard enabled else {return}
        guard !needsCorrection else {return}
        var boundary=now
        if let baseline=turnBaseline,let start=baseline.anchor {
            engine=baseline
            boundary=max(start,min(now,lastReliableAt ?? start))
            advanceAccounting(&engine,to:boundary)
        }
        pendingTurnEvidence=nil;pendingUnaccountedInterval=nil
        recover(toBlack:next.map{$0 == .black} ?? engine.blackToPlay,
            reason:"Moves appeared without individual timing evidence. Review the clocks; no missing presses or increments were invented.",at:boundary)
        awaitingTurn=next==nil;save()
    }
    func recover(toBlack:Bool,reason:String,at now:Double) {
        guard enabled else {return}
        // Review may run before the timer's next callback. Protect the same
        // pending press here, before pause() advances the clock to review time.
        // holdForTimingReview clears the evidence before calling back here.
        if let evidence=pendingTurnEvidence {
            holdForTimingReview(evidence,at:now,toBlack:toBlack,reason:reason)
            return
        }
        pause(reason,at:now,manual:false)
        discardTimingBaseline()
        manuallyPaused=true;engine.blackToPlay=toBlack;needsCorrection=true;save()
    }
    /// Stop at the earliest retained possible press, before recognition delay
    /// can erase a period or declare a loss. Balances explicitly require review.
    func holdForTimingReview(_ evidence:ClockPressEstimate,at now:Double,toBlack:Bool?=nil,reason:String) {
        guard enabled else {return}
        var stopAt=now
        if let baseline=turnBaseline,let start=baseline.anchor,evidence.valid,
           evidence.time>=start,evidence.earliestPlausibleTime<=now {
            engine=baseline
            stopAt=max(start,evidence.earliestPlausibleTime)
            advanceAccounting(&engine,to:stopAt)
        }
        pendingTurnEvidence=nil
        timingNote=reason
        recover(toBlack:toBlack ?? engine.blackToPlay,reason:reason,at:stopAt)
    }
    /// Historical gaps do not replay clock presses. Preserve accrued time and
    /// continue the known live turn, without inventing increments or overtime resets.
    func followLiveTurn(_ color:Stone?,at now:Double,resumeIfReady:Bool=false) {
        let diagnosticPrevious=engine
        defer {reportPeriodChanges(from:diagnosticPrevious,at:now,cause:"live turn")}
        guard enabled else {return}
        liveReviewActive=true
        timingNote="The current turn is retained independently of unresolved move locations. Reviewing history does not press the clock."
        advanceAccounting(&engine,to:now);discardTimingBaseline()
        guard let color else {
            awaitingTurn=true;pause("Whose turn is it? Choose Black or White to continue the clock.",at:now,manual:false);return
        }
        awaitingTurn=false;engine.blackToPlay=color == .black
        if resumeIfReady {ready(at:now)}
        turnBaseline=running ? engine:nil
        notice=requiresReview ? "Check both clock times before resuming." : running ? "\(color.rawValue.capitalized) to play":"Clock paused"
        if running && audible {audio.beganTurn(engine,settings:sounds)}
        save()
    }
    func recordLiveMove(id:UUID,black:Bool,at now:Double,observedAt:Double,estimate:ClockPressEstimate?=nil) {
        let diagnosticPrevious=engine
        defer {reportPeriodChanges(from:diagnosticPrevious,at:now,cause:"live move recognition",press:estimate)}
        guard enabled,!liveEvents.contains(where:{$0.id==id}) else {return}
        liveReviewActive=true
        guard !awaitingTurn,!needsCorrection,engine.blackToPlay==black,(running || turnBaseline != nil) else {
            recover(toBlack:!black,reason:"Live move has no retained clock turn. Check both times before resuming.",at:now);return
        }
        let displayedBeforeRecognition=engine
        let invalidEstimate=estimate.map{!$0.valid} ?? false
        let estimate=estimate.flatMap{$0.valid ? $0:nil}
        var boundary=now
        guard !invalidEstimate,usablePress(observedAt,estimate:estimate,black:black,now:now) else {
            recover(toBlack:!black,reason:"Live move timing crosses a clock hold. Check both times before resuming.",at:now);return
        }
        if observedAt.isFinite,observedAt<=now,let baseline=turnBaseline,
           let start=baseline.anchor,observedAt>=start,baseline.blackToPlay==black {
            if let estimate {
                let upper=min(now,estimate.latestPlausibleTime)
                var lowerClock=baseline;advanceAccounting(&lowerClock,to:max(start,estimate.earliestPlausibleTime))
                var upperClock=baseline;advanceAccounting(&upperClock,to:upper)
                if lowerClock.expiredBlack==nil && upperClock.expiredBlack != nil {
                    holdForTimingReview(estimate,at:now,toBlack:!black,reason:"Hand-clear uncertainty overlaps time expiry. Review both clocks before continuing.")
                    return
                }
            }
            engine=baseline;boundary=observedAt
        }
        advanceAccounting(&engine,to:boundary,beforePress:true);let before=engine
        if engine.move(black:black,at:boundary) {
            liveEvents.append(.init(id:id,black:black,before:before,after:engine,estimate:estimate))
            keepBaseline(engine)
            advanceAccounting(&engine,to:now)
            notice="\(engine.blackToPlay ? "Black":"White") to play"
            if audible {audio.moved(engine,settings:sounds,previous:displayedBeforeRecognition)}
            if running {armTimer()}
        } else {pause("Move recognized after time expired. Review the clocks.",at:now);onTimeout?()}
        save()
    }
    /// Associate already observed presses with their final SGF numbers exactly
    /// once. Resolving chronology never charges time or awards an increment.
    func finalizeLiveHistory(mapping:[UUID:Int],moveCount:Int,blackToPlay:Bool) {
        guard enabled else {return}
        for press in provisionalMoves.filter({$0.number<=moveCount}) {
            recordMove(number:press.number,black:press.black,at:ProcessInfo.processInfo.systemUptime)
        }
        for press in liveEvents {
            if let number=mapping[press.id],!moves.contains(where:{$0.number==number}) {
                moves.append(.init(number:number,black:press.black,before:press.before,after:press.after,estimate:press.estimate))
                if let estimate=press.estimate {
                    pressEvidence.removeAll{$0.number==number}
                    pressEvidence.append(.init(number:number,estimate:estimate,applied:press.after.anchor==estimate.time))
                }
            }
        }
        moves.sort{$0.number<$1.number};baseMove=moveCount
        engine.blackToPlay=provisionalMoves.last.map{!$0.black} ?? blackToPlay;liveReviewActive = !provisionalMoves.isEmpty;awaitingTurn=false
        save()
    }
    func canCorrect(black:LocalClockEngine.Side,white:LocalClockEngine.Side)->Bool {enabled && valid(black) && valid(white)}
    @discardableResult func correct(black:LocalClockEngine.Side,white:LocalClockEngine.Side,blackToPlay:Bool,moveCount:Int,at now:Double=ProcessInfo.processInfo.systemUptime)->Bool {
        guard canCorrect(black:black,white:white) else {return false}
        pause(at:now)
        engine.correct(black:black,white:white,blackToPlay:blackToPlay)
        audio.resetAnnouncements(to:engine)
        // Explicit clock review supplies the next player as well as balances.
        // Keep the manual pause until fresh board verification, but release the
        // unknown-turn gate that would otherwise make ready() refuse forever.
        awaitingTurn=false
        reviewedMissingProvisional=nil
        needsCorrection=false;manuallyPaused=true;baseMove=moveCount
        notice="Clocks corrected · paused. Resume when both players are ready.";save()
        return true
    }
    /// Preserve the timing boundary independently of unresolved SGF locations.
    func acknowledgePendingTurns(_ locations:[Set<Int>],firstBlack:Bool,moveCount:Int) {
        guard !requiresReview,!running else {return}
        reviewedMissingProvisional=locations.isEmpty && !provisionalMoves.isEmpty ? provisionalMoves.map(\.number):nil
        for (offset,points) in locations.enumerated() {
            let number=moveCount+offset+1
            guard !provisionalMoves.contains(where:{$0.number==number}) else {continue}
            provisionalMoves.append(.init(number:number,black:offset%2==0 ? firstBlack:!firstBlack,
                before:engine,after:engine,observedLocations:points.sorted(),reviewed:true))
        }
        provisionalMoves.sort{$0.number<$1.number}
        liveReviewActive = !provisionalMoves.isEmpty
        if !locations.isEmpty {timingNote="Agreed clock balances include the pending moves. Their placements remain under review; no historical clock presses were inferred."}
        save()
    }
    /// Called only after repeated clear observations of the saved position.
    /// Keep the agreed totals; undoing a false press would overwrite that review.
    @discardableResult func resolveMissingProvisional(moveCount:Int,blackToPlay:Bool)->Bool {
        guard canResolveMissingProvisional,baseMove==moveCount else {return false}
        provisionalMoves=[];reviewedMissingProvisional=nil;liveReviewActive=false
        engine.blackToPlay=blackToPlay
        timingNote="Agreed clock totals retained. Fresh board verification cleared the absent provisional move."
        save();return true
    }
    private func valid(_ side:LocalClockEngine.Side)->Bool {
        side.remaining.isFinite && (0.001...604800).contains(side.remaining) &&
            (1...engine.settings.periods).contains(side.periods) && (1...engine.settings.stonesPerPeriod).contains(side.stones) &&
            (!side.overtime || [.byoyomi,.canadian].contains(engine.settings.kind))
    }
    func undo(to moveCount:Int,blackToPlay:Bool,at now:Double=ProcessInfo.processInfo.systemUptime) {
        guard enabled else {return}
        pendingResumeAnnouncement=nil
        pause(at:now)
        if let move=moves.last,move.number==moveCount+1,move.number>baseMove {
            engine=move.before;engine.restoredPaused();moves.removeLast();needsCorrection=false
            audio.resetAnnouncements(to:engine)
            notice="Last clock press undone · clocks paused"
        } else {engine.blackToPlay=blackToPlay;needsCorrection=true;notice="Undo needs clock review. Check both clocks."}
        // A resolved review can place the checkpoint at the move being undone.
        // Keep the shortened recording reloadable without inventing press times.
        baseMove=min(baseMove,moveCount);moves.removeAll{$0.number>moveCount};pressEvidence.removeAll{$0.number>moveCount}
        liveEvents=[];provisionalMoves=[];liveReviewActive=false;awaitingTurn=false;reviewedMissingProvisional=nil
        save()
    }
    func restore(from sgf:URL,signature:String,moveCount:Int,blackToPlay:Bool) {
        configure(.init(kind:.none),blackToPlay:blackToPlay)
        let url=sgf.deletingPathExtension().appendingPathExtension("clock.json")
        guard storageWriter.perform({FileManager.default.fileExists(atPath:url.path)}) else {return}
        do {
            let data=try storageWriter.perform {try JSONDecoder().decode(Saved.self,from:Data(contentsOf:url))}
            guard data.version==1,data.signature==signature,data.engine.settings.validationError==nil,
                  data.baseMove<=moveCount,data.moves.count<=moveCount,
                  data.engine.blackToPlay==blackToPlay || data.engine.expiredBlack != nil || data.liveReviewActive == true else {
                throw NSError(domain:"PhysicalGo.Clock",code:1,userInfo:[NSLocalizedDescriptionKey:"Saved clock does not match this recording."])
            }
            guard [data.engine.black,data.engine.white].allSatisfy({$0.remaining.isFinite && (0...604800).contains($0.remaining) && (1...data.engine.settings.periods).contains($0.periods) && (1...data.engine.settings.stonesPerPeriod).contains($0.stones)}) else {
                throw NSError(domain:"PhysicalGo.Clock",code:2,userInfo:[NSLocalizedDescriptionKey:"Saved clock contains invalid values."])
            }
            guard data.moves.allSatisfy({$0.estimate?.valid ?? true}),
                  (data.pressEvidence ?? []).allSatisfy({$0.number>0 && $0.number<=moveCount && ($0.estimate?.valid ?? true)}) else {
                throw NSError(domain:"PhysicalGo.Clock",code:3,userInfo:[NSLocalizedDescriptionKey:"Saved clock has invalid press evidence."])
            }
            let provisional=data.provisionalMoves ?? []
            guard provisional.enumerated().allSatisfy({offset,press in
                press.number==moveCount+offset+1 && ((press.estimate?.valid ?? false) || (press.reviewed == true && press.observedLocations?.isEmpty == false)) &&
                press.black==(offset%2==0 ? blackToPlay:!blackToPlay)
            }) else {throw RecordingStore.Failure(message:"Provisional clock presses do not match this game.")}
            engine=data.engine;engine.restoredPaused();moves=data.moves;provisionalMoves=provisional;baseMove=data.baseMove;pressEvidence=data.pressEvidence ?? []
            reviewedMissingProvisional=data.reviewedMissingProvisional
            audio.resetAnnouncements(to:engine)
            needsCorrection=data.needsCorrection;manuallyPaused=true;file=url;self.signature=signature
            liveEvents=data.liveEvents ?? [];liveReviewActive=data.liveReviewActive ?? false
            awaitingTurn=data.awaitingTurn ?? false;timingNote=data.timingNote;automaticPause=data.automaticPause
            pendingResumeAnnouncement=data.resumeAnnouncement
            automaticCapturePosition=data.capturePosition;automaticCapturePaused=data.capturePosition != nil;provisionalCaptureStart=data.provisionalCaptureStart
            notice=requiresReview ? "Saved clocks need review. Choose Review & resume to confirm or adjust both times."
                : "Saved clocks restored · paused. Resume the clock when ready."
        } catch {saveError=error.localizedDescription;notice="Saved clock could not be restored."}
    }
    /// Coordinate corrections keep measured balances. Truncation cannot infer
    /// historical thinking time and explicitly requires a clock review.
    func writeHistoricalCorrection(to url:URL,signature:String,moveCount:Int,blackToPlay:Bool,discardedMoves:Int,hasReviews:Bool)throws {
        guard enabled else {return}
        var corrected=engine;corrected.restoredPaused();corrected.blackToPlay=blackToPlay
        let saved=Saved(signature:signature,engine:corrected,moves:moves.filter{$0.number<=moveCount},
            baseMove:min(baseMove,moveCount),needsCorrection:needsCorrection || discardedMoves>0,
            liveEvents:discardedMoves>0 ? []:liveEvents,liveReviewActive:hasReviews,awaitingTurn:hasReviews,
            timingNote:discardedMoves>0 ? "Later moves set aside. Check both clock times.":timingNote,pressEvidence:pressEvidence.filter{$0.number<=moveCount})
        try storageWriter.perform {try JSONEncoder().encode(saved).write(to:url.deletingPathExtension().appendingPathExtension("clock.json"),options:.atomic)}
    }
    func sgfMoveProperties(_ number:Int)->[String:[String]] {
        guard let move=moves.first(where:{$0.number==number}) else {return [:]}
        let side=move.black ? move.after.black:move.after.white
        var props=[move.black ? "BL":"WL":[String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),side.remaining)]]
        if side.overtime {props[move.black ? "OB":"OW"]=[String(engine.settings.kind == .byoyomi ? side.periods:side.stones)]}
        return props
    }
    func testSound() {if audible {audio.say("Ten. Nine. Three periods left.",settings:sounds,announcement:true)}}
    private func armTimer() {
        guard timer==nil else {return}
        // A run-loop timer plus an unstructured Task can defer countdown
        // updates during native view work. Deliver directly on the main queue.
        // Missed callbacks coalesce: charge monotonic elapsed time, never the
        // number of callbacks, and preserve every existing hold/expiry guard.
        let timer=DispatchSource.makeTimerSource(queue:.main)
        timer.schedule(deadline:.now()+0.1,repeating:.milliseconds(100),leeway:.milliseconds(5))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {self?.tick(at:ProcessInfo.processInfo.systemUptime)}
        }
        self.timer=timer;timer.resume()
    }
    private func save() {
        guard enabled,let file,!signature.isEmpty else {return}
        do {
            let saved=Saved(signature:signature,engine:engine,moves:moves,baseMove:baseMove,needsCorrection:needsCorrection,
                            liveEvents:liveEvents,liveReviewActive:liveReviewActive,awaitingTurn:awaitingTurn,timingNote:timingNote,automaticPause:automaticPause,
                            resumeAnnouncement:pendingResumeAnnouncement,capturePosition:automaticCapturePosition,pressEvidence:pressEvidence,provisionalMoves:provisionalMoves,provisionalCaptureStart:provisionalCaptureStart,reviewedMissingProvisional:reviewedMissingProvisional)
            try storageWriter.submit("clock",component:.clock,coalescingKey:file.path) {try JSONEncoder().encode(saved).write(to:file,options:.atomic)}
            saveError=nil
        } catch {saveError="Could not save clock: \(error.localizedDescription)"}
    }
}
