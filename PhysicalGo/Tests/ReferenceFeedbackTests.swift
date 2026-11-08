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
        print("PASS: successful capture, failure without false success, disabled repeated capture, completion survives camera status changes, reference invalidation, and stable native layout at both text sizes and widths.")
    }
}
