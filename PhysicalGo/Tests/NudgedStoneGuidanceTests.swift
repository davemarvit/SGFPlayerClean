import AppKit
import ImageIO
import SwiftUI

@main struct NudgedStoneGuidanceTests {
    struct Meta:Decodable {let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double}
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;precondition(ok,message)}
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/HalfwayNudge")
        func image(_ file:URL)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(file as CFURL,nil)!,0,nil)!}
        let reference=GrayFrame(image:image(folder.appendingPathComponent("empty-reference.png")))!
        func load(_ name:String)throws->(BoardObservation,GrayFrame,Meta) {
            let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent(name+".json")))
            let frame=GrayFrame(image:image(folder.appendingPathComponent(name+".png")))!
            return (BoardDetector.detect(frame:frame,reference:reference,calibration:meta.calibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!,frame,meta)
        }
        let (nudged,_,_)=try load("nudged"), (centered,centerFrame,meta)=try load("centered")
        var expected=[Occupancy](repeating:.empty,count:361)
        expected[60] = .black;expected[180] = .black;expected[300] = .white
        check(nudged.signature[180] == .uncertain && nudged.signature[199] == .uncertain,"Warning evidence assigned an ambiguous disk")
        check(nudged.centeringPoints(confirmedBoard:expected)==[180],"Real halfway stone lacks specific centering evidence")
        check(centered.centeringPoints(confirmedBoard:expected).isEmpty,"Centered real stone got a nudge warning")
        check(nudged.signature[60] == .black && nudged.signature[300] == .white,"Nudge affected other real stones")
        var noEvidence=nudged;noEvidence.centeringEvidence=[]
        check(noEvidence.centeringPoints(confirmedBoard:expected).isEmpty,"Uncertainty alone became a nudge")
        var crowded=expected;crowded[199] = .black
        check(nudged.centeringPoints(confirmedBoard:crowded).isEmpty,"Ambiguous same-color pair assigned one disk")
        crowded[199] = .white
        check(nudged.centeringPoints(confirmedBoard:crowded).isEmpty,"Opposite-color neighbor was ignored")
        var wrong=expected;wrong[180] = .white
        check(nudged.centeringPoints(confirmedBoard:wrong).isEmpty,"Wrong-color disk became centering advice")
        check(nudged.centeringPoints(confirmedBoard:Array(repeating:.empty,count:361)).isEmpty,"A new disk was assigned to history")
        for kind in 0..<3 {
            var blocked=nudged
            if kind==0 {blocked.handObstructed=true}
            if kind==1 {blocked.lightingBlocked=true}
            if kind==2 {blocked.manualPoints=[180]}
            check(blocked.centeringPoints(confirmedBoard:expected).isEmpty,"Hand/lighting/manual evidence produced guidance")
        }
        // Empty reference and real glare photos must not become nudge warnings.
        let empty=BoardDetector.detect(frame:reference,reference:reference,calibration:meta.referenceCalibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
        check(empty.centeringEvidence.isEmpty,"Empty wood supplied a displaced disk")
        struct GlareFrame:Decodable {let image:String;let calibration:BoardCalibration}
        let glareRoot=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ResidualGlare")
        let glare=try JSONDecoder().decode([GlareFrame].self,from:Data(contentsOf:glareRoot.appendingPathComponent("sequence.json")))
        for item in glare {
            let frame=GrayFrame(image:image(glareRoot.appendingPathComponent(item.image)))!
            let view=BoardDetector.detect(frame:frame,reference:reference,calibration:item.calibration,threshold:meta.threshold,referenceCalibration:meta.referenceCalibration)!
            check(view.centeringPoints(confirmedBoard:expected).isEmpty,"Real glare raised centering advice")
            check(view.centeringEvidence.isEmpty,"Real glare supplied a displaced-disk outline")
        }
        // Warning provenance survives adaptive-empty and tracking output copies.
        var adaptive=KnownEmptyLighting()
        var decorated=centered;decorated.centeringEvidence=nudged.centeringEvidence
        for n in 0..<8 {_=adaptive.observe(decorated,frame:centerFrame,calibration:meta.calibration,expected:expected,context:"copy",now:Double(n)*0.21,valid:true)}
        var readings=centered.readings
        readings[0] = .init(row:0,col:0,occupancy:.uncertain,confidence:0,delta:0)
        var uncertain=BoardObservation(readings:readings,size:19);uncertain.centeringEvidence=nudged.centeringEvidence
        let copied=adaptive.observe(uncertain,frame:centerFrame,calibration:meta.calibration,expected:expected,context:"copy",now:1.68,valid:true)
        check(copied.signature[0] == .empty && copied.centeringEvidence.count==nudged.centeringEvidence.count,"Adaptive empty path dropped warning evidence")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("nudged-guidance-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let r=GameRecorder(storage:root);r.clock.audible=false
        var now=ProcessInfo.processInfo.systemUptime
        func feed(_ input:BoardObservation,count:Int=7) {
            for _ in 0..<count {now += 0.21;var view=input;view.capturedAt=now;view.handObstructed=false;r.consume(view,now:now)}
        }
        r.start(size:19,now:now,clockSettings:.init(kind:.fischer,mainSeconds:300,incrementSeconds:30,maximumSeconds:600));r.pause()
        for point in [180,300,60] {r.manualMove(at:.init(point/19,point%19))}
        _=r.confirmClockReview(black:r.clock.engine.black,white:r.clock.engine.white,resume:false)
        r.resume();feed(centered)
        check(r.moveCount==3 && r.clock.running && !r.clock.engine.blackToPlay,"Running White setup failed")
        let sgf=r.sgf(),clock=r.clock.engine,presses=r.clock.pressEvidence.count
        // Repeating the same captured photograph is not fresh temporal evidence.
        var repeated=nudged;now += 0.21;repeated.capturedAt=now;repeated.handObstructed=false
        for _ in 0..<12 {r.consume(repeated,now:now)}
        check(r.adjustmentIssues[180]==nil,"Repeated frame raised a marker")
        feed(centered);feed(noEvidence)
        check(r.adjustmentIssues[180]==nil,"Plain uncertainty raised a marker")
        feed(nudged,count:3)
        check(r.adjustmentIssues[180]==nil,"Brief nudge bypassed debounce")
        feed(nudged,count:4)
        check(r.adjustmentIssues[180] == .centering,"Sustained nudge missing actionable marker")
        check(RecordingClarity.checkPoints(recorder:r,observation:nudged)==[180],"Nudge marked duplicate intersections")
        check(RecordingClarity.issues(recorder:r).contains{$0.kind == .nudged && $0.points==[180] && $0.hold==nil},"Nudge route/hold incorrect")
        check(r.sgf()==sgf && r.moveCount==3 && r.clock.engine==clock && r.clock.running && r.clock.pressEvidence.count==presses,"Nudge changed history, increment, turn or clock")
        let text=RecordingClarity.explanation(recorder:r,observation:nudged,orientation:.init(3)) ?? ""
        check(text.contains("K10") && text.contains("centering"),"Visible guidance lacks intended coordinate")
        let selection=LiveIssueSelection(point:180,position:r.issuePositionSignature,observed:r.discrepancyObservation(at:180))
        let review=LiveIssueReviewView(recorder:r,selection:selection,orientation:.init(3),onCorrect:{_ in},onClose:{})
        check(review.status == .centering && review.status.actionable,"Click did not open centering guidance")
        let host=NSHostingView(rootView:review.background(Color(nsColor:.windowBackgroundColor)))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:590,height:760),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=host;window.orderFront(nil);RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
        let artifacts=try TestArtifacts.directory("nudged-stone-guidance")
        try bitmap.representation(using:.png,properties:[:])!.write(to:artifacts.appendingPathComponent("centering.png"))
        feed(noEvidence)
        check(r.adjustmentIssues[180] == .centering,"Unknown frames falsely cleared centering issue")
        feed(centered)
        check(r.adjustmentIssues.isEmpty && review.status == .resolved && r.clock.running,"Fresh centered evidence failed to clear while running")
        check(r.sgf()==sgf && r.clock.engine==clock,"Running restoration changed history or clock")
        r.pause();let paused=r.clock.engine
        feed(nudged)
        check(r.adjustmentIssues[180] == .centering && !r.clock.running,"Paused nudge lost guidance or resumed clock")
        feed(centered)
        check(r.adjustmentIssues.isEmpty && r.clock.engine==paused && !r.clock.running && r.sgf()==sgf,"Paused restoration changed timing/history")
        window.orderOut(nil);try r.flushStorage()
        print("PASS: \(checks) nudge checks; two real photos, 16 real glare frames, synthetic timestamp debounce, running/paused recorder and native guidance")
    }
}
