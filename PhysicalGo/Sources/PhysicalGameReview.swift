import Foundation
import Combine

@MainActor protocol PhysicalReviewWorker:AnyObject {
    var failure:String? {get}
    func load(game:SGFPlayer,id:String,relatedIDs:[String])
    func analysis(at turn:Int)->AIAnalysis?
    func submit(game:SGFPlayer,turn:Int,visits:Int)
    func stop()
}

@MainActor private final class PhysicalReviewKataGoWorker:PhysicalReviewWorker {
    let engine=PhysicalScoring.makeWorker()
    var failure:String? {engine.analysisError ?? engine.engineStartupError}
    func load(game:SGFPlayer,id:String,relatedIDs:[String]) {
        engine.loadAnalysisCache(for:id,game:game,reusing:relatedIDs)
    }
    func analysis(at turn:Int)->AIAnalysis? {engine.currentAnalysisData[turn]}
    func submit(game:SGFPlayer,turn:Int,visits:Int) {
        if !engine.isEngineRunning {engine.start()}
        let payload=game.getAIPayload(at:turn)
        engine.analyzeGame(id:engine.currentGameId,initialStones:payload.initial,moves:payload.moves,
                           size:game.board.size,maxVisits:visits,settings:game.analysisSettings)
    }
    func stop() {engine.stop()}
}

/// A bounded, cancellable history sweep. It never seeks or edits the recorder.
@MainActor final class PhysicalGameReview:ObservableObject {
    struct Point:Identifiable {
        let turn:Int
        let summary:AIPositionSummary
        let segment:Int
        var id:Int {turn}
    }
    @Published private(set) var analyses:[Int:AIAnalysis]=[:]
    @Published private(set) var busy=false
    @Published private(set) var error:String?
    @Published private(set) var unavailableReason:String?
    @Published private(set) var totalMoves=0
    @Published private(set) var analyzingTurn:Int?
    private var player=SGFPlayer()
    private var cacheID=""
    private var relatedIDs:[String]=[]
    private var worker:(any PhysicalReviewWorker)?
    private var task:Task<Void,Never>?
    private var generation=UUID()
    private let makeWorker:()->any PhysicalReviewWorker
    let minimumVisits=100
    init(makeWorker:(()->any PhysicalReviewWorker)?=nil) {
        self.makeWorker=makeWorker ?? {PhysicalReviewKataGoWorker()}
    }
    var evaluations:[MoveEvaluation] {
        AIGameQuality.evaluate(analyses:analyses,upTo:totalMoves,engine:player).values.sorted {$0.turn<$1.turn}
    }
    func performance(_ color:Stone)->AIPlayerPerformance {
        AIPlayerPerformance(player:color,evaluations:evaluations,analyses:analyses)
    }
    func moveCount(_ color:Stone)->Int {(0..<totalMoves).filter {player.moveColor(at:$0)==color}.count}
    var points:[Point] {
        var result:[Point]=[],segment=0,previous = -1
        for turn in analyses.keys.sorted() {
            guard let root=analyses[turn]?.rootInfo,
                  let summary=AIPositionSummary(root:root,playerToMove:player.playerToMove(at:turn)) else {continue}
            if turn != previous+1 {segment += 1}
            result.append(Point(turn:turn,summary:summary,segment:segment));previous=turn
        }
        return result
    }
    var coverage:String {"\(evaluations.count) of \(totalMoves) moves analyzed"}
    var complete:Bool {totalMoves>0 && evaluations.count==totalMoves}
    func prepare(game:SGFGame,cacheID:String,relatedIDs:[String]=[],unavailableReason:String?=nil) {
        cancel();analyses=[:];error=nil;self.unavailableReason=unavailableReason
        player=SGFPlayer();player.load(game:game);totalMoves=game.moves.count
        self.cacheID=cacheID;self.relatedIDs=relatedIDs
    }
    func receive(_ incoming:[Int:AIAnalysis]) {
        guard unavailableReason==nil else {return}
        var next=analyses
        for (turn,analysis) in incoming {
            guard (0...totalMoves).contains(turn),analysis.turnNumber==turn,
                  let root=analysis.rootInfo,root.visits>=minimumVisits,
                  AIPositionSummary(root:root,playerToMove:player.playerToMove(at:turn)) != nil,
                  root.visits>=(next[turn]?.rootInfo?.visits ?? 0) else {continue}
            next[turn]=analysis
        }
        analyses=next
    }
    func start() {
        guard !busy,unavailableReason==nil,totalMoves>0 else {return}
        cancel();error=nil
        let worker=makeWorker();self.worker=worker
        worker.load(game:player,id:cacheID,relatedIDs:relatedIDs)
        receive(Dictionary(uniqueKeysWithValues:(0...totalMoves).compactMap {turn in worker.analysis(at:turn).map {(turn,$0)}}))
        let missing=(0...totalMoves).filter {analyses[$0]==nil}
        guard !missing.isEmpty else {worker.stop();self.worker=nil;return}
        busy=true
        let identity=generation
        task=Task { @MainActor [weak self] in
            guard let self else {return}
            for turn in missing {
                guard !Task.isCancelled,self.generation==identity else {return}
                self.analyzingTurn=turn
                worker.submit(game:self.player,turn:turn,visits:self.minimumVisits)
                let began=ProcessInfo.processInfo.systemUptime
                while !Task.isCancelled,self.generation==identity {
                    if let value=worker.analysis(at:turn) {self.receive([turn:value])}
                    if self.analyses[turn] != nil {break}
                    if let failure=worker.failure {self.finish(error:failure);return}
                    if ProcessInfo.processInfo.systemUptime-began>125 {self.finish(error:"Game analysis timed out. Retry to continue.");return}
                    do {try await Task.sleep(nanoseconds:100_000_000)} catch {return}
                }
            }
            guard !Task.isCancelled,self.generation==identity else {return}
            self.finish(error:nil)
        }
    }
    private func finish(error:String?) {
        self.error=error;worker?.stop();worker=nil;task=nil;busy=false;analyzingTurn=nil
    }
    func cancel() {
        generation=UUID();task?.cancel();task=nil;worker?.stop();worker=nil;busy=false;analyzingTurn=nil
    }
}
