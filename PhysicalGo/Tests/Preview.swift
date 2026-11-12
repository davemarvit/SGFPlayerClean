import AppKit
import SwiftUI
import ImageIO

@main struct Preview {
    @MainActor static func main() throws {
        setbuf(stdout,nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/.build")
        func fixture(_ name: String) -> CGImage {
            let source = CGImageSourceCreateWithURL(root.appendingPathComponent("Fixtures/\(name).png") as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        // Startup selection and persistence, with activation injected to avoid hardware.
        let suite="PhysicalGoStartupTests-"+UUID().uuidString
        let settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        settings.set("usb",forKey:"PhysicalGo.lastCameraID")
        settings.set("USB board camera",forKey:"PhysicalGo.lastCameraName")
        func startupModel()->ExperimentModel {
            ExperimentModel(discoverCameras:false,restoreViewSettings:true,referenceArchive:nil,recordingStorage:nil,settings:settings)
        }
        let startup=startupModel()
        startup.cameras=[.init(id:"builtin",name:"Built-in"),.init(id:"usb",name:"USB board camera")]
        var activations=0
        startup.startCameraOnLaunch {activations += 1}
        startup.startCameraOnLaunch {activations += 1}
        guard activations==1,startup.cameraID=="usb",!startup.recorder.hasGame else {fatalError("Launch did not select the last camera exactly once, or started recording")}
        let missingCamera=startupModel();missingCamera.cameras=[.init(id:"builtin",name:"Built-in")]
        missingCamera.startCameraOnLaunch {fatalError("Activated a different camera without selection")}
        guard missingCamera.cameraStatus.contains("unavailable") else {fatalError("Missing last-used camera has no explanation")}
        let movedPort=startupModel();movedPort.cameras=[.init(id:"new-usb-id",name:"USB board camera")]
        movedPort.startCameraOnLaunch {activations += 1}
        guard movedPort.cameraID=="new-usb-id",activations==2 else {fatalError("Unique camera-name fallback failed")}
        movedPort.handleCameraStatus("Live",state:.live)
        guard settings.string(forKey:"PhysicalGo.lastCameraID")=="new-usb-id" else {fatalError("Successful camera choice was not persisted")}
        let duplicateNames=startupModel()
        duplicateNames.cameras=[.init(id:"one",name:"USB board camera"),.init(id:"two",name:"USB board camera")]
        duplicateNames.startCameraOnLaunch {fatalError("Guessed between duplicate camera names")}
        let sampleStartup=startupModel();sampleStartup.frozen=true
        sampleStartup.startCameraOnLaunch {fatalError("Replaced a frozen sample with the camera")}
        settings.removeObject(forKey:"PhysicalGo.lastCameraID");settings.removeObject(forKey:"PhysicalGo.lastCameraName")
        let firstLaunch=startupModel();firstLaunch.cameras=[.init(id:"only",name:"Webcam")]
        firstLaunch.startCameraOnLaunch {activations += 1}
        guard firstLaunch.cameraID=="only",activations==3 else {fatalError("First launch did not select an available camera")}
        let noCamera=startupModel();noCamera.startCameraOnLaunch {fatalError("Started with no camera")}
        guard noCamera.cameraStatus.contains("No camera") else {fatalError("No-camera startup has no explanation")}
        print("PASS: automatic camera selection, saved preference, changed USB ID, missing/ambiguous devices, no device, sample preservation, and one-shot startup without auto-recording.")
        let model = ExperimentModel(discoverCameras: false, automaticGridDetection: false, restoreViewSettings:false,referenceArchive:nil)
        model.tracksCameraMotion=false // The synthetic classifier fixture has no grid lines.
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:940),styleMask:[.titled],backing:.buffered,defer:false)
        let host = NSHostingView(rootView:ExperimentView(model:model).frame(width:1280,height:940))
        window.contentView = host; window.orderFront(nil)
        func settle() { RunLoop.main.run(until:Date().addingTimeInterval(0.4)) }
        func screenshot(_ name: String) throws {
            settle(); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
        }
        try screenshot("welcome")
        model.receive(fixture("empty"))
        for p in [ImagePoint(x:0.1,y:0.1),ImagePoint(x:0.9,y:0.1),ImagePoint(x:0.9,y:0.9),ImagePoint(x:0.1,y:0.9)] { model.addCorner(p) }
        settle()
        guard model.rectifiedImage != nil && !model.hasReference else { fatalError("Correction must work before an empty reference") }
        model.captureReference(); settle()
        model.receive(fixture("stones")); settle()
        guard model.observation?.snapshot.stones.count == 5 else { fatalError("Model did not detect fixture") }
        model.frozen = true; model.sourceName = "Synthetic fixture"; model.cameraStatus = "Photo · synthetic test board"
        model.message = "Synthetic fixture for interface verification. Physical board accuracy has not yet been measured."
        model.label(0)
        guard model.labels[0] == .white else { fatalError("Manual label did not cycle") }
        try screenshot("detected-board")
        let sample = root.appendingPathComponent("SampleTest-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:sample) }
        try model.saveSample(to: sample)
        let data = try Data(contentsOf:sample.appendingPathComponent("sample.json"))
        let metadata = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        guard (metadata["readings"] as? [[String:Any]])?.count == 361,
              (metadata["manualLabels"] as? [String:String])?["0"] == "white",
              FileManager.default.fileExists(atPath:sample.appendingPathComponent("empty-reference.png").path) else { fatalError("Sample export incomplete") }
        let sgf = try String(contentsOf:sample.appendingPathComponent("position.sgf"),encoding:.utf8)
        let savedGame = SGFGame.from(tree:try SGFParser.parse(text:sgf))
        guard savedGame.setup.count == 5 && savedGame.moves.isEmpty else { fatalError("Sample SGF incorrect") }
        do { try model.saveSample(to:sample); fatalError("Overwrote sample") } catch ExperimentModel.SampleError.exists { }

        // A frozen sample remains exportable during recovery; the next live run verifies alignment against the preserved baseline.
        model.handleCameraStatus("Reconnecting", state: .recovering)
        guard model.running && !model.stable && model.hasReference && model.labels[0] == .white else { fatalError("Recovery damaged a frozen sample") }
        model.toggleFreeze()
        guard model.hasReference && model.awaitingReferenceFrame && model.observation == nil && model.calibration != nil else { fatalError("Resume lost the saved reference or reused stale observations") }
        let preservedReference = model.referenceImage
        model.captureReference()
        guard model.referenceImage === preservedReference else { fatalError("Captured stale frame while waiting for camera") }
        model.handleCameraStatus("Live", state: .live)
        model.receive(fixture("empty")); model.captureReference(); settle()
        guard model.hasReference else { fatalError("Fresh frames could not be recalibrated") }
        model.handleCameraStatus("No frames", state: .failed)
        guard !model.running && model.hasReference && model.awaitingReferenceFrame && model.observation == nil && !model.stable else { fatalError("Failed stream retained live detection state") }
        model.resetCalibration()
        guard model.observation == nil && !model.hasReference && model.labels.isEmpty else { fatalError("Calibration reset retained stale detection") }
        model.tracksCameraMotion=true
        let realFolder = root.deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/EdgeStones")
        struct CalibrationOnly: Decodable { let calibration: BoardCalibration }
        let saved = try JSONDecoder().decode(CalibrationOnly.self,from:Data(contentsOf:realFolder.appendingPathComponent("sample.json")))
        func realPhoto(_ name: String) -> CGImage {
            let source = CGImageSourceCreateWithURL(realFolder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        model.receive(realPhoto("empty-reference.png"))
        for corner in saved.calibration.corners { model.addCorner(corner) }
        model.captureReference(); settle()
        model.receive(realPhoto("frame.png")); settle()
        if model.observation?.snapshot.stones.count != 2 || model.observation?.signature.contains(.uncertain) != false {
            print("Edge replay diagnostic:",model.gridStatus,"recoveries",model.alignmentRecoveries,"cal",String(describing:model.calibration))
            print(model.observation?.readings.filter{$0.occupancy != .empty}.map{"\($0.row),\($0.col):\($0.occupancy)"} ?? [])
            fatalError("Real-board UI replay failed")
        }
        model.frozen = true; model.cameraStatus = "Photo · saved edge-stone test"
        model.message = "Saved sample replay: white A4, black F1, 359 empty intersections. Live retest still required."
        try screenshot("edge-stones-fixed")
        func awaitGrid(_ target: ExperimentModel) {
            let deadline = Date().addingTimeInterval(10)
            while target.detectingGrid && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.05)) }
            guard !target.detectingGrid else { fatalError("Grid search timed out") }
        }
        model.resetCalibration()
        model.receive(realPhoto("empty-reference.png"))
        model.detectGrid(); awaitGrid(model)
        guard model.calibration != nil && model.corners.count == 4 && !model.hasReference else { fatalError("Automatic grid setup failed or assumed the board was empty") }
        model.captureReference(); settle()
        model.receive(realPhoto("frame.png")); settle()
        guard model.observation?.snapshot.stones.count == 2 && model.observation?.signature.contains(.uncertain) == false else { fatalError("Automatic calibration changed edge-stone results") }
        model.message = "Automatic grid calibration on the saved sample: white A4, black F1."
        try screenshot("automatic-grid")

        let automatic = ExperimentModel(discoverCameras:false,restoreViewSettings:false,referenceArchive:nil)
        automatic.receive(realPhoto("empty-reference.png")); awaitGrid(automatic)
        guard automatic.calibration != nil else { fatalError("First view did not automatically find the grid") }
        automatic.resetCalibration()
        automatic.detectGrid()
        let manualCorner = ImagePoint(x:0.25,y:0.1)
        automatic.addCorner(manualCorner)
        RunLoop.main.run(until:Date().addingTimeInterval(1))
        guard automatic.calibration == nil && automatic.corners.count == 1 && automatic.corners[0].x == manualCorner.x else { fatalError("Late auto result overwrote manual calibration") }
        automatic.resetCalibration()
        automatic.detectGrid()
        automatic.size = 9; automatic.boardSizeChanged(); awaitGrid(automatic)
        guard automatic.calibration == nil && automatic.corners.isEmpty else { fatalError("Stale size result or wrong-size calibration accepted") }
        automatic.stop()
        let failureURL=realFolder.deletingLastPathComponent().appendingPathComponent("GridOutlineFailure/frame.png")
        let failureSource=CGImageSourceCreateWithURL(failureURL as CFURL,nil)!
        model.resetCalibration()
        model.receive(CGImageSourceCreateImageAtIndex(failureSource,0,nil)!)
        model.detectGrid(); awaitGrid(model)
        guard model.calibration != nil && !model.hasReference else { fatalError("Clear-board failure did not recover through the model") }
        model.captureReference(); settle()
        guard model.observation?.signature.allSatisfy({ $0 == .empty }) == true else { fatalError("Recovered grid did not produce an empty reference") }
        model.cameraStatus = "Photo · saved grid-detection failure"
        model.message = "Previously rejected clear-board sample: grid found automatically, 361 empty intersections."
        try screenshot("automatic-grid-recovered")
        let offsetFolder=realFolder.deletingLastPathComponent().appendingPathComponent("WhiteEdgeOffset")
        let offsetSaved=try JSONDecoder().decode(CalibrationOnly.self,from:Data(contentsOf:offsetFolder.appendingPathComponent("sample.json")))
        func offsetPhoto(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(offsetFolder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        model.resetCalibration()
        model.receive(offsetPhoto("empty-reference.png"))
        for corner in offsetSaved.calibration.corners { model.addCorner(corner) }
        model.captureReference(); settle()
        model.receive(offsetPhoto("frame.png")); settle()
        guard let observation=model.observation,observation.snapshot.stones.count==4,
              observation.readings[14*19].occupancy == .white,
              observation.signature.filter({ $0 == .uncertain }).count <= 2 else { fatalError("Offset white edge stone UI replay failed") }
        model.cameraStatus = "Photo · latest edge-stone sample"
        model.message = "Saved sample: both white stones and both black stones recognized. Two empty points remain uncertain."
        try screenshot("white-edge-local")
        let flickerFolder=realFolder.deletingLastPathComponent().appendingPathComponent("CenterFlicker")
        let flickerSaved=try JSONDecoder().decode(CalibrationOnly.self,from:Data(contentsOf:flickerFolder.appendingPathComponent("sample.json")))
        func flickerPhoto(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(flickerFolder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        model.resetCalibration()
        model.receive(flickerPhoto("empty-reference.png"))
        for corner in flickerSaved.calibration.corners { model.addCorner(corner) }
        model.captureReference(); settle()
        model.receive(flickerPhoto("frame.png")); settle()
        guard model.observation?.snapshot.stones.count==9 && model.observation?.signature.contains(.uncertain)==false else { fatalError("Captured flicker not resolved in model") }
        model.cameraStatus="Photo · captured center-stone flicker"
        model.message="Captured flicker replay: 4 white, 5 black, 352 empty. Grid overlay leaves the stones clear."
        let unrotatedSGF=model.observation?.positionSGF()
        let unchangedCalibration=model.calibration
        guard model.rectifiedImage != nil else { fatalError("Calibrated frame was not rectified") }
        let rawBefore=model.image,referenceBefore=model.referenceImage
        let aspectBefore=model.rectifiedLongAxisRows
        let beforeWidth=model.rectifiedImage!.width,beforeHeight=model.rectifiedImage!.height
        print("Real sample automatic long axis: rows=\(aspectBefore), confident=\(model.aspectConfident)")
        model.swapLongSide(); settle()
        guard model.rectifiedImage?.width==beforeHeight && model.rectifiedImage?.height==beforeWidth,
              model.aspectOverridden else { fatalError("Optional long-side correction failed") }
        model.swapLongSide(); settle()
        model.straightenBoard=false; model.perspectiveViewChanged(); settle()
        guard model.rectifiedImage==nil && model.rectifiedGeometry==nil && model.image===rawBefore,
              model.referenceImage===referenceBefore && model.calibration==unchangedCalibration,
              model.observation?.positionSGF()==unrotatedSGF else { fatalError("View toggle altered recognition or raw frame") }
        try screenshot("perspective-original")
        model.straightenBoard=true; model.perspectiveViewChanged(); settle()
        model.estimateBoardAspect()
        guard model.rectifiedImage != nil && model.rectifiedLongAxisRows==aspectBefore else { fatalError("Correction toggle did not restore geometry") }
        try screenshot("center-flicker-fixed")
        model.rotateView()
        guard model.calibration==unchangedCalibration && model.hasReference && model.observation?.positionSGF()==unrotatedSGF else { fatalError("Display rotation changed calibration, baseline or SGF") }
        let rotatedSample=root.appendingPathComponent("RotatedSample-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:rotatedSample) }
        try model.saveSample(to:rotatedSample)
        let rotatedMetadata=try JSONSerialization.jsonObject(with:Data(contentsOf:rotatedSample.appendingPathComponent("sample.json"))) as! [String:Any]
        guard rotatedMetadata["displayQuarterTurns"] as? Int == 1,
              rotatedMetadata["width"] as? Int == 1920,
              rotatedMetadata["perspectiveCorrectedView"] as? Bool == true,
              try String(contentsOf:rotatedSample.appendingPathComponent("position.sgf"),encoding:.utf8)==unrotatedSGF else { fatalError("Rotated export changed source coordinates or omitted orientation") }
        try screenshot("rotated-camera")
        model.showGridOverlay=false
        try screenshot("rotated-no-grid")
        model.showGridOverlay=true
        for _ in 0..<3 { model.rotateView() }
        guard model.viewQuarterTurns==0 else { fatalError("Four turns did not restore orientation") }

        // Manual clicks are made in displayed TL/TR/BR/BL order, even after rotation.
        let oriented=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil)
        for turns in 0..<4 {
            oriented.resetCalibration(); oriented.receive(realPhoto("empty-reference.png"))
            let displayedOrder=oriented.orientation.displayedCorners(saved.calibration.corners)
            for point in displayedOrder { oriented.addCorner(point) }
            guard oriented.calibration?.corners==saved.calibration.corners else { fatalError("Manual calibration order incorrect at rotation \(turns)") }
            oriented.captureReference()
            let before=oriented.referenceImage
            oriented.rotateView()
            guard oriented.hasReference && oriented.referenceImage===before else { fatalError("Rotation discarded a reference") }
            oriented.undoCorner()
            guard oriented.corners.count==3 && oriented.calibration==nil && oriented.rectifiedImage==nil else { fatalError("Rotated Undo corner failed") }
        }
        oriented.stop()

        let retry=ExperimentModel(discoverCameras:false,restoreViewSettings:false,referenceArchive:nil)
        let blankBytes=[UInt8](repeating:200,count:1920*1080)
        let blank=CGImage(width:1920,height:1080,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:1920,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:Data(blankBytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        retry.running=true; retry.cameraState = .live; retry.frameCount=8
        retry.receive(blank); awaitGrid(retry)
        guard retry.calibration==nil && retry.lookingForGrid else { fatalError("Automatic grid search did not stay armed after a miss") }
        retry.receive(realPhoto("empty-reference.png"))
        guard !retry.detectingGrid && retry.calibration==nil else { fatalError("Automatic retry ignored its rate limit") }
        RunLoop.main.run(until:Date().addingTimeInterval(2.1))
        retry.receive(realPhoto("empty-reference.png")); awaitGrid(retry)
        guard retry.calibration != nil && !retry.hasReference else { fatalError("Automatic retry did not find the later clear board") }
        retry.resetCalibration(allowAutomatic:true)
        retry.toggleFreeze(); retry.toggleFreeze()
        retry.receive(realPhoto("empty-reference.png")); awaitGrid(retry)
        guard retry.calibration != nil else { fatalError("Resume did not rearm automatic grid search") }
        retry.resetCalibration()
        retry.receive(realPhoto("empty-reference.png"))
        guard !retry.detectingGrid && retry.calibration==nil else { fatalError("Manual mode was overridden by automatic scanning") }
        retry.stop()
        // A bumped camera changes current geometry, never the empty reference.
        let bumpFolder=realFolder.deletingLastPathComponent().appendingPathComponent("CameraBump")
        let bumpSaved=try JSONDecoder().decode(CalibrationOnly.self,from:Data(contentsOf:bumpFolder.appendingPathComponent("sample.json")))
        func bumpPhoto(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(bumpFolder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        model.resetCalibration(); model.receive(bumpPhoto("empty-reference.png"))
        for p in bumpSaved.calibration.corners { model.addCorner(p) }
        model.captureReference(); settle()
        let originalReference=model.referenceImage,originalReferenceCalibration=model.referenceCalibration
        let bumpFrame=bumpPhoto("frame.png")
        model.receive(bumpFrame); settle()
        guard model.alignmentRecoveries>0 && !model.alignmentNeedsRecovery,
              model.hasReference && model.referenceImage===originalReference,
              model.referenceCalibration==originalReferenceCalibration,
              model.calibration != originalReferenceCalibration,
              model.observation?.snapshot.stones.count==16,
              model.observation!.signature.filter({$0 == .uncertain}).count<=5 else { fatalError("Model did not recover the bumped camera while preserving its reference") }
        model.cameraStatus="Photo · recovered camera bump"
        model.message="Recovered alignment: all 16 stones recognized; \(model.observation!.signature.filter{$0 == .uncertain}.count) points remain uncertain."
        for _ in 0..<3 { model.rotateView() }
        try screenshot("camera-bump-recovered")
        let recovered=root.appendingPathComponent("RecoveredSample-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:recovered) }
        try model.saveSample(to:recovered)
        struct RecoverMetadata:Decodable {
            let schemaVersion:Int; let calibration:BoardCalibration; let referenceCalibration:BoardCalibration
            let alignmentNeedsRecovery:Bool
        }
        let recoveredData=try JSONDecoder().decode(RecoverMetadata.self,from:Data(contentsOf:recovered.appendingPathComponent("sample.json")))
        guard recoveredData.schemaVersion==3 && recoveredData.calibration==model.calibration,
              recoveredData.referenceCalibration==originalReferenceCalibration,
              !recoveredData.alignmentNeedsRecovery,
              !FileManager.default.fileExists(atPath:recovered.appendingPathComponent("position.sgf").path) else { fatalError("Recovered sample omitted its reference geometry or exported uncertain stones") }
        model.receive(blank); settle()
        guard model.alignmentNeedsRecovery && model.observation==nil && !model.stable,
              model.rectifiedImage != nil && model.referenceImage===originalReference else { fatalError("Obscured grid did not pause recognition while preserving presentation") }
        model.captureReference()
        guard model.referenceImage===originalReference else { fatalError("Paused tracking replaced the empty reference") }
        try screenshot("camera-bump-paused")
        let paused=root.appendingPathComponent("PausedSample-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:paused) }
        try model.saveSample(to:paused)
        let pausedData=try JSONDecoder().decode(RecoverMetadata.self,from:Data(contentsOf:paused.appendingPathComponent("sample.json")))
        guard pausedData.alignmentNeedsRecovery && !FileManager.default.fileExists(atPath:paused.appendingPathComponent("position.sgf").path) else { fatalError("Unaligned frame exported a position") }
        model.receive(bumpFrame); settle()
        guard !model.alignmentNeedsRecovery && model.observation?.snapshot.stones.count==16 else { fatalError("Clear frame did not resume recovery") }
        model.receive(blank); model.resetCalibration(); settle()
        guard model.calibration==nil && model.referenceCalibration==nil && !model.hasReference && model.rectifiedImage==nil else { fatalError("In-flight tracking survived calibration reset") }
                // Start directly on an occupied board, with no reference or prior history.
        let occupiedFolder=realFolder.deletingLastPathComponent().appendingPathComponent("OccupiedTracking")
        let occupiedSource=CGImageSourceCreateWithURL(occupiedFolder.appendingPathComponent("frame.png") as CFURL,nil)!
        let occupiedPhoto=CGImageSourceCreateImageAtIndex(occupiedSource,0,nil)!
        model.resetCalibration(); model.frozen=false
        model.receive(occupiedPhoto); model.detectGrid(); awaitGrid(model); settle()
        model.running=true; model.cameraState = .live
        for _ in 0..<7 { model.receive(occupiedPhoto); settle() }
        guard !model.hasReference && !model.automaticReference && model.referenceImage==nil,
              !model.alignmentNeedsRecovery && model.observation?.snapshot.stones.count==21 else { fatalError("Occupied startup required a reference, learned stones as background, or entered the recovery loop") }
        model.frozen=true; model.cameraStatus="Photo · occupied board, no empty reference"
        model.message="21 stones detected without a reference. Orange points remain uncertain."
        try screenshot("occupied-no-reference")
        let noRef=root.appendingPathComponent("NoReferenceSample-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:noRef) }
        try model.saveSample(to:noRef)
        let noRefData=try JSONSerialization.jsonObject(with:Data(contentsOf:noRef.appendingPathComponent("sample.json"))) as! [String:Any]
        guard noRefData["detectionMode"] as? String == "localAppearance",
              noRefData["automaticReference"] as? Bool == false,
              !FileManager.default.fileExists(atPath:noRef.appendingPathComponent("empty-reference.png").path) else { fatalError("Reference-free sample export is incorrect") }
        let replay=BoardAppearanceDetector.detect(frame:GrayFrame(image:model.image!)!,calibration:model.calibration!,threshold:model.threshold)
        guard replay.signature==model.observation?.signature else { fatalError("Reference-free sample cannot be replayed") }
        model.stop()

        // Repeated fresh, visibly empty frames can promote themselves to a baseline.
        let autoReferenceModel=ExperimentModel(discoverCameras:false,restoreViewSettings:false,referenceArchive:nil)
        let clearPhoto=flickerPhoto("empty-reference.png")
        autoReferenceModel.receive(clearPhoto); awaitGrid(autoReferenceModel); settle()
        guard autoReferenceModel.observation?.signature.allSatisfy({$0 == .empty}) == true && !autoReferenceModel.hasReference else { fatalError("Empty-board hypothesis not established independently") }
        autoReferenceModel.running=true; autoReferenceModel.cameraState = .live
        for _ in 0..<6 { autoReferenceModel.receive(clearPhoto); settle() }
        guard autoReferenceModel.hasReference && autoReferenceModel.automaticReference && autoReferenceModel.referenceImage===clearPhoto else { fatalError("Verified empty board did not capture its own reference") }
        autoReferenceModel.useWithoutReference(); settle()
        for _ in 0..<6 { autoReferenceModel.receive(clearPhoto); settle() }
        guard !autoReferenceModel.hasReference && !autoReferenceModel.automaticReference else { fatalError("Explicit reference-free mode recaptured a baseline") }
        autoReferenceModel.stop()
                let grainFolder=realFolder.deletingLastPathComponent().appendingPathComponent("GrainedWhite")
        let grainCal=try JSONDecoder().decode(CalibrationOnly.self,from:Data(contentsOf:grainFolder.appendingPathComponent("sample.json")))
        let grainSource=CGImageSourceCreateWithURL(grainFolder.appendingPathComponent("frame.png") as CFURL,nil)!
        let grainImage=CGImageSourceCreateImageAtIndex(grainSource,0,nil)!
        model.resetCalibration()
        while model.viewQuarterTurns != 0 { model.rotateView() }
        model.receive(grainImage)
        for p in grainCal.calibration.corners { model.addCorner(p) }
        settle()
        guard !model.hasReference && model.observation?.snapshot.stones.count==21,
              model.observation?.readings[16*19+7].occupancy == .white,
              model.observation!.signature.filter({$0 == .uncertain}).count<=10 else { fatalError("Grained white stone failed in the model") }
        for _ in 0..<3 { model.rotateView() }
        model.cameraStatus="Photo · grained white stone"
        model.message="21 stones recognized. 10 empty intersections remain uncertain."
        try screenshot("grained-white-fixed")
        // A real camera nudge exceeds local tracking but the complete grid remains visible.
        let movedFolder=realFolder.deletingLastPathComponent().appendingPathComponent("LargeCameraMove")
        let movedSource=CGImageSourceCreateWithURL(movedFolder.appendingPathComponent("frame.png") as CFURL,nil)!
        let movedImage=CGImageSourceCreateImageAtIndex(movedSource,0,nil)!
        let beforeMove=model.calibration!
        model.frozen=false; model.running=true; model.cameraState = .live
        for _ in 0..<3 { model.receive(movedImage); settle() }
        awaitGrid(model); settle()
        guard !model.alignmentNeedsRecovery, model.alignmentRecoveries == 1,
              model.calibration != beforeMove, model.observation != nil,
              model.gridStatus.contains("full-view search"), !model.hasReference else {
            fatalError("Large camera movement did not escalate and recover automatically")
        }
        // Independently marked outer intersections in the raw saved frame, within 0.25 spacing.
        let expectedCorners=[ImagePoint(x:453.0/1920,y:82.0/1080),ImagePoint(x:1432.0/1920,y:35.0/1080),
                             ImagePoint(x:1601.0/1920,y:988.0/1080),ImagePoint(x:385.0/1920,y:1042.0/1080)]
        for (actual,expected) in zip(model.calibration!.corners,expectedCorners) {
            guard hypot((actual.x-expected.x)*1920,(actual.y-expected.y)*1080)<15 else {
                fatalError("Full-view recovery selected the wrong outer grid")
            }
        }
        print("Large-move recovery: \(model.observation!.snapshot.stones.count) stones, \(model.observation!.signature.filter({$0 == .uncertain}).count) uncertain")
        let recoveredCalibration=model.calibration
        for _ in 0..<4 { model.receive(movedImage); settle() }
        guard !model.alignmentNeedsRecovery, model.alignmentRecoveries == 1,
              model.calibration == recoveredCalibration else { fatalError("Recovered grid immediately reentered recovery") }
        model.cameraStatus="Photo · larger camera move recovered automatically"
        try screenshot("large-camera-move-recovered")

        // An occluded board cannot be acquired: retry only on fresh live frames, then stop.
        for _ in 0..<3 { model.receive(blank); settle() }
        awaitGrid(model); settle()
        guard model.alignmentNeedsRecovery, model.recoverySearchAttempts == 1,
              model.observation == nil, model.rectifiedImage != nil else { fatalError("First broad recovery attempt lost presentation or accepted unverified evidence") }
        for expectedAttempt in 2...3 {
            RunLoop.main.run(until:Date().addingTimeInterval(2.1))
            model.analyze(); settle()
            guard model.recoverySearchAttempts == expectedAttempt-1 else { fatalError("A redraw retried recovery without a fresh camera frame") }
            model.receive(blank); settle(); awaitGrid(model); settle()
            guard model.recoverySearchAttempts == expectedAttempt else { fatalError("Full-view recovery retry count is incorrect") }
        }
        guard model.recoverySearchExhausted, model.gridIndicator == "Grid needs attention",
              model.calibration == recoveredCalibration, model.observation == nil else { fatalError("Failed recovery never stopped or changed the calibration") }
        try screenshot("large-camera-move-needs-attention")
        RunLoop.main.run(until:Date().addingTimeInterval(2.1))
        model.receive(blank); settle()
        guard model.recoverySearchAttempts == 3, !model.detectingGrid else { fatalError("Recovery exceeded its retry budget") }
        model.toggleFreeze(); settle()
        guard model.gridIndicator == "Grid recovery paused" else { fatalError("Frozen recovery still claims to be working") }
        model.toggleFreeze(); settle(); model.receive(movedImage); settle()
        guard !model.alignmentNeedsRecovery, !model.recoverySearchExhausted,
              model.observation != nil else { fatalError("Restoring the aligned view did not resume detection") }
        // A canceled full-frame result must not resurrect the old calibration.
        model.detectGrid(recovering:true); model.resetCalibration(); settle()
        guard model.calibration == nil, model.recoverySearchAttempts == 0,
              !model.detectingGrid, model.observation == nil else { fatalError("Canceled recovery applied its result") }
        // A shadow beside an occupied cluster must not become an extra black stone.
        let shadowFolder=realFolder.deletingLastPathComponent().appendingPathComponent("FalseBlack")
        let shadowCal=try JSONDecoder().decode(CalibrationOnly.self,from:Data(contentsOf:shadowFolder.appendingPathComponent("sample.json")))
        let shadowSource=CGImageSourceCreateWithURL(shadowFolder.appendingPathComponent("frame.png") as CFURL,nil)!
        let shadowImage=CGImageSourceCreateImageAtIndex(shadowSource,0,nil)!
        while model.viewQuarterTurns != 0 { model.rotateView() }
        model.receive(shadowImage)
        for p in shadowCal.calibration.corners { model.addCorner(p) }
        settle()
        guard model.observation?.snapshot.stones.count == 21,
              model.observation?.readings[14*19+15].occupancy == .uncertain else {
            fatalError("Shadow still became an extra black stone in the app")
        }
        for _ in 0..<3 { model.rotateView() }
        model.cameraStatus="Photo · false black candidate removed"
        model.message="21 real stones detected. The shadowed empty point remains uncertain."
        try screenshot("false-black-fixed")
        // Reference-backed, near-wood-brightness white stone displaced toward a neighbor.
        let referenceOffsetFolder=realFolder.deletingLastPathComponent().appendingPathComponent("ReferenceOffset")
        struct ReferenceOffsetMetadata:Decodable { let referenceCalibration:BoardCalibration }
        let referenceOffsetMeta=try JSONDecoder().decode(ReferenceOffsetMetadata.self,from:Data(contentsOf:referenceOffsetFolder.appendingPathComponent("sample.json")))
        func referenceOffsetPhoto(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(referenceOffsetFolder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        model.resetCalibration()
        while model.viewQuarterTurns != 0 { model.rotateView() }
        model.receive(referenceOffsetPhoto("empty-reference.png"))
        for p in referenceOffsetMeta.referenceCalibration.corners { model.addCorner(p) }
        settle(); model.captureReference(); settle()
        model.receive(referenceOffsetPhoto("frame.png")); settle()
        guard model.hasReference, !model.alignmentNeedsRecovery,
              model.observation?.snapshot.stones.count == 20,
              model.observation?.readings[13*19+17].occupancy == .white,
              model.observation!.signature.filter({$0 == .uncertain}).count <= 5 else {
            fatalError("Reference-backed offset white stone failed in the app")
        }
        for _ in 0..<3 { model.rotateView() }
        model.cameraStatus="Photo · off-center white stone with reference"
        model.message="20 stones recognized, including the off-center white stone. \(model.observation!.signature.filter{$0 == .uncertain}.count) points remain uncertain."
        try screenshot("reference-offset-fixed")
        let multipleFolder=realFolder.deletingLastPathComponent().appendingPathComponent("MultipleDisplaced")
        let multipleMeta=try JSONDecoder().decode(ReferenceOffsetMetadata.self,from:Data(contentsOf:multipleFolder.appendingPathComponent("sample.json")))
        func multiplePhoto(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(multipleFolder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        model.resetCalibration()
        while model.viewQuarterTurns != 0 { model.rotateView() }
        model.receive(multiplePhoto("empty-reference.png"))
        for p in multipleMeta.referenceCalibration.corners { model.addCorner(p) }
        settle(); model.captureReference(); settle()
        model.receive(multiplePhoto("frame.png")); settle()
        guard model.hasReference, !model.alignmentNeedsRecovery,
              model.observation?.snapshot.stones.count==21,
              model.observation!.signature.filter({$0 == .uncertain}).count<=8 else { fatalError("Displaced neighbors regression in the app") }
        for _ in 0..<3 { model.rotateView() }
        model.cameraStatus="Photo · multiple displaced stones"
        model.message="21 stones correctly assigned. \(model.observation!.signature.filter{$0 == .uncertain}.count) uncertain points remain."
        try screenshot("multiple-displaced-fixed")
        let round2Folder=realFolder.deletingLastPathComponent().appendingPathComponent("DisplacedRound2")
        let round2Meta=try JSONDecoder().decode(ReferenceOffsetMetadata.self,from:Data(contentsOf:round2Folder.appendingPathComponent("sample.json")))
        func round2Photo(_ name:String)->CGImage {
            let source=CGImageSourceCreateWithURL(round2Folder.appendingPathComponent(name) as CFURL,nil)!
            return CGImageSourceCreateImageAtIndex(source,0,nil)!
        }
        model.resetCalibration()
        while model.viewQuarterTurns != 0 { model.rotateView() }
        model.receive(round2Photo("empty-reference.png"))
        for p in round2Meta.referenceCalibration.corners { model.addCorner(p) }
        settle(); model.captureReference(); settle()
        model.receive(round2Photo("frame.png")); settle()
        guard model.hasReference, !model.alignmentNeedsRecovery,
              model.observation?.snapshot.stones.count==21,
              model.observation?.readings[14*19+18].occupancy == .empty,
              model.observation!.signature.filter({$0 == .uncertain}).count<=8,
              model.observation!.footprints.count==21 else { fatalError("Geometry inference failed in the app") }
        model.cameraStatus="Photo · stone outlines and possible occupancy"
        model.message="All 21 stones recognized. Row 14, column 18 is empty; 8 points remain uncertain."
        try screenshot("geometry-raw-orientation")
        for _ in 0..<3 { model.rotateView() }
        try screenshot("geometry-player-orientation")
        let geometryFolder=root.appendingPathComponent("GeometrySample-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:geometryFolder) }
        try model.saveSample(to:geometryFolder)
        let geometryData=try JSONSerialization.jsonObject(with:Data(contentsOf:geometryFolder.appendingPathComponent("sample.json"))) as! [String:Any]
        guard (geometryData["stoneFootprints"] as? [[String:Any]])?.count==21 else { fatalError("Footprint diagnostics omitted from sample") }
        let signature=model.observation!.signature
        model.showStoneOutlines=false; settle()
        guard model.observation!.signature==signature else { fatalError("Outline visibility changed recognition") }
        // A saved occupied frame must be referenceReplayed with its distinct empty baseline.
        let archiveFolder=root.appendingPathComponent("ReferenceArchive-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:archiveFolder) }
        let archive=ReferenceArchive(url:archiveFolder.appendingPathComponent("reference.plist"))
        let referenceReplay=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:archive)
        referenceReplay.cameras=[.init(id:"fixture-camera",name:"FULL HD WEB CAM")]; referenceReplay.cameraID="fixture-camera"
        try referenceReplay.openSample(from:round2Folder); settle()
        guard referenceReplay.frozen, referenceReplay.hasReference, referenceReplay.observation?.signature == signature,
              referenceReplay.viewQuarterTurns == 3, referenceReplay.referenceImage !== referenceReplay.image else { fatalError("Opening sample changed its classification or replaced the empty baseline with stones") }
        let persisted=try archive.load()!
        guard persisted.enabled,persisted.cameraID == "fixture-camera",
              persisted.referenceCalibration == round2Meta.referenceCalibration,
              GrayFrame(image:persisted.image)!.pixels == GrayFrame(image:round2Photo("empty-reference.png"))!.pixels else {
            fatalError("Persisted reference changed pixels, calibration, or camera identity")
        }
        referenceReplay.prepareCameraStart()
        guard referenceReplay.hasReference,referenceReplay.awaitingReferenceFrame,referenceReplay.image == nil,referenceReplay.observation == nil else { fatalError("Camera restart discarded the baseline or displayed stale detection") }
        referenceReplay.handleCameraStatus("Live",state:.live)
        referenceReplay.analyze(); settle()
        guard referenceReplay.awaitingReferenceFrame,referenceReplay.observation == nil else { fatalError("Validated reference without a fresh frame") }
        referenceReplay.receive(round2Photo("frame.png")); settle()
        guard !referenceReplay.awaitingReferenceFrame,referenceReplay.hasReference,referenceReplay.observation?.signature == signature else { fatalError("Fresh occupied frame could not reuse saved reference") }
        referenceReplay.handleCameraStatus("Reconnecting",state:.recovering)
        guard referenceReplay.hasReference,referenceReplay.awaitingReferenceFrame,referenceReplay.observation == nil else { fatalError("Reconnect lost baseline") }
        referenceReplay.handleCameraStatus("Live",state:.live); referenceReplay.receive(round2Photo("frame.png")); settle()
        guard referenceReplay.observation?.signature == signature else { fatalError("Reconnect changed classification") }
        referenceReplay.stop()
        let relaunched=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:archive)
        guard relaunched.hasReference,relaunched.awaitingReferenceFrame,relaunched.image == nil,
              relaunched.referenceCalibration == referenceReplay.referenceCalibration else { fatalError("App relaunch did not restore paired reference/calibration") }
        relaunched.cameras=referenceReplay.cameras; relaunched.cameraID="fixture-camera"
        relaunched.prepareCameraStart(); relaunched.handleCameraStatus("Live",state:.live)
        relaunched.receive(round2Photo("frame.png")); settle()
        guard relaunched.observation?.signature == signature else { fatalError("App relaunch changed referenceReplay recognition") }
        // A malformed import fails before it can replace the working session or archive.
        let broken=archiveFolder.appendingPathComponent("broken")
        try FileManager.default.createDirectory(at:broken,withIntermediateDirectories:true)
        try Data("{}".utf8).write(to:broken.appendingPathComponent("sample.json"))
        let beforeBroken=relaunched.referenceImage
        do { try relaunched.openSample(from:broken); fatalError("Accepted a sample without a reference") }
        catch ReferenceArchive.ArchiveError.noReference { }
        guard relaunched.referenceImage === beforeBroken,relaunched.observation?.signature == signature else { fatalError("Broken import damaged active session") }
        relaunched.useWithoutReference(); settle()
        guard try archive.load()?.enabled == false else { fatalError("Reference opt-out was not persisted") }
        let optedOut=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:archive)
        guard !optedOut.hasReference else { fatalError("Relaunch ignored reference opt-out") }
        relaunched.stop()
        try referenceReplay.openSample(from:round2Folder); settle()
        referenceReplay.cameraID="different-camera"; referenceReplay.prepareCameraStart()
        guard !referenceReplay.hasReference,referenceReplay.calibration == nil,try archive.load()?.enabled == false else { fatalError("Reused baseline for a different camera") }
        referenceReplay.stop()
        try referenceReplay.openSample(from:round2Folder); settle()
        referenceReplay.prepareCameraStart(); referenceReplay.handleCameraStatus("Live",state:.live)
        let resized=round2Photo("frame.png").cropping(to:CGRect(x:0,y:0,width:1000,height:800))!
        referenceReplay.receive(resized); settle()
        guard !referenceReplay.hasReference,referenceReplay.calibration == nil else { fatalError("Reused baseline with different frame dimensions") }
        referenceReplay.stop()
        // Current and reference calibration are separate, including after a bump.
        let shifted=BoardCalibration(size:19,corners:round2Meta.referenceCalibration.corners.map{ImagePoint(x:$0.x+0.001,y:$0.y)})!
        try archive.save(image:round2Photo("empty-reference.png"),referenceCalibration:round2Meta.referenceCalibration,
            calibration:shifted,cameraID:"fixture-camera",cameraName:"FULL HD WEB CAM")
        let shiftedSaved=try archive.load()!
        guard shiftedSaved.calibration == shifted,shiftedSaved.referenceCalibration == round2Meta.referenceCalibration else { fatalError("Archive conflated original and tracked calibration") }
        try Data("not a reference".utf8).write(to:archive.url,options:.atomic)
        let corrupt=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:archive)
        guard !corrupt.hasReference,corrupt.message.contains("Could not restore") else { fatalError("Corrupt archive was silently accepted") }
        print("PASS: identical saved-frame referenceReplay, lossless paired reference persistence, fresh-frame validation, camera reconnect, app relaunch, malformed import, opt-out, camera/dimension mismatch, and corrupt archive recovery.")
        // Exercise actual image -> model analysis -> recorder, without activating hardware.
        let recordingModel=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        recordingModel.soundMode = .off
        recordingModel.tracksCameraMotion=false
        let straight=[ImagePoint(x:0.1,y:0.1),ImagePoint(x:0.9,y:0.1),ImagePoint(x:0.9,y:0.9),ImagePoint(x:0.1,y:0.9)]
        let syntheticCal=BoardCalibration(size:19,corners:straight)!
        func recordingFrame(_ stones:[(Int,Int,UInt8)])->CGImage {
            let side=720
            var pixels=[UInt8](repeating:160,count:side*side)
            for (row,col,color) in stones {
                let point=syntheticCal.point(col:Double(col),row:Double(row))
                let x=point.x*Double(side-1),y=point.y*Double(side-1),radius=14.0
                for j in Int(y-radius)...Int(y+radius) { for i in Int(x-radius)...Int(x+radius) where hypot(Double(i)-x,Double(j)-y)<radius { pixels[j*side+i]=color } }
            }
            return CGImage(width:side,height:side,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:side,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:Data(pixels) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        }
        let recordingEmpty=recordingFrame([]),recordingBlack=recordingFrame([(9,9,22)]),recordingWhite=recordingFrame([(9,9,22),(9,10,241)])
        recordingModel.receive(recordingEmpty)
        for point in straight { recordingModel.addCorner(point) }; settle()
        recordingModel.captureReference(); settle()
        recordingModel.handleCameraStatus("Live · synthetic recorder test",state:.live)
        func feedRecording(_ frame:CGImage,frames:Int=6) {
            for _ in 0..<frames { recordingModel.receive(frame); RunLoop.main.run(until:Date().addingTimeInterval(0.3)) }
        }
        guard !recordingModel.liveBoardReady,!recordingModel.canStartNewRecording else {fatalError("Stored/manual grid enabled Record before a live verification")}
        recordingModel.startRecording()
        guard !recordingModel.recorder.hasGame else {fatalError("Start bypassed readiness")}
        feedRecording(recordingEmpty,frames:1)
        guard recordingModel.liveBoardReady,!recordingModel.canStartNewRecording else {fatalError("A single frame armed a new recording")}
        feedRecording(recordingEmpty)
        guard recordingModel.canStartNewRecording else {fatalError("Verified empty live board did not enable Record")}
        RunLoop.main.run(until:Date().addingTimeInterval(1.1))
        guard !recordingModel.canStartNewRecording else {fatalError("Stale camera frame enabled Record")}
        feedRecording(recordingEmpty)
        host.rootView=ExperimentView(model:recordingModel).frame(width:1280,height:940)
        try screenshot("recorder-ready")
        recordingModel.startRecording() // Reuse the just-verified empty camera view.
        guard recordingModel.recorder.state == .recording else { fatalError("Native recorder did not verify empty board") }
        feedRecording(recordingBlack)
        guard recordingModel.recorder.moveCount==1 else { fatalError("Native image pipeline failed to record Black") }
        host.rootView=ExperimentView(model:recordingModel).frame(width:1280,height:940)
        try screenshot("recorder-active-transport")
        feedRecording(recordingWhite)
        guard recordingModel.recorder.moveCount==2 else { fatalError("Native image pipeline failed to record White") }
        recordingModel.recorder.seek(1)
        feedRecording(recordingWhite)
        guard recordingModel.recorder.reviewIndex==1,recordingModel.recorder.moveCount==2,recordingModel.recorder.reviewedBoard?.stones.count==1 else { fatalError("Live frames corrupted move review") }
        host.rootView=ExperimentView(model:recordingModel).frame(width:1280,height:940)
        try screenshot("recorder-review")
        recordingModel.recorder.seek(2);feedRecording(recordingWhite)
        guard recordingModel.canResumeRecording,!recordingModel.canStartNewRecording else {fatalError("Resume required an empty board or new recording allowed occupied start")}
        recordingModel.resumeRecording();feedRecording(recordingWhite)
        guard recordingModel.recorder.canPass else { fatalError("Native resume did not synchronize accepted board") }
        recordingModel.toggleFreeze()
        guard !recordingModel.recorder.canPass,!recordingModel.liveBoardReady,recordingModel.recorder.moveCount==2 else { fatalError("Frozen camera retained active recording evidence") }
        recordingModel.toggleFreeze(); feedRecording(recordingWhite)
        recordingModel.recorder.pass(); recordingModel.recorder.pass()
        guard recordingModel.recorder.state == .finished,recordingModel.recorder.moveCount==4 else { fatalError("Native pass handling failed") }
        try screenshot("recorder-finished")
        let recorded=SGFGame.from(tree:try SGFParser.parse(text:recordingModel.recorder.sgf()))
        guard recorded.moves.count==4,recorded.moves[0].1?.0==9,recorded.moves[1].1?.0==10 else { fatalError("Native recorder SGF has wrong move order or coordinates") }
        recordingModel.startRecording()
        feedRecording(recordingWhite)
        guard recordingModel.recorder.state == .finished,recordingModel.recorder.moveCount==4,
              !recordingModel.canStartNewRecording,recordingModel.recordingReadiness.contains("2 possible stones") else { fatalError("Occupied starting board bypassed readiness or discarded the saved game") }
        try screenshot("recorder-not-ready")
        feedRecording(recordingEmpty)
        recordingModel.startRecording()
        guard recordingModel.recorder.state == .recording else { fatalError("Native catch-up setup failed") }
        feedRecording(recordingWhite); feedRecording(recordingWhite)
        guard recordingModel.recorder.moveCount==2,recordingModel.recorder.positions[1].stones.count==1,
              recordingModel.recorder.positions[1].grid[9][9] == .black else { fatalError("Native image pipeline did not recover two moves in turn order") }
        recordingModel.recorder.seek(1)
        try screenshot("recorder-pair-review")
        feedRecording(recordingEmpty)
        recordingModel.startRecording()
        let rapidStones:[(Int,Int,UInt8)]=[(9,9,22),(9,10,241),(11,11,22),(11,12,241)]
        for count in 1...4 {
            feedRecording(recordingFrame(Array(rapidStones.prefix(count))),frames:2)
            if count==3 {
                guard recordingModel.recorder.moveCount>0,recordingModel.recorder.pendingMoveCount>0 else {fatalError("Native rapid play did not save the confirmed prefix")}
            }
        }
        feedRecording(recordingFrame(rapidStones))
        guard recordingModel.recorder.moveCount==4,recordingModel.recorder.pendingMoveCount==0 else {fatalError("Native rapid four-move sequence stalled")}
        recordingModel.recorder.seek(2)
        guard recordingModel.recorder.reviewedBoard?.stones.count==2 else {fatalError("Native rapid history cannot be reviewed")}
        try screenshot("recorder-rapid-review")
        recordingModel.stop()
        guard !recordingModel.recordingControlReady else {fatalError("Stopped camera still enabled Record")}
        print("PASS: shared Record/Resume readiness, fresh live grid, empty-board preflight, occupied-start rejection, stale/frozen/stopped cameras, and native UI.")
        print("PASS: native image recognition -> stable move acceptance -> review/pause/resume -> freeze -> passes -> SGF export; review and finished-game screenshots.")
        // A stationary lighting shadow can block automatic empty-board verification.
        // Explicit empty-board confirmation captures a baseline, never bypassing
        // the subsequent fresh-frame checks or starting a game on its own.
        let shadowStartup=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        shadowStartup.tracksCameraMotion=false;shadowStartup.soundMode = .off
        shadowStartup.receive(recordingEmpty)
        for point in straight {shadowStartup.addCorner(point)};settle()
        shadowStartup.captureReference();settle()
        shadowStartup.handleCameraStatus("Live · startup shadow test",state:.live)
        let shadowSide=720
        var shadowPixels=[UInt8](repeating:160,count:shadowSide*shadowSide)
        for y in 300..<345 {for x in 285..<415 {shadowPixels[y*shadowSide+x]=85}}
        let startupShadowImage=CGImage(width:shadowSide,height:shadowSide,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:shadowSide,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:Data(shadowPixels) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        func feedShadow(_ frames:Int=6) {
            for _ in 0..<frames {shadowStartup.receive(startupShadowImage);RunLoop.main.run(until:Date().addingTimeInterval(0.3))}
        }
        feedShadow()
        guard !shadowStartup.canStartNewRecording,shadowStartup.canCaptureStartupReference,
              shadowStartup.recordingReadinessTitle=="Not ready to record",
              shadowStartup.recordingReadiness.contains("uncertain") || shadowStartup.recordingReadiness.contains("possible") else {fatalError("Shadow-blocked startup did not explain its readings and offer empty reference capture")}
        host.rootView=ExperimentView(model:shadowStartup).frame(width:1280,height:940)
        try screenshot("recorder-shadow-not-ready")
        shadowStartup.captureStartupReference()
        guard !shadowStartup.canStartNewRecording,!shadowStartup.recorder.hasGame else {fatalError("Manual baseline bypassed fresh verification or started recording")}
        feedShadow()
        guard shadowStartup.canStartNewRecording,shadowStartup.startupReferenceCaptured,!shadowStartup.canCaptureStartupReference,shadowStartup.showsStartupReferenceControl,shadowStartup.recordingReadinessTitle=="Ready to record",!shadowStartup.recorder.hasGame else {fatalError("Captured shadow baseline did not reach Ready without starting the recorder")}
        try screenshot("recorder-shadow-ready")
        shadowStartup.startRecording()
        guard shadowStartup.recorder.state == .recording,shadowStartup.recorder.moveCount==0,!shadowStartup.canCaptureStartupReference else {fatalError("Confirmed empty baseline did not start an empty game or remained available mid-game")}
        shadowStartup.stop()
        print("PASS: shadow-blocked startup explanation, explicit empty-reference fallback, fresh verification, and no automatic recording or mid-game baseline replacement.")
        // Persistent, nonmodal failure feedback remains visible over the camera.
        let warningModel=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        warningModel.soundMode = .off
        warningModel.receive(recordingWhite)
        warningModel.handleCameraStatus("Live · synthetic unsaved-move warning",state:.live)
        warningModel.recorder.start(size:19)
        var warningTime=0.0
        func warningFrames(_ readings:[Occupancy],_ count:Int) {
            for _ in 0..<count {
                warningTime += 0.21
                warningModel.recorder.consume(BoardObservation(readings:readings.enumerated().map{i,v in IntersectionReading(row:i/19,col:i%19,occupancy:v,confidence:1,delta:0)},size:19),now:warningTime)
            }
        }
        var warningBoard=[Occupancy](repeating:.empty,count:361)
        warningFrames(warningBoard,5)
        warningBoard[9*19+9] = .black;warningFrames(warningBoard,5)
        warningBoard[9*19+10] = .white
        for i in 20..<72 {warningBoard[i] = .uncertain}
        warningFrames(warningBoard,14)
        guard warningModel.recorder.needsAttention,warningModel.recorder.moveCount==1,
              warningModel.recorder.unsavedStoneCount==1 else {fatalError("Persistent warning did not reflect an observed but unsaved White move")}
        host.rootView=ExperimentView(model:warningModel).frame(width:1280,height:940)
        try screenshot("recorder-unsaved-warning")
        warningModel.stop()
        print("PASS: persistent nonmodal unsaved-move warning, last saved count, camera overlay, and muted-sound indicator.")
        // Replay real board pixels with deliberate sub-cell camera translations.
        // This is a manufactured two-move sequence, not an inferred history of the sample.
        let jitterModel=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        jitterModel.soundMode = .off
        let stalledFolder=realFolder.deletingLastPathComponent().appendingPathComponent("RecordingStalled")
        let stalled=try ReferenceArchive.readSample(stalledFolder)
        let emptyGray=GrayFrame(image:stalled.reference.image)!,occupiedGray=GrayFrame(image:stalled.frame!)!
        let cal=stalled.reference.referenceCalibration
        func stagedFrame(_ points:[BoardPosition],dx:Int=0)->CGImage {
            let width=emptyGray.width,height=emptyGray.height
            var pixels=emptyGray.pixels
            for point in points {
                let center=cal.point(col:Double(point.col),row:Double(point.row))
                let across=cal.point(col:Double(point.col)+1,row:Double(point.row))
                let down=cal.point(col:Double(point.col),row:Double(point.row)+1)
                let radius=Int(0.85*max(hypot((across.x-center.x)*Double(width),(across.y-center.y)*Double(height)),hypot((down.x-center.x)*Double(width),(down.y-center.y)*Double(height))))
                let cx=Int(center.x*Double(width-1)),cy=Int(center.y*Double(height-1))
                for y in max(0,cy-radius)...min(height-1,cy+radius) { for x in max(0,cx-radius)...min(width-1,cx+radius) {
                    pixels[y*width+x]=occupiedGray.pixels[y*width+x]
                } }
            }
            if dx != 0 {
                let original=pixels
                for y in 0..<height { for x in 0..<width { pixels[y*width+x]=original[y*width+min(width-1,max(0,x-dx))] } }
            }
            return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:Data(pixels) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        }
        let clearBoard=stagedFrame([])
        jitterModel.receive(clearBoard)
        for point in cal.corners { jitterModel.addCorner(point) }; settle()
        jitterModel.captureReference(); settle()
        jitterModel.handleCameraStatus("Live · real-image camera jitter test",state:.live)
        for _ in 0..<6 { jitterModel.receive(clearBoard); RunLoop.main.run(until:Date().addingTimeInterval(0.4)) }
        jitterModel.startRecording()
        guard jitterModel.recorder.state == .recording else { fatalError("Real-image recorder failed to arm") }
        let black=BoardPosition(9,3),white=BoardPosition(15,9)
        for points in [[black],[black,white]] {
            for dx in [0,3,-3,2,-2,3,-3,0,2,-2] {
                jitterModel.receive(stagedFrame(points,dx:dx)); RunLoop.main.run(until:Date().addingTimeInterval(0.45))
            }
            guard jitterModel.recorder.moveCount==points.count else {
                print("Jitter diagnostics:",jitterModel.recorder.status,jitterModel.gridStatus,"corrections",jitterModel.alignmentRecoveries)
                print(jitterModel.observation?.readings.filter{$0.occupancy != .empty}.map{"\($0.row),\($0.col):\($0.occupancy)"} ?? [])
                fatalError("Verified camera corrections starved move recording")
            }
        }
        guard jitterModel.alignmentRecoveries>=2 else { fatalError("Camera jitter replay did not exercise grid corrections") }
        jitterModel.interfaceScale=1.4
        host.rootView=ExperimentView(model:jitterModel).frame(width:1280,height:940)
        try screenshot("recorder-large-text")
        guard jitterModel.interfaceScale==1.4 else { fatalError("Text scale did not update") }
        jitterModel.resizeText(1); guard jitterModel.interfaceScale==1.5 else { fatalError("Text scale upper bound failed") }
        jitterModel.resizeText(-2); guard jitterModel.interfaceScale==0.9 else { fatalError("Text scale lower bound failed") }
        // Confirm the native layout exposes a split view, rather than a fixed-width controls column.
        func hasSplit(_ view:NSView)->Bool { view is NSSplitView || view.subviews.contains(where:hasSplit) }
        guard hasSplit(host) else { fatalError("Controls divider is not resizable") }
        jitterModel.stop()
        print("PASS: actual saved-board pixels, translated grid corrections, two recorded moves, adjustable font limits, and native split view.")
        // Reference-free occupied-board recovery must use raw stone shapes for display aspect.
        let aspectModel=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        let aspectFolder=realFolder.deletingLastPathComponent().appendingPathComponent("LongSideBump")
        let aspectMeta=try JSONDecoder().decode(CalibrationOnly.self,from:Data(contentsOf:aspectFolder.appendingPathComponent("sample.json")))
        let aspectSource=CGImageSourceCreateWithURL(aspectFolder.appendingPathComponent("frame.png") as CFURL,nil)!
        let aspectImage=CGImageSourceCreateImageAtIndex(aspectSource,0,nil)!
        aspectModel.receive(aspectImage)
        for corner in aspectMeta.calibration.corners { aspectModel.addCorner(corner) }; settle()
        guard !aspectModel.hasReference,!aspectModel.rectifiedLongAxisRows,aspectModel.aspectStoneCount>=3,
              aspectModel.observation?.snapshot.stones.count==10 else { fatalError("Stone shapes did not correct occupied-board display aspect") }
        let aspectSignature=aspectModel.observation!.signature
        for _ in 0..<3 { aspectModel.rotateView() }
        host.rootView=ExperimentView(model:aspectModel).frame(width:1280,height:940)
        try screenshot("stone-aspect-corrected")
        aspectModel.swapLongSide();settle()
        guard aspectModel.aspectOverridden,aspectModel.rectifiedLongAxisRows,aspectModel.observation!.signature==aspectSignature else { fatalError("Aspect override changed recognition or was ignored") }
        aspectModel.detectGrid();awaitGrid(aspectModel);settle()
        guard aspectModel.aspectOverridden,aspectModel.rectifiedLongAxisRows else { fatalError("Grid refinement discarded the manual long-side choice") }
        aspectModel.stop()
        print("PASS: stone-based aspect on an occupied reference-free board, rotated display, unchanged classifications, and manual override across grid refinement.")
        let tentative=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        tentative.soundMode = .off;tentative.size=9
        host.rootView=ExperimentView(model:tentative).frame(width:1280,height:940);settle()
        var tentativeTime=0.0,tentativePoints=[Occupancy](repeating:.empty,count:81)
        func tentativeFeed(_ count:Int) {
            for _ in 0..<count {tentativeTime += 0.21
                let view=BoardObservation(readings:tentativePoints.enumerated().map{
                    .init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)
                },size:9)
                tentative.observation=view;tentative.recorder.consume(view,now:tentativeTime)
            }
        }
        tentative.recorder.start(size:9);tentativeFeed(5)
        tentativePoints[10] = .black;tentativeFeed(2);tentativePoints[10] = .uncertain
        tentativePoints[20] = .white;tentativeFeed(2);tentativePoints[30] = .black;tentativeFeed(90)
        guard tentative.recorder.retainingTentativeMoves,tentative.recorder.pendingMoveCount==3,
              tentative.recorder.tentativeNextPlayer == .white,tentative.recorder.moveCount==0 else {fatalError("Tentative status lost retained moves or displayed the wrong next player")}
        host.rootView=ExperimentView(model:tentative).frame(width:1280,height:940)
        try screenshot("tentative-history")
        let interpretationHost=NSHostingView(rootView:DetectedBoard(model:tentative,recorder:tentative.recorder).frame(width:420,height:420).padding(30))
        interpretationHost.frame=CGRect(x:0,y:0,width:480,height:480)
        interpretationHost.layoutSubtreeIfNeeded()
        let bitmap=interpretationHost.bitmapImageRepForCachingDisplay(in:interpretationHost.bounds)!
        interpretationHost.cacheDisplay(in:interpretationHost.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"PhysicalGo/.build/interpretation-confidence.png"))
        tentativePoints[40] = .white;tentativeFeed(5)
        guard tentative.recorder.lastInterpretedPoint==40,tentative.recorder.pendingMoveCount==4 else {fatalError("Latest white move marker did not advance behind the pending first move")}
        interpretationHost.rootView=DetectedBoard(model:tentative,recorder:tentative.recorder).frame(width:420,height:420).padding(30)
        interpretationHost.layoutSubtreeIfNeeded()
        interpretationHost.cacheDisplay(in:interpretationHost.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"PhysicalGo/.build/interpretation-confidence-white.png"))
        print("PASS: native tentative-history status, pending turn, warning distinction, and confirmed-board review separation.")
        // Physical placement warnings must also be visible before a move has
        // entered the recorder's pending queue.
        struct PlacementMetadata:Decodable {let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double}
        let placementFolder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/PlacementAmbiguity")
        let placementMeta=try JSONDecoder().decode(PlacementMetadata.self,from:Data(contentsOf:placementFolder.appendingPathComponent("metadata.json")))
        func placementImage(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(placementFolder.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
        let placements=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        placements.observation=BoardDetector.detect(frame:GrayFrame(image:placementImage("000589.png"))!,reference:GrayFrame(image:placementImage("empty-reference.png"))!,calibration:placementMeta.calibration,threshold:placementMeta.threshold,referenceCalibration:placementMeta.referenceCalibration)
        guard placements.observation?.ambiguousPlacements==[99,184,252],placements.recorder.pendingConfidence.isEmpty else {fatalError("Placement markers still depend on a pending recorded move")}
        let placementHost=NSHostingView(rootView:DetectedBoard(model:placements,recorder:placements.recorder).frame(width:640,height:640).padding(20))
        placementHost.frame=CGRect(x:0,y:0,width:680,height:680);placementHost.layoutSubtreeIfNeeded()
        let placementBitmap=placementHost.bitmapImageRepForCachingDisplay(in:placementHost.bounds)!
        placementHost.cacheDisplay(in:placementHost.bounds,to:placementBitmap)
        try placementBitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"PhysicalGo/.build/physical-placement-markers.png"))
        print("PASS: actual moves 23/51/53 have spatial markers even without an active game or tentative queue.")
        model.stop(); window.orderOut(nil)
        print("PASS: model calibration, reference, photo recognition, manual labels, complete sample export, overwrite protection, recovery/frozen-sample handling, reset, automatic grid setup/cancellation/wrong-size rejection, and UI previews.")
    }
}
