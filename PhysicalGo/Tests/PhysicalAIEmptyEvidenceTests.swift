// Real controller and pipeline tests; synthetic observation sequences are
// explicitly distinct from a measured live-camera recognition delay.
import Foundation
import ImageIO

@MainActor private final class EmptyEvidenceScenario {
    final class Clock {var now=100.0}
    let clock=Clock(),referenceID=UUID()
    let ai:PhysicalAI
    let historyCount:Int
    init(root:URL,black:Bool)throws {
        let folder=root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var settings=PhysicalAISettings();settings.size=19;settings.humanBlack=black
        let moves:[Int?]=black ? []:[72];historyCount=moves.count
        var saved=PhysicalAI.Snapshot(id:UUID(),settings:settings,moves:moves.map{.init(point:$0)})
        let player=SGFPlayer();player.load(game:PhysicalAI.game(saved));player.seek(to:moves.count)
        saved.verifiedPosition = .init(cells:player.board.grid.flatMap{$0}.map{$0?.rawValue ?? "empty"},cameraContext:"empty-proof-grid")
        try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("current.json"))
        let c=clock
        let laser=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,uptime:{c.now})
        ai=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:laser,uptime:{c.now})
        laser.observeCamera(hand:false,valid:true,capturedAt:c.now,now:c.now,context:"empty-proof-grid")
        ai.resume()
        for _ in 0..<4 {let o=next();ai.consume(o,now:c.now)}
    }
    func next(point:Int?=nil,black:Bool=true,neighbor:Int?=nil,mode:String="valid")->BoardObservation {
        clock.now+=0.2
        var readings=ai.cells.enumerated().map {.init(row:$0.offset/19,col:$0.offset%19,occupancy:Occupancy(rawValue:$0.element)!,confidence:1,delta:0) as IntersectionReading}
        if let point {readings[point] = .init(row:point/19,col:point%19,occupancy:black ? .black:.white,confidence:0.96,delta:black ? -0.3:0.3)}
        if let neighbor {readings[neighbor] = .init(row:neighbor/19,col:neighbor%19,occupancy:.empty,confidence:0.75,delta:0.003)}
        let stamp=mode=="stale" ? clock.now-2:clock.now,imageID=UUID()
        var o=BoardObservation(readings:readings,size:19,capturedAt:stamp,handObstructed:false,evidenceFrameID:imageID,evidenceReferenceID:referenceID)
        if let neighbor,mode != "missing" {
            o.emptyCrossingEvidence[neighbor] = .init(frameID:mode=="frame" ? UUID():imageID,
                referenceID:mode=="reference" ? UUID():referenceID,capturedAt:mode=="timestamp" ? stamp-0.1:stamp,
                reading:readings[neighbor],support:.init(woodMatches:21,woodSamples:27,railMatches:[3,4],railSamples:[4,4],innerMatches:3,innerSamples:4))
            if mode=="mutation" {
                let saved=readings[neighbor]
                o.readings[neighbor] = .init(row:saved.row,col:saved.col,occupancy:.empty,confidence:0.75,delta:0.1)
                o.readings[neighbor]=saved
            }
            if mode=="uncertain" || mode=="extra-black" || mode=="extra-white" {
                o.readings[neighbor] = .init(row:neighbor/19,col:neighbor%19,occupancy:mode=="uncertain" ? .uncertain:mode=="extra-black" ? .black:.white,confidence:mode=="uncertain" ? 0.75:1,delta:0)
            }
            if mode=="covering-fit" {o.footprints=[.init(row:neighbor/19,col:neighbor%19,center:.init(x:Double(neighbor%19),y:Double(neighbor/19)),radiusCol:0.42,radiusRow:0.42,quality:0.95)]}
        }
        if mode=="hand" {o.handObstructed=true}
        if mode=="unknown-hand" {o.handObstructed=nil}
        if mode=="lighting" {o.lightingBlocked=true}
        if mode=="target-offset",let point {o.footprints=[.init(row:point/19,col:point%19,center:.init(x:Double(point%19)+0.45,y:Double(point/19)),radiusCol:0.43,radiusRow:0.43,quality:0.95)]}
        return o
    }
    func feed(point:Int,black:Bool,neighbor:Int,mode:String="valid",count:Int=1) {
        for _ in 0..<count {let o=next(point:point,black:black,neighbor:neighbor,mode:mode);ai.consume(o,now:clock.now)}
    }
}

@main struct PhysicalAIEmptyEvidenceTests {
    @MainActor static func main()throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);checks+=1}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("empty-proof-controller-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        for black in [false,true] {
            for point in [0,9,18,171,180,189,342,351,360] {
                let h=try EmptyEvidenceScenario(root:root,black:black),neighbor=point%19==18 ? point-1:point+1
                check(h.ai.phase == .human,"Fixture must begin a verified human turn")
                let anchor=h.ai.timing.anchor
                h.feed(point:point,black:black,neighbor:neighbor,mode:"missing",count:5)
                check(h.ai.snapshot!.moves.count==h.historyCount && h.ai.timing.anchor==anchor,"Weak empty without positive proof must not advance moves or clock")
                h.feed(point:point,black:black,neighbor:neighbor,count:3)
                check(h.ai.snapshot!.moves.count==h.historyCount,"Three frames spanning only0.4seconds must not short-circuit stability")
                h.feed(point:point,black:black,neighbor:neighbor)
                check(h.ai.snapshot!.moves.count==h.historyCount+1 && h.ai.snapshot!.moves.last!.point==point,"Both colors at corners/edges/interior must accept after normal fresh stability")
                h.ai.pause()
            }
            for mode in ["timestamp","frame","reference","mutation","uncertain","extra-black","extra-white","covering-fit","hand","unknown-hand","lighting","stale","target-offset"] {
                let h=try EmptyEvidenceScenario(root:root,black:black),anchor=h.ai.timing.anchor
                h.feed(point:180,black:black,neighbor:181,mode:mode,count:5)
                check(h.ai.snapshot!.moves.count==h.historyCount && h.ai.timing.anchor==anchor,"Invalid/competing evidence must preserve history and clock: \(mode), \(black)")
                h.ai.pause()
            }
            let interrupted=try EmptyEvidenceScenario(root:root,black:black),anchor=interrupted.ai.timing.anchor
            interrupted.feed(point:180,black:black,neighbor:181,count:2)
            interrupted.feed(point:180,black:black,neighbor:181,mode:"missing")
            interrupted.feed(point:180,black:black,neighbor:181,count:3)
            check(interrupted.ai.snapshot!.moves.count==interrupted.historyCount && interrupted.ai.timing.anchor==anchor,"An unsupported neighbor must reset accumulated placement witnesses")
            interrupted.feed(point:180,black:black,neighbor:181)
            check(interrupted.ai.snapshot!.moves.count==interrupted.historyCount+1,"Later valid proof must recover without resetting the game")
            interrupted.ai.pause()
            let duplicate=try EmptyEvidenceScenario(root:root,black:black)
            let same=duplicate.next(point:180,black:black,neighbor:181)
            for _ in 0..<12 {duplicate.ai.consume(same,now:duplicate.clock.now)}
            check(duplicate.ai.snapshot!.moves.count==duplicate.historyCount,"Repeated identical frame must not count as multiple witnesses")
            duplicate.feed(point:180,black:black,neighbor:181,count:3)
            check(duplicate.ai.snapshot!.moves.count==duplicate.historyCount+1,"Independent new observations must still recover after duplicate frames")
            duplicate.ai.pause()
            let dark=try EmptyEvidenceScenario(root:root,black:black)
            check(dark.ai.laser.confirmPhysicalLaserOff(session:.init(source:"ai",session:dark.ai.snapshot!.id,size:19)),"Fixture must arm the real manual dark barrier")
            dark.feed(point:180,black:black,neighbor:181,count:5)
            check(dark.ai.snapshot!.moves.count==dark.historyCount,"Positive wood proof cannot bypass missing confirmed-dark camera evidence")
            dark.ai.pause()
        }
        // Actual pipeline: preserve original capture time, never trackingTime's
        // fallback. The repeated static photo tests wiring, not fresh witnesses.
        struct Meta:Decodable {let currentCalibration:BoardCalibration;let referenceCalibration:BoardCalibration}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CrowdedEmptyTarget")
        let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:fixture.appendingPathComponent("frame.json")))
        func image(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(fixture.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let photo=image("board.png"),reference=GrayFrame(image:image("empty.png"))!
        var input=CameraAnalysisPipeline.Input(target:photo,calibration:meta.currentCalibration,threshold:0.13,reference:reference,referenceCalibration:meta.referenceCalibration,
            straighten:false,longAxisRows:false,checkStoneAspect:false,previousStoneCount:0,pendingAxis:nil,trackingAnchor:nil,
            alignmentExpected:[],checkAlignment:false,trackingState:EstablishedStoneTracker(),trackingExpected:[],trackingContext:"receipt-pipeline",
            trackingManualPoints:[],trackingFresh:false,trackingTime:999,originalCaptureUptime:123)
        let delivered=CameraAnalysisPipeline.process(input)
        check(delivered.rawResult?.capturedAt==123 && !(delivered.rawResult?.emptyCrossingEvidence.isEmpty ?? true),"Pipeline must preserve explicit source time and actual positive pixel receipts")
        check(delivered.rawResult!.emptyCrossingEvidence.values.allSatisfy{$0.capturedAt==123 && $0.frameID==delivered.frame!.patchIdentity},"Receipts must identify the exact analyzed image, not processing time")
        input.originalCaptureUptime=nil
        let redraw=CameraAnalysisPipeline.process(input)
        check(redraw.rawResult?.capturedAt==nil && redraw.rawResult?.emptyCrossingEvidence.isEmpty==true,"Missing original capture time must never be replaced with tracking/processing fallback")
        print("PASS: \(checks) actual controller/pipeline empty-crossing evidence checks")
    }
}
