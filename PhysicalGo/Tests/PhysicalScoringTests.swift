import Foundation

@MainActor func runPhysicalScoringTests() async throws {
    try runPhysicalPowerTests()
    try await runScoringHandoffTests()
    if ProcessInfo.processInfo.environment["PHYSICAL_GO_SCORING_POLICY_ONLY"] == "1" {return}
    var checks=0
    func check(_ value:Bool,_ reason:String) {checks += 1;precondition(value,reason)}
    var game=SGFGame();game.boardSize=9;game.info=SGFGame.Info(komi:"6.5",rules:"Japanese")
    game.setup=[(.black,0,0),(.black,1,0),(.white,8,8)];game.initialPlayer = .black
    let player=SGFPlayer();player.load(game:game)
    let session=LocalScoringSession(player:player,handicap:0)
    var ownership=Array(repeating:0.0,count:81);ownership[0] = -1;ownership[1] = -1;ownership[80] = -1
    let analysis=AIAnalysis(id:"test",isDuringSearch:false,turnNumber:0,moveInfos:[],rootInfo:.init(winrate:0.1,scoreLead:-8.5,visits:100),ownership:ownership)
    let proposed=PhysicalScoring.suggestedSession(session,analysis:analysis,playerToMove:.black)
    check(proposed.deadStones==Set([BoardPosition(0,0),BoardPosition(0,1)]),"AI marked living group or failed to mark whole dead group")
    check(proposed.result?.white.total==8.5 && proposed.result?.black.total==0,"Territory/komi/dead prisoners counted incorrectly")
    var reviewed=proposed;reviewed.toggleDeadGroup(at:BoardPosition(0,0))
    check(reviewed.deadStones.isEmpty,"Player correction did not revive whole group")
    game.info.rules="Chinese";player.load(game:game)
    let area=LocalScoringSession(player:player,handicap:0)
    check(area.result?.black.total==2 && area.result?.white.total==7.5,"Area scoring differs from stones plus komi")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("physical-score-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let recorder=GameRecorder(storage:directory);recorder.clock.audible=false
    recorder.start(size:9,info:SGFGame.Info(komi:"6.5",rules:"Japanese"));recorder.pause();recorder.pass();recorder.pass()
    let scoring=PhysicalScoring();scoring.open(recorder:recorder)
    let began=ProcessInfo.processInfo.systemUptime
    while scoring.busy && ProcessInfo.processInfo.systemUptime-began<125 {try await Task.sleep(nanoseconds:100_000_000)}
    check(scoring.error==nil,"Real KataGo failed: \(scoring.error ?? "unknown")")
    check(scoring.aiAvailable && scoring.visits>0 && scoring.finalReview,"Real AI did not provide final proposal")
    check(recorder.game.info.result==nil,"AI silently declared a result")
    check(!scoring.canAccept,"AI markings were accepted without agreement")
    scoring.approveAll(true)
    scoring.accept(recorder:recorder)
    check(scoring.accepted && recorder.game.info.result=="W+6.5","Confirmed result not saved")
    let saved=SGFGame.from(tree:try SGFParser.parse(text:String(contentsOf:recorder.autosaveURL!)))
    check(saved.info.result=="W+6.5" && saved.moves.count==2,"SGF result or move history wrong")
    check(FileManager.default.fileExists(atPath:recorder.autosaveURL!.deletingPathExtension().appendingPathExtension("score.json").path),"Scoring review not archived")
    scoring.cancel()
    let ongoing=GameRecorder(storage:directory);ongoing.clock.audible=false
    ongoing.start(size:9,info:SGFGame.Info(komi:"6.5",rules:"Chinese"));ongoing.pause()
    let liveBackground=PhysicalBackgroundAnalysis()
    liveBackground.refresh(recorder:ongoing,local:true,foreground:false,power:.external)
    let backgroundStart=ProcessInfo.processInfo.systemUptime
    while liveBackground.cachedAnalysis(for:ongoing)?.rootInfo==nil && ProcessInfo.processInfo.systemUptime-backgroundStart<120 {
        try await Task.sleep(nanoseconds:100_000_000)
    }
    check(liveBackground.cachedAnalysis(for:ongoing)?.rootInfo != nil,"Real continuous background analysis returned no estimate")
    liveBackground.refresh(recorder:ongoing,local:true,foreground:false,power:.battery)
    check(!liveBackground.running,"Real background worker did not stop on simulated battery transition")
    scoring.startMonitoring(recorder:ongoing,isLocal:{true},readPower:{.battery})
    scoring.open(recorder:ongoing)
    let start=ProcessInfo.processInfo.systemUptime
    while scoring.busy && ProcessInfo.processInfo.systemUptime-start<125 {try await Task.sleep(nanoseconds:100_000_000)}
    check(scoring.error==nil && scoring.aiAvailable && !scoring.finalReview,"In-progress estimate failed")
    check(ongoing.state == .paused && ongoing.game.info.result==nil,"Estimate ended game or wrote result")
    check(!scoring.background.running,"Explicit scoring on battery started continuous analysis")
    scoring.shutdown()
    print("PASS: \(checks) AI scoring checks, including live KataGo estimates/final review, dead-group correction, Japanese/Chinese arithmetic, explicit result confirmation and saved SGF/report")
}

@MainActor private final class FakePhysicalBackgroundWorker:PhysicalBackgroundWorker {
    var failure:String?
    var stopped=false
    var submitted:[Int]=[]
    var results:[Int:AIAnalysis]=[:]
    func analyze(_ player:SGFPlayer) {submitted.append(player.currentIndex)}
    func analysis(at index:Int)->AIAnalysis? {results[index]}
    func stop() {stopped=true}
}

@MainActor private func runPhysicalPowerTests() throws {
    var checks=0
    func check(_ value:Bool,_ reason:String) {checks += 1;precondition(value,reason)}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("physical-power-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:directory)}
    let recorder=GameRecorder(storage:directory);recorder.clock.audible=false
    recorder.start(size:9,info:SGFGame.Info(komi:"6.5",rules:"Japanese"));recorder.pause()
    var workers:[FakePhysicalBackgroundWorker]=[]
    let background=PhysicalBackgroundAnalysis(makeWorker:{let worker=FakePhysicalBackgroundWorker();workers.append(worker);return worker})
    func update(_ power:PhysicalPowerSource,local:Bool=true,foreground:Bool=false) {
        background.refresh(recorder:recorder,local:local,foreground:foreground,power:power)
    }
    update(.battery);update(.unknown)
    check(workers.isEmpty && !background.running,"Battery/unknown power started automatic AI")
    update(.external)
    check(workers.count==1 && background.running && workers[0].submitted==[0],"External power did not start continuous current-position analysis")
    update(.external)
    check(workers.count==1 && workers[0].submitted==[0],"Unchanged position restarted AI")
    let result=AIAnalysis(id:"warm",isDuringSearch:true,turnNumber:0,moveInfos:[],rootInfo:.init(winrate:0.5,scoreLead:0,visits:150),ownership:Array(repeating:0,count:81))
    workers[0].results[0]=result
    update(.battery)
    check(workers[0].stopped && !background.running,"Unplugging left worker running")
    check(background.cachedAnalysis(for:recorder)?.rootInfo?.visits==150,"Unplugging discarded warm estimate")
    update(.external)
    check(workers.count==2 && background.running,"Reconnecting power did not resume analysis")
    workers[1].results[0]=AIAnalysis(id:"restarted",isDuringSearch:true,turnNumber:0,moveInfos:[],rootInfo:.init(winrate:0.5,scoreLead:0,visits:10),ownership:Array(repeating:0,count:81))
    update(.external)
    check(background.cachedAnalysis(for:recorder)?.rootInfo?.visits==150,"Fresh search replaced the stronger cached result")
    update(.external,foreground:true)
    check(workers[1].stopped && !background.running,"Background competed with requested score")
    update(.external)
    check(workers.count==3,"Closing scoring did not resume background")
    update(.external,local:false)
    check(workers[2].stopped && !background.running,"Online mode left local AI running")
    update(.external)
    recorder.pass()
    update(.external)
    check(workers.count==4 && workers[3].submitted==[0,1],"New position did not update existing worker")
    check(background.cachedAnalysis(for:recorder)==nil,"New move reused previous position's estimate")
    workers[3].failure="Fixture failure"
    update(.external);update(.external)
    check(workers[3].stopped && workers.count==4 && !background.running,"Engine failure caused busy retry loop")
    update(.battery);update(.external)
    check(workers.count==5,"Power cycle did not allow recovery from worker failure")
    var info=recorder.game.info;info.komi="7.5";recorder.updateInfo(info);update(.external)
    check(workers[4].submitted==[1,1],"Komi change did not refresh analysis")
    recorder.finish();update(.external)
    check(workers[4].stopped && !background.running,"Finished game kept background worker alive")
    let capturedURL=directory.appendingPathComponent("captures.sgf")
    try "(;GM[1]FF[4]AP[PhysicalGo:0.82]SZ[9]RU[Japanese]KM[6.5];B[ba];W[aa];B[ab])".write(to:capturedURL,atomically:true,encoding:.utf8)
    let restored=GameRecorder(storage:directory);restored.clock.audible=false
    try restored.restoreSavedGame(from:capturedURL)
    let player=SGFPlayer();player.load(game:restored.game);player.seek(to:restored.moveCount)
    let score=LocalScoringSession(player:player,handicap:0)
    check(score.capturesByBlack==1 && score.capturesByWhite==0,"Saved move history lost capture counts with AI off")
    check(player.board.stones[BoardPosition(0,0)]==nil && restored.moveCount==3,"Capture replay did not remove captured stone")
    print("PASS: \(checks) power-aware analysis checks (battery/unknown/AC, unplug/replug, foreground scoring, online mode, position/komi changes, failures, end game, captured-stone replay)")
}


@MainActor private func runScoringHandoffTests() async throws {
    let recorder=GameRecorder(storage:nil);recorder.clock.audible=false
    recorder.start(size:9,info:SGFGame.Info(komi:"6.5",rules:"Japanese"));recorder.pause()
    let worker=FakePhysicalBackgroundWorker()
    let background=PhysicalBackgroundAnalysis(makeWorker:{worker})
    background.refresh(recorder:recorder,local:true,foreground:false,power:.external)
    func analysis(_ visits:Int)->AIAnalysis {
        .init(id:"warm",isDuringSearch:true,turnNumber:0,moveInfos:[],rootInfo:.init(winrate:0.5,scoreLead:-6.5,visits:visits),ownership:Array(repeating:0,count:81))
    }
    worker.results[0]=analysis(1400)
    let key=recorder.scoringPositionKey
    var info=recorder.game.info;info.playerBlack="Test";info.result="W+R";recorder.updateInfo(info)
    precondition(recorder.scoringPositionKey==key,"Names or resignation invalidated Go analysis")
    recorder.finish()
    background.refresh(recorder:recorder,local:true,foreground:false,power:.external)
    let scoring=PhysicalScoring(background:background);scoring.open(recorder:recorder)
    precondition(!scoring.busy && scoring.aiAvailable && scoring.visits==1400 && !scoring.canAccept,"Finished game discarded warm ownership or started fresh analysis")
    precondition(recorder.game.info.result=="W+R","Opening scoring replaced resignation")
    scoring.shutdown()
    // A partially searched position transfers the same worker to Score game.
    let ongoing=GameRecorder(storage:nil);ongoing.clock.audible=false
    ongoing.start(size:9,info:SGFGame.Info(komi:"6.5",rules:"Japanese"));ongoing.pause()
    let warm=FakePhysicalBackgroundWorker()
    let bg=PhysicalBackgroundAnalysis(makeWorker:{warm})
    bg.refresh(recorder:ongoing,local:true,foreground:false,power:.external)
    warm.results[0]=analysis(100)
    let live=PhysicalScoring(background:bg);live.open(recorder:ongoing)
    precondition(live.busy && live.visits==100 && live.aiAvailable && !warm.stopped && !bg.running,"Partial cache was hidden or warm worker was restarted")
    warm.results[0]=analysis(350)
    try await Task.sleep(nanoseconds:250_000_000)
    precondition(!live.busy && live.visits==350 && warm.stopped,"Transferred continuous search failed to complete")
    live.cancel();live.presented=false;live.open(recorder:ongoing)
    precondition(!live.busy && live.visits==350,"Reopening scoring discarded the completed explicit search")
    live.shutdown()
    // An unconfirmed new stone does not stop the previous position's search.
    let pending=GameRecorder(storage:nil);pending.clock.audible=false;pending.start(size:9,info:SGFGame.Info(komi:"6.5",rules:"Japanese"))
    func view(_ stone:Bool)->BoardObservation {.init(readings:(0..<81).map {.init(row:$0/9,col:$0%9,occupancy:stone && $0==40 ? .black:.empty,confidence:1,delta:0)},size:9)}
    for i in 0..<5 {pending.consume(view(false),now:Double(i)*0.21)}
    let held=FakePhysicalBackgroundWorker(),hold=PhysicalBackgroundAnalysis(makeWorker:{held})
    hold.refresh(recorder:pending,local:true,foreground:false,power:.external)
    pending.consume(view(true),now:1.1)
    precondition(pending.pendingMoveCount==1,"Pending search fixture did not produce a tentative stone")
    hold.refresh(recorder:pending,local:true,foreground:false,power:.external)
    precondition(!held.stopped && held.submitted==[0],"Camera confirmation gap tore down the AI")
    hold.refresh(recorder:pending,local:true,foreground:false,power:.battery)
    precondition(held.stopped,"Pending move prevented battery shutdown")
    print("PASS: cached final ownership, metadata/resignation identity, partial-cache display, warm-worker transfer, pending-move retention and battery shutdown")
}
