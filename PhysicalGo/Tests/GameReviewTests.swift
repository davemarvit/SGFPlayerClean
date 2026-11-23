import Foundation
import AppKit
import SwiftUI

@MainActor private final class FakeReviewWorker:PhysicalReviewWorker {
    var failure:String?
    var results:[Int:AIAnalysis]=[:]
    var responses:[Int:AIAnalysis]=[:]
    var submitted:[Int]=[]
    var stopped=false
    var loadedID=""
    func load(game:SGFPlayer,id:String,relatedIDs:[String]) {loadedID=id}
    func analysis(at turn:Int)->AIAnalysis? {results[turn]}
    func submit(game:SGFPlayer,turn:Int,visits:Int) {submitted.append(turn);results[turn]=responses[turn]}
    func stop() {stopped=true}
}

@MainActor func runGameReviewTests() async throws {
    var checks=0
    func check(_ condition:Bool,_ message:String) {checks += 1;precondition(condition,message)}
    func analysis(_ turn:Int,_ score:Double,_ win:Double,priors:Bool=true)->AIAnalysis {
        AIAnalysis(id:"review",isDuringSearch:false,turnNumber:turn,
                   moveInfos:[AIMoveInfo(move:"A1",visits:100,winrate:win,scoreLead:score,pv:[],prior:priors ? 1:nil,order:0)],
                   rootInfo:AIRootInfo(winrate:win,scoreLead:score,visits:100))
    }
    let game=SGFGame.from(tree:try SGFParser.parse(text:"(;GM[1]FF[4]SZ[9]RU[Japanese]KM[6.5];B[aa];W[bb];B[];W[] )"))
    let data=[0:analysis(0,5,0.7),1:analysis(1,-3,0.4),2:analysis(2,6,0.81),3:analysis(3,-6,0.2),4:analysis(4,6,0.8)]
    let worker=FakeReviewWorker();worker.results=[0:data[0]!,4:data[4]!];worker.responses=data
    let review=PhysicalGameReview(makeWorker:{worker})
    review.prepare(game:game,cacheID:"fixture")
    review.receive([0:data[0]!,2:data[2]!])
    check(review.evaluations.isEmpty,"A missing adjacent position fabricated a perfect move")
    check(review.points.count==2 && review.points[0].segment != review.points[1].segment,"Graph connects across missing analysis")
    check(review.performance(.black).accuracy==nil,"No evaluated moves received an accuracy")
    review.start()
    for _ in 0..<50 where review.busy {try await Task.sleep(nanoseconds:10_000_000)}
    check(review.complete && !review.busy && worker.stopped,"History sweep did not complete and stop")
    check(worker.submitted==[1,3],"History sweep did not reuse complete cached positions")
    check(review.evaluations.count==4 && review.moveCount(.black)==2 && review.moveCount(.white)==2,"Passes missing from move coverage")
    let black=review.performance(.black),white=review.performance(.white)
    check(black.meanPointLoss==1 && white.meanPointLoss==1.5,"Before/after perspective produced wrong mean losses")
    check(abs(black.accuracy!-100*pow(0.75,1/0.55))<0.00001,"Black accuracy differs from the shared difficulty-weighted formula")
    check(review.evaluations[0].quality == .mediocre && review.evaluations[1].quality == .disastrous,"Move-quality categories changed")
    check(review.points[1].summary.blackScoreLead==3 && review.points[1].summary.blackWinrate==0.6,"White-to-move graph perspective inverted")
    let player=SGFPlayer();player.load(game:game)
    let engine=KataGoEngine();engine.currentAnalysisData=data
    check(engine.evaluateGameQuality(upTo:4,engine:player).mapValues(\.quality)==Dictionary(uniqueKeysWithValues:review.evaluations.map {($0.turn,$0.quality)}),"SGFPlayer Clean and Physical Go grades differ")
    review.prepare(game:game,cacheID:"older")
    var legacy=data;legacy[0]=analysis(0,5,0.7,priors:false);review.receive(legacy)
    check(review.performance(.black).accuracy==nil && review.performance(.black).meanPointLoss==1,"Missing priors fabricated an accuracy or hid valid point loss")
    review.prepare(game:game,cacheID:"unresolved",unavailableReason:"Review moves")
    review.receive(data);review.start()
    check(review.analyses.isEmpty && !review.busy,"Unresolved chronology received player ratings")
    let stalled=FakeReviewWorker(),cancellable=PhysicalGameReview(makeWorker:{stalled})
    cancellable.prepare(game:game,cacheID:"stalled");cancellable.start()
    try await Task.sleep(nanoseconds:20_000_000)
    cancellable.cancel();stalled.results=data
    try await Task.sleep(nanoseconds:120_000_000)
    check(stalled.stopped && !cancellable.busy && cancellable.analyses.isEmpty,"Closing review allowed a late result to alter assessments")
    cancellable.prepare(game:SGFGame(),cacheID:"new")
    check(cancellable.totalMoves==0 && cancellable.points.isEmpty,"New game retained old review")
    let failed=FakeReviewWorker();failed.failure="Engine failed"
    let recovered=FakeReviewWorker();recovered.responses=data
    var attempts=0
    let retry=PhysicalGameReview(makeWorker:{attempts += 1;return attempts==1 ? failed:recovered})
    retry.prepare(game:game,cacheID:"retry");retry.start()
    for _ in 0..<50 where retry.busy {try await Task.sleep(nanoseconds:10_000_000)}
    check(retry.error=="Engine failed" && failed.stopped,"Engine failure left analysis busy")
    retry.start()
    for _ in 0..<50 where retry.busy {try await Task.sleep(nanoseconds:10_000_000)}
    check(retry.complete && retry.error==nil,"Retry did not recover incomplete history")
    // Real game: deterministic review of the saved background history, including gaps.
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/UnfinishedScoring")
    let actual=SGFGame.from(tree:try SGFParser.parse(text:String(contentsOf:fixture.appendingPathComponent("game.sgf"))))
    let history=try JSONDecoder().decode([Int:AIAnalysis].self,from:Data(contentsOf:fixture.appendingPathComponent("history.json")))
    review.prepare(game:actual,cacheID:"actual");review.receive(history)
    check(review.totalMoves==65 && !review.evaluations.isEmpty && review.evaluations.count<65,"Recorded partial-history coverage wrong")
    check(review.performance(.black).accuracy != nil && review.performance(.white).accuracy != nil,"Actual game lacks player assessments")
    let counts=MoveQuality.allCases.map {q in review.evaluations.filter {$0.quality==q}.count}
    check(counts.reduce(0,+)==review.evaluations.count,"Move-quality distribution double-counts or omits analyzed moves")
    let host=NSHostingView(rootView:PhysicalGameReviewView(review:review).padding(24).background(Color(nsColor:.windowBackgroundColor)))
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:930,height:470),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua);host.appearance=window.appearance;window.contentView=host
    window.orderFront(nil);host.layoutSubtreeIfNeeded()
    let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])!.write(to:TestArtifacts.file("physical-score-audit/game-review.png"));window.orderOut(nil)
    print("PASS: \(checks) game-review checks (shared accuracy/grades, perspective, passes, gaps, cache reuse, cancellation, failure/retry, unknown chronology and actual-game render)")
    review.cancel();retry.cancel()
}
