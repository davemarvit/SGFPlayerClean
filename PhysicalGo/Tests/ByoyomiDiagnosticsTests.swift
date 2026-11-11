import AppKit
import SwiftUI

@main struct ByoyomiDiagnosticsTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory);setbuf(stdout,nil)
        var checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("byoyomi-diagnostics-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let clock=LocalGameClock();clock.audible=false
        var changes=[ByoyomiPeriodChange]()
        clock.onByoyomiPeriodChange={changes.append($0)}
        clock.configure(.init(kind:.byoyomi,mainSeconds:5,periodSeconds:15,periods:3),blackToPlay:true);clock.ready(at:100)
        clock.tick(at:105)
        check(changes.isEmpty,"Entering byoyomi counted as losing a period")
        clock.tick(at:120.1);clock.tick(at:120.2)
        check(changes.count==1 && changes[0].before==3 && changes[0].after==2 && changes[0].boundary==120,"Silent ticking missed or repeated the period loss")
        let estimate=ClockPressEstimate(time:119.8,method:.handBracket,observedLower:119.7,observedUpper:119.9,estimatedError:0.12)
        clock.recordMove(number:1,black:true,at:120.3,observedAt:119.8,estimate:estimate)
        check(changes.count==2 && !changes[1].lost && changes[1].press==estimate,"Recognition refund lost its timing evidence")
        check(clock.engine.black.periods==3 && abs(clock.engine.white.remaining-4.5)<0.0001,"Diagnostics changed clock arithmetic")
        clock.recordMove(number:1,black:true,at:120.3,observedAt:119.8,estimate:estimate)
        check(changes.count==2,"Duplicate recognition repeated a period event")
        clock.pause(at:120.4)
        changes=[];clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:5,periods:1),blackToPlay:false);clock.ready(at:200);clock.tick(at:205)
        check(changes.count==1 && changes[0].before==1 && changes[0].after==0 && !changes[0].black,"Final period expiry was omitted")
        changes=[];clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:5,periods:4),blackToPlay:true);clock.ready(at:300);clock.tick(at:310.1)
        check(changes.count==1 && changes[0].before-changes[0].after==2,"A delayed tick lost multiple boundaries")
        clock.pause(at:310.2)
        changes=[];clock.configure(.init(kind:.absolute,mainSeconds:5),blackToPlay:true);clock.ready(at:400);clock.tick(at:405)
        check(changes.isEmpty,"Non-byoyomi expiry created a byoyomi clip")
        changes=[];clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:5,periods:3),blackToPlay:true);clock.ready(at:500)
        clock.recordMove(number:1,black:true,at:506.2,observedAt:506,estimate:.init(time:506,method:.clearFrame))
        check(changes.count==1 && changes[0].press?.time==506,"A loss first discovered during recognition was missed")
        clock.pause(at:506.3)
        changes=[];var adjusted=clock.engine.black;adjusted.periods=1
        check(clock.correct(black:adjusted,white:clock.engine.white,blackToPlay:false,moveCount:1,at:506.3) && changes.isEmpty,"Manual clock edits created a false loss event")
        // Replay the actual disputed White move. This feature records evidence;
        // it does not change the original timing judgment or clock balance.
        struct Incident:Decodable {let turnStartedUptime:Double;let estimatedHandClearUptime:Double;let recordedAtUptime:Double;let clockPressEstimate:ClockPressEstimate}
        let incident=try JSONDecoder().decode(Incident.self,from:Data(contentsOf:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ByoyomiLoss/move62.json")))
        changes=[];clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:2),blackToPlay:false,baseMove:61);clock.ready(at:incident.turnStartedUptime)
        clock.tick(at:incident.turnStartedUptime+15.02)
        clock.recordMove(number:62,black:false,at:incident.recordedAtUptime,observedAt:incident.estimatedHandClearUptime,estimate:incident.clockPressEstimate)
        check(changes.count==1 && changes[0].before==2 && changes[0].after==1,"Actual move 62 failed to trigger exactly once")
        check(clock.engine.white.periods==1 && clock.moves.last?.estimate==incident.clockPressEstimate,"Diagnostics altered the actual move's judgment")
        clock.pause(at:incident.recordedAtUptime)
        let defaultsName="PhysicalGo.ByoyomiDiagnostics."+UUID().uuidString
        let defaults=UserDefaults(suiteName:defaultsName)!
        defer {defaults.removePersistentDomain(forName:defaultsName)}
        check(!DiagnosticSettings.load(defaults).enabled,"New installations collect diagnostic images without opting in")
        defaults.set(true,forKey:"PhysicalGo.captureUnusualMoves")
        check(DiagnosticSettings.load(defaults).enabled,"Explicit legacy collection preference was lost")
        defaults.removeObject(forKey:"PhysicalGo.captureUnusualMoves")
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,referenceArchive:nil,recordingStorage:nil,settings:defaults,
            diagnosticRoot:root.appendingPathComponent("continuous"),moveEvidenceRoot:root.appendingPathComponent("clips"))
        check(!model.moveEvidenceCapture.enabled,"Disabled diagnostics still buffer images")
        model.diagnosticSettings.enabled=true;model.diagnosticSettings.unusualMoves=false
        check(model.moveEvidenceCapture.enabled && model.diagnosticSettings.byoyomiLosses,"Period clips depend on unusual-move collection")
        model.showDiagnostics=false
        check(model.moveEvidenceCapture.enabled,"Collapsing diagnostics disabled collection")
        check(DiagnosticSettings.load(defaults)==model.diagnosticSettings,"Advanced settings did not persist")
        model.diagnosticSettings.beforeSeconds=6;model.diagnosticSettings.afterSeconds=8;model.diagnosticSettings.framesPerSecond=10
        check(DiagnosticSettings.load(defaults)==model.diagnosticSettings,"Clip parameters did not persist")
        model.diagnosticSettings.beforeSeconds=4;model.diagnosticSettings.afterSeconds=5;model.diagnosticSettings.framesPerSecond=5
        let bitmap=CGContext(data:nil,width:128,height:96,bitsPerComponent:8,bytesPerRow:512,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(gray:0.5,alpha:1));bitmap.fill(CGRect(x:0,y:0,width:128,height:96));let image=bitmap.makeImage()!
        let t=ProcessInfo.processInfo.systemUptime
        func offer(_ offset:Double,playing:Bool=true) {
            model.moveEvidenceCapture.offer(image,at:t+offset,online:playing,context:["testFrameTime":t+offset],reference:nil,anchor:nil,anchorRevision:0)
        }
        func settle() {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
        for i in 0...45 {offer(Double(i)/5)}
        model.recorder.clock.audible=false;model.recorder.clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:5,periods:3),blackToPlay:true)
        model.recorder.clock.ready(at:t+4);model.recorder.clock.tick(at:t+9.01)
        check(model.moveEvidenceCapture.recorder.isCapturing,"Real model callback did not save a period-loss clip")
        let folder=model.moveEvidenceCapture.recorder.folder!
        settle()
        model.recorder.clock.recordMove(number:1,black:true,at:t+9.3,observedAt:t+8.9,estimate:.init(time:t+8.9,method:.clearFrame))
        model.recorder.clock.pause(at:t+9.5)
        for i in 46...69 {offer(Double(i)/5,playing:false);settle()}
        check(model.moveEvidenceCapture.recorder.isCapturing,"Pausing play truncated the post-event camera clip")
        offer(14.1,playing:false);model.moveEvidenceCapture.closeForExit()
        let rows=try String(contentsOf:folder.appendingPathComponent("events.jsonl"),encoding:.utf8).split(separator:"\n").map {try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        let frames=rows.filter{$0["event"] as? String=="frame"},times=frames.compactMap{$0["captureUptime"] as? Double}
        check(times.count>=40 && times.first!<=t+5.21 && times.last!>=t+13.79,"Surrounding pre/post frames were not retained")
        let triggers=rows.filter{$0["event"] as? String=="move evidence trigger"}
        check(triggers.count==1,"One period loss created duplicate clip triggers")
        let periodEvents=rows.compactMap{$0["clockPeriodChange"] as? [String:Any]}
        check(periodEvents.contains{$0["event"] as? String=="byoyomi period lost"},"Loss metadata missing from clip")
        check(periodEvents.contains{$0["event"] as? String=="byoyomi period restored" && $0["press"] != nil},"Refund and hand-clear estimate missing from clip")
        let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("session.json"))) as! [String:Any]
        check(manifest["samplesPerSecond"] as? Int==5 && manifest["requestedPostSeconds"] as? Int==5,"Manifest disagrees with configured clip parameters")
        model.diagnosticSettings.enabled=false
        check(!model.moveEvidenceCapture.enabled && model.moveEvidenceCapture.bufferedFrames==0,"Disabling diagnostics left the camera ring active")
        let prior=try FileManager.default.contentsOfDirectory(at:model.moveEvidenceCapture.root,includingPropertiesForKeys:nil).count
        model.recorder.clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:5,periods:2),blackToPlay:true);model.recorder.clock.ready(at:t+20)
        offer(24);model.recorder.clock.tick(at:t+25.1)
        check(try FileManager.default.contentsOfDirectory(at:model.moveEvidenceCapture.root,includingPropertiesForKeys:nil).count==prior,"Diagnostics-off period loss wrote a clip")
        model.recorder.clock.pause(at:t+25.2)
        model.diagnosticSettings.enabled=true;model.diagnosticSettings.byoyomiLosses=false;model.diagnosticSettings.unusualMoves=true
        model.recorder.clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:5,periods:2),blackToPlay:true);model.recorder.clock.ready(at:t+30)
        offer(34);model.recorder.clock.tick(at:t+35.1)
        check(!model.moveEvidenceCapture.recorder.isCapturing,"Disabled period-loss trigger ignored its own setting")
        model.recorder.clock.pause(at:t+35.2);model.diagnosticSettings.enabled=false
        model.startDiagnostics()
        let continuousFolder=model.diagnostics.folder!
        _=model.diagnostics.capture(image,at:t+40,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        model.diagnosticSettings.byoyomiLosses=true
        model.recorder.clock.configure(.init(kind:.byoyomi,mainSeconds:0,periodSeconds:5,periods:2),blackToPlay:true);model.recorder.clock.ready(at:t+40)
        offer(44);model.recorder.clock.tick(at:t+45.1)
        check(!model.moveEvidenceCapture.recorder.isCapturing,"Continuous recording opened a competing clip writer")
        _=model.diagnostics.capture(image,at:t+45.2,context:[:],reference:nil,anchor:nil,anchorRevision:0)
        model.recorder.clock.pause(at:t+45.3);model.diagnosticSettings.enabled=false;model.diagnostics.closeForExit()
        let continuousRows=try String(contentsOf:continuousFolder.appendingPathComponent("events.jsonl"),encoding:.utf8).split(separator:"\n").map {try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        let bookmark=continuousRows.compactMap{$0["decision"] as? [String:Any]}.compactMap{$0["periodChange"] as? [String:Any]}.first
        check(bookmark?["evidenceCaptureFolder"] as? String==continuousFolder.path && bookmark?["evidenceCaptureKind"] as? String=="continuous diagnostics","Period loss did not bookmark the continuous camera evidence")
        check(!model.diagnostics.isCapturing && !model.moveEvidenceCapture.enabled,"Master switch left continuous or event recording active")
        print("PASS: \(checks) byoyomi diagnostics checks")
        if CommandLine.arguments.contains("--ui") {
            let view=DiagnosticControls(model:model,diagnostics:model.diagnostics).padding(20)
            let host=NSHostingView(rootView:ScrollView{view});host.frame=NSRect(x:0,y:0,width:650,height:900)
            let window=NSWindow(contentRect:host.frame,styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.title="Physical Go Advanced Settings Test";window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;window.center()
            NSApplication.shared.setActivationPolicy(.regular);window.makeKeyAndOrderFront(nil);NSApplication.shared.activate(ignoringOtherApps:true)
            print("UI READY");NSApplication.shared.run()
        }
    }
}
