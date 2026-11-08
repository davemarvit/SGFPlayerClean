import AppKit
import CoreImage

@main struct StoneTrackingUITests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks += 1;if !ok {fatalError(message)}}
        func wait(_ ready:()->Bool) {
            let limit=Date().addingTimeInterval(40)
            while !ready() && Date()<limit {RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
            check(ready(),"Camera-analysis delivery timed out")
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("tracking-ui-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:root)
        model.recoverySpeechEnabled=false
        try model.openSample(from:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CameraBump"))
        wait {model.observation != nil}
        let black=[(12,16),(13,16),(14,16),(15,15),(16,5),(16,13),(16,15),(17,14)]
        let white=[(13,17),(14,17),(15,3),(15,16),(16,7),(16,16),(17,15),(17,16)]
        var sgf="(;GM[1]FF[4]AP[PhysicalGo:0.88]SZ[19]RU[Japanese]KM[6.5]"
        for i in black.indices {sgf += ";B["+SGFCoordinates.toSGF(x:black[i].1,y:black[i].0)+"];W["+SGFCoordinates.toSGF(x:white[i].1,y:white[i].0)+"]"}
        sgf += ")"
        let file=root.appendingPathComponent("game.sgf");try sgf.write(to:file,atomically:true,encoding:.utf8)
        try model.recorder.restoreSavedGame(from:file)
        let saved=model.recorder.sgf(),image=model.image!,context=CIContext(),input=CIImage(cgImage:model.image!)
        model.running=true;model.cameraState = .live;model.frozen=false
        var now=ProcessInfo.processInfo.systemUptime
        func frame() {
            now += 0.6
            let fresh=context.createCGImage(input,from:input.extent)!
            model.receive(fresh,capturedAt:now)
            wait {model.image === fresh}
        }
        for _ in 0..<8 {frame()}
        check(model.stoneTrackingReport.tracked>0,"Live camera path did not establish physical stone tracks")
        print("Live sample tracked \(model.stoneTrackingReport.tracked) of 16 established stones")
        check(model.recorder.sgf()==saved && model.recorder.state == .paused,"Background refresh modified or resumed the game")
        check(model.observation?.signature==model.trackedBoardObservation?.signature,"Unchanged image produced an unexplained remapping")
        check(model.correctedObservation?.signature==model.observation?.signature,"Display diverged from unchanged image")
        now += 3;frame()
        check(model.stoneTrackingReport.tracked==0,"Live camera gap reused stale tracks")
        for _ in 0..<4 {frame()}
        check(model.stoneTrackingReport.tracked>0,"Tracking did not recover after fresh views")
        model.frozen=true;frame()
        check(model.stoneTrackingReport.tracked==0,"Frozen input supplied fresh tracking evidence")
        check(model.recorder.sgf()==saved,"Freeze/camera gap changed SGF")
        model.frozen=false
        for _ in 0..<4 {frame()}
        model.beginBoardCorrection();frame()
        check(model.stoneTrackingReport.tracked==0,"Manual correction session did not suspend association")
        model.cancelBoardCorrection()
        model.running=false
        check(image.width==model.image?.width,"Camera input dimensions changed")
        print("PASS: \(checks) native camera-path checks; background geometry, unchanged SGF, paused recording, camera gap, freeze and manual correction")
    }
}
