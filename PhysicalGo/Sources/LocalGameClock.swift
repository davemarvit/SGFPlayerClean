import Foundation
import Combine

@MainActor final class LocalGameClock:ObservableObject {
    struct Move:Codable {
        var number:Int
        var black:Bool
        var before:LocalClockEngine
        var after:LocalClockEngine
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
    }
    struct LivePress:Codable {
        let id:UUID
        let black:Bool
        let before:LocalClockEngine
        let after:LocalClockEngine
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
    @Published private(set) var automaticPause:AutomaticPause?
    var onAutomaticPause:((AutomaticPause)->Void)?
    var onAutomaticPauseCleared:(()->Void)?
    var onResumeAnnouncement:((String)->Void)?
    private(set) var pendingResumeAnnouncement:String?
    private let audio=LocalClockAudio()
    var onSpeechEvent:SpeechEventHandler? {didSet {audio.onSpeechEvent=onSpeechEvent}}
    private var timer:Timer?
    private var manuallyPaused=false
    private(set) var moves=[Move]()
    private(set) var baseMove=0
    private var file:URL?
    private var signature=""
    private var lastSaved=0.0
    // Start of the current uninterrupted turn, used only after a move is verified.
    private var turnBaseline:LocalClockEngine?
    deinit {timer?.invalidate()}
    var enabled:Bool {engine.enabled}
    var running:Bool {engine.running}
    var requiresReview:Bool {needsCorrection || engine.expiredBlack != nil}
    func configure(_ settings:LocalClockSettings,blackToPlay:Bool,baseMove:Int=0) {
        guard settings.validationError==nil else {return}
        timer?.invalidate();timer=nil;audio.stop(reason:"clock configured")
        audio.resetAnnouncements()
        engine=LocalClockEngine(settings:settings,blackToPlay:blackToPlay);moves=[];self.baseMove=baseMove
        needsCorrection=false;manuallyPaused=false;notice="Clock starts when the board is ready."
        liveReviewActive=false;awaitingTurn=false;timingNote=nil;liveEvents=[]
        pendingResumeAnnouncement=nil
        clearAutomaticPause()
        file=nil;signature="";saveError=nil;turnBaseline=nil
    }
    func bind(to sgf:URL?,signature:String) {
        file=sgf?.deletingPathExtension().appendingPathExtension("clock.json");self.signature=signature
        save()
    }
    func ready(at now:Double) {
        guard enabled,!running,!manuallyPaused,!needsCorrection,!awaitingTurn,engine.expiredBlack==nil else {return}
        engine.resume(at:now);clearAutomaticPause();turnBaseline=engine;notice="\(engine.blackToPlay ? "Black":"White") to play"
        let announcement=pendingResumeAnnouncement;pendingResumeAnnouncement=nil
        if announcement == nil && audible {audio.beganTurn(engine,settings:sounds)}
        armTimer();save()
        if let announcement {onResumeAnnouncement?("\(announcement) Clocks resumed. \(engine.blackToPlay ? "Black":"White") to play.")}
    }
    func queueResumeAnnouncement(_ message:String) {
        guard enabled,!running else {return}
        pendingResumeAnnouncement=message;save()
    }
    func requestResume() {manuallyPaused=false}
    func resume(at now:Double=ProcessInfo.processInfo.systemUptime) {
        guard !needsCorrection else {return}
        manuallyPaused=false;ready(at:now)
    }
    func pause(_ reason:String="Clock paused",at now:Double=ProcessInfo.processInfo.systemUptime,manual:Bool=true) {
        guard enabled else {return}
        let wasRunning=running
        engine.pause(at:now);turnBaseline=nil
        // Later camera interruptions must not revoke an explicit user pause.
        if manual {manuallyPaused=true} else if wasRunning {manuallyPaused=false}
        let beganAutomaticPause = wasRunning && !manual && automaticPause==nil
        if beganAutomaticPause {
            let prefix="Clock paused · "
            automaticPause=AutomaticPause(reason:reason.hasPrefix(prefix) ? String(reason.dropFirst(prefix.count)):reason,recordedAt:Date())
        }
        notice=engine.expiredBlack.map {"\($0 ? "Black":"White") time expired. Review and enter the agreed result in Info."} ?? reason
        audio.stop(reason:reason);timer?.invalidate();timer=nil;save()
        if beganAutomaticPause,let automaticPause {onAutomaticPause?(automaticPause)}
    }
    func interrupt(_ reason:String,at now:Double=ProcessInfo.processInfo.systemUptime) {
        if awaitingTurn {return}
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
        guard running else {return}
        let previous=engine
        engine.advance(to:now)
        if audible {audio.update(previous:previous,current:engine,settings:sounds)}
        if engine.expiredBlack != nil {
            notice="\(engine.expiredBlack == true ? "Black":"White") time expired. Review and enter the agreed result in Info."
            timer?.invalidate();timer=nil;save();onTimeout?()
        } else if now-lastSaved>=1 {lastSaved=now;save()}
    }
    func recordMove(number:Int,black:Bool,at now:Double,observedAt:Double?=nil,manualCorrection:Bool=false) {
        guard enabled else {return}
        if moves.last?.number == number {return}
        if needsCorrection {engine.blackToPlay = !black;save();return}
        if manualCorrection {recover(toBlack:!black,reason:"Move entered manually. Check both clocks before resuming.",at:now);return}
        guard number==max(moves.last?.number ?? 0,baseMove)+1,!needsCorrection else {
            recover(toBlack:!black,reason:"Move timing needs review. Check both clocks before resuming.",at:now);return
        }
        let displayedBeforeRecognition=engine
        var boundary=now
        if let observedAt,observedAt.isFinite,observedAt<=now,
           let baseline=turnBaseline,let start=baseline.anchor,observedAt>=start,baseline.blackToPlay==black {
            // Verification can arrive after the visible timeout. Only retained evidence
            // from this uninterrupted turn can establish an earlier, on-time move.
            engine=baseline;boundary=observedAt
        }
        engine.advance(to:boundary)
        let before=engine
        if engine.move(black:black,at:boundary) {
            let pressed=engine
            turnBaseline=engine.running ? engine:nil
            moves.append(Move(number:number,black:black,before:before,after:pressed))
            engine.advance(to:now)
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
    /// A verified sequence can lack individual clock-press times. Keep live
    /// timing moving, retain accrued totals and avoid inventing per-move bonuses.
    /// The next ordinary move must follow this confirmed SGF position.
    func recordCatchUp(first:Int,last:Int,blackToPlay:Bool,at now:Double) {
        guard enabled,last>=first else {return}
        let recorded=max(moves.last?.number ?? 0,baseMove)
        guard last>recorded else {return}
        guard first==recorded+1 else {
            recover(toBlack:blackToPlay,reason:"Clock history does not match the confirmed game. Check both times before resuming.",at:now);return
        }
        engine.advance(to:now);engine.blackToPlay=blackToPlay;baseMove=last;turnBaseline=nil
        timingNote="Moves \(first)–\(last) were confirmed together. Their individual clock presses and bonuses were not reconstructed. Live timing continues; adjust either time if needed."
        ready(at:now) // Respects manual pauses, genuine timeouts and explicit review gates.
        turnBaseline=running ? engine:nil
        if !requiresReview {notice=running ? "\(blackToPlay ? "Black":"White") to play":"Clock paused"}
        if running && audible {audio.moved(engine,settings:sounds)}
        save()
    }

    func recover(toBlack:Bool,reason:String,at now:Double) {
        guard enabled else {return}
        pause(reason,at:now,manual:false)
        manuallyPaused=true;engine.blackToPlay=toBlack;needsCorrection=true;save()
    }
    /// Historical gaps do not replay clock presses. Preserve accrued time and
    /// continue the known live turn, without inventing increments or overtime resets.
    func followLiveTurn(_ color:Stone?,at now:Double,resumeIfReady:Bool=false) {
        guard enabled else {return}
        liveReviewActive=true
        timingNote="Earlier clock presses were not all observed. Continue playing; adjust times if needed. Reviewing move order will not change the clocks."
        engine.advance(to:now);turnBaseline=nil
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
    func recordLiveMove(id:UUID,black:Bool,at now:Double,observedAt:Double) {
        guard enabled,!liveEvents.contains(where:{$0.id==id}) else {return}
        liveReviewActive=true
        guard !awaitingTurn,!needsCorrection,engine.blackToPlay==black,(running || turnBaseline != nil) else {
            followLiveTurn(black ? .white:.black,at:now,resumeIfReady:true);return
        }
        let displayedBeforeRecognition=engine
        var boundary=now
        if observedAt.isFinite,observedAt<=now,let baseline=turnBaseline,
           let start=baseline.anchor,observedAt>=start,baseline.blackToPlay==black {
            engine=baseline;boundary=observedAt
        }
        engine.advance(to:boundary);let before=engine
        if engine.move(black:black,at:boundary) {
            liveEvents.append(.init(id:id,black:black,before:before,after:engine))
            turnBaseline=engine.running ? engine:nil
            engine.advance(to:now)
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
        for press in liveEvents {
            if let number=mapping[press.id],!moves.contains(where:{$0.number==number}) {
                moves.append(.init(number:number,black:press.black,before:press.before,after:press.after))
            }
        }
        moves.sort{$0.number<$1.number};baseMove=moveCount
        engine.blackToPlay=blackToPlay;liveReviewActive=false;awaitingTurn=false
        save()
    }
    func canCorrect(black:LocalClockEngine.Side,white:LocalClockEngine.Side)->Bool {enabled && valid(black) && valid(white)}
    @discardableResult func correct(black:LocalClockEngine.Side,white:LocalClockEngine.Side,blackToPlay:Bool,moveCount:Int,at now:Double=ProcessInfo.processInfo.systemUptime)->Bool {
        guard canCorrect(black:black,white:white) else {return false}
        pause(at:now)
        engine.correct(black:black,white:white,blackToPlay:blackToPlay)
        audio.resetAnnouncements(to:engine)
        needsCorrection=false;manuallyPaused=true;baseMove=moveCount
        notice="Clocks corrected · paused. Resume when both players are ready.";save()
        return true
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
        save()
    }
    func restore(from sgf:URL,signature:String,moveCount:Int,blackToPlay:Bool) {
        configure(.init(kind:.none),blackToPlay:blackToPlay)
        let url=sgf.deletingPathExtension().appendingPathExtension("clock.json")
        guard FileManager.default.fileExists(atPath:url.path) else {return}
        do {
            let data=try JSONDecoder().decode(Saved.self,from:Data(contentsOf:url))
            guard data.version==1,data.signature==signature,data.engine.settings.validationError==nil,
                  data.baseMove<=moveCount,data.moves.count<=moveCount,
                  data.engine.blackToPlay==blackToPlay || data.engine.expiredBlack != nil || data.liveReviewActive == true else {
                throw NSError(domain:"PhysicalGo.Clock",code:1,userInfo:[NSLocalizedDescriptionKey:"Saved clock does not match this recording."])
            }
            guard [data.engine.black,data.engine.white].allSatisfy({$0.remaining.isFinite && (0...604800).contains($0.remaining) && (1...data.engine.settings.periods).contains($0.periods) && (1...data.engine.settings.stonesPerPeriod).contains($0.stones)}) else {
                throw NSError(domain:"PhysicalGo.Clock",code:2,userInfo:[NSLocalizedDescriptionKey:"Saved clock contains invalid values."])
            }
            engine=data.engine;engine.restoredPaused();moves=data.moves;baseMove=data.baseMove
            audio.resetAnnouncements(to:engine)
            needsCorrection=data.needsCorrection;manuallyPaused=true;file=url;self.signature=signature
            liveEvents=data.liveEvents ?? [];liveReviewActive=data.liveReviewActive ?? false
            awaitingTurn=data.awaitingTurn ?? false;timingNote=data.timingNote;automaticPause=data.automaticPause
            pendingResumeAnnouncement=data.resumeAnnouncement
            notice=requiresReview ? "Saved clocks need review. Choose Review & resume to confirm or adjust both times."
                : "Saved clocks restored · paused. Resume the clock when ready."
        } catch {saveError=error.localizedDescription;notice="Saved clock could not be restored."}
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
        let timer=Timer(timeInterval:0.1,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.tick(at:ProcessInfo.processInfo.systemUptime) }
        }
        self.timer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    private func save() {
        guard enabled,let file,!signature.isEmpty else {return}
        do {
            let saved=Saved(signature:signature,engine:engine,moves:moves,baseMove:baseMove,needsCorrection:needsCorrection,
                            liveEvents:liveEvents,liveReviewActive:liveReviewActive,awaitingTurn:awaitingTurn,timingNote:timingNote,automaticPause:automaticPause,
                            resumeAnnouncement:pendingResumeAnnouncement)
            try JSONEncoder().encode(saved).write(to:file,options:.atomic);saveError=nil
        } catch {saveError="Could not save clock: \(error.localizedDescription)"}
    }
}
