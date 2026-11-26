import Foundation

@main struct PhysicalColdOFFTransitionTests {
 @MainActor static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("cold-off-transition-"+UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  let fixtures=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ColdOffTransition")
  var now=100.0,wall=1000.0,frameID:UInt64=100,checks=0
  func check(_ condition:Bool,_ message:String) {precondition(condition,message);checks+=1}
  func request(_ l:PhysicalLaserGuidance)throws->PhysicalLaserGuidance.Request {
   try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:l.directory.appendingPathComponent("request.json")))
  }
  func frame(_ l:PhysicalLaserGuidance) {
   now+=0.2;wall+=0.2;frameID+=1
   l.noteFrame(.init(streamEpoch:l.frames.streamEpoch,frameID:frameID,capturedAtUptime:now,arrivedAtUptime:now,capturedAtUnix:wall,timestampSource:"cameraPresentation",presentationSeconds:now))
   l.observeCamera(hand:false,valid:true,capturedAt:now,now:now,context:"camera/grid")
  }
  func deliver(_ name:String,_ l:PhysicalLaserGuidance,mutate:((inout [String:Any])->Void)?=nil)throws {
   var raw=try JSONSerialization.jsonObject(with:Data(contentsOf:fixtures.appendingPathComponent(name+".json"))) as! [String:Any]
   let r=try request(l)
   raw["schemaVersion"]=r.schemaVersion;raw["producer"]=l.producer.uuidString;raw["sequence"]=r.sequence;raw["updatedAtUnix"]=wall
   raw["playSession"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(r.playSession),options:.fragmentsAllowed)
   raw["cameraContext"]=r.cameraContext;raw["streamEpoch"]=r.streamEpoch?.uuidString
   if name=="full-off" {
    raw["offSinceUnix"]=wall-0.5
    raw["evidenceAfter"]=["streamEpoch":l.frames.streamEpoch.uuidString,"frameID":0,"timestampSource":"cameraPresentation"]
   }
   mutate?(&raw)
   let data=try JSONSerialization.data(withJSONObject:raw);_=try JSONDecoder().decode(PhysicalLaserGuidance.DriverStatus.self,from:data)
   try data.write(to:l.directory.appendingPathComponent("status.json"),options:.atomic);l.tick()
  }
  func cold(_ name:String)throws->PhysicalLaserGuidance {
   let l=PhysicalLaserGuidance(directory:root.appendingPathComponent(name),automatic:false,wallTime:{wall},uptime:{now})
   l.setPlaySession(.init(source:"ai",session:UUID(),size:9));l.setStandbyEnabled(true);l.setEnabled(true);frame(l)
   try deliver("full-off",l)
   check(try request(l).schemaVersion==2 && request(l).action=="off" && l.admissionBlocker == .awaitingFullOFF,"Fixture negotiates cold schema2 OFF")
   return l
  }
  let l=try cold("host-cold");let revision=l.sequence
  var clicks=0;l.onTargetIndicated={_ in clicks+=1}
  for _ in 0..<3 {
   try deliver("transition",l)
   check(!l.holdingInterrupted,"Actual host cold OFF transition must not latch standby_context_changed")
   check(try request(l).action=="off" && l.sequence==revision && !l.mayHaveMotorSession,"Transition preserves OFF and cannot grant motion or churn revisions")
   check(!l.acceptsObservation(capturedAt:now,now:now,requireDarkEvidence:true) && clicks==0,"Unknown output grants neither recognition nor illumination notification")
   frame(l)
  }
  // No transition may pin a setup. Only the eventual full OFF adopts it.
  try deliver("full-off",l,mutate:{$0["setupId"]="eventual-confirmed-setup"})
  check(try request(l).action=="standby" && l.admissionBlocker==nil && !l.holdingInterrupted,"Actual full OFF alone completes current admission")
  try deliver("transition",l,mutate:{$0["setupId"]="8d98ed7584c4265a"})
  check(try l.holdingInterrupted && request(l).action=="off","A previously advertised setup cannot replace the now-known setup")

  for invalid in ["producer","sequence","stale","simulation","capability","session","context","epoch","missing-setup","empty-setup","illumination","off-stamp","watermark","beam-dark"] {
   let x=try cold("invalid-"+invalid)
   try deliver("transition",x,mutate:{raw in
    switch invalid {
    case "producer":raw["producer"]=UUID().uuidString
    case "sequence":raw["sequence"]=x.sequence-1
    case "stale":raw["updatedAtUnix"]=wall-0.8
    case "simulation":raw["mode"]="simulation"
    case "capability":raw["capabilities"]=[]
    case "session":raw["playSession"]=["source":"ai","session":UUID().uuidString,"size":9]
    case "context":raw["cameraContext"]="other-camera"
    case "epoch":raw["streamEpoch"]=UUID().uuidString
    case "missing-setup":raw.removeValue(forKey:"setupId")
    case "empty-setup":raw["setupId"]=""
    case "illumination":raw["illuminationConfirmed"]=true
    case "off-stamp":raw["offSinceUnix"]=wall-1
    case "watermark":raw["evidenceAfter"]=["streamEpoch":x.frames.streamEpoch.uuidString,"frameID":0,"timestampSource":"cameraPresentation"]
    default:raw["beamOffSinceUnix"]=wall-1
    }
   })
   check(try request(x).action=="off" && !x.mayHaveMotorSession,"Invalid transition never authorizes motion: "+invalid)
   check(!x.acceptsObservation(capturedAt:now,now:now,requireDarkEvidence:true),"Invalid transition cannot authorize recognition: "+invalid)
   if !["producer","sequence","stale","simulation"].contains(invalid) {check(x.holdingInterrupted,"Owned invalid transition retains explicit latch: "+invalid)}
  }
  let closing=try cold("cold-pause")
  closing.setPlaySession(nil)
  try deliver("transition",closing)
  check(try !closing.holdingInterrupted && request(closing).action=="off" && request(closing).playSession==nil,"A nullable closing scope can wait without inventing motor release")
  check(!closing.acceptsObservation(capturedAt:now,now:now,requireDarkEvidence:true),"Closing transition remains uncertain output")
  try deliver("full-off",closing)
  check(try request(closing).schemaVersion==1 && !closing.mayHaveMotorSession,"Confirmed OFF alone completes cold cancellation")
  let timeout=try cold("bounded-wait")
  for _ in 0..<17 {try deliver("transition",timeout);frame(timeout)}
  check(try timeout.holdingInterrupted && request(timeout).action=="off","Current heartbeats cannot extend the existing3s transition deadline")

  // Same-scope explicit Retry closes the old negotiation, returns through
  // schema1 OFF, then waits for its new schema2 transition/full-OFF receipt.
  let retry=try cold("retry")
  try deliver("transition",retry,mutate:{$0["cameraContext"]="wrong"})
  try deliver("full-off",retry);frame(retry);retry.showAgain()
  try deliver("full-off",retry);try deliver("full-off",retry)
  check(try request(retry).schemaVersion==2 && request(retry).action=="off","Retry earns a new cold OFF negotiation")
  try deliver("transition",retry)
  check(!retry.holdingInterrupted && retry.admissionBlocker == .awaitingFullOFF,"Same-scope Retry does not reproduce the false transition latch")
  try deliver("full-off",retry)
  check(try request(retry).action=="standby" && retry.admissionBlocker==nil,"Current full OFF completes Retry")
  print("PASS: \(checks) cold OFF host/native sequence checks")
 }
}
