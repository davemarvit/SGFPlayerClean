import Foundation

/// Offline ledger replay from logged classifications and accepted turn events.
/// Full camera outlines are absent, so this is a component diagnostic rather
/// than a reproduction of camera recognition. Never writes to the input game.
@main struct ReplayStoneIdentityJournal {
 static func main() throws {
  let src=URL(fileURLWithPath:CommandLine.arguments[1])
  let rows=try String(contentsOf:src).split(separator:"\n").map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
  var ledger=RecordingStoneLedger(size:19), committed=[Int:Int](), timed=[Int:(Stone,Set<Int>)](), previousSequences=[[Int]]()
  var output=[[String:Any]]()
  for row in rows {
   let event=row["event"] as! String
   if event=="observed turn clock press",let n=row["number"] as? Int,let h=row["candidateHistory"] as? [String:Any] {
    timed[n]=(h["color"] as? String == "black" ? .black:.white,Set(h["possibleLocations"] as! [Int]))
   }
   if event=="accepted move",let moves=row["moveTimings"] as? [[String:Any]] {
    for m in moves {committed[m["moveNumber"] as! Int]=m["point"] as? Int}
   }
   defer {if let sequences=row["tentativeSequences"] as? [[Int]] {previousSequences=sequences}}
   guard event=="observation",row["state"] as? String == "recording",let time=row["uptime"] as? Double else {continue}
   let total=max(committed.keys.max() ?? 0,timed.keys.max() ?? 0)
   let inputs=(1...max(1,total)).compactMap {n -> RecordingStoneLedger.Input? in
    guard n<=total else {return nil}
    var candidates=Set(committed[n].map{[$0]} ?? Array(timed[n]?.1 ?? []))
    let offset=n-committed.count-1
    if offset>=0 {for path in previousSequences where path.indices.contains(offset) {candidates.insert(path[offset])}}
    return .init(number:n,color:timed[n]?.0 ?? (n%2==1 ? .black:.white),pass:false,point:committed[n],candidates:candidates,press:nil)
   }
   try ledger.reconcile(inputs,captures:[:])
   let signature=Array((row[CommandLine.arguments.count>2 ? CommandLine.arguments[2]:"position"] as? String) ?? (row["position"] as! String))
   let confidence=row["readingConfidence"] as! [Double],delta=row["readingDelta"] as! [Double]
   var obs=BoardObservation(readings:signature.enumerated().map{i,c in .init(row:i/19,col:i%19,occupancy:c=="B" ? .black:c=="W" ? .white:c=="?" ? .uncertain:.empty,confidence:confidence[i],delta:delta[i])},size:19)
   obs.capturedAt=row["captureUptime"] as? Double;obs.handObstructed=row["handObstructed"] as? Bool;obs.lightingBlocked=row["lightingBlocked"] as? Bool ?? false
   let before=ledger.records
   let excluded=ledger.observe(obs,now:time)
   if total>=13 {
    let potential=obs.readings.indices.filter{committed.values.contains($0)==false && obs.readings[$0].occupancy == .white && confidence[$0]>=0.9}
    output.append(["time":time,"whiteCandidates":potential,"excludedWhite":potential.filter{excluded.contains($0)},"whiteIdentities":before.filter{$0.color == .white}.map{r -> [String:Any] in
     let known=r.physicalGroup ?? r.physicalPoint.map{Set([$0])} ?? r.historicalPoint.map{Set([$0])} ?? r.candidates
     return ["number":r.number,"known":known.sorted(),"visible":known.filter{obs.readings[$0].occupancy == .white && confidence[$0]>=0.9}.sorted()]
    },"newCandidates":ledger.records.filter{$0.number>=12}.map{["number":$0.number,"candidates":$0.candidates.sorted()] as [String:Any]}])
   }
  }
  let data=try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]);FileHandle.standardOutput.write(data)
 }
}
