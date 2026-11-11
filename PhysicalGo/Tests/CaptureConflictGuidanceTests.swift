import Foundation

@MainActor private final class CaptureGuidanceVoice:RecoverySpeechOutput {
    var hasStartedSpeech=false
    var onSpeechFinished:(()->Void)?
    var onSpeechEvent:SpeechEventHandler?
    var phrases=[String](),stops=[String]()
    var conflicts:[String] {phrases.filter{$0.contains("recorded board disagree")}}
    func say(_ text:String,settings:LocalClockSounds,announcement:Bool) {phrases.append(text);hasStartedSpeech=false}
    func stop(reason:String) {stops.append(reason);hasStartedSpeech=false}
    func start() {hasStartedSpeech=true;onSpeechEvent?("started",[:])}
    func finish() {hasStartedSpeech=false;onSpeechEvent?("finished",[:]);onSpeechFinished?()}
}

enum CaptureConflictGuidanceTests {
    @MainActor static func run() throws -> Int {
        var checks=0
        func check(_ ok:Bool,_ reason:String) {checks += 1;precondition(ok,reason)}
        // Frame-count, elapsed-time and continuity gates are independent of fps.
        var monitor=CaptureConflictMonitor()
        for i in 0..<20 {check(!monitor.update([1],now:Double(i)/10),"10 fps warned before two seconds")}
        check(monitor.update([1],now:2) && monitor.points==[1],"Persistent disagreement was not announced")
        check(!monitor.update([1],now:2) && !monitor.update([1],now:1),"Repeated/out-of-order callbacks repeated speech")
        check(!monitor.update([1],now:2.1),"Persistent issue repeated speech")
        monitor.interrupt();check(monitor.points.isEmpty,"Hand entry retained stale speech points")
        check(!monitor.update([1],now:3) && !monitor.update([1],now:4) && monitor.update([1],now:5),"Hand entry did not require a fresh warning interval")
        _=monitor.update([],now:5.1)
        check(monitor.points.isEmpty && !monitor.update([1],now:6),"Corrected/uncertain point retained old evidence")
        check(!monitor.update([1],now:8),"Camera gap counted as continuous disagreement")

        let root=FileManager.default.temporaryDirectory.appendingPathComponent("capture-speech-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/IncompleteCapture")
        let sgf=try String(contentsOf:fixture.appendingPathComponent("before.sgf"),encoding:.utf8)
        let partial=try JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:fixture.appendingPathComponent("observed.json")))
        let game=SGFGame.from(tree:try SGFParser.parse(text:sgf))
        let plan=AutomaticCapture.find(game:game,readings:partial,minimum:2)!
        let empty=plan.before.indices.first{plan.before[$0] == .empty && $0 != plan.point}!
        let stone=plan.before.indices.first{plan.before[$0].stone != nil && !plan.captured.contains($0)}!
        var now=ProcessInfo.processInfo.systemUptime
        func feed(_ r:GameRecorder,_ values:[Occupancy],count:Int=1) {
            for _ in 0..<count {
                now += 0.21
                r.consume(.init(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19,capturedAt:now,handObstructed:false),now:now)
                r.clock.tick(at:now)
            }
        }
        func make()throws->(ExperimentModel,CaptureGuidanceVoice) {
            let voice=CaptureGuidanceVoice()
            let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,
                referenceArchive:nil,recordingStorage:root,diagnosticRoot:root.appendingPathComponent("diagnostics"),recoveryAudio:voice)
            model.moveEvidenceCapture.enabled=false;model.soundMode = .off;model.recoverySpeechEnabled=true
            model.flipView();model.handleCameraStatus("Live",state:.live)
            let r=model.recorder;r.clock.audible=false
            let file=root.appendingPathComponent(UUID().uuidString+".sgf")
            try sgf.write(to:file,atomically:true,encoding:.utf8);try r.restoreSavedGame(from:file)
            r.attachClock(.init(kind:.absolute,mainSeconds:300));r.clock.sounds.volume=0
            r.resume();feed(r,plan.before,count:5);feed(r,partial,count:3)
            check(r.clock.automaticCapturePaused,"Speech fixture did not enter capture hold")
            r.clock.audible=true
            return (model,voice)
        }
        check(plan.conflictingPoints(partial).isEmpty && plan.conflictingPoints(plan.target).isEmpty,"Expected prisoner removals became conflicts")
        for kind in ["extra","missing","color","moved"] {
            let (model,voice)=try make(),r=model.recorder
            var bad=partial,points=Set<Int>()
            if kind=="extra" || kind=="moved" {bad[empty] = .black;points.insert(empty)}
            if kind=="missing" || kind=="moved" {bad[stone] = .empty;points.insert(stone)}
            if kind=="color" {bad[stone] = plan.before[stone] == .black ? .white:.black;points.insert(stone)}
            check(plan.conflictingPoints(bad)==points,"\(kind) reported the wrong conflict locations")
            feed(r,bad,count:3);feed(r,partial)
            var unknown=partial;unknown[empty] = .uncertain;unknown[stone] = .uncertain
            feed(r,unknown,count:11)
            check(voice.conflicts.isEmpty && r.automaticCaptureConflictPoints.isEmpty,"Transient or uncertain reading spoke a conflict")
            feed(r,bad,count:10)
            check(voice.conflicts.isEmpty,"\(kind) warned before two seconds of fresh evidence")
            feed(r,bad)
            check(voice.conflicts.count==1 && Set(r.automaticCaptureConflictPoints)==points,"\(kind) did not produce one specific spoken warning")
            let words=voice.conflicts[0]
            check(words.contains("Clocks remain paused") && words.contains("before correcting anything") && !words.contains("Finish removing"),"\(kind) gave the wrong instruction")
            for turns in 0..<4 {
                let rotated=r.spokenRecoveryInstruction(orientation:.init(turns))
                check(points.allSatisfy{rotated.contains(BoardCoordinates.name(point:$0,size:19,orientation:.init(turns)))},"Capture speech used unrotated coordinates")
            }
            check(points.allSatisfy{words.contains(BoardCoordinates.name(point:$0,size:19,orientation:model.orientation))},"Model speech did not use displayed coordinates")
            check(LocalPlayStatus(recorder:r).title=="Check board before resuming","Screen still requested prisoner removal for a conflicting stone")
            let stopped=r.clock.engine,stops=voice.stops.count;voice.start()
            feed(r,bad,count:30)
            check(voice.conflicts.count==1,"\(kind) warning repeated during the same persistent issue")
            check(r.clock.engine.black==stopped.black && r.clock.engine.white==stopped.white && r.moveCount==45,"\(kind) changed clocks or saved a conflicting capture")
            feed(r,partial)
            check(r.automaticCaptureConflictPoints.isEmpty && voice.stops.count==stops,"Correction cut off an audible instruction")
            feed(r,plan.target,count:5)
            check(r.clock.running && r.moveCount==46 && voice.phrases.last==words,"Completion interrupted the warning or failed to restart")
            voice.finish()
            check(voice.phrases.last=="Capture complete. Clocks resumed. White to play.","Completion acknowledgement was lost after the warning finished")
            r.pause()
        }
        // A queued warning must disappear if the hand returns or the issue
        // clears, but be eligible again if fresh evidence confirms it later.
        let (model,voice)=try make(),r=model.recorder
        feed(r,partial,count:30)
        check(voice.phrases.count==1 && voice.conflicts.isEmpty,"Fixture did not request the ordinary removal instruction")
        voice.start()
        var bad=partial;bad[empty] = .white
        feed(r,bad,count:11)
        check(voice.conflicts.isEmpty,"Capture warning interrupted a sentence already playing")
        now += 0.21;r.noteHandObstruction(now:now);voice.finish()
        check(voice.conflicts.isEmpty && r.automaticCaptureConflictPoints.isEmpty,"Hand entry left a stale conflict queued")
        feed(r,bad,count:11)
        check(voice.conflicts.count==1,"Unheard cancelled warning could not be requested again")
        voice.start();model.recoverySpeechEnabled=false
        check(voice.stops.last=="recovery speech muted","Explicit mute did not stop capture guidance")
        r.pause();check(r.automaticCaptureConflictPoints.isEmpty,"Manual pause retained stale conflict guidance")
        print("PASS: \(checks) capture conflict guidance checks")
        return checks
    }
}
