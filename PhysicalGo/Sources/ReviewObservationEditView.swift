import SwiftUI

struct ReviewObservationEditView:View {
    @ObservedObject var recorder:GameRecorder
    let edit:ReviewObservationEdit
    let orientation:BoardOrientation
    let onClose:()->Void
    let onSaved:()->Void
    let onHistorySaved:()->Void
    @State private var error:String?
    var body:some View {
        if let number=edit.savedMoveNumber {
            HistoricalMoveCorrectionView(recorder:recorder,orientation:orientation,number:number,onClose:onClose,
                initialDestination:edit.to,reviewEdit:edit,onSaved:onHistorySaved)
        } else {
            VStack(alignment:.leading,spacing:12) {
                Text("Correct detected stone").font(.title2.bold())
                Text("This updates the camera interpretation saved for this review. Saved moves and live camera readings stay unchanged.")
                RecordedBoard(recorder:recorder,orientation:orientation,
                    boardOverride:DeferredMoveHistory.board(edit.corrected,size:recorder.game.boardSize),
                    highlightedPoints:[edit.to.row*recorder.game.boardSize+edit.to.col],showsLastMoveMarker:false,onPoint:{_ in})
                    .frame(width:500,height:500)
                Text("The original camera interpretation is kept. After saving, review the remaining changes and their move order. Clocks stay paused.").font(.callout).foregroundStyle(.secondary)
                if let error {Text(error).foregroundStyle(.red)}
                HStack {
                    Button("Cancel",action:onClose).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Use corrected interpretation") {
                        do {try recorder.correctReviewObservation(edit);onSaved();onClose()} catch {self.error=error.localizedDescription}
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width:550)
        }
    }
}
