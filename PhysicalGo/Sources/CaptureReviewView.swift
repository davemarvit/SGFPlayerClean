import SwiftUI

struct CaptureReviewView: View {
    @ObservedObject var recorder: GameRecorder
    let plan: CaptureReviewPlan
    let orientation: BoardOrientation
    let onClose: () -> Void
    let onSaved: () -> Void
    let onOtherMove: () -> Void
    @State private var error: String?

    private var remaining: Set<Int> { plan.remaining(in: recorder.reviewCameraPosition) }
    private var verification: ReviewBoardVerification.Status { recorder.captureVerificationStatus(plan) }
    private var ready: Bool { verification == .ready }
    private func coordinate(_ point: Int) -> String {
        let size = recorder.game.boardSize, last = Double(size - 1)
        let p = orientation.display(.init(x: Double(point % size) / last, y: Double(point / size) / last))
        return "\(Array("ABCDEFGHJKLMNOPQRST")[Int((p.x * last).rounded())])\(size - Int((p.y * last).rounded()))"
    }
    private var board: BoardSnapshot {
        var shown = plan.target
        for p in remaining { shown[p] = plan.move.color == .black ? .white : .black }
        return DeferredMoveHistory.board(shown, size: recorder.game.boardSize)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(ready ? "Capture ready to confirm" : "Finish the capture").font(.title2.bold())
                Spacer()
                Label("Clocks paused", systemImage: "pause.circle").foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Captured stones to remove").font(.headline)
                    RecordedBoard(recorder: recorder, orientation: orientation, allowsLiveSelection: false,
                        boardOverride: board, highlightedPoints: remaining.sorted(), highlightColor: .orange,
                        showsLastMoveMarker: false, onPoint: { _ in })
                        .frame(width: 520, height: 520)
                    Text(verification == .waitingForCamera ? "Last known capture position · waiting for live verification."
                         : remaining.isEmpty ? "The captured stones appear to be removed." : "Remove only the orange-ringed stones.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(plan.move.color.rawValue.capitalized) captures at \(coordinate(plan.point))").font(.title3.bold())
                    Text("Keep the capturing stone at \(coordinate(plan.point)) in place.")
                    if !remaining.isEmpty,verification != .waitingForCamera {
                        Text("Remove the remaining captured \(plan.move.color.opponent.rawValue) \(remaining.count == 1 ? "stone" : "stones") at \(remaining.sorted().map(coordinate).joined(separator: ", ")).")
                    }
                    Text(ready ? "The camera has verified the removal. Confirm to save the capturing move."
                         : verification.guidance(coordinate: coordinate))
                    Text("This saves one capturing move. Clock times stay unchanged; you decide when to resume.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("This was a different move…", action: onOtherMove).padding(.top, 12)
                }.frame(width: 300, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Confirm capture") {
                    error = recorder.confirmCaptureReview(plan.id)
                    if error == nil { onSaved() }
                }.buttonStyle(.borderedProminent).disabled(!ready)
            }
        }.padding(20).frame(minWidth: 882, minHeight: 670)
    }
}
