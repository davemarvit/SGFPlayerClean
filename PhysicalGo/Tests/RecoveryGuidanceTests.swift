import AppKit

@MainActor private final class GuidanceVoice:RecoverySpeechOutput {
    var hasStartedSpeech=false
    var onSpeechFinished:(()->Void)?
    var onSpeechEvent:SpeechEventHandler?
    var phrases=[String](),stops=[String]()
    func say(_ text:String,settings:LocalClockSounds,announcement:Bool) {phrases.append(text);hasStartedSpeech=false}
    func stop(reason:String) {stops.append(reason);hasStartedSpeech=false}
    func start() {hasStartedSpeech=true;onSpeechEvent?("started",[:])}
    func finish() {onSpeechEvent?("finished",[:]);hasStartedSpeech=false;onSpeechFinished?()}
}

@main struct RecoveryGuidanceTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let voice=GuidanceVoice(),speech=RecoverySpeech(audio:voice),settings=LocalClockSounds()
        speech.request(.recordingWarning,text:"Check N17",settings:settings);voice.start()
        speech.cancel(.recordingWarning,reason:"clocks resumed")
        speech.request(.clockResume,text:"Clocks resumed",settings:settings,priority:true)
        check(voice.stops.isEmpty && voice.phrases==["Check N17"],"Clock restart interrupted the important warning")
        voice.finish()
        check(voice.phrases.last=="Clocks resumed","Completed warning lost its state update")
        speech.cancel(.clockResume,reason:"paused again")
        check(voice.stops==["paused again"],"Unstarted obsolete resume was not removed")
        speech.request(.lighting,text:"Glare",settings:settings);voice.start()
        speech.request(.viewRecovered,text:"Clear",settings:settings)
        speech.request(.recordingWarning,text:"Check N18",settings:settings)
        speech.request(.recordingWarning,text:"Check N17",settings:settings)
        voice.finish()
        check(voice.phrases.last=="Check N17" && !voice.phrases.contains("Check N18"),"Latest warning did not precede queued all-clear")
        voice.start();speech.request(.recordingWarning,text:"Check P10",settings:settings)
        speech.request(.recordingWarning,text:"Check P10",settings:settings)
        voice.finish();check(voice.phrases.last=="Check P10","A changed issue on the active topic was dropped")
        voice.start();voice.finish();check(voice.phrases.last=="Clear","Queued acknowledgement was lost")
        voice.finish()
        speech.request(.alignment,text:"Camera",settings:settings);voice.start()
        var needed=true,latest="Old location"
        speech.request(.recordingWarning,text:latest,settings:settings,refresh:{needed ? latest:nil})
        latest="Current location";voice.finish()
        check(voice.phrases.last==latest,"Queued warning used outdated coordinates")
        voice.start();speech.request(.lighting,text:"Obsolete glare",settings:settings,refresh:{needed ? "Glare":nil})
        needed=false;voice.finish()
        check(!voice.phrases.contains("Obsolete glare") && voice.phrases.last==latest,"Resolved queued problem still spoke")
        speech.request(.recordingWarning,text:"Mute me",settings:settings);voice.start()
        speech.request(.clockResume,text:"Do not play",settings:settings);speech.stop(reason:"user muted speech");voice.finish()
        check(voice.stops.last=="user muted speech" && !voice.phrases.contains("Do not play"),"Explicit mute did not stop and clear speech")

        // A verified board recovery interrupts obsolete instructions and closes
        // only an audible episode. Repeated or unclear views cannot resolve it.
        let resolvedVoice=GuidanceVoice(),resolvedSpeech=RecoverySpeech(audio:resolvedVoice)
        let feedback=RecordingWarningFeedback(speech:resolvedSpeech)
        var stamp=10.0
        func observe(_ count:Int=6,agrees:Bool=true,resolved:Bool=true,enabled:Bool=true,running:Bool=true,session:String="one") {
            for _ in 0..<count {
                stamp += 0.21
                feedback.observe(session:session,agrees:agrees,resolved:resolved,fresh:true,now:stamp,
                    enabled:enabled,clocksEnabled:true,clockRunning:running,settings:settings)
            }
        }
        feedback.began(session:"one")
        resolvedSpeech.request(.recordingWarning,text:"Remove the problem",settings:settings)
        resolvedVoice.start()
        for _ in 0..<10 {feedback.observe(session:"one",agrees:true,resolved:true,fresh:true,now:stamp,
            enabled:true,clocksEnabled:true,clockRunning:true,settings:settings)}
        check(resolvedVoice.stops.isEmpty,"Duplicate frames stopped a genuine warning")
        observe(3);observe(1,agrees:false);observe(3)
        check(resolvedVoice.stops.isEmpty,"Unclear evidence did not reset recovery verification")
        observe(resolved:false)
        check(resolvedVoice.stops.isEmpty,"An unresolved issue announced recovery")
        observe()
        check(resolvedVoice.stops.last=="board position verified" && resolvedVoice.phrases.last=="Board position verified.","Audible obsolete warning was not stopped and acknowledged")
        let resolvedCount=resolvedVoice.phrases.count;observe()
        check(resolvedVoice.phrases.count==resolvedCount,"Repeated clear frames repeated the acknowledgment")
        resolvedVoice.start();resolvedVoice.finish()
        feedback.began(session:"one")
        resolvedSpeech.request(.recordingWarning,text:"Never heard",settings:settings)
        observe()
        check(resolvedVoice.phrases.last=="Never heard" && resolvedVoice.stops.last=="board position verified","Unheard warning produced an unnecessary all-clear")
        feedback.began(session:"one")
        resolvedSpeech.request(.recordingWarning,text:"Missing while paused",settings:settings);resolvedVoice.start()
        observe(running:false)
        check(resolvedVoice.phrases.last=="Board position verified. Clocks remain paused.","Recovery falsely implied clock resumption")
        resolvedVoice.start();resolvedVoice.finish()
        feedback.began(session:"one")
        resolvedSpeech.request(.recordingWarning,text:"Mute",settings:settings);resolvedVoice.start()
        resolvedSpeech.stop(reason:"muted");observe(enabled:false);observe()
        check(resolvedVoice.phrases.last=="Mute","Unmuting replayed an old recovery")
        feedback.began(session:"one")
        resolvedSpeech.request(.recordingWarning,text:"Old game",settings:settings);resolvedVoice.start()
        observe(session:"two")
        check(resolvedVoice.stops.last=="recording session changed" && resolvedVoice.phrases.last=="Old game","Old game's warning survived into a new session")
        feedback.began(session:"two")
        resolvedSpeech.request(.recordingWarning,text:"Queued recovery",settings:settings);resolvedVoice.start();resolvedVoice.finish()
        resolvedSpeech.request(.alignment,text:"Camera view",settings:settings);resolvedVoice.start()
        observe(session:"two");observe(1,agrees:false,session:"two");resolvedVoice.finish()
        check(resolvedVoice.phrases.last=="Camera view","A renewed disagreement allowed a queued all-clear")

        let root=FileManager.default.temporaryDirectory.appendingPathComponent("recovery-guidance-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        func make(_ text:String,after:[Occupancy])throws->GameRecorder {
            let url=root.appendingPathComponent(UUID().uuidString+".sgf")
            try text.write(to:url,atomically:true,encoding:.utf8)
            let game=SGFGame.from(tree:try SGFParser.parse(text:text))
            let player=SGFPlayer();player.load(game:game);player.seek(to:game.moves.count)
            var history=DeferredMoveHistory();history.size=game.boardSize;history.baseMove=game.moves.count
            history.anchorSignature=RecordingIdentity.signature(for:game)
            history.sections=[.init(reviewNumber:3,before:DeferredMoveHistory.states(player.board),after:after,reason:"Test",firstSeen:1,confirmedAt:1)]
            try JSONEncoder().encode(history).write(to:url.deletingPathExtension().appendingPathExtension("reviews.json"))
            let r=GameRecorder(storage:root);r.clock.audible=false;try r.restoreSavedGame(from:url);r.attachClock(.init())
            return r
        }
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/IncompleteCapture")
        let capture=try make(String(contentsOf:fixture.appendingPathComponent("before.sgf"),encoding:.utf8),
            after:JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:fixture.appendingPathComponent("observed.json"))))
        let captureWords=capture.spokenRecoveryInstruction(orientation:.init(3))
        check(captureWords.contains(BoardCoordinates.name(point:312,size:19,orientation:.init(3))) && captureWords.contains("Confirm capture") && !captureWords.contains("actual moves"),"Capture guidance omitted remaining point/action or requested move order")
        check(!captureWords.contains(BoardCoordinates.name(point:294,size:19,orientation:.init(3))),"Capture guidance requested removing an already removed stone")
        let base="(;GM[1]FF[4]AP[PhysicalGo:0.130]SZ[9]RU[Japanese];B[bb];W[gg])"
        var values=Array(repeating:Occupancy.empty,count:81);values[10] = .black;values[60] = .white
        var bumped=values;bumped[10] = .empty;bumped[11] = .black
        let bump=try make(base,after:bumped),bumpWords=bump.spokenRecoveryInstruction()
        check(bumpWords.contains("B8") && bumpWords.contains("C8") && bumpWords.contains("may have moved") && bumpWords.contains("only if it was bumped"),"Bump guidance lacked locations or claimed certainty")
        var missing=values;missing[10] = .empty
        let missingWords=try make(base,after:missing).spokenRecoveryInstruction()
        check(missingWords.contains("appear missing at B8") && missingWords.contains("if they were captured"),"Missing stone was treated as a move-order problem")
        var colors=values;colors[10] = .white
        check(try make(base,after:colors).spokenRecoveryInstruction().contains("Stone colors differ at B8"),"Color disagreement was not identified")
        var additions=values;additions[20] = .black;additions[30] = .black
        let added=try make(base,after:additions),addedWords=added.spokenRecoveryInstruction()
        check(addedWords.contains("New stones") && addedWords.contains("Open Review 3") && addedWords.contains("undo accidental additions"),"New stones lacked a specific review action")
        var mixed=missing;mixed[50] = .black
        check(try make(base,after:mixed).spokenRecoveryInstruction().contains("Placements and removals differ"),"Mixed changes were presented as a known bump")
        check(BoardCoordinates.name(point:244,size:19,orientation:.init(3))=="N17" && BoardCoordinates.name(point:245,size:19,orientation:.init(3))=="N18","Speech coordinates do not match the incident's displayed orientation")
        for turns in 0..<4 {
            check(Set((0..<81).map{BoardCoordinates.name(point:$0,size:9,orientation:.init(turns))}).count==81,"Rotated coordinate mapping is not one-to-one")
        }

        // Exercise the real model callbacks: starting clocks must not cancel
        // either the audible warning or the unresolved review that caused it.
        let modelVoice=GuidanceVoice()
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,
            referenceArchive:nil,recordingStorage:root,diagnosticRoot:root.appendingPathComponent("diagnostics"),recoveryAudio:modelVoice)
        model.moveEvidenceCapture.enabled=false;model.soundMode = .off
        try model.recorder.restoreSavedGame(from:added.autosaveURL!)
        model.recorder.attachClock(.init());model.recorder.clock.sounds.volume=0
        model.handleCameraStatus("Live",state:.live)
        model.recorder.onReviewNeeded?();modelVoice.start()
        let first=modelVoice.phrases.last
        model.recorder.clock.configure(.init(kind:.absolute,mainSeconds:100),blackToPlay:true)
        model.recorder.clock.ready(at:ProcessInfo.processInfo.systemUptime)
        check(model.recorder.clock.running && modelVoice.stops.isEmpty && modelVoice.phrases.last==first,"Model's clock subscription cut off a review warning")
        model.recoverySpeechEnabled=false
        check(modelVoice.stops.last=="recovery speech muted","Model mute failed to stop protected guidance")
        model.recorder.clock.pause()

        // Reproduce the live incident through actual recorder/model callbacks:
        // one saved stone disappears and returns without another accepted move.
        let liveVoice=GuidanceVoice()
        let liveModel=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,
            referenceArchive:nil,recordingStorage:root,diagnosticRoot:root.appendingPathComponent("live-diagnostics"),recoveryAudio:liveVoice)
        liveModel.moveEvidenceCapture.enabled=false;liveModel.soundMode = .off
        liveModel.handleCameraStatus("Live",state:.live)
        let live=liveModel.recorder
        live.clock.sounds.volume=0;live.clock.sounds.moveBeep=false
        var now=ProcessInfo.processInfo.systemUptime
        live.start(size:9,now:now,clockSettings:.init(kind:.fischer,mainSeconds:300,incrementSeconds:2,maximumSeconds:600))
        var actualBoard=Array(repeating:Occupancy.empty,count:81)
        func feedLive(_ values:[Occupancy],count:Int=8) {
            for _ in 0..<count {
                now += 0.21
                live.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:now,handObstructed:false),now:now)
            }
        }
        feedLive(actualBoard);actualBoard[40] = .black;feedLive(actualBoard)
        check(live.moveCount==1 && live.clock.running,"Live speech fixture did not start")
        let savedRecord=live.sgf()
        let pressEncoder=JSONEncoder();pressEncoder.outputFormatting=[.sortedKeys]
        let savedPresses=try pressEncoder.encode(live.clock.moves)
        var lifted=actualBoard;lifted[40] = .empty
        feedLive(lifted,count:22)
        check(liveVoice.phrases.last?.contains("disagree")==true && live.adjustmentIssues[40] != nil,"Missing stone did not produce the incident's warning")
        liveVoice.start();feedLive(actualBoard,count:12)
        check(liveVoice.stops.last=="board position verified" && liveVoice.phrases.last=="Board position verified.","Restoring a stone without a new move failed to stop and acknowledge speech")
        let unchangedPresses=try pressEncoder.encode(live.clock.moves)==savedPresses
        check(live.sgf()==savedRecord && unchangedPresses && live.clock.running && !live.clock.engine.blackToPlay,"Speech recovery changed history, presses or turn")
        liveVoice.start();liveVoice.finish()
        feedLive(lifted,count:22);liveVoice.start();live.pause()
        let pausedClock=live.clock.engine
        feedLive(actualBoard,count:12)
        check(liveVoice.phrases.last=="Board position verified. Clocks remain paused." && live.clock.engine==pausedClock && live.state == .paused,"Paused restoration lost its acknowledgment or resumed/changed clocks")
        liveVoice.finish()

        // Actual muted audio, including the event journal, must reach natural
        // completion after cancellation rather than merely passing a fake test.
        let audio=LocalClockAudio(),actual=RecoverySpeech(audio:audio)
        var events=[(String,[String:Any])](),muted=LocalClockSounds();muted.volume=0
        actual.onSpeechEvent={events.append(($0,$1))}
        actual.request(.recordingWarning,text:"Clocks paused. Please check the screen.",settings:muted)
        let startDeadline=Date().addingTimeInterval(5)
        while !audio.hasStartedSpeech && Date()<startDeadline {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
        check(audio.hasStartedSpeech,"Muted playback never started")
        actual.cancel(.recordingWarning,reason:"clocks resumed")
        let deadline=Date().addingTimeInterval(8)
        while !events.contains(where:{$0.0=="finished"}) && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
        check(events.contains{$0.0=="finished"} && !events.contains{$0.0=="interrupted"},"Actual warning was interrupted before completion")
        check(events.contains{$0.0=="finishing guidance" && $0.1["topic"] as? String=="recordingWarning"},"Protected playback decision was not journaled")
        // The same verified-resolution path must interrupt real audio, not
        // merely pass the fake-voice assertions above.
        actual.request(.recordingWarning,text:"Clocks paused. Please check the screen.",settings:muted)
        let interruptStart=Date().addingTimeInterval(5)
        while !audio.hasStartedSpeech && Date()<interruptStart {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
        check(audio.hasStartedSpeech,"Actual warning did not start for verified-resolution test")
        actual.resolved(.recordingWarning,reason:"board position verified",interruptAudible:true)
        check(!audio.hasStartedSpeech && events.contains{$0.0=="interrupted" && $0.1["reason"] as? String=="board position verified"},"Verified resolution did not interrupt real playback")
        check(KokoroSpeech.shared.cached("Board position verified.") != nil && KokoroSpeech.shared.cached("Board position verified. Clocks remain paused.") != nil,"Recovery acknowledgment is missing bundled Kokoro audio")
        print("PASS: \(checks) recovery guidance checks: specific actions, rotated coordinates, conditional bump/capture instructions, queue priority, updated/obsolete prompts, real model clock restart, explicit mute and natural audio completion")
    }
}
