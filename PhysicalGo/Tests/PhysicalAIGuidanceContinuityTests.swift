import Foundation
@main struct PhysicalAIGuidanceContinuityTests {
 @MainActor static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("guidance-continuity-"+UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  var now=100.0,wall=1000.0,checks=0
  var frameID:UInt64=0
  func check(_ value:Bool,_ message:String){precondition(value,message);checks+=1}
  func fixture(_ name:String,pending:Bool=false,capture:Int=0,generate:PhysicalAI.Generate?=nil)throws->PhysicalAI {
   let folder=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   var settings=PhysicalAISettings();settings.size=9;settings.humanBlack=false
   let moves=capture==2 ? [1,0,10,9,18]:capture==1 ? [9,0,80,2,1]:[40]
   let saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:moves.map{.init(point:$0,decisionReceivedAtUnix:999)},pendingPlacement:pending,pendingCaptureCleanup:capture==2,
     captureIndication:capture>0 ? .init(moveNumber:5,acceptedAtUnix:999,removed:capture==2 ? [9]:[]):nil,timing:PhysicalAITiming(blackToPlay:false))
   try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
   let l=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,wallTime:{wall},uptime:{now})
   let ai=PhysicalAI(directory:folder,generate:generate ?? {_,_ in "pass"},laser:l,uptime:{now},wallTime:{wall});ai.resume();return ai
  }
  func request(_ l:PhysicalLaserGuidance)throws->PhysicalLaserGuidance.Request {
   try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:l.directory.appendingPathComponent("request.json")))
  }
  func status(_ l:PhysicalLaserGuidance,reason:String?="controller_fault",state:String="fault",sequence:Int?=nil,producer:UUID?=nil,age:Double=0,mode:String="hardware",tick:Bool=true)throws {
   let s=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:producer ?? l.producer,sequence:sequence ?? l.sequence,updatedAtUnix:wall-age,mode:mode,state:state,laserOn:false,offSinceUnix:state=="off" ? wall-1:nil,detail:state,evidenceAfter:state=="off" ? .init(streamEpoch:l.frames.streamEpoch,frameID:0,timestampSource:"cameraPresentation"):nil,reasonCode:reason,requiresNewRevision:state=="fault")
   try JSONEncoder().encode(s).write(to:l.directory.appendingPathComponent("status.json"),options:.atomic);if tick {l.tick()}
  }
  func camera(_ l:PhysicalLaserGuidance) {
   now+=0.25;wall+=0.25;frameID+=1
   l.noteFrame(.init(streamEpoch:l.frames.streamEpoch,frameID:frameID,capturedAtUptime:now,arrivedAtUptime:now,capturedAtUnix:wall,timestampSource:"cameraPresentation",presentationSeconds:now))
   l.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"grid")
  }
  func feed(_ ai:PhysicalAI,_ cells:[String],count:Int=3) {
   for _ in 0..<count {
    camera(ai.laser)
    var o=BoardObservation(readings:cells.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:9)
    o.capturedAt=now;o.handObstructed=false;ai.consume(o,now:now)
   }
  }
  // Closing the app uses this same shutdown() path. Delayed cancellation must
  // never be charged as play time, and a nested pause cannot restart cleanup.
  for (operation,capture) in [("pause",0),("shutdown",0),("shutdown",2)] {
   let name="manual-"+operation+"-\(capture)",ai=try fixture(name,pending:true,capture:capture),l=ai.laser
   l.setEnabled(true);camera(l);now+=2;wall+=2
   let before=ai.snapshot!,frozen=ai.timing.saved(at:now)
   var callbacks=0
   l.onRequestPublished={_ in
    guard callbacks==0 else {return};callbacks+=1
    check(ai.phase == .paused && ai.timing==frozen,"\(operation) freezes phase and clocks before request/process cancellation")
    now+=5;wall+=5;ai.pause()
   }
   if operation=="shutdown" {ai.shutdown()} else {ai.pause()}
   l.onRequestPublished=nil
   check(callbacks==1 && ai.timing==frozen,"\(operation) excludes delayed cleanup and tolerates nested pause")
   check(try request(l).action=="off" && l.playSession==nil,"\(operation) revokes laser target/session")
   let reopened=PhysicalAI(directory:root.appendingPathComponent(name),generate:{_,_ in "pass"},
    laser:PhysicalLaserGuidance(directory:root.appendingPathComponent(name+"-reopened"),automatic:false,wallTime:{wall},uptime:{now}),uptime:{now},wallTime:{wall})
   check(reopened.phase == .paused && reopened.timing==frozen,"\(operation) persists exact frozen clock across reconstruction")
   check(reopened.snapshot!.id==before.id && reopened.snapshot!.moves.map(\.point)==before.moves.map(\.point) && reopened.snapshot!.pendingPlacement,
    "\(operation) preserves pending placement and accepted history across reconstruction")
   check(reopened.snapshot!.pendingCaptureCleanup==before.pendingCaptureCleanup && reopened.snapshot!.captureIndication?.removed==before.captureIndication?.removed,
    "\(operation) preserves partial prisoner cleanup and its clock hold")
   check(reopened.snapshot!.guidanceInterruption==nil,"Intentional \(operation) does not fabricate a hardware fault")
  }

  // An ended AI game stays available as history after reopen but must not
  // require its old stones when recovering the grid on a cleared board.
  do {
   let name="ended-grid",ai=try fixture(name,pending:true),folder=root.appendingPathComponent(name)
   let suite="PhysicalGo.EndedGridTests."+UUID().uuidString,settings=UserDefaults(suiteName:suite)!
   defer {settings.removePersistentDomain(forName:suite)}
   func model(_ ai:PhysicalAI,_ suffix:String)->ExperimentModel {
    let isolated=folder.appendingPathComponent(suffix)
    let m=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,
     recordingStorage:isolated.appendingPathComponent("recordings"),settings:settings,diagnosticRoot:isolated.appendingPathComponent("diagnostics"),
     moveEvidenceRoot:isolated.appendingPathComponent("evidence"),stoneSetLibraryURL:isolated.appendingPathComponent("stones.json"),ai:ai,
     onlineBoard:PhysicalOnlineBoard(directory:isolated.appendingPathComponent("online"),announceOpponent:{},announceCorrection:{}))
    m.playMode = .ai;return m
   }
   let live=model(ai,"live")
   check(live.recoveryExpected.count==81 && live.recoveryExpected[40] == .black,"Unfinished AI position remains the recovery anchor")
   ai.pause()
   check(live.recoveryExpected.count==81 && live.recoveryExpected[40] == .black,"Manual pause preserves unfinished-board recovery")
   ai.finish()
   let saved=ai.snapshot!,savedData=try Data(contentsOf:folder.appendingPathComponent("current.json")),sgf=try Data(contentsOf:ai.savedURL!)
   check(live.recoveryExpected.isEmpty,"Ended AI history no longer anchors physical grid")
   let reopened=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:PhysicalLaserGuidance(directory:folder.appendingPathComponent("reopened-bridge"),automatic:false),uptime:{now},wallTime:{wall})
   let restored=model(reopened,"restored")
   check(reopened.phase == .finished && restored.recoveryExpected.isEmpty,"Reopened ended game permits cleared-board grid recovery")
   check(reopened.snapshot!.id==saved.id && reopened.snapshot!.moves.map(\.point)==saved.moves.map(\.point) && reopened.timing==ai.timing,"Ended-game reopen preserves identity, moves and clocks")
   check(try Data(contentsOf:folder.appendingPathComponent("current.json"))==savedData && Data(contentsOf:ai.savedURL!)==sgf,"Grid recovery inspection does not rewrite saved game or SGF")
  }
  for (name,capture,pending) in [("human",0,false),("placing",0,true),("single",1,true),("multiple",2,true)] {
   let ai=try fixture(name,pending:pending,capture:capture)
   if !pending {feed(ai,ai.cells);check(ai.phase == .human,"Fixture reaches human turn")}
   let l=ai.laser;l.setEnabled(true);camera(l)
   if name=="human" {check(l.target==nil && l.alignmentPreparation==nil,"Legacy human-turn fault has no target/preparation")}
   now+=2;wall+=2
   let saved=ai.snapshot!,timing=ai.timing.saved(at:now),detected=now
   var first=true
   l.onRequestPublished={r in
    if first {first=false;check(r.action=="off","OFF is published before game suspension");now+=5;wall+=5}
   }
   try status(l)
   check(ai.phase == .paused && !ai.active,"Hard fault automatically pauses \(name)")
   check(ai.timing==timing,"Clock freezes at detection before callback/file/process work for \(name)")
   check(ai.snapshot!.id==saved.id && ai.snapshot!.moves.map(\.point)==saved.moves.map(\.point) && ai.snapshot!.moves.map(\.decisionReceivedAtUnix)==saved.moves.map(\.decisionReceivedAtUnix),"Hard fault preserves accepted identity/history/receipt boundaries")
   check(ai.snapshot!.pendingPlacement==saved.pendingPlacement && ai.snapshot!.pendingCaptureCleanup==saved.pendingCaptureCleanup,"Fault retains placement and capture clock policy")
   check(ai.snapshot!.captureIndication?.removed==saved.captureIndication?.removed,"Partial prisoner ledger survives interruption")
   check(ai.snapshot!.guidanceInterruption=="controller_fault","Interruption persists for restart recovery")
   check(try request(l).action=="off" && l.playSession==nil,"Paused game revokes motor session")
   l.onRequestPublished=nil;now=detected+60;wall+=60
   try status(l)
   check(ai.timing==timing,"Repeated fault cannot recharge a paused clock")
   ai.resume();check(ai.phase == .paused,"Resume cannot bypass retained hard fault")
   let restored=PhysicalAI(directory:root.appendingPathComponent(name),generate:{_,_ in "pass"},laser:PhysicalLaserGuidance(directory:root.appendingPathComponent(name+"-restore"),automatic:false,wallTime:{wall},uptime:{now}),uptime:{now},wallTime:{wall})
   check(restored.phase == .paused && restored.timing==timing && restored.snapshot!.guidanceInterruption=="controller_fault","Restart preserves charged clock and recovery requirement")
   check(restored.laser.gameFaultNeedsRecheck && restored.laser.controllerResetRequired,"Relaunch restores native recheck requirement without fabricating hardware state")
   restored.resume();check(restored.phase == .paused,"Default disabled bridge after relaunch is not an explicit opt-out")
   camera(restored.laser);restored.confirmLaserPhysicallyOff();restored.resume()
   check(restored.phase == .paused,"Physical-off confirmation alone cannot resume before new camera evidence")
   camera(restored.laser);restored.resume();check(restored.phase == .paused,"Manual dark flush excludes early frames")
   camera(restored.laser);restored.resume();check(restored.active,"Explicit physical-off confirmation plus fresh flushed camera view enables camera-only Resume")
   check(restored.snapshot!.guidanceInterruption==nil && restored.snapshot!.laserRecheckReason=="controller_fault","Camera-only continuation clears pause reason but retains durable laser recheck")
   check(capture==2 ? restored.timing.anchor==nil:restored.snapshot!.pendingPlacement ? restored.timing.anchor != nil:true,"Resume retains multiple-capture clock hold")
   if name=="placing" {
    let r=restored.laser;r.setEnabled(true);r.setTarget(.init(source:"ai",session:restored.snapshot!.id,moveNumber:2,size:9,row:1,col:1,black:true,decisionReceivedAtUnix:wall));camera(r);try status(r,reason:nil,state:"off");r.verifyMoveTarget(capturedAt:now,now:now)
    check(try r.gameFaultNeedsRecheck && request(r).action=="off","Relaunch/manual fallback cannot bypass fault on re-enable or new target")
    r.showAgain();camera(r);try status(r,reason:nil,state:"off");r.verifyMoveTarget(capturedAt:now,now:now)
    check(try request(r).action=="point","Current healthy OFF plus explicit native recheck restores indication after relaunch")
   }
   if name=="human" {
    let again=PhysicalAI(directory:root.appendingPathComponent(name),generate:{_,_ in "pass"},laser:PhysicalLaserGuidance(directory:root.appendingPathComponent("second-relaunch-bridge"),automatic:false,wallTime:{wall},uptime:{now}),uptime:{now},wallTime:{wall})
    check(again.snapshot!.guidanceInterruption==nil && again.snapshot!.laserRecheckReason=="controller_fault" && again.laser.gameFaultNeedsRecheck && again.laser.controllerResetRequired,"Second relaunch preserves outstanding recheck after camera-only play")
    again.finish();check(again.start() && again.snapshot!.laserRecheckReason=="controller_fault","New game cannot erase durable controller/native recheck requirement")
   }
   // A same-process opt-out retains hardware/native latches for re-enable.
   camera(l);ai.confirmLaserPhysicallyOff();camera(l);camera(l);ai.resume()
   check(ai.active && l.controllerResetRequired && l.gameFaultNeedsRecheck,"Opt-out preserves controller/native hard latch")
   if name=="placing" {
    l.cameraStreamChanged();camera(l)
    check(!l.acceptsObservation(capturedAt:now,now:now),"New stream cannot borrow manual dark evidence from old epoch")
    camera(l)
    check(l.acceptsObservation(capturedAt:now,now:now),"Still-disabled physical-off choice can regain fresh new-stream proof without driver")
   }
   l.setEnabled(true);camera(l);try status(l,reason:nil,state:"off")
   check(try request(l).action=="off","Re-enable cannot silently bypass prior fault")
  }

  // Ignore evidence that does not establish a current enabled hardware fault.
  for kind in ["old-revision","other-producer","stale","simulation","disabled","unclassified","camera_frame_stale","request_lease_expired","hand_obstructed","camera_evidence_unavailable","arming","holding"] {
   let ai=try fixture("ignore-"+kind,pending:true),l=ai.laser;l.setEnabled(true);camera(l)
   let before=ai.snapshot!.moves.count
   switch kind {
   case "old-revision":try status(l,sequence:l.sequence-1)
   case "other-producer":try status(l,producer:UUID())
   case "stale":try status(l,age:1)
   case "simulation":try status(l,mode:"simulation")
   case "disabled":l.setEnabled(false);try status(l)
   case "unclassified":try status(l,reason:nil)
   case "camera_frame_stale","request_lease_expired","hand_obstructed","camera_evidence_unavailable":try status(l,reason:kind)
   default:try status(l,reason:nil,state:kind)
   }
   check(ai.active && ai.snapshot!.guidanceInterruption==nil && ai.snapshot!.moves.count==before,"Ignore non-hard/unowned receipt: \(kind)")
  }

  for code in ["laser_transport_fault","laser_setup_fault","laser_optical_fault","laser_operation_fault"] {
   let ai=try fixture("hard-"+code,pending:true),l=ai.laser;l.setEnabled(true);camera(l);try status(l,reason:code)
   check(ai.phase == .paused && ai.snapshot!.guidanceInterruption==code && !l.controllerResetRequired,"Explicit reviewed non-controller hard reason pauses without claiming firmware reset: \(code)")
  }

  func v2status(_ l:PhysicalLaserGuidance,state:String="off",mutate:((inout PhysicalLaserGuidance.DriverStatus)->Void)?=nil)throws {
   let r=try request(l),dark=state=="holding"
   let evidence=PhysicalLaserGuidance.EvidenceAfter(streamEpoch:l.frames.streamEpoch,frameID:0,timestampSource:"cameraPresentation")
   var d=PhysicalLaserGuidance.DriverStatus(schemaVersion:r.schemaVersion,producer:l.producer,sequence:r.sequence,updatedAtUnix:wall,mode:"hardware",state:state,laserOn:false,offSinceUnix:state=="off" ? wall-1:nil,detail:state,evidenceAfter:state=="off" ? evidence:nil,setupId:"setup",reasonCode:state=="fault" ? "controller_fault":nil,requiresNewRevision:state=="fault",capabilities:["darkMotorStandbyV1"],playSession:r.playSession,cameraContext:r.cameraContext,streamEpoch:r.streamEpoch,motorsHeld:dark,motorBusPowered:dark,beamOffSinceUnix:dark ? wall-1:nil,darkEvidenceAfter:dark ? evidence:nil,thermal:.init(policy:"warm_hold",sampleSequence:1,receivedAtUnix:wall,sampleAgeUpperMs:100,baseC:20,tiltC:20,unavailableReason:dark ? nil:"power_off"))
   mutate?(&d);try JSONEncoder().encode(d).write(to:l.directory.appendingPathComponent("status.json"),options:.atomic);l.tick()
  }
  for field in ["current","session","context","epoch","setup"] {
   let ai=try fixture("v2-"+field,pending:true),l=ai.laser;l.setStandbyEnabled(true);l.setEnabled(true);camera(l)
   try v2status(l);try v2status(l);try v2status(l,state:"holding")
   check(try request(l).action=="standby","Real schema2 handshake admits standby before fault test")
   try v2status(l,state:"fault",mutate:{d in
    switch field {
    case "session":d.playSession = .init(source:"ai",session:UUID(),size:9)
    case "context":d.cameraContext="other"
    case "epoch":d.streamEpoch=UUID()
    case "setup":d.setupId="other"
    default:break
    }
   })
   check(field=="current" ? ai.phase == .paused:ai.active,"Only fully scoped v2 fault pauses active AI: \(field)")
  }
  // Replay the actual receipts around the recorded 1.788-second gap. Only
  // identity and clock origin are rebound to this isolated game.
  func recordedReceipt(_ name:String,_ l:PhysicalLaserGuidance)throws {
   let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/GuidanceWarmHandoff")
   var raw=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent(name+".json"))) as! [String:Any]
   let shift=wall-(raw["updatedAtUnix"] as! Double),r=try request(l)
   raw["producer"]=l.producer.uuidString;raw["sequence"]=r.sequence;raw["updatedAtUnix"]=wall
   raw["playSession"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(r.playSession),options:.fragmentsAllowed)
   raw["cameraContext"]=r.cameraContext;raw["streamEpoch"]=r.streamEpoch?.uuidString;raw["setupId"]="setup"
   for key in ["offSinceUnix","beamOffSinceUnix"] {if let old=raw[key] as? Double {raw[key]=old+shift}}
   for key in ["evidenceAfter","darkEvidenceAfter"] {if var e=raw[key] as? [String:Any] {e["streamEpoch"]=l.frames.streamEpoch.uuidString;e["frameID"]=0;raw[key]=e}}
   if var t=raw["thermal"] as? [String:Any],let old=t["receivedAtUnix"] as? Double {t["receivedAtUnix"]=old+shift;raw["thermal"]=t}
   try JSONSerialization.data(withJSONObject:raw).write(to:l.directory.appendingPathComponent("status.json"),options:.atomic);l.tick()
  }
  let lost=try fixture("recorded-status-gap",pending:true),ll=lost.laser
  ll.setStandbyEnabled(true);ll.setEnabled(true);camera(ll)
  try v2status(ll);try v2status(ll);try v2status(ll,state:"holding")
  ll.verifyMoveTarget(capturedAt:now,now:now)
  check(try request(ll).action=="point","Recorded replay starts with actual pending-move indication")
  var recordedClicks=0;ll.onTargetIndicated={_ in recordedClicks+=1}
  try recordedReceipt("adequate",ll)
  check(recordedClicks==0,"Historical adequate fixture lacks actual optical source proof and cannot announce a fresh cue")
  ll.observeCamera(hand:true,valid:true,capturedAt:now,now:now,context:"grid")
  check(try request(ll).action=="standby","Recorded hand interruption requests warm standby")
  let lostMoves=lost.snapshot!.moves.map(\.point)
  now+=0.829;wall+=0.829;ll.tick()
  check(try request(ll).action=="off" && ll.holdingInterrupted && lost.active,"Missing status stops hardware while allowing a returning classified recovery")
  now+=1.7876689434051514-0.829;wall+=1.7876689434051514-0.829
  let lostTiming=lost.timing.saved(at:now)
  try recordedReceipt("off",ll)
  check(lost.phase == .paused && lost.snapshot!.guidanceInterruption=="driver_link_lost","Returning unclassified full OFF pauses the silently latched game")
  check(lost.timing==lostTiming && lost.snapshot!.moves.map(\.point)==lostMoves && lost.snapshot!.pendingPlacement,"Lost-link pause freezes clock and preserves pending move")
  now+=60;wall+=60;ll.tick()
  check(lost.timing==lostTiming && recordedClicks==0,"Silent OFF cannot charge placement time or announce another click")

  for code in ["hand_obstructed","camera_evidence_unavailable","camera_frame_stale","request_lease_expired"] {
   let ai=try fixture("returning-transient-"+code,pending:true),l=ai.laser
   l.setStandbyEnabled(true);l.setEnabled(true);camera(l)
   try v2status(l);try v2status(l);try v2status(l,state:"holding")
   now+=0.8;wall+=0.8;l.tick()
   try v2status(l,mutate:{$0.reasonCode=code})
   check(ai.active && l.recoveringCamera && !l.holdingInterrupted && !l.gameFaultNeedsRecheck,"Returning classified transient retains automatic recovery: \(code)")
   now+=3;wall+=3;l.tick()
   check(ai.active && !l.gameFaultNeedsRecheck,"Classified recovery cancels unresolved-link game pause: \(code)")
  }

  // A warm quiescence can take the recorded 1.788 seconds. Fresh scoped
  // transition heartbeats renew liveness without claiming darkness or a click.
  func transition(_ l:PhysicalLaserGuidance,mutate:((inout PhysicalLaserGuidance.DriverStatus)->Void)?=nil)throws {
   let r=try request(l)
   var d=PhysicalLaserGuidance.DriverStatus(schemaVersion:2,producer:l.producer,sequence:r.sequence,updatedAtUnix:wall,
     mode:"hardware",state:"transitioning",laserOn:true,offSinceUnix:nil,detail:"Waiting for warm quiescence",
     setupId:"setup",illuminationConfirmed:false,capabilities:["darkMotorStandbyV1"],playSession:r.playSession,
     cameraContext:r.cameraContext,streamEpoch:r.streamEpoch)
   mutate?(&d);try JSONEncoder().encode(d).write(to:l.directory.appendingPathComponent("status.json"),options:.atomic);l.tick()
  }
  let handoff=try fixture("warm-handoff",pending:true),hl=handoff.laser
  hl.setStandbyEnabled(true);hl.setEnabled(true);camera(hl)
  try v2status(hl);try v2status(hl);try v2status(hl,state:"holding")
  var clicks=0;hl.onTargetIndicated={_ in clicks+=1}
  for _ in 0..<8 {
   try transition(hl);camera(hl)
   check(try handoff.active && !hl.holdingInterrupted && request(hl).action=="standby","Fresh scoped handoff remains admitted across 1.788-second observed quiescence")
   check(!hl.acceptsObservation(capturedAt:now,now:now) && clicks==0,"Transition cannot authorize camera evidence or first-light audio")
  }
  try v2status(hl,state:"holding")
  check(handoff.active && !hl.holdingInterrupted,"Genuine dark holding completes bounded handoff")
  check(hl.acceptsObservation(capturedAt:now,now:now),"Only confirmed holding restores dark recognition")

  let prolonged=try fixture("transition-timeout",pending:true),pl=prolonged.laser
  pl.setStandbyEnabled(true);pl.setEnabled(true);camera(pl)
  try v2status(pl);try v2status(pl);try v2status(pl,state:"holding")
  let pendingBefore=prolonged.snapshot!.moves.map(\.point)
  let initialTransitionRevision=pl.sequence
  for i in 0..<13 {
   try transition(pl)
   if i==6 {pl.observeCamera(hand:true,valid:true,capturedAt:now,now:now,context:"grid")}
   camera(pl)
  }
  check(pl.sequence>initialTransitionRevision,"Handoff deadline spans hand-driven revision changes")
  check(prolonged.phase == .paused && prolonged.snapshot!.guidanceInterruption=="transition_timeout","Fresh transition heartbeats cannot renew beyond three seconds")
  check(try request(pl).action=="off" && prolonged.snapshot!.pendingPlacement && prolonged.snapshot!.moves.map(\.point)==pendingBefore,"Transition timeout preserves pending move and requests OFF")

  for invalid in ["illumination","watermark","beam-dark","session","context","epoch","setup"] {
   let ai=try fixture("bad-transition-"+invalid,pending:true),l=ai.laser
   l.setStandbyEnabled(true);l.setEnabled(true);camera(l)
   try v2status(l);try v2status(l);try v2status(l,state:"holding")
   try transition(l,mutate:{d in
    switch invalid {
    case "illumination":d.illuminationConfirmed=true
    case "watermark":d.evidenceAfter = .init(streamEpoch:l.frames.streamEpoch,frameID:0,timestampSource:"cameraPresentation")
    case "beam-dark":d.beamOffSinceUnix=wall-1
    case "session":d.playSession = .init(source:"ai",session:UUID(),size:9)
    case "context":d.cameraContext="other"
    case "epoch":d.streamEpoch=UUID()
    default:d.setupId="other"
    }
   })
   check(try request(l).action=="off" && l.holdingInterrupted,"Malformed/unrelated transition cannot maintain motor admission: \(invalid)")
   check(["illumination","watermark","beam-dark"].contains(invalid) ? ai.phase == .paused:ai.active,"Only owned malformed transition can pause this game: \(invalid)")
  }
  let absent=try fixture("link-never-returns",pending:true),al=absent.laser
  al.setStandbyEnabled(true);al.setEnabled(true);camera(al)
  try v2status(al);try v2status(al);try v2status(al,state:"holding")
  now+=0.8;wall+=0.8;al.tick()
  now+=3;wall+=3;al.tick()
  check(absent.phase == .paused && absent.snapshot!.guidanceInterruption=="driver_link_lost","Missing driver cannot leave own-session clock running after bounded recovery wait")

  let thermal=try fixture("native-thermal",pending:true),tl=thermal.laser;tl.setStandbyEnabled(true);tl.setEnabled(true);camera(tl)
  try v2status(tl);try v2status(tl);try v2status(tl,state:"holding")
  try v2status(tl,state:"holding",mutate:{$0.thermal?.baseC=50})
  check(thermal.phase == .paused && thermal.snapshot!.guidanceInterruption=="thermal_telemetry_unavailable","Fresh scoped native hard thermal failure pauses even before host fault classification")
  let online=try fixture("online");feed(online,online.cells);online.laser.setEnabled(true);camera(online.laser)
  online.laser.setPlaySession(.init(source:"online",session:UUID(),size:9));try status(online.laser)
  check(online.active && online.snapshot!.guidanceInterruption==nil,"Online-scoped fault cannot pause unrelated local AI")
  let oldGame=try fixture("old-game",pending:true),og=oldGame.laser;og.setEnabled(true);camera(og)
  let oldRevision=og.sequence;oldGame.finish();check(oldGame.start(),"Start a distinct game after old game ends")
  try status(og,sequence:oldRevision)
  check(oldGame.active && oldGame.snapshot!.guidanceInterruption==nil,"Old game fault cannot pause a new game")

  let during=try fixture("during-consume",pending:true),dl=during.laser;dl.setEnabled(true);camera(dl);try status(dl,reason:nil,state:"off")
  try status(dl,tick:false)
  var observed=during.cells;observed[40]="empty"
  var incoming=BoardObservation(readings:observed.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0)},size:9)
  incoming.capturedAt=now;incoming.handObstructed=false;during.consume(incoming,now:now)
  check(during.phase == .paused && during.snapshot!.pendingPlacement && during.snapshot!.moves.count==1,"Fault during target verification fences the remaining consume transaction")
  check(during.status.hasPrefix("AI game paused"),"Interrupted consume cannot overwrite the pause explanation")

  // Deliberate physical-off fallback after actual indication, with no driver
  // available to acknowledge OFF. No camera result predating the barrier works.
  let fallback=try fixture("illuminated-fallback",pending:true),fl=fallback.laser
  fl.setEnabled(true);camera(fl);try status(fl,reason:nil,state:"off");fl.verifyMoveTarget(capturedAt:now,now:now)
  check(try request(fl).action=="point","Fallback starts with a possibly illuminated operation")
  try status(fl);try FileManager.default.removeItem(at:fl.directory.appendingPathComponent("status.json"))
  let frozen=fallback.timing;camera(fl);fallback.confirmLaserPhysicallyOff();fallback.resume()
  check(fallback.phase == .paused && fallback.timing==frozen,"Explicit physical off does not restart clock before flushed evidence")
  camera(fl);fallback.resume();check(fallback.phase == .paused,"Early frame cannot bypass manual dark barrier")
  camera(fl);fallback.resume();check(fallback.phase == .placing,"New flushed timestamped camera evidence admits explicit camera-only Resume")
  feed(fallback,fallback.cells)
  check(fallback.phase == .human && !fallback.snapshot!.pendingPlacement,"Camera-only recognition remains usable without any driver OFF receipt")
  var reply=fallback.cells;reply[0]="white";feed(fallback,reply)
  check(fallback.snapshot!.moves.count==2,"Fresh camera-only play can accept the next legal human move")
  fl.setEnabled(true);fl.setTarget(.init(source:"ai",session:fallback.snapshot!.id,moveNumber:3,size:9,row:2,col:2,black:true,decisionReceivedAtUnix:wall));camera(fl);try status(fl,reason:nil,state:"off");fl.verifyMoveTarget(capturedAt:now,now:now)
  check(try fl.gameFaultNeedsRecheck && fl.controllerResetRequired && request(fl).action=="off","New move/re-enable cannot reuse physical-off override or bypass hard latch")

  // A real driver OFF plus explicit recheck permits disabled camera-only
  // recovery without claiming the user physically switched off the power.
  for schema2 in [false,true] {
   let ai=try fixture("disabled-driver-off-\(schema2)",pending:true),l=ai.laser
   func healthy()throws {
    if schema2 {try v2status(l)} else {try status(l,reason:nil,state:"off")}
   }
   l.setStandbyEnabled(schema2);l.setEnabled(true);camera(l)
   try healthy();try healthy()
   if schema2 {try v2status(l,state:"fault")} else {try status(l)}
   let saved=ai.snapshot!,frozen=ai.timing
   check(ai.phase == .paused && saved.pendingPlacement,"Driver fault pauses pending placement")
   l.setEnabled(false);camera(l);try healthy();ai.resume()
   check(ai.phase == .paused && ai.timing==frozen,"Fresh genuine OFF cannot bypass explicit recheck while disabled")
   l.setEnabled(true);camera(l);try healthy();try healthy();l.showAgain()
   check(!l.gameFaultNeedsRecheck && !l.controllerResetRequired && ai.phase == .paused,"Explicit recheck clears hardware requirement without resuming play")
   var actions:[String]=[]
   l.onRequestPublished={actions.append($0.action)}
   l.setEnabled(false)
   check(!l.readyToResumeFaultPausedGame(session:saved.id),"Disable requires a new matching OFF revision")
   camera(l);try healthy();try healthy()
   let statusURL=l.directory.appendingPathComponent("status.json")
   let good=try JSONSerialization.jsonObject(with:Data(contentsOf:statusURL)) as! [String:Any]
   for invalid in ["producer","revision","schema","stale","simulation","lit","not-off","revision-required","controller-fault","missing-watermark","watermark-epoch","watermark-frame","watermark-source","too-early"] {
    var bad=good
    switch invalid {
    case "producer":bad["producer"]=UUID().uuidString
    case "revision":bad["sequence"]=l.sequence-1
    case "schema":bad["schemaVersion"]=2
    case "stale":bad["updatedAtUnix"]=wall-1
    case "simulation":bad["mode"]="simulation"
    case "lit":bad["laserOn"]=true
    case "not-off":bad["state"]="holding"
    case "revision-required":bad["requiresNewRevision"]=true
    case "controller-fault":bad["reasonCode"]="controller_fault"
    case "missing-watermark":bad.removeValue(forKey:"evidenceAfter")
    case "too-early":bad["offSinceUnix"]=wall
    default:
     var watermark=bad["evidenceAfter"] as! [String:Any]
     if invalid=="watermark-epoch" {watermark["streamEpoch"]=UUID().uuidString}
     if invalid=="watermark-frame" {watermark["frameID"]=frameID}
     if invalid=="watermark-source" {watermark["timestampSource"]="callback"}
     bad["evidenceAfter"]=watermark
    }
    try JSONSerialization.data(withJSONObject:bad).write(to:statusURL,options:.atomic);l.tick()
    check(!l.readyToResumeFaultPausedGame(session:saved.id),"Disabled recovery rejects \(invalid), schema2=\(schema2)")
   }
   try healthy()
   check(l.readyToResumeFaultPausedGame(session:saved.id),"Explicit recheck and genuine post-OFF frame admit disabled recovery without manual confirmation")
   now+=1.6;wall+=1.6;try healthy()
   check(!l.readyToResumeFaultPausedGame(session:saved.id),"Fresh OFF cannot make an old clear camera frame current")
   camera(l);try healthy()
   l.noteFrame(.init(streamEpoch:l.frames.streamEpoch,frameID:frameID+1,capturedAtUptime:now+0.01,arrivedAtUptime:now+0.01,capturedAtUnix:wall+0.01,timestampSource:"cameraPresentation",presentationSeconds:now+0.01))
   check(!l.readyToResumeFaultPausedGame(session:saved.id),"Current frame cannot borrow another frame's clear verdict")
   camera(l);try healthy();ai.resume()
   check(ai.phase == .placing && !l.enabled && ai.snapshot!.pendingPlacement,"Disabled recovery resumes verification, not assumed placement")
   check(ai.snapshot!.id==saved.id && ai.snapshot!.moves.map(\.point)==saved.moves.map(\.point),"Dark recovery preserves accepted game history")
   var uncertain=ai.cells;uncertain[40]="uncertain"
   try healthy();feed(ai,uncertain,count:1)
   check(ai.snapshot!.pendingPlacement && ai.phase == .placing,"Uncertain occupied target cannot advance the game during dark verification")
   for _ in 0..<3 {try healthy();feed(ai,ai.cells,count:1)}
   check(ai.phase == .human && !ai.snapshot!.pendingPlacement,"Normal whole-board evidence confirms the already placed stone")
   check(!actions.isEmpty && actions.allSatisfy{$0=="off"},"Disabled recheck, Resume and placement verification never request point or standby")
   l.onRequestPublished=nil
  }

  // A queued engine result cannot commit after the fault callback returns.
  var continuation:CheckedContinuation<String,Never>?
  let thinkingFolder=root.appendingPathComponent("thinking")
  let thinkingLaser=PhysicalLaserGuidance(directory:thinkingFolder.appendingPathComponent("bridge"),automatic:false,wallTime:{wall},uptime:{now})
  let thinking=PhysicalAI(directory:thinkingFolder,generate:{_,_ in await withCheckedContinuation {continuation=$0}},laser:thinkingLaser,uptime:{now},wallTime:{wall})
  thinking.draft.size=9;thinking.draft.humanBlack=false;check(thinking.start(),"Start thinking fixture")
  feed(thinking,thinking.cells);await Task.yield()
  check(thinking.phase == .thinking && continuation != nil,"AI completion is pending")
  thinkingLaser.setEnabled(true);camera(thinkingLaser);try status(thinkingLaser,reason:"controller_fault")
  let pausedTiming=thinking.timing
  continuation?.resume(returning:"E5");await Task.yield();await Task.yield()
  check(thinking.phase == .paused && thinking.snapshot!.moves.isEmpty && thinking.timing==pausedTiming,"Late AI completion cannot commit or switch clocks after fault")

  // Healthy OFF/recheck is not a game resume; explicit Resume is still required.
  let recover=try fixture("recover",pending:true),rl=recover.laser;rl.setEnabled(true);camera(rl);try status(rl)
  camera(rl);try status(rl,reason:nil,state:"off");rl.showAgain()
  check(recover.phase == .paused,"Hardware/native recovery never resumes game automatically")
  try status(rl,reason:nil,state:"off");recover.resume()
  check(recover.phase == .placing && recover.snapshot!.pendingPlacement && recover.snapshot!.moves.count==1,"Explicit healthy Resume restores same pending AI move")
  check(recover.snapshot!.guidanceInterruption==nil && recover.snapshot!.laserRecheckReason==nil,"Healthy OFF plus explicit recheck clears durable requirement at the next saved checkpoint")
  if let path=ProcessInfo.processInfo.environment["PHYSICAL_GO_HOST_FAULT_STATUS_FIXTURES"] {
   struct Manifest:Decodable {
    struct Fixture:Decodable {let file:String;let expectedAutoPause:Bool}
    struct Recovery:Decodable {let reasonCode:String;let faultFile:String;let confirmedOffFile:String;let healthyOffFile:String}
    let fixtures:[Fixture];let recoverySequences:[Recovery]?
   }
   let folder=URL(fileURLWithPath:path)
   let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:folder.appendingPathComponent("manifest.json")))
   check(!manifest.fixtures.isEmpty,"Actual host fault fixture manifest is nonempty")
   func rebound(_ file:String,_ l:PhysicalLaserGuidance,sequence:Int?=nil)throws->[String:Any] {
    let r=try request(l)
    var raw=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent(file))) as! [String:Any]
    let previous=(raw["updatedAtUnix"] as? Double) ?? wall
    raw["schemaVersion"]=r.schemaVersion;raw["producer"]=l.producer.uuidString;raw["sequence"]=sequence ?? l.sequence;raw["updatedAtUnix"]=wall
    raw["playSession"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(r.playSession),options:.fragmentsAllowed)
    raw["cameraContext"]=r.cameraContext;raw["streamEpoch"]=l.frames.streamEpoch.uuidString;raw["setupId"]="setup"
    for key in ["offSinceUnix","beamOffSinceUnix"] {if let old=raw[key] as? Double {raw[key]=old+(wall-previous)}}
    for key in ["evidenceAfter","darkEvidenceAfter"] {if var e=raw[key] as? [String:Any] {e["streamEpoch"]=l.frames.streamEpoch.uuidString;e["frameID"]=frameID;raw[key]=e}}
    if var t=raw["thermal"] as? [String:Any],let old=t["receivedAtUnix"] as? Double {t["receivedAtUnix"]=old+(wall-previous);raw["thermal"]=t}
    return raw
   }
   func deliver(_ raw:[String:Any],_ l:PhysicalLaserGuidance)throws {
    let data=try JSONSerialization.data(withJSONObject:raw);_=try JSONDecoder().decode(PhysicalLaserGuidance.DriverStatus.self,from:data)
    try data.write(to:l.directory.appendingPathComponent("status.json"),options:.atomic);l.tick()
   }
   for item in manifest.fixtures {
    let ai=try fixture("host-"+item.file),l=ai.laser;feed(ai,ai.cells)
    l.setStandbyEnabled(true);l.setEnabled(true);camera(l);try v2status(l);try v2status(l);try v2status(l,state:"holding")
    check(try ai.phase == .human && l.target==nil && request(l).action=="standby","Host fixture starts in real targetless active-game v2 scope")
    let r=try request(l)
    var raw=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent(item.file))) as! [String:Any]
    let oldUpdated=(raw["updatedAtUnix"] as? Double) ?? wall
    raw["producer"]=l.producer.uuidString;raw["sequence"]=l.sequence;raw["updatedAtUnix"]=wall
    raw["playSession"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(r.playSession),options:.fragmentsAllowed)
    raw["cameraContext"]=r.cameraContext;raw["streamEpoch"]=l.frames.streamEpoch.uuidString;raw["setupId"]="setup"
    for key in ["offSinceUnix","beamOffSinceUnix"] {if let previous=raw[key] as? Double {raw[key]=previous+(wall-oldUpdated)}}
    for key in ["evidenceAfter","darkEvidenceAfter"] {if var evidence=raw[key] as? [String:Any] {evidence["streamEpoch"]=l.frames.streamEpoch.uuidString;raw[key]=evidence}}
    if var thermal=raw["thermal"] as? [String:Any],let received=thermal["receivedAtUnix"] as? Double {thermal["receivedAtUnix"]=received+(wall-oldUpdated);raw["thermal"]=thermal}
    let data=try JSONSerialization.data(withJSONObject:raw)
    _=try JSONDecoder().decode(PhysicalLaserGuidance.DriverStatus.self,from:data)
    try data.write(to:l.directory.appendingPathComponent("status.json"),options:.atomic);l.tick()
    check((ai.phase == .paused)==item.expectedAutoPause,"Actual host classification drives native pause correctly: \(item.file)")
    check(ai.snapshot!.moves.count==1,"Host fixture cannot fabricate a move")
   }
   check(manifest.recoverySequences?.count==4,"Actual host transient recovery chains are present")
   for chain in manifest.recoverySequences ?? [] {
    for mode in ["v2-point","v2-standby","v1-point","v1-off"] {
     let point=mode.hasSuffix("point"),v2=mode.hasPrefix("v2")
     let ai=try fixture("sequence-"+chain.reasonCode+mode,pending:point),l=ai.laser
     if !point {feed(ai,ai.cells)}
     l.setStandbyEnabled(v2);l.setEnabled(true);camera(l)
     if v2 {try v2status(l);try v2status(l);try v2status(l,state:"holding")}
     else {try status(l,reason:nil,state:"off")}
     if point {l.verifyMoveTarget(capturedAt:now,now:now)}
     let failed=l.sequence
     try deliver(rebound(chain.faultFile,l),l)
     let recoveryRevision=l.sequence
     check(ai.active && !l.gameFaultNeedsRecheck,"Bootstrap unknown-light transient is not a hard thermal diagnosis")
     check(try request(l).action=="off" && recoveryRevision>failed,"Transient issues a new OFF revision")
     try deliver(rebound(chain.confirmedOffFile,l,sequence:failed),l)
     try deliver(rebound(chain.faultFile,l,sequence:failed),l)
     check(try request(l).action=="off" && l.sequence==recoveryRevision,"Rejected original fault/OFF cannot authorize recovery or churn revisions")
     if mode=="v2-standby" {now+=1;wall+=1;l.tick();check(l.sequence==recoveryRevision && ai.active,"Delayed healthy OFF keeps scoped transient recovery pending")}
     if chain.reasonCode=="hand_obstructed",mode=="v2-point" {
      l.observeCamera(hand:true,valid:true,capturedAt:now,now:now,context:"grid")
      check(try request(l).action=="off" && ai.active,"Hand during transient OFF wait keeps recovery scoped and beam off")
     }
     var healthy=try rebound(chain.healthyOffFile,l)
     try deliver(healthy,l)
     check(try request(l).action=="off","Healthy new-revision OFF alone cannot restore marking")
     now+=0.35;wall+=0.35
     for i in 0..<3 {
      healthy["updatedAtUnix"]=wall;try deliver(healthy,l);camera(l)
      if point {l.verifyMoveTarget(capturedAt:now,now:now)}
      if i<2 {check(try request(l).action=="off","Three fresh clear post-watermark frames are required")}
     }
     check(try request(l).action==(point ? "point":v2 ? "standby":"off"),"Same operation recovers from actual host chain: \(chain.reasonCode)/\(mode)")
     check(!l.recoveringCamera && !l.suppressed && ai.active,"Recovery clears only transient state without pausing or changing game")
     if mode=="v1-off" {for _ in 0..<3 {healthy["updatedAtUnix"]=wall;try deliver(healthy,l)};check(l.sequence==recoveryRevision && !l.recoveringCamera,"Healthy reason echo cannot restart targetless v1 recovery")}
    }
   }
   if let chain=manifest.recoverySequences?.first {
    var pending:CheckedContinuation<String,Never>?
    let folder=root.appendingPathComponent("decision-during-recovery")
    let l=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,wallTime:{wall},uptime:{now})
    let ai=PhysicalAI(directory:folder,generate:{_,_ in await withCheckedContinuation {pending=$0}},laser:l,uptime:{now},wallTime:{wall})
    ai.draft.size=9;ai.draft.humanBlack=false;check(ai.start(),"Start AI decision/recovery fixture");feed(ai,ai.cells)
    for _ in 0..<10 {if pending != nil {break};await Task.yield()}
    check(ai.phase == .thinking && pending != nil,"Authoritative AI completion waits during targetless recovery")
    l.setStandbyEnabled(true);l.setEnabled(true);camera(l);try v2status(l);try v2status(l);try v2status(l,state:"holding")
    try deliver(rebound(chain.faultFile,l),l)
    let oldOFF=l.sequence
    let oldHealthy=try rebound(chain.healthyOffFile,l)
    pending?.resume(returning:"E5")
    for _ in 0..<10 {if ai.phase != .thinking {break};await Task.yield()}
    check(ai.phase == .placing && ai.snapshot!.moves.count==1 && l.sequence>oldOFF,"New AI target revokes old recovery evidence with a fresh OFF revision")
    try deliver(oldHealthy,l);check(try request(l).action=="off","Prior targetless healthy receipt cannot authorize new point")
    var healthy=try rebound(chain.healthyOffFile,l);try deliver(healthy,l);now+=0.35;wall+=0.35
    for i in 0..<3 {healthy["updatedAtUnix"]=wall;try deliver(healthy,l);camera(l);l.verifyMoveTarget(capturedAt:now,now:now);if i<2 {check(try request(l).action=="off","New decision needs its own three fresh frames")}}
    check(try request(l).action=="point" && l.target?.row==4 && l.target?.col==4 && ai.phase == .placing,"Same-game decision received during recovery resumes without a manual latch or phantom placement")

    let paused=try fixture("manual-pause-during-recovery",pending:true),pl=paused.laser
    pl.setStandbyEnabled(true);pl.setEnabled(true);camera(pl);try v2status(pl);try v2status(pl);try v2status(pl,state:"holding")
    pl.verifyMoveTarget(capturedAt:now,now:now);try deliver(rebound(chain.faultFile,pl),pl)
    let pausedID=paused.snapshot!.id,pausedMoves=paused.snapshot!.moves.map(\.point)
    paused.pause()
    check(try paused.phase == .paused && paused.snapshot!.pendingPlacement && paused.snapshot!.id==pausedID && paused.snapshot!.moves.map(\.point)==pausedMoves && request(pl).action=="off","Explicit Pause during transient recovery preserves pending game and requests full OFF")
    try deliver(rebound(chain.healthyOffFile,pl),pl)
    paused.resume();camera(pl);try v2status(pl);try v2status(pl);try v2status(pl)
    camera(pl);pl.verifyMoveTarget(capturedAt:now,now:now)
    check(try paused.phase == .placing && !pl.gameFaultNeedsRecheck && !pl.holdingInterrupted && request(pl).action=="point","Explicit Resume uses new OFF/camera admission without manufacturing a permanent transient latch")

    for mutation in ["session","context","epoch","setup","hard-controller","stone-seen","target-session","target-source","target-size"] {
     let ai=try fixture("blocked-recovery-"+mutation,pending:true),l=ai.laser
     l.setStandbyEnabled(true);l.setEnabled(true);camera(l);try v2status(l);try v2status(l);try v2status(l,state:"holding")
     l.verifyMoveTarget(capturedAt:now,now:now);try deliver(rebound(chain.faultFile,l),l)
     var healthy=try rebound(chain.healthyOffFile,l)
     switch mutation {
     case "session":healthy["playSession"]=["source":"ai","session":UUID().uuidString,"size":9]
     case "context":healthy["cameraContext"]="wrong-camera"
     case "epoch":healthy["streamEpoch"]=UUID().uuidString
     case "setup":healthy["setupId"]="wrong-setup"
     case "hard-controller":healthy["state"]="fault";healthy["reasonCode"]="controller_fault";healthy["requiresNewRevision"]=true
     case "target-session","target-source","target-size":
      l.setTarget(.init(source:mutation=="target-source" ? "online":"ai",session:mutation=="target-session" ? UUID():ai.snapshot!.id,
          moveNumber:1,size:mutation=="target-size" ? 19:9,row:4,col:4,black:true,decisionReceivedAtUnix:wall))
     default:l.suppress("stone_seen_at_target")
     }
     now+=0.35;wall+=0.35
     for _ in 0..<4 {healthy["updatedAtUnix"]=wall;try deliver(healthy,l);camera(l);l.verifyMoveTarget(capturedAt:now,now:now)}
     if mutation=="stone-seen" {
      let r=try request(l);check(r.action != "point" && l.suppressed && (r.action != "standby" || r.target==nil),"Observed stone remains optically suppressed; dark holding may continue")
     } else {check(try request(l).action=="off","Recovery cannot clear contradictory scope or stronger latch: \(mutation)")}
     if mutation=="hard-controller" {check(ai.phase == .paused && l.controllerResetRequired,"Hard controller fault during transient wait remains latched")}
    }
   }
  }
  print("PASS \(checks) automatic guidance-fault continuity checks")
 }
}
