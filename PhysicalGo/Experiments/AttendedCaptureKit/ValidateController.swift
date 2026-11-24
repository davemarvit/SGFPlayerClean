import Foundation
@testable import PhysicalGoTestRuntime

/// Runs only against copied fixtures and synthetic observations, never cameras,
/// live preferences or app storage. Link against an existing reviewed runtime.
@main struct ValidateCaptureKit {
 @MainActor static func main() async throws {
  guard CommandLine.arguments.count==2 else {fatalError("Usage: ValidateCaptureKit FIXTURE_DIRECTORY")}
  let fixtures=URL(fileURLWithPath:CommandLine.arguments[1])
  let temp=FileManager.default.temporaryDirectory.appendingPathComponent("capture-operator-kit-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:temp)}
  var checks=0,now=100.0
  func check(_ value:Bool,_ detail:String){precondition(value,detail);checks+=1}
  for (label,next,prisoners) in [("single-white-prisoner",1,[0]),("two-white-prisoners",38,[0,19])] {
   let folder=temp.appendingPathComponent(label)
   try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   try FileManager.default.copyItem(at:fixtures.appendingPathComponent(label+"/current.json"),to:folder.appendingPathComponent("current.json"))
   let saved=try JSONDecoder().decode(PhysicalAI.Snapshot.self,from:Data(contentsOf:folder.appendingPathComponent("current.json")))
   check(saved.moves.count==4 && saved.settings.humanBlack && saved.settings.size==19 && saved.settings.fastTestMode==true,"Actual snapshot decoder accepts human Black fixture")
   check(saved.moves.allSatisfy {$0.decisionReceivedAtUnix==nil} && saved.captureIndication==nil && saved.verifiedPosition==nil,"Fixture asserts no camera evidence or observed move times")
   let laser=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false)
   let ai=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:laser,uptime:{now})
   check(ai.phase == .paused && ai.error==nil && ai.snapshot?.id==saved.id,"Actual initializer restores paused synthetic session")
   func feed(_ cells:[String]) {
    for _ in 0..<3 {
     now+=0.25
     var observation=BoardObservation(readings:cells.enumerated().map {.init(row:$0.offset/19,col:$0.offset%19,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:19)
     observation.capturedAt=now;observation.handObstructed=false
     ai.consume(observation,now:now)
    }
   }
   ai.resume();feed(ai.cells)
   check(ai.phase == .human && ai.turn == .black,"Resume requires matching synthetic board before human turn")
   var physical=ai.cells;physical[next]="black";feed(physical)
   check(ai.snapshot!.moves.count==5 && ai.lastCapturePoints==prisoners && !ai.snapshot!.pendingPlacement,"Real human capture commits fifth move with exact prisoners")
   check(ai.snapshot!.captureIndication?.moveNumber==5 && ai.snapshot!.captureIndication!.acceptedAtUnix>0,"Attended-event path creates new capture context rather than fixture inventing it")
   let held=prisoners.count>=2
   check(ai.captureCleanupPending==held && (ai.timing.anchor==nil)==held,"Single runs next clock; two prisoners hold elapsed clock")
   let elapsed=ai.timing.elapsed(black:false,at:now)
   now+=1;feed(physical)
   check(held ? ai.timing.elapsed(black:false,at:now)==elapsed:ai.timing.elapsed(black:false,at:now)>elapsed,"Delayed removal obeys actual clock policy")
   if held {
    physical[19]="empty";feed(physical)
    check(ai.snapshot!.moves.count==5 && ai.remainingCapturedStones==1 && ai.snapshot!.captureIndication?.removed==[19],"Out-of-order partial removal is preserved without phantom move")
    check(ai.timing.anchor==nil && ai.captureCleanupPending,"Partial removal retains two-stone cleanup clock hold")
   }
   for p in prisoners {physical[p]="empty"}
   feed(physical)
   check(ai.snapshot!.captureIndication==nil && !ai.captureCleanupPending && ai.timing.anchor != nil,"All positive removals clear capture state and run next clock")
   ai.pause()
  }
  print("PASS \(checks) actual snapshot/controller checks; synthetic observations only, temporary game storage")
 }
}
