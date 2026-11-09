import AppKit
import SwiftUI
import CoreImage

@main struct RecoveryUITests {
    struct Entry:Decodable {
        let time:Double
        let event:String?
        let position:String?
        let footprints:[StoneFootprint]?
        let placementFits:[StoneFootprint]?
    }
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        func wait(_ ready:()->Bool) {
            let end=Date().addingTimeInterval(60)
            while !ready() && Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
            check(ready(),"Timed out waiting for board recovery")
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("recovery-ui-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let suite="PhysicalGo.recovery-test."+UUID().uuidString,settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:true,
                                  referenceArchive:nil,recordingStorage:root,settings:settings)
        check(model.recoverySpeechEnabled,"Recovery speech not enabled by default")
        model.recoverySpeechEnabled=false
        check(settings.object(forKey:"PhysicalGo.recoverySpeech") as? Bool == false,"Recovery speech setting not persisted")
        let restored=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:true,
                                     referenceArchive:nil,recordingStorage:nil,settings:settings)
        check(!restored.recoverySpeechEnabled,"Recovery speech preference not restored")
        let fixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/CameraBump")
        try model.openSample(from:fixture)
        wait {model.observation != nil && !model.alignmentNeedsRecovery}
        let black=[(12,16),(13,16),(14,16),(15,15),(16,5),(16,13),(16,15),(17,14)]
        let white=[(13,17),(14,17),(15,3),(15,16),(16,7),(16,16),(17,15),(17,16)]
        var sgf="(;GM[1]FF[4]AP[PhysicalGo:0.83]SZ[19]RU[Japanese]KM[6.5]"
        for i in black.indices {
            sgf += ";B["+SGFCoordinates.toSGF(x:black[i].1,y:black[i].0)+"];W["+SGFCoordinates.toSGF(x:white[i].1,y:white[i].0)+"]"
        }
        sgf += ")"
        let file=root.appendingPathComponent("game.sgf");try sgf.write(to:file,atomically:true,encoding:.utf8)
        try model.recorder.restoreSavedGame(from:file)
        let saved=model.recorder.sgf(),position=model.recorder.positions.last!,reference=model.referenceCalibration
        check(position.stones.count==16,"Test game did not reproduce known photo")
        // Exercise the actual camera-delivery path without opening hardware.
        let goodImage=model.image!,wasFrozen=model.frozen
        let dark=CGImage(width:goodImage.width,height:goodImage.height,bitsPerComponent:8,bitsPerPixel:8,
            bytesPerRow:goodImage.width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),
            provider:CGDataProvider(data:Data(repeating:0,count:goodImage.width*goodImage.height) as CFData)!,
            decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        model.running=true;model.cameraState = .live;model.frozen=false
        let time=ProcessInfo.processInfo.systemUptime
        model.receive(dark,capturedAt:time)
        wait {model.lightingNeedsRecovery && model.observation?.lightingBlocked == true}
        check(!model.alignmentNeedsRecovery,"Lights-out was mistaken for a camera nudge")
        check(model.visibleObservation==nil && !model.liveBoardReady,"Unreadable exposure remained playable")
        check(model.recorder.sgf()==saved && model.referenceCalibration==reference,"Lighting changed saved game/reference")
        model.receive(dark,capturedAt:time+8.2)
        wait {model.lightingNeedsHelp}
        let lightingOutput=URL(fileURLWithPath:"PhysicalGo/.build/RecoveryUI")
        try FileManager.default.createDirectory(at:lightingOutput,withIntermediateDirectories:true)
        let lightingHost=NSHostingView(rootView:ExperimentView(model:model).frame(width:1500,height:1150))
        lightingHost.frame=NSRect(x:0,y:0,width:1500,height:1150)
        lightingHost.appearance=NSAppearance(named:.darkAqua);lightingHost.layoutSubtreeIfNeeded()
        let lightingBitmap=lightingHost.bitmapImageRepForCachingDisplay(in:lightingHost.bounds)!
        lightingHost.cacheDisplay(in:lightingHost.bounds,to:lightingBitmap)
        try lightingBitmap.representation(using:.png,properties:[:])!.write(to:lightingOutput.appendingPathComponent("lighting-banner.png"))
        let lightingContext=CIContext(),lightingInput=CIImage(cgImage:goodImage)
        for i in 0..<4 {
            let fresh=lightingContext.createCGImage(lightingInput,from:lightingInput.extent)!
            model.receive(fresh,capturedAt:time+9+Double(i)*0.3)
            wait {model.image === fresh}
        }
        wait {!model.lightingNeedsRecovery}
        check(!model.lightingNeedsHelp && model.visibleObservation != nil,"Lighting notice did not clear automatically")
        check(model.recorder.state == .paused && model.recorder.sgf()==saved,"Lighting resumed or modified a paused game")
        model.running=false;model.frozen=wasFrozen
        let input=CIImage(cgImage:model.image!),context=CIContext()
        let moved=context.createCGImage(input.transformed(by:CGAffineTransform(translationX:60,y:0)),from:input.extent)!
        model.image=moved;model.detectGrid()
        check(model.alignmentNeedsRecovery,"Reacquisition did not show interrupt immediately")
        wait {!model.detectingGrid && !model.alignmentNeedsRecovery && model.observation != nil}
        check(model.recorder.sgf()==saved && model.recorder.positions.last!.stones==position.stones,"Recovery changed recorded game")
        check(model.referenceCalibration==reference,"Recovery relabeled empty reference")
        check(model.recorder.state == .paused,"Recovery resumed a manually paused game")
        let blank=context.createCGImage(CIImage(color:CIColor(red:0.7,green:0.7,blue:0.7)).cropped(to:input.extent),from:input.extent)!
        model.image=blank;model.detectGrid()
        wait {!model.detectingGrid}
        check(model.alignmentNeedsRecovery && model.recoveryNeedsFullBoard,"Missing board did not ask for reframing")
        check(model.observation==nil,"Failed recovery left a playable stale observation")
        check(model.recorder.sgf()==saved,"Failed recovery changed the game")
        let output=URL(fileURLWithPath:"PhysicalGo/.build/RecoveryUI")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1500,height:1150),styleMask:[.titled],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua)
        let host=NSHostingView(rootView:ExperimentView(model:model));window.contentView=host;window.orderFront(nil)
        RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("recovery-banner.png"))
        model.image=moved;model.detectGrid()
        wait {!model.detectingGrid && !model.alignmentNeedsRecovery && model.observation != nil}
        check(!model.recoveryNeedsFullBoard,"Recovery left adjustment notice active")
        check(model.recorder.sgf()==saved && model.recorder.pendingMoveCount==0,"Retry changed saved/pending game state")
        window.orderOut(nil)
        model.resetCalibration(preservingRecording:true);model.image=moved;model.detectGrid()
        check(model.alignmentNeedsRecovery,"Lost calibration did not show recovery notice")
        wait {!model.detectingGrid && !model.alignmentNeedsRecovery && model.observation != nil}
        check(model.recorder.sgf()==saved && model.recorder.positions.last!.stones==position.stones,"Lost calibration changed the recorded position")
        model.recorder.finish()
        check(model.recoveryExpected.isEmpty,"Finished game constrained recovery of a cleared board")
        // Use the current recorder's interpretation of the historical session rather
        // than obsolete hard-coded accepted/pending counts from its older algorithm.
        let pendingFixture=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/GridRefinement")
        let entries=try JSONDecoder().decode([Entry].self,from:Data(contentsOf:pendingFixture.appendingPathComponent("observations.json")))
        let recorder=GameRecorder(storage:root),start=entries.first!.time
        recorder.clock.audible=false
        let empty=BoardObservation(readings:(0..<361).map{.init(row:$0/19,col:$0%19,occupancy:.empty,confidence:1,delta:0)},size:19)
        for i in 0..<6 {recorder.consume(empty,now:start-2+Double(i)*0.21)}
        recorder.start(size:19,now:start-0.9)
        for entry in entries {
            if let event=entry.event {
                if event=="paused" {recorder.pause()}
                else if event=="resumed" {recorder.resume()}
                else if !event.contains("Checking that the physical board matches") {
                    recorder.suspendVision(event,preserveObservations:event.contains("Grid alignment lost"),preserveOrder:event.contains("Finding the grid"))
                }
            } else if let position=entry.position {
                let readings=position.enumerated().map {i,c in IntersectionReading(row:i/19,col:i%19,occupancy:c=="B" ? .black:c=="W" ? .white:c=="?" ? .uncertain:.empty,confidence:1,delta:0)}
                recorder.consume(BoardObservation(readings:readings,size:19,footprints:entry.footprints ?? [],placementFits:entry.placementFits ?? []),now:entry.time)
            }
        }
        recorder.pause();try recorder.savePendingCheckpoint()
        check(recorder.pendingMoveCount>0 || recorder.hasDeferredMoves,"Historical replay has no unresolved moves to protect")
        let pending=recorder.pendingConfidence.compactMap(\.point),savedCount=recorder.moveCount,pendingSGF=recorder.sgf()
        let reviewSections=recorder.reviewHistory.sections
        let pendingModel=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        try pendingModel.openSample(from:pendingFixture)
        wait {pendingModel.observation != nil && !pendingModel.alignmentNeedsRecovery}
        try pendingModel.recorder.restoreSavedGame(from:recorder.autosaveURL!)
        pendingModel.detectGrid()
        wait {!pendingModel.detectingGrid && !pendingModel.alignmentNeedsRecovery && pendingModel.observation != nil}
        check(pendingModel.recorder.moveCount==savedCount && pendingModel.recorder.sgf()==pendingSGF,"Recovery changed historical accepted moves")
        check(pendingModel.recorder.pendingConfidence.compactMap(\.point)==pending,"Recovery erased or reordered historical tentative moves")
        check(pendingModel.recorder.reviewHistory.sections.map(\.id)==reviewSections.map(\.id)
            && zip(pendingModel.recorder.reviewHistory.sections,reviewSections).allSatisfy {$0.before==$1.before && $0.after==$1.after && $0.moves==$1.moves && $0.committed==$1.committed},
            "Recovery changed retained review history")
        print("Historical recovery preserved \(savedCount) saved + \(pending.count) tentative moves")
        print("PASS: \(checks) recovery UI checks: speech preference, real photo reacquisition, loss notice, missing-board guidance, retry/clear, saved game/reference preservation and native banner render")
    }
}
