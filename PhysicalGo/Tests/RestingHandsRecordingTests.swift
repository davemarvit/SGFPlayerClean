import AppKit
import ImageIO

@main struct RestingHandsRecordingTests {
    struct Frame:Decodable {
        let id:Int
        let image:String,reference:String
        let calibration:BoardCalibration,referenceCalibration:BoardCalibration
        let threshold:Double,capturedAt:Double,availableAt:Double
        let originalOutline:HandOutlineTracker.Result?
        let originalPose:HandMotionPose?
    }
    struct Input:Decodable {let start:Double;let frames:[Frame]}
    @MainActor static func main()throws {
        NSApplication.shared.setActivationPolicy(.accessory);setbuf(stdout,nil)
        let input=try JSONDecoder().decode(Input.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        let output=URL(fileURLWithPath:CommandLine.arguments[2])
        func photo(_ path:String)->CGImage {
            CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil)!,0,nil)!
        }
        func write<T:Encodable>(_ value:T,_ name:String)throws {
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(value).write(to:output.appendingPathComponent(name))
        }
        var reports=[[String:Any]](),allPassed=true
        for mode in ["saved-gate","corrected"] {
            let r=GameRecorder(storage:nil,deferredLocations:true);r.clock.audible=false
            let offset=ProcessInfo.processInfo.systemUptime+10-input.frames[0].capturedAt
            var started=false,tracker=HandOutlineTracker(),stones=EstablishedStoneTracker(),lighting=KnownEmptyLighting()
            var references=[String:GrayFrame](),rows=[[String:Any]](),everReview=false
            var receipts=[Int:ClockPressEstimate](),changedReceipts=false
            for f in input.frames {
                let time=f.capturedAt+offset,now=f.availableAt+offset
                if !started,f.capturedAt>=input.start {
                    r.start(size:19,now:input.start+offset,clockSettings:.init(kind:.absolute,mainSeconds:1800))
                    started=true
                }
                let expected=r.positions.last?.grid.flatMap{$0}.map {stone -> Occupancy in
                    stone == Stone.black ? .black:stone == Stone.white ? .white:.empty
                } ?? []
                if references[f.reference]==nil {references[f.reference]=GrayFrame(image:photo(f.reference))!}
                // Replay the recorded accepted grid; independently rerun stone
                // detection, Vision hands, outline tracking and lighting/tracks.
                let result=CameraAnalysisPipeline.process(.init(target:photo(f.image),calibration:f.calibration,threshold:f.threshold,
                    reference:references[f.reference],referenceCalibration:f.referenceCalibration,straighten:false,longAxisRows:false,
                    checkStoneAspect:false,previousStoneCount:0,pendingAxis:nil,trackingAnchor:nil,alignmentExpected:expected,
                    checkAlignment:false,trackingState:stones,trackingExpected:expected,trackingContext:mode,
                    trackingManualPoints:[],trackingFresh:true,trackingTime:time,checkHands:true,handTracking:tracker,
                    handTimestampSource:"cameraPresentation",emptyLighting:lighting,lightingContext:mode))
                tracker=result.handTracking;stones=result.trackingResult;lighting=result.emptyLighting
                var visual=result.handOutline
                if mode=="saved-gate" {
                    visual=f.originalOutline
                    if let e=visual?.estimate {
                        visual?.estimate = .init(time:e.time+offset,method:e.method,observedLower:e.observedLower.map{$0+offset},
                            observedUpper:e.observedUpper.map{$0+offset},estimatedError:e.estimatedError,samples:e.samples,
                            timestampSource:e.timestampSource,fallbackReason:e.fallbackReason)
                    }
                }
                let hand=visual?.obstructed
                let estimate=r.observeHandMotion(result.handPose,at:time,source:"cameraPresentation",visual:visual)
                if hand==true {r.noteHandObstruction(now:now,capturedAt:time)}
                else if var observation=result.trackedObservation ?? result.result {
                    if hand==false {r.noteHandClear()}
                    observation.capturedAt=time;observation.handObstructed=hand;observation.clockPressEstimate=estimate
                    r.consume(observation,now:now)
                }
                r.clock.tick(at:now);everReview = everReview || r.clock.requiresReview
                for press in r.clock.moves+r.clock.provisionalMoves {
                    if let e=press.estimate {
                        if let old=receipts[press.number],old != e {changedReceipts=true}
                        receipts[press.number]=e
                    }
                }
                rows.append(["frame":f.id,"capture":f.capturedAt,"hand":hand as Any? ?? NSNull(),
                    "reason":visual?.reason ?? "none","depth":visual?.depth as Any? ?? NSNull(),
                    "estimate":estimate.map{$0.time-offset} as Any? ?? NSNull(),
                    "savedMoves":r.moveCount,"timedMoves":receipts.keys.sorted(),"review":r.clock.requiresReview,
                    "status":r.status])
                if f.id%50==0 {print(mode,f.id,"moves",r.moveCount,"timed",receipts.count,"review",everReview)}
            }
            let presses=(r.clock.moves+r.clock.provisionalMoves).sorted{$0.number<$1.number}
            let expected=[300,60,307,269,268,249,287,250]
            let points=r.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}
            let report:[String:Any]=["mode":mode,"savedPoints":points,"timedMoves":presses.map(\.number),
                "pressTimes":presses.map{($0.estimate?.time ?? offset)-offset},"everReview":everReview,
                "running":r.clock.running,"status":r.status,"clockNotice":r.clock.notice,
                "receiptsChanged":changedReceipts,"unresolved":r.stoneLedger?.records.filter(\.locationUnresolved).map(\.number) ?? []]
            reports.append(report);print(report)
            try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent(mode+"-frames.json"))
            if mode=="saved-gate" {allPassed = allPassed && everReview && presses.count==2}
            else {
                allPassed = allPassed && !everReview && r.clock.running && presses.map(\.number)==Array(1...8) && !changedReceipts
                allPassed = allPassed && points==Array(expected.prefix(points.count))
                // White is visibly placed before the hand exit bracket in images
                // 59–60. Images 74–81 show later cleanup of that same stone.
                // Location uncertainty must not defer White's press to cleanup.
                let lower=input.frames.first{$0.id==59}!.capturedAt
                let upper=input.frames.first{$0.id==60}!.capturedAt
                let white=presses.first{$0.number==2}?.estimate
                allPassed = allPassed && white != nil && abs(white!.time-offset-(lower+upper)/2)<1e-6
                allPassed = allPassed && rows.first{$0["frame"] as? Int==118}?["hand"] as? Bool==true
                allPassed = allPassed && rows.first{$0["frame"] as? Int==150}?["hand"] as? Bool==false
                // Earlier turn detection may leave its original location for
                // review. Complete the SGF without creating or retiming turns.
                r.pause()
                let ids=r.stoneLedger!.records.map(\.id),pending=r.deferredPendingRecords
                let correction=pending.isEmpty ? nil:r.resolveDeferredLocations(
                    Dictionary(uniqueKeysWithValues:pending.map{($0.number,expected[$0.number-1])}),identities:pending.map(\.id))
                let completed=r.game.moves.compactMap{$0.1.map{$0.1*19+$0.0}}
                let corrected=r.clock.moves+r.clock.provisionalMoves
                let preserved=presses.allSatisfy {before in corrected.contains {after in
                    before.number==after.number && before.estimate==after.estimate && before.before==after.before && before.after==after.after
                }}
                allPassed = allPassed && correction==nil && completed==expected && preserved && r.stoneLedger!.records.map(\.id)==ids
                reports[reports.count-1]["completedPoints"]=completed
                reports[reports.count-1]["correctionPreservedReceipts"]=preserved
                reports[reports.count-1]["correctionError"]=correction as Any? ?? NSNull()
            }
            r.pause()
        }
        try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("results.json"))
        precondition(allPassed,"Resting-hands recording did not meet clock/coverage/sequence requirements; inspect reports")
        print("PASS: original failure reproduced; corrected camera pipeline keeps all eight turns timed without changing confirmed receipts")
    }
}
