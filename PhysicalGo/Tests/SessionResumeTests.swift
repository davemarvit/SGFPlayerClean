import AppKit
import ImageIO

@main struct SessionResumeTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("session-resume-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let suite="PhysicalGo.SessionResume."+UUID().uuidString,settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ResumeAlignment")
        let file=root.appendingPathComponent("game.sgf")
        try FileManager.default.copyItem(at:fixture.appendingPathComponent("game.sgf"),to:file)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        func model()->ExperimentModel {
            let m=ExperimentModel(discoverCameras:false,automaticGridDetection:false,referenceArchive:nil,recordingStorage:root,settings:settings,diagnosticRoot:root.appendingPathComponent("diagnostics"),moveEvidenceRoot:root.appendingPathComponent("clips"))
            m.recorder.clock.audible=false;m.recoverySpeechEnabled=false;m.moveEvidenceCapture.enabled=false
            return m
        }
        let first=model();first.restoreLastLocalGame()
        check(!first.recorder.hasGame,"First launch invented a game")
        try first.recorder.restoreSavedGame(from:file)
        check(LastLocalGame(settings:settings).url==file,"Explicitly opened game was not remembered")
        check(first.recorder.flushForExit(),"Could not persist the paused game")
        let saved=try Data(contentsOf:file),clock=first.recorder.clock.engine
        let reopened=model();reopened.restoreLastLocalGame()
        check(reopened.recorder.moveCount==67 && reopened.recorder.state == .paused,"Ordinary launch did not reopen saved history paused")
        check(!reopened.recorder.clock.running && reopened.recorder.clock.engine.black==clock.black && reopened.recorder.clock.engine.white==clock.white,"Reopen changed clock balances")
        check(reopened.recoveryExpected.filter{$0.stone != nil}.count==62,"Camera recovery cannot see the saved stones at launch")
        struct Sample:Decodable {let calibration:BoardCalibration}
        reopened.calibration=try JSONDecoder().decode(Sample.self,from:Data(contentsOf:fixture.appendingPathComponent("sample.json"))).calibration
        reopened.image=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(fixture.appendingPathComponent("frame.png") as CFURL,nil)!,0,nil)!
        reopened.frozen=true;reopened.detectGrid()
        let end=Date().addingTimeInterval(60)
        while (reopened.detectingGrid || reopened.observation==nil) && Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
        check(!reopened.detectingGrid && !reopened.alignmentNeedsRecovery && reopened.observation != nil,"Actual model failed occupied-board reacquisition")
        check(reopened.recorder.state == .paused && !reopened.recorder.clock.running,"Grid recovery started the clocks")
        check(try Data(contentsOf:file)==saved,"Reacquisition rewrote saved moves")
        check(reopened.recorder.clock.engine.black==clock.black && reopened.recorder.clock.engine.white==clock.white,"Reacquisition altered time")
        let online=model();online.playMode = .online;online.restoreLastLocalGame()
        check(!online.recorder.hasGame,"Online launch reopened a local game")
        online.playMode = .local
        LastLocalGame(settings:settings).remember(root.appendingPathComponent("missing.sgf"))
        let missing=model();missing.restoreLastLocalGame()
        check(!missing.recorder.hasGame && missing.message.contains("Could not reopen"),"Missing recording silently replaced the game")
        print("PASS: \(checks) session resume, saved-history alignment, paused clocks and missing-file checks")
    }
}
