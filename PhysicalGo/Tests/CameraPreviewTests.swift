import AppKit
import ImageIO

@main struct CameraPreviewTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory);setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        func settle(_ seconds:Double=0.3) {RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
        func wait(_ name:String,_ predicate:()->Bool) {
            let deadline=Date().addingTimeInterval(5)
            while !predicate() && Date()<deadline {settle(0.02)}
            check(predicate(),"Camera analysis did not finish: \(name)")
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("camera-preview-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let suite="CameraPreviewTests."+UUID().uuidString,settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/CoveredBorder")
        struct Metadata:Decodable {let calibration:BoardCalibration}
        let cal=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:fixture.appendingPathComponent("metadata.json"))).calibration
        func photo(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(fixture.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let clear=photo("000001.png"),hand=photo("000011.png")
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,
            referenceArchive:nil,recordingStorage:root,settings:settings,diagnosticRoot:root.appendingPathComponent("diagnostics"),moveEvidenceRoot:root.appendingPathComponent("clips"))
        model.soundMode = .off;model.recoverySpeechEnabled=false;model.tracksCameraMotion=false
        model.diagnosticSettings.unusualMoves=false;model.diagnosticSettings.byoyomiLosses=false
        model.calibration=cal;model.corners=cal.corners;model.straightenBoard=true
        model.recorder.start(size:19,clockSettings:.init(kind:.absolute,mainSeconds:300))
        model.recorder.clock.audible=false;model.recorder.pause()
        model.running=true;model.frozen=false;model.handleCameraStatus("Live · preview test",state:.live)
        model.alignmentCheck = .failed
        model.receiveCameraFrame(clear,capturedAt:ProcessInfo.processInfo.systemUptime)
        wait("first clear preview") {model.image === clear && model.rectifiedImage != nil}
        check(model.alignmentCheck == .passed,"Fresh accepted alignment retained a failed search message")
        check(model.rawCameraPreview==nil,"Hidden raw view retained camera images")
        model.showsRawCameraView=true
        let before=model.rectifiedImage!,engine=model.recorder.clock.engine
        model.alignmentCheck = .failed
        model.receiveCameraFrame(hand,capturedAt:ProcessInfo.processInfo.systemUptime)
        check(model.rawCameraPreview?.image === hand,"On-demand raw view waited for recognition or used rectified pixels")
        wait("hand obstruction") {model.recorder.handOverBoard}
        check(model.image === hand,"Raw preview failed to show current hand frame")
        check(model.rectifiedImage !== before,"Flattened preview froze on the previous clear frame")
        let rendered=BoardRectifier.render(hand,geometry:model.rectifiedGeometry!)!
        check(GrayFrame(image:model.rectifiedImage!)!.pixels==GrayFrame(image:rendered)!.pixels,"Flattened preview does not contain the current hand pixels")
        check(model.observation==nil && model.trackedBoardObservation==nil,"Hand frame kept stale recognition overlays")
        check(model.alignmentCheck == .failed,"An obstructed frame incorrectly cleared alignment failure")
        check(model.recorder.moveCount==0 && model.recorder.clock.engine==engine && !model.recorder.clock.running,"Refreshing hand pixels changed paused history or clocks")
        let held=model.rectifiedImage!
        model.frozen=true;model.receiveCameraFrame(clear,capturedAt:ProcessInfo.processInfo.systemUptime);settle()
        check(model.rectifiedImage === held,"Explicit Freeze stopped freezing the preview")
        check(model.rawCameraPreview?.image === clear,"Analysis Freeze hid the live raw camera view")
        let rawTime=model.rawCameraPreview?.capturedAt
        model.frozen=false;model.receiveCameraFrame(clear,capturedAt:ProcessInfo.processInfo.systemUptime-3);settle()
        check(model.rectifiedImage === held,"A stale camera buffer replaced current pixels")
        check(model.rawCameraPreview?.capturedAt==rawTime,"Raw view accepted a stale camera image")
        check(model.alignmentCheck == .failed,"Frozen or stale frames incorrectly cleared alignment failure")
        // A fresh clear frame must release the hand gate and restore observations.
        for _ in 0..<8 {model.receiveCameraFrame(clear,capturedAt:ProcessInfo.processInfo.systemUptime);settle(0.35)}
        check(!model.recorder.handOverBoard && model.observation != nil,"Clear board did not recover after the hand")
        check(model.alignmentCheck == .passed,"Clear live recovery retained obsolete alignment failure")
        check(model.recorder.moveCount==0 && model.recorder.clock.engine==engine,"Clear preview resumed paused play or saved fixture stones")
        let calibrationBeforeRetry=model.calibration
        check(!model.canRetryStartupSetup,"Empty-board setup reset was offered during an existing game")
        model.retryStartupSetup()
        check(model.calibration==calibrationBeforeRetry && model.recorder.clock.engine==engine,"Startup retry reset a current game's grid or clocks")
        model.showsRawCameraView=false
        check(model.rawCameraPreview==nil,"Closing raw view retained its extra image")
        model.alignmentCheck = .failed
        model.undoCorner()
        check(model.alignmentCheck == .idle,"Manual corner edit retained the old alignment result")
        model.alignmentCheck = .failed
        model.resetCalibration()
        check(model.alignmentCheck == .idle,"Reset grid retained the old alignment result")
        model.stop()
        print("PASS: \(checks) camera preview checks: actual hand pixels, flattened rendering, blocked overlays, manual pause, explicit freeze, stale buffers and recovery")
    }
}
