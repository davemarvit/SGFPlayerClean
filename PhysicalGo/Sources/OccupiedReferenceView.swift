import SwiftUI

struct OccupiedReferenceControls:View {
    @ObservedObject var model:ExperimentModel
    @State private var confirming=false
    var body:some View {
        DisclosureGroup("Occupied reference") {
            VStack(alignment:.leading,spacing:8) {
                Text("Keep the stones in place. Capture the clear parts even if some stones are uncertain. Ambiguous locations and their neighbors are excluded. The empty-board reference is preserved.")
                Button("Capture occupied reference…") {confirming=true}
                    .disabled(!model.canCaptureOccupiedReference)
                    .accessibilityIdentifier("capture-occupied-reference")
                Toggle("Refresh while the board is stable",isOn:$model.refreshOccupiedReference)
                Text(model.occupiedReferenceStatus).font(.caption).foregroundStyle(.secondary)
            }.padding(.top,6)
        }
        .accessibilityIdentifier("occupied-reference-controls")
        .confirmationDialog("Choose which parts of the board to capture",isPresented:$confirming,titleVisibility:.visible) {
            Button("Board matches — capture reference") {model.captureOccupiedReference()}
            Button("Capture confident areas only") {model.captureOccupiedReference(confidentAreasOnly:true)}
            Button("Cancel",role:.cancel) {}
        } message: {
            Text("Use “Board matches” only if all \(model.ai.cells.filter{$0 != "empty"}.count) stones match the displayed game and all other intersections are empty. Otherwise capture confident areas only: unclear regions are skipped. Keep your hands away. Neither option changes game moves.")
        }
    }
}
