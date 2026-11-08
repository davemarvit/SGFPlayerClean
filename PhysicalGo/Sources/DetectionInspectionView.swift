import SwiftUI

struct DetectionInspectionView:View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject var recorder:GameRecorder
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(model.alignmentNeedsRecovery ? "Detection paused while the grid is realigned" : "Camera readings with your manual corrections")
                .font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
            DetectedBoard(model:model,recorder:recorder).aspectRatio(1,contentMode:.fit).frame(maxWidth:520)
            if let observation=model.correctedObservation {
                let black=observation.signature.filter{$0 == .black}.count
                let white=observation.signature.filter{$0 == .white}.count
                let uncertain=observation.signature.filter{$0 == .uncertain}.count
                Text("\(black) black · \(white) white · \(uncertain) uncertain").monospacedDigit()
            }
            HStack {
                Button("Correct board…") {model.beginBoardCorrection()}
                    .disabled(model.observation == nil || model.alignmentNeedsRecovery)
                if !model.boardCorrections.values.isEmpty {
                    Text("\(model.boardCorrections.values.count) manual · purple rings").foregroundStyle(.purple)
                }
            }
            Text(model.boardCorrections.values.isEmpty ? "Use Correct board to tell the system where stones actually are." : "Manual intersections stay as you set them. Use Correct board → Use camera to release one when its stone changes.")
                .foregroundStyle(.secondary)
            if !model.boardCorrections.notice.isEmpty { Text(model.boardCorrections.notice).foregroundStyle(.secondary) }
        }.font(.system(size:12*model.interfaceScale))
    }
}
