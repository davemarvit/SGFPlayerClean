import Foundation
@main struct HistoricalMoveTests {
    @MainActor static func main() throws {
        // Stateful sequence: old stones can be uncertain, but new placements need evidence.
        let n=9,empty=Array(repeating:"empty",count:81),confidence=Array(repeating:1.0,count:81)
        var h=HistoricalMoveEvidence(),board=empty
        board[0]="black";h.anchor(board)
        var seen=board;seen[0]="uncertain";seen[10]="black";seen[80]="uncertain"
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true) == .candidate(10))
        h.didSubmit(10,color:"black")
        h.advance(board,submitted:nil) // Turn-only update must not forget accepted evidence.
        board[10]="black";h.advance(board,submitted:nil)
        seen[10]="uncertain"
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:false) == .idle)
        board[20]="white";h.advance(board,submitted:nil)
        seen[11]="black";seen[20]="uncertain"
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true) == .placementNeeded)
        seen[20]="white"
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true) == .candidate(11))
        // Captures arriving from the server must not turn a residual own stone into a move.
        board[0]="empty";h.advance(board,submitted:nil)
        seen=board;seen[0]="black"
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true) == .idle)
        seen[12]="black"
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true) == .candidate(12))
        seen[12]="empty";seen[0]="empty"
        _=h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true)
        seen[0]="black"
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true) == .candidate(0))
        // Evidence cannot come from weak classifications, ambiguous assignment, or a global obstruction.
        h.anchor(empty);seen=empty;seen[10]="black"
        var weak=confidence;weak[10]=0.79
        precondition(h.observe(seen,confidence:weak,size:n,color:"black",myTurn:true) == .ambiguous)
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true,ambiguous:[10]) == .ambiguous)
        for i in 30..<60 {seen[i]="uncertain"}
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true) == .obscured)
        seen=empty;seen[10]="black";seen[11]="black"
        precondition(h.observe(seen,confidence:confidence,size:n,color:"black",myTurn:true) != .candidate(10))
        // Integration checks actual transport isolation, time settlement, and missing opponent placement.
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let move=directory.appendingPathComponent("move.json")
        var revision=0
        func publish(_ cells:[String],turn:Bool=true) throws {
            revision += 1
            let state:[String:Any]=["token":"offline-only","game":123,"version":revision,"size":n,"cells":cells,"ready":true,"myTurn":turn,"color":"black","time":Date().timeIntervalSince1970]
            try JSONSerialization.data(withJSONObject:state).write(to:directory.appendingPathComponent("state.json"))
        }
        func observation(_ cells:[String])->BoardObservation {
            .init(readings:cells.indices.map{.init(row:$0/n,col:$0%n,occupancy:Occupancy(rawValue:cells[$0])!,confidence:1,delta:0)},size:n)
        }
        try publish(empty,turn:false)
        let bridge=PhysicalOnlineBoard(directory:directory,announceOpponent:{},announceCorrection:{})
        bridge.enabled=true;bridge.consume(observation(empty),now:1)
        board=empty;board[20]="white";try publish(board)
        seen=empty;seen[10]="black";seen[20]="uncertain";seen[80]="uncertain"
        for i in 0..<10 {bridge.consume(observation(seen),now:1.1+Double(i)*0.2)}
        precondition(!FileManager.default.fileExists(atPath:move.path),"Cannot skip opponent placement")
        seen[20]="white"
        for i in 0..<7 {bridge.consume(observation(seen),now:3.1+Double(i)*0.2)}
        let request=try JSONSerialization.jsonObject(with:Data(contentsOf:move)) as! [String:Any]
        precondition(request["x"] as? Int==1 && request["y"] as? Int==1)
        try FileManager.default.removeItem(at:move)
        for i in 0..<10 {bridge.consume(observation(seen),now:5+Double(i)*0.2)}
        precondition(!FileManager.default.fileExists(atPath:move.path))
        print("PASS: historical state, split acknowledgment, opponent placement, captured remnants and reuse, weak/ambiguous candidates, broad occlusion, competing moves, single local-evidence dispatch.")
    }
}
