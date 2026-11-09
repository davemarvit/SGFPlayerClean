import AppKit

@main struct RecoveryLifecycleTests {
    struct Sample:Decodable {
        struct Label:Decodable {let point:Int;let choice:ManualBoardCorrections.Choice}
        let rawReadings:[IntersectionReading],labels:[Label]
    }
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/IncompleteCapture")
        let glare=try JSONDecoder().decode(Sample.self,from:Data(contentsOf:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/RecoveryGlare/sample.json")))
        let raw=BoardObservation(readings:glare.rawReadings,size:19)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("recovery-lifecycle-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let sgf=try String(contentsOf:fixture.appendingPathComponent("before.sgf"),encoding:.utf8)
        let game=SGFGame.from(tree:try SGFParser.parse(text:sgf))
        let player=SGFPlayer();player.load(game:game);player.seek(to:game.moves.count)
        let after=try JSONDecoder().decode([Occupancy].self,from:Data(contentsOf:fixture.appendingPathComponent("observed.json")))
        var history=DeferredMoveHistory();history.size=19;history.baseMove=game.moves.count;history.anchorSignature=RecordingIdentity.signature(for:game)
        history.sections=[.init(reviewNumber:1,before:DeferredMoveHistory.states(player.board),after:after,reason:"Incomplete capture",firstSeen:1,confirmedAt:2)]
        let file=folder.appendingPathComponent("game.sgf");try sgf.write(to:file,atomically:true,encoding:.utf8)
        try JSONEncoder().encode(history).write(to:file.withExtension("reviews.json"))
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:folder)
        model.recoverySpeechEnabled=false;model.moveEvidenceCapture.enabled=false
        let recorder=model.recorder;recorder.clock.audible=false
        let labels=model.boardCorrections;labels.begin(size:19)
        for label in glare.labels {labels.set(label.choice,at:label.point)}
        let checked=labels.apply(to:raw,preview:true)
        check(glare.labels.contains{raw.signature[$0.point].stone != nil},"Incident no longer reproduces glare disagreement")
        check(labels.apply(to:raw).signature==raw.signature,"Draft affected live observation")
        try recorder.restoreSavedGame(from:file);recorder.attachClock(.init())
        let plan=recorder.pendingCaptureReview!,time=ProcessInfo.processInfo.systemUptime
        let proof=CheckedReviewPhoto(reviewID:plan.id,target:plan.target,position:checked.signature,capturedAt:time)
        check(!proof.verifies(id:UUID(),target:plan.target,requiredClear:plan.captured,now:time),"Photo crossed review identity")
        check(!proof.verifies(id:plan.id,target:plan.source,requiredClear:plan.captured,now:time),"Photo crossed target position")
        check(!proof.verifies(id:plan.id,target:plan.target,requiredClear:plan.captured,now:time+61),"Expired photo authorized a correction")
        check(!proof.verifies(id:plan.id,target:plan.target,requiredClear:plan.captured,now:time-1),"Future timestamp accepted")
        let clocks=recorder.clock.engine
        check(recorder.confirmCaptureReview(plan.id,now:time) != nil,"Raw glare or old observations silently approved a capture")
        check(recorder.confirmCaptureReview(plan.id,now:time,checkedPhoto:proof)==nil,"Explicit checked-photo capture failed")
        labels.commit()
        check(labels.values.isEmpty && labels.apply(to:raw).signature==raw.signature,"Photo approval left persistent overrides")
        check(recorder.moveCount==46 && recorder.nextPlayer == .white && !recorder.hasDeferredMoves,"Checked photo changed legal capture history")
        check(recorder.clock.engine.black==clocks.black && recorder.clock.engine.white==clocks.white && !recorder.clock.running,"Photo resolution changed or restarted clocks")
        check(recorder.confirmCaptureReview(plan.id,now:time,checkedPhoto:proof) != nil,"Photo confirmation replay duplicated a move")
        check(recorder.reviewHistory.sections.last?.reason.contains("capture") == true,"Original review provenance lost")
        recorder.resume();var now=time
        func feed(_ values:[Occupancy]) {
            let observation=BoardObservation(readings:values.enumerated().map{.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19)
            for _ in 0..<12 {now+=0.21;model.deliverLiveObservation(observation,now:now)}
        }
        feed(plan.target)
        var next=plan.target;next[185] = .white;feed(next)
        check(recorder.moveCount==47 && recorder.positions.last!.grid[9][14] == .white,"Real White move at former Empty label was hidden")
        next[204] = .black;feed(next)
        check(recorder.moveCount==48 && recorder.positions.last!.grid[10][14] == .black,"Real Black move at former Empty label was hidden")
        recorder.pause()
        let restored=GameRecorder(storage:folder);restored.clock.audible=false;try restored.restoreSavedGame(from:file)
        check(restored.moveCount==48 && !restored.clock.running,"Restart lost recovery or resumed a manually paused game")
        print("PASS: \(checks) recovery lifecycle checks: actual glare, photo-only labels, explicit legal capture, expiry/context/replay guards, unchanged clocks, subsequent real White/Black moves and restart")
    }
}
private extension URL {
    func withExtension(_ suffix:String)->URL {deletingPathExtension().appendingPathExtension(suffix)}
}
