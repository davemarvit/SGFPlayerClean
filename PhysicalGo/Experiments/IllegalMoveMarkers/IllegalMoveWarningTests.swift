import Foundation

@main struct IllegalMoveWarningTests {
 static func main() throws {
  var checks=0
  func check(_ ok:Bool,_ name:String) {precondition(ok,name);checks+=1}
  let ko:[(Stone,Int,Int)]=[(.black,1,0),(.black,0,1),(.black,1,2),(.white,1,1),(.white,2,0),(.white,3,1),(.white,2,2)]
  let suicide:[(Stone,Int,Int)]=[(.black,0,0),(.white,0,1),(.white,1,1),(.white,2,0)]
  func player(_ rules:String,_ setup:[(Stone,Int,Int)],online:Bool=false)->SGFPlayer {
   var game=SGFGame();game.boardSize=9;game.setup=setup;game.info.rules=rules;game.analysisOnline=online
   let p=SGFPlayer();p.load(game:game);return p
  }
  func cells(_ p:SGFPlayer)->[String] {p.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"}}
  func attempted(_ p:SGFPlayer,_ point:Int,_ color:Stone)->[String] {var c=cells(p);c[point]=color.rawValue;return c}
  func evidence(_ c:[String],_ t:Double,frame:String?=nil,hand:Bool?=false,dark:Bool=true,
                aligned:Bool=true,uncertain:Int?=nil,ambiguous:Set<Int>=[],low:Int?=nil)->PhysicalIllegalMoveWarning.Evidence {
   var raw=c.map{Optional($0)},confidence=Array(repeating:1.0,count:c.count)
   if let uncertain {raw[uncertain]=nil};if let low {confidence[low]=0.7}
   return .init(frameID:frame ?? String(t),capturedAt:t,cells:raw,confidence:confidence,ambiguous:ambiguous,hand:hand,aligned:aligned,confirmedDark:dark)
  }
  func detect(_ p:SGFPlayer,_ c:[String],permits:Bool=true)->PhysicalIllegalMoveWarning.Candidate? {
   var tracker=PhysicalIllegalMoveWarning.Tracker(),result:PhysicalIllegalMoveWarning.Candidate?
   for t in [1.0,1.25,1.5] {
    result=tracker.observe(player:p,context:"game/history/rules/camera",human:p.turn,acceptsHumanAttempt:true,pendingAIPlacement:false,evidence:evidence(c,t),now:t,permitsReply:{_ in permits})
    if t<1.5 {check(result==nil,"Warning requires three frames spanning450ms")}
   }
   return result
  }
  for rule in ["Japanese","Chinese"] {
   let p=player(rule,suicide),before=p.createSnapshot(),board=p.board
   let c=attempted(p,1,.black)
   check(PhysicalMoveInference.candidate(board:cells(p),observed:c,size:9,color:"black")==nil,"Existing legal candidate path excludes suicide before diagnostic rejection")
   check(detect(p,c)?.rejection == .suicide,"Suicide diagnostic uses current engine policy: \(rule)")
   check(p.board==board && p.currentIndex==before.currentIndex && p.maxIndex==before.moves.count && p.capturesByBlack==0 && p.capturesByWhite==0,"Warning leaves board/history/captures unchanged")
   check(p.analysisSettings.playRules?.repetition == .simple,"Local AI preset actually uses simple ko: \(rule)")
  }
  let nz=player("nz",suicide)
  check(nz.analysisSettings.playRules?.allowsSelfCapture==true && detect(nz,attempted(nz,1,.black))==nil,"Allowed NZ self-capture is not called illegal")
  let unknown=player("ing",suicide)
  check(unknown.analysisSettings.playRules==nil && detect(unknown,attempted(unknown,1,.black))==nil,"Unknown rule policy cannot produce speculative warning")

  for rule in ["Japanese","Chinese"] {
   let p=player(rule,ko);check(p.tryPlayMove(color:.black,x:2,y:1)==nil,"Legal ko fixture capture")
   let board=p.board,history=p.maxIndex,captured=p.capturesByBlack
   let present=attempted(p,10,.white)
   check(detect(p,present)?.rejection == .ko,"Ko detected before captured black stone removal")
   var removed=present;removed[11]="empty"
   let warning=detect(p,removed)
   check(warning?.rejection == .ko && warning?.restorePoints==[11],"Ko warning identifies prematurely removed stone to restore")
   check(p.board==board && p.maxIndex==history && p.capturesByBlack==captured,"Private simulation cannot commit ko or alter captures")
   check(detect(p,present,permits:false)==nil,"Unresolved prior prisoner blocks an illegal/new-reply interpretation")
   check(p.tryPlayMove(color:.white,x:8,y:8)==nil && p.tryPlayMove(color:.black,x:8,y:7)==nil,"Ko threat and response fixture")
   check(detect(p,attempted(p,10,.white))==nil,"Legal recapture after threat is not marked")
  }
  let positional=player("Chinese",ko,online:true)
  check(positional.analysisSettings.playRules?.repetition == .positional,"Online Chinese uses positional superko")
  check(positional.tryPlayMove(color:.black,x:2,y:1)==nil,"Superko fixture capture")
  check(positional.tryPlayMove(color:.white,x:-1,y:-1)==nil && positional.tryPlayMove(color:.black,x:-1,y:-1)==nil,"Passes retain repetition history")
  check(detect(positional,attempted(positional,10,.white))?.rejection == .superko,"Longer repeated position gets authoritative superko reason")

  let snap=player("Japanese",[(.black,0,0),(.black,1,0),(.black,0,2),(.white,0,1),(.white,2,0),(.white,2,1),(.white,1,2)])
  check(snap.tryPlayMove(color:.black,x:1,y:1)==nil,"Snapback fixture capture")
  check(snap.moveRejection(color:.white,x:0,y:1)==nil && detect(snap,attempted(snap,9,.white))==nil,"Legal snapback is not mislabeled ko")
  let capturing=player("Japanese",[(.white,0,0),(.white,1,0),(.white,0,1),(.black,2,0),(.black,0,2),(.black,2,1),(.black,1,2)])
  check(capturing.moveRejection(color:.black,x:1,y:1)==nil && detect(capturing,attempted(capturing,10,.black))==nil,"Surrounded but capturing move is not suicide")

  let p=player("Japanese",suicide),attempt=attempted(player("Japanese",suicide),1,.black)
  var tracker=PhysicalIllegalMoveWarning.Tracker()
  func feed(_ e:PhysicalIllegalMoveWarning.Evidence,now:Double?=nil,active:Bool=true,pending:Bool=false,context:String="same")->PhysicalIllegalMoveWarning.Candidate? {
   tracker.observe(player:p,context:context,human:.black,acceptsHumanAttempt:active,pendingAIPlacement:pending,evidence:e,now:now ?? e.capturedAt,permitsReply:{_ in true})
  }
  check(feed(evidence(attempt,1))==nil && feed(evidence(attempt,1.25))==nil,"Two frames cannot warn")
  check(feed(evidence(attempt,1.5,hand:true))==nil,"Hand clears warning witnesses")
  check(feed(evidence(attempt,1.75))==nil && feed(evidence(attempt,2))==nil && feed(evidence(attempt,2.25)) != nil,"Clearance needs fresh witnesses after hand")
  check(feed(evidence(attempt,2.5,dark:false))==nil,"Illuminated evidence clears warning")
  check(feed(evidence(attempt,2.75,uncertain:40))==nil,"Retained/unknown board cannot substantiate warning")
  check(feed(evidence(attempt,3,ambiguous:[1]))==nil,"Ambiguous intersection cannot be called illegal")
  check(feed(evidence(attempt,3.25,low:1))==nil,"Weak new-stone evidence cannot warn")
  check(feed(evidence(attempt,3.5),now:4.3)==nil,"Stale recording cannot warn")
  check(feed(evidence(attempt,4.5),now:4)==nil,"Future recording cannot warn")
  check(feed(evidence(attempt,4.75,hand:nil))==nil,"Unknown hand state cannot warn")
  check(feed(evidence(attempt,5,aligned:false))==nil,"Unaligned board cannot warn")
  check(feed(evidence(attempt,5.25),active:false)==nil,"Paused/opponent phase cannot warn")
  check(feed(evidence(attempt,5.5),pending:true)==nil,"Pending AI placement cannot turn into illegal human warning")
  check(feed(evidence(attempt,6,frame:"same"))==nil && feed(evidence(attempt,6.25,frame:"same"))==nil && feed(evidence(attempt,6.5,frame:"same"))==nil,"Repeated frame cannot create three witnesses")
  check(feed(evidence(attempt,7))==nil && feed(evidence(attempt,7.25))==nil,"Fresh cohort begins")
  check(feed(evidence(attempt,7.5),context:"replacement") == nil,"Position/camera context change resets cohort")
  var multiple=attempt;multiple[40]="black"
  check(detect(p,multiple)==nil,"Two new stones cannot produce guessed illegal marker")
  var unrelated=attempt;unrelated[9]="empty"
  check(detect(p,unrelated)==nil,"Unrelated removal is synchronization issue, not guessed illegal move")
  print("PASS \(checks) illegal-marker candidate checks; actual SGFPlayer rules, no hardware, production unchanged")
 }
}
