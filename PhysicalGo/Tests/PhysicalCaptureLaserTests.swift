// Full-app suite: real guidance/frame-broker types; no hardware or camera startup.
import Foundation
@main struct PhysicalCaptureLaserTests {
 @MainActor static func main() throws {
  let directory=FileManager.default.temporaryDirectory.appendingPathComponent("capture-contract-"+UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:directory)}
  var now=100.0,wall=1000.0,checks=0,cues=0
  let laser=PhysicalLaserGuidance(directory:directory,automatic:false,wallTime:{wall},uptime:{now})
  func check(_ value:Bool,_ reason:String){precondition(value,reason);checks+=1}
  func request()->PhysicalLaserGuidance.Request {try! JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:directory.appendingPathComponent("request.json")))}
  func status(capable:Bool=true,state:String="off",lit:Bool=false,sequence:Int?=nil,requiresNew:Bool=false) throws {
   let value=PhysicalLaserGuidance.DriverStatus(schemaVersion:1,producer:laser.producer,sequence:sequence ?? laser.sequence,updatedAtUnix:wall,mode:lit ? "hardware":"simulation",state:state,laserOn:lit,offSinceUnix:wall-1,detail:state,requiresNewRevision:requiresNew,illuminationConfirmed:lit,capabilities:capable ? ["capturedStoneIndication"]:[])
   try JSONEncoder().encode(value).write(to:directory.appendingPathComponent("status.json"),options:.atomic);laser.tick()
  }
  func frame(){now+=0.25;wall+=0.25;laser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"grid")}
  let session=UUID()
  let capture=PhysicalLaserGuidance.Target(source:"ai",session:session,moveNumber:5,size:19,row:0,col:0,black:false,decisionReceivedAtUnix:999,purpose:"capture")
  laser.onTargetIndicated={_ in cues+=1}
  laser.setEnabled(true);laser.setTarget(capture);try status(capable:false);frame();laser.verifyCaptureTarget(capturedAt:now,now:now)
  check(request().action=="off" && request().target==nil,"Old backend receives compatible OFF without unknown capture purpose")
  try status();frame();laser.verifyEmptyTarget(capturedAt:now,now:now)
  // Existing positive capture evidence is allowed to remain valid after capability arrives.
  laser.invalidateCamera();frame();try status();laser.verifyEmptyTarget(capturedAt:now,now:now)
  check(request().action=="off","Empty verifier cannot authorize occupied capture")
  laser.verifyMoveTarget(capturedAt:now,now:now);check(request().action=="off","Move verifier cannot authorize capture")
  laser.verifyCaptureTarget(capturedAt:now,now:now);check(request().action=="point","Capture verifier admits stable caller evidence")
  try status(state:"adequate",lit:true);check(cues==0,"Capture never announces an opponent move")
  laser.observeCamera(hand:true,valid:true,capturedAt:now,now:now,context:"grid")
  check(request().action=="off" && laser.suppressed,"Hand immediately extinguishes capture")
  for i in 0..<3 {frame();try status();laser.verifyCaptureTarget(capturedAt:now,now:now);if i<2 {check(request().action=="off","Hand recovery requires repeated evidence")}}
  check(request().action=="point","Stable dark hand recovery restores prisoner")
  laser.suppress("capture_evidence_changed");check(request().action=="off","Suspected disappearance only requests OFF")
  for _ in 0..<3 {frame();try status();laser.verifyCaptureTarget(capturedAt:now,now:now)}
  check(request().action=="point","False removal suspicion recovers only after dark stable positive evidence")
  let oldSequence=laser.sequence
  let next=PhysicalLaserGuidance.Target(source:"ai",session:session,moveNumber:5,size:19,row:1,col:0,black:false,decisionReceivedAtUnix:999,purpose:"capture")
  check(capture.id != next.id,"Prisoners have distinct identity")
  laser.setTarget(next);frame();try status(sequence:oldSequence);laser.verifyCaptureTarget(capturedAt:now,now:now)
  check(request().action=="off","Prior revision OFF acknowledgement cannot admit next prisoner")
  try status();laser.verifyCaptureTarget(capturedAt:now,now:now);check(request().action=="point","New revision dark acknowledgement admits next target")
  try status(state:"fault",requiresNew:true);check(request().action=="off","Fault inhibits capture")
  laser.setTarget(capture);frame();try status();laser.verifyCaptureTarget(capturedAt:now,now:now)
  check(request().action=="off" && laser.suppressed,"Changing prisoner cannot erase same-move fault latch")
  laser.setTarget(nil);check(request().action=="off","Completion/pause removes target")
  laser.setTarget(next);frame();try status();laser.verifyCaptureTarget(capturedAt:now,now:now)
  check(request().action=="off" && laser.suppressed,"Empty selection cannot erase same-move fault latch")
  let move=PhysicalLaserGuidance.Target(source:"ai",session:session,moveNumber:6,size:19,row:2,col:2,black:true,decisionReceivedAtUnix:wall)
  laser.setTarget(move);frame();try status();laser.verifyMoveTarget(capturedAt:now,now:now);try status(state:"adequate",lit:true)
  check(cues==1,"Ordinary opponent move retains exactly one positive-illumination callback")
  // A noisy prisoner observation must not turn an existing stronger latch into
  // the recoverable capture-evidence state, even after a valid OFF receipt.
  for blocked in ["camera_stream_changed","camera_context_changed","driver_interrupted","driver_link_lost","camera_frame_stale","request_lease_expired","stone_seen_at_target"] {
   let fresh=PhysicalLaserGuidance.Target(source:"ai",session:UUID(),moveNumber:1,size:19,row:0,col:0,black:false,decisionReceivedAtUnix:wall,purpose:"capture")
   laser.setTarget(fresh);frame();try status();laser.verifyCaptureTarget(capturedAt:now,now:now)
   check(request().action=="point","Regression setup must be actively indicating")
   if blocked=="camera_stream_changed" {laser.cameraStreamChanged()}
   else if blocked=="camera_context_changed" {laser.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"moved-grid")}
   else if blocked=="driver_interrupted" {try status(state:"fault",requiresNew:true)}
   else if blocked=="driver_link_lost" {now+=1;wall+=1;laser.tick()}
   else {laser.suppress(blocked)}
   frame();try status()
   check(request().action=="off" && laser.suppressed,"Stronger latch setup stays OFF")
   // This is the same raw observation path used by PhysicalAI.consume before
   // dark-frame acceptance; it must preserve the earlier reason.
   laser.suppress("capture_evidence_changed")
   for _ in 0..<4 {frame();try status();laser.verifyCaptureTarget(capturedAt:now,now:now)}
   check(request().action=="off" && laser.suppressed,"Capture evidence must not recover \(blocked)")
   check(request().reason==blocked,"Capture evidence must preserve \(blocked) reason")
  }
  print("PASS \(checks) real laser-contract behavior checks (real application types)")
 }
}
