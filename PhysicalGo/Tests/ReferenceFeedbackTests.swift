import AppKit
import SwiftUI

@main struct ReferenceFeedbackTests {
    @MainActor static func main() {
        setbuf(stdout,nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
        model.tracksCameraMotion=false
        model.captureReference()
        precondition(!model.startupReferenceCaptured,"Unsuccessful capture claimed completion")
        let pixels=Data(repeating:160,count:100*100)
        let image=CGImage(width:100,height:100,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:100,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:pixels as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        for scale in [1.0,1.5] {
            for width in [380.0,700.0] {
                let model=ExperimentModel(discoverCameras:false,automaticGridDetection:false,restoreViewSettings:false,referenceArchive:nil,recordingStorage:nil)
                model.tracksCameraMotion=false;model.interfaceScale=scale
                model.receive(image)
                for point in [ImagePoint(x:0.1,y:0.1),ImagePoint(x:0.9,y:0.1),ImagePoint(x:0.9,y:0.9),ImagePoint(x:0.1,y:0.9)] {model.addCorner(point)}
                model.useWithoutReference()
                precondition(!model.startupReferenceCaptured,"Removed reference retained completion")
                let host=NSHostingView(rootView:StartupReferenceControl(model:model).frame(width:width))
                host.layoutSubtreeIfNeeded()
                let before=host.fittingSize
                model.captureReference()
                precondition(model.startupReferenceCaptured,"Successful capture did not show completion")
                precondition(!model.canCaptureStartupReference,"Completed primary capture action still enabled")
                model.handleCameraStatus("Camera unavailable",state:.failed)
                RunLoop.main.run(until:Date().addingTimeInterval(0.2))
                precondition(model.startupReferenceCaptured,"Transient camera status erased completion")
                host.layoutSubtreeIfNeeded()
                let after=host.fittingSize
                print("width",width,"scale",scale,"before",before,"after",after)
                precondition(abs(before.height-after.height)<1,"Completion shifted the controls")
                model.useWithoutReference()
                precondition(!model.startupReferenceCaptured,"Removed reference retained completion")
            }
        }
        // A retry must clear the mistaken setup, reject its old analysis, and
        // wait for fresh camera pixels without opening a game or starting clocks.
        model.receive(image)
        for point in [ImagePoint(x:0.1,y:0.1),ImagePoint(x:0.9,y:0.1),ImagePoint(x:0.9,y:0.9),ImagePoint(x:0.1,y:0.9)] {model.addCorner(point)}
        model.captureReference()
        model.running=true;model.handleCameraStatus("Live · retry test",state:.live)
        precondition(model.canRetryStartupSetup,"Completed reference removed the retry action")
        model.frozen=true
        precondition(!model.canRetryStartupSetup,"Frozen pixels were offered as a fresh setup retry")
        model.frozen=false
        let clock=model.recorder.clock.engine
        model.retryStartupSetup()
        precondition(model.calibration==nil && !model.hasReference && !model.startupReferenceCaptured && model.image==nil,"Retry retained the mistaken grid/reference or reused stale pixels")
        RunLoop.main.run(until:Date().addingTimeInterval(0.3))
        precondition(model.calibration==nil && !model.hasReference,"Old in-flight analysis restored a discarded setup")
        precondition(!model.recorder.hasGame && model.recorder.clock.engine==clock,"Setup retry created a game or changed clock balances")
        // A fresh delivery, not a UI redraw, launches the replacement search.
        model.frameCount=8
        model.receiveCameraFrame(image,capturedAt:ProcessInfo.processInfo.systemUptime)
        precondition(model.detectingGrid && model.image === image,"Retry did not search fresh camera pixels")
        model.stop()
        print("PASS: successful capture, failure without false success, disabled repeated capture, completion survives camera status changes, reference invalidation, and stable native layout at both text sizes and widths.")
    }
}
