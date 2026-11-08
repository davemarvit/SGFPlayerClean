import AppKit
import SwiftUI

@main struct LayoutVoiceTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("layout-voice-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let suite="PhysicalGo.LayoutTests."+UUID().uuidString
        let settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:root,settings:settings,diagnosticRoot:root.appendingPathComponent("diagnostics"))
        model.moveEvidenceCapture.enabled=false;model.recorder.clock.audible=false
        model.recorder.start(size:19,clockSettings:.init(kind:.none));model.recorder.pause()
        model.recorder.manualMove(at:BoardPosition(3,3));model.recorder.manualMove(at:BoardPosition(15,15))
        let original=model.recorder.sgf()
        let output=try TestArtifacts.directory("physical-layout-voice")
        func render<V:View>(_ view:V,_ name:String,width:CGFloat=1000,height:CGFloat=1100)throws->NSBitmapImageRep {
            let host=NSHostingView(rootView:view.background(Color(nsColor:.windowBackgroundColor)))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled],backing:.buffered,defer:false)
            window.appearance=NSAppearance(named:.darkAqua);host.appearance=window.appearance
            window.contentView=host;window.orderFront(nil)
            RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
            window.orderOut(nil);return bitmap
        }
        func boardBounds(_ bitmap:NSBitmapImageRep)->CGRect {
            var points=[CGPoint]()
            for y in stride(from:0,to:bitmap.pixelsHigh,by:2) {
                for x in stride(from:0,to:bitmap.pixelsWide,by:2) {
                    guard let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else {continue}
                    if c.redComponent>0.7 && c.redComponent<0.9 && c.greenComponent>0.55 && c.greenComponent<0.75 && c.blueComponent>0.3 && c.blueComponent<0.55 {
                        points.append(CGPoint(x:x,y:y))
                    }
                }
            }
            precondition(!points.isEmpty,"No board in native render")
            let x=points.map(\.x),y=points.map(\.y)
            return CGRect(x:x.min()!,y:y.min()!,width:x.max()!-x.min()!,height:y.max()!-y.min()!)
        }
        for width in [CGFloat(760),1000] {
            let live=try render(RecordingView(model:model,recorder:model.recorder,showsRecordingControls:false,initialDisplay:.live),"live-\(Int(width))",width:width)
            let saved=try render(RecordingView(model:model,recorder:model.recorder,showsRecordingControls:false,initialDisplay:.saved),"saved-\(Int(width))",width:width)
            let a=boardBounds(live),b=boardBounds(saved)
            print("Board bounds at \(width): live \(a), saved \(b)")
            check(a==b,"Live and saved boards moved or resized")
        }
        let states=[
            SetupCameraMessage(alignment:true,needsFullBoard:true,exhausted:false,lighting:false,ready:false,detecting:false),
            SetupCameraMessage(alignment:true,needsFullBoard:false,exhausted:false,lighting:false,ready:false,detecting:true),
            SetupCameraMessage(alignment:true,needsFullBoard:false,exhausted:true,lighting:false,ready:false,detecting:false),
            SetupCameraMessage(alignment:false,needsFullBoard:false,exhausted:false,lighting:true,ready:false,detecting:false),
            SetupCameraMessage(alignment:false,needsFullBoard:false,exhausted:false,lighting:false,ready:true,detecting:false),
            SetupCameraMessage(alignment:false,needsFullBoard:false,exhausted:false,lighting:false,ready:true,detecting:false,check:.passed),
            SetupCameraMessage(alignment:false,needsFullBoard:false,exhausted:false,lighting:false,ready:false,detecting:false,check:.failed)]
        for scale in [1.0,1.5] {
            var height:CGFloat?
            for (i,state) in states.enumerated() {
                let view=SetupCameraStatusContent(message:state,detecting:i==1,canRetry:i != 1,scale:scale,onRetry:{})
                let host=NSHostingView(rootView:view.frame(width:760))
                let measured=host.fittingSize.height
                print("Setup status \(i), scale \(scale): \(measured)")
                if let height {check(abs(height-measured)<0.5,"Camera status changed height")} else {height=measured}
                _=try render(view,"camera-status-\(i)-\(scale)",width:760,height:measured)
            }
        }
        let speech=KokoroSpeech.shared
        check(speech.available,"Bundled Kokoro models unavailable in test")
        for i in 1...10 {check(speech.cached(String(i)) != nil,"Countdown \(i) is not precached")}
        let byo=LocalClockSettings(kind:.byoyomi,mainSeconds:0,periodSeconds:15,periods:5)
        var engine=LocalClockEngine(settings:byo)
        func bars(_ side:LocalClockEngine.Side)->ByoyomiPeriodProgress {ByoyomiPeriodProgress(settings:byo,side:side)}
        check(bars(engine.black).fractions==[1,1,1,1,1],"Initial periods are not full")
        engine.resume(at:0);engine.advance(to:12)
        check(bars(engine.black).fractions==[1,1,1,1,0.2],"Current period did not shrink on the right")
        engine.pause(at:12);engine.advance(to:30)
        check(bars(engine.black).fractions.last==0.2,"Paused bar kept shrinking")
        engine.resume(at:30);engine.advance(to:33)
        check(bars(engine.black).fractions==[1,1,1,1],"Exhausted period did not disappear")
        check(bars(engine.black).capacity==5,"Surviving bars would grow after losing a period")
        engine.advance(to:34);engine.move(black:true,at:34)
        check(bars(engine.black).fractions==[1,1,1,1],"On-time move failed to refill the current period")
        engine.advance(to:35)
        check(bars(engine.black).fractions==[1,1,1,1],"Opponent turn changed the waiting player's bars")
        let restored=LocalClockEngine.Side(remaining:15,overtime:true,periods:5,stones:25)
        engine.correct(black:restored,white:engine.white,blackToPlay:false)
        check(bars(engine.black).fractions.count==5,"Restored period did not reappear")
        let expired=LocalClockEngine.Side(remaining:0,overtime:true,periods:1,stones:25)
        check(bars(expired).fractions.isEmpty,"Final exhausted period left a visible bar")
        let main=LocalClockEngine.Side(remaining:300,overtime:false,periods:5,stones:25)
        check(bars(main).fractions==[1,1,1,1,1],"Main time consumed reserved overtime bars")
        let many=ByoyomiPeriodProgress(settings:.init(periods:100),side:.init(remaining:30,overtime:true,periods:100,stones:25))
        check(many.columns==10 && many.rows==10,"Large period count cannot fit the display")
        let clocks=GameRecorder(storage:nil);clocks.clock.audible=false
        clocks.start(size:19,clockSettings:byo);clocks.pause()
        let black=LocalClockEngine.Side(remaining:15,overtime:true,periods:4,stones:25)
        let white=LocalClockEngine.Side(remaining:3,overtime:true,periods:3,stones:25)
        check(clocks.clock.correct(black:black,white:white,blackToPlay:false,moveCount:0),"Could not render sketch example")
        _=try render(LocalClockPanel(clock:clocks.clock,recorder:clocks,large:false),"byoyomi-clock",width:1000,height:680)
        _=try render(LocalClockPanel(clock:clocks.clock,recorder:clocks,large:true),"byoyomi-large-clock",width:1200,height:850)
        let examples:[LocalClockEngine.Side]=[white,.init(remaining:15,overtime:true,periods:2,stones:25),.init(remaining:7.5,overtime:true,periods:2,stones:25),expired]
        let stages=VStack(alignment:.leading,spacing:28) {
            ForEach(examples.indices,id:\.self) {i in
                VStack(alignment:.leading,spacing:10) {
                    Text(["3 periods · 3 seconds left","Period exhausted · 2 periods remain","2 periods · halfway through this period","Time expired"][i]).font(.headline)
                    ByoyomiPeriodBars(settings:byo,side:examples[i],active:true,large:true)
                }
            }
        }.padding(28)
        _=try render(stages,"byoyomi-stages",width:600,height:440)
        check(model.recorder.sgf()==original && model.recorder.state == .paused,"UI tests modified the game")
        print("PASS: \(checks) layout, offline voice resources and game-preservation checks")
    }
}
