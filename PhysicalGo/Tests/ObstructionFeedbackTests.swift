import AppKit

@MainActor private final class TestRecoveryVoice:RecoverySpeechOutput {
    var hasStartedSpeech=false
    var onSpeechFinished:(()->Void)?
    var onSpeechEvent:SpeechEventHandler?
    var phrases=[String](),stops=[String]()
    func say(_ text:String,settings:LocalClockSounds,announcement:Bool) {phrases.append(text);hasStartedSpeech=false}
    func stop(reason:String) {stops.append(reason);hasStartedSpeech=false}
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
        sample(false,0);sample(false,1)
        sample(true,1.2,fresh:false);sample(true,1.2,fresh:false)
        check(voice.phrases.isEmpty,"Redrawing an old image announced recovery")
        for t in [1.25,1.5,1.75,2.0] {sample(true,t)}
        check(voice.phrases.isEmpty,"Single/short clear view announced stability")
        sample(true,2.25)
        check(voice.phrases==["Board view clear. Clocks remain paused."],"Paused game did not receive truthful recovery acknowledgement")
        voice.finish();sample(true,3);sample(true,4)
        check(voice.phrases.count==1,"Stable view repeatedly announced itself")
        sample(false,5);sample(false,6);sample(true,6.25);sample(true,6.5)
        sample(false,6.6)
        for t in [7.0,7.25,7.5,7.75] {sample(true,t)}
        check(voice.phrases.count==1,"Flicker counted as sustained recovery")
        sample(true,8)
        check(voice.phrases.count==2,"Stable recovery after flicker stayed silent")
        sample(false,8.1)
        check(voice.stops.contains("board view unclear again"),"A queued all-clear survived another obstruction")
        feedback.reset();sample(false,10);sample(false,11)
        for t in [12.0,12.25,14.0,14.25,14.5,14.75] {sample(true,t)}
        check(voice.phrases.count==2,"Camera gap counted as continuous clear evidence")
        sample(true,15)
        check(voice.phrases.count==3,"Fresh clear frames after gap failed recovery")
        voice.finish();feedback.reset()
        sample(false,20);sample(false,21)
        for t in [21.25,21.5,21.75,22.0,22.25] {sample(true,t,enabled:false)}
        check(voice.phrases.count==3,"Muted recovery spoke")
        feedback.reset();sample(false,25);sample(false,26)
        speech.request(.clockResume,text:"Clocks resumed. White to play.",settings:settings)
        for t in [26.25,26.5,26.75,27.0,27.25] {sample(true,t,running:true)}
        check(voice.phrases.last=="Clocks resumed. White to play." && voice.phrases.count==4,"Clock resume and board recovery produced duplicate announcements")
        voice.finish();feedback.reset();sample(false,30)
        for t in [30.25,30.5,30.75,31.0,31.25] {sample(true,t)}
        check(voice.phrases.count==4,"A fleeting silent obstruction produced unnecessary chatter")
        feedback.reset();sample(false,40);sample(false,41)
        speech.request(.alignment,text:"Please clear the board view.",settings:settings);voice.hasStartedSpeech=true
        for t in [41.25,41.5,41.75,42.0,42.25] {sample(true,t)}
        check(voice.phrases.last=="Please clear the board view.","Recovery spoke over an active warning")
        voice.finish()
        check(voice.phrases.last=="Board view clear. Clocks remain paused.","Audible warning was not followed by all-clear")
        voice.finish();feedback.reset()
        let beforeHand=voice.phrases.count
        for i in 0..<20 {
            feedback.observe(clear:false,fresh:true,now:50+Double(i)*0.2,handObstructed:true,enabled:true,clocksEnabled:true,clockRunning:true,settings:settings)
        }
        for t in [54.0,54.25,54.5,54.75,55.0] {sample(true,t,running:true)}
        check(voice.phrases.count==beforeHand,"Ordinary hand placement generated recovery chatter")
        try runCoveredBorderTests()
        print("PASS: \(checks) obstruction feedback checks: actual hand reports, grace, real movement, fresh stable recovery, manual pause, mute, flicker, camera gaps, queued speech and clock-resume deduplication")
    }
}
