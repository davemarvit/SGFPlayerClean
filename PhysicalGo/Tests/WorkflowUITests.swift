import AppKit
import SwiftUI

@main struct WorkflowUITests {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        try runCameraContinuityTests()
        try runCoveredBorderTests()
        runPauseAnnouncementTests()
        runAlignmentGateTests()
        try runHandicapTests()
        try runHandicapVerificationTests()
        try runCrowdedRestartTests()
        try runSimpleReviewTests()
        try runBoardCheckGuidanceTests()
        _ = ObstructionEvidenceTests.run()
        _ = try ObservationHistoryTests.run()
        _ = try LocalMoveEvidenceTests.run()
        try runAutomaticPauseTests()
        try runPeriodCorrectionTests()
        try runLocalClockTests()
        runByoyomiAnnouncementTests()
        try runFeedbackLifecycleTests()
        try runSetupStartTests()
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;precondition(condition,message)}
        var workspace=PlayWorkspace()
        check(workspace.activity == .setup,"New sessions must begin in Setup")
        workspace.gameBecameAvailable()
        check(workspace.activity == .play,"Starting switches to the stable play panel")
        workspace.changedMode()
        check(workspace.activity == .setup,"Mode switch resets presentation")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("workflow-ui-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let suite="PhysicalGo.WorkflowUITests."+UUID().uuidString
        let settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:root.appendingPathComponent("games"),settings:settings,diagnosticRoot:root.appendingPathComponent("diagnostics"))
        model.showDiagnostics=false
        model.recorder.clock.audible=false
        let output=try TestArtifacts.directory("physical-move-recovery")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:880),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua)
        window.backgroundColor = .windowBackgroundColor
        let host=NSHostingView(rootView:ExperimentView(model:model))
        window.contentView=host;window.orderFront(nil)
        func settle() {RunLoop.main.run(until:Date().addingTimeInterval(0.3));host.layoutSubtreeIfNeeded()}
        func snapshot(_ name:String) throws {
            settle()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            check(bitmap.pixelsWide>=1060 && bitmap.pixelsHigh>=740,"Native render has invalid dimensions")
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        try snapshot("setup")
        model.recorder.start(size:19,info:SGFGame.Info(playerBlack:"Black player",playerWhite:"White player"),clockSettings:.init(),startPaused:true)
        try snapshot("play-paused")
        let initialStatus=LocalPlayStatus(recorder:model.recorder)
        check(initialStatus.title=="Ready to start" && initialStatus.nextStep.contains("Start"),"First-start status is misleading")
        let sgf=model.recorder.sgf(),state=model.recorder.state
        model.showDiagnostics=true
        try snapshot("diagnostic-controls")
        check(!model.diagnostics.isCapturing,"Showing diagnostics started capture")
        check(model.recorder.sgf()==sgf && model.recorder.state==state,"Showing diagnostics changed game")
        model.startDiagnostics();settle()
        check(model.diagnostics.isCapturing,"Test capture did not start")
        model.showDiagnostics=false;settle()
        check(model.diagnostics.isCapturing,"Collapsing diagnostics stopped collection")
        model.diagnostics.stop()
        model.moveEvidenceCapture.enabled=true;settle()
        model.moveEvidenceCapture.enabled=false
        check(model.recorder.sgf()==sgf && model.recorder.state==state,"Diagnostic choices affected recording")
        let originalBlack=model.recorder.clock.engine.black,originalWhite=model.recorder.clock.engine.white
        var finalPeriod=originalBlack;finalPeriod.remaining=10;finalPeriod.overtime=true;finalPeriod.periods=3
        check(model.recorder.confirmClockReview(black:finalPeriod,white:originalWhite,resume:false),"Could not render final-ten overtime")
        try snapshot("final-ten-seconds")
        finalPeriod.remaining=30;finalPeriod.periods=2
        check(model.recorder.confirmClockReview(black:finalPeriod,white:originalWhite,resume:false),"Could not render fresh overtime period")
        try snapshot("fresh-byoyomi-period")
        check(model.recorder.confirmClockReview(black:originalBlack,white:originalWhite,resume:false),"Could not restore fixture clock")
        model.recorder.clock.recover(toBlack:true,reason:"Several moves need a timing review.",at:ProcessInfo.processInfo.systemUptime)
        try snapshot("clock-review")
        check(model.recorder.clock.requiresReview && model.recorder.state == .paused,"Clock review state not retained")
        let beforeReview=model.recorder.sgf()
        check(model.recorder.confirmClockReview(black:model.recorder.clock.engine.black,white:model.recorder.clock.engine.white,resume:false),"Clock review rejected agreed times")
        check(model.recorder.state == .paused && model.recorder.sgf()==beforeReview,"Review resumed or changed the game")
        model.recorder.clock.pauseOnInterruption=false
        model.recorder.clock.resume(at:ProcessInfo.processInfo.systemUptime)
        check(model.recorder.clock.running && model.recorder.state == .paused,"Could not exercise recording paused with clock running")
        try snapshot("recording-paused-clock-running")
        model.recorder.clock.pause("Test clock stopped")
        model.recorder.clock.pauseOnInterruption=true
        window.appearance=NSAppearance(named:.aqua)
        try snapshot("play-light")
        window.appearance=NSAppearance(named:.darkAqua)
        model.interfaceScale=1.5
        window.setContentSize(NSSize(width:1060,height:740))
        try snapshot("play-large-text-minimum-window")
        model.interfaceScale=1.1
        model.playMode = .online
        try snapshot("online-setup")
        check(model.recorder.sgf()==sgf && model.recorder.state == .paused,"Mode switch lost local game")
        model.playMode = .local
        let persistent=ExperimentModel(discoverCameras:false,automaticGridDetection:false,referenceArchive:nil,recordingStorage:nil,settings:settings,diagnosticRoot:root)
        persistent.moveEvidenceCapture.enabled=false
        persistent.diagnostics.limitGB=10
        persistent.showDiagnostics=true
        let restored=ExperimentModel(discoverCameras:false,automaticGridDetection:false,referenceArchive:nil,recordingStorage:nil,settings:settings,diagnosticRoot:root)
        check(!restored.moveEvidenceCapture.enabled && restored.diagnostics.limitGB==10 && restored.showDiagnostics,"Diagnostic choices did not survive relaunch")
        check(!restored.diagnostics.isCapturing,"Relaunch silently started continuous recording")
        model.diagnostics.closeForExit();model.moveEvidenceCapture.closeForExit()
        print("PASS: \(checks) workflow, native render, collection independence and game preservation checks; ten native snapshots")
    }
}


@MainActor private func runSetupStartTests() throws {
    var checks=0
    func check(_ ok:Bool,_ message:String) {checks += 1;precondition(ok,message)}
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("setup-start-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let recorder=GameRecorder(storage:root);recorder.clock.audible=false
    let empty=BoardObservation(readings:(0..<81).map {.init(row:$0/9,col:$0%9,occupancy:.empty,confidence:1,delta:0)},size:9)
    var time=ProcessInfo.processInfo.systemUptime,started=0
    recorder.onGameStarted={started += 1}
    recorder.start(size:9,clockSettings:.init(),startPaused:true)
    for _ in 0..<20 {time += 0.21;recorder.consume(empty,now:time)}
    check(recorder.awaitingFirstStart && recorder.state == .paused && !recorder.clock.running && recorder.moveCount==0 && started==0,"Saving setup started play or clocks")
    check(!recorder.canPass && !recorder.canEdit && !recorder.canScorePosition,"Ready setup allowed game actions before Start")
    let cancelled=GameRecorder(storage:nil);cancelled.clock.audible=false
    cancelled.start(size:9,startPaused:true);cancelled.finish()
    check(cancelled.state == .finished && !cancelled.awaitingFirstStart,"Ending unused setup left a stale Start state")
    let savedBlack=recorder.clock.engine.black
    let restored=GameRecorder(storage:nil);restored.clock.audible=false
    try restored.restoreSavedGame(from:recorder.autosaveURL!)
    check(restored.awaitingFirstStart && restored.state == .paused && !restored.clock.running,"Ready setup failed to survive restart")
    recorder.resume()
    for _ in 0..<7 {time += 0.21;recorder.consume(empty,now:time)}
    check(!recorder.awaitingFirstStart && recorder.state == .recording && recorder.clock.running && started==1,"Start did not arm verified play exactly once")
    check(recorder.clock.engine.black.remaining==savedBlack.remaining,"Setup time was charged to a player")
    recorder.pause();recorder.clock.requestResume();recorder.resume()
    for _ in 0..<7 {time += 0.21;recorder.consume(empty,now:time)}
    check(started==1,"Resume repeated the game-start sound")
    recorder.pause()
    let handicap=GameRecorder(storage:nil);handicap.clock.audible=false
    handicap.start(size:9,handicap:2,clockSettings:.init(),startPaused:true)
    check(handicap.awaitingFirstStart && !handicap.clock.running,"Handicap setup started clocks")
    handicap.resume()
    let initial=handicap.positions[0]
    let stones=BoardObservation(readings:(0..<81).map {.init(row:$0/9,col:$0%9,occupancy:initial.grid[$0/9][$0%9] == .black ? .black:.empty,confidence:1,delta:0)},size:9)
    for _ in 0..<8 {time += 0.21;handicap.consume(stones,now:time)}
    check(handicap.state == .recording && handicap.clock.running && !handicap.clock.engine.blackToPlay,"Handicap start did not verify stones and start White")
    handicap.pause()
    for (state,title) in [(AlignmentCheck.checking,"Checking alignment…"),(.passed,"Alignment passed"),(.failed,"Alignment check did not pass")] {
        let text=SetupCameraMessage(alignment:false,needsFullBoard:false,exhausted:false,lighting:false,ready:true,detecting:state == .checking,check:state)
        check(text.title==title,"Alignment feedback is not explicit")
        if state != .checking {check(text.buttonTitle=="Check alignment again","Completed alignment check did not offer a retry")}
    }
    if let folder=ProcessInfo.processInfo.environment["PHYSICAL_GO_WORKFLOW_REVIEW"] {
        let source=URL(fileURLWithPath:folder),files=try FileManager.default.contentsOfDirectory(at:source,includingPropertiesForKeys:nil)
        let game=files.first{$0.pathExtension=="sgf"}!,copy=root.appendingPathComponent("review.sgf")
        for ext in ["sgf","reviews.json","pending.json","clock.json"] {
            try FileManager.default.copyItem(at:game.deletingPathExtension().appendingPathExtension(ext),to:copy.deletingPathExtension().appendingPathExtension(ext))
        }
        let review=GameRecorder(storage:nil);review.clock.audible=false;try review.restoreSavedGame(from:copy)
        let section=review.reviewHistory.sections.last!,before=review.game.moves.count,black=review.clock.engine.black,white=review.clock.engine.white
        let order=try ReviewOrderRecovery.load(url:game.deletingPathExtension().appendingPathExtension("observations.jsonl"),before:section.before,after:section.after,first:.white,through:section.recordedAt)
        check(order.orders.isEmpty && order.turnConflict?.point==74 && order.turnConflict?.color == .black,"Actual out-of-turn conflict was not identified")
        check(review.withdrawAccidentalMoves(section.id,removedByPlayer:false) != nil && review.hasDeferredMoves,"Withdrawal did not require physical removal confirmation")
        let removalTime=ProcessInfo.processInfo.systemUptime-1.1
        let removal=BoardObservation(readings:section.before.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19)
        for i in 0..<6 {review.consume(removal,now:removalTime+Double(i)*0.21)}
        let result=review.withdrawAccidentalMoves(section.id,removedByPlayer:true)
        check(result==nil && !review.hasDeferredMoves && review.moveCount==before && review.nextPlayer == .white,"Withdrawal invented moves or failed to restore White: \(result ?? "")")
        check(review.clock.engine.black==black && review.clock.engine.white==white,"Withdrawal changed clock totals")
        check(review.reviewHistory.sections.last?.after==section.after && review.reviewHistory.sections.last?.recoverySource?.contains("out-of-turn")==true,"Withdrawal lost the original photograph interpretation or reason")
        check(review.state == .paused,"Withdrawal automatically resumed play")
    }
    print("PASS: \(checks) setup/start, restart, initial sound, handicap, alignment feedback and actual out-of-turn recovery checks")
}


@MainActor private final class FakeRecoveryVoice:RecoverySpeechOutput {
    var hasStartedSpeech=false
    var onSpeechFinished:(()->Void)?
    var onSpeechEvent:SpeechEventHandler?
    var phrases=[String](),stops=[String]()
    func say(_ text:String,settings:LocalClockSounds,announcement:Bool) {phrases.append(text);hasStartedSpeech=false}
    func stop(reason:String) {stops.append(reason);hasStartedSpeech=false}
    func finish() {hasStartedSpeech=false;onSpeechFinished?()}
}

@MainActor private func runFeedbackLifecycleTests() throws {
    var checks=0
    func check(_ ok:Bool,_ message:String) {checks += 1;precondition(ok,message)}
    let fake=FakeRecoveryVoice(),guidance=RecoverySpeech(audio:fake),settings=LocalClockSounds()
    guidance.request(.lighting,text:"Lighting",settings:settings)
    guidance.resolved(.lighting)
    check(fake.stops.count==1,"A recovered condition left an unsaid warning queued")
    guidance.request(.lighting,text:"Lighting again",settings:settings);fake.hasStartedSpeech=true
    guidance.request(.alignment,text:"Camera",settings:settings)
    guidance.request(.alignment,text:"Camera",settings:settings)
    check(fake.phrases.count==2,"Camera and lighting guidance overlapped")
    guidance.resolved(.lighting)
    check(fake.stops.count==1,"Recovery cut off an audible phrase")
    fake.finish()
    check(fake.phrases==["Lighting","Lighting again","Camera"],"Queued guidance was lost or duplicated")
    guidance.resolved(.alignment)
    check(fake.stops.count==2,"Unstarted queued guidance survived recovery")
    guidance.request(.lighting,text:"Active",settings:settings);fake.hasStartedSpeech=true
    guidance.request(.alignment,text:"Obsolete",settings:settings);guidance.resolved(.alignment);fake.finish()
    check(!fake.phrases.contains("Obsolete"),"An obsolete camera warning played after lighting recovered")
    guidance.request(.lighting,text:"Mute",settings:settings);fake.hasStartedSpeech=true
    guidance.request(.alignment,text:"Do not play",settings:settings);guidance.stop(reason:"muted");fake.finish()
    check(fake.stops.last=="muted" && !fake.phrases.contains("Do not play"),"Mute failed to stop and clear guidance")
    guidance.request(.alignment,text:"Stream interruption",settings:settings);fake.hasStartedSpeech=true
    let count=fake.stops.count;guidance.finishCurrent(reason:"camera stream interrupted")
    check(fake.stops.count==count,"A camera stream hiccup cut an audible phrase")
    fake.finish()
    // Real muted Kokoro playback must reach its end after recovery. The test
    // never speaks over the user's active game.
    let audio=LocalClockAudio(),actual=RecoverySpeech(audio:audio)
    var events=[(String,[String:Any])](),muted=LocalClockSounds();muted.volume=0
    actual.onSpeechEvent={events.append(($0,$1))}
    let phrase="Please pause play. Improve the lighting on the whole board and reduce glare. Keep the stones in place while I check the view."
    actual.request(.lighting,text:phrase,settings:muted)
    check(audio.hasStartedSpeech,"Bundled guidance failed to start")
    actual.resolved(.lighting)
    let deadline=Date().addingTimeInterval(10)
    while !events.contains(where:{$0.0=="finished"}) && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
    check(events.contains(where:{$0.0=="finished"}) && !events.contains(where:{$0.0=="interrupted"}),"Recovered guidance did not play to natural completion")
    let start=events.first{$0.0=="started"}!.1,end=events.first{$0.0=="finished"}!.1
    check((end["playedSeconds"] as? Double ?? 0)>=(start["durationSeconds"] as? Double ?? 20)-0.2,"Natural completion was logged before the clip finished")
    check(start["utteranceID"] as? String==end["utteranceID"] as? String && start["topic"] as? String=="lighting","Speech audit lost request identity or source")
    actual.request(.alignment,text:phrase,settings:muted);actual.stop(reason:"user muted speech")
    check(events.last?.0=="interrupted" && events.last?.1["reason"] as? String=="user muted speech","Explicit stop lacks a diagnostic reason")
    let recorder=GameRecorder(storage:nil);recorder.clock.audible=false
    recorder.start(size:9,clockSettings:.init());recorder.pause()
    var closed=0
    let host=NSHostingView(rootView:SavedReviewNotice(recorder:recorder,onClose:{closed += 1}))
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:300),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=host;window.orderFront(nil)
    func settle() {RunLoop.main.run(until:Date().addingTimeInterval(0.15))}
    settle();check(closed==0,"Paused completion notice dismissed itself")
    recorder.resume();settle();check(closed==1,"Main-screen recording resume did not dismiss completion notice")
    recorder.pause();settle();recorder.clock.resume();settle()
    check(closed==2,"Clock-only resume did not dismiss stale completion notice")
    recorder.clock.pause();settle();recorder.finish();settle()
    check(closed==3,"Ending the game left a stale completion notice")
    window.orderOut(nil)
    print("PASS: \(checks) saved-review dismissal and speech lifecycle checks, including full-length muted Kokoro playback")
}


@MainActor private func runByoyomiAnnouncementTests() {
    var checks=0
    func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
    var policy=ByoyomiAnnouncements()
    var engine=LocalClockEngine(settings:.init(kind:.byoyomi,mainSeconds:1,periodSeconds:15,periods:5))
    engine.resume(at:0)
    check(policy.observe(engine)==nil,"Main time announced overtime")
    engine.advance(to:1)
    check(policy.observe(engine)=="Entering byoyomi. 5 periods left","Missing entry announcement")
    check(policy.observe(engine)==nil,"Repeated entry on next observation")
    engine.move(black:true,at:2)
    check(policy.observe(engine)==nil,"White announced Black's overtime")
    engine.advance(to:3)
    check(policy.observe(engine)=="Entering byoyomi. 5 periods left","White's independent entry was lost")
    engine.move(black:false,at:4)
    check(policy.observe(engine)==nil,"Unchanged periods announced at Black's next turn")
    engine.advance(to:19)
    check(policy.observe(engine)=="4 periods left","Losing one period did not announce four remaining")
    check(policy.observe(engine)==nil,"Period loss repeated on next frame")
    engine.move(black:true,at:20)
    check(policy.observe(engine)==nil,"Black's period loss triggered a White announcement")
    engine.move(black:false,at:21)
    check(policy.observe(engine)==nil,"Four periods repeated at the next turn")
    engine.pause(at:22);engine.resume(at:23)
    check(policy.observe(engine)==nil,"Pause/resume repeated the period count")
    engine.advance(to:67)
    check(policy.observe(engine)=="1 period left","Skipped timer callbacks did not report the current period count")
    policy.reset(to:engine)
    check(policy.observe(engine)==nil,"Restored clocks announced existing overtime again")
    engine.black.periods=3;policy.reset(to:engine)
    check(policy.observe(engine)==nil,"Manual clock correction spoke as a new entry")
    engine.black.periods=2
    check(policy.observe(engine)=="2 periods left","A later loss after correction was suppressed")
    policy.reset()
    engine=LocalClockEngine(settings:.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:5))
    check(policy.observe(engine)=="Entering byoyomi. 5 periods left","Zero-main-time game did not announce initial overtime")
    check(policy.observe(engine)==nil,"Zero-main-time entry repeated")
    // Exercise the actual speech wiring, silently, including suppression of a
    // countdown while the entry sentence is playing.
    let audio=LocalClockAudio()
    var settings=LocalClockSounds();settings.volume=0;settings.moveBeep=false
    var requests=[String]()
    audio.onSpeechEvent={event,details in if event=="requested",let text=details["phrase"] as? String {requests.append(text)}}
    engine.resume(at:0)
    audio.beganTurn(engine,settings:settings);audio.beganTurn(engine,settings:settings)
    check(requests==["Entering byoyomi. 5 periods left"],"Turn-start wiring repeated entry")
    let before=engine;engine.advance(to:6)
    audio.update(previous:before,current:engine,settings:settings)
    check(requests.count==1,"Countdown interrupted entry announcement")
    audio.moved(engine,settings:settings)
    check(requests.count==1,"Move feedback announced unchanged periods")
    let prior=engine;engine.advance(to:15)
    audio.update(previous:prior,current:engine,settings:settings)
    check(requests.last=="4 periods left" && requests.count==2,"Live timer wiring did not announce a lost period once")
    audio.stop(reason:"test complete")
    for count in 1...10 {
        let phrase="Entering byoyomi. \(count) \(count==1 ? "period":"periods") left"
        check(KokoroSpeech.shared.cached(phrase) != nil,"New overtime prompt is not bundled: \(phrase)")
    }
    print("PASS: \(checks) byoyomi transition, per-player, resume, restoration and bundled speech checks")
}

@MainActor private func runCrowdedRestartTests() throws {
    var checks=0
    func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
    func wait(_ ready:()->Bool) {
        let end=Date().addingTimeInterval(20)
        while !ready() && Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.03))}
        check(ready(),"Crowded restart did not settle")
    }
    let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CrowdedRestart")
    struct Metadata:Decodable {let calibration:BoardCalibration}
    let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:fixture.appendingPathComponent("sample.json")))
    let expected=try JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:fixture.appendingPathComponent("expected.json")))
    let source=CGImageSourceCreateWithURL(fixture.appendingPathComponent("frame.png") as CFURL,nil)!
    let image=CGImageSourceCreateImageAtIndex(source,0,nil)!,frame=GrayFrame(image:image,includeColor:false)!
    let start=ProcessInfo.processInfo.systemUptime
    let found=try AutoGridDetector.recover(image:image,size:19,previous:meta.calibration,expected:expected)
    let elapsed=ProcessInfo.processInfo.systemUptime-start
    check(found.result != nil && found.usedStones,"Existing crowded grid was not recovered with stones")
    let corrected=found.result!.calibration
    check(corrected != meta.calibration,"Small camera scale change was not refined")
    for (point,pixel) in zip(corrected.corners,[(569.0,132.0),(1454,141),(1471,980),(542,975)]) {
        check(hypot(point.x*1919-pixel.0,point.y*1079-pixel.1)<3,"Refined grid missed a visible outer intersection")
    }
    check(elapsed<1,"Known-grid verification took over a second")
    print("Crowded restart: existing grid verified in \(String(format:"%.1f",elapsed*1000)) ms")
    for (dx,dy) in [(1.0,0.0),(-1,0),(0,1),(0,-1),(0.5,0.5)] {
        let corners=[(0.0,0.0),(18,0),(18,18),(0,18)].map {meta.calibration.point(col:$0.0+dx,row:$0.1+dy)}
        let wrong=BoardCalibration(size:19,corners:corners)!
        let landmarks=AutoGridDetector.landmarkEvidence(frame:frame,size:19,expected:expected) {wrong.point(col:$0,row:$1)}
        check(landmarks.fraction<0.8 || AutoGridDetector.knownGridSupport(frame:frame,calibration:wrong,expected:expected)==nil,"Wrong intersection offset passed known-grid verification")
    }
    for turns in 1...3 {
        let corners=Array(meta.calibration.corners[turns...])+Array(meta.calibration.corners[..<turns])
        let wrong=BoardCalibration(size:19,corners:corners)!
        let landmarks=AutoGridDetector.landmarkEvidence(frame:frame,size:19,expected:expected) {wrong.point(col:$0,row:$1)}
        check(landmarks.fraction<0.8,"Rotated known stones passed verification")
    }
    let blank=GrayFrame(image:CGImage(width:image.width,height:image.height,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:image.width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:Data(repeating:160,count:image.width*image.height) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!,includeColor:false)!
    check(AutoGridDetector.knownGridSupport(frame:blank,calibration:meta.calibration,expected:expected)==nil,"Blank frame passed grid verification")
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("crowded-restart-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    for ext in ["sgf","clock.json","pending.json","reviews.json"] {
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("game."+ext),to:root.appendingPathComponent("game."+ext))
    }
    let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:root)
    model.recoverySpeechEnabled=false;model.recorder.clock.audible=false;model.moveEvidenceCapture.enabled=false
    try model.openSample(from:fixture)
    wait {model.alignmentNeedsRecovery || model.observation != nil}
    try model.recorder.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
    let game=model.recorder.sgf(),clock=model.recorder.clock.engine
    model.detectGrid()
    wait {!model.detectingGrid && !model.alignmentNeedsRecovery && model.observation != nil}
    check(model.recorder.sgf()==game && model.recorder.clock.engine==clock,"Recovery changed saved moves or clock values")
    check(model.recorder.state == .paused,"Recovery resumed a manually paused game")
    model.running=true;model.cameraState = .live;model.frozen=false
    for _ in 0..<6 {
        model.receive(image,capturedAt:ProcessInfo.processInfo.systemUptime)
        RunLoop.main.run(until:Date().addingTimeInterval(0.2))
    }
    check(!model.alignmentNeedsRecovery && model.observation != nil,"Recovered grid immediately failed tracking again")
    check(model.observation!.signature.filter{$0 == .uncertain}.isEmpty,"Refined crowded grid left uncertain intersections")
    model.recorder.resume();model.recorder.clock.requestResume()
    model.recorder.suspendVision("Grid alignment lost",preserveOrder:true)
    let held=LocalPlayPresentation(recorder:model.recorder,clock:model.recorder.clock)
    check(held.automaticHold && held.title=="Waiting for board · clocks stopped","Automatic hold still presents Playing")
    model.recorder.pause()
    let paused=LocalPlayPresentation(recorder:model.recorder,clock:model.recorder.clock)
    check(!paused.automaticHold && paused.title=="Game paused","Keep paused failed to leave automatic-resume state")
    model.recorder.clock.resume()
    let running=LocalPlayPresentation(recorder:model.recorder,clock:model.recorder.clock)
    check(!running.automaticHold,"Running clock presented as stopped")
    model.recorder.clock.pause()
    model.recorder.resume();model.recorder.clock.requestResume()
    let now=ProcessInfo.processInfo.systemUptime,observation=model.observation!
    for step in 0..<15 {model.recorder.consume(observation,now:now+Double(step)*0.21)}
    check(model.recorder.moveCount==109 && !model.recorder.hasDeferredMoves,"The two missed moves did not recover as a unique legal sequence")
    check(model.recorder.clock.running,"Clock did not resume after the board and missed moves were verified")
    model.recorder.pause()
    print("PASS: \(checks) crowded restart, wrong-offset/rotation rejection, saved game preservation and clock-hold presentation checks")
}

@MainActor private func runPeriodCorrectionTests() throws {
    var checks=0
    func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
    for black in [true,false] {for live in [false,true] {for announcements in [true,false] {
        let clock=LocalGameClock(),base=ProcessInfo.processInfo.systemUptime,id=UUID()
        var settings=LocalClockSounds();settings.volume=0;settings.moveBeep=false;settings.announcePeriods=announcements
        clock.sounds=settings
        var events=[(String,[String:Any])]()
        clock.onSpeechEvent={events.append(($0,$1))}
        clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:3),blackToPlay:black)
        clock.ready(at:base);clock.tick(at:base+15.2)
        check((black ? clock.engine.black:clock.engine.white).periods==2,"Test did not display two periods")
        if announcements {check(events.contains{$0.0=="started" && $0.1["phrase"] as? String=="2 periods left"},"Lower period count did not start playback")}
        if live {clock.recordLiveMove(id:id,black:black,at:base+15.5,observedAt:base+14.5)}
        else {clock.recordMove(number:1,black:black,at:base+15.5,observedAt:base+14.5)}
        check((black ? clock.engine.black:clock.engine.white).periods==3,"Recognition failed to restore the period")
        let corrections=events.filter{$0.0=="requested" && $0.1["phrase"] as? String=="Corrected: \(black ? "Black":"White"), 3 periods left"}
        check(corrections.count==(announcements ? 1:0),"Correction missing, duplicated, or ignored the announcement preference")
        if announcements {
            check(corrections[0].1["player"] as? String==(black ? "Black":"White"),"Correction attributed to the next player")
            check(corrections[0].1["correction"] as? Bool == true,"Correction is not identifiable in the speech journal")
            clock.tick(at:base+16.5)
            check(events.last{$0.0=="requested"}?.1["phrase"] as? String=="Corrected: \(black ? "Black":"White"), 3 periods left","Opponent entry interrupted correction")
        }
        if live {clock.recordLiveMove(id:id,black:black,at:base+16.5,observedAt:base+14.5)}
        else {clock.recordMove(number:1,black:black,at:base+16.5,observedAt:base+14.5)}
        check(events.filter{$0.0=="requested" && $0.1["correction"] as? Bool == true}.count==(announcements ? 1:0),"Duplicate move repeated a correction")
        if black && !live && announcements {
            let deadline=Date().addingTimeInterval(5)
            while !events.contains(where:{$0.0=="finished" && $0.1["correction"] as? Bool == true}) && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.03))}
            check(events.contains{$0.0=="finished" && $0.1["correction"] as? Bool == true},"Correction failed to finish")
            clock.tick(at:base+17.5)
            check(events.last{$0.0=="requested"}?.1["phrase"] as? String=="Entering byoyomi. 3 periods left","Opponent overtime entry was lost after correction")
        }
        clock.pause()
    }}}
    // A lower count that was never spoken needs no spoken correction.
    let clock=LocalGameClock(),base=ProcessInfo.processInfo.systemUptime
    var settings=LocalClockSounds();settings.volume=0;settings.moveBeep=false;clock.sounds=settings
    var phrases=[String]()
    clock.onSpeechEvent={event,details in if event=="requested",let phrase=details["phrase"] as? String {phrases.append(phrase)}}
    clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:3),blackToPlay:true)
    clock.ready(at:base);clock.audible=false;clock.tick(at:base+15.2);clock.audible=true
    clock.recordMove(number:1,black:true,at:base+15.5,observedAt:base+14.5)
    check(!phrases.contains{$0.hasPrefix("Corrected:")},"Unspoken lower count generated a correction")
    clock.pause()
    // Ordinary timely moves never manufacture a correction.
    phrases=[];clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:3),blackToPlay:true)
    clock.ready(at:base);clock.recordMove(number:1,black:true,at:base+1,observedAt:base+0.5)
    check(!phrases.contains{$0.hasPrefix("Corrected:")},"Timely move generated a correction")
    clock.pause()
    for player in ["Black","White"] {for count in 1...10 {check(KokoroSpeech.shared.cached("Corrected: \(player), \(count) \(count==1 ? "period":"periods") left") != nil,"Correction phrase is not bundled")}}
    print("PASS: \(checks) spoken period correction checks: both players, confirmed and deferred history, mute, duplicates, opponent entry, natural completion and cached prompts")
}

@MainActor private func runAutomaticPauseTests() throws {
    var checks=0
    func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("pause-tests-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    let clock=LocalGameClock(),base=ProcessInfo.processInfo.systemUptime
    clock.audible=false
    var events=[LocalGameClock.AutomaticPause](),cleared=0
    clock.onAutomaticPause={events.append($0)};clock.onAutomaticPauseCleared={cleared += 1}
    clock.configure(.init(kind:.absolute,mainSeconds:300),blackToPlay:true)
    clock.interrupt("Finding the grid",at:base)
    check(clock.automaticPause==nil && events.isEmpty,"Startup was announced as an automatic stop")
    clock.ready(at:base)
    clock.interrupt("Grid alignment lost. The recorded game is preserved.",at:base+1)
    let pause=clock.automaticPause!
    check(!clock.running && events.count==1,"A running clock did not report its automatic stop")
    check(pause.reason=="Grid alignment lost. The recorded game is preserved.","Cause includes an internal prefix")
    let remaining=clock.engine.black.remaining
    clock.interrupt("Finding the grid",at:base+2)
    check(clock.automaticPause==pause && events.count==1,"Repeated recovery replaced or re-announced the original cause")
    clock.pause("Clock and recording paused",at:base+3)
    clock.interrupt("Grid recovered; checking the move",at:base+4)
    clock.ready(at:base+5)
    check(!clock.running && clock.automaticPause==pause,"Camera recovery revoked a manual pause")
    check(clock.engine.black.remaining==remaining,"Paused checks consumed clock time")
    clock.requestResume()
    check(clock.automaticPause==pause,"Pressing Resume cleared the cause before verification")
    let url=root.appendingPathComponent("game.sgf")
    clock.bind(to:url,signature:"pause-test")
    let restored=LocalGameClock();restored.audible=false
    restored.restore(from:url,signature:"pause-test",moveCount:0,blackToPlay:true)
    check(restored.automaticPause==pause && !restored.running,"Restart lost the pause cause")
    check(restored.engine.black.remaining==remaining,"Restart changed paused time")
    restored.interrupt("Another camera check",at:base+6);restored.ready(at:base+6)
    check(!restored.running,"A camera check resumed a restored paused clock")
    clock.ready(at:base+6)
    check(clock.running && clock.automaticPause==nil && cleared==1,"Actual verified resume failed to clear the cause")
    clock.pause(at:base+7)
    check(clock.automaticPause==nil && events.count==1,"Manual pause manufactured an automatic cause")
    clock.resume(at:base+8);clock.pauseOnInterruption=false
    clock.interrupt("Unclear camera",at:base+9)
    check(clock.running && clock.automaticPause==nil && events.count==1,"Disabled auto-pause still generated a stop")
    clock.pauseOnInterruption=true;clock.interrupt("Camera stopped",at:base+10)
    check(events.count==2 && clock.automaticPause?.reason=="Camera stopped","A later interruption did not get its own cause")
    clock.finish(at:base+11)
    check(clock.automaticPause==nil && !clock.running,"Finished game kept an obsolete hold")
    // Backward compatibility with clock files written before pause metadata existed.
    var legacy=try JSONSerialization.jsonObject(with:Data(contentsOf:url.deletingPathExtension().appendingPathExtension("clock.json"))) as! [String:Any]
    legacy.removeValue(forKey:"automaticPause")
    try JSONSerialization.data(withJSONObject:legacy).write(to:url.deletingPathExtension().appendingPathExtension("clock.json"))
    restored.restore(from:url,signature:"pause-test",moveCount:0,blackToPlay:true)
    check(restored.saveError==nil && restored.automaticPause==nil,"Legacy clock files cannot restore")
    let recorder=GameRecorder(storage:root.appendingPathComponent("recordings"))
    recorder.clock.audible=false
    var manualEvents=0;recorder.clock.onAutomaticPause={_ in manualEvents += 1}
    recorder.start(size:19,clockSettings:.init(kind:.absolute,mainSeconds:300))
    recorder.clock.ready(at:base)
    recorder.pause()
    check(manualEvents==0 && recorder.clock.automaticPause==nil,"Recording Pause was misreported as a camera stop")
    let view=ClockPauseFeedback(pause:pause,paused:true,pendingMoves:1,requiresReview:false,awaitingTurn:false)
    check(view.nextStep.contains("Press Resume") && view.nextStep.contains("unconfirmed move"),"Paused pending move has no actionable explanation")
    let waiting=ClockPauseFeedback(pause:pause,paused:false,pendingMoves:1,requiresReview:false,awaitingTurn:false)
    check(waiting.nextStep.contains("Waiting to confirm") && waiting.nextStep.contains("after verification"),"Automatic hold does not explain what it awaits")
    check(ClockPauseFeedback(pause:pause,paused:true,pendingMoves:1,requiresReview:true,awaitingTurn:false).nextStep.contains("Review & resume"),"Clock review gate omitted from instructions")
    check(ClockPauseFeedback(pause:pause,paused:false,pendingMoves:0,requiresReview:false,awaitingTurn:true).nextStep.contains("Choose Black or White"),"Unknown turn has no action")
    let host=NSHostingView(rootView:view.padding(16).frame(width:700))
    host.appearance=NSAppearance(named:.darkAqua)
    host.frame=NSRect(origin:.zero,size:host.fittingSize);host.layoutSubtreeIfNeeded()
    let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
    host.cacheDisplay(in:host.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])!.write(to:TestArtifacts.file("physical-pause-explanation/pause-feedback.png"))
    let fake=FakeRecoveryVoice(),speech=RecoverySpeech(audio:fake)
    speech.request(.clockPause,text:"Clocks paused. Please check the screen.",settings:.init())
    speech.resolved(.clockPause,reason:"clock resumed")
    check(fake.stops.count==1,"Unstarted pause speech survived resume")
    speech.request(.clockPause,text:"Clocks paused. Please check the screen.",settings:.init())
    fake.hasStartedSpeech=true;speech.resolved(.clockPause,reason:"clock resumed")
    check(fake.stops.count==1,"Resuming clipped an already audible pause notice")
    check(KokoroSpeech.shared.cached("Clocks paused. Please check the screen.") != nil,"Pause notice is not bundled")
    print("PASS: \(checks) automatic-pause checks: original cause, pending move, manual pause, resume, restart, legacy files, clock time, native render and voice lifecycle")
}

@MainActor private func runBoardCheckGuidanceTests() throws {
    var checks=0
    func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
    let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ResumeVerification")
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("history-first-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    func restored()->GameRecorder {
        let dir=root.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.copyItem(at:fixture,to:dir)
        let recorder=GameRecorder(storage:dir);recorder.clock.audible=false
        try! recorder.restoreSavedGame(from:dir.appendingPathComponent("game.sgf"))
        return recorder
    }
    func states(_ board:BoardSnapshot)->[Occupancy] {board.grid.flatMap{$0}.map {stone -> Occupancy in
        if stone == .black {return .black};if stone == .white {return .white};return .empty
    }}
    func decode(_ text:String)->[Occupancy] {text.map{c -> Occupancy in c=="B" ? .black:c=="W" ? .white:c=="?" ? .uncertain:.empty}}
    func view(_ values:[Occupancy])->BoardObservation {
        BoardObservation(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19)
    }
    let recorder=restored(),clockBefore=recorder.clock.engine
    check(recorder.moveCount==172 && recorder.pendingMoveCount==1,"Wrong stalled-game fixture")
    let base=states(recorder.positions.last!),after=states(recorder.interpretedBoard!)
    let json=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture.appendingPathComponent("observation.json"))) as! [String:Any]
    let readings=decode(json["position"] as! String),actual=view(readings)
    let expectedOld=Set(readings.indices.filter{readings[$0] == .uncertain && base[$0].stone != nil})
    check(expectedOld.count>6,"Fixture does not reproduce the old cap")
    check(MoveObservationHistory.confirmedOcclusions(readings,base:base,after:after)==expectedOld,"History did not retain the old stones")
    check(RecordingClarity.checkPoints(readings:readings,base:base,after:after).isEmpty,"Unchanged old stones still request manual correction")
    let now=ProcessInfo.processInfo.systemUptime
    // Paused observation updates guidance, never history or clock presses.
    for i in 0..<10 {recorder.consume(actual,now:now+Double(i)*0.21)}
    check(recorder.adjustmentIssues.isEmpty && recorder.moveCount==172 && !recorder.clock.running,"Paused guidance changed the game or flagged old uncertainty")
    check(recorder.clock.engine.black.remaining==clockBefore.black.remaining,"Paused guidance charged clock time")
    let before=recorder.sgf()
    recorder.clock.requestResume();recorder.resume()
    var acceptedAt:Double?
    for i in 0..<12 {
        let at=now+3+Double(i)*0.21
        recorder.consume(actual,now:at)
        if recorder.moveCount==173 {acceptedAt=at-(now+3);break}
    }
    check(recorder.moveCount==173 && recorder.pendingMoveCount==0,"Actual clear pending move still stalls behind old uncertainty")
    check(acceptedAt != nil && acceptedAt!<=1.7,"Resumed clear move took longer than its fresh verification window")
    check(states(recorder.positions.last!)==after,"Acceptance changed a historical stone")
    check(recorder.clock.running && !recorder.clock.engine.blackToPlay,"Confirmed move did not switch and resume the clock")
    check(recorder.adjustmentIssues.isEmpty,"Accepted move left misleading orange rings")
    recorder.pause()
    // Replay distinct recorded frames and their actual spacing, not duplicated
    // confidence votes from a single image.
    let replay=restored()
    let frames=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture.appendingPathComponent("replay.json"))) as! [[String:Any]]
    replay.clock.requestResume();replay.resume()
    let firstTime=frames[0]["time"] as! Double
    var replayDelay:Double?
    for frame in frames {
        let elapsed=(frame["time"] as! Double)-firstTime
        var observation=view(decode(frame["position"] as! String));observation.lightingBlocked=frame["lightingBlocked"] as? Bool ?? false
        replay.consume(observation,now:now+elapsed)
        if replay.moveCount==173 {replayDelay=elapsed;break}
    }
    check(replayDelay != nil && replayDelay!<3,"Recorded sequence still cannot accept the clear pending move promptly")
    check(states(replay.positions.last!)==after,"Recorded replay corrupted a prior stone")
    replay.pause()
    print("History-first replay: \(expectedOld.count) unreadable recorded stones; saved-view confirmation \(String(format:"%.2f",acceptedAt!)) s; distinct recorded frames \(String(format:"%.2f",replayDelay!)) s")
    // The limit is semantic, not a new numeric cap: all unchanged old identities
    // can be unreadable while a clear new move and the empty space are visible.
    let crowded=restored();var obscured=after
    for p in base.indices where base[p].stone != nil && base[p]==after[p] {obscured[p] = .uncertain}
    crowded.clock.requestResume();crowded.resume()
    for i in 0..<10 {crowded.consume(view(obscured),now:now+Double(i)*0.21)}
    check(crowded.moveCount==173,"A hidden numeric cap still reopens recorded stones")
    crowded.pause()
    let newUnknown=restored();var unknownNew=readings;unknownNew[88] = .uncertain
    newUnknown.clock.requestResume();newUnknown.resume()
    for i in 0..<15 {newUnknown.consume(view(unknownNew),now:now+Double(i)*0.21)}
    check(newUnknown.moveCount==172,"History invented an unreadable new move")
    check(newUnknown.adjustmentIssues[88] == .newMove,"Persistent uncertainty at the new move has no marker")
    newUnknown.pause()
    let conflict=restored();var wrong=after
    let old=base.indices.first{base[$0].stone != nil && base[$0]==after[$0]}!
    wrong[old] = base[old] == .black ? .white:.black
    conflict.clock.requestResume();conflict.resume()
    for i in 0..<12 {conflict.consume(view(wrong),now:now+Double(i)*0.21)}
    check(conflict.moveCount==172 && conflict.adjustmentIssues[old] == .conflict,"Definite contrary evidence was ignored")
    var uncertainConflict=after;uncertainConflict[old] = .uncertain
    for i in 0..<12 {conflict.consume(view(uncertainConflict),now:now+3+Double(i)*0.21)}
    check(conflict.moveCount==172 && conflict.adjustmentIssues[old] == .conflict,"Uncertainty erased a previously verified contradiction")
    conflict.pause()
    // A short-lived or moving fringe never becomes a request to adjust stones.
    var monitor=BoardAdjustmentMonitor()
    for i in 0..<20 {monitor.update(issues:[i:.conflict],clear:[],now:Double(i)*0.21)}
    check(monitor.visible.isEmpty,"Moving one-frame errors generated moving targets")
    for i in 0..<5 {monitor.update(issues:[42:.placement],clear:[],now:5+Double(i)*0.21)}
    check(monitor.visible==[42:.placement],"Persistent ambiguous intersection did not get marked")
    monitor.update(issues:[:],clear:[42],now:6)
    check(monitor.visible[42] != nil,"One good frame flickered an active marker away")
    monitor.update(issues:[:],clear:[],now:6.21)
    check(monitor.visible[42] != nil,"Unknown readings moved an active marker")
    for i in 0..<5 {monitor.update(issues:[:],clear:[42],now:6.5+Double(i)*0.21)}
    check(monitor.visible.isEmpty,"Repeated agreement did not clear the marker")
    monitor.update(issues:[12:.conflict],clear:[],now:8)
    for _ in 0..<10 {monitor.update(issues:[12:.conflict],clear:[],now:8)}
    check(monitor.visible.isEmpty,"Repeated timestamps counted as fresh evidence")
    monitor.update(issues:[12:.conflict],clear:[],now:20)
    check(monitor.visible.isEmpty,"A camera gap carried old evidence into a new marker")
    var captured=after;captured[old] = .empty
    var unknownCapture=captured;unknownCapture[old] = .uncertain
    check(BoardAdjustmentMonitor.evidence(readings:unknownCapture,base:base,after:captured)[old] == .capture,"Capture ambiguity is hidden")
    check(!MoveObservationHistory.confirmedOcclusions(unknownCapture,base:base,after:captured).contains(old),"History inferred a capture removal")
    check(BoardAdjustmentMonitor.evidence(readings:[.empty],base:base,after:after).isEmpty,"Mismatched grids indexed past the board")
    // Native render shows the same saved position without fluctuating old-stone
    // rings, and a separate persistent conflict at its fixed board intersection.
    let out=try TestArtifacts.directory("physical-history-first")
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:720),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua);window.backgroundColor = .windowBackgroundColor
    for (name,recording,observation) in [("retained",recorder,actual),("conflict",conflict,view(wrong))] {
        let host=NSHostingView(rootView:VStack(alignment:.leading) {
            Text(name=="retained" ? "Move accepted · older stones retained":"Persistent disagreement · check the orange ring").font(.headline)
            RecordedBoard(recorder:recording,orientation:BoardOrientation(3),showsLivePosition:true,observation:observation) {_ in}.frame(width:600,height:600)
        }.padding(16))
        window.contentView=host;window.orderFront(nil)
        RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name+".png"))
        check(bitmap.pixelsWide>=600,"Invalid native marker render")
    }
    window.orderOut(nil)
    check(!before.isEmpty && recorder.game.moves.count==173,"Native render changed the game")
    print("PASS: \(checks) history-first resume and stable-marker checks: actual session replay, old identities, new moves, contradictions, capture evidence, debounce, camera gaps and native views")
}

@MainActor private func runSimpleReviewTests() throws {
    var checks=0
    func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
    let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/AccidentalCleanup")
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("simple-review-"+UUID().uuidString)
    try FileManager.default.copyItem(at:fixture,to:root)
    defer {try? FileManager.default.removeItem(at:root)}
    let recorder=GameRecorder(storage:root);recorder.clock.audible=false
    try recorder.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
    let original=recorder.reviewHistory,clock=recorder.clock.engine,before=recorder.sgf()
    let section=original.reviews.first{$0.reviewNumber==3}!,id=section.id
    check(recorder.moveCount==173 && original.unresolved==2,"Wrong cleanup fixture")
    let context=recorder.contextForReview(id)!
    check(context.turnKnown && recorder.nextPlayer == .white,"Expected White turn was lost")
    let plan=recorder.accidentalWithdrawalPlan(id)!
    check(plan.removedPoints==[19,20,38],"Cleanup selected the wrong extras")
    check(plan.sectionIDs.count==3 && plan.keptMoves.count==1,"Related removal review or later move is missing")
    check(plan.keptMoves[0].color == .white && plan.keptMoves[0].point==BoardPosition(4,1),"Cleanup would discard or relocate the later White move")
    check(plan.nextPlayer == .black && plan.target[77] == .white,"Incorrect target position or next player")
    check(plan.results[id]==section.before,"First cleanup result changed an established stone")
    check(recorder.canWithdrawAccidentalMoves(id),"Earlier accidental section still cannot be cleaned up")
    check(recorder.withdrawAccidentalMoves(id,removedByPlayer:false) != nil,"Cleanup did not require an explicit confirmation")
    check(recorder.withdrawAccidentalMoves(id,removedByPlayer:true) != nil,"Cleanup ignored missing camera verification")
    check(recorder.sgf()==before && recorder.reviewHistory.unresolved==2,"Rejected cleanup changed the game")
    var unrelated=original
    let last=unrelated.sections.count-1
    unrelated.sections[last].after[360] = .black
    check(AccidentalStoneWithdrawal.make(history:unrelated,id:id,context:context.game)==nil,"Unrelated unresolved change was discarded")
    var wrongColor=original
    wrongColor.sections[last-1].moves=[.init(color:.black,point:.init(4,1))]
    check(AccidentalStoneWithdrawal.make(history:wrongColor,id:id,context:context.game)==nil,"Later wrong-color move bypassed rules validation")
    var replay=original
    replay.sections[last].after[19] = .empty
    var replayed=replay.sections[last]
    replayed.id=UUID();replayed.before=replayed.after;replayed.after[19] = .black;replayed.moves=nil
    replay.sections.append(replayed)
    check(AccidentalStoneWithdrawal.make(history:replay,id:id,context:context.game)==nil,"A later replay at an excluded point was silently discarded")
    var capture=original;capture.sections[2].before[19] = .white
    check(AccidentalStoneWithdrawal.make(history:capture,id:id,context:context.game)==nil,"Cleanup accepted a changed or captured original stone")
    func observation(_ states:[Occupancy])->BoardObservation {
        .init(readings:states.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19)
    }
    var time=ProcessInfo.processInfo.systemUptime-5
    func feed(_ states:[Occupancy],count:Int=6) {for _ in 0..<count {time += 0.21;recorder.consume(observation(states),now:time)}}
    var notRemoved=plan.target;notRemoved[19] = .black
    feed(notRemoved)
    check(!recorder.accidentalRemovalVerified(plan,now:time+0.01),"One remaining accidental stone was treated as removed")
    var unknown=plan.target;unknown[19] = .uncertain
    feed(unknown)
    check(!recorder.accidentalRemovalVerified(plan,now:time+0.01),"Unseen removal was inferred")
    feed(plan.target,count:1)
    check(!recorder.accidentalRemovalVerified(plan,now:time+0.01),"A single frame confirmed removal")
    feed(plan.target,count:5)
    check(recorder.accidentalRemovalVerified(plan,now:time+0.01),"Actual cleanup was not verified")
    check(!recorder.accidentalRemovalVerified(plan,now:time+2),"Stale camera verification survived a missing feed")
    let out=try TestArtifacts.directory("physical-simple-review")
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:920,height:720),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua);window.backgroundColor = .windowBackgroundColor
    // Keep the witness clock aligned with real time for the actual view's button.
    recorder.suspendVision("Test camera restart",preserveOrder:true)
    time=ProcessInfo.processInfo.systemUptime-1.3;feed(plan.target)
    let host=NSHostingView(rootView:ReviewSectionView(recorder:recorder,id:id,orientation:BoardOrientation(3)))
    window.contentView=host;window.orderFront(nil)
    RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
    let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
    host.cacheDisplay(in:host.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent("cleanup-ready.png"))
    check(bitmap.pixelsWide>=882,"Invalid native review render")
    window.orderOut(nil)
    let result=recorder.withdrawAccidentalMoves(id,removedByPlayer:true,now:time+0.01)
    check(result==nil,"Combined cleanup failed: \(result ?? "")")
    check(recorder.moveCount==174 && !recorder.hasDeferredMoves && !recorder.hasUnfinishedReviews,"Cleanup did not resolve both reviews and keep the later move")
    check(recorder.game.moves.last!.0 == .white && recorder.game.moves.last!.1!.0==1 && recorder.game.moves.last!.1!.1==4,"Kept move was changed")
    check(DeferredMoveHistory.states(recorder.positions.last!)==plan.target,"Final board differs from the displayed proposal")
    check(recorder.clock.engine.black==clock.black && recorder.clock.engine.white==clock.white,"Cleanup changed accrued clock times")
    check(recorder.state == .paused && !recorder.clock.running && !recorder.clock.awaitingTurn && recorder.clock.engine.blackToPlay,"Cleanup resumed clocks or left the turn unknown")
    for section in original.sections {
        let kept=recorder.reviewHistory.sections.first{$0.id==section.id}!
        check(kept.before==section.before && kept.after==section.after,"Cleanup overwrote a source camera snapshot")
    }
    let restored=GameRecorder(storage:nil);restored.clock.audible=false
    try restored.restoreSavedGame(from:root.appendingPathComponent("game.sgf"))
    check(restored.moveCount==174 && !restored.hasDeferredMoves,"Finalized cleanup failed to survive restart")
    check(recorder.withdrawAccidentalMoves(id,removedByPlayer:true,now:time+0.01) != nil,"Repeated confirmation applied cleanup twice")
    print("PASS: \(checks) one-board cleanup checks: actual two-review mistake, later White preserved, fresh removal evidence, wrong colors, unrelated changes, replay protection, snapshots, clocks, restart and native view")
}

@MainActor private func runPauseAnnouncementTests() {
    var checks=0
    func check(_ ok:Bool,_ text:String) {checks += 1;precondition(ok,text)}
    let voice=FakeRecoveryVoice(),speech=RecoverySpeech(audio:voice)
    let announcements=ClockPauseAnnouncements(speech:speech,delay:0.01)
    let settings=LocalClockSounds()
    func settle() {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
    func begin() {announcements.began(settings:settings,enabled:{true})}
    func clear(_ running:Bool=true,_ black:Bool=false,_ enabled:Bool=true) {
        announcements.cleared(running:running,blackToPlay:black,enabled:enabled,settings:settings)
    }
    func heard() {voice.hasStartedSpeech=true;voice.onSpeechEvent?("started",[:])}
    begin();clear();settle()
    check(voice.phrases.isEmpty,"Brief hold spoke after recovering")
    begin();settle();clear()
    check(voice.stops.count==1 && !voice.phrases.contains(where:{$0.contains("resumed")}),"Unheard pause caused an orphan resume")
    begin();settle();heard();voice.finish();clear()
    check(voice.phrases.last=="Clocks resumed. White to play.","Completed pause lacked White resume")
    heard();voice.finish()
    begin();settle();heard();clear(true,true)
    check(voice.phrases.last=="Clocks paused. Please check the screen.","Resume overlapped or cut off pause")
    voice.finish();check(voice.phrases.last=="Clocks resumed. Black to play.","Mid-sentence recovery lost Black resume")
    // The resume is still synthesizing. A new pause must cancel it.
    begin();check(voice.stops.last=="clocks paused again","Stale resume survived a new pause")
    settle();heard();voice.finish();clear(false)
    check(voice.phrases.last=="Clocks paused. Please check the screen.","Ending/resetting game announced resume")
    begin();settle();heard();voice.finish();clear(true,false,false)
    check(voice.phrases.last=="Clocks paused. Please check the screen.","Muted recovery announced resume")
    speech.request(.lighting,text:"Lighting",settings:settings);heard()
    begin();settle();clear();voice.finish()
    check(voice.phrases.last=="Clocks resumed. White to play.","Audible lighting pause lacked resume")
    heard();voice.finish()
    var enabled=true
    announcements.began(settings:settings,enabled:{enabled});enabled=false;settle()
    check(voice.phrases.last=="Clocks resumed. White to play.","Mute during debounce did not suppress pause")
    clear(false)
    // A second brief hold while the first pause is still speaking must not
    // erase the obligation to announce the eventual resumption.
    begin();settle();heard();clear()
    begin();voice.finish();clear(true,true)
    check(voice.phrases.last=="Clocks resumed. Black to play.","Rapid re-pause lost the eventual resume announcement")
    heard();voice.finish()
    let beforeBrief=voice.phrases.count
    begin();clear();settle()
    check(voice.phrases.count==beforeBrief,"Already heard resume leaked into a later silent hold")
    for topic in [RecoverySpeech.Topic.alignment,.lighting] {
        begin()
        speech.request(topic,text:"Please pause play",settings:settings);heard();voice.finish()
        clear(true,true)
        check(voice.phrases.last=="Clocks resumed. Black to play.","Camera/lighting warning was not paired with resume")
        heard();voice.finish()
        let oldCount=voice.phrases.count
        begin();clear();settle()
        check(voice.phrases.count==oldCount,"Old camera warning caused unrelated resume speech")
    }
    for text in ["Clocks resumed. Black to play.","Clocks resumed. White to play."] {
        check(KokoroSpeech.shared.cached(text) != nil,"Missing bundled resume speech")
    }
    print("PASS: \(checks) paired pause/resume speech checks: debounce, actual playback, queue priority, both players, repeated holds, mute and finish")
}

private func runAlignmentGateTests() {
    var checks=0,gate=BoardAlignmentGate()
    let marginal:[String:Any]=["rejectionReason":"no grid fit; profile error too high","profileError":0.041]
    func check(_ ok:Bool,_ text:String) {checks += 1;precondition(ok,text)}
    check(!gate.shouldHold(report:marginal,now:0,allowGrace:true),"One marginal frame paused")
    gate.reset()
    for i in 0..<20 {
        check(!gate.shouldHold(report:marginal,now:Double(i),allowGrace:true),"Isolated failures accumulated across success")
        gate.reset()
    }
    check(!gate.shouldHold(report:marginal,now:30,allowGrace:true),"First failure paused")
    check(!gate.shouldHold(report:marginal,now:30.3,allowGrace:true),"Second failure paused too soon")
    check(gate.shouldHold(report:marginal,now:30.7,allowGrace:true),"Sustained failures did not pause")
    gate.reset();_ = gate.shouldHold(report:marginal,now:40,allowGrace:true)
    check(gate.shouldHold(report:marginal,now:40.95,allowGrace:true),"Slow frames extended grace beyond bound")
    gate.reset();_ = gate.shouldHold(report:marginal,now:50,allowGrace:true)
    for _ in 0..<10 {_ = gate.shouldHold(report:marginal,now:50,allowGrace:true)}
    check(gate.failures==1,"Redraws counted as fresh evidence")
    check(!gate.shouldHold(report:marginal,now:53,allowGrace:true) && gate.failures==1,"Camera gap reused stale failures")
    check(gate.shouldHold(report:marginal,now:54,allowGrace:false),"Startup/online/setup incorrectly received grace")
    for reason in ["fitted grid moved at least 0.4 intersections","invalid fitted corners","corner transform failed","tracking anchor unavailable","camera frame decoding failed"] {
        gate.reset();check(gate.shouldHold(report:["rejectionReason":reason],now:60,allowGrace:true),"Definite/unusable alignment was delayed: \(reason)")
    }
    print("PASS: \(checks) alignment hysteresis checks: isolated/sustained failures, bounded delay, fresh frames, displacement and calibration failures")
}
