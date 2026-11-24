import Foundation
@main struct PhysicalAIPracticeTests {
 @MainActor static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("practice-positions-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:root)}
  var checks=0,now=100.0
  func check(_ value:Bool,_ detail:String){precondition(value,detail);checks+=1}
  func original(_ folder:URL,recheck:String?=nil)throws->Data {
   try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   var settings=PhysicalAISettings();settings.size=9;settings.humanBlack=false
   let saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:[9,0,80,2,1].map{.init(point:$0,decisionReceivedAtUnix:1000)},
      pendingPlacement:true,pendingCaptureCleanup:false,captureIndication:.init(moveNumber:5,acceptedAtUnix:1000),
      timing:PhysicalAITiming(blackSeconds:12.25,whiteSeconds:34.5,blackToPlay:false),
      verifiedPosition:.init(cells:Array(repeating:"empty",count:81),cameraContext:"old-camera"),laserRecheckReason:recheck)
   let data=try JSONEncoder().encode(saved)
   try data.write(to:folder.appendingPathComponent("current.json"))
   try Data("prior SGF must remain unchanged".utf8).write(to:folder.appendingPathComponent(saved.id.uuidString+".sgf"))
   try Data("separate three-move checkpoint".utf8).write(to:folder.appendingPathComponent("three-move-checkpoint.json"))
   return data
  }
  func controller(_ folder:URL,generate:PhysicalAI.Generate?=nil)->PhysicalAI {
   PhysicalAI(directory:folder,generate:generate ?? {_,_ in "pass"},
      laser:PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,wallTime:{1000+now},uptime:{now}),uptime:{now},wallTime:{1000+now})
  }
  func feed(_ ai:PhysicalAI,_ cells:[String],count:Int=3) {
   for _ in 0..<count {
    now+=0.25
    var observation=BoardObservation(readings:cells.enumerated().map{.init(row:$0.offset/ai.size,col:$0.offset%ai.size,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:ai.size)
    observation.capturedAt=now;observation.handObstructed=false;ai.consume(observation,now:now)
   }
  }
  for position in PhysicalAIPracticePosition.allCases {
   let folder=root.appendingPathComponent(position.rawValue),oldData=try original(folder)
   let old=try JSONDecoder().decode(PhysicalAI.Snapshot.self,from:oldData)
   var calls=0
   let ai=controller(folder,generate:{_,_ in calls+=1;return "K10"})
   let oldClock=ai.timing
   check(ai.loadPracticePosition(position),"Load \(position.title)")
   let test=ai.snapshot!,context=test.practiceTest!
   check(test.id != old.id && context.testID==test.id && context.previousGameID==old.id,"Separate test identity owns original backup")
   check(ai.phase == .paused && !ai.active && ai.timing.anchor==nil && ai.timing.blackSeconds==0 && ai.timing.whiteSeconds==0,"Test loads paused with explicit zero synthetic elapsed balances")
   check(test.settings.size==19 && test.settings.humanBlack==position.humanBlack && test.settings.fastTestMode==true,"Correct board/color and fast test configuration")
   check(test.moves.map(\.point)==position.moves.map(Optional.some) && test.moves.allSatisfy {$0.decisionReceivedAtUnix==nil},"Only declared synthetic opening, no invented move timestamps")
   check(test.captureIndication==nil && test.verifiedPosition==nil && !test.pendingPlacement,"No borrowed camera/capture/placement evidence")
   check(ai.laser.target==nil && ai.laser.playSession==nil && !ai.laser.enabled,"Loading cannot activate laser or play session")
   let store=PhysicalAIPracticeStore(directory:folder),backup=try store.readBackup(context)
   check(backup.previousCurrent==oldData,"Durable backup retains exact prior JSON bytes")
   check(try String(contentsOf:folder.appendingPathComponent(old.id.uuidString+".sgf"),encoding:.utf8)=="prior SGF must remain unchanged","Original derived SGF not rewritten")
   let exported=try SGFParser.parse(text:PhysicalAI.sgf(test)),comments=exported.mainLineNodes.first?.props["C"] ?? []
   check(comments.count==1 && comments[0].contains("Synthetic") && comments[0].contains("KataGo AI practice"),"Standard single SGF comment retains original and synthetic-history notes")
   for _ in 0..<3 {await Task.yield()}
   check(calls==0 && ai.snapshot!.moves.count==position.moves.count,"Loading paused test cannot invoke AI")
   check(!ai.loadPracticePosition(position) && ai.snapshot!.id==test.id,"Nested test cannot replace original return context")
   // Relaunch decoding retains the test label and return reference; no write.
   let reopened=controller(folder)
   check(reopened.snapshot?.practiceTest==context && reopened.phase == .paused,"Relaunch retains test identity and paused state")
   ai.resume()
   let beforeResumeBoard=ai.cells
   for _ in 0..<3 {await Task.yield()}
   check(calls==0 && ai.phase == .checking,"Resume alone cannot request AI before fresh board verification")
   check(!ai.returnFromPracticePosition() && !ai.loadPracticePosition(.emptyHumanBlack),"Active test cannot be replaced or returned")
   if position.moves.isEmpty {
    var wrong=ai.cells;wrong[0]="white";feed(ai,wrong)
    for _ in 0..<3 {await Task.yield()}
    check(calls==0 && ai.snapshot!.moves.isEmpty,"Nonempty board cannot start empty-board AI test")
    feed(ai,beforeResumeBoard)
    if position.humanBlack {
     check(ai.phase == .human && calls==0 && ai.turn == .black,"Verified empty Human Black starts human turn")
    } else {
     for _ in 0..<20 {if ai.phase == .placing {break};await Task.yield()}
     check(calls==1 && ai.phase == .placing && ai.snapshot!.moves.count==1 && ai.snapshot!.pendingPlacement,"Verified empty Human White naturally requests AI Black once")
    }
   } else {
    feed(ai,beforeResumeBoard)
    check(ai.phase == .human && ai.turn == .black && calls==0,"Pre-capture board verifies before human fifth move")
    var physical=ai.cells;physical[position.nextMove!]="black";feed(ai,physical)
    check(ai.snapshot!.moves.count==5 && ai.lastCapturePoints==position.prisoners,"Normal human recognition commits expected legal capture")
    let multiple=position.prisoners.count==2
    check(ai.captureCleanupPending==multiple && (ai.timing.anchor==nil)==multiple,"Single clock runs; default two-stone cleanup holds")
    if multiple {
     physical[19]="empty";feed(ai,physical)
     check(ai.remainingCapturedStones==1 && ai.snapshot!.captureIndication?.removed==[19] && ai.timing.anchor==nil,"Partial out-of-order cleanup retains remaining prisoner and hold")
    }
   }
   ai.pause()
   check(ai.returnFromPracticePosition(),"Return original after test activity")
   check(try Data(contentsOf:folder.appendingPathComponent("current.json"))==oldData,"Return restores exact old snapshot when no new fault exists")
   check(ai.snapshot!.id==old.id && ai.snapshot!.moves.count==5 && ai.snapshot!.pendingPlacement && ai.timing==oldClock,"Original history, placement and elapsed clocks preserved")
   check(ai.phase == .paused && ai.laser.target==nil && ai.laser.playSession==nil && !ai.canPass,"Returned game remains paused without old recognition/laser witness")
   check(try Data(contentsOf:folder.appendingPathComponent("three-move-checkpoint.json"))==Data("separate three-move checkpoint".utf8),"Other saved checkpoint remains untouched")
   check(try store.readBackup(context).previousCurrent==oldData,"Backup remains immutable after return")
   check(!ai.returnFromPracticePosition(),"Old return action cannot overwrite restored real game")
  }
  let emptyFolder=root.appendingPathComponent("no-prior"),empty=controller(emptyFolder)
  empty.draft.size=13;empty.draft.humanBlack=false
  let draft=empty.draft
  check(empty.loadPracticePosition(.emptyHumanBlack),"No-game loader creates separate practice context")
  check(empty.snapshot!.practiceTest!.previousGameID==nil && empty.returnFromPracticePosition(),"No-game return is explicit absence")
  check(empty.phase == .idle && empty.snapshot==nil && empty.draft==draft && !FileManager.default.fileExists(atPath:emptyFolder.appendingPathComponent("current.json").path),"Return to setup restores draft and removes only own current test")
  check(empty.loadPracticePosition(.emptyHumanWhite),"New test after return uses same safe path")
  var faultTest=empty.snapshot!;faultTest.guidanceInterruption="controller_fault";faultTest.laserRecheckReason="controller_fault"
  try JSONEncoder().encode(faultTest).write(to:emptyFolder.appendingPathComponent("current.json"),options:.atomic)
  let faultEmpty=controller(emptyFolder),retained=try Data(contentsOf:emptyFolder.appendingPathComponent("current.json"))
  check(!faultEmpty.returnFromPracticePosition() && faultEmpty.snapshot?.practiceTest != nil,"Unresolved fault prevents no-game persistence removal")
  check(try Data(contentsOf:emptyFolder.appendingPathComponent("current.json"))==retained,"Refused no-game return preserves test bytes")
  // A simulated healthy hardware OFF receipt goes through the real native
  // recheck API; no gameplay Resume is needed merely to leave the test.
  let l=faultEmpty.laser;l.setEnabled(true);now+=0.25
  l.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"practice-camera")
  let off=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:l.producer,sequence:l.sequence,updatedAtUnix:1000+now,
      mode:"hardware",state:"off",laserOn:false,offSinceUnix:999+now,detail:"Synthetic healthy OFF for native recovery test")
  try JSONEncoder().encode(off).write(to:l.directory.appendingPathComponent("status.json"),options:.atomic)
  l.tick();l.showAgain()
  check(!l.gameFaultNeedsRecheck && faultEmpty.phase == .paused && faultEmpty.snapshot?.guidanceInterruption != nil,"Explicit healthy recheck clears requirement without gameplay Resume")
  check(faultEmpty.returnFromPracticePosition() && faultEmpty.snapshot==nil,"Resolved no-game fault permits direct Return to setup")

  let faultFolder=root.appendingPathComponent("fault-prior"),faultData=try original(faultFolder,recheck:"controller_fault")
  let fault=controller(faultFolder)
  check(fault.snapshot!.guidanceInterruption==nil && fault.laser.gameFaultNeedsRecheck,"Prior durable native requirement without active interruption is restored")
  check(fault.loadPracticePosition(.emptyHumanBlack),"Fault-paused game can be backed up without clearing fault")
  check(fault.snapshot!.guidanceInterruption=="controller_fault" && fault.laser.controllerResetRequired,"Practice inherits actual unresolved resume gate")
  fault.resume();check(fault.phase == .paused,"Practice Resume cannot bypass hardware recheck")
  check(fault.returnFromPracticePosition(),"Fault returns safely into preserved original game")
  let prior=try JSONDecoder().decode(PhysicalAI.Snapshot.self,from:faultData)
  check(fault.snapshot!.id==prior.id && fault.snapshot!.moves.map(\.point)==prior.moves.map(\.point) && fault.snapshot!.timing==prior.timing,"Fault carryover preserves original history/clocks")
  check(fault.snapshot!.guidanceInterruption=="controller_fault" && fault.snapshot!.laserRecheckReason=="controller_fault" && fault.laser.gameFaultNeedsRecheck,"Restoration retains unresolved recheck and resume gate")
  let resolvedFolder=root.appendingPathComponent("resolved-test-fault"),resolvedOriginal=try original(resolvedFolder)
  let beforeFault=controller(resolvedFolder);check(beforeFault.loadPracticePosition(.emptyHumanBlack),"Healthy prior game starts resolved-fault regression")
  var interrupted=beforeFault.snapshot!;interrupted.guidanceInterruption="controller_fault";interrupted.laserRecheckReason="controller_fault"
  try JSONEncoder().encode(interrupted).write(to:resolvedFolder.appendingPathComponent("current.json"),options:.atomic)
  let resolved=controller(resolvedFolder),resolvedLaser=resolved.laser
  resolvedLaser.setEnabled(true);now+=0.25;resolvedLaser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"practice-camera")
  let healthy=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:resolvedLaser.producer,sequence:resolvedLaser.sequence,updatedAtUnix:1000+now,
      mode:"hardware",state:"off",laserOn:false,offSinceUnix:999+now,detail:"Synthetic healthy OFF")
  try JSONEncoder().encode(healthy).write(to:resolvedLaser.directory.appendingPathComponent("status.json"),options:.atomic)
  resolvedLaser.tick();resolvedLaser.showAgain()
  check(!resolvedLaser.gameFaultNeedsRecheck && resolved.snapshot?.guidanceInterruption != nil,"Resolved native fault can retain a stale pause explanation before Resume")
  check(resolved.returnFromPracticePosition() && !resolvedLaser.gameFaultNeedsRecheck && resolved.snapshot?.guidanceInterruption==nil,"Return cannot re-latch a resolved test fault into healthy prior game")
  check(try Data(contentsOf:resolvedFolder.appendingPathComponent("current.json"))==resolvedOriginal,"Resolved test fault does not alter healthy original snapshot")
  checks += try await PhysicalAIPracticeCaptureReviewTests.run()
  print("PASS \(checks) actual practice-position persistence/controller checks")
 }
}
