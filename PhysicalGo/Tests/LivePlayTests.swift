import AppKit
import SwiftUI

@main struct LivePlayTests {
    @MainActor static func main() async throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ ok:Bool,_ reason:String) {checks += 1;precondition(ok,reason)}
        func close(_ a:Double,_ b:Double)->Bool {abs(a-b)<0.0001}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("physical-live-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        func render<V:View>(_ value:V,_ name:String,width:CGFloat,height:CGFloat) async throws {
            let host=NSHostingView(rootView:value.background(Color(nsColor:.windowBackgroundColor)))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled],backing:.buffered,defer:false)
            window.appearance=NSAppearance(named:.darkAqua);host.appearance=window.appearance
            window.contentView=host;window.orderFront(nil)
            try await Task.sleep(nanoseconds:200_000_000);host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
            let output=URL(fileURLWithPath:"/Users/Dave/Documents/SGF PLayer/work/physical-live-play")
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"));window.orderOut(nil)
        }
        // Clock presses have their own identity, independent of SGF numbering.
        for kind in [LocalClockSettings.Kind.absolute,.fischer,.byoyomi,.canadian,.simple] {
            let clock=LocalGameClock();clock.audible=false
            let overtime=[LocalClockSettings.Kind.byoyomi,.canadian].contains(kind)
            let settings=LocalClockSettings(kind:kind,mainSeconds:overtime ? 0:100,periodSeconds:30,periods:5,incrementSeconds:10,maximumSeconds:200,stonesPerPeriod:5)
            clock.configure(settings,blackToPlay:true);clock.ready(at:0)
            let original=clock.engine.black.remaining
            clock.followLiveTurn(.white,at:2)
            check(clock.running && !clock.requiresReview && !clock.engine.blackToPlay,"Order-only gap stopped \(kind)")
            check(close(clock.engine.black.remaining,original-2),"Gap invented a clock reset or increment")
            let id=UUID();clock.recordLiveMove(id:id,black:false,at:5,observedAt:4)
            check(clock.running && clock.engine.blackToPlay && clock.liveEvents.count==1,"Observed live press did not switch \(kind)")
            let whiteExpected=kind == .fischer ? 108.0 : [.simple,.byoyomi].contains(kind) ? 30.0 : kind == .canadian ? 28.0:98.0
            check(close(clock.engine.white.remaining,whiteExpected) && close(clock.engine.black.remaining,original-3),"Live press lost overtime/increment or recognition latency for \(kind)")
            if kind == .canadian {check(clock.engine.white.stones==4 && clock.engine.black.stones==5,"Gap invented Canadian presses")}
            let before=clock.engine
            clock.recordLiveMove(id:id,black:false,at:5,observedAt:4)
            check(clock.engine==before,"Duplicate event charged time twice")
            clock.pause(at:5);let paused=clock.engine
            clock.finalizeLiveHistory(mapping:[id:4],moveCount:4,blackToPlay:true)
            check(clock.engine==paused && !clock.requiresReview,"Resolving history changed the clocks")
            check(clock.sgfMoveProperties(4)["WL"] != nil,"Live press was not associated with its finalized SGF move")
            clock.finalizeLiveHistory(mapping:[id:4],moveCount:4,blackToPlay:true)
            check(clock.moves.count==1,"Finalization duplicated the clock press")
        }
        let ambiguous=LocalGameClock();ambiguous.audible=false
        ambiguous.configure(.init(kind:.absolute,mainSeconds:100),blackToPlay:true);ambiguous.ready(at:0)
        ambiguous.followLiveTurn(nil,at:3)
        check(ambiguous.awaitingTurn && !ambiguous.running && !ambiguous.requiresReview,"Unknown turn did not request a lightweight confirmation")
        ambiguous.followLiveTurn(.white,at:20,resumeIfReady:true)
        check(ambiguous.running && !ambiguous.awaitingTurn && ambiguous.engine.black.remaining==97 && ambiguous.engine.white.remaining==100,"Turn confirmation invented missing elapsed time")
        ambiguous.pause(at:21);ambiguous.followLiveTurn(.black,at:22,resumeIfReady:true)
        check(!ambiguous.running,"Turn inference overrode an explicit Pause")
        let late=LocalGameClock();late.audible=false;late.configure(.init(kind:.absolute,mainSeconds:3),blackToPlay:true);late.ready(at:0)
        late.followLiveTurn(.black,at:1);late.tick(at:4)
        late.recordLiveMove(id:UUID(),black:true,at:4,observedAt:2)
        check(late.running && late.engine.black.remaining==1 && late.engine.white.remaining==1,"Delayed confirmation lost a witnessed on-time live move")

        var now=ProcessInfo.processInfo.systemUptime+10
        func observation(_ board:BoardSnapshot)->BoardObservation {
            BoardObservation(readings:DeferredMoveHistory.states(board).enumerated().map{.init(row:$0.offset/board.size,col:$0.offset%board.size,occupancy:$0.element,confidence:1,delta:0)},size:board.size)
        }
        func feed(_ r:GameRecorder,_ board:BoardSnapshot) {for _ in 0..<7 {now += 0.21;r.consume(observation(board),now:now)}}
        func gap(_ rules:String="Japanese")->(GameRecorder,SGFPlayer,[BoardPosition]) {
            let r=GameRecorder(storage:folder);r.clock.audible=false
            r.start(size:9,info:.init(komi:"6.5",rules:rules),clockSettings:.init(kind:.fischer,mainSeconds:100,incrementSeconds:10,maximumSeconds:200))
            feed(r,r.positions[0]);let actual=SGFPlayer();actual.load(game:r.game)
            let order=[BoardPosition(0,0),BoardPosition(8,8),BoardPosition(0,1)]
            for p in order {check(actual.tryPlayMove(color:actual.turn,x:p.col,y:p.row)==nil,"Bad gap fixture")}
            feed(r,actual.board)
            check(r.hasDeferredMoves && r.moveCount==0 && r.liveNextPlayer == .white,"Gap lost the live position or next player")
            check(r.clock.running && r.state == .recording,"Order-only gap interrupted play")
            return (r,actual,order)
        }
        let (r,actual,order)=gap()
        r.pause()
        let oddRestart=GameRecorder(storage:folder);oddRestart.clock.audible=false
        try oddRestart.restoreSavedGame(from:r.autosaveURL!)
        check(oddRestart.nextPlayer == .black && oddRestart.liveNextPlayer == .white && !oddRestart.clock.engine.blackToPlay && oddRestart.clock.saveError==nil,"Live turn could not differ from the SGF turn after restart")
        r.resume();feed(r,actual.board)
        try await render(VStack {LocalClockPanel(clock:r.clock,recorder:r);ReviewQueueRail(recorder:r,onReview:{_ in})}.padding(),"live-clock",width:1100,height:760)
        let key=r.scoringPositionKey
        check(actual.tryPlayMove(color:.white,x:7,y:8)==nil,"Bad continuation")
        feed(r,actual.board)
        check(r.clock.running && r.clock.engine.blackToPlay && r.clock.liveEvents.count==1 && r.moveCount==0,"Later move waited for SGF before switching clock")
        check(r.scoringPositionKey != key,"Live AI cache key stayed at the saved prefix")
        let scorePlayer=SGFPlayer();scorePlayer.load(game:r.scoringGame)
        check(scorePlayer.board==actual.board && scorePlayer.getCurrentAIPayload().initial.count==4,"Scoring payload omitted unsaved live stones")
        r.pause();let times=(r.clock.engine.black,r.clock.engine.white)
        let restored=GameRecorder(storage:folder);restored.clock.audible=false;try restored.restoreSavedGame(from:r.autosaveURL!)
        check(restored.clock.saveError==nil && restored.clock.engine.black==times.0 && restored.clock.engine.white==times.1,"Live clocks failed restart against the shorter SGF")
        check(restored.hasDeferredMoves && !restored.clock.running && restored.clock.liveEvents.count==1,"Restart discarded live presses or automatically resumed")
        restored.resume();feed(restored,actual.board)
        check(restored.clock.running,"Live recording could not resume while reviews remained")
        // A stable, contradictory change cannot name a next player reliably.
        var changed=DeferredMoveHistory.states(actual.board);changed[0] = .empty
        feed(restored,DeferredMoveHistory.board(changed,size:9))
        check(restored.needsTurnConfirmation && restored.clock.awaitingTurn && restored.state == .recording,"Unknown live turn did not leave recording active")
        try await render(LiveTurnPrompt(recorder:restored).padding(),"turn-prompt",width:650,height:200)
        restored.confirmLiveTurn(.black,at:now)
        check(restored.clock.running && restored.liveNextPlayer == .black,"Quick turn confirmation waited for historical review")
        restored.pause()
        let confirmedRestart=GameRecorder(storage:folder);confirmedRestart.clock.audible=false
        try confirmedRestart.restoreSavedGame(from:restored.autosaveURL!)
        check(confirmedRestart.liveNextPlayer == .black && !confirmedRestart.clock.awaitingTurn,"Confirmed live turn failed restart")

        // Scoring is independent of chronology, with an explicit prisoner gate.
        r.finish()
        check(r.state == .finished && r.hasUnfinishedReviews && r.canScorePosition && !r.clock.running,"Ending play blocked scoring or discarded reviews")
        let endedRestart=GameRecorder(storage:folder);endedRestart.clock.audible=false
        try endedRestart.restoreSavedGame(from:r.autosaveURL!)
        check(endedRestart.state == .finished && endedRestart.canScorePosition && endedRestart.hasUnfinishedReviews,"Ended game lost independent scoring/review state on restart")
        let scoring=PhysicalScoring();scoring.open(recorder:r,analyzeImmediately:false)
        check(scoring.presented && scoring.finalReview && scoring.session?.board==actual.board,"Final score opened the incomplete SGF instead of the live board")
        let analysis=AIAnalysis(id:"live-test",isDuringSearch:false,turnNumber:0,moveInfos:[],rootInfo:.init(winrate:0.5,scoreLead:0,visits:42),ownership:Array(repeating:0.0,count:81))
        check(scoring.receiveAnalysis(analysis),"Live ownership result was rejected")
        check(scoring.needsPrisonerConfirmation && !scoring.canAccept,"Territory scoring silently assumed prisoner counts")
        try await render(PhysicalScoringView(scoring:scoring,recorder:r,orientation:BoardOrientation(0)),"live-scoring",width:930,height:740)
        scoring.setPrisoners(black:4,white:1);scoring.prisonersConfirmed=true;scoring.markingsConfirmed=true
        check(scoring.canAccept && scoring.session?.result?.black.captured==4 && scoring.session?.result?.white.captured==1,"Confirmed prisoner totals were not used")
        scoring.accept(recorder:r)
        check(scoring.accepted && r.game.info.result != nil && r.hasUnfinishedReviews && r.moveCount==0,"Scoring required move-order review or finalized SGF prematurely")
        let result=r.game.info.result
        let section=r.reviewHistory.reviews[0]
        var draft=MoveRecoveryDraft(game:r.contextForReview(section.id)!.game,observation:nil)
        for p in order {check(draft.add(p,checkCameraColor:false)==nil,"Bad review order")}
        let pausedClock=r.clock.engine
        check(r.resolveReview(section.id,draft:draft,overrideCamera:false)==nil,"Ended game could not resolve remaining review")
        check(r.state == .finished && !r.hasUnfinishedReviews && r.moveCount==4 && r.game.info.result==result,"Finalizing SGF lost the scored result")
        check(r.clock.engine.black==pausedClock.black && r.clock.engine.white==pausedClock.white && !r.clock.requiresReview,"Historical review changed clock totals")
        check(r.sgf().contains("WL["),"Final SGF omitted the independently observed clock press")
        let (area,areaActual,_)=gap("Chinese");area.finish()
        scoring.open(recorder:area,analyzeImmediately:false);_ = scoring.receiveAnalysis(analysis);scoring.markingsConfirmed=true
        check(!scoring.needsPrisonerConfirmation && scoring.canAccept,"Area scoring unnecessarily required prisoners")
        check(scoring.session?.board==areaActual.board,"Area score lost live position")
        scoring.cancel()

        // An actual local KataGo request verifies setup-stone payloads end to end.
        print("Deterministic checks passed; asking local KataGo to score the live board…")
        scoring.open(recorder:area)
        let start=ProcessInfo.processInfo.systemUptime
        while scoring.busy && ProcessInfo.processInfo.systemUptime-start<125 {try await Task.sleep(nanoseconds:100_000_000)}
        check(scoring.aiAvailable && scoring.error==nil && scoring.visits>0,"Live-position KataGo failed: \(scoring.error ?? "no result")")
        check(scoring.session?.board==areaActual.board && area.hasUnfinishedReviews,"AI scoring mutated or ignored live history")
        scoring.markingsConfirmed=true
        scoring.accept(recorder:area)
        check(scoring.accepted && area.game.info.result != nil,"Area result could not be saved before reviewing history")
        let areaSection=area.reviewHistory.reviews[0]
        var changedDraft=MoveRecoveryDraft(game:area.contextForReview(areaSection.id)!.game,observation:nil)
        for p in [BoardPosition(0,0),BoardPosition(8,8),BoardPosition(0,2)] {check(changedDraft.add(p,checkCameraColor:false)==nil,"Bad score-invalidation fixture")}
        check(area.resolveReview(areaSection.id,draft:changedDraft,overrideCamera:true)==nil && area.game.info.result==nil,"A corrected scoring board retained a stale agreed result")
        scoring.shutdown()
        print("PASS: \(checks) live-play checks; five clocks, recognition latency, turn confirmation, pause/resume, restart, independent SGF finalization, prisoner confirmation, area scoring and real KataGo")
    }
}
