import Foundation
import Combine
#if os(macOS)
import IOKit.ps
#endif

/// Keep the device adapter separate from the analysis policy for a future iOS host.
enum PhysicalPowerSource {
    case external, battery, unknown
    static func current() -> Self {
        #if os(macOS)
        guard let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source=IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {return .unknown}
        if source as String == kIOPSACPowerValue {return .external}
        if source as String == kIOPSBatteryPowerValue {return .battery}
        #endif
        return .unknown
    }
}

@MainActor protocol PhysicalBackgroundWorker:AnyObject {
    var failure:String? {get}
    func analyze(_ player:SGFPlayer)
    func analysis(at index:Int)->AIAnalysis?
    func stop()
}

@MainActor private final class PhysicalKataGoBackgroundWorker:PhysicalBackgroundWorker {
    let engine=PhysicalScoring.makeWorker()
    var failure:String? {engine.analysisError ?? engine.engineStartupError}
    init() {engine.currentGameId="physical-background-"+UUID().uuidString;engine.start()}
    func analyze(_ player:SGFPlayer) {
        let payload=player.getCurrentAIPayload()
        engine.analyzeGame(id:engine.currentGameId,initialStones:payload.initial,moves:payload.moves,
                           size:player.board.size,maxVisits:300,settings:player.analysisSettings,
                           continuous:true,requireOwnership:true)
    }
    func analysis(at index:Int)->AIAnalysis? {engine.currentAnalysisData[index]}
    func stop() {engine.stop()}
}

/// Stable live positions may be analyzed independently of unresolved chronology.
@MainActor final class PhysicalBackgroundAnalysis:ObservableObject {
    @Published private(set) var status="AI runs on request until power is checked."
    @Published private(set) var running=false
    private let makeWorker:()->any PhysicalBackgroundWorker
    private var worker:(any PhysicalBackgroundWorker)?
    private var key:String?
    private var failedKey:String?
    private var index=0
    private var latest:AIAnalysis?
    init(makeWorker:(()->any PhysicalBackgroundWorker)?=nil) {
        self.makeWorker=makeWorker ?? {PhysicalKataGoBackgroundWorker()}
    }
    static func positionKey(_ recorder:GameRecorder)->String {
        recorder.scoringPositionKey
    }
    func cachedAnalysis(for recorder:GameRecorder)->AIAnalysis? {
        guard key==Self.positionKey(recorder) else {return nil}
        return best(worker?.analysis(at:index))
    }
    private func best(_ incoming:AIAnalysis?)->AIAnalysis? {
        guard let incoming else {return latest}
        guard let latest else {return incoming}
        return (latest.rootInfo?.visits ?? 0)>(incoming.rootInfo?.visits ?? 0) ? latest:incoming
    }
    func remember(_ analysis:AIAnalysis,positionKey:String) {
        guard worker == nil,!positionKey.isEmpty else {return}
        if key != positionKey {latest=nil}
        key=positionKey;latest=best(analysis)
    }
    /// Transfer the existing search to an explicit score request without a cold start.
    func takeWorker(for recorder:GameRecorder)->(any PhysicalBackgroundWorker)? {
        guard key==Self.positionKey(recorder) else {return nil}
        if let value=worker?.analysis(at:index) {latest=best(value)}
        let result=worker;worker=nil;running=false;return result
    }
    func refresh(recorder:GameRecorder,local:Bool,foreground:Bool,power:PhysicalPowerSource) {
        let nextKey=Self.positionKey(recorder)
        if nextKey != key {latest=nil;failedKey=nil}
        // Harvest only the position that was actually submitted, before changing key/index.
        if nextKey==key,let value=worker?.analysis(at:index) {latest=best(value)}
        let changed=nextKey != key
        guard local else {stop();status="Local AI is off during online play.";return}
        guard power == .external else {
            stop();failedKey=nil
            status=power == .battery ? "On battery · AI runs only when you press Score game.":"Power source unknown · AI runs only on request."
            return
        }
        guard !foreground else {stop();status="Score game is using the AI; background analysis is paused.";return}
        guard recorder.state != .finished else {
            stop();status="Game finished · the last analyzed position is retained for scoring.";return
        }
        guard recorder.canScorePosition else {
            // A hand over the next move must not tear down the warm engine.
            // The retained result stays keyed to the last submitted position.
            status="Plugged in · keeping the last position ready while the camera confirms the next move.";return
        }
        if let failure=worker?.failure {
            stop();failedKey=nextKey;status="Background AI unavailable: "+failure;return
        }
        guard failedKey != nextKey else {return}
        if worker == nil || changed {
            let game=recorder.scoringGame
            let player=SGFPlayer();player.load(game:game);player.seek(to:game.moves.count)
            if let issue=LocalScoringSession(player:player,handicap:recorder.game.handicap).issue {
                stop();status="Background AI waiting: "+issue;return
            }
            key=nextKey;index=player.currentIndex
            if worker == nil {worker=makeWorker()}
            worker?.analyze(player)
            if let failure=worker?.failure {stop();failedKey=nextKey;status="Background AI unavailable: "+failure;return}
        }
        running=true
        status="Plugged in · AI analyzes the current position in the background."
    }
    func stop() {worker?.stop();worker=nil;running=false}
}
