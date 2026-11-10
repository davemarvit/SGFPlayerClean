import AppKit

@MainActor private final class TestRecoveryVoice:RecoverySpeechOutput {
    var hasStartedSpeech=false
    var onSpeechFinished:(()->Void)?
    var onSpeechEvent:SpeechEventHandler?
    var phrases=[String](),stops=[String]()
    func say(_ text:String,settings:LocalClockSounds,announcement:Bool) {phrases.append(text);hasStartedSpeech=false}
    func stop(reason:String) {stops.append(reason);hasStartedSpeech=false}
    func start() {hasStartedSpeech=true;onSpeechEvent?("started",[:])}
    func finish() {hasStartedSpeech=false;onSpeechFinished?()}
}

@main struct ObstructionFeedbackTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        let file=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/HandObstruction/reports.json")
        let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [[String:Any]]
        let reports=rows.map{$0["report"] as! [String:Any]}
        check(reports.contains(where:BoardAlignmentGate.likelyObstruction),"Actual hand incident lost its surviving-stone/broken-edge evidence")
        var prompt=BoardRecoveryPrompt()
        for (i,report) in reports.enumerated() {
            check(prompt.update(recovering:true,needsHelp:true,enabled:true,now:Double(i)*0.25,
                obstructed:BoardAlignmentGate.likelyObstruction(report))==nil,"Recorded hand wave immediately asked for camera adjustment")
        }
        check(prompt.likelyObstruction && !prompt.maySearch(now:7.9),"Obstruction hint did not survive temporary loss of more landmarks")
        check(prompt.update(recovering:true,needsHelp:true,enabled:true,now:8)?.contains("Move hands and other obstructions clear") == true,"Prolonged obstruction did not explain what to clear")
        check(prompt.update(recovering:true,needsHelp:true,enabled:true,now:20)==nil,"One obstruction repeated its warning")
        var moved=reports[0];moved["rejectionReason"]="fitted grid moved at least 0.4 intersections"
        check(!BoardAlignmentGate.likelyObstruction(moved),"Measured camera displacement was mistaken for a hand")
        var blank=reports[0];blank["knownStoneMatches"]=0;blank["knownStoneFraction"]=0.0
        check(!BoardAlignmentGate.likelyObstruction(blank),"Lost view fabricated surviving stone evidence")
        var gate=BoardAlignmentGate()
        check(gate.shouldHold(report:moved,now:0,allowGrace:true),"Real displacement received unsafe frame-acceptance grace")

        let voice=TestRecoveryVoice(),speech=RecoverySpeech(audio:voice),feedback=BoardViewRecoveryFeedback(speech:speech)
        let settings=LocalClockSounds()
        func sample(_ clear:Bool,_ time:Double,fresh:Bool=true,enabled:Bool=true,running:Bool=false) {
            feedback.observe(clear:clear,fresh:fresh,now:time,enabled:enabled,clocksEnabled:true,clockRunning:running,settings:settings)
        }
        func clearView(_ time:Double,enabled:Bool=true,running:Bool=false) {
            for i in 0..<5 {sample(true,time+Double(i)*0.25,enabled:enabled,running:running)}
        }
        // A hand need not be recognized as a hand: every silent interruption,
        // including long ones, must recover silently during ordinary play.
        for turn in 0..<20 {
            let t=Double(turn)*15
            sample(false,t,running:true);sample(false,t+9,running:true)
            clearView(t+10,running:true)
        }
        check(voice.phrases.isEmpty,"Routine moves or a long silent obstruction produced all-clear chatter")
        feedback.reset();sample(false,400)
        speech.request(.alignment,text:"Check the camera",settings:settings);voice.start();voice.finish()
        sample(false,401)
        sample(true,401.2,fresh:false);sample(true,401.2,fresh:false)
        for t in [401.25,401.5,401.75,402.0] {sample(true,t)}
        check(voice.phrases==["Check the camera"],"Stale or insufficient clear frames announced recovery")
        sample(true,402.25)
        check(voice.phrases.last=="Board view clear. Clocks remain paused.","An audible camera warning lacked its recovery acknowledgement")
        voice.start();voice.finish();sample(true,403)
        let afterWarning=voice.phrases.count
        for turn in 0..<5 {
            let t=410+Double(turn)*5
            sample(false,t);sample(false,t+1);clearView(t+1.25)
        }
        check(voice.phrases.count==afterWarning,"An old warning caused acknowledgements after later routine moves")

        feedback.reset();sample(false,450)
        speech.request(.lighting,text:"Improve the lighting",settings:settings) // Never audible.
        clearView(451)
        check(voice.phrases.last=="Improve the lighting" && voice.stops.last=="condition recovered","An unplayed warning earned an unnecessary all-clear")
        feedback.reset();sample(false,460)
        speech.request(.lighting,text:"Reduce glare",settings:settings);voice.start()
        clearView(461)
        check(voice.phrases.last=="Reduce glare","All-clear interrupted an audible warning")
        voice.finish()
        check(voice.phrases.last=="Board view clear. Clocks remain paused.","Lighting recovery failed to follow the audible warning")
        sample(false,462.1)
        check(voice.stops.last=="board view unclear again","Queued all-clear survived renewed obstruction")
        clearView(463)
        check(voice.phrases.filter{$0=="Board view clear. Clocks remain paused."}.count==2,"Renewed silent obstruction repeated the same recovery announcement")

        feedback.reset();sample(false,480)
        speech.request(.alignment,text:"Show the corners",settings:settings);voice.start();voice.finish()
        for t in [481.0,481.25,483.0,483.25,483.5,483.75] {sample(true,t)}
        check(voice.phrases.last=="Show the corners","A camera gap counted as sustained clear evidence")
        sample(true,484)
        check(voice.phrases.last=="Board view clear. Clocks remain paused.","Fresh clear evidence after a gap failed to acknowledge recovery")
        voice.finish();feedback.reset();sample(false,490)
        speech.request(.lighting,text:"Check glare",settings:settings);voice.start();voice.finish()
        clearView(491,enabled:false)
        check(voice.phrases.last=="Check glare","Muted recovery spoke")
        clearView(493)
        check(voice.phrases.last=="Check glare","Unmuting replayed an old recovery")

        feedback.reset();sample(false,500)
        speech.request(.alignment,text:"Check alignment",settings:settings);voice.start();voice.finish()
        speech.request(.clockResume,text:"Clocks resumed. White to play.",settings:settings)
        clearView(501,running:true)
        check(voice.phrases.last=="Clocks resumed. White to play.","Clock resume was followed by a duplicate board all-clear")
        voice.finish()
        // The clock coordinator may forget the warning; actual playback still
        // earns one acknowledgement in this interruption, never in a later one.
        feedback.reset();sample(false,510)
        speech.request(.lighting,text:"Improve lighting",settings:settings);voice.start();voice.finish()
        speech.forgetAnnouncement(.lighting);clearView(511,running:true)
        check(voice.phrases.last=="Board view clear.","Another consumer clearing heard-state lost a genuine recovery")
        voice.finish();feedback.reset();sample(false,520);clearView(521,running:true)
        check(voice.phrases.filter{$0=="Board view clear."}.count==1,"Reset carried a completed warning into a new silent episode")
        try runCoveredBorderTests()
        print("PASS: \(checks) obstruction feedback checks: actual hand reports, silent routine moves, episode-scoped audible recovery, fresh frames, mute, camera gaps, queued speech and clock-resume deduplication")
    }
}
