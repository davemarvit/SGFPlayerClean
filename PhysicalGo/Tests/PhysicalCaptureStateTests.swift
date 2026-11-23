import Foundation
@main struct PhysicalCaptureStateTests {
 static func main() {
  var count=0
  func check(_ value:Bool,_ why:String) {precondition(value,why);count+=1}
  let id=PhysicalCaptureGuidance.Identity(session:UUID(),moveNumber:5)
  var state=PhysicalCaptureGuidance()
  var t=100.0
  func observe(_ values:[String?],context:String="camera/epoch",identity:PhysicalCaptureGuidance.Identity?=nil)->Int? {
   t+=0.25;return state.observe(identity:identity ?? id,values:values,stamp:t,now:t,context:context)
  }
  state.configure(identity:id,prisoners:[0:"white",9:"white"],placement:(18,"black"),removed:[],evidenceAfter:100)
  var cells=[String?](repeating:"empty",count:81);cells[0]="white";cells[9]="white"
  for stamp in [99.2,99.5,99.8] {check(state.observe(identity:id,values:cells,stamp:stamp,now:100,context:"camera/epoch")==nil && state.selected==nil,"Pre-move frames cannot establish capture evidence")}

  for _ in 0..<3 {check(observe(cells)==nil,"Unplaced AI must win over capture")}
  cells[18]="black"
  check(observe(cells)==nil,"One placement frame insufficient")
  check(observe(cells)==nil,"Two placement frames insufficient")
  check(observe(cells)==0 && state.placementConfirmed,"Placed AI enables first legal prisoner")
  let stableTime=t
  cells[0]="empty"
  check(state.observe(identity:id,values:cells,stamp:stableTime,now:t,context:"camera/epoch")==nil && state.removed.isEmpty,"Duplicate cannot prove removal")
  check(observe(cells)==nil && state.selected==0,"One absent frame cannot switch prisoner")
  cells[0]=nil
  for _ in 0..<4 {check(observe(cells)==nil && state.removed.isEmpty,"Unknown never means removed or relight")}
  cells[0]="white";cells[9]="empty"
  for _ in 0..<3 {_=observe(cells)}
  check(state.removed==[9] && state.selected==0,"Out-of-order removal retains current prisoner")
  state.invalidate()
  check(observe(cells)==nil,"Hand clears admission witnesses")
  _=observe(cells);check(observe(cells)==0,"Fresh repeated evidence restores current prisoner")
  cells[0]="empty"
  for _ in 0..<3 {_=observe(cells)}
  check(state.remainingCount==0 && state.selected==nil,"Complete removals clear target")
  cells[0]="white";cells[9]="white"
  for _ in 0..<4 {check(observe(cells)==nil && state.remainingCount==0,"Removed prisoners cannot resurrect")}
  state.clear();check(!state.pending,"Full board completion closes logical capture")
  state.configure(identity:id,prisoners:[0:"white"],placement:nil,removed:[],evidenceAfter:100)
  cells[18]="empty";cells[10]="black"
  for _ in 0..<3 {_=observe(cells)}
  check(state.selected==0 && state.remainingCount==1,"Single human capture independent of clock pause; extra stone never selected")
  let wrong=PhysicalCaptureGuidance.Identity(session:id.session,moveNumber:id.moveNumber-1)
  var empty=cells;empty[0]="empty"
  for _ in 0..<4 {check(observe(empty,identity:wrong)==nil && state.remainingCount==1,"Stale move identity rejected")}
  state.invalidate(dropPlacement:true)
  check(observe(cells,context:"camera/new-epoch")==nil,"Camera replacement requires new witnesses")
  _=observe(cells,context:"camera/new-epoch");check(observe(cells,context:"camera/new-epoch")==0,"New context admits after stable evidence")
  check(state.observe(identity:id,values:empty,stamp:t-2,now:t,context:"camera/new-epoch")==nil && state.remainingCount==1,"Stale frame cannot remove")
  let saved=PhysicalCaptureGuidance.Saved(moveNumber:5,acceptedAtUnix:1000,removed:[0,99])
  state.clear();state.configure(identity:id,prisoners:[0:"white",9:"white"],placement:(18,"black"),removed:saved.removed,evidenceAfter:t)
  check(state.removed==[0] && !state.placementConfirmed,"Restore preserves legal removals but discards placement evidence")
  state.clear();state.configure(identity:id,prisoners:[0:"white",9:"white"],placement:(18,"black"),removed:[],evidenceAfter:t)
  cells=Array(repeating:"empty",count:81);cells[18]="black";cells[0]="white"
  for _ in 0..<3 {_=observe(cells)}
  check(!state.permitsReply(at:0),"Remaining prisoner cannot become a human reply after partial removal")
  check(!state.permitsReply(at:40),"Reply elsewhere cannot bypass a remaining prisoner")
  cells[0]="empty"
  for _ in 0..<2 {_=observe(cells);check(!state.permitsReply(at:40),"Cleanup requires stable positive empty evidence")}
  _=observe(cells)
  check(state.permitsReply(at:40),"Stable complete cleanup permits an outside reply")
  cells[0]=nil
  for _ in 0..<3 {_=observe(cells)}
  check(!state.permitsReply(at:40),"Persisted removal ledger cannot replace current empty evidence")
  cells[0]="white"
  for _ in 0..<3 {_=observe(cells)}
  check(state.permitsReply(at:0),"A previously positively removed prisoner coordinate can receive a new reply")
  check(!state.permitsReply(at:40),"Reoccupied prisoner elsewhere still blocks cleanup")
  state.invalidate()
  check(!state.permitsReply(at:0),"Another prisoner's stale evidence cannot authorize combined reply")
  print("PASS \(count) capture-state behavior checks")
 }
}
