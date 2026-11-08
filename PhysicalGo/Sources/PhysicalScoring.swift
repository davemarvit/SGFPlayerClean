import Foundation
import Combine

/// Reuses SGF Player's KataGo transport, ownership interpretation and scoring rules.
/// Analysis snapshots never modify recorded moves or declare a result automatically.
@MainActor final class PhysicalScoring:ObservableObject {
    @Published var presented=false
    @Published private(set) var busy=false
    @Published private(set) var error:String?
    @Published private(set) var estimate:AIPositionSummary?
    @Published var session:LocalScoringSession?
    @Published private(set) var ownership:[BoardPosition:AIOwnershipEstimate]=[:]
    @Published private(set) var likelyDead:[BoardPosition:Double]=[:]
    enum BoardDisplay:String,CaseIterable {case estimate="AI territory",counted="Final count"}
    @Published var boardDisplay:BoardDisplay = .estimate
    var showsCountedTerritory:Bool {finalReview && boardDisplay == .counted}
    @Published private(set) var finalReview=false
    @Published private(set) var accepted=false
    @Published private(set) var visits=0
    @Published private(set) var usesLivePosition=false
    enum Approval:String,CaseIterable {case prisoners="Prisoner totals",deadGroups="Dead groups",territory="Territory assignments",neutral="Unmarked neutral points"}
    @Published private(set) var approvedComponents:Set<Approval>=[]
    var requiredApprovals:[Approval] {Approval.allCases.filter {$0 != .prisoners || session?.rule.territoryScoring == true}}
    var pendingApprovals:[Approval] {requiredApprovals.filter {!approvedComponents.contains($0)}}
    var allApproved:Bool {!requiredApprovals.isEmpty && pendingApprovals.isEmpty}
    var partlyApproved:Bool {!allApproved && requiredApprovals.contains {approvedComponents.contains($0)}}
    var prisonersConfirmed:Bool {
        get {approvedComponents.contains(.prisoners)}
        set {setApproval(.prisoners,to:newValue)}
    }
    var markingsConfirmed:Bool {
        get {[Approval.deadGroups,.territory,.neutral].allSatisfy {approvedComponents.contains($0)}}
        set {for c in [Approval.deadGroups,.territory,.neutral] {setApproval(c,to:newValue)}}
    }
    func setApproval(_ component:Approval,to value:Bool) {
        guard !accepted,!busy,aiAvailable else {return}
        if value {approvedComponents.insert(component)} else {approvedComponents.remove(component)}
    }
    func approveAll(_ value:Bool) {
        guard !accepted,!busy,aiAvailable else {return}
        if value {approvedComponents.formUnion(requiredApprovals)} else {approvedComponents.removeAll()}
    }
    var approvalStatus:String {
        if accepted {return "Agreed result saved."}
        if busy {return "Wait for analysis to finish before approving."}
        if !aiAvailable {return "AI analysis is needed before approving."}
        if let issue=session?.issue {return issue}
        if allApproved {return "All details approved. Ready to save."}
        if pendingApprovals.count==1 {return "Approve \(pendingApprovals[0].rawValue.lowercased()) to save."}
        return "Approve all scoring details, or review the \(pendingApprovals.count) remaining components."
    }
    enum MarkingTool:String,CaseIterable {case deadGroups="Dead groups",blackTerritory="Black territory",whiteTerritory="White territory",neutral="Neutral point"}
    @Published var markingTool:MarkingTool = .deadGroups
    @Published private(set) var territoryCorrections:[BoardPosition:Occupancy]=[:]
    var countedTerritory:[BoardPosition:Stone] {
        guard let session else {return [:]}
        return Self.territoryProposal(session,ownership:ownership,corrections:territoryCorrections)
    }
    var countedResult:LocalScoreResult? {session?.result(territory:countedTerritory)}
    var unassignedEmptyPoints:Int {
        guard let session else {return 0}
        let counted=countedTerritory
        return (0..<session.board.size).reduce(0) {total,row in total+(0..<session.board.size).filter {col in
            let p=BoardPosition(row,col)
            return session.board.stones[p]==nil && counted[p]==nil
        }.count}
    }
    static func territoryProposal(_ session:LocalScoringSession,ownership:[BoardPosition:AIOwnershipEstimate],corrections:[BoardPosition:Occupancy]=[:])->[BoardPosition:Stone] {
        var result=ownership.mapValues(\.color)
        // Enclosed territory is directly countable without an AI confidence cutoff.
        for (p,c) in session.territory {result[p]=c}
        for p in session.deadStones {if let c=session.board.stones[p] {result[p]=c.opponent}}
        for p in session.neutralPoints {result.removeValue(forKey:p)}
        for (p,state) in corrections {result[p]=state.stone}
        return result.filter {p,_ in
            (0..<session.board.size).contains(p.row) && (0..<session.board.size).contains(p.col) &&
            (session.board.stones[p]==nil || session.deadStones.contains(p))
        }
    }
    var needsPrisonerConfirmation:Bool {session?.rule.territoryScoring == true && !prisonersConfirmed}
    var canAccept:Bool {finalReview && !busy && aiAvailable && !accepted && allApproved && countedResult != nil}
    var displayedScoreLead:Double? {
        estimate?.blackScoreLead
    }
    let background:PhysicalBackgroundAnalysis
    init(background:PhysicalBackgroundAnalysis? = nil) {self.background=background ?? PhysicalBackgroundAnalysis()}
    private var lastAnalysis:AIAnalysis?
    private var requestedVisits:Int {finalReview ? 1000:300}
    private var powerTimer:Timer?
    private var refreshPower:(()->Void)?
    func startMonitoring(recorder:GameRecorder,isLocal:@escaping ()->Bool,readPower:@escaping ()->PhysicalPowerSource=PhysicalPowerSource.current) {
        powerTimer?.invalidate()
        refreshPower = { [weak self,weak recorder] in
            guard let self,let recorder else {return}
            self.background.refresh(recorder:recorder,local:isLocal(),foreground:self.presented,
                                    power:readPower())
        }
        refreshPower?()
        let timer=Timer(timeInterval:1,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated {self?.refreshPower?()}
        }
        RunLoop.main.add(timer,forMode:.common);powerTimer=timer
    }
    func stopForOnlinePlay() {presented=false;cancel();background.stop()}
    func shutdown() {powerTimer?.invalidate();powerTimer=nil;refreshPower=nil;cancel();background.stop()}
    deinit {powerTimer?.invalidate()}
    private var engine:KataGoEngine?
    private var warmWorker:(any PhysicalBackgroundWorker)?
    private var task:Task<Void,Never>?
    private var sourceURL:URL?
    private var sourceMoves=0
    private var sourceRules:String?
    private var sourceKomi:String?
    private var sourcePositionKey=""
    private var generation=UUID()
    private var player=SGFPlayer()
    var aiAvailable:Bool {estimate != nil}
    func open(recorder:GameRecorder,analyzeImmediately:Bool=true) {
        guard recorder.canScorePosition else {return}
        let cached=background.cachedAnalysis(for:recorder)
        let warm=background.takeWorker(for:recorder)
        background.stop();cancel()
        finalReview=recorder.state == .finished;boardDisplay = .estimate
        recorder.pause();recorder.clock.pause("Clock paused for scoring")
        usesLivePosition=recorder.hasDeferredMoves;approvedComponents=[]
        territoryCorrections=[:];markingTool = .deadGroups
        let position=recorder.scoringGame
        player=SGFPlayer();player.load(game:position);player.seek(to:position.moves.count)
        sourcePositionKey=recorder.scoringPositionKey
        sourceURL=recorder.autosaveURL;sourceMoves=recorder.moveCount
        sourceRules=recorder.game.info.rules;sourceKomi=recorder.game.info.komi
        session=LocalScoringSession(player:player,handicap:recorder.game.handicap)
        if usesLivePosition {
            session?.capturesByBlack=recorder.knownPrisoners.black;session?.capturesByWhite=recorder.knownPrisoners.white
        }
        estimate=nil;lastAnalysis=nil;ownership=[:];likelyDead=[:];error=nil;accepted=false;visits=0;presented=true
        if let cached {receiveAnalysis(cached,allowInProgress:true)}
        // A continuous-search snapshot is already a valid score proposal. Do
        // not discard it merely because KataGo was still searching on AC.
        if analyzeImmediately && (!aiAvailable || visits<requestedVisits) {
            if let warm {continueSearch(warm)} else {analyze()}
        } else {warm?.stop()}
    }
    func reviewFinal(recorder:GameRecorder) {
        guard matches(recorder),recorder.pendingMoveCount==0 else {return}
        recorder.finish()
        guard recorder.state == .finished else {error=recorder.status;return}
        finalReview=true
        if let lastAnalysis {receiveAnalysis(lastAnalysis,allowInProgress:true)}
        if !aiAvailable || visits<requestedVisits {analyze()}
    }
    private func matches(_ recorder:GameRecorder)->Bool {
        recorder.scoringPositionKey==sourcePositionKey && recorder.autosaveURL==sourceURL && recorder.moveCount==sourceMoves &&
        recorder.game.info.rules==sourceRules && recorder.game.info.komi==sourceKomi
    }
    private func continueSearch(_ worker:any PhysicalBackgroundWorker) {
        warmWorker=worker;busy=true
        let identity=UUID();generation=identity
        let index=player.currentIndex,target=requestedVisits
        task=Task { @MainActor [weak self] in
            let began=ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self,self.generation==identity else {return}
                if let result=worker.analysis(at:index),let root=result.rootInfo,
                   root.visits>=target,self.receiveAnalysis(result,allowInProgress:true) {
                    self.busy=false;worker.stop();self.warmWorker=nil;return
                }
                if let failure=worker.failure {
                    self.error=failure;self.busy=false;worker.stop();self.warmWorker=nil;return
                }
                if ProcessInfo.processInfo.systemUptime-began>120 {
                    self.error="AI scoring timed out. Close and try again.";self.busy=false;worker.stop();self.warmWorker=nil;return
                }
                do {try await Task.sleep(nanoseconds:100_000_000)} catch {return}
            }
        }
    }
    private func analyze() {
        task?.cancel();warmWorker?.stop();warmWorker=nil;engine?.stop();busy=true;error=nil
        guard let session,session.issue==nil else {busy=false;error=session?.issue ?? "No scoring position.";return}
        let identity=UUID();generation=identity
        let worker=Self.makeWorker()
        engine=worker
        worker.currentGameId="physical-score-"+identity.uuidString
        worker.start()
        guard worker.isEngineRunning else {busy=false;error=worker.engineStartupError ?? "Could not start the local AI.";return}
        let payload=player.getCurrentAIPayload(),index=player.currentIndex
        let settings=player.analysisSettings
        worker.analyzeGame(id:worker.currentGameId,initialStones:payload.initial,moves:payload.moves,size:player.board.size,
                           maxVisits:requestedVisits,settings:settings,requireOwnership:true)
        task=Task { @MainActor [weak self] in
            let began=ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self,self.generation==identity else {return}
                if let analysis=worker.currentAnalysisData[index],self.receiveAnalysis(analysis) {
                    self.busy=false;worker.stop();return
                }
                if let error=worker.analysisError ?? worker.engineStartupError {
                    self.error=error;self.busy=false;worker.stop();return
                }
                if ProcessInfo.processInfo.systemUptime-began>120 {
                    self.error="AI scoring timed out. Close and try again.";self.busy=false;worker.stop();return
                }
                do {try await Task.sleep(nanoseconds:100_000_000)} catch {return}
            }
        }
    }
    @discardableResult func receiveAnalysis(_ analysis:AIAnalysis,allowInProgress:Bool=false)->Bool {
        guard (allowInProgress || analysis.isDuringSearch != true),let root=analysis.rootInfo,root.visits>0,
              let summary=AIPositionSummary(root:root,playerToMove:player.turn),
              analysis.ownership?.count==player.board.size*player.board.size else {return false}
        approvedComponents=[]
        lastAnalysis=analysis;estimate=summary;visits=root.visits
        ownership=AILikelyDeadStones.ownershipEstimates(analysis:analysis,size:player.board.size,playerToMove:player.turn)
        likelyDead=AILikelyDeadStones.strengths(analysis:analysis,stones:player.board.stones,size:player.board.size,playerToMove:player.turn)
        background.remember(analysis,positionKey:sourcePositionKey)
        if finalReview || usesLivePosition {applySuggestions(analysis)}
        return true
    }
    static func makeWorker()->KataGoEngine {
        let defaults=UserDefaults(suiteName:"com.davemarvit.SGFPlayerClean")
        let executable=URL(fileURLWithPath:defaults?.string(forKey:"customKataGoPath") ?? "/opt/homebrew/bin/katago")
        let configuredModel=defaults?.string(forKey:"customAIModelPath").map {URL(fileURLWithPath:$0)}
        let model=configuredModel.flatMap {FileManager.default.fileExists(atPath:$0.path) ? $0:nil}
            ?? Bundle.main.url(forResource:"kata1-b18",withExtension:"bin.gz")
            ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SGFPlayerClean/Resources/kata1-b18.bin.gz")
        let config=Bundle.main.url(forResource:"analysis",withExtension:"cfg")
            ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SGFPlayerClean/Resources/analysis.cfg")
        let cache=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("Physical Go/Scoring")
        return KataGoEngine(executableURL:executable,modelURL:model,configURL:config,cacheDirectory:cache,legacyImportDirectories:[])
    }
    static func suggestedSession(_ original:LocalScoringSession,analysis:AIAnalysis,playerToMove:Stone)->LocalScoringSession {
        var proposed=original
        proposed.neutralPoints=[]
        let strengths=AILikelyDeadStones.strengths(analysis:analysis,stones:original.board.stones,size:original.board.size,playerToMove:playerToMove)
        // These are reviewable proposals, not declarations of death. Require the
        // whole group's opposing ownership minus search spread to exceed 0.5.
        // In the shared strength scale that is >0.15. Requiring >=0.8 hid
        // many groups whose loss was already assumed in the AI score estimate.
        proposed.deadStones=Set(strengths.filter {$0.value>0.15}.map(\.key))
        // Ownership near zero or opposite the enclosing stones may be seki or unsettled.
        // Exclude those regions from the proposal; players can restore them on the board.
        if let ownership=analysis.ownership,ownership.count==original.board.size*original.board.size {
            for region in proposed.regions {
                guard let owner=region.owner,!region.points.isEmpty else {continue}
                let values=region.points.map {ownership[$0.row*original.board.size+$0.col]*(owner==playerToMove ? 1:-1)}
                if values.reduce(0,+)/Double(values.count)<0.6 {proposed.neutralPoints.formUnion(region.points)}
            }
        }
        return proposed
    }
    private func applySuggestions(_ analysis:AIAnalysis) {
        guard let original=session else {return}
        session=Self.suggestedSession(original,analysis:analysis,playerToMove:player.turn)
    }
    func toggle(_ point:BoardPosition) {
        guard finalReview,!busy,!accepted else {return}
        guard let current=session,(0..<current.board.size).contains(point.row),(0..<current.board.size).contains(point.col) else {return}
        if markingTool == .deadGroups {
            guard current.board.stones[point] != nil else {return}
            session?.toggleDeadGroup(at:point)
            approvedComponents.remove(.deadGroups)
        } else {
            guard current.board.stones[point]==nil || current.deadStones.contains(point) else {return}
            let state:Occupancy = markingTool == .blackTerritory ? .black : markingTool == .whiteTerritory ? .white : .empty
            let existing=countedTerritory[point]
            guard state.stone != existing else {return}
            territoryCorrections[point]=state
            approvedComponents.remove(markingTool == .neutral ? .neutral:.territory)
        }
    }
    func accept(recorder:GameRecorder) {
        guard canAccept else {error=approvalStatus;return}
        guard matches(recorder),let session,let result=countedResult else {
            error="The game or scoring details changed. Close scoring and try again.";return
        }
        let difference=result.black.total-result.white.total
        var info=recorder.game.info
        info.result=difference==0 ? "0":"\(difference>0 ? "B":"W")+\(Self.points(abs(difference)))"
        recorder.updateInfo(info)
        guard recorder.saveError==nil else {error=recorder.saveError;return}
        recorder.noteScoredPosition(session.board)
        if let failure=recorder.reviewSaveError {error=failure;return}
        if let url=recorder.autosaveURL {
            let report:[String:Any]=["move":sourceMoves,"result":info.result!,"rules":info.rules ?? "","komi":info.komi ?? "",
                "blackTotal":result.black.total,"whiteTotal":result.white.total,"aiVisits":visits,
                "deadStones":session.deadStones.map {[$0.row,$0.col]},"neutralPoints":session.neutralPoints.map {[$0.row,$0.col]},
                "territory":countedTerritory.map { ["row":$0.key.row,"col":$0.key.col,"color":$0.value.rawValue] },
                "territoryCorrections":territoryCorrections.map { ["row":$0.key.row,"col":$0.key.col,"state":$0.value.rawValue] },
                "markingsConfirmed":markingsConfirmed,"approvedComponents":requiredApprovals.map(\.rawValue),"unassignedEmptyPoints":unassignedEmptyPoints,
                "livePosition":DeferredMoveHistory.states(session.board).map(\.rawValue),
                "reviewsOutstanding":recorder.reviewHistory.unresolved,"prisonersConfirmed":prisonersConfirmed,
                "capturesByBlack":session.capturesByBlack,"capturesByWhite":session.capturesByWhite,
                "confirmedAt":Date().timeIntervalSince1970]
            do {try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]).write(to:url.deletingPathExtension().appendingPathExtension("score.json"),options:.atomic)}
            catch {self.error="Result saved in SGF, but scoring details could not be saved: \(error.localizedDescription)"}
        }
        accepted=true
    }
    func setPrisoners(black:Int,white:Int) {
        guard !accepted,!busy,let current=session,(0...10000).contains(black),(0...10000).contains(white),current.capturesByBlack != black || current.capturesByWhite != white else {return}
        session?.capturesByBlack=black;session?.capturesByWhite=white;approvedComponents.remove(.prisoners)
    }
    static func points(_ value:Double)->String {String(format:value.rounded()==value ? "%.0f":"%.1f",locale:Locale(identifier:"en_US_POSIX"),value)}
    func cancel() {warmWorker?.stop();warmWorker=nil;task?.cancel();task=nil;engine?.stop();engine=nil;busy=false;generation=UUID()}
}
