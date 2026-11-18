import Foundation

@main struct DeferredFullRecordingTests {
    struct Frame:Decodable {
        let capturedAt:Double,availableAt:Double
        let hand:Bool?,lightingBlocked:Bool
        let readings:[IntersectionReading],shapes:[StoneFootprint]
    }
    struct Game:Decodable {let name:String;let expected:[Int];let frames:[Frame]}
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        let games=try JSONDecoder().decode([Game].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        var results=[[String:Any]]()
        for game in games {
            var variants=[[String:Any]]()
            for enabled in [false,true] {
                let r=GameRecorder(storage:nil,deferredLocations:enabled);r.clock.audible=false
                let epoch=ProcessInfo.processInfo.systemUptime+10,offset=epoch-game.frames[0].capturedAt
                r.start(size:19,now:epoch-3,clockSettings:.init(kind:.fischer,mainSeconds:10000,incrementSeconds:2,maximumSeconds:20000))
                // Supplied empty starting board, shared by both variants. Not
                // counted as additional recording evidence or physical timing.
                for i in 0..<8 {
                    let t=epoch-2+Double(i)*0.21
                    r.consume(.init(readings:(0..<361).map{.init(row:$0/19,col:$0%19,occupancy:.empty,confidence:1,delta:0)},
                        size:19,capturedAt:t,handObstructed:false),now:t)
                }
                var transitions=0,previous=false
                for frame in game.frames {
                    let now=frame.availableAt+offset,stamp=frame.capturedAt+offset
                    if frame.hand==true {r.noteHandObstruction(now:now,capturedAt:stamp)}
                    else {
                        r.consume(.init(readings:frame.readings,size:19,lightingBlocked:frame.lightingBlocked,
                            footprints:frame.shapes,capturedAt:stamp,handObstructed:frame.hand),now:now)
                    }
                    r.clock.tick(at:now)
                    if r.clock.requiresReview && !previous {transitions += 1}
                    previous=r.clock.requiresReview
                }
                let points=r.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}
                let presses=(r.clock.moves+r.clock.provisionalMoves).sorted{$0.number<$1.number}
                let report:[String:Any]=["enabled":enabled,"savedPoints":points,"timedMoves":presses.map(\.number),
                    "pressTimes":presses.map{($0.estimate?.time ?? $0.after.anchor ?? offset)-offset},
                    "reviewTransitions":transitions,"clockReview":r.clock.requiresReview,"status":r.status,"clockNotice":r.clock.notice,
                    "unresolvedLocations":r.stoneLedger?.records.filter(\.locationUnresolved).count ?? 0,
                    "expectedSavedSequence":points==game.expected]
                variants.append(report)
                print(game.name,enabled,"saved",points.count,"timed",presses.count,"reviews",transitions,flushLabel(r.status))
                r.pause()
            }
            results.append(["game":game.name,"expectedMoves":game.expected.count,"observations":game.frames.count,"variants":variants])
        }
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
    }
    static func flushLabel(_ value:String)->String {value}
}
