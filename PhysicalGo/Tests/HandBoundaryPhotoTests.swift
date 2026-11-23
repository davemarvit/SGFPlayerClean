import Foundation
enum HandBoundaryPhotoTests {
 static func run() throws {
  setbuf(stdout,nil)
  let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/R13Clearance")
  let pipe=Pipe(),p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/gzip");p.arguments=["-dc",folder.appendingPathComponent("frames.json.gz").path];p.standardOutput=pipe
  try p.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit();precondition(p.terminationStatus==0)
  let frames=try JSONDecoder().decode([String:HandOutlineFrame].self,from:data)
  var checks=0,failures=0
  func check(_ ok:Bool,_ message:String) {checks+=1;if !ok {failures+=1;print("FAIL",message)}}
  let clear=HandMotionPose(hands:[])
  // Reconstructed state sweep, not the missing historical checkpoint. The
  // near-time pre-H11 photo lacks H11; the later replay reference also tests
  // sensitivity to a stale background. See fixture provenance.json.
  for background in ["beforeH11","replayBefore"] {for edge in 0..<4 {for side in stride(from:0.0,through:18.0,by:3.0) {
   var t=HandOutlineTracker(checkpoint:.init(background:frames[background],active:true,edge:edge,center:edge%2==0 ? [side,2]:[16,side],direction:nil,appearance:nil))
   let first=t.observe(frames["blockedPhoto"]!,pose:clear,at:0,source:"photo")
   check(first.obstructed==true,"First clear view bypassed confirmation")
   let second=t.observe(frames["blockedPhoto"]!,pose:clear,at:0.2,source:"photo")
   check(second.obstructed==false,"Clear photo held: \(background), edge\(edge), lateral\(side): \(second.reason)")
  }}}
  // Independently visible hands must survive repeated pose-detector misses.
  for name in ["hand133","hand135","hand140","hand142","blur143"] {
   var t=HandOutlineTracker(checkpoint:.init(background:frames["replayBefore"],active:true,edge:0,center:[11,0],direction:nil,appearance:nil))
   for n in 0..<4 {
    let result=t.observe(frames[name]!,pose:clear,at:Double(n)*0.2,source:"photo")
    check(result.obstructed==true && result.estimate==nil,"Visible photographed hand cleared after pose loss: \(name), repeat\(n), \(result.reason)")
   }
   _=t.observe(frames["replayClear"]!,pose:clear,at:0.8,source:"photo")
   check(t.observe(frames["replayClear"]!,pose:clear,at:1,source:"photo").obstructed==false,"Photographed exit remained blocked after \(name)")
  }
  // Retained appearance/location from the actual offline replay must also
  // survive the missed blurred hand. Checkpoint timing history is not stored;
  // this tests a new, conservative observed bracket after reacquisition.
  let checkpointPipe=Pipe(),checkpointProcess=Process()
  checkpointProcess.executableURL=URL(fileURLWithPath:"/usr/bin/gzip")
  checkpointProcess.arguments=["-dc",folder.appendingPathComponent("learned-checkpoint.json.gz").path]
  checkpointProcess.standardOutput=checkpointPipe
  try checkpointProcess.run()
  let checkpointData=checkpointPipe.fileHandleForReading.readDataToEndOfFile()
  checkpointProcess.waitUntilExit();precondition(checkpointProcess.terminationStatus==0)
  let checkpoint=try JSONDecoder().decode(HandOutlineTracker.Checkpoint.self,from:checkpointData)
  precondition(checkpoint.active && checkpoint.direction != nil)
  var learned=HandOutlineTracker(checkpoint:checkpoint)
  for time in [0.0,0.2,0.4,0.6] {
   let result=learned.observe(frames["blur143"]!,pose:clear,at:time,source:"retained")
   check(result.obstructed==true && result.estimate==nil,"Learned appearance/location lost the photographed blurred hand")
  }
  let firstClear=learned.observe(frames["replayClear"]!,pose:clear,at:0.8,source:"retained")
  check(firstClear.obstructed==true && firstClear.estimate==nil,"Reacquisition bypassed visual confirmation")
  let exit=learned.observe(frames["replayClear"]!,pose:clear,at:1,source:"retained")
  check(exit.obstructed==false && exit.estimate?.method == .handBracket && exit.estimate?.observedLower==0.6 && exit.estimate?.observedUpper==0.8,"Reacquisition reused a stale velocity estimate or retained obstruction")
  check(learned.observe(frames["replayClear"]!,pose:clear,at:1.2,source:"retained").estimate==nil,"Clear board repeated the clock press")
  precondition(failures==0,"Photographed boundary regression");print("PASS: \(checks) photographed boundary checks: clear R13 views, retained visible/blurred hands, verified exits")
 }
}
