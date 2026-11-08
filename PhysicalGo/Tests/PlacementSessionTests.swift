import Foundation

@MainActor enum PlacementSessionChecks {
    static func run()throws->Int {
        struct Entry:Decodable {let event:String?;let time:Double;let position:String?;let offsets:[String:Double]?}
        struct Session:Decodable {let source:String;let expected:[Int];let observations:[Entry]}
        let url=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/PlacementAmbiguity/sessions.json")
        let sessions=try JSONDecoder().decode([Session].self,from:Data(contentsOf:url))
        let recorder=GameRecorder(storage:nil)
        var checks=0,lastView:BoardObservation?,time=0.0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        for (index,session) in sessions.enumerated() {
            for entry in session.observations {
                time=entry.time
                if let event=entry.event {
                    switch event {
                    case "start":recorder.start(size:19,now:time)
                    case "paused":recorder.pause()
                    case "resumed":recorder.resume()
                    case "finished":recorder.finish()
                    default:
                        if !event.contains("Checking that the physical board matches") {
                            recorder.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"),preserveOrder:event.contains("Finding the grid"))
                        }
                    }
                } else if let position=entry.position {
                    let states=position.map{$0=="B" ? Occupancy.black : $0=="W" ? .white : $0=="?" ? .uncertain : .empty}
                    let shapes=(entry.offsets ?? [:]).map{key,offset -> StoneFootprint in
                        let point=Int(key)!
                        // The archived sessions contain displacement only, not
                        // complete outlines. Use deliberately ambiguous disks
                        // to keep testing chronology retention under the new
                        // assignment policy, rather than the old centering rule.
                        let offset:Double = [252,99,184].contains(point) ? 0.49:offset
                        return .init(row:point/19,col:point%19,center:.init(x:Double(point%19),y:Double(point/19)+offset),radiusCol:0.46,radiusRow:0.46,quality:0.99)
                    }
                    let view=BoardObservation(readings:states.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,footprints:shapes)
                    if view.signature.filter({$0 == .uncertain}).count<=18 {lastView=view}
                    recorder.consume(view,now:time)
                }
            }
            let saved=recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}
            let pending=recorder.pendingConfidence.compactMap(\.point)
            check(saved==Array(session.expected.prefix(22)),"Ambiguous move 23 reached SGF in session \(index)")
            check(saved+pending==session.expected,"Pending game lost chronological moves across session \(index): \(saved+pending)")
            check(recorder.pendingConfidence.first?.placementUncertain==true,"Move 23's placement uncertainty expired")
        }
        check(recorder.pendingMoveCount==31,"The combined sessions should retain moves 23 through 53")
        let unclear=recorder.pendingConfidence.filter(\.placementUncertain).compactMap(\.point)
        check(Set(unclear)==[252,99,184],"Wrong lasting placement uncertainties in combined footage: \(unclear)")
        check(recorder.pendingConfidence[52-23].level=="high","Clear white move 52 was penalized for its neighbors")
        // Simulate centering the three marked stones; the image-derived colors
        // and retained chronology stay unchanged. This is not a new camera frame.
        recorder.resume()
        var adjusted=lastView!
        adjusted.footprints=adjusted.footprints.map { shape in
            [252,99,184].contains(shape.row*19+shape.col) ? .init(row:shape.row,col:shape.col,center:.init(x:Double(shape.col),y:Double(shape.row)),radiusCol:shape.radiusCol,radiusRow:shape.radiusRow,quality:shape.quality) : shape
        }
        for _ in 0..<8 {time += 0.21;recorder.consume(adjusted,now:time)}
        check(recorder.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}==sessions.last!.expected,"Simulated centering did not finish the exact 53-move sequence: \(recorder.moveCount), \(recorder.status), \(recorder.pendingConfidence)")
        check(recorder.pendingMoveCount==0,"Resolved placement evidence was not cleared")
        print("PASS: \(checks) combined-session checks: all 53 intended assignments retained, 23/51/53 held for placement, pause/resume continuity, and completion after simulated centering.")
        return checks
    }
}
