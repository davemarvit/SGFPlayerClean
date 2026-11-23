// Real app controller, guidance and frame-broker regression; no devices or camera.
import Foundation
@main struct PhysicalLaserStandbyTests {
 @MainActor static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("laser-standby-"+UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  var checks=0
  func check(_ value:Bool,_ why:String) {precondition(value,why);checks+=1}
  final class Clock {var now=100.0;var wall=1000.0}
  let clock=Clock()
  func fixture(_ name:String)->PhysicalLaserGuidance {
   PhysicalLaserGuidance(directory:root.appendingPathComponent(name),automatic:false,wallTime:{clock.wall},uptime:{clock.now})
  }
  func request(_ laser:PhysicalLaserGuidance)->PhysicalLaserGuidance.Request {
   try! JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:laser.directory.appendingPathComponent("request.json")))
  }
  func frame(_ laser:PhysicalLaserGuidance,hand:Bool?=false,valid:Bool=true) {
   clock.now+=0.1;clock.wall+=0.1
   let f=PhysicalLaserFrameBroker.Frame(streamEpoch:laser.frames.streamEpoch,frameID:100,capturedAtUptime:clock.now,arrivedAtUptime:clock.now,capturedAtUnix:clock.wall,timestampSource:"cameraPresentation",presentationSeconds:clock.now)
   laser.noteFrame(f);laser.observeCamera(hand:hand,valid:valid,capturedAt:clock.now,now:clock.now,context:"camera/grid")
  }
  func status(_ laser:PhysicalLaserGuidance,state:String="off",capable:Bool=true,mutate:((inout PhysicalLaserGuidance.DriverStatus)->Void)?=nil) throws {
   let r=request(laser)
   let dark=state=="holding" || state=="cooling"
   let evidence=PhysicalLaserGuidance.EvidenceAfter(streamEpoch:laser.frames.streamEpoch,frameID:1,timestampSource:"cameraPresentation")
   var s=PhysicalLaserGuidance.DriverStatus(schemaVersion:r.schemaVersion,producer:laser.producer,sequence:r.sequence,updatedAtUnix:clock.wall,mode:"hardware",state:state,laserOn:false,offSinceUnix:state=="off" ? clock.wall-1:nil,detail:state,evidenceAfter:state=="off" ? evidence:nil,setupId:"setup-1",capabilities:capable ? ["darkMotorStandbyV1","capturedStoneIndication","stoneCenteringWiggle"]:[],playSession:r.playSession,cameraContext:r.cameraContext,streamEpoch:r.streamEpoch,motorsHeld:state=="holding",motorBusPowered:dark,beamOffSinceUnix:dark ? clock.wall-1:nil,darkEvidenceAfter:dark ? evidence:nil,thermal:.init(policy:state=="cooling" ? "cooling":"warm_hold",sampleSequence:1,receivedAtUnix:clock.wall,sampleAgeUpperMs:100,baseC:20,tiltC:21,maxBaseC:22,maxTiltC:23,baseTrendCPerMinute:0.2,tiltTrendCPerMinute:-0.1,unavailableReason:dark ? nil:"power_off"))
   mutate?(&s)
   try JSONEncoder().encode(s).write(to:laser.directory.appendingPathComponent("status.json"),options:.atomic);laser.tick()
  }
  func change(_ s:inout PhysicalLaserGuidance.DriverStatus,_ fields:[String:Any]) {
   var object=try! JSONSerialization.jsonObject(with:JSONEncoder().encode(s)) as! [String:Any]
   for (key,value) in fields {object[key]=value}
   s=try! JSONDecoder().decode(PhysicalLaserGuidance.DriverStatus.self,from:JSONSerialization.data(withJSONObject:object))
  }
  let session=PhysicalLaserGuidance.PlaySession(source:"ai",session:UUID(),size:9)
  func activate(_ laser:PhysicalLaserGuidance) throws {
   laser.setPlaySession(session);laser.setStandbyEnabled(true);laser.setEnabled(true);frame(laser)
   check(request(laser).schemaVersion==1 && request(laser).action=="off","Initial legacy OFF discovers capability")
   try status(laser)
   check(request(laser).schemaVersion==2 && request(laser).action=="off","Capability requires new schema2 OFF handshake")
   try status(laser)
   check(request(laser).action=="standby" && request(laser).target==nil && request(laser).retainOnly==false,"Fresh schema2 true OFF permits clear standby")
   try status(laser,state:"holding")
  }
  let l=fixture("normal")
  check(!l.standbyEnabled,"Persistent holding is opt-in and initially off")
  try activate(l)
  check(l.mayHaveMotorSession,"Dark holding tracks live motor session independently of beam")
  check(l.motorMessage=="Holding · laser off" && l.temperatureMessage.contains("20°C") && l.temperatureMessage.contains("max 22°C"),"Fresh physical holding and current/max/trend displayed")
  check(l.acceptsObservation(capturedAt:clock.now,now:clock.now),"Matching fresh powered darkness permits recognition")
  let seq=l.sequence;frame(l,hand:true)
  check(request(l).action=="standby" && request(l).retainOnly==true && l.sequence>seq,"Hand creates distinct immutable retain-only revision")
  try status(l,state:"holding")
  frame(l,hand:false)
  check(request(l).retainOnly==false,"Clear observation creates new normal standby permission")
  try status(l,state:"cooling")
  check(l.motorMessage=="Cooling · motors released" && l.acceptsObservation(capturedAt:clock.now,now:clock.now),"Cooling is released yet powered dark evidence, not OFF")
  l.setEnabled(false)
  check(request(l).schemaVersion==2 && request(l).action=="off" && l.mayHaveMotorSession,"Disable keeps schema2 OFF renewal until actual power-off")
  try status(l,state:"holding")
  check(l.mayHaveMotorSession && request(l).action=="off","Darkness cannot acknowledge disable")
  try status(l)
  check(!l.mayHaveMotorSession && request(l).schemaVersion==1,"Full OFF completes shutdown before legacy fallback")
  check(l.temperatureMessage=="Temperature unavailable","Powered-off cached readings are not current temperatures")

  // Each unsafe receipt is tested against a newly admitted real controller so a
  // fault latch cannot accidentally make subsequent rejection cases vacuous.
  let cases:[(String,(inout PhysicalLaserGuidance.DriverStatus)->Void)]=[
   ("missing capability",{$0.capabilities=[]}),
   ("simulation holding",{change(&$0,["mode":"simulation"])}),
   ("insufficient optical flush",{$0.beamOffSinceUnix=clock.wall-0.1}),
   ("wrong session",{$0.playSession = .init(source:"ai",session:UUID(),size:9)}),
   ("wrong context",{$0.cameraContext="other"}),
   ("wrong epoch",{$0.streamEpoch=UUID()}),
   ("wrong setup",{$0.setupId="other"}),
   ("old watermark",{$0.darkEvidenceAfter = .init(streamEpoch:UUID(),frameID:1,timestampSource:"cameraPresentation")}),
   ("same frame",{$0.darkEvidenceAfter = .init(streamEpoch:$0.streamEpoch!,frameID:100,timestampSource:"cameraPresentation")}),
   ("callback without bound",{$0.darkEvidenceAfter = .init(streamEpoch:$0.streamEpoch!,frameID:1,timestampSource:"callback")}),
   ("missing thermal age",{$0.thermal?.sampleAgeUpperMs=nil}),
   ("stale thermal",{$0.thermal?.sampleAgeUpperMs=751}),
   ("missing thermal",{$0.thermal=nil}),
   ("future thermal receipt",{$0.thermal?.receivedAtUnix=clock.wall+1}),
   ("inconsistent thermal age",{$0.thermal?.receivedAtUnix=clock.wall-0.4;$0.thermal?.sampleAgeUpperMs=100}),
   ("stale receipt",{$0 = .init(schemaVersion:$0.schemaVersion,producer:$0.producer,sequence:$0.sequence,updatedAtUnix:clock.wall-0.8,mode:$0.mode,state:$0.state,laserOn:false,offSinceUnix:nil,detail:"stale")}),
   ("temperature unavailable",{$0.thermal?.unavailableReason="stale"}),
   ("50C trip",{$0.thermal?.tiltC=50}),
   ("missing held confirmation",{$0.motorsHeld=nil}),
   ("bus off in holding",{$0.motorBusPowered=false}),
   ("old revision",{$0 = .init(schemaVersion:$0.schemaVersion,producer:$0.producer,sequence:$0.sequence-1,updatedAtUnix:clock.wall,mode:$0.mode,state:"holding",laserOn:false,offSinceUnix:nil,detail:"old")})
  ]
  for (name,mutation) in cases {
   let x=fixture(name);try activate(x)
   check(x.acceptsObservation(capturedAt:clock.now,now:clock.now),"Case starts with accepted dark evidence: \(name)")
   try status(x,state:"holding",mutate:mutation)
   check(!x.acceptsObservation(capturedAt:clock.now,now:clock.now),"Reject unsafe powered darkness: \(name)")
   if name.contains("thermal") || name=="temperature unavailable" || name=="50C trip" {
    check(request(x).action=="off" && x.holdingInterrupted,"Bad thermal receipt also stops motor permission: \(name)")
   }
  }
  let trip=fixture("trip-ui");try activate(trip)
  try status(trip,state:"holding",mutate:{$0.thermal?.baseC=50;$0.thermal?.maxBaseC=50})
  check(request(trip).action=="off" && trip.holdingInterrupted,"Valid 50C trip remains an immediate OFF latch")
  check(trip.temperatureMessage.contains("50°C") && trip.motorMessage.contains("stopped"),"Fresh trip reading stays visible with stopped message")
  try status(trip)
  check(trip.temperatureMessage=="Temperature unavailable","Full OFF cannot present retained trip temperature as live")
  let sim=fixture("sim-discovery");sim.setPlaySession(session);sim.setStandbyEnabled(true);sim.setEnabled(true);frame(sim)
  try status(sim,mutate:{change(&$0,["mode":"simulation"])})
  check(request(sim).schemaVersion==1 && !sim.standbyAvailable,"Simulation cannot advertise a commissioned hardware holding capability")
  let falseOff=fixture("sim-off");try activate(falseOff);falseOff.setEnabled(false)
  try status(falseOff,mutate:{change(&$0,["mode":"simulation"])})
  check(falseOff.mayHaveMotorSession && request(falseOff).schemaVersion==2,"Simulation OFF cannot complete hardware motor shutdown")
  try status(falseOff);check(!falseOff.mayHaveMotorSession,"Hardware OFF completes the retained shutdown")
  let initialFault=fixture("initial-fault");initialFault.setPlaySession(session);initialFault.setStandbyEnabled(true);initialFault.setEnabled(true);frame(initialFault)
  try status(initialFault,mutate:{$0.requiresNewRevision=true;$0.reasonCode="driver_fault"})
  check(request(initialFault).schemaVersion==1 && request(initialFault).action=="off" && initialFault.holdingInterrupted,"Initial true OFF fault cannot be bypassed by schema negotiation")
  try status(initialFault);check(request(initialFault).schemaVersion==1,"Healthy heartbeat alone cannot clear initial fault latch")
  initialFault.showAgain();try status(initialFault)
  check(request(initialFault).schemaVersion==2 && request(initialFault).action=="off","Explicit retry still requires full schema2 OFF handshake")

  let stateFault=fixture("initial-state-fault");stateFault.setPlaySession(session);stateFault.setStandbyEnabled(true);stateFault.setEnabled(true);frame(stateFault)
  try status(stateFault,state:"fault")
  check(stateFault.holdingInterrupted && request(stateFault).action=="off","Initial fault state does not depend on optional requiresNewRevision flag")
  try status(stateFault)
  check(request(stateFault).schemaVersion==1 && stateFault.holdingInterrupted,"Later healthy OFF cannot erase initial explicit fault state")

  func beginArming(_ name:String) throws -> PhysicalLaserGuidance {
   let x=fixture(name);x.setPlaySession(session);x.setStandbyEnabled(true);x.setEnabled(true);frame(x);try status(x);try status(x)
   try status(x,state:"arming",mutate:{$0.thermal?.unavailableReason="bootstrap"})
   return x
  }
  let boot=try beginArming("bootstrap")
  check(!boot.holdingInterrupted && request(boot).action=="standby","Bounded dark cold arming may await first causal sample")
  check(!boot.acceptsObservation(capturedAt:clock.now,now:clock.now),"Arming never supplies dark recognition evidence")
  for i in 0..<25 {
   clock.now+=0.4;clock.wall+=0.4;frame(boot);try status(boot,state:"arming",mutate:{$0.thermal?.unavailableReason="bootstrap"})
   if i==10 {boot.setTarget(.init(source:"ai",session:session.session,moveNumber:2,size:9,row:2,col:2,black:true,decisionReceivedAtUnix:clock.wall))}
  }
  check(boot.holdingInterrupted && request(boot).action=="off","Fresh arming heartbeat and target revisions cannot extend original 12s deadline")
  let badBoot=try beginArming("bootstrap-beam")
  try status(badBoot,state:"arming",mutate:{change(&$0,["laserOn":true]);$0.thermal?.unavailableReason="bootstrap"})
  check(badBoot.holdingInterrupted && request(badBoot).action=="off","Bootstrap can never claim a powered beam")
  let unexpected=try beginArming("unexpected-light-flush")
  try status(unexpected,state:"arming",mutate:{change(&$0,["laserOn":true]);$0.thermal?.unavailableReason="bootstrap"})
  unexpected.setEnabled(false);try status(unexpected)
  try status(unexpected,mutate:{change(&$0,["offSinceUnix":clock.wall])})
  frame(unexpected)
  check(!unexpected.acceptsObservation(capturedAt:clock.now,now:clock.now),"Unexpected light during dark-only operation still requires optical flush after genuine OFF")
  clock.now+=0.25;clock.wall+=0.25;frame(unexpected)
  check(unexpected.acceptsObservation(capturedAt:clock.now,now:clock.now),"Fresh post-watermark frame after optical flush releases disabled recognition")
  let falseDark=try beginArming("bootstrap-receipt")
  try status(falseDark,state:"arming",mutate:{$0.beamOffSinceUnix=clock.wall-1;$0.thermal?.unavailableReason="bootstrap"})
  check(falseDark.holdingInterrupted,"Bootstrap cannot claim an optical dark receipt")
  let moved=try beginArming("bootstrap-motion")
  try status(moved,state:"approaching",mutate:{$0.thermal?.unavailableReason="bootstrap"})
  check(moved.holdingInterrupted && request(moved).action=="off","Approaching must have valid telemetry; no bootstrap exemption during movement")

  let toggle=fixture("toggle-off");try activate(toggle);toggle.setStandbyEnabled(false)
  check(request(toggle).schemaVersion==2 && request(toggle).action=="off","Opt-out retains schema2 shutdown contract")
  try status(toggle,state:"holding");check(toggle.mayHaveMotorSession,"Opt-out still waits despite darkness")
  try status(toggle);check(request(toggle).schemaVersion==1 && !toggle.mayHaveMotorSession,"Opt-out returns to legacy only after actual full OFF")
  let changeGame=fixture("change-game");try activate(changeGame);changeGame.setPlaySession(.init(source:"ai",session:UUID(),size:9))
  check(request(changeGame).action=="off","New game identity cannot reuse old game motor hold")
  let cameraChange=fixture("context-transition");try activate(cameraChange)
  cameraChange.setTarget(.init(source:"ai",session:session.session,moveNumber:1,size:9,row:1,col:1,black:true,decisionReceivedAtUnix:clock.wall));try status(cameraChange,state:"holding")
  var emitted=[PhysicalLaserGuidance.Request]();cameraChange.onRequestPublished={emitted.append($0)}
  cameraChange.observeCamera(hand:false,valid:true,capturedAt:clock.now,now:clock.now,context:"new-camera/grid")
  check(!emitted.isEmpty && emitted.allSatisfy {$0.action=="off"},"Changed camera scope never emits an intermediate active old-context request")
  for state in ["arming","approaching","adequate","refining","spot_not_found","unknown"] {
   let scope=fixture("active-scope-"+state);try activate(scope)
   try status(scope,state:state,mutate:{$0.cameraContext="other";$0.motorBusPowered=true})
   check(request(scope).action=="off" && scope.holdingInterrupted,"Every active or unknown status is scoped before permission: \(state)")
  }
  let hard=fixture("hard-controller-fault");try activate(hard)
  try status(hard,state:"fault",mutate:{$0.reasonCode="controller_fault";$0.requiresNewRevision=true})
  check(hard.controllerResetRequired && hard.motorMessage.contains("reset required"),"Hard controller latch explains physical reset requirement")
  hard.showAgain();check(hard.controllerResetRequired && request(hard).action=="off","Native Retry cannot clear controller hard latch")
  try status(hard,mutate:{$0.reasonCode="controller_fault";$0.requiresNewRevision=true})
  hard.showAgain();check(hard.controllerResetRequired,"Even full OFF cannot bypass a retained controller fault")
  try status(hard)
  hard.showAgain();check(!hard.controllerResetRequired && request(hard).action=="off","Recheck after independently healthy full OFF starts a fresh handshake; it never resets firmware")
  let age=fixture("causal-age");try activate(age)
  try status(age,state:"holding",mutate:{$0.thermal?.sampleAgeUpperMs=650})
  clock.now+=0.15;clock.wall+=0.15
  check(!age.acceptsObservation(capturedAt:clock.now-0.15,now:clock.now),"Status transport age adds to causal motor sample bound")

  let coldHand=fixture("cold-hand");coldHand.setPlaySession(session);coldHand.setStandbyEnabled(true);coldHand.setEnabled(true);frame(coldHand,hand:true)
  try status(coldHand);try status(coldHand)
  check(request(coldHand).retainOnly==true,"Hand at admission cannot request cold arming or cooling reengagement")
  frame(coldHand,hand:nil)
  check(request(coldHand).action=="off","Unknown hand evidence cannot retain motors")
  let noGame=fixture("no-game");noGame.setStandbyEnabled(true);noGame.setEnabled(true);frame(noGame);try status(noGame)
  check(request(noGame).schemaVersion==1 && request(noGame).action=="off","Opt-in without active game cannot establish motor session")
  noGame.setPlaySession(.init(source:"ai",session:UUID(),size:12));try status(noGame)
  check(noGame.playSession==nil && request(noGame).action=="off","Invalid play identity cannot authorize holding")
  let legacy=fixture("legacy");legacy.setPlaySession(session);legacy.setStandbyEnabled(true);legacy.setEnabled(true);frame(legacy);try status(legacy,capable:false)
  check(request(legacy).schemaVersion==1 && request(legacy).playSession==nil && request(legacy).retainOnly==nil,"Old driver sees unchanged schema1 contract")
  legacy.setTarget(.init(source:"ai",session:session.session,moveNumber:1,size:9,row:0,col:0,black:true,decisionReceivedAtUnix:clock.wall));try status(legacy,capable:false);frame(legacy);legacy.verifyMoveTarget(capturedAt:clock.now,now:clock.now)
  check(request(legacy).action=="point" && request(legacy).schemaVersion==1,"Legacy per-indication pointing remains available")

  let fault=fixture("session-fault");try activate(fault)
  try status(fault,state:"holding",mutate:{$0.requiresNewRevision=true;$0.reasonCode="thermal_fault"})
  check(fault.holdingInterrupted && request(fault).action=="off","Fault latches even without a pending target")
  fault.setTarget(.init(source:"ai",session:session.session,moveNumber:2,size:9,row:1,col:1,black:true,decisionReceivedAtUnix:clock.wall));frame(fault);try status(fault);fault.verifyMoveTarget(capturedAt:clock.now,now:clock.now)
  check(request(fault).action=="off","Next target cannot erase active-session thermal fault")
  fault.setTarget(nil);frame(fault);try status(fault)
  check(request(fault).action=="off","Target clearing cannot erase active-session thermal fault")

  fault.setStandbyEnabled(false);try status(fault)
  check(request(fault).schemaVersion==1 && request(fault).action=="off","Faulted opt-out can complete actual motor shutdown")
  fault.setTarget(.init(source:"ai",session:session.session,moveNumber:3,size:9,row:3,col:3,black:true,decisionReceivedAtUnix:clock.wall));frame(fault);try status(fault);fault.verifyMoveTarget(capturedAt:clock.now,now:clock.now)
  check(request(fault).action=="off" && fault.holdingInterrupted,"Legacy fallback cannot bypass monitored session fault on a later move")
  let another=PhysicalLaserGuidance.PlaySession(source:"ai",session:UUID(),size:9)
  fault.setPlaySession(another);fault.setTarget(.init(source:"ai",session:another.session,moveNumber:1,size:9,row:4,col:4,black:true,decisionReceivedAtUnix:clock.wall));frame(fault);try status(fault);fault.verifyMoveTarget(capturedAt:clock.now,now:clock.now)
  check(request(fault).action=="off" && fault.holdingInterrupted,"Changing game identity is not an explicit hardware fault retry")
  fault.showAgain();frame(fault);try status(fault);fault.verifyMoveTarget(capturedAt:clock.now,now:clock.now)
  check(request(fault).action=="point","Explicit retry plus fresh dark evidence can restore legacy indication")

  // Exercise actual AI lifecycle; status receipts cannot mutate game records or
  // clocks, even when placement is pending. Only board consumption owns those.
  let folder=root.appendingPathComponent("ai");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  var settings=PhysicalAISettings();settings.size=9;settings.humanBlack=false
  let saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:[.init(point:40,decisionReceivedAtUnix:999)],pendingPlacement:true,timing:PhysicalAITiming(blackToPlay:false))
  try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
  let aiLaser=fixture("ai-bridge")
  let ai=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:aiLaser,uptime:{clock.now},wallTime:{clock.wall})
  check(aiLaser.playSession==nil,"Loaded paused game has no motor permission")
  ai.resume();check(aiLaser.playSession?.session==saved.id,"Resume publishes explicit active AI identity")
  aiLaser.setStandbyEnabled(true);aiLaser.setEnabled(true);frame(aiLaser);try status(aiLaser);try status(aiLaser)
  let prior=try JSONEncoder().encode(ai.snapshot),timing=ai.timing
  try status(aiLaser,state:"holding");try status(aiLaser,state:"cooling")
  check(ai.snapshot!.moves.count==1 && ai.snapshot!.pendingPlacement,"Holding/cooling acknowledgement never confirms AI placement")
  check(try JSONSerialization.jsonObject(with:prior) as! NSDictionary == JSONSerialization.jsonObject(with:JSONEncoder().encode(ai.snapshot)) as! NSDictionary,"Thermal acknowledgement cannot change saved game")
  check(ai.timing.anchor==timing.anchor && ai.timing.blackToPlay==timing.blackToPlay,"Thermal acknowledgement cannot change clock ownership or anchor")
  ai.pause();check(request(aiLaser).target==nil && request(aiLaser).alignmentPreparation==nil,"Schema2 OFF has no stale pending operation or alignment preparation")
  check(aiLaser.playSession==nil && request(aiLaser).action=="off" && request(aiLaser).schemaVersion==2,"Pause revokes session and requests actual full OFF")
  try status(aiLaser,state:"holding");check(aiLaser.mayHaveMotorSession,"Pause remains awaiting full motor shutdown despite dark receipt")
  try status(aiLaser);check(!aiLaser.mayHaveMotorSession,"Pause completes only at actual full OFF")

  // Optional exported fixtures are encoded by the production Swift types for
  // the host's independent parser. No runtime bridge directory is touched.
  if let path=ProcessInfo.processInfo.environment["PHYSICAL_GO_STANDBY_FIXTURES"] {
   let out=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
   let x=fixture("exports");try activate(x)
   try Data(contentsOf:x.directory.appendingPathComponent("request.json")).write(to:out.appendingPathComponent("swift-standby-clear.json"))
   x.setTarget(.init(source:"ai",session:session.session,moveNumber:1,size:9,row:4,col:4,black:true,decisionReceivedAtUnix:clock.wall))
   try status(x,state:"holding");x.verifyMoveTarget(capturedAt:clock.now,now:clock.now)
   check(request(x).action=="point","Export contains an actual admitted schema2 point")
   try Data(contentsOf:x.directory.appendingPathComponent("request.json")).write(to:out.appendingPathComponent("swift-point.json"))
   frame(x,hand:true)
   try Data(contentsOf:x.directory.appendingPathComponent("request.json")).write(to:out.appendingPathComponent("swift-standby-hand.json"))
   x.setEnabled(false)
   try Data(contentsOf:x.directory.appendingPathComponent("request.json")).write(to:out.appendingPathComponent("swift-off.json"))
  }
  if let path=ProcessInfo.processInfo.environment["PHYSICAL_GO_HOST_STATUS_FIXTURES"] {
   let files=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:path),includingPropertiesForKeys:nil).filter {$0.pathExtension=="json"}
   check(!files.isEmpty,"Host exported actual status fixtures")
   for file in files {
    let s=try JSONDecoder().decode(PhysicalLaserGuidance.DriverStatus.self,from:Data(contentsOf:file))
    check(s.schemaVersion==2 && s.mode=="hardware","Host schema2 decodes in actual Swift type: \(file.lastPathComponent)")
    if s.state=="off" {
     check(!s.laserOn && s.motorsHeld==false && s.motorBusPowered==false && s.offSinceUnix != nil,"Host OFF means complete hardware shutdown")
     check(s.thermal?.unavailableReason=="power_off","OFF thermal values are explicitly unavailable")
    } else if ["holding","cooling"].contains(s.state) {
     check(s.playSession?.valid==true && s.cameraContext != nil && s.streamEpoch != nil && s.setupId != nil,"Host powered darkness carries complete identity")
     check(!s.laserOn && s.motorBusPowered==true && s.motorsHeld==(s.state=="holding"),"Host hold/cooling motor truth matches native contract")
     check(s.beamOffSinceUnix != nil && s.darkEvidenceAfter != nil && s.offSinceUnix==nil && s.evidenceAfter==nil,"Host powered darkness is distinct from full OFF")
     check(s.thermal?.admissible(statusAge:0,updatedAtUnix:s.updatedAtUnix)==true,"Host causal thermal fields admit at publication time")
    } else {check(s.state=="arming" && !s.laserOn && s.darkEvidenceAfter==nil,"Host cold bootstrap is dark without recognition receipt")}
   }
  }
  print("PASS \(checks) monitored standby checks (real app types; no hardware)")
 }
}
