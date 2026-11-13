import AppKit
import SwiftUI

private final class DelayedKokoro:KokoroSpeechSynthesizing,@unchecked Sendable {
    let available=true
    var completion:(@Sendable (Data?)->Void)?
    func cached(_ text:String)->Data? {nil}
    func synthesize(_ text:String,completion:@escaping @Sendable (Data?)->Void) {self.completion=completion}
}

@main struct CaptureHoldFeedbackTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        func wait(_ seconds:Double) {RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
        var sounds=LocalClockSounds();sounds.volume=0
        let silent=try KokoroSpeech.wav(Array(repeating:Float(0),count:8000))
        let cold=DelayedKokoro(),audio=LocalClockAudio.forRecovery(kokoro:cold)
        let recovery=RecoverySpeech(audio:audio)
        var engines=[String](),fallbacks=0
        recovery.onSpeechEvent={event,details in
            if event=="started",let engine=details["engine"] as? String {engines.append(engine)}
            if event=="fallback" {fallbacks+=1}
        }
        recovery.request(.recordingWarning,text:"Clocks paused. Remove captured stones.",settings:sounds)
        wait(1.7)
        check(engines.isEmpty && fallbacks==0,"Cold recovery fell back after the clock-speech deadline")
        cold.completion?(silent);wait(0.6)
        check(engines==["Kokoro"] && fallbacks==0,"First delayed recovery did not use Kokoro exactly once")
        let prior=engines
        recovery.request(.recordingWarning,text:"An obsolete removal instruction.",settings:sounds)
        recovery.resolved(.recordingWarning,reason:"capture completed",interruptAudible:true)
        cold.completion?(silent);wait(0.3)
        check(engines==prior,"Late Kokoro result spoke obsolete capture instructions")
        recovery.request(.recordingWarning,text:"Synthesis failure.",settings:sounds)
        cold.completion?(nil);wait(0.1)
        check(fallbacks==1,"Actual Kokoro failure suppressed necessary fallback")
        recovery.stop(reason:"test finished")
        let urgent=DelayedKokoro(),clockAudio=LocalClockAudio(kokoro:urgent)
        var urgentFallbacks=0,lateKokoro=false
        clockAudio.onSpeechEvent={event,details in
            if event=="fallback" {urgentFallbacks+=1}
            if event=="started",details["engine"] as? String=="Kokoro" {lateKokoro=true}
        }
        clockAudio.say("Three periods left.",settings:sounds,announcement:true);wait(1.7)
        check(urgentFallbacks==1,"Time-sensitive clock announcement lost its deadline")
        urgent.completion?(silent);wait(0.2)
        check(!lateKokoro,"Late synthesis duplicated a time-sensitive fallback")
        clockAudio.stop(reason:"test finished")

        let root=FileManager.default.temporaryDirectory.appendingPathComponent("capture-hold-feedback-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/IncompleteCapture")
        let sgf=try String(contentsOf:fixture.appendingPathComponent("before.sgf"),encoding:.utf8)
        let partial=try JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:fixture.appendingPathComponent("observed.json")))
        let game=SGFGame.from(tree:try SGFParser.parse(text:sgf)),plan=AutomaticCapture.find(game:game,readings:partial,minimum:2)!
        var prisoners=plan.before;prisoners[plan.point]=plan.color == .black ? .black:.white
        let file=root.appendingPathComponent("game.sgf");try sgf.write(to:file,atomically:true,encoding:.utf8)
        let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:file)
        r.attachClock(.init(kind:.absolute,mainSeconds:300));r.resume()
        var now=ProcessInfo.processInfo.systemUptime
        func feed(_ values:[Occupancy],count:Int=6) {
            for _ in 0..<count {now+=0.21;r.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:now,handObstructed:false),now:now)}
        }
        feed(plan.before);feed(prisoners)
        func presentation()->LocalPlayPresentation {LocalPlayPresentation(recorder:r,clock:r.clock)}
        check(r.clock.automaticCapturePaused && !r.clock.running,"Fixture did not enter automatic capture hold")
        check(presentation().captureHold && presentation().transportTitle=="Paused for stone removal","Capture transport still implies running clocks")
        let held=r.clock.engine
        let host=NSHostingView(rootView:LocalClockPanel(clock:r.clock,recorder:r).environment(\.colorScheme,.dark).background(Color.black))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:740),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;window.orderFront(nil)
        wait(0.2);host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
        let output=try TestArtifacts.file("capture-hold-feedback/paused-for-removal.png")
        try bitmap.representation(using:.png,properties:[:])!.write(to:output);window.orderOut(nil)
        r.pause()
        check(!presentation().captureHold && presentation().transportTitle=="Resume","Manual pause lost the way to resume capture checking")
        check(r.clock.engine.black==held.black && r.clock.engine.white==held.white,"Pausing capture checking charged time")
        r.resume();feed(prisoners)
        check(presentation().captureHold && !r.clock.running,"Resuming capture checking started clocks before removal")
        var one=prisoners;one[plan.captured.sorted().first!] = .empty;feed(one)
        check(presentation().captureHold && presentation().transportTitle=="Paused for stone removal","Partial removal cleared capture hold presentation")
        feed(plan.target,count:12)
        check(r.clock.running && !presentation().captureHold && presentation().transportTitle=="Pause","Verified completion failed to restore running transport")
        check(r.moveCount==game.moves.count+1,"UI lifecycle duplicated or lost the capture")
        r.pause()
        print("PASS: \(checks) capture hold feedback checks: first cold Kokoro, cancellation/failure/deadline, hold label, manual pause, partial removal and completion; native panel at \(output.path)")
    }
}
