import Foundation

@main struct WhiteTurnAppearanceTests {
    struct Frame:Decodable {
        let capturedAt:Double,availableAt:Double
        let hand:Bool?,lightingBlocked:Bool
        let readings:[IntersectionReading],shapes:[StoneFootprint]
        let estimate:ClockPressEstimate?
    }
    struct Input:Decodable {let frames:[Frame];let expectedPressTime:Double}
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        let input=try JSONDecoder().decode(Input.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        let baseline=CommandLine.arguments.contains("--expect-failure")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("white-turn-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var reports=[[String:Any]](),checks=0
        func check(_ condition:Bool,_ message:String) {checks+=1;precondition(condition,message)}
        if !baseline {
            let empty=Array(repeating:Occupancy.empty,count:81)
            func sample(_ time:Double,color:Occupancy = .white,score:Double=0.84,quality:Double=0.995,
                        hand:Bool?=false,blocked:Bool=false,outline:Bool=true,x:Double=4,neighbor:Bool=false,radius:Double=0.46)->BoardObservation {
                var values=empty;values[40]=color;if neighbor {values[41] = color}
                return .init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:$0.offset==40 ? score:1,delta:0)},
                    size:9,lightingBlocked:blocked,
                    footprints:outline ? [.init(row:4,col:4,center:.init(x:x,y:3.72),radiusCol:radius,radiusRow:radius,quality:quality)]:[],
                    capturedAt:time,handObstructed:hand)
            }
            func turn(_ make:(Double)->BoardObservation)->ClearBoardTiming.ObservedTurn? {
                var timing=ClearBoardTiming()
                for i in 0..<6 {let t=100+Double(i)*0.21;timing.observe(make(t),now:t,allowWhiteOutlineEvidence:true)}
                return timing.observedTurns(base:empty,excluding:[],after:0).first
            }
            let supported=turn{sample($0)}
            check(supported?.estimate.time==100 && supported?.confirmation.appearanceSupportedViews==6,"Outline support retimed or failed a sustained white turn")
            check(supported?.confirmation.minimumScore==0.84,"Appearance support falsified the raw point score")
            check(turn{sample($0,outline:false)}==nil,"Low point score alone accepted a turn")
            check(turn{sample($0,color:.black)}==nil,"White exception weakened black/shadow policy")
            check(turn{sample($0,score:0.79)}==nil,"Weak color evidence accepted a turn")
            check(turn{sample($0,quality:0.97)}==nil,"Weak outline accepted a turn")
            check(turn{sample($0,hand:nil)}==nil && turn{sample($0,hand:true)}==nil,"Unknown or obstructed hand evidence accepted a turn")
            check(turn{sample($0,blocked:true)}==nil,"Lighting failure accepted a turn")
            check(turn{sample($0,x:4.5,neighbor:true)}==nil,"One outline certified two stones")
            check(turn{sample($0,radius:0.9)}==nil,"Oversized outline accepted a turn")
            var count=0
            check(turn{t in count+=1;return sample(t,x:count%2==0 ? 3.9:4.1)}==nil,"A moving outline certified a settled turn")
            var timing=ClearBoardTiming()
            for i in 0..<5 {let t=100+Double(i)*0.21;timing.observe(sample(t),now:t,allowWhiteOutlineEvidence:true)}
            check(timing.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Too few clear observations accepted a turn")
            timing.observe(sample(103),now:103,allowWhiteOutlineEvidence:true)
            check(timing.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Camera gap reused old confirmation support")
            var fast=ClearBoardTiming()
            for i in 0..<31 {let t=100+Double(i)/30;fast.observe(sample(t),now:t,allowWhiteOutlineEvidence:true)}
            let fastTurn=fast.observedTurns(base:empty,excluding:[],after:0).first
            check(fastTurn?.estimate.time==100 && fastTurn?.confirmation.appearanceSupportedViews==31,"Faster camera delivery prevented a full second of confirmation")
            var improving=ClearBoardTiming()
            improving.observe(sample(100),now:100,allowWhiteOutlineEvidence:true)
            for i in 1..<12 {let t=100+Double(i)*0.21;improving.observe(sample(t,score:1,outline:false),now:t,allowWhiteOutlineEvidence:true)}
            check(improving.observedTurns(base:empty,excluding:[],after:0).first?.estimate.time==100,"Early outline evidence blocked later ordinary strong readings or retimed the move")

            // Weak point readings must still account for two old white stones
            // after hand-covered cleanup without choosing which identity moved.
            var ledger=RecordingStoneLedger(size:9)
            try ledger.reconcile([.init(number:1,color:.white,pass:false,point:40,candidates:[40],press:nil),
                .init(number:2,color:.black,pass:false,point:70,candidates:[70],press:nil),
                .init(number:3,color:.white,pass:false,point:42,candidates:[42],press:nil)],captures:[:])
            let originalIDs=ledger.records.map(\.id)
            func cleanup(_ t:Double,hand:Bool=false,missing:Bool=false)->BoardObservation {
                var values=empty;values[49] = missing ? .uncertain:.white;values[51] = .white;values[70] = .black
                return .init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,
                    confidence:$0.element == .white ? 0.84:($0.element == .uncertain ? 0:1),delta:0)},size:9,
                    footprints:([49,51].filter{!missing || $0 != 49}).map{.init(row:$0/9,col:$0%9,
                        center:.init(x:Double($0%9),y:Double($0/9)-0.28),radiusCol:0.46,radiusRow:0.46,quality:0.995)},
                    capturedAt:t,handObstructed:hand)
            }
            _=ledger.observe(cleanup(100,hand:true),now:100)
            for i in 1...8 {let t=100+Double(i)*0.21;_=ledger.observe(cleanup(t),now:t)}
            check(ledger.records.filter{$0.color == .white}.allSatisfy{$0.physicalGroup==[49,51] && $0.physicalPoint==nil && $0.locationUnresolved},"White cleanup guessed same-color identities or failed to account for their outlines")
            check(ledger.records.map(\.id)==originalIDs && ledger.records.count==3,"White cleanup created or reassigned a move")
            let excluded=ledger.observe(cleanup(102,missing:true),now:102)
            check(excluded.contains(49) && excluded.contains(51) && ledger.records.filter{$0.color == .white}.allSatisfy{$0.locationUnresolved},"One white sighting resolved two old identities")
        }
        for enabled in [false,true] {
            let file=root.appendingPathComponent("\(enabled).sgf")
            // Supplied seven-move setup at the recorded manual clock review.
            // No saved decision or timing is supplied for the new white turn.
            try "(;AP[PhysicalGo:0.194]FF[4]GM[1]SZ[19]RU[Japanese];B[pp];W[dd];B[dq];W[do];B[co];W[cn];B[cp])".write(to:file,atomically:true,encoding:.utf8)
            let r=GameRecorder(storage:root,deferredLocations:enabled);r.clock.audible=false
            try r.restoreSavedGame(from:file)
            r.attachClock(.init(kind:.absolute,mainSeconds:1800));_=r.resume()
            let offset=ProcessInfo.processInfo.systemUptime+1-input.frames[0].capturedAt
            var review=false,firstReceipt:LocalGameClock.Move?,acceptedAt:Double?
            for frame in input.frames {
                let t=frame.capturedAt+offset,now=frame.availableAt+offset
                if frame.hand==true {r.noteHandObstruction(now:now,capturedAt:t)}
                else {
                    let estimate=frame.estimate.map {e in ClockPressEstimate(time:e.time+offset,method:e.method,
                        observedLower:e.observedLower.map{$0+offset},observedUpper:e.observedUpper.map{$0+offset},
                        estimatedError:e.estimatedError,samples:e.samples,timestampSource:e.timestampSource,fallbackReason:e.fallbackReason)}
                    r.consume(.init(readings:frame.readings,size:19,lightingBlocked:frame.lightingBlocked,
                        footprints:frame.shapes,capturedAt:t,handObstructed:frame.hand,clockPressEstimate:estimate),now:now)
                }
                r.clock.tick(at:now);review = review || r.clock.requiresReview
                if firstReceipt==nil,let press=(r.clock.moves+r.clock.provisionalMoves).first(where:{$0.number==8}) {
                    firstReceipt=press;acceptedAt=frame.availableAt
                }
            }
            let presses=r.clock.moves+r.clock.provisionalMoves
            let report:[String:Any]=["enabled":enabled,"savedMoves":r.moveCount,"timedMoves":presses.map(\.number),
                "review":review,"running":r.clock.running,"notice":r.clock.notice,
                "earlierWhiteMarked":r.stoneLedger?.records.first{$0.number==2}?.locationUnresolved ?? false,
                "newWhiteUnresolved":r.placementAmbiguities.contains{$0.number==8},
                "pressTime":firstReceipt?.estimate.map{$0.time-offset} as Any? ?? NSNull(),
                "acceptedAt":acceptedAt as Any? ?? NSNull()]
            reports.append(report);print(report)
            if !enabled || baseline {
                check(review && firstReceipt==nil,"Recorded failure no longer reproduces in baseline")
                if enabled {check(r.stoneLedger!.records[1].locationUnresolved,"Earlier-white marker failure did not reproduce")}
            } else {
                check(!review && r.clock.running,"White outline evidence still stops clocks")
                check(presses.filter{$0.number==8}.count==1 && r.clock.engine.blackToPlay,"White turn lost or duplicated")
                check(abs(firstReceipt!.estimate!.time-offset-input.expectedPressTime)<0.000001,"White turn timestamp moved to later confirmation")
                check(!r.stoneLedger!.records[1].locationUnresolved,"Stationary white stone acquired a false cleanup marker")
                check(r.placementAmbiguities.contains{$0.number==8},"Turn evidence silently resolved the new stone's location")
                r.pause()
                let ids=r.deferredPendingRecords.map(\.id),press=firstReceipt!
                check(r.resolveDeferredLocations([8:72],identities:ids)==nil,"Later location review failed")
                check(r.clock.moves.last?.estimate==press.estimate && r.clock.moves.last?.after==press.after,"Location correction changed original clock receipt")
                try r.flushStorage()
                let restored=GameRecorder(storage:root,deferredLocations:true);restored.clock.audible=false
                try restored.restoreSavedGame(from:file)
                check(restored.clock.moves.last?.estimate==press.estimate && restored.moveCount==8,"Restart changed corrected move/time")
            }
            r.pause()
        }
        try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("PASS: \(checks) recorded white-turn appearance checks")
    }
}
