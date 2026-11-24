// Real controller, legal SGF history and diagnostic tracker; no devices or real saves.
import Foundation

@main struct PhysicalAIIllegalMoveTests {
 @MainActor static func main() throws {
  setbuf(stdout,nil)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("illegal-ai-"+UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  final class Clock {var now=100.0;var wall=1000.0}
  let clock=Clock();var checks=0
  func check(_ ok:Bool,_ why:String) {precondition(ok,why);checks+=1}
  let suicide=[0,9,80,10,79,2]
  let ko=[1,10,9,2,19,12,80,20,11]
  let snapback=[0,9,1,2,18,11,80,19,10]
  func fixture(_ name:String,moves:[Int],humanBlack:Bool,rules:String="Japanese",pending:Bool=false,capture:Bool=false)throws->PhysicalAI {
   let folder=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   var settings=PhysicalAISettings();settings.size=9;settings.humanBlack=humanBlack;settings.rules=rules
   let saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:moves.map{.init(point:$0,decisionReceivedAtUnix:999)},pendingPlacement:pending,
      captureIndication:capture ? .init(moveNumber:moves.count,acceptedAtUnix:999):nil,
      timing:PhysicalAITiming(blackToPlay:humanBlack))
   try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
   let laser=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,wallTime:{clock.wall},uptime:{clock.now})
   let ai=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:laser,uptime:{clock.now},wallTime:{clock.wall})
   check(ai.phase == .paused,"Reviewed fixture must load as valid legal history: \(name)")
   ai.resume();return ai
  }
  func observe(_ ai:PhysicalAI,_ cells:[String],hand:Bool?=false,stamp:Double?=nil,ambiguous:Int?=nil,
               manual:Int?=nil,weak:Int?=nil,context:String="grid",lighting:Bool=false) {
   clock.now+=0.25;clock.wall+=0.25
   let captured=stamp ?? clock.now
   ai.laser.observeCamera(hand:hand,valid:true,capturedAt:captured,now:clock.now,context:context)
   var o=BoardObservation(readings:cells.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,
      occupancy:Occupancy(rawValue:$0.element)!,confidence:$0.offset==weak ? 0.7:1,delta:0)},size:9)
   o.capturedAt=captured;o.handObstructed=hand;o.lightingBlocked=lighting
   if let ambiguous {o.footprints=[.init(row:ambiguous/9,col:ambiguous%9,center:.init(x:Double(ambiguous%9)+0.5,y:Double(ambiguous/9)),radiusCol:0.5,radiusRow:0.5,quality:0.98)]}
   if let ambiguous {check(o.assignmentOffsets(confirmedBoard:ai.cells.map{Occupancy(rawValue:$0)!})[ambiguous].map{$0>=0.30}==true,"Ambiguity fixture must actually be geometrically ambiguous")}
   if let manual {o.manualPoints=[manual]}
   ai.consume(o,now:clock.now)
  }
  func feed(_ ai:PhysicalAI,_ cells:[String],count:Int=3) {for _ in 0..<count {observe(ai,cells)}}
  func data(_ ai:PhysicalAI)throws->Data {try JSONEncoder().encode(ai.snapshot)}
  func sameSnapshot(_ before:Data,_ ai:PhysicalAI)throws->Bool {
   try JSONSerialization.jsonObject(with:before) as! NSDictionary == JSONSerialization.jsonObject(with:data(ai)) as! NSDictionary
  }

  for rules in ["Japanese","Chinese"] {
   let ai=try fixture("suicide-"+rules,moves:suicide,humanBlack:true,rules:rules)
   feed(ai,ai.cells);check(ai.phase == .human,"Verified fixture reaches human turn")
   let snapshot=try data(ai),timing=ai.timing,cells=ai.cells
   var attempt=cells;attempt[1]="black"
   observe(ai,attempt);observe(ai,attempt)
   check(ai.illegalMoveWarning==nil,"Two fresh frames cannot create illegal warning")
   observe(ai,attempt,stamp:clock.now)
   check(ai.illegalMoveWarning==nil,"Repeated capture timestamp cannot create third witness")
   observe(ai,attempt)
   check(ai.illegalMoveWarning?.point==1 && ai.illegalMoveWarning?.rejection == .suicide,"Specific self-capture warning on strong third distinct observation")
   check(ai.status.contains(SGFPlayer.MoveRejection.suicide.rawValue) && ai.status.contains("marked ×"),"Screen says why to remove the stone")
   check(ai.mismatch?.remove==[1] && ai.mismatch?.place.isEmpty==true,"Existing screen correction marks only the illegal addition")
   check(try sameSnapshot(snapshot,ai),"Warning cannot mutate saved move, pending flags, history or captured ledger")
   check(ai.timing==timing && ai.cells==cells && ai.phase == .human,"Warning preserves clock anchor, accepted board and turn")
   check(ai.laser.target==nil,"Screen-only warning adds no laser target or purpose")
   observe(ai,attempt,hand:true)
   check(ai.illegalMoveWarning==nil && !ai.status.contains(SGFPlayer.MoveRejection.suicide.rawValue),"Hand clears stale specific warning")
   feed(ai,cells)
   check(ai.illegalMoveWarning==nil && ai.mismatch==nil,"Removing illegal stone restores normal turn")
   var legal=cells;legal[40]="black";feed(ai,legal)
   check(ai.snapshot?.moves.count==suicide.count+1 && ai.snapshot?.moves.last?.point==40,"Ordinary legal placement still commits")
   ai.pause()
  }

  for removed in [false,true] {
   let ai=try fixture(removed ? "ko-removed":"ko-present",moves:ko,humanBlack:false)
   feed(ai,ai.cells);let snapshot=try data(ai),timing=ai.timing
   var attempt=ai.cells;attempt[10]="white";if removed {attempt[11]="empty"}
   feed(ai,attempt)
   check(ai.illegalMoveWarning?.rejection == .ko && ai.illegalMoveWarning?.point==10,"Ko attempt is diagnostic, not accepted")
   check(ai.illegalMoveWarning?.restorePoints==(removed ? [11]:[]),"Prematurely removed ko stone requires explicit restoration")
   check(ai.mismatch?.remove==[10] && ai.mismatch?.place==(removed ? [11]:[]),"Existing screen marks the illegal stone and any restoration")
   check(try sameSnapshot(snapshot,ai) && ai.timing==timing,"Ko warning cannot rewrite history/captures/clocks")
   ai.pause();check(ai.illegalMoveWarning==nil,"Pause clears diagnostic state")
  }

  let prisoner=try fixture("prisoner-not-ko",moves:ko,humanBlack:false,capture:true)
  var left=prisoner.cells;left[10]="white"
  feed(prisoner,left)
  check(prisoner.remainingCapturedStones==1 && prisoner.illegalMoveWarning==nil,"Remaining legal prisoner is never relabeled an illegal recapture")
  check(!prisoner.status.contains(SGFPlayer.MoveRejection.ko.rawValue) && prisoner.snapshot?.moves.count==ko.count,"Unremoved prisoner cannot advance history or produce ko accusation")
  feed(prisoner,prisoner.cells)
  check(prisoner.phase == .human,"Positive cleanup completes before the next human attempt")
  feed(prisoner,left)
  check(prisoner.illegalMoveWarning?.rejection == .ko,"A new stone after independently verified prisoner removal can be diagnosed")
  prisoner.pause()

  let pending=try fixture("pending-ai",moves:suicide,humanBlack:true,pending:true)
  var pendingAttempt=pending.cells;pendingAttempt[1]="black";feed(pending,pendingAttempt)
  check(pending.illegalMoveWarning==nil && pending.snapshot?.pendingPlacement==true,"Pending AI placement cannot acquire new diagnostic warning")
  pending.pause()
  let snap=try fixture("legal-snapback",moves:snapback,humanBlack:false)
  feed(snap,snap.cells);var snapAttempt=snap.cells;snapAttempt[9]="white";feed(snap,snapAttempt)
  check(snap.illegalMoveWarning==nil && snap.snapshot?.moves.count==snapback.count+1,"Legal snapback remains accepted rather than mislabeled ko")
  snap.pause()

  let invalid=try fixture("invalid-evidence",moves:suicide,humanBlack:true)
  feed(invalid,invalid.cells);var invalidAttempt=invalid.cells;invalidAttempt[1]="black"
  for _ in 0..<4 {observe(invalid,invalidAttempt,ambiguous:1)}
  check(invalid.illegalMoveWarning==nil && invalid.snapshot?.moves.count==suicide.count,"Ambiguous location cannot be guessed illegal")
  var unknown=invalidAttempt;unknown[40]="uncertain"
  feed(invalid,unknown,count:4)
  check(invalid.illegalMoveWarning==nil,"Retained uncertain intersections cannot substantiate diagnostic")
  for _ in 0..<4 {observe(invalid,invalidAttempt,manual:1)}
  check(invalid.illegalMoveWarning==nil,"Manual correction is not positive observed illegal placement")
  for _ in 0..<4 {observe(invalid,invalidAttempt,weak:1)}
  check(invalid.illegalMoveWarning==nil,"Weak new-stone evidence cannot warn")
  for _ in 0..<4 {observe(invalid,invalidAttempt,stamp:clock.now-1)}
  check(invalid.illegalMoveWarning==nil,"Old observation within general recognition window is too old for diagnostic")
  for _ in 0..<4 {observe(invalid,invalidAttempt,hand:nil)}
  check(invalid.illegalMoveWarning==nil,"Unknown hand clears diagnostic")
  observe(invalid,invalidAttempt);observe(invalid,invalidAttempt)
  observe(invalid,invalidAttempt,context:"replacement-grid")
  check(invalid.illegalMoveWarning==nil,"Changed camera context cannot reuse preceding two witnesses")
  feed(invalid,invalidAttempt)
  check(invalid.illegalMoveWarning?.rejection == .suicide,"Fresh context can independently establish warning")
  let duplicate=clock.now
  observe(invalid,invalidAttempt,stamp:duplicate,context:"changed-on-duplicate")
  check(invalid.illegalMoveWarning==nil && invalid.mismatch==nil,"Camera context change clears displayed warning even before duplicate-frame return")
  feed(invalid,invalidAttempt)
  check(invalid.illegalMoveWarning != nil,"Fresh camera context rebuilds diagnostic")
  invalid.laser.cameraStreamChanged()
  observe(invalid,invalidAttempt,stamp:clock.now)
  check(invalid.illegalMoveWarning==nil,"Stream change clears displayed warning even on duplicate capture stamp")
  feed(invalid,invalidAttempt)
  observe(invalid,invalidAttempt,lighting:true)
  check(invalid.illegalMoveWarning==nil,"Lighting interruption clears warning")
  var multiple=invalidAttempt;multiple[40]="black";feed(invalid,multiple,count:4)
  check(invalid.illegalMoveWarning==nil,"Multiple additions cannot select a guessed illegal stone")
  invalid.pause()

  // AI UI supports Japanese/Chinese only. Verify the same production diagnostic
  // helper against the authoritative allowed-self-capture model without adding a preset.
  var nzGame=SGFGame();nzGame.boardSize=9;nzGame.info.rules="nz"
  nzGame.setup=[(.black,0,0),(.white,0,1),(.white,1,1),(.white,2,0)]
  let nz=SGFPlayer();nz.load(game:nzGame)
  var nzCells=nz.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"};nzCells[1]="black"
  var tracker=PhysicalIllegalMoveWarning.Tracker()
  for (i,t) in [1.0,1.25,1.5].enumerated() {
   let warning=tracker.observe(player:nz,context:"nz",human:.black,acceptsHumanAttempt:true,pendingAIPlacement:false,
       evidence:.init(frameID:String(i),capturedAt:t,cells:nzCells.map{Optional($0)},confidence:Array(repeating:1,count:81),ambiguous:[],hand:false,aligned:true,confirmedDark:true),now:t,permitsReply:{_ in true})
   check(warning==nil,"Allowed self-capture is never mislabeled suicide")
  }
  check(nz.tryPlayMove(color:.black,x:1,y:0)==nil,"Authoritative allowed-self-capture remains legal")
  print("PASS \(checks) screen-only illegal-move controller checks (real engine/controller; no hardware)")
 }
}
