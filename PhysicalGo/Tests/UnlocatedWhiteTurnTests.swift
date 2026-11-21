import AppKit
import ImageIO

/// Pixel replay of the missed C16 white from the established 19-stone position.
/// The journal supplies subsequent observations without saved images, never new
/// move decisions. Earlier hand-covered images were not saved continuously.
@main struct UnlocatedWhiteTurnTests {
    struct Photo:Decodable {
        let image:String,reference:String
        let calibration:BoardCalibration,referenceCalibration:BoardCalibration
        let threshold:Double
    }
    struct Frame:Decodable {
        let capturedAt:Double,availableAt:Double
        let hand:Bool?,lightingBlocked:Bool
        let readings:[IntersectionReading],shapes:[StoneFootprint],placements:[StoneFootprint]
        let estimate:ClockPressEstimate?,photo:Photo?
    }
    struct Control:Decodable {let event:String;let time:Double,capturedAt:Double;let estimate:ClockPressEstimate?}
    struct Input:Decodable {let start:Double;let frames:[Frame];let controls:[Control]}
    @MainActor static func main()throws {
        NSApplication.shared.setActivationPolicy(.accessory);setbuf(stdout,nil)
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks+=1;precondition(condition,message)}
        // One disk has two location hypotheses; neither is a raw white label.
        let empty=[Occupancy](repeating:.empty,count:81)
        func uncertain(_ t:Double)->BoardObservation {
            var values=empty;values[31] = .uncertain;values[40] = .uncertain
            return .init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,
                confidence:$0.element == .uncertain ? 0:1,delta:0)},size:9,capturedAt:t,handObstructed:false,
                centeringEvidence:[31,40].map{.init(color:.white,shape:.init(row:$0/9,col:$0%9,
                    center:.init(x:4,y:3.5),radiusCol:0.46,radiusRow:0.49,quality:0.96))})
        }
        func turn(_ make:(Double)->BoardObservation,enabled:Bool=true)->ClearBoardTiming.ObservedTurn? {
            var timing=ClearBoardTiming()
            for i in 0..<7 {let t=100+Double(i)*0.21;timing.observe(make(t),now:t,allowWhiteOutlineEvidence:enabled)}
            return timing.observedTurns(base:empty,excluding:[],after:0).first
        }
        let evidence=turn(uncertain)
        check(evidence?.locations==[31,40] && evidence?.color == .white,"One unresolved disk lost or assigned an exact point")
        check(evidence?.estimate.time==100,"Turn was dated at confirmation instead of first sighting")
        let source=uncertain(100),represented=source.turnEvidenceObservation
        check(source.signature[31] == .uncertain && source.signature[40] == .uncertain &&
              represented.signature.filter{$0 == .white}.count==1,"Turn evidence changed raw labels or duplicated the disk")
        check(turn(uncertain,enabled:false)==nil,"Compatibility mode accepted new outline evidence")
        check(turn{t in var o=uncertain(t);o.handObstructed=true;return o}==nil,"Hand-covered disk accepted")
        check(turn{t in var o=uncertain(t);o.handObstructed=nil;return o}==nil,"Unknown hand clearance accepted")
        check(turn{t in var o=uncertain(t);o.lightingBlocked=true;return o}==nil,"Lighting failure accepted")
        check(turn{t in var o=uncertain(t);o.manualPoints=[31];return o}==nil,"Manual corrections supplied clock evidence")
        check(turn{t in var o=uncertain(t);o.centeringEvidence.removeLast();return o}==nil,"One rejected hypothesis established a turn")
        check(turn{t in var o=uncertain(t);o.centeringEvidence=o.centeringEvidence.map{e in
            .init(color:.black,shape:e.shape)};return o}==nil,"White recovery weakened black/shadow detection")
        check(turn{t in var o=uncertain(t);o.footprints=[o.centeringEvidence[0].shape];return o}==nil,"Existing outline counted as another disk")
        check(turn{t in var o=uncertain(t);o.centeringEvidence=o.centeringEvidence.map{e in
            .init(color:e.color,shape:.init(row:e.shape.row,col:e.shape.col,center:e.shape.center,
                radiusCol:0.46,radiusRow:0.49,quality:0.93))};return o}==nil,"Weak disk outline accepted")
        check(turn{t in var o=uncertain(t);let old=o.centeringEvidence[1]
            o.centeringEvidence[1] = .init(color:.white,shape:.init(row:4,col:4,center:.init(x:4.15,y:3.5),
                radiusCol:old.shape.radiusCol,radiusRow:old.shape.radiusRow,quality:0.96));return o}==nil,
            "Disagreeing disk centers were merged")
        var interrupted=ClearBoardTiming()
        for i in 0..<5 {let t=100+Double(i)*0.21;interrupted.observe(uncertain(t),now:t,allowWhiteOutlineEvidence:true)}
        check(interrupted.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Too few observations accepted")
        interrupted.observe(uncertain(104),now:104,allowWhiteOutlineEvidence:true)
        check(interrupted.observedTurns(base:empty,excluding:[],after:0).isEmpty,"Camera gap reused old confirmation")
        var ledger=RecordingStoneLedger(size:9)
        try ledger.reconcile([.init(number:1,color:.white,pass:false,point:22,candidates:[22],press:nil)],captures:[:])
        let oldID=ledger.records[0].id
        var cleanupTiming=ClearBoardTiming()
        for i in 0..<8 {
            let t=100+Double(i)*0.21,observation=uncertain(t)
            let excluded=ledger.observe(observation.turnEvidenceObservation,now:t)
            cleanupTiming.observe(observation,now:t,allowWhiteOutlineEvidence:true)
            check(cleanupTiming.observedTurns(base:empty,excluding:excluded,after:0).isEmpty,
                "An existing white moved between intersections became another turn")
        }
        check(ledger.records.count==1 && ledger.records[0].id==oldID && ledger.records[0].locationUnresolved,
            "Unresolved cleanup changed the stone's identity or historical certainty")
        print("PASS:",checks,"unresolved white turn checks")
        let input=try JSONDecoder().decode(Input.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        let output=URL(fileURLWithPath:CommandLine.arguments[2])
        var reports=[[String:Any]]()
        func photo(_ path:String)->GrayFrame {
            GrayFrame(image:CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil)!,0,nil)!)!
        }
        func image(_ path:String)->CGImage {
            CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil)!,0,nil)!
        }
        let first=input.frames.first{$0.photo != nil}!.capturedAt
        let lastPhoto=input.frames.last{$0.photo != nil}!.capturedAt
        // Automatic clips sampled fewer images than live recognition processed.
        // Do not alternate reclassified pixels with the old defective labels in
        // that interval; replay only actual saved samples, at their real times.
        let frames=input.frames.filter{$0.photo != nil || $0.capturedAt>lastPhoto}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("UnlocatedWhite-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        do {
            let file=folder.appendingPathComponent("cleanup.sgf")
            try "(;AP[PhysicalGo:0.199]FF[4]GM[1]SZ[9];B[aa];W[ec];B[ii])".write(to:file,atomically:true,encoding:.utf8)
            let r=GameRecorder(storage:folder,deferredLocations:true);r.clock.audible=false
            try r.restoreSavedGame(from:file);r.attachClock(.init(kind:.absolute,mainSeconds:1800));_=r.resume()
            let start=ProcessInfo.processInfo.systemUptime+1
            func cleanupView(_ t:Double,moved:Bool)->BoardObservation {
                var o=uncertain(t)
                for p in [0,80] {o.readings[p] = .init(row:p/9,col:p%9,occupancy:.black,confidence:1,delta:0)}
                if !moved {
                    o.centeringEvidence=[]
                    for p in [31,40] {o.readings[p] = .init(row:p/9,col:p%9,occupancy:.empty,confidence:1,delta:0)}
                    o.readings[22] = .init(row:2,col:4,occupancy:.white,confidence:1,delta:0)
                }
                return o
            }
            for i in 0..<8 {let t=start+Double(i)*0.21;r.consume(cleanupView(t,moved:false),now:t)}
            check(r.clock.running && r.moveCount==3,"Cleanup setup did not resume")
            let ids=r.stoneLedger!.records.map(\.id)
            r.noteHandObstruction(now:start+1.8,capturedAt:start+1.8);r.noteHandClear()
            for i in 0..<10 {let t=start+2+Double(i)*0.21;r.consume(cleanupView(t,moved:true),now:t);r.clock.tick(at:t)}
            check(r.clock.lastTimedMove==3 && r.moveCount==3 && r.stoneLedger!.records.map(\.id)==ids,
                "Hand-covered cleanup created a phantom white turn")
            check(r.clock.running && !r.clock.requiresReview,"Location-only cleanup stopped the clocks")
            r.pause();try r.flushStorage()
            print("PASS: native recorder keeps a hand-covered white cleanup unresolved without an extra turn")
        }
        // Directly inspected position before White C16, including the earlier
        // black disk at D16. This is setup, not evidence of any new turn time.
        let setup=[300,60,306,288,307,308,289,290,270,309,249,294,72,97,66,44,187,54,73]
        let sgf="(;AP[PhysicalGo:0.199]FF[4]GM[1]SZ[19]RU[Japanese]"+setup.enumerated().map {i,p in
            ";\(i%2==0 ? "B":"W")[\(UnicodeScalar(97+p%19)!)\(UnicodeScalar(97+p/19)!)]"
        }.joined()+")"
        for mode in ["logged","pixels","pipeline"] {
            let pixels=mode != "logged",pipeline=mode=="pipeline"
            let file=folder.appendingPathComponent("\(mode).sgf")
            try sgf.write(to:file,atomically:true,encoding:.utf8)
            let r=GameRecorder(storage:folder,deferredLocations:true);r.clock.audible=false
            try r.restoreSavedGame(from:file)
            r.attachClock(.init(kind:.absolute,mainSeconds:1800));_=r.resume()
            let offset=ProcessInfo.processInfo.systemUptime+1-first
            func shifted(_ e:ClockPressEstimate?)->ClockPressEstimate? {e.map {
                .init(time:$0.time+offset,method:$0.method,observedLower:$0.observedLower.map{$0+offset},
                    observedUpper:$0.observedUpper.map{$0+offset},estimatedError:$0.estimatedError,samples:$0.samples,
                    timestampSource:$0.timestampSource,fallbackReason:$0.fallbackReason)
            }}
            var control=input.controls.firstIndex{$0.capturedAt>=first} ?? input.controls.count
            var lastEstimate:ClockPressEstimate?,everReview=false,changed=false
            var hands=HandOutlineTracker(),stones=EstablishedStoneTracker(),lighting=KnownEmptyLighting()
            var receipts=[Int:ClockPressEstimate](),references=[String:GrayFrame](),rows=[[String:Any]]()
            for f in frames {
                while control<input.controls.count,input.controls[control].time<=f.availableAt {
                    let c=input.controls[control];control+=1
                    if pipeline,c.capturedAt<=lastPhoto {continue}
                    if c.event=="hand obstruction began" {r.noteHandObstruction(now:c.time+offset,capturedAt:c.capturedAt+offset);lastEstimate=nil}
                    if c.event=="hand obstruction cleared" {r.noteHandClear()}
                    if c.event=="hand-clear clock boundary" {lastEstimate=shifted(c.estimate)}
                }
                var observation=BoardObservation(readings:f.readings,size:19,lightingBlocked:f.lightingBlocked,
                    footprints:f.shapes,placementFits:f.placements)
                var hand=f.hand,estimate=shifted(f.estimate) ?? lastEstimate;lastEstimate=nil
                if pixels,let p=f.photo {
                    if references[p.reference]==nil {references[p.reference]=photo(p.reference)}
                    if pipeline {
                        let expected=r.positions.last.map{DeferredMoveHistory.states($0)} ?? []
                        let result=CameraAnalysisPipeline.process(.init(target:image(p.image),calibration:p.calibration,
                            threshold:p.threshold,reference:references[p.reference],referenceCalibration:p.referenceCalibration,
                            straighten:false,longAxisRows:false,checkStoneAspect:false,previousStoneCount:0,pendingAxis:nil,
                            trackingAnchor:nil,alignmentExpected:expected,checkAlignment:false,trackingState:stones,
                            trackingExpected:expected,trackingContext:mode,trackingManualPoints:[],trackingFresh:true,
                            trackingTime:f.capturedAt+offset,checkHands:true,handTracking:hands,
                            handTimestampSource:"cameraPresentation",emptyLighting:lighting,lightingContext:mode))
                        hands=result.handTracking;stones=result.trackingResult;lighting=result.emptyLighting
                        hand=result.handOutline?.obstructed
                        estimate=r.observeHandMotion(result.handPose,at:f.capturedAt+offset,source:"cameraPresentation",visual:result.handOutline)
                        observation=result.trackedObservation ?? result.result!
                    } else {
                        observation=BoardDetector.detect(frame:photo(p.image),reference:references[p.reference]!,calibration:p.calibration,
                            threshold:p.threshold,referenceCalibration:p.referenceCalibration)!
                    }
                }
                observation.capturedAt=f.capturedAt+offset;observation.handObstructed=hand
                observation.clockPressEstimate=estimate
                if hand==true {r.noteHandObstruction(now:f.availableAt+offset,capturedAt:f.capturedAt+offset)}
                else {if hand==false {r.noteHandClear()};r.consume(observation,now:f.availableAt+offset)}
                r.clock.tick(at:f.availableAt+offset)
                everReview = everReview || r.clock.requiresReview
                for p in r.clock.moves+r.clock.provisionalMoves {
                    if let e=p.estimate {
                        if let old=receipts[p.number],old != e {changed=true}
                        receipts[p.number]=e
                    }
                }
                if f.capturedAt-input.start>117 {
                    rows.append(["time":f.capturedAt,"photo":f.photo?.image as Any? ?? NSNull(),
                        "rawC16":observation.readings[53].occupancy.rawValue,
                        "turnC16":observation.turnEvidenceObservation.readings[53].occupancy.rawValue,
                        "centering":observation.centeringEvidence.count,"timed":r.clock.lastTimedMove,
                        "review":r.clock.requiresReview,"status":r.status])
                }
            }
            let presses=(r.clock.moves+r.clock.provisionalMoves).sorted{$0.number<$1.number}
            let report:[String:Any]=["mode":mode,"pixels":pixels,"timed":r.clock.lastTimedMove,"review":everReview,"running":r.clock.running,
                "changedReceipts":changed,"saved":r.moveCount,"notice":r.clock.notice,"status":r.status,
                "presses":presses.map{["number":$0.number,"time":($0.estimate?.time ?? offset)-offset,
                    "locations":$0.observedLocations as Any? ?? NSNull()]},"frames":rows]
            reports.append(report);print(mode,"timed",r.clock.lastTimedMove,"review",everReview,"running",r.clock.running,"changed",changed)
            if pixels {
                check(!everReview && r.clock.running,"Unresolved white stopped the clocks")
                check(presses.map(\.number)==[20,21],"Missed or duplicated the white/black turns")
                check(presses[0].observedLocations==[34,53] && presses[1].observedLocations==[52],"Lost location alternatives or merged distinct stones")
                let whiteAppearance=frames.first{$0.photo?.image.hasSuffix("/000017.png")==true}!.capturedAt
                let blackAppearance=frames.first{$0.photo?.image.hasSuffix("/000031.png")==true}!.capturedAt
                if pipeline {
                    check(presses[0].estimate!.time-offset<=whiteAppearance && presses[0].estimate!.time-offset>input.start+122,
                        "White hand estimate outside its placement interval")
                    check(presses[1].estimate!.time-offset<=blackAppearance && presses[1].estimate!.time-offset>input.start+125.4,
                        "Black hand estimate outside its placement interval")
                } else {
                    check(abs(presses[0].estimate!.time-offset-whiteAppearance)<1e-6,"White dated at confirmation rather than its first visible appearance")
                    check(abs(presses[1].estimate!.time-offset-blackAppearance)<1e-6,"Following black turn retimed")
                }
                check(!changed && r.stoneLedger!.records[19].locationUnresolved,"Receipts changed or white location silently resolved")
                r.pause()
                let identities=r.stoneLedger!.records.map(\.id)
                check(r.resolveDeferredLocations([20:53,21:52],identities:r.deferredPendingRecords.map(\.id))==nil,"Later location correction rejected")
                let corrected=r.clock.moves+r.clock.provisionalMoves
                check(r.moveCount==21 && r.stoneLedger!.records.map(\.id)==identities,"Correction created another move or changed identities")
                for p in presses {
                    let after=corrected.first{$0.number==p.number}!
                    check(after.estimate==p.estimate && after.before==p.before && after.after==p.after,"Correction changed original timing or balances")
                }
                reports[reports.count-1]["correctionPreservedReceipts"]=true
                print("PASS: C16 correction retains both clock receipts and all stone identities")
            } else {
                check(everReview && !r.clock.running && presses.isEmpty && r.clock.lastTimedMove==19,"Original missed-white failure did not reproduce")
            }
            r.pause()
            try r.flushStorage()
        }
        try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        print("PASS:",checks,"checks, including recorded white/black continuation and later correction")
    }
}
