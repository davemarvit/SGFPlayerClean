import SwiftUI

struct DetectionTuningView:View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject var recorder:GameRecorder
    private var editable:Bool {recorder.state != .recording && recorder.state != .verifying && recorder.pendingMoveCount==0}
    var body:some View {
        DisclosureGroup("Advanced detection") {
            VStack(alignment:.leading,spacing:8) {
                HStack {Text("Brightness difference");Spacer();Text(String(format:"%.2f",model.threshold)).monospacedDigit()}
                Text("How much contrast helps a patch qualify as a stone. Color and shape also contribute.")
                VStack(spacing:4) {
                    Slider(value:$model.threshold,in:0.05...0.35,step:0.01).onChange(of:model.threshold){_,_ in model.thresholdChanged()}
                        .accessibilityLabel("Minimum brightness difference")
                    HStack {Text("More sensitive");Spacer();Text("Less sensitive")}.font(.system(size:11*model.interfaceScale))
                    Button("Reset to 0.13") {model.threshold=0.13}
                }.disabled(!editable)
                Text("Lower values can pick up shadows; higher values can miss low-contrast stones. Usually leave this at 0.13. This does not set move confidence.")
                if !editable {Text("Pause and resolve pending moves before changing detection settings.").foregroundStyle(.orange)}
            }.font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary).padding(.top,6)
        }
    }
}
