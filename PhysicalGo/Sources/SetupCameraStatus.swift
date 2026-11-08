import SwiftUI

enum AlignmentCheck {case idle,checking,passed,failed}

/// Setup feedback stays below the view being positioned. All states use the
/// same slots, including a verified board, so retries never move the preview.
struct SetupCameraMessage {
    var title:String
    var detail:String
    var attention=false
    var buttonTitle="Check alignment"
    init(alignment:Bool,needsFullBoard:Bool,exhausted:Bool,lighting:Bool,ready:Bool,detecting:Bool,check:AlignmentCheck = .idle) {
        attention=alignment || lighting
        if check == .checking {
            title="Checking alignment…"
            detail="Keep the board and camera steady. The result will appear here."
        } else if check == .failed {
            attention=true;title="Alignment check did not pass"
            detail="Show all four corners and the outer grid lines, then check again."
            buttonTitle="Check alignment again"
        } else if alignment {
            title=needsFullBoard ? "Show the whole board":exhausted ? "Board alignment needs attention":"Reacquiring board…"
            detail=needsFullBoard
                ? "Adjust the camera or board so all four corners and the outer grid lines are visible. Then hold everything steady."
                : exhausted ? "Keep the whole board in view and retry. If alignment cannot be verified, use Manual corners in the camera controls."
                : "Hold the camera and board steady while their positions are verified. Stones can stay in place."
        } else if lighting {
            title="Adjusting to the lighting…"
            detail="Light the board evenly and reduce glare or strong shadows. Leave the stones in place while the view is checked."
        } else if ready {
            title=check == .passed ? "Alignment passed":"Board is in view"
            detail=check == .passed ? "The grid is aligned. Keep the camera steady, then save your game setup.":"Grid aligned. Keep the camera steady; continue with game setup below."
            if check == .passed {buttonTitle="Check alignment again"}
        } else {
            title=detecting ? "Finding the grid…":"Position the camera"
            detail="Keep all four corners and the outer grid lines in view. Hold the camera steady, then check alignment."
        }
    }
}

struct SetupCameraStatus:View {
    @ObservedObject var model:ExperimentModel
    var body:some View {
        SetupCameraStatusContent(message:SetupCameraMessage(
            alignment:model.alignmentNeedsRecovery,needsFullBoard:model.recoveryNeedsFullBoard,
            exhausted:model.recoverySearchExhausted,lighting:model.lightingNeedsRecovery,
            ready:model.calibration != nil,detecting:model.detectingGrid,check:model.alignmentCheck),
            detecting:model.detectingGrid,
            canRetry:model.image != nil && !model.frozen && model.cameraState == .live && !model.detectingGrid,
            scale:model.interfaceScale,onRetry:{model.detectGrid(reportCheck:true)})
    }
}

struct SetupCameraStatusContent:View {
    let message:SetupCameraMessage
    let detecting:Bool
    let canRetry:Bool
    let scale:Double
    let onRetry:()->Void
    var body:some View {
        HStack(alignment:.center,spacing:16) {
            Image(systemName:message.attention ? "viewfinder":"camera")
                .font(.system(size:26)).frame(width:32).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:6) {
                Text(message.title).font(.system(size:17*scale,weight:.semibold)).lineLimit(1)
                Text(message.detail).font(.system(size:13*scale)).lineLimit(3,reservesSpace:true)
                    .help(message.detail)
            }.frame(maxWidth:.infinity,alignment:.leading)
            VStack(spacing:8) {
                ProgressView().controlSize(.small).opacity(detecting ? 1:0)
                Button(message.buttonTitle,action:onRetry).disabled(!canRetry)
                    .buttonStyle(.borderedProminent)
            }.frame(width:170)
        }.frame(height:84*scale).padding(14)
            .background((message.attention ? Color.orange:Color.secondary).opacity(0.15),in:RoundedRectangle(cornerRadius:10))
            .accessibilityElement(children:.contain)
    }
}
