// Full-app suite: no source extraction/stubs; only the move generator is injected.
import Foundation
@main struct PhysicalCaptureControllerTests {
 @MainActor static func main() async throws {
  setbuf(stdout,nil)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("capture-ai-"+UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  var now=100.0,wall=1000.0,checks=0
  func check(_ value:Bool,_ reason:String){precondition(value,reason);checks+=1}
  func fixture(_ name:String,multi:Bool,humanCapture:Bool=false) throws -> PhysicalAI {
   let folder=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   var settings=PhysicalAISettings();settings.size=9;settings.humanBlack=humanCapture
   // Legal fixtures: A8,A9,J1,C9,B9 => A9; B9,A9,B8,A8,A7 => A9/A8.
   let moves=multi ? [1,0,10,9,18]:[9,0,80,2,1]
   let saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:moves.map{.init(point:$0,decisionReceivedAtUnix:999)},pendingPlacement:!humanCapture,pendingCaptureCleanup:multi,
      captureIndication:.init(moveNumber:5,acceptedAtUnix:999),timing:PhysicalAITiming(blackToPlay:false))
   try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
   let laser=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,wallTime:{wall},uptime:{now})
   let ai=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:laser,uptime:{now},wallTime:{wall})
   ai.resume();return ai
  }
  func feed(_ ai:PhysicalAI,_ cells:[String],hand:Bool=false,count:Int=3){
   for _ in 0..<count {
    now+=0.25;wall+=0.25;ai.laser.observeCamera(hand:hand,valid:true,capturedAt:now,now:now,context:"grid")
    var o=BoardObservation(readings:cells.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:9)
    o.capturedAt=now;o.handObstructed=hand;ai.consume(o,now:now)
   }
  }
  let single=try fixture("single",multi:false)
  var before=single.cells;before[0]="white";before[1]="empty"
  feed(single,before);check(single.laser.target?.purpose==nil && single.guidanceTarget?.col==1,"AI placement precedes prisoners")
  before[1]="black";feed(single,before)
  check(single.laser.target?.purpose=="capture" && single.captureGuidancePoint==0,"Independent placed witness changes laser purpose")
  check(single.snapshot!.pendingPlacement && single.snapshot!.moves.count==5,"Capture guidance cannot finish logical placement or append a move")
  check(single.guidanceTarget==nil,"Confirmed AI stone no longer shows an unplaced blue ring")
  check(!single.captureCleanupPending && single.timing.anchor != nil,"Single capture retains running next-player clock")
  let timeBefore=single.timing.elapsed(black:false,at:now)
  feed(single,before,hand:true)
  check(single.snapshot!.pendingPlacement && single.snapshot!.moves.count==5,"Hand does not complete move")
  check(single.timing.elapsed(black:false,at:now)>timeBefore,"Single capture hand interval still charged")
  feed(single,single.cells)
  check(!single.snapshot!.pendingPlacement && single.snapshot!.captureIndication==nil && single.phase == .human,"Full board agreement alone closes placement/capture")
  var extra=single.cells;extra[0]="white";feed(single,extra)
  check(single.laser.target?.purpose != "capture","Completed capture cannot resurrect from extra stone")
  let multi=try fixture("multi",multi:true)
  var partial=multi.cells;partial[0]="white";partial[9]="white";feed(multi,partial)
  check(multi.captureCleanupPending && multi.timing.anchor==nil && multi.remainingCapturedStones==2,"Two prisoners preserve capture clock pause")
  partial[9]="empty";feed(multi,partial)
  check(multi.snapshot!.moves.count==5,"Remaining prisoner must not be inferred as a legal human reply after partial removal")
  check(multi.remainingCapturedStones==1 && multi.captureGuidancePoint==0 && multi.snapshot!.captureIndication!.removed==[9],"Out-of-order partial removal persists separately")
  check(multi.snapshot!.pendingPlacement && multi.timing.anchor==nil,"Partial cleanup cannot complete turn or resume clock")
  multi.pause()
  let restoreLaser=PhysicalLaserGuidance(directory:root.appendingPathComponent("restored-bridge"),automatic:false,wallTime:{wall},uptime:{now})
  let restored=PhysicalAI(directory:root.appendingPathComponent("multi"),generate:{_,_ in "pass"},laser:restoreLaser,uptime:{now},wallTime:{wall})
  check(restored.captureGuidancePoint==nil && restored.remainingCapturedStones==1,"Restart preserves removal ledger but discards physical placement witness")
  restored.resume();feed(restored,partial)
  check(restored.captureGuidancePoint==0 && restored.snapshot!.moves.count==5,"Restart obtains fresh evidence for remaining prisoner")
  multi.resume();feed(multi,partial)
  check(multi.remainingCapturedStones==1 && multi.snapshot!.moves.count==5,"Pause/resume preserves legal capture context")
  feed(multi,multi.cells)
  check(multi.snapshot!.captureIndication==nil && !multi.captureCleanupPending && multi.timing.anchor != nil,"Full multiple cleanup resumes existing clock path")
  let human=try fixture("human",multi:false,humanCapture:true)
  var humanBoard=human.cells;humanBoard[0]="white";feed(human,humanBoard)
  check(human.captureGuidancePoint==0 && human.laser.target?.purpose=="capture" && !human.snapshot!.pendingPlacement,"Single human capture needs no AI placement witness")
  check(human.snapshot!.moves.count==5 && human.phase == .checking,"Pending prisoner prevents requesting next AI move")
  human.centeringEnabled=true
  for _ in 0..<3 {
   now+=0.25;wall+=0.25;human.laser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"grid")
   var o=BoardObservation(readings:humanBoard.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:9)
   o.capturedAt=now;o.handObstructed=false;o.centeringEvidence=[.init(color:.black,shape:StoneFootprint(row:3,col:3,center:.init(x:3.4,y:3.4),radiusCol:0.5,radiusRow:0.5,quality:0.98))]
   human.consume(o,now:now)
  }
  check(human.centeringStone==nil && human.laser.target?.purpose=="capture","Capture suppresses optional centering even for a single prisoner")
  for humanBlack in [true,false] {
   let folder=root.appendingPathComponent(humanBlack ? "new-human":"new-ai")
   try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   var settings=PhysicalAISettings();settings.size=9;settings.humanBlack=humanBlack
   let saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:[9,0,80,2].map{.init(point:$0)})
   try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
   let bridge=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,wallTime:{wall},uptime:{now})
   let ai=PhysicalAI(directory:folder,generate:{_,_ in "B9"},laser:bridge,uptime:{now},wallTime:{wall})
   ai.resume();feed(ai,ai.cells)
   if humanBlack {var placed=ai.cells;placed[1]="black";feed(ai,placed)}
   else {
    let deadline=ProcessInfo.processInfo.systemUptime+2
    while ai.snapshot!.moves.count<5 && ProcessInfo.processInfo.systemUptime<deadline {
     try await Task.sleep(nanoseconds:5_000_000)
    }
   }
   check(ai.snapshot!.moves.count==5 && ai.lastCapturePoints==[0],"Real legal move commit derives exactly the captured set")
   check(ai.snapshot!.captureIndication?.moveNumber==5 && ai.snapshot!.captureIndication!.acceptedAtUnix>0,"New human and AI captures persist explicit capture context")
   check(ai.snapshot!.pendingPlacement == !humanBlack && !ai.captureCleanupPending,"New single capture keeps placement and clock flags distinct")
   ai.pause()
  }
  func feedWithoutLaser(_ ai:PhysicalAI,_ cells:[String],count:Int=3) {
   for _ in 0..<count {
    now+=0.25;wall+=0.25
    var o=BoardObservation(readings:cells.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:9)
    o.capturedAt=now;o.handObstructed=false;ai.consume(o,now:now)
   }
  }
  for bound in [false,true] {
   let combined=try fixture(bound ? "combined-bound":"combined-board-only",multi:true)
   let whiteBefore=combined.timing.whiteSeconds
   var reply=combined.cells;reply[40]="white"
   now+=20;wall+=20
   if bound {feed(combined,reply)} else {feedWithoutLaser(combined,reply)}
   check(combined.snapshot!.moves.count==6 && combined.snapshot!.moves.last!.point==40,"Complete cleanup plus legal reply must remain supported")
   check(!combined.snapshot!.pendingPlacement && !combined.captureCleanupPending,"Combined reply clears original placement/cleanup hold")
   check(combined.timing.whiteSeconds==whiteBefore,"Combined reply cannot charge the capture-cleanup interval")
   if !bound {check(combined.laser.cameraContext==nil && !combined.laser.enabled,"Board-only cleanup never invents a laser camera binding")}
   combined.pause()
  }
  let unboundPartial=try fixture("partial-board-only",multi:true)
  var oneLeft=unboundPartial.cells;oneLeft[0]="white"
  feedWithoutLaser(unboundPartial,oneLeft)
  check(unboundPartial.snapshot!.moves.count==5 && unboundPartial.clockPausedForCaptureCleanup,"Board-only path also rejects a remaining prisoner as a reply")
  unboundPartial.pause()
  // Deliberately seed retained empty labels: generic board stabilization can
  // borrow them, but capture cleanup must still obtain new positive observations.
  let seed=try fixture("retained-seed",multi:true)
  var saved=seed.snapshot!;saved.verifiedPosition = .init(cells:seed.cells,cameraContext:"grid")
  let retainedFolder=root.appendingPathComponent("retained-empty")
  try FileManager.default.createDirectory(at:retainedFolder,withIntermediateDirectories:true)
  try JSONEncoder().encode(saved).write(to:retainedFolder.appendingPathComponent("current.json"))
  seed.pause()
  let retainedLaser=PhysicalLaserGuidance(directory:retainedFolder.appendingPathComponent("bridge"),automatic:false,wallTime:{wall},uptime:{now})
  let retained=PhysicalAI(directory:retainedFolder,generate:{_,_ in "pass"},laser:retainedLaser,uptime:{now},wallTime:{wall})
  retained.resume();var uncertain=retained.cells;uncertain[0]="uncertain";uncertain[40]="white"
  feed(retained,uncertain)
  check(retained.snapshot!.moves.count==5 && retained.clockPausedForCaptureCleanup,"Borrowed empty history cannot prove prisoner cleanup")
  uncertain[0]="empty";feed(retained,uncertain,count:2)
  check(retained.snapshot!.moves.count==5,"One or two fresh empty frames cannot exploit an already stable retained board")
  feed(retained,uncertain,count:1)
  check(retained.snapshot!.moves.count==6 && retained.snapshot!.moves.last!.point==40,"Third stable positive empty frame permits legitimate combined reply")
  retained.pause()
  print("PASS \(checks) real AI controller/legal SGF/timing integration checks (real application types; injected move generator)")
 }
}
